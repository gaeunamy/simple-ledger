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

  Hive.registerAdapter(ExpenseAdapter());
  Hive.registerAdapter(CardDataAdapter());

  await Hive.openBox<CardData>('myCardsBox');
  await Hive.openBox('settingsBox');

  runApp(const MyApp());
}

// ============================================================================
// 2. 앱 인프라 설정 (루트 위젯 및 글로벌 테마)
// ============================================================================
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
          backgroundColor: Color(0xFFE0E5EC),
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF2D3142)),
          titleTextStyle: TextStyle(color: Color(0xFF2D3142), fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      home: const MultiCardScreen(),
    );
  }
}

// ============================================================================
// 3. 데이터 모델 클래스 (Hive Box 연동용 고유 데코레이터 포함)
// ============================================================================
@HiveType(typeId: 0)
class Expense extends HiveObject {
  @HiveField(0)
  final int amount;
  @HiveField(1)
  final DateTime date;
  @HiveField(2)
  final int? installmentMonths;
  @HiveField(3)
  final bool isInstallment;
  @HiveField(4)
  final String? memo;

  Expense({
    required this.amount,
    required this.date,
    this.installmentMonths,
    this.isInstallment = false,
    this.memo,
  });

  String get formattedDate => '${date.month}.${date.day.toString().padLeft(2, '0')}';
}

@HiveType(typeId: 1)
class CardData extends HiveObject {
  @HiveField(0)
  final String name;
  @HiveField(1)
  final int total; // -1 이면 실적제외(단순합산용)카드
  @HiveField(2)
  final List<Expense> expenses;

  CardData({
    required this.name,
    required this.total,
    required this.expenses,
  });

  int getSpent(bool isPerformanceMode, {DateTime? targetDate}) {
    final target = targetDate ?? DateTime.now();
    int spent = 0;
    for (var expense in expenses) {
      if (isPerformanceMode) {
        if (expense.isInstallment && expense.installmentMonths == null) {
          continue;
        }
        if (expense.date.year == target.year && expense.date.month == target.month) {
          spent += expense.amount;
        }
      } else {
        if (expense.isInstallment) {
          if (expense.installmentMonths == null) {
            if (expense.date.year == target.year && expense.date.month == target.month) {
              spent += expense.amount;
            }
          } else {
            int monthsPassed = (target.year - expense.date.year) * 12 + (target.month - expense.date.month);
            if (monthsPassed >= 0 && monthsPassed < expense.installmentMonths!) {
              spent += expense.amount ~/ expense.installmentMonths!;
            }
          }
        } else {
          if (expense.date.year == target.year && expense.date.month == target.month) {
            spent += expense.amount;
          }
        }
      }
    }
    return spent;
  }
}

// ============================================================================
// 4. 상태 관리 화면 컴포넌트
// ============================================================================
class MultiCardScreen extends StatefulWidget {
  const MultiCardScreen({super.key});

  @override
  State<MultiCardScreen> createState() => _MultiCardScreenState();
}

class _MultiCardScreenState extends State<MultiCardScreen> with WidgetsBindingObserver {
  late Box<CardData> cardBox;
  late Box settingsBox;
  List<CardData> cards = [];
  bool _isPerformanceMode = false;
  bool _isExpenseModalOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cardBox = Hive.box<CardData>('myCardsBox');
    settingsBox = Hive.box('settingsBox');

    _isPerformanceMode = settingsBox.get('isPerformanceMode', defaultValue: false);

