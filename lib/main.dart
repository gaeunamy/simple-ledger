import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'main.g.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  Hive.registerAdapter(ExpenseAdapter());
  Hive.registerAdapter(CardDataAdapter());

  await Hive.openBox<CardData>('myCardsBox');

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

@HiveType(typeId: 0)
class Expense {
  @HiveField(0)
  final int amount;
  
  @HiveField(1)
  final DateTime date;

  @HiveField(2)
  final int? installmentMonths; 

  @HiveField(3)
  final bool isInstallment; 

  Expense({
    required this.amount, 
    required this.date, 
    this.installmentMonths, 
    this.isInstallment = false
  });

  String get formattedDate {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${date.month}.${date.day} ${weekdays[date.weekday - 1]}';
  }
}

@HiveType(typeId: 1)
class CardData {
  @HiveField(0)
  final String name;
  
  @HiveField(1)
  final String logoPath;
  
  @HiveField(2)
  final int total;
  
  @HiveField(3)
  List<Expense> expenses;

  CardData({
    required this.name, 
    required this.logoPath,
    required this.total,
    List<Expense>? expenses,
  }) : expenses = expenses ?? [];

  int getSpent(bool isPerformanceMode) {
    final now = DateTime.now();

    return expenses.fold(0, (sum, item) {
      if (isPerformanceMode) {
        if (item.isInstallment && item.installmentMonths == null) {
          return sum; 
        }
        if (item.date.year == now.year && item.date.month == now.month) {
          return sum + item.amount; 
        }
        return sum;
      } else {
        if (item.isInstallment) {
          if (item.installmentMonths == null) {
            if (item.date.year == now.year && item.date.month == now.month) {
              return sum + item.amount;
            }
          } else {
            int monthsPassed = (now.year - item.date.year) * 12 + (now.month - item.date.month);
            if (monthsPassed >= 0 && monthsPassed < item.installmentMonths!) {
              return sum + (item.amount ~/ item.installmentMonths!);
            }
          }
        } else {
          if (item.date.year == now.year && item.date.month == now.month) {
            return sum + item.amount;
          }
        }
        return sum;
      }
    });
  }

  bool isOverBudget(bool isPerformanceMode) => getSpent(isPerformanceMode) > total;
  double getSpentPercent(bool isPerformanceMode) => total > 0 ? (getSpent(isPerformanceMode) / total).clamp(0.0, 1.0) : 0.0;
}

class MultiCardScreen extends StatefulWidget {
  const MultiCardScreen({super.key});

  @override
  State<MultiCardScreen> createState() => _MultiCardScreenState();
}

class _MultiCardScreenState extends State<MultiCardScreen> with WidgetsBindingObserver {
  late Box<CardData> cardBox;
  late List<CardData> cards;

  final FocusNode _amountFocusNode = FocusNode();
  bool _isExpenseModalOpen = false;

  bool _isPerformanceMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cardBox = Hive.box<CardData>('myCardsBox');

