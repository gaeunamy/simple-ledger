import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

part 'main.g.dart'; 

// ============================================================================
// 1. 앱 진입점 및 로컬 데이터베이스(Hive) 초기화
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // 기존에 꼬여있는 데이터 파일이 있다면 삭제
  // await Hive.deleteBoxFromDisk('myCardsBox');
  // await Hive.deleteBoxFromDisk('expenseBox');
  // await Hive.deleteBoxFromDisk('settingsBox');

  Hive.registerAdapter(ExpenseAdapter());
  Hive.registerAdapter(CardDataAdapter());

  await Hive.openBox<CardData>('myCardsBox');
  await Hive.openBox<Expense>('expenseBox');
  await Hive.openBox('settingsBox');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.0), 
          ),
          child: child!,
        );
      },
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFE0E5EC), 
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const MultiCardScreen(),
    );
  }
}

// ============================================================================
// 2. 데이터 모델 (Hive DB 스토리지 엔티티)
// ============================================================================

// [지출 내역 모델] - 이제 특정 카드에 종속되지 않고 독립적으로 저장됨
@HiveType(typeId: 0)
class Expense extends HiveObject { // HiveObject 상속으로 개별 삭제 용이
  @HiveField(0)
  final int amount;
  
  @HiveField(1)
  final DateTime date;

  @HiveField(2)
  final int? installmentMonths; 

  @HiveField(3)
  final bool isInstallment; 

  @HiveField(4)
  String? memo; 

  @HiveField(5)
  final String cardName; // [핵심] 어떤 카드의 지출인지 꼬리표(외래키) 달기

  Expense({
    required this.amount, 
    required this.date, 
    this.installmentMonths, 
    this.isInstallment = false,
    this.memo,
    required this.cardName,
  });

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String get formattedDate {
    return '${date.month}.${date.day} ${_weekdays[date.weekday - 1]}';
  }
}

// [카드 정보 모델] - 지출 내역을 품지 않고 가볍게 유지됨
@HiveType(typeId: 1)
class CardData extends HiveObject {
  @HiveField(0)
  String name; 
  
  @HiveField(1)
  final String logoPath;
  
  @HiveField(2)
  int total; 

  @HiveField(3)
  String? description; 

  CardData({
    required this.name, 
    required this.logoPath,
    required this.total,
    this.description,
  });
}

// ============================================================================
// 4. 메인 화면 (다중 카드 및 지출 관리 화면)
// ============================================================================
class MultiCardScreen extends StatefulWidget {
  const MultiCardScreen({super.key});

  @override
  State<MultiCardScreen> createState() => _MultiCardScreenState();
}

class _MultiCardScreenState extends State<MultiCardScreen> with WidgetsBindingObserver {

  late Box<CardData> cardBox;
  late Box<Expense> expenseBox;
  late Box settingsBox;
  late List<CardData> cards;

  final FocusNode _amountFocusNode = FocusNode();
  bool _isExpenseModalOpen = false;
  bool _isPerformanceMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cardBox = Hive.box<CardData>('myCardsBox');
    expenseBox = Hive.box<Expense>('expenseBox');
    settingsBox = Hive.box('settingsBox');

    _isPerformanceMode = settingsBox.get('isPerformanceMode', defaultValue: false);

    if (cardBox.isEmpty) {
      cardBox.addAll([
        CardData(name: '롯데카드', logoPath: 'assets/images/lotte.png', total: 300000),
        CardData(name: '국민카드', logoPath: 'assets/images/kb.png', total: 300000),
        CardData(name: '하나카드', logoPath: 'assets/images/hana.png', total: 300000),
        CardData(name: '신한카드', logoPath: 'assets/images/shinhan.png', total: 1000000),
        CardData(name: '삼성카드', logoPath: 'assets/images/samsung.png', total: 300000),
        CardData(name: '우리카드', logoPath: 'assets/images/woori.png', total: 300000),
      ]);
    }
    cards = cardBox.values.toList();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountFocusNode.dispose();
    super.dispose();
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  // [최적화] 특정 날짜 기준 특정 카드의 지출 총액을 계산하는 함수
  int _getCardSpent(String cardName, DateTime targetDate) {
    int sum = 0;
    // expenseBox에서 해당 카드의 지출 내역만 가져와 계산
    final targetExpenses = expenseBox.values.where((e) => e.cardName == cardName);
    
    for (var item in targetExpenses) {
      if (_isPerformanceMode) {
        if (item.isInstallment && item.installmentMonths == null) continue; 
        if (item.date.year == targetDate.year && item.date.month == targetDate.month) {
          sum += item.amount; 
        }
      } else {
        if (item.isInstallment) {
          if (item.installmentMonths == null) {
            if (item.date.year == targetDate.year && item.date.month == targetDate.month) {
              sum += item.amount;
            }
          } else {
            int monthsPassed = (targetDate.year - item.date.year) * 12 + (targetDate.month - item.date.month);
            if (monthsPassed >= 0 && monthsPassed < item.installmentMonths!) {
              sum += (item.amount ~/ item.installmentMonths!);
            }
          }
        } else {
          if (item.date.year == targetDate.year && item.date.month == targetDate.month) {
            sum += item.amount;
          }
        }
      }
    }
    return sum;
  }

