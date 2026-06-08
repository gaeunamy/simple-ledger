import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';

part 'main.g.dart';

// ============================================================================
// 1. 유틸리티 및 확장 기능 (Extensions & Formatters)
// ============================================================================
extension CurrencyFormatter on int {
  /// 숫자를 100,000 형태의 콤마가 포함된 문자열로 변환합니다.
  String toCurrency() {
    return toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}

class CurrencyInputFormatter extends TextInputFormatter {
  /// TextField 입력 시 실시간으로 천 단위 콤마를 찍어줍니다.
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    String cleaned = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return newValue.copyWith(text: '');
    
    int value = int.parse(cleaned);
    String formatted = value.toCurrency();
    
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ============================================================================
// 2. 앱 진입점 및 로컬 데이터베이스(Hive) 초기화
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
// 3. 앱 인프라 설정 (루트 위젯 및 글로벌 테마)
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
// 4. 데이터 모델 클래스 (안정성을 위해 id 및 orderIndex 필드 추가)
// ============================================================================
@HiveType(typeId: 0)
class Expense extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final int amount;
  @HiveField(2)
  final DateTime date;
  @HiveField(3)
  final int? installmentMonths;
  @HiveField(4)
  final bool isInstallment;
  @HiveField(5)
  final String? memo;

  Expense({
    required this.id,
    required this.amount,
    required this.date,
    this.installmentMonths,
    this.isInstallment = false,
    this.memo,
  });

  String get formattedDate => '${date.month}.${date.day.toString().padLeft(2, '0')}';
  
  Expense copyWith({
    int? amount,
    DateTime? date,
    int? installmentMonths,
    bool? isInstallment,
    String? memo,
  }) {
    return Expense(
      id: id,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      installmentMonths: installmentMonths ?? this.installmentMonths,
      isInstallment: isInstallment ?? this.isInstallment,
      memo: memo ?? this.memo,
    );
  }
}

@HiveType(typeId: 1)
class CardData extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final int total;
  @HiveField(3)
  final List<Expense> expenses;
  @HiveField(4)
  int orderIndex;

  CardData({
    required this.id,
    required this.name,
    required this.total,
    required this.expenses,
    required this.orderIndex,
  });