    if (cardBox.isEmpty) {
      cardBox.addAll([
        CardData(name: '롯데카드', logoPath: 'assets/images/lotte.png', total: 300000, expenses: []),
        CardData(name: '국민카드', logoPath: 'assets/images/kb.png', total: 300000, expenses: []),
        CardData(name: '하나카드', logoPath: 'assets/images/hana.png', total: 300000, expenses: []),
        CardData(name: '신한카드', logoPath: 'assets/images/shinhan.png', total: 1000000, expenses: []),
        CardData(name: '삼성카드', logoPath: 'assets/images/samsung.png', total: 500000, expenses: []),
        CardData(name: '우리카드', logoPath: 'assets/images/woori.png', total: 300000, expenses: []),
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isExpenseModalOpen) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _isExpenseModalOpen) {
          _amountFocusNode.requestFocus();
        }
      });
    }
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  void _showAddExpenseModal(BuildContext context, {int initialCardIndex = 0}) {
    _isExpenseModalOpen = true;
    int selectedCardIndex = initialCardIndex;
    bool isExpanded = initialCardIndex >= 4; 
    
    bool isInstallmentActive = false; 
    bool showInstallmentPicker = false; 
    int? selectedInstallment; 

    final TextEditingController amountController = TextEditingController();

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
                child: Column(
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
                    const Text(
                      '지출 내역 추가',
                      style: TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold, 
                        color: Color(0xFF2D3142)
                      ),
                    ),
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
                                          borderRadius: BorderRadius.circular(8),
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
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF9098B1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // 🔥 피커에 의한 레이아웃 밀림 방지를 위해 Stack으로 감쌈
                    Stack(
                      clipBehavior: Clip.none, // 피커가 공중으로 온전히 튀어나올 수 있도록 설정
                      children: [
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
                                width: 70,
                                height: 40,
                                margin: const EdgeInsets.only(left: 6),
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
                                child: Text(
                                  '할부',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    // 🔥 할부가 활성화(ON) 되면 글자색을 파란색으로 변경
                                    color: isInstallmentActive ? const Color(0xFF2F60FF) : const Color(0xFF9098B1),
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
                                  height: 40,
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
                                style: const TextStyle(
                                  fontSize: 16, 
                                  color: Color(0xFF2D3142), 
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '소비 금액',
                                  hintStyle: TextStyle(
                                    fontSize: 16, 
                                    color: Color(0xFF9098B1), 
                                    fontWeight: FontWeight.w600,
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.only(bottom: 6),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Color(0xFFD1D9E6), width: 1),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Color(0xFF2F60FF), width: 1),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '원',
                              style: TextStyle(
                                fontSize: 16, 
                                color: Color(0xFF2D3142), 
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        // 🔥 공간을 밀어내지 않고 위로 떠오르는 오버레이 형태의 개월 수 피커
                        if (showInstallmentPicker)
                          Positioned(
                            bottom: 48, // 입력창 위쪽으로 배치
                            left: 88,   // 개월 버튼의 X축 위치에 딱 맞춤 (할부 여백 6 + 할부 버튼 70 + 간격 12)
                            child: Container(
                              height: 115, 
                              width: 80,   
                              decoration: BoxDecoration(
                                color: const Color(0xFFD1D9E6),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  // 오버레이가 살짝 떠있는 느낌을 주는 그림자 추가
                                  BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(4, 4), blurRadius: 8),
                                  const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)
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
                                  date: DateTime.now(),
                                  installmentMonths: selectedInstallment,
                                  isInstallment: isInstallmentActive,
                                )
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
                            colors: [
                              Color(0xFF4A7DFF), 
                              Color(0xFF1A4BFF), 
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2F60FF).withOpacity(0.4),
                              offset: const Offset(4, 6),
                              blurRadius: 12,
                            ),
                            const BoxShadow(
                              color: Colors.white,
                              offset: Offset(-4, -4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '확인',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
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

  void _showCardDetailModal(BuildContext context, CardData card) {
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
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          card.name,
                          style: const TextStyle(
                            color: Color(0xFF2D3142),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
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
                              '+',
                              style: TextStyle(
                                fontSize: 16, 
                                color: Color(0xFF2D3142), 
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Expanded(
                      child: card.expenses.isEmpty
                          ? const Center(
                              child: Text(
                                '아직 등록된 지출 내역이 없습니다.',
                                style: TextStyle(
                                  color: Color(0xFF9098B1),
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: card.expenses.length,
                              itemBuilder: (_, index) {
                                final expense = card.expenses[index];

                                int displayedAmount = expense.amount;
                                if (_isPerformanceMode) {
                                  if (expense.isInstallment && expense.installmentMonths == null) {
                                    displayedAmount = 0; 
                                  }
                                } else {
                                  if (expense.isInstallment && expense.installmentMonths != null) {
                                    displayedAmount = expense.amount ~/ expense.installmentMonths!;
                                  }
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          expense.formattedDate,
                                          style: const TextStyle(
                                            color: Color(0xFF9098B1),
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (expense.isInstallment) ...[
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF2F60FF),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Text(
                                              '${_formatCurrency(displayedAmount)}원',
                                              style: const TextStyle(
                                                color: Color(0xFF2D3142),
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            card.expenses.removeAt(index); 
                                            int cardIndex = cards.indexOf(card);
                                            cardBox.putAt(cardIndex, card);
                                          });
                                          setModalState(() {}); 
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.redAccent,
                                            size: 20,
                                          ),
                                        ),
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
            },
          );
        },
      );
    }

  void _showSummaryModal(BuildContext context) {
      final totalSpent = cards.fold<int>(0, (sum, card) => sum + card.getSpent(_isPerformanceMode));
      final totalBudget = cards.fold<int>(0, (sum, card) => sum + card.total);
      final totalRemaining = totalBudget - totalSpent;

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFFE0E5EC),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(32),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '요약',
                  style: TextStyle(
                    color: Color(0xFF2D3142),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        '총 소비',
                        '${_formatCurrency(totalSpent)}원',
                        const Color(0xFF2D3142),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _summaryCard(
                      '남은 예산',
                      '${_formatCurrency(totalRemaining)}원',
                      const Color(0xFF2D3142),
                    ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                const Text(
                  '카드별 소비',
                  style: TextStyle(
                    color: Color(0xFF9098B1),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                    itemCount: cards.length, 
                    itemBuilder: (_, index) {
                      final card = cards[index];
                      final remain = card.total - card.getSpent(_isPerformanceMode);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
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
                                scale: card.name == '국민카드' 
                                    ? 1.8 
                                    : card.name == '삼성카드' 
                                        ? 1.3 
                                        : 1.0, 
                                child: Image.asset(
                                  card.logoPath,
                                  width: 16, 
                                  height: 16,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.credit_card, size: 12, color: Color(0xFF2F60FF));
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    card.name,
                                    style: const TextStyle(
                                      color: Color(0xFF9098B1),
                                      fontSize: 12, 
                                    ),
                                  ),
                                  Text(
                                    '${_formatCurrency(card.getSpent(_isPerformanceMode))}원',
                                    style: const TextStyle(
                                      color: Color(0xFF2D3142),
                                      fontSize: 16, 
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              remain >= 0
                                  ? '${_formatCurrency(remain)}원 남음'
                                  : '-${_formatCurrency(remain.abs())}원 초과',
                              style: TextStyle(
                                color: remain >= 0
                                    ? const Color(0xFF2F60FF)
                                    : Colors.redAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
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
        },
      );
    }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentMonth = now.month;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final progressPercent = now.day / daysInMonth;

    final mainScreenCards = cards.where((card) => card.name != '우리카드' && card.name != '삼성카드').toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  '$currentMonth월 플랜',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3142),
                  ),
                ),
                const SizedBox(width: 10),
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
            
            GestureDetector(
              onTap: () {
                setState(() {
                  _isPerformanceMode = !_isPerformanceMode;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E5EC),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isPerformanceMode
                      ? [
                          const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 4),
                          BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 4),
                        ]
                      : [
                          const BoxShadow(color: Colors.white, offset: Offset(2, 2), blurRadius: 4),
                          BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(-2, -2), blurRadius: 4),
                        ],
                ),
                child: Text(
                  _isPerformanceMode ? '실적 보기' : '청구액 보기',
                  style: TextStyle(
                    fontSize: 12, 
                    color: _isPerformanceMode ? const Color(0xFF2F60FF) : const Color(0xFF9098B1), 
                    fontWeight: FontWeight.bold
                  ), 
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 5), 
              _buildProgressSection(progressPercent, now.day, currentMonth),
              const SizedBox(height: 55), 
              
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 18, 
                  mainAxisSpacing: 22, 
                  childAspectRatio: 0.85, 
                ),
                itemCount: mainScreenCards.length,
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => _showCardDetailModal(context, mainScreenCards[index]), 
                  child: BudgetCardWidget(data: mainScreenCards[index], isPerformanceMode: _isPerformanceMode),
                ),
              ),
              
              const SizedBox(height: 55),
              
              Center(
                child: GestureDetector(
                  onTap: () => _showAddExpenseModal(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF4A7DFF),
                          Color(0xFF1A4BFF),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2F60FF).withOpacity(0.4),
                        offset: const Offset(4, 6),
                        blurRadius: 12,
                      ),
                      const BoxShadow(
                        color: Colors.white,
                        offset: Offset(-4, -4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Text(
                    '지출 내역 추가',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _summaryCard(
      String title,
      String value,
      Color valueColor, {
      String? subText,
    }) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFE0E5EC),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            const BoxShadow(
              color: Colors.white,
              offset: Offset(-6, -6),
              blurRadius: 12,
            ),
            BoxShadow(
              color: const Color(0xFFA3B1C6).withOpacity(0.5),
              offset: const Offset(6, 6),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9098B1),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: valueColor,
                    ),
                  ),
                  if (subText != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      subText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9098B1),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E5EC),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      const BoxShadow(color: Colors.white, offset: Offset(2, 2), blurRadius: 4),
                      BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(-2, -2), blurRadius: 4),
                    ],
                  ),
                ),
                Container(
                  height: 12,
                  width: fillWidth,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2F60FF), Color(0xFF00C6FF)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(6),
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
                                boxShadow: [
                                  BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 2),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: tooltipWidth,
                          height: 26,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E5EC),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              const BoxShadow(color: Colors.white, offset: Offset(-2, -2), blurRadius: 3),
                              BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.5), offset: const Offset(2, 2), blurRadius: 3),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$currentDay일', 
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                          ),
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