    if (cardBox.isEmpty) {
      cardBox.addAll([
        CardData(name: '신한카드', total: 300000, expenses: []),
        CardData(name: '국민카드', total: 300000, expenses: []),
        CardData(name: '삼성카드', total: -1, expenses: []),
        CardData(name: '현대카드', total: 500000, expenses: []),
      ]);
    }
    cards = cardBox.values.toList();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isExpenseModalOpen) {
      setState(() {});
    }
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  // [개별 카드 이름 및 목표 실적 수정 팝업 창]
  void _showEditCardDialog(BuildContext context, CardData card, StateSetter updateParentModal) {
    final nameController = TextEditingController(text: card.name);
    final totalController = TextEditingController(text: card.total == -1 ? '' : card.total.toString());
    bool isPerformanceExcluded = card.total == -1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFE0E5EC),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('카드 수정', style: TextStyle(color: Color(0xFF2D3142), fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('카드 이름', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFD1D9E6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('실적 제외 카드', style: TextStyle(color: Color(0xFF2D3142), fontSize: 14, fontWeight: FontWeight.bold)),
                      Switch(
                        value: isPerformanceExcluded,
                        activeColor: const Color(0xFF2F60FF),
                        onChanged: (val) {
                          setDialogState(() {
                            isPerformanceExcluded = val;
                            if (isPerformanceExcluded) {
                              totalController.clear();
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  if (!isPerformanceExcluded) ...[
                    const SizedBox(height: 8),
                    const Text('목표 실적 (원)', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: totalController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFD1D9E6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소', style: TextStyle(color: Color(0xFF9098B1))),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      final newName = nameController.text.trim();
                      final int newTotal = isPerformanceExcluded ? -1 : (int.tryParse(totalController.text) ?? 0);
                      
                      final updatedCard = CardData(
                        name: newName.isNotEmpty ? newName : card.name,
                        total: newTotal,
                        expenses: card.expenses,
                      );
                      
                      int idx = cards.indexOf(card);
                      cards[idx] = updatedCard;
                      cardBox.putAt(idx, updatedCard);
                      updateParentModal(() {});
                      Navigator.pop(context);
                    });
                  },
                  child: const Text('저장', style: TextStyle(color: Color(0xFF2F60FF), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // [개별 지출 정보 및 설명 메모 수정 다이얼로그]
  void _showExpenseMemoDialog(BuildContext context, CardData card, Expense expense, StateSetter updateParentModal) {
    final amountController = TextEditingController(text: _formatCurrency(expense.amount));
    final memoController = TextEditingController(text: expense.memo ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFE0E5EC),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('지출 내역 수정', style: TextStyle(color: Color(0xFF2D3142), fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('지출 금액 (원)', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFD1D9E6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('지출 설명 (메모)', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: memoController,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: '예: 커피, 식비 등',
                    hintStyle: const TextStyle(color: Color(0xFF9098B1), fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFFD1D9E6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: Color(0xFF9098B1))),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  final input = amountController.text.replaceAll(',', '');
                  final parsedAmount = int.tryParse(input);
                  if (parsedAmount != null && parsedAmount > 0) {
                    final updatedExpense = Expense(
                      amount: parsedAmount,
                      date: expense.date,
                      installmentMonths: expense.installmentMonths,
                      isInstallment: expense.isInstallment,
                      memo: memoController.text.trim(),
                    );
                    int expenseIdx = card.expenses.indexOf(expense);
                    card.expenses[expenseIdx] = updatedExpense;
                    int cardIdx = cards.indexOf(card);
                    cardBox.putAt(cardIdx, card);
                    updateParentModal(() {});
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('올바른 금액을 입력해주세요.')),
                    );
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

  // [새로운 지출 내역 추가 바텀 시트 (할부 및 인라인 달력 포함)]
  void _showAddExpenseModal(BuildContext context, {int initialCardIndex = 0}) {
    _isExpenseModalOpen = true;
    int selectedCardIndex = initialCardIndex;
    DateTime selectedDate = DateTime.now();
    DateTime currentMonthView = DateTime(selectedDate.year, selectedDate.month, 1);
    bool showCalendar = false;
    bool isInstallmentActive = false;
    int? selectedInstallment;
    bool showInstallmentPicker = false;
    bool isExpanded = false;

    final amountController = TextEditingController();
    final _amountFocusNode = FocusNode();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
              ),
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
                        Center(
                          child: Container(
                            width: 48,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '지출 내역 추가',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                            ),
                            Builder(
                              builder: (context) {
                                final isToday = selectedDate.year == DateTime.now().year &&
                                    selectedDate.month == DateTime.now().month &&
                                    selectedDate.day == DateTime.now().day;
                                return GestureDetector(
                                  onTap: () {
                                    FocusScope.of(context).unfocus();
                                    setModalState(() {
                                      showCalendar = !showCalendar;
                                      if (showCalendar) {
                                        currentMonthView = DateTime(selectedDate.year, selectedDate.month, 1);
                                      }
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    height: 32,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0E5EC),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: isToday
                                          ? [
                                              const BoxShadow(color: Colors.white, offset: Offset(2, 2), blurRadius: 4),
                                              BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(-2, -2), blurRadius: 4),
                                            ]
                                          : [
                                              const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4),
                                              BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4),
                                            ],
                                    ),
                                    child: Text(
                                      isToday ? '오늘' : '${selectedDate.month}월 ${selectedDate.day}일',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isToday ? const Color(0xFF9098B1) : const Color(0xFF2F60FF),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        // [인라인 달력 영역]
                        if (showCalendar) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E5EC),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.3), offset: const Offset(4, 4), blurRadius: 8),
                                const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    GestureDetector(
                                      onTap: () => setModalState(() => currentMonthView = DateTime(currentMonthView.year, currentMonthView.month - 1, 1)),
                                      child: const Icon(Icons.chevron_left, color: Color(0xFF2D3142)),
                                    ),
                                    Text(
                                      '${currentMonthView.year}년 ${currentMonthView.month}월',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                                    ),
                                    GestureDetector(
                                      onTap: () => setModalState(() => currentMonthView = DateTime(currentMonthView.year, currentMonthView.month + 1, 1)),
                                      child: const Icon(Icons.chevron_right, color: Color(0xFF2D3142)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Builder(builder: (context) {
                                  final daysInMonth = DateTime(currentMonthView.year, currentMonthView.month + 1, 0).day;
                                  final firstWeekday = DateTime(currentMonthView.year, currentMonthView.month, 1).weekday;
                                  int blankSpaces = firstWeekday == 7 ? 0 : firstWeekday;

                                  return GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 7,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                    ),
                                    itemCount: blankSpaces + daysInMonth,
                                    itemBuilder: (context, index) {
                                      if (index < blankSpaces) return const SizedBox.shrink();

                                      final day = index - blankSpaces + 1;
                                      final isSelected = currentMonthView.year == selectedDate.year &&
                                          currentMonthView.month == selectedDate.month &&
                                          day == selectedDate.day;
                                      return GestureDetector(
                                        onTap: () {
                                          setModalState(() {
                                            selectedDate = DateTime(currentMonthView.year, currentMonthView.month, day);
                                            showCalendar = false;
                                          });
                                        },
                                        child: Container(
                                          alignment: Alignment.center,
                                          decoration: isSelected
                                              ? BoxDecoration(
                                                  color: const Color(0xFFE0E5EC),
                                                  shape: BoxShape.circle,
                                                  boxShadow: [
                                                    const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4),
                                                    BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4),
                                                  ],
                                                )
                                              : const BoxDecoration(shape: BoxShape.circle, color: Colors.transparent),
                                          child: Text(
                                            '$day',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                              color: isSelected ? const Color(0xFF2F60FF) : const Color(0xFF2D3142),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Container(
                          height: 50,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1D9E6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              ...List.generate(isExpanded ? cards.length : 4, (index) {
                                final isSelected = selectedCardIndex == index;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => setModalState(() => selectedCardIndex = index),
                                    child: Container(
                                      decoration: isSelected
                                          ? BoxDecoration(
                                              color: const Color(0xFFE0E5EC),
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3),
                                                BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.4), offset: const Offset(2, 2), blurRadius: 3),
                                              ],
                                            )
                                          : const BoxDecoration(color: Colors.transparent),
                                      alignment: Alignment.center,
                                      child: Text(
                                        cards[index].name.substring(0, 2),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                          color: isSelected ? const Color(0xFF2F60FF) : const Color(0xFF9098B1),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              if (!isExpanded)
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setModalState(() => isExpanded = true),
                                    child: Container(
                                      decoration: const BoxDecoration(color: Colors.transparent),
                                      alignment: Alignment.center,
                                      child: const Text(
                                        '+',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF9098B1)),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  if (isInstallmentActive) {
                                    isInstallmentActive = false;
                                    selectedInstallment = null;
                                    showInstallmentPicker = false;
                                  } else {
                                    isInstallmentActive = true;
                                  }
                                });
                              },
                              child: Container(
                                width: 60,
                                height: 38,
                                margin: const EdgeInsets.only(left: 8),
                                alignment: Alignment.center,
                                decoration: isInstallmentActive
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
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      '할부',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isInstallmentActive ? const Color(0xFF2F60FF) : const Color(0xFF9098B1),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (isInstallmentActive) ...[
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    showInstallmentPicker = !showInstallmentPicker;
                                  });
                                },
                                child: Container(
                                  width: 80,
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: selectedInstallment != null
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
                                    selectedInstallment != null ? '$selectedInstallment개월' : '개월',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: selectedInstallment != null ? const Color(0xFF2F60FF) : const Color(0xFF9098B1),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: amountController,
                                focusNode: _amountFocusNode,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  hintText: '소비 금액',
                                  hintStyle: TextStyle(fontSize: 16, color: Color(0xFF9098B1), fontWeight: FontWeight.w600),
                                  isDense: true,
                                  contentPadding: EdgeInsets.only(bottom: 6),
                                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD1D9E6), width: 1)),
                                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2F60FF), width: 1)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '원',
                              style: TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        GestureDetector(
                          onTap: () {
                            if (amountController.text.isNotEmpty) {
                              int amount = int.tryParse(amountController.text.replaceAll(',', '')) ?? 0;
                              if (amount > 0) {
                                setState(() {
                                  cards[selectedCardIndex].expenses.insert(
                                    0,
                                    Expense(
                                      amount: amount,
                                      date: selectedDate,
                                      installmentMonths: selectedInstallment,
                                      isInstallment: isInstallmentActive,
                                    ),
                                  );
                                  cardBox.putAt(selectedCardIndex, cards[selectedCardIndex]);
                                });
                                Navigator.pop(context);
                              }
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF4A7DFF), Color(0xFF1A4BFF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2F60FF).withOpacity(0.4),
                                  offset: const Offset(0, 4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              '추가',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showInstallmentPicker)
                      Positioned(
                        left: 76,
                        bottom: 90,
                        child: Container(
                          width: 90,
                          height: 150,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E5EC),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(4, 4), blurRadius: 8),
                              const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
                            ],
                          ),
                          child: ListView.builder(
                            itemCount: 12,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemBuilder: (context, index) {
                              final month = index + 1;
                              final isMonthSelected = selectedInstallment == month;
                              return GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    selectedInstallment = month;
                                    showInstallmentPicker = false;
                                  });
                                },
                                child: Container(
                                  height: 32,
                                  alignment: Alignment.center,
                                  margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                                  decoration: BoxDecoration(
                                    color: isMonthSelected ? const Color(0xFF2F60FF) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$month개월',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isMonthSelected ? Colors.white : const Color(0xFF2D3142),
                                    ),
                                  ),
                                ),
                              );
                            },
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

  // [특정 카드의 전체 지출 상세 내역 바텀 시트]
  void _showCardDetailModal(BuildContext context, CardData card, {DateTime? targetDate}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFE0E5EC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            card.name,
                            style: const TextStyle(color: Color(0xFF2D3142), fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _showEditCardDialog(context, card, setModalState),
                            child: const Icon(Icons.edit, size: 16, color: Color(0xFF9098B1)),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _showAddExpenseModal(context, initialCardIndex: cards.indexOf(card));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E5EC),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4),
                              BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4),
                            ],
                          ),
                          child: const Text(
                            '지출 추가',
                            style: TextStyle(color: Color(0xFF2F60FF), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Builder(
                    builder: (context) {
                      final target = targetDate ?? DateTime.now();
                      final filteredExpenses = card.expenses.where((expense) {
                        if (_isPerformanceMode) {
                          if (expense.isInstallment && expense.installmentMonths == null) {
                            return false;
                          }
                          return expense.date.year == target.year && expense.date.month == target.month;
                        } else {
                          if (expense.isInstallment) {
                            if (expense.installmentMonths == null) {
                              return expense.date.year == target.year && expense.date.month == target.month;
                            }
                            int monthsPassed = (target.year - expense.date.year) * 12 + (target.month - expense.date.month);
                            return monthsPassed >= 0 && monthsPassed < expense.installmentMonths!;
                          } else {
                            return expense.date.year == target.year && expense.date.month == target.month;
                          }
                        }
                      }).toList();

                      return Expanded(
                        child: filteredExpenses.isEmpty
                            ? const Center(
                                child: Text(
                                  '이번 달 지출 내역이 없습니다.',
                                  style: TextStyle(color: Color(0xFF9098B1), fontSize: 16),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredExpenses.length,
                                itemBuilder: (_, index) {
                                  final expense = filteredExpenses[index];
                                  int displayedAmount = expense.amount;
                                  if (!_isPerformanceMode) {
                                    if (expense.isInstallment && expense.installmentMonths != null) {
                                      displayedAmount = expense.amount ~/ expense.installmentMonths!;
                                    }
                                  }
                                  Color circleColor = const Color(0xFF2F60FF);
                                  if (expense.isInstallment && expense.installmentMonths == null) {
                                    circleColor = const Color(0xFF00BFA5);
                                  }
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
                                                SizedBox(
                                                  width: 60,
                                                  child: Text(
                                                    expense.formattedDate,
                                                    style: const TextStyle(color: Color(0xFF9098B1), fontSize: 14),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    crossAxisAlignment: CrossAxisAlignment.center,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        crossAxisAlignment: CrossAxisAlignment.center,
                                                        children: [
                                                          if (expense.isInstallment) ...[
                                                            Container(
                                                              width: 6,
                                                              height: 6,
                                                              decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
                                                            ),
                                                            const SizedBox(width: 6),
                                                          ],
                                                          Text(
                                                            '${_formatCurrency(displayedAmount)}원',
                                                            style: const TextStyle(color: Color(0xFF2D3142), fontSize: 16, fontWeight: FontWeight.bold),
                                                          ),
                                                          if (_isPerformanceMode && expense.isInstallment && expense.installmentMonths != null) ...[
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              '/${expense.installmentMonths}개월',
                                                              style: const TextStyle(color: Color(0xFF9098B1), fontSize: 12, fontWeight: FontWeight.normal),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      if (expense.memo != null && expense.memo!.isNotEmpty) ...[
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          expense.memo!,
                                                          style: const TextStyle(color: Color(0xFF9098B1), fontSize: 12),
                                                          textAlign: TextAlign.center,
                                                        ),
                                                      ],
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
                                              card.expenses.remove(expense);
                                              int cardIdx = cards.indexOf(card);
                                              cardBox.putAt(cardIdx, card);
                                            });
                                            setModalState(() {});
                                          },
                                          child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // [전체 카드 소비 현황 및 정렬 변경 모달]
  void _showSummaryModal(BuildContext context) {
    DateTime selectedSummaryDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final int totalSpent = cards.fold<int>(0, (sum, card) => sum + card.getSpent(_isPerformanceMode, targetDate: selectedSummaryDate));
            final int totalBudget = cards.fold<int>(0, (sum, card) => sum + (card.total == -1 ? 0 : card.total));
            final totalRemaining = cards.fold<int>(0, (sum, card) {
              if (card.total == -1) return sum;
              final spent = card.getSpent(_isPerformanceMode, targetDate: selectedSummaryDate);
              return sum + (card.total - spent);
            });

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFE0E5EC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('월별 요약 및 순서', style: TextStyle(color: Color(0xFF2D3142), fontSize: 20, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => setModalState(() => selectedSummaryDate = DateTime(selectedSummaryDate.year, selectedSummaryDate.month - 1, 1)),
                            child: const Icon(Icons.chevron_left, size: 24, color: Color(0xFF2D3142)),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${selectedSummaryDate.month}월',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setModalState(() => selectedSummaryDate = DateTime(selectedSummaryDate.year, selectedSummaryDate.month + 1, 1)),
                            child: const Icon(Icons.chevron_right, size: 24, color: Color(0xFF2D3142)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(child: _buildSummaryItem('총 소비', '${_formatCurrency(totalSpent)}원', const Color(0xFF2F60FF))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildSummaryItem('남은 금액', '${_formatCurrency(totalRemaining)}원', totalRemaining >= 0 ? const Color(0xFF2F60FF) : Colors.redAccent)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text('카드별 내역 (순서 변경 가능)', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: cards.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        setModalState(() {
                          final item = cards.removeAt(oldIndex);
                          cards.insert(newIndex, item);
                        });
                        setState(() {
                          for (int i = 0; i < cards.length; i++) {
                            cardBox.putAt(i, cards[i]);
                          }
                        });
                      },
                      itemBuilder: (_, index) {
                        final card = cards[index];
                        final spent = card.getSpent(_isPerformanceMode, targetDate: selectedSummaryDate);
                        return ListTile(
                          key: ValueKey(card.name),
                          title: Text(card.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                          subtitle: Text(card.total == -1 ? '실적 제외' : '실적: ${_formatCurrency(spent)} / ${_formatCurrency(card.total)}원'),
                          trailing: const Icon(Icons.drag_handle),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================================
  // 5. 메인 화면 렌더링 영역
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentMonth = now.month;

    int totalSpent = cards.fold(0, (sum, card) => sum + card.getSpent(_isPerformanceMode));
    int totalBudget = cards.fold(0, (sum, card) => sum + (card.total == -1 ? 0 : card.total));
    double progressPercent = totalBudget == 0 ? 0.0 : (totalSpent / totalBudget).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Text(
              '$currentMonth월 지출',
              style: const TextStyle(color: Color(0xFF2D3142), fontWeight: FontWeight.bold, fontSize: 22),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _showSummaryModal(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E5EC),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4),
                    BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4),
                  ],
                ),
                child: const Text(
                  '요약',
                  style: TextStyle(fontSize: 12, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: () {
              setState(() {
                _isPerformanceMode = !_isPerformanceMode;
                settingsBox.put('isPerformanceMode', _isPerformanceMode);
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _isPerformanceMode ? const Color(0xFF2F60FF) : const Color(0xFFE0E5EC),
                borderRadius: BorderRadius.circular(12),
                boxShadow: _isPerformanceMode
                    ? [
                        BoxShadow(color: const Color(0xFF2F60FF).withOpacity(0.4), offset: const Offset(2, 2), blurRadius: 4),
                      ]
                    : [
                        const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4),
                        BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4),
                      ],
              ),
              child: Text(
                _isPerformanceMode ? '실적 확인' : '청구금액 확인',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _isPerformanceMode ? Colors.white : const Color(0xFF2D3142),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildProgressSection(progressPercent, now.day, currentMonth),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.95,
                ),
                itemCount: cards.length,
                itemBuilder: (context, index) {
                  return BudgetCardWidget(
                    data: cards[index],
                    isPerformanceMode: _isPerformanceMode,
                    onTap: () => _showCardDetailModal(context, cards[index]),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: () => _showAddExpenseModal(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4A7DFF), Color(0xFF1A4BFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF2F60FF).withOpacity(0.4), offset: const Offset(4, 6), blurRadius: 12),
                      const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 12),
                    ],
                  ),
                  child: const Text(
                    '지출 내역 추가',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 5-1. 내부 서브 컴포넌트: 상단 요약 카드 항목 빌더
  // --------------------------------------------------------------------------
  Widget _buildSummaryItem(String label, String value, Color valueColor, {String? subText}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E5EC),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.4), offset: const Offset(4, 4), blurRadius: 8),
          const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF9098B1), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor),
                ),
                if (subText != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    subText,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF9098B1), fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 5-2. 내부 서브 컴포넌트: 상단 이번 달 진행률 바 (게이지 및 날짜 툴팁)
  // --------------------------------------------------------------------------
  Widget _buildProgressSection(double progress, int currentDay, int currentMonth) {
    final lastDay = DateTime(DateTime.now().year, currentMonth + 1, 0).day;
    final double timeProgress = currentDay / lastDay;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double totalWidth = constraints.maxWidth;
          final double barHeight = 12.0;

          final double timeIndicatorPos = totalWidth * timeProgress;
          final double progressWidth = totalWidth * progress;

          final double tooltipWidth = 54.0;
          double tooltipLeft = timeIndicatorPos - (tooltipWidth / 2);
          if (tooltipLeft < 0) tooltipLeft = 0;
          if (tooltipLeft + tooltipWidth > totalWidth) tooltipLeft = totalWidth - tooltipWidth;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 34),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // 기본 배경 바 (오목한 디자인)
                  Container(
                    height: barHeight,
                    width: totalWidth,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D9E6),
                      borderRadius: BorderRadius.circular(barHeight / 2),
                    ),
                  ),
                  // 지출 진행률 채우기 (볼록한 파란 그라데이션 바)
                  Container(
                    height: barHeight,
                    width: progressWidth,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(barHeight / 2),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8faaff), Color(0xFF2F60FF)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  // 날짜 인디케이터 세로 막대 핀
                  Positioned(
                    left: timeIndicatorPos - 2,
                    top: -4,
                    child: Container(
                      width: 4,
                      height: barHeight + 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D3142),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // 날짜 말풍선 툴팁 컴포넌트
                  Positioned(
                    left: tooltipLeft,
                    top: -38,
                    child: SizedBox(
                      width: tooltipWidth,
                      height: 34,
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Positioned(
                            bottom: 2,
                            child: Transform.rotate(
                              angle: 3.141592 / 4,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0E5EC),
                                  boxShadow: [
                                    BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 3),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: tooltipWidth,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E5EC),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4),
                                const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4),
                              ],
                            ),
                            child: Text(
                              '${currentDay}일',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '지출 진행률: ${(progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9098B1), fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '한달 기준: ${(timeProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9098B1), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// 6. 개별 카드 위젯 (뉴모피즘 스타일 원형 인디케이터 포함)
// ============================================================================
class BudgetCardWidget extends StatefulWidget {
  final CardData data;
  final bool isPerformanceMode;
  final VoidCallback onTap;

  const BudgetCardWidget({
    super.key,
    required this.data,
    required this.isPerformanceMode,
    required this.onTap,
  });

  @override
  State<BudgetCardWidget> createState() => _BudgetCardWidgetState();
}

class _BudgetCardWidgetState extends State<BudgetCardWidget> {
  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    final int spentAmount = widget.data.getSpent(widget.isPerformanceMode);
    double spentPercent = 0.0;
    bool isOver = false;

    if (widget.data.total != -1 && widget.data.total > 0) {
      spentPercent = (spentAmount / widget.data.total).clamp(0.0, 1.0);
      if (spentAmount > widget.data.total) {
        isOver = true;
      }
    }

    Color activeColor = const Color(0xFF2F60FF);
    if (widget.data.total == -1) {
      activeColor = const Color(0xFF9098B1);
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE0E5EC),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFA3B1C6).withOpacity(0.6),
              offset: const Offset(8, 8),
              blurRadius: 16,
            ),
            const BoxShadow(
              color: Colors.white,
              offset: Offset(-8, -8),
              blurRadius: 16,
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E5EC),
                      shape: BoxShape.circle,
                      boxShadow: [
                        const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3),
                        BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 3),
                      ],
                    ),
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    child: Transform.scale(
                      scale: widget.data.name == '국민카드' ? 1.2 : 1.0,
                      child: const Icon(Icons.credit_card, size: 14, color: Color(0xFF2D3142)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.data.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3142),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E5EC),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(4, 4), blurRadius: 8),
                          const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: widget.data.total == -1 ? 0.0 : spentPercent,
                        strokeWidth: 7,
                        valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    if (isOver && widget.data.total != -1)
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: widget.data.total == 0 ? 1.0 : ((spentAmount - widget.data.total) / widget.data.total).clamp(0.0, 1.0),
                          strokeWidth: 7,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF453A)),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                    SizedBox(
                      width: 90,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _formatCurrency(spentAmount),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D3142),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                widget.data.total == -1 ? '실적 제외 카드' : '목표: ${_formatCurrency(widget.data.total)}원',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9098B1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}