  CardData copyWith({
    String? name,
    int? total,
    List<Expense>? expenses,
    int? orderIndex,
  }) {
    return CardData(
      id: id,
      name: name ?? this.name,
      total: total ?? this.total,
      // 원본 데이터 오염 방지를 위해 가변 리스트로 복제
      expenses: expenses ?? List<Expense>.from(this.expenses),
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  int getSpent(bool isPerformanceMode, {DateTime? targetDate}) {
    final target = targetDate ?? DateTime.now();
    int spent = 0;
    for (var expense in expenses) {
      if (isPerformanceMode) {
        if (expense.isInstallment && expense.installmentMonths == null) continue;
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
// 5. 메인 스크린 컴포넌트
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cardBox = Hive.box<CardData>('myCardsBox');
    settingsBox = Hive.box('settingsBox');

    _isPerformanceMode = settingsBox.get('isPerformanceMode', defaultValue: false);

    if (cardBox.isEmpty) {
      _initDefaultCards();
    }
    _loadCards();
  }

  Future<void> _initDefaultCards() async {
    try {
      final defaultCards = [
        CardData(id: 'c1', name: '신한카드', total: 300000, expenses: [], orderIndex: 0),
        CardData(id: 'c2', name: '국민카드', total: 300000, expenses: [], orderIndex: 1),
        CardData(id: 'c3', name: '삼성카드', total: -1, expenses: [], orderIndex: 2),
        CardData(id: 'c4', name: '현대카드', total: 500000, expenses: [], orderIndex: 3),
      ];
      for (var card in defaultCards) {
        await cardBox.put(card.id, card);
      }
    } catch (e) {
      debugPrint('카드 초기화 에러: $e');
    }
  }

  void _loadCards() {
    setState(() {
      cards = cardBox.values.toList();
      cards.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  // 데이터베이스 안전 저장 헬퍼
  Future<void> _safeSaveCard(CardData updatedCard) async {
    try {
      await cardBox.put(updatedCard.id, updatedCard);
      _loadCards();
    } catch (e) {
      debugPrint('저장 실패: $e');
    }
  }

  void _showSummaryModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SummaryBottomSheet(
          cards: cards,
          isPerformanceMode: _isPerformanceMode,
          onReorder: (oldIndex, newIndex) async {
            if (newIndex > oldIndex) newIndex -= 1;
            setState(() {
              final item = cards.removeAt(oldIndex);
              cards.insert(newIndex, item);
            });
            try {
              for (int i = 0; i < cards.length; i++) {
                cards[i].orderIndex = i;
                await cardBox.put(cards[i].id, cards[i]);
              }
            } catch (e) {
              debugPrint('순서 변경 에러: $e');
            }
          },
        );
      },
    );
  }

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
            onTap: () async {
              setState(() {
                _isPerformanceMode = !_isPerformanceMode;
              });
              await settingsBox.put('isPerformanceMode', _isPerformanceMode);
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
                    ? [BoxShadow(color: const Color(0xFF2F60FF).withOpacity(0.4), offset: const Offset(2, 2), blurRadius: 4)]
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
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => CardDetailBottomSheet(
                          card: cards[index],
                          isPerformanceMode: _isPerformanceMode,
                          onCardUpdated: _safeSaveCard,
                          onAddExpenseRequested: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => AddExpenseBottomSheet(
                                cards: cards,
                                initialCardIndex: index,
                                onSave: _safeSaveCard,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => AddExpenseBottomSheet(
                      cards: cards,
                      initialCardIndex: 0,
                      onSave: _safeSaveCard,
                    ),
                  );
                },
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

  Widget _buildProgressSection(double progress, int currentDay, int currentMonth) {
    final lastDay = DateTime(DateTime.now().year, currentMonth + 1, 0).day;
    final double timeProgress = currentDay / lastDay;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double totalWidth = constraints.maxWidth;
          const double barHeight = 12.0;

          final double timeIndicatorPos = totalWidth * timeProgress;
          final double progressWidth = totalWidth * progress;

          const double tooltipWidth = 54.0;
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
                  Container(
                    height: barHeight,
                    width: totalWidth,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D9E6),
                      borderRadius: BorderRadius.circular(barHeight / 2),
                    ),
                  ),
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
                                  boxShadow: [BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 3)],
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
                  Text('지출 진행률: ${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Color(0xFF9098B1), fontWeight: FontWeight.w600)),
                  Text('한달 기준: ${(timeProgress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Color(0xFF9098B1), fontWeight: FontWeight.w600)),
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
// 6. 분리된 모듈 위젯들 (성능 최적화)
// ============================================================================

// [지출 추가 바텀 시트]
class AddExpenseBottomSheet extends StatefulWidget {
  final List<CardData> cards;
  final int initialCardIndex;
  final Function(CardData) onSave;

  const AddExpenseBottomSheet({
    super.key,
    required this.cards,
    required this.initialCardIndex,
    required this.onSave,
  });

  @override
  State<AddExpenseBottomSheet> createState() => _AddExpenseBottomSheetState();
}

class _AddExpenseBottomSheetState extends State<AddExpenseBottomSheet> {
  late int selectedCardIndex;
  DateTime selectedDate = DateTime.now();
  late DateTime currentMonthView;
  bool showCalendar = false;
  bool isInstallmentActive = false;
  int? selectedInstallment;
  bool showInstallmentPicker = false;
  bool isExpanded = false;
  final amountController = TextEditingController();
  final _amountFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    selectedCardIndex = widget.initialCardIndex;
    currentMonthView = DateTime(selectedDate.year, selectedDate.month, 1);
  }

  @override
  Widget build(BuildContext context) {
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
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('지출 내역 추가', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                    Builder(
                      builder: (context) {
                        final isToday = selectedDate.year == DateTime.now().year &&
                            selectedDate.month == DateTime.now().month &&
                            selectedDate.day == DateTime.now().day;
                        return GestureDetector(
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            setState(() {
                              showCalendar = !showCalendar;
                              if (showCalendar) currentMonthView = DateTime(selectedDate.year, selectedDate.month, 1);
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
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isToday ? const Color(0xFF9098B1) : const Color(0xFF2F60FF)),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (showCalendar) _buildInlineCalendar(),
                const SizedBox(height: 24),
                _buildCardSelector(),
                const SizedBox(height: 32),
                _buildInputRow(),
                const SizedBox(height: 40),
                GestureDetector(
                  onTap: () {
                    if (amountController.text.isNotEmpty) {
                      int amount = int.tryParse(amountController.text.replaceAll(',', '')) ?? 0;
                      if (amount > 0) {
                        final newExpense = Expense(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          amount: amount,
                          date: selectedDate,
                          installmentMonths: selectedInstallment,
                          isInstallment: isInstallmentActive,
                        );
                        
                        // 기존 리스트를 안전하게 복제하여 수정 (Unmodifiable 오류 방지)
                        final targetCard = widget.cards[selectedCardIndex];
                        final newExpensesList = List<Expense>.from(targetCard.expenses)..insert(0, newExpense);
                        final updatedCard = targetCard.copyWith(expenses: newExpensesList);
                        
                        widget.onSave(updatedCard);
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(colors: [Color(0xFF4A7DFF), Color(0xFF1A4BFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      boxShadow: [BoxShadow(color: const Color(0xFF2F60FF).withOpacity(0.4), offset: const Offset(0, 4), blurRadius: 8)],
                    ),
                    alignment: Alignment.center,
                    child: const Text('추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
            if (showInstallmentPicker) _buildInstallmentPicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineCalendar() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
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
                  onTap: () => setState(() => currentMonthView = DateTime(currentMonthView.year, currentMonthView.month - 1, 1)),
                  child: const Icon(Icons.chevron_left, color: Color(0xFF2D3142)),
                ),
                Text('${currentMonthView.year}년 ${currentMonthView.month}월', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                GestureDetector(
                  onTap: () => setState(() => currentMonthView = DateTime(currentMonthView.year, currentMonthView.month + 1, 1)),
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
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 8, crossAxisSpacing: 8),
                itemCount: blankSpaces + daysInMonth,
                itemBuilder: (context, index) {
                  if (index < blankSpaces) return const SizedBox.shrink();
                  final day = index - blankSpaces + 1;
                  final isSelected = currentMonthView.year == selectedDate.year && currentMonthView.month == selectedDate.month && day == selectedDate.day;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
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
                        style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: isSelected ? const Color(0xFF2F60FF) : const Color(0xFF2D3142)),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCardSelector() {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: const Color(0xFFD1D9E6), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          ...List.generate(isExpanded ? widget.cards.length : 4, (index) {
            final isSelected = selectedCardIndex == index;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => selectedCardIndex = index),
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
                    widget.cards[index].name.substring(0, 2),
                    style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, color: isSelected ? const Color(0xFF2F60FF) : const Color(0xFF9098B1)),
                  ),
                ),
              ),
            );
          }),
          if (!isExpanded)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => isExpanded = true),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.transparent),
                  alignment: Alignment.center,
                  child: const Text('+', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF9098B1))),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
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
                : BoxDecoration(color: const Color(0xFFD1D9E6), borderRadius: BorderRadius.circular(12)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('할부', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isInstallmentActive ? const Color(0xFF2F60FF) : const Color(0xFF9098B1))),
              ),
            ),
          ),
        ),
        if (isInstallmentActive) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => setState(() => showInstallmentPicker = !showInstallmentPicker),
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
                  : BoxDecoration(color: const Color(0xFFD1D9E6), borderRadius: BorderRadius.circular(12)),
              child: Text(selectedInstallment != null ? '$selectedInstallment개월' : '개월',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: selectedInstallment != null ? const Color(0xFF2F60FF) : const Color(0xFF9098B1))),
            ),
          ),
        ],
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: amountController,
            focusNode: _amountFocusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              CurrencyInputFormatter(), // 개선점: 실시간 콤마
            ],
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
        const Text('원', style: TextStyle(fontSize: 16, color: Color(0xFF2D3142), fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInstallmentPicker() {
    return Positioned(
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
                setState(() {
                  selectedInstallment = month;
                  showInstallmentPicker = false;
                });
              },
              child: Container(
                height: 32,
                alignment: Alignment.center,
                margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                decoration: BoxDecoration(color: isMonthSelected ? const Color(0xFF2F60FF) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                child: Text('$month개월', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isMonthSelected ? Colors.white : const Color(0xFF2D3142))),
              ),
            );
          },
        ),
      ),
    );
  }
}