  // ============================================================================
  // 모달 및 팝업창 관리
  // ============================================================================

  void _showEditCardDialog(BuildContext context, CardData card, StateSetter updateParentModal) {
    final TextEditingController budgetController = TextEditingController(text: card.total == -1 ? '' : card.total.toString());
    final TextEditingController descController = TextEditingController(text: card.description ?? '');
    bool isNoLimit = card.total == -1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFE0E5EC),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text('${card.name} 설정', style: const TextStyle(color: Color(0xFF2D3142), fontWeight: FontWeight.bold, fontSize: 18)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('예산 설정', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch, // 👈 핵심: 자식들 높이를 강제로 통일함
                        children: [
                          Expanded(
                            child: TextField(
                              controller: budgetController,
                              enabled: !isNoLimit,
                              keyboardType: TextInputType.number,
                              style: TextStyle(
                                fontSize: 16,
                                color: isNoLimit ? const Color(0xFF9098B1) : const Color(0xFF2D3142),
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                isDense: true, // 💡 중요: 내부 여백을 줄임
                                hintText: isNoLimit ? '한도 없는 카드' : '예산 금액 입력',
                                hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9098B1), fontWeight: FontWeight.bold),
                                filled: true,
                                fillColor: isNoLimit ? const Color(0xFFD1D9E6).withOpacity(0.5) : const Color(0xFFD1D9E6),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), // 💡 10에서 12로 변경하여 세로 중앙을 맞춤
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                isNoLimit = !isNoLimit;
                                if (isNoLimit) budgetController.clear();
                              });
                            },
                            child: Container(
                              // height: 38, // 💡 height를 제거하세요! 
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              decoration: isNoLimit
                                  ? BoxDecoration(
                                      color: const Color(0xFFE0E5EC),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3),
                                        BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.4), offset: const Offset(2, 2), blurRadius: 3),
                                      ],
                                    )
                                  : BoxDecoration(
                                      color: const Color(0xFFD1D9E6),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                              child: Text(
                                '한도 없음',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isNoLimit ? const Color(0xFF2F60FF) : const Color(0xFF9098B1)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('카드 메모', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: '예: 관리비, 통신비, 정수기',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9098B1),
                          fontWeight: FontWeight.bold,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFD1D9E6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), 
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Color(0xFF9098B1)))),
                TextButton(
                  onPressed: () {
                    setState(() {
                      card.total = isNoLimit ? -1 : (int.tryParse(budgetController.text.replaceAll(',', '')) ?? 0);
                      card.description = descController.text.trim();
                      card.save(); // HiveObject의 save 활용
                    });
                    updateParentModal(() {});
                    Navigator.pop(context);
                  },
                  child: const Text('확인', style: TextStyle(color: Color(0xFF2F60FF), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showExpenseMemoDialog(BuildContext context, CardData card, Expense expense, StateSetter updateParentModal) {
    final TextEditingController amountController = TextEditingController(text: expense.amount.toString());
    final TextEditingController memoController = TextEditingController(text: expense.memo ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFE0E5EC),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('지출 수정', style: TextStyle(color: Color(0xFF2D3142), fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView( 
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                const Text('소비 금액', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: '금액 입력',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF9098B1),
                      fontWeight: FontWeight.bold,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFD1D9E6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), 
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
                  ),
                ),
                const SizedBox(height: 24),
                const Text('지출 메모', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: memoController,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: '예: 커피, 식비 등',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF9098B1),
                      fontWeight: FontWeight.bold,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFD1D9E6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), 
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Color(0xFF9098B1)))),
            TextButton(
              onPressed: () {
                setState(() {
                  final parsedAmount = int.tryParse(amountController.text.replaceAll(',', ''));
                  if (parsedAmount != null && parsedAmount > 0) {
                    // [최적화] 새로운 객체를 넣는 대신 기존 객체의 값만 업데이트 후 저장
                    expenseBox.put(expense.key, Expense(
                      amount: parsedAmount,
                      date: expense.date,
                      installmentMonths: expense.installmentMonths,
                      isInstallment: expense.isInstallment,
                      memo: memoController.text.trim(),
                      cardName: expense.cardName,
                    ));
                    updateParentModal(() {});
                    Navigator.pop(context);
                  }
                });
              },
              child: const Text('확인', style: TextStyle(color: Color(0xFF2F60FF), fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showAddExpenseModal(BuildContext context, {int initialCardIndex = 0}) {
    _isExpenseModalOpen = true;
    int selectedCardIndex = initialCardIndex;
    bool isExpanded = initialCardIndex >= 4; 
    bool isInstallmentActive = false; 
    bool showInstallmentPicker = false; 
    int? selectedInstallment; 
    bool showCalendar = false;
    DateTime selectedDate = DateTime.now();
    DateTime currentMonthView = DateTime(selectedDate.year, selectedDate.month, 1);
    final TextEditingController amountController = TextEditingController();
    final LayerLink _installmentLayerLink = LayerLink();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFFE0E5EC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(999)))),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('지출 내역 추가', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                            Builder(
                              builder: (context) {
                                final isToday = selectedDate.year == DateTime.now().year && selectedDate.month == DateTime.now().month && selectedDate.day == DateTime.now().day;
                                return GestureDetector(
                                  onTap: () {
                                    FocusScope.of(context).unfocus(); 
                                    setModalState(() {
                                      showCalendar = !showCalendar;
                                      if (showCalendar) currentMonthView = DateTime(selectedDate.year, selectedDate.month, 1);
                                    });
                                  },
                                  child: Container(
                                    height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(12),
                                      boxShadow: isToday ? [const BoxShadow(color: Colors.white, offset: Offset(2, 2), blurRadius: 4), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(-2, -2), blurRadius: 4)] : [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4)],
                                    ),
                                    child: Text(isToday ? '오늘' : '${selectedDate.month}.${selectedDate.day}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isToday ? const Color(0xFF9098B1) : const Color(0xFF2F60FF))),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),

                        if (showCalendar) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E5EC), 
                              borderRadius: BorderRadius.circular(16), 
                              boxShadow: [
                                BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.3), offset: const Offset(4, 4), blurRadius: 8), 
                                const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)
                              ]
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    GestureDetector(onTap: () => setModalState(() => currentMonthView = DateTime(currentMonthView.year, currentMonthView.month - 1, 1)), child: const Icon(Icons.chevron_left, color: Color(0xFF2D3142))),
                                    Text('${currentMonthView.year}년 ${currentMonthView.month}월', style: const TextStyle(color: Color(0xFF2D3142), fontWeight: FontWeight.bold, fontSize: 15)),
                                    GestureDetector(onTap: () => setModalState(() => currentMonthView = DateTime(currentMonthView.year, currentMonthView.month + 1, 1)), child: const Icon(Icons.chevron_right, color: Color(0xFF2D3142))),
                                  ],
                                ),
                                // 💡 위쪽 간격들 원상복구 (16, 12)
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: const [Text('일', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)), Text('월', style: TextStyle(color: Color(0xFF9098B1), fontSize: 12)), Text('화', style: TextStyle(color: Color(0xFF9098B1), fontSize: 12)), Text('수', style: TextStyle(color: Color(0xFF9098B1), fontSize: 12)), Text('목', style: TextStyle(color: Color(0xFF9098B1), fontSize: 12)), Text('금', style: TextStyle(color: Color(0xFF9098B1), fontSize: 12)), Text('토', style: TextStyle(color: Color(0xFF2F60FF), fontSize: 12, fontWeight: FontWeight.bold))],
                                ),
                                const SizedBox(height: 12),
                                Builder(
                                  builder: (context) {
                                    final daysInMonth = DateTime(currentMonthView.year, currentMonthView.month + 1, 0).day;
                                    final firstWeekday = DateTime(currentMonthView.year, currentMonthView.month, 1).weekday; 
                                    int blankSpaces = firstWeekday == 7 ? 0 : firstWeekday;

                                    return GridView.builder(
                                      shrinkWrap: true, 
                                      physics: const NeverScrollableScrollPhysics(),
                                      padding: EdgeInsets.zero,
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 7, 
                                        mainAxisSpacing: 2,     
                                        crossAxisSpacing: 8,
                                        childAspectRatio: 1.3,
                                      ),
                                      itemCount: blankSpaces + daysInMonth,
                                      itemBuilder: (context, index) {
                                        if (index < blankSpaces) return const SizedBox.shrink();
                                        final day = index - blankSpaces + 1;
                                        final isSelected = currentMonthView.year == selectedDate.year && currentMonthView.month == selectedDate.month && day == selectedDate.day;

                                        return GestureDetector(
                                          onTap: () => setModalState(() { selectedDate = DateTime(currentMonthView.year, currentMonthView.month, day); showCalendar = false; }),
                                          child: Center(
                                            child: Container(
                                              width: 30, height: 30, 
                                              alignment: Alignment.center,
                                              decoration: isSelected 
                                                ? BoxDecoration(color: const Color(0xFFE0E5EC), shape: BoxShape.circle, boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4)]) 
                                                : const BoxDecoration(shape: BoxShape.circle, color: Colors.transparent),
                                              child: Text('$day', style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: isSelected ? const Color(0xFF2F60FF) : const Color(0xFF2D3142))),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  }
                                ),
                              ],
                            ),
                          ),
                        ],                  

                        const SizedBox(height: 24),
                        
                        Container(
                          height: 50, padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: const Color(0xFFD1D9E6), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              ...List.generate(isExpanded ? cards.length : 4, (index) {
                                final isSelected = selectedCardIndex == index;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => setModalState(() => selectedCardIndex = index),
                                    child: Container(
                                      decoration: isSelected ? BoxDecoration(color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(12), boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.4), offset: const Offset(2, 2), blurRadius: 3)]) : const BoxDecoration(color: Colors.transparent),
                                      alignment: Alignment.center,
                                      child: Text(cards[index].name.substring(0, 2), style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: isSelected ? const Color(0xFF2F60FF) : const Color(0xFF9098B1))),
                                    ),
                                  ),
                                );
                              }),
                              if (!isExpanded)
                                Expanded(child: GestureDetector(onTap: () => setModalState(() => isExpanded = true), child: Container(decoration: const BoxDecoration(color: Colors.transparent), alignment: Alignment.center, child: const Text('+', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF9098B1)))))),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () => setModalState(() {
                                if (isInstallmentActive) { isInstallmentActive = false; selectedInstallment = null; showInstallmentPicker = false; } else { isInstallmentActive = true; }
                              }),
                             child: Container(
                              width: 60, 
                              height: 38,
                              margin: const EdgeInsets.only(left: 6),
                              alignment: Alignment.center,
                              decoration: isInstallmentActive 
                                  ? BoxDecoration(
                                      color: const Color(0xFFE0E5EC), 
                                      borderRadius: BorderRadius.circular(12), 
                                      boxShadow: [
                                        const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3), 
                                        BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.4), offset: const Offset(2, 2), blurRadius: 3)
                                      ]
                                    ) 
                                  : BoxDecoration(
                                      color: const Color(0xFFD1D9E6), 
                                      borderRadius: BorderRadius.circular(12)
                                    ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown, 
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4), 
                                  child: Text(
                                    '할부', 
                                    style: TextStyle(
                                      fontSize: 14, 
                                      fontWeight: FontWeight.bold, 
                                      color: isInstallmentActive ? const Color(0xFF2F60FF) : const Color(0xFF9098B1)
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            ),
                            
                            if (isInstallmentActive) ...[
                              const SizedBox(width: 10),
                              CompositedTransformTarget(
                                link: _installmentLayerLink,
                                child: GestureDetector(
                                  onTap: () => setModalState(() => showInstallmentPicker = !showInstallmentPicker),
                                  child: Container(
                                    width: 80, height: 38, alignment: Alignment.center,
                                  decoration: selectedInstallment != null ? BoxDecoration(color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(12), boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.4), offset: const Offset(2, 2), blurRadius: 3)]) : BoxDecoration(color: const Color(0xFFD1D9E6), borderRadius: BorderRadius.circular(12)),
                                  child: Text(selectedInstallment != null ? '$selectedInstallment개월' : '개월', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: selectedInstallment != null ? const Color(0xFF2F60FF) : const Color(0xFF9098B1))),
                                  ),
                                ),
                              ),
                            ],
                            
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: amountController, focusNode: _amountFocusNode, keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  hintText: '소비 금액', hintStyle: TextStyle(fontSize: 16, color: Color(0xFF9098B1), fontWeight: FontWeight.w600),
                                  isDense: true, contentPadding: EdgeInsets.only(bottom: 6),
                                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD1D9E6), width: 1)),
                                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2F60FF), width: 1)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('원', style: TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold)),
                          ],
                        ),
                        
                        const SizedBox(height: 40),
                        
                        GestureDetector(
                          onTap: () {
                            if (amountController.text.isNotEmpty) {
                              int amount = int.tryParse(amountController.text.replaceAll(',', '')) ?? 0;
                              if (amount > 0) {
                                setState(() {
                                  // [최적화] 거대한 리스트를 덮어쓰는 대신, 독립적인 box에 데이터 하나만 쏙 저장
                                  expenseBox.add(
                                    Expense(
                                      amount: amount, 
                                      date: selectedDate,
                                      installmentMonths: selectedInstallment,
                                      isInstallment: isInstallmentActive,
                                      cardName: cards[selectedCardIndex].name, // 외래키로 카드 이름 저장
                                    )
                                  );
                                });
                                Navigator.pop(context); 
                              }
                            }
                          },
                          child: Container(
                            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(colors: [Color(0xFF4A7DFF), Color(0xFF1A4BFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                              boxShadow: [BoxShadow(color: const Color(0xFF2F60FF).withOpacity(0.4), offset: const Offset(4, 6), blurRadius: 12), const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)],
                            ),
                            alignment: Alignment.center,
                            child: const Text('확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),

                    if (showInstallmentPicker)
                      Positioned(
                        child: CompositedTransformFollower(
                          link: _installmentLayerLink,
                          targetAnchor: Alignment.topCenter,     // 타겟(버튼)의 상단 중앙을 기준으로
                          followerAnchor: Alignment.bottomCenter, // 팔로워(팝업)의 하단 중앙을 맞춤
                          offset: const Offset(0, -8),            // 위로 8픽셀 여백 주기
                          child: Container(
                            height: 115, width: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1D9E6), 
                              borderRadius: BorderRadius.circular(12), 
                              boxShadow: [
                                BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(4, 4), blurRadius: 8), 
                                const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)
                              ]
                            ),
                          child: ListView.builder(
                            itemCount: 12, padding: const EdgeInsets.symmetric(vertical: 4),
                            itemBuilder: (context, index) {
                              final month = index + 1;
                              final isMonthSelected = selectedInstallment == month;
                              return GestureDetector(
                                onTap: () => setModalState(() { selectedInstallment = month; showInstallmentPicker = false; }),
                                child: Container(
                                  height: 32, alignment: Alignment.center, margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                                  decoration: BoxDecoration(color: isMonthSelected ? const Color(0xFF2F60FF) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                                  child: Text('$month개월', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isMonthSelected ? Colors.white : const Color(0xFF2D3142))),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _isExpenseModalOpen = false;
    });
  }

  void _showCardDetailModal(BuildContext context, CardData card, {DateTime? targetDate}) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7, padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: Color(0xFFE0E5EC), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(999)))),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(card.name, style: const TextStyle(color: Color(0xFF2D3142), fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          GestureDetector(onTap: () => _showEditCardDialog(context, card, setModalState), child: const Icon(Icons.edit, size: 16, color: Color(0xFF9098B1))),
                        ],
                      ),
                      GestureDetector(
                        onTap: () { Navigator.pop(context); _showAddExpenseModal(context, initialCardIndex: cards.indexOf(card)); },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(16), boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4)]),
                          child: const Text('+', style: TextStyle(fontSize: 18, color: Color(0xFF2D3142), fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  if (card.description != null && card.description!.isNotEmpty) ...[
                    const SizedBox(height: 0.5), Text(card.description!, style: const TextStyle(color: Color(0xFF9098B1), fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  Builder(
                    builder: (context) {
                      final target = targetDate ?? DateTime.now();
                      
                      // [최적화] 해당 카드의 지출만 필터링해서 가져옴
                      final cardExpenses = expenseBox.values.where((e) => e.cardName == card.name).toList();
                      
                      // 시간순 정렬 (최신순)
                      cardExpenses.sort((a, b) => b.date.compareTo(a.date));

                      final filteredExpenses = cardExpenses.where((expense) {
                        if (_isPerformanceMode) {
                          if (expense.date.year == target.year && expense.date.month == target.month) {
                            return !(expense.isInstallment && expense.installmentMonths == null);
                          }
                          return false;
                        } else {
                          if (expense.isInstallment && expense.installmentMonths != null) {
                            int monthsPassed = (target.year - expense.date.year) * 12 + (target.month - expense.date.month);
                            return monthsPassed >= 0 && monthsPassed < expense.installmentMonths!;
                          } else {
                            return expense.date.year == target.year && expense.date.month == target.month;
                          }
                        }
                      }).toList();

                      return Expanded(
                        child: filteredExpenses.isEmpty
                            ? const Center(child: Text('이번 달 지출 내역이 없습니다.', style: TextStyle(color: Color(0xFF9098B1), fontSize: 16)))
                            : ListView.builder(
                                itemCount: filteredExpenses.length,
                                itemBuilder: (_, index) {
                                  final expense = filteredExpenses[index];
                                  int displayedAmount = expense.amount;
                                  if (!_isPerformanceMode && expense.isInstallment && expense.installmentMonths != null) {
                                    displayedAmount = expense.amount ~/ expense.installmentMonths!;
                                  }
                                  Color circleColor = expense.isInstallment && expense.installmentMonths == null ? const Color(0xFF00BFA5) : const Color(0xFF2F60FF);

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center, 
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => _showExpenseMemoDialog(context, card, expense, setModalState),
                                            behavior: HitTestBehavior.opaque, 
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                SizedBox(width: 60, child: Text(expense.formattedDate, style: const TextStyle(color: Color(0xFF9098B1), fontSize: 14))),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center,
                                                        children: [
                                                          if (expense.isInstallment) ...[Container(width: 6, height: 6, decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle)), const SizedBox(width: 6)],
                                                          Text('${_formatCurrency(displayedAmount)}원', style: const TextStyle(color: Color(0xFF2D3142), fontSize: 16, fontWeight: FontWeight.bold)),
                                                          if (_isPerformanceMode && expense.isInstallment && expense.installmentMonths != null) ...[const SizedBox(width: 4), Text('/${expense.installmentMonths}개월', style: const TextStyle(color: Color(0xFF9098B1), fontSize: 12))],
                                                        ],
                                                      ),
                                                      if (expense.memo != null && expense.memo!.isNotEmpty) ...[const SizedBox(height: 2), Text(expense.memo!, style: const TextStyle(color: Color(0xFF9098B1), fontSize: 12), textAlign: TextAlign.center)],
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              // [최적화] 지출 내역 하나를 데이터베이스에서 완전 삭제 (HiveObject 덕분에 편함)
                                              expense.delete();
                                            });
                                            setModalState(() {}); 
                                          },
                                          child: Container(padding: const EdgeInsets.all(8), color: Colors.transparent, child: const Icon(Icons.close, color: Colors.redAccent, size: 20)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      );
                    }
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSummaryModal(BuildContext context) {
    DateTime selectedSummaryDate = DateTime.now();

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // [최적화] 미리 캐시 로직을 통해 가져온 값 사용
            final totalSpent = cards.fold<int>(0, (sum, card) => sum + _getCardSpent(card.name, selectedSummaryDate));
            final totalRemaining = cards.fold<int>(0, (sum, card) {
              if (card.total == -1) return sum;
              return sum + (card.total - _getCardSpent(card.name, selectedSummaryDate));
            });

            return Container(
              height: MediaQuery.of(context).size.height * 0.8, padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: Color(0xFFE0E5EC), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(999)))),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Text('요약', style: TextStyle(color: Color(0xFF2D3142), fontSize: 20, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => setModalState(() => selectedSummaryDate = DateTime(selectedSummaryDate.year, selectedSummaryDate.month - 1)),
                                child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(8), boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 2), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 2)]), child: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF2D3142))),
                              ),
                              const SizedBox(width: 11),
                              SizedBox(width: 75, child: FittedBox(fit: BoxFit.scaleDown, child: Text('${selectedSummaryDate.year}년 ${selectedSummaryDate.month}월', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF2F60FF), fontSize: 14, fontWeight: FontWeight.bold)))),
                              const SizedBox(width: 11),
                              GestureDetector(
                                onTap: () => setModalState(() => selectedSummaryDate = DateTime(selectedSummaryDate.year, selectedSummaryDate.month + 1)),
                                child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(8), boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 2), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 2)]), child: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF2D3142))),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: _summaryCard('총 소비', '${_formatCurrency(totalSpent)}원', const Color(0xFF2D3142))),
                      const SizedBox(width: 16),
                      Expanded(child: _summaryCard('남은 예산', '${_formatCurrency(totalRemaining)}원', const Color(0xFF2D3142))),
                    ],
                  ),
                  const SizedBox(height: 40),
                  const Text('카드별 소비', style: TextStyle(color: Color(0xFF9098B1), fontSize: 14)),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ReorderableListView.builder(
                      proxyDecorator: (Widget child, int index, Animation<double> animation) { return Material(type: MaterialType.transparency, child: child); },
                      itemCount: cards.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex -= 1;
                        setModalState(() { final item = cards.removeAt(oldIndex); cards.insert(newIndex, item); });
                        setState(() { for (int i = 0; i < cards.length; i++) { cardBox.putAt(i, cards[i]); } });
                      },
                      itemBuilder: (_, index) {
                        final card = cards[index];
                        final cardSpent = _getCardSpent(card.name, selectedSummaryDate); // [최적화]
                        final remain = card.total - cardSpent;

                        return Padding(
                          key: ValueKey(card.name), padding: const EdgeInsets.only(bottom: 20),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque, 
                            onTap: () { Navigator.pop(context); _showCardDetailModal(context, card, targetDate: selectedSummaryDate); },
                            child: Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(left: 4), width: 24, height: 24,
                                  decoration: BoxDecoration(color: const Color(0xFFE0E5EC), shape: BoxShape.circle, boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 3)]),
                                  alignment: Alignment.center,
                                  child: Transform.scale(
                                    scale: card.name == '국민카드' ? 1.8 : card.name == '삼성카드' ? 1.3 : 1.0, 
                                    child: Image.asset(card.logoPath, width: 16, height: 16, fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => const Icon(Icons.credit_card, size: 12, color: Color(0xFF2F60FF))),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(card.name, style: const TextStyle(color: Color(0xFF9098B1), fontSize: 12)),
                                      Text('${_formatCurrency(cardSpent)}원', style: const TextStyle(color: Color(0xFF2D3142), fontSize: 16, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                if (card.total != -1) Text(remain >= 0 ? '${_formatCurrency(remain)}원' : '-${_formatCurrency(remain.abs())}원', style: TextStyle(color: remain >= 0 ? const Color(0xFF2F60FF) : Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentMonth = now.month;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final progressPercent = now.day / daysInMonth;
    final mainScreenCards = cards.take(4).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text('$currentMonth월 플랜', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _showSummaryModal(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                    decoration: BoxDecoration(color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(12), boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4)]),
                    child: const Text('요약', style: TextStyle(fontSize: 12, color: Color(0xFF2D3142), fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () {
                setState(() { _isPerformanceMode = !_isPerformanceMode; settingsBox.put('isPerformanceMode', _isPerformanceMode); });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(12),
                  boxShadow: _isPerformanceMode ? [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4)] : [const BoxShadow(color: Colors.white, offset: Offset(2, 2), blurRadius: 4), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(-2, -2), blurRadius: 4)],
                ),
                child: Text(_isPerformanceMode ? '실적 보기' : '청구액 보기', style: TextStyle(fontSize: 12, color: _isPerformanceMode ? const Color(0xFF2F60FF) : const Color(0xFF9098B1), fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 5), 
              _buildProgressSection(progressPercent, now.day, currentMonth),
              const SizedBox(height: 55), 
              GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 18, mainAxisSpacing: 22, childAspectRatio: 0.85),
                itemCount: mainScreenCards.length,
                itemBuilder: (context, index) {
                  final card = mainScreenCards[index];
                  // [최적화] 부모 위젯에서 한 번만 연산해서 넘겨줌
                  final spentAmount = _getCardSpent(card.name, now);
                  
                  return GestureDetector(
                    onTap: () => _showCardDetailModal(context, card), 
                    child: BudgetCardWidget(data: card, isPerformanceMode: _isPerformanceMode, spentAmount: spentAmount),
                  );
                }
              ),
              const SizedBox(height: 55),
              Center(
                child: GestureDetector(
                  onTap: () => _showAddExpenseModal(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: const LinearGradient(colors: [Color(0xFF4A7DFF), Color(0xFF1A4BFF)], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: const Color(0xFF2F60FF).withOpacity(0.4), offset: const Offset(4, 6), blurRadius: 12), const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)]),
                    child: const Text('지출 내역 추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String value, Color valueColor, {String? subText}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(24), boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-6, -6), blurRadius: 12), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(6, 6), blurRadius: 12)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, color: Color(0xFF9098B1), fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor)),
                if (subText != null) ...[const SizedBox(width: 8), Text(subText, style: const TextStyle(fontSize: 14, color: Color(0xFF9098B1), fontWeight: FontWeight.w600))],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(double progress, int currentDay, int currentMonth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40), 
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final fillWidth = maxWidth * progress;
            const tooltipWidth = 48.0;
            double tooltipLeft = fillWidth - (tooltipWidth / 2);
            if (tooltipLeft < 0) tooltipLeft = 0;
            if (tooltipLeft > maxWidth - tooltipWidth) tooltipLeft = maxWidth - tooltipWidth;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(height: 12, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(6), boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(2, 2), blurRadius: 4), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(-2, -2), blurRadius: 4)])),
                Container(height: 12, width: fillWidth, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2F60FF), Color(0xFF00C6FF)], begin: Alignment.centerLeft, end: Alignment.centerRight), borderRadius: BorderRadius.circular(6))),
                Positioned(
                  left: tooltipLeft, top: -38,
                  child: SizedBox(
                    width: tooltipWidth, height: 34,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        Positioned(bottom: 2, child: Transform.rotate(angle: 3.141592 / 4, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFE0E5EC), boxShadow: [BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 2)])))),
                        Container(
                          width: tooltipWidth, height: 26, alignment: Alignment.center,
                          decoration: BoxDecoration(color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(6), boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 3)]),
                          child: Text('$currentDay일', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ============================================================================
// 6. 커스텀 위젯: 개별 카드 
// ============================================================================
// [최적화] 매번 계산하지 않고 부모에게서 spentAmount를 받아와서 그리기만 하는 StatelessWidget으로 변경
class BudgetCardWidget extends StatelessWidget {
  final CardData data;
  final bool isPerformanceMode;
  final int spentAmount; 

  const BudgetCardWidget({super.key, required this.data, required this.isPerformanceMode, required this.spentAmount});

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  bool isOverBudget() {
    if (data.total == -1) return false;
    return spentAmount > data.total;
  }
      
  double getSpentPercent() {
    if (data.total == -1) return 0.0;
    if (data.total == 0) return spentAmount > 0 ? 1.0 : 0.0;
    return (spentAmount / data.total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE0E5EC), borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.6), offset: const Offset(8, 8), blurRadius: 16), const BoxShadow(color: Colors.white, offset: Offset(-8, -8), blurRadius: 16)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24, height: 24, clipBehavior: Clip.antiAlias, alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFE0E5EC), shape: BoxShape.circle, boxShadow: [const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3), BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 3)]),
                  child: Transform.scale(
                    scale: data.name == '국민카드' ? 1.8 : data.name == '삼성카드' ? 1.3 : 1.0,
                    child: Image.asset(data.logoPath, width: 16, height: 16, fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => const Icon(Icons.credit_card, size: 14, color: Color(0xFF2F60FF))),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(data.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)))),
              ],
            ),
            const SizedBox(height: 15),
            Expanded(child: Center(child: _buildDonutChart())),
          ],
        ),
      ),
    );
  }

  Widget _buildDonutChart() {
    final spentPercent = getSpentPercent();
    final isOver = isOverBudget();
    final activeColor = isPerformanceMode ? const Color(0xFF2F60FF) : const Color(0xFF00BFA5);

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE0E5EC), boxShadow: [BoxShadow(color: Color(0xFFA3B1C6), offset: Offset(4, 4), blurRadius: 8), BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)]),
          ),
          SizedBox(
            width: 100, height: 100,
            child: CircularProgressIndicator(value: data.total == -1 ? 0.0 : spentPercent, strokeWidth: 7, valueColor: AlwaysStoppedAnimation<Color>(activeColor), strokeCap: StrokeCap.round),
          ),
          if (isOver && data.total != -1)
            SizedBox(
              width: 100, height: 100,
              child: CircularProgressIndicator(value: data.total == 0 ? 1.0 : ((spentAmount - data.total) / data.total).clamp(0.0, 1.0), strokeWidth: 7, valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF453A)), strokeCap: StrokeCap.round),
            ),
          SizedBox(
            width: 90,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_formatCurrency(spentAmount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
            ),
          ),
        ],
      ),
    );
  }
}