class BudgetCardWidget extends StatefulWidget {
  final CardData data;
  final bool isPerformanceMode;
  const BudgetCardWidget({super.key, required this.data, required this.isPerformanceMode});
  @override
  State<BudgetCardWidget> createState() => _BudgetCardWidgetState();
}

class _BudgetCardWidgetState extends State<BudgetCardWidget> {
  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE0E5EC),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFA3B1C6).withOpacity(0.6),
              offset: const Offset(8, 8),
              blurRadius: 16),
          const BoxShadow(
              color: Colors.white, offset: Offset(-8, -8), blurRadius: 16)
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
                    scale: widget.data.name == '국민카드' ? 1.8 : widget.data.name == '삼성카드' ? 1.3 : 1.0,
                    child: Image.asset(
                      widget.data.logoPath,
                      width: 16,
                      height: 16,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.credit_card, size: 14, color: Color(0xFF2F60FF));
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.data.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                ),
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
    final spentAmount = widget.data.getSpent(widget.isPerformanceMode);
    final spentPercent = widget.data.getSpentPercent(widget.isPerformanceMode);
    final isOver = widget.data.isOverBudget(widget.isPerformanceMode);

    final activeColor = widget.isPerformanceMode
        ? const Color(0xFF2F60FF)
        : const Color(0xFF00BFA5);

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE0E5EC),
              boxShadow: [
                BoxShadow(color: Color(0xFFA3B1C6), offset: Offset(4, 4), blurRadius: 8),
                BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8)
              ],
            ),
          ),
          SizedBox(
            width: 100,
            height: 100,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(widget.isPerformanceMode),
              tween: Tween<double>(begin: 0.0, end: spentPercent),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 7,
                valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
          if (isOver)
            SizedBox(
              width: 100,
              height: 100,
              child: CircularProgressIndicator(
                value: ((spentAmount - widget.data.total) / widget.data.total).clamp(0.0, 1.0),
                strokeWidth: 7,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF453A)),
                strokeCap: StrokeCap.round,
              ),
            ),
          SizedBox(
            width: 90,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: Text(
                  _formatCurrency(spentAmount),
                  key: ValueKey(spentAmount),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}