// [특정 카드 지출 내역 바텀시트]
class CardDetailBottomSheet extends StatefulWidget {
  final CardData card;
  final bool isPerformanceMode;
  final Function(CardData) onCardUpdated;
  final VoidCallback onAddExpenseRequested;

  const CardDetailBottomSheet({
    super.key,
    required this.card,
    required this.isPerformanceMode,
    required this.onCardUpdated,
    required this.onAddExpenseRequested,
  });

  @override
  State<CardDetailBottomSheet> createState() => _CardDetailBottomSheetState();
}

class _CardDetailBottomSheetState extends State<CardDetailBottomSheet> {
  DateTime targetDate = DateTime.now();

  void _showEditCardDialog() {
    final nameController = TextEditingController(text: widget.card.name);
    final totalController = TextEditingController(text: widget.card.total == -1 ? '' : widget.card.total.toString());
    bool isPerformanceExcluded = widget.card.total == -1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFE0E5EC),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('카드 수정', style: TextStyle(color: Color(0xFF2D3142), fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFD1D9E6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('실적 제외 카드', style: TextStyle(color: Color(0xFF2D3142), fontSize: 14, fontWeight: FontWeight.bold)),
                    Switch(
                      value: isPerformanceExcluded,
                      onChanged: (val) => setDialogState(() {
                        isPerformanceExcluded = val;
                        if (val) totalController.clear();
                      }),
                    ),
                  ],
                ),
                if (!isPerformanceExcluded) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: totalController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFD1D9E6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
              TextButton(
                onPressed: () {
                  final newName = nameController.text.trim();
                  final newTotal = isPerformanceExcluded ? -1 : (int.tryParse(totalController.text) ?? 0);
                  final updatedCard = widget.card.copyWith(name: newName.isNotEmpty ? newName : widget.card.name, total: newTotal);
                  widget.onCardUpdated(updatedCard);
                  Navigator.pop(context);
                },
                child: const Text('저장'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredExpenses = widget.card.expenses.where((expense) {
      if (widget.isPerformanceMode) {
        if (expense.isInstallment && expense.installmentMonths == null) return false;
        return expense.date.year == targetDate.year && expense.date.month == targetDate.month;
      } else {
        if (expense.isInstallment) {
          if (expense.installmentMonths == null) {
            return expense.date.year == targetDate.year && expense.date.month == targetDate.month;
          }
          int monthsPassed = (targetDate.year - expense.date.year) * 12 + (targetDate.month - expense.date.month);
          return monthsPassed >= 0 && monthsPassed < expense.installmentMonths!;
        } else {
          return expense.date.year == targetDate.year && expense.date.month == targetDate.month;
        }
      }
    }).toList();

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
          Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(999)))),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(widget.card.name, style: const TextStyle(color: Color(0xFF2D3142), fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  GestureDetector(onTap: _showEditCardDialog, child: const Icon(Icons.edit, size: 16, color: Color(0xFF9098B1))),
                ],
              ),
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  widget.onAddExpenseRequested();
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
                  child: const Text('지출 추가', style: TextStyle(color: Color(0xFF2F60FF), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: filteredExpenses.isEmpty
                ? const Center(child: Text('이번 달 지출 내역이 없습니다.', style: TextStyle(color: Color(0xFF9098B1), fontSize: 16)))
                : ListView.builder(
                    itemCount: filteredExpenses.length,
                    itemBuilder: (_, index) {
                      final expense = filteredExpenses[index];
                      int displayedAmount = expense.amount;
                      if (!widget.isPerformanceMode && expense.isInstallment && expense.installmentMonths != null) {
                        displayedAmount = expense.amount ~/ expense.installmentMonths!;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          children: [
                            SizedBox(width: 60, child: Text(expense.formattedDate, style: const TextStyle(color: Color(0xFF9098B1), fontSize: 14))),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (expense.isInstallment)
                                        Container(
                                          width: 6,
                                          height: 6,
                                          margin: const EdgeInsets.only(right: 6),
                                          decoration: BoxDecoration(color: expense.installmentMonths == null ? const Color(0xFF00BFA5) : const Color(0xFF2F60FF), shape: BoxShape.circle),
                                        ),
                                      Text('${displayedAmount.toCurrency()}원', style: const TextStyle(color: Color(0xFF2D3142), fontSize: 16, fontWeight: FontWeight.bold)),
                                      if (widget.isPerformanceMode && expense.isInstallment && expense.installmentMonths != null)
                                        Text('/${expense.installmentMonths}개월', style: const TextStyle(color: Color(0xFF9098B1), fontSize: 12)),
                                    ],
                                  ),
                                  if (expense.memo != null && expense.memo!.isNotEmpty) Text(expense.memo!, style: const TextStyle(color: Color(0xFF9098B1), fontSize: 12)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: () {
                                final newList = List<Expense>.from(widget.card.expenses)..remove(expense);
                                widget.onCardUpdated(widget.card.copyWith(expenses: newList));
                              },
                              child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// [상단 요약 및 정렬 바텀시트]
class SummaryBottomSheet extends StatefulWidget {
  final List<CardData> cards;
  final bool isPerformanceMode;
  final Function(int, int) onReorder;

  const SummaryBottomSheet({super.key, required this.cards, required this.isPerformanceMode, required this.onReorder});

  @override
  State<SummaryBottomSheet> createState() => _SummaryBottomSheetState();
}

class _SummaryBottomSheetState extends State<SummaryBottomSheet> {
  DateTime selectedSummaryDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final int totalSpent = widget.cards.fold<int>(0, (sum, card) => sum + card.getSpent(widget.isPerformanceMode, targetDate: selectedSummaryDate));
    final totalRemaining = widget.cards.fold<int>(0, (sum, card) {
      if (card.total == -1) return sum;
      return sum + (card.total - card.getSpent(widget.isPerformanceMode, targetDate: selectedSummaryDate));
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
          Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(999)))),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('월별 요약 및 순서', style: TextStyle(color: Color(0xFF2D3142), fontSize: 20, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  GestureDetector(onTap: () => setState(() => selectedSummaryDate = DateTime(selectedSummaryDate.year, selectedSummaryDate.month - 1, 1)), child: const Icon(Icons.chevron_left, size: 24)),
                  const SizedBox(width: 8),
                  Text('${selectedSummaryDate.month}월', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => setState(() => selectedSummaryDate = DateTime(selectedSummaryDate.year, selectedSummaryDate.month + 1, 1)), child: const Icon(Icons.chevron_right, size: 24)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(child: _buildSummaryItem('총 소비', '${totalSpent.toCurrency()}원', const Color(0xFF2F60FF))),
              const SizedBox(width: 16),
              Expanded(child: _buildSummaryItem('남은 금액', '${totalRemaining.toCurrency()}원', totalRemaining >= 0 ? const Color(0xFF2F60FF) : Colors.redAccent)),
            ],
          ),
          const SizedBox(height: 32),
          const Text('카드별 내역 (순서 변경 가능)', style: TextStyle(color: Color(0xFF9098B1), fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: widget.cards.length,
              onReorder: widget.onReorder,
              itemBuilder: (_, index) {
                final card = widget.cards[index];
                final spent = card.getSpent(widget.isPerformanceMode, targetDate: selectedSummaryDate);
                return ListTile(
                  key: ValueKey(card.id),
                  title: Text(card.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                  subtitle: Text(card.total == -1 ? '실적 제외' : '실적: ${spent.toCurrency()} / ${card.total.toCurrency()}원'),
                  trailing: const Icon(Icons.drag_handle),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color valueColor) {
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
            child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: valueColor)),
          ),
        ],
      ),
    );
  }
}

// [메인 화면 카드 위젯]
class BudgetCardWidget extends StatelessWidget {
  final CardData data;
  final bool isPerformanceMode;
  final VoidCallback onTap;

  const BudgetCardWidget({super.key, required this.data, required this.isPerformanceMode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final int spentAmount = data.getSpent(isPerformanceMode);
    double spentPercent = 0.0;
    bool isOver = false;

    if (data.total != -1 && data.total > 0) {
      spentPercent = (spentAmount / data.total).clamp(0.0, 1.0);
      if (spentAmount > data.total) isOver = true;
    }

    Color activeColor = data.total == -1 ? const Color(0xFF9098B1) : const Color(0xFF2F60FF);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE0E5EC),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.6), offset: const Offset(8, 8), blurRadius: 16),
            const BoxShadow(color: Colors.white, offset: Offset(-8, -8), blurRadius: 16)
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
                    child: const Icon(Icons.credit_card, size: 14, color: Color(0xFF2D3142)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(data.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                        value: data.total == -1 ? 0.0 : spentPercent,
                        strokeWidth: 7,
                        valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    if (isOver && data.total != -1)
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: data.total == 0 ? 1.0 : ((spentAmount - data.total) / data.total).clamp(0.0, 1.0),
                          strokeWidth: 7,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF453A)),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                    SizedBox(
                      width: 90,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(spentAmount.toCurrency(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3142))),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                data.total == -1 ? '실적 제외 카드' : '목표: ${data.total.toCurrency()}원',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF9098B1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}