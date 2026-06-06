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

// 지출 내역 모델
@HiveType(typeId: 0)
class Expense {
  @HiveField(0)
  final int amount;
  
  @HiveField(1)
  final DateTime date;

  Expense({required this.amount, required this.date});

  String get formattedDate {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${date.month}.${date.day} ${weekdays[date.weekday - 1]}';
  }
}

// 카드 데이터 모델
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

  int get spent => expenses.fold(0, (sum, item) => sum + item.amount);
  bool get isOverBudget => spent > total;
  double get spentPercent => total > 0 ? (spent / total).clamp(0.0, 1.0) : 0.0;
}

class MultiCardScreen extends StatefulWidget {
  const MultiCardScreen({super.key});

  @override
  State<MultiCardScreen> createState() => _MultiCardScreenState();
}

class _MultiCardScreenState extends State<MultiCardScreen> {
  late Box<CardData> cardBox;
  late List<CardData> cards;

  @override
  void initState() {
    super.initState();
    cardBox = Hive.box<CardData>('myCardsBox');

    if (cardBox.isEmpty) {
      cardBox.addAll([
        CardData(name: '롯데카드', logoPath: 'assets/images/lotte.png', total: 150000, expenses: []),
        CardData(name: '국민카드', logoPath: 'assets/images/kb.png', total: 150000, expenses: []),
        CardData(name: '하나카드', logoPath: 'assets/images/hana.png', total: 150000, expenses: []),
        CardData(name: '삼성카드', logoPath: 'assets/images/samsung.png', total: 150000, expenses: []),
      ]);
    }

    cards = cardBox.values.toList();
  }

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  // 지출 내역 추가 팝업 모달
  void _showAddExpenseModal(BuildContext context, {int initialCardIndex = 0}) {
    int selectedCardIndex = initialCardIndex;
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
                bottom: MediaQuery.of(context).viewInsets.bottom, 
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
                        fontSize: 16, 
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
                        children: List.generate(cards.length, (index) {
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
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amountController,
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
                    
                    const SizedBox(height: 40),
                    
                    GestureDetector(
                      onTap: () {
                        if (amountController.text.isNotEmpty) {
                          int amount = int.tryParse(amountController.text.replaceAll(',', '')) ?? 0;
                          if (amount > 0) {
                            setState(() {
                              cards[selectedCardIndex].expenses.insert(
                                0, 
                                Expense(amount: amount, date: DateTime.now())
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
                            fontSize: 14,
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
    );
  }

  // 특정 카드 지출 내역 모달
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
                    
                    // 추가 버튼
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
                            Navigator.pop(context); // 현재 상세 모달 닫기
                            _showAddExpenseModal(context, initialCardIndex: cards.indexOf(card)); // 지출 추가 모달 열기
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
                                        child: Text(
                                          '${_formatCurrency(expense.amount)}원',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Color(0xFF2D3142),
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
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
      final totalSpent = cards.fold<int>(0, (sum, card) => sum + card.spent);
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
                      final remain = card.total - card.spent;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
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
                                  width: 20,
                                  height: 20,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.credit_card, size: 12, color: Color(0xFF2F60FF));
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    card.name,
                                    style: const TextStyle(
                                      color: Color(0xFF9098B1),
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${_formatCurrency(card.spent)}원',
                                    style: const TextStyle(
                                      color: Color(0xFF2D3142),
                                      fontSize: 18,
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
                                fontSize: 14,
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$currentMonth월 플랜',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3142),
              ),
            ),
            GestureDetector(
              onTap: () => _showSummaryModal(context),
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
                  '요약',
                  style: TextStyle(fontSize: 14, color: Color(0xFF2D3142), fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5), 
            _buildProgressSection(progressPercent, now.day, currentMonth),
            const SizedBox(height: 60),
            
            // 카드 그리드 뷰
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 25,
                mainAxisSpacing: 30,
                childAspectRatio: 0.85, 
              ),
              itemCount: cards.length,
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => _showCardDetailModal(context, cards[index]), 
                child: BudgetCardWidget(data: cards[index]),
              ),
            ),
            
            const SizedBox(height: 60),
            
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
    );
  }

  Widget _summaryCard(
    String title,
    String value,
    Color valueColor, {
    String? subText,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),

              if (subText != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subText,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF9098B1),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(double progress, int currentDay, int currentMonth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 44), 
        
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
  const BudgetCardWidget({super.key, required this.data});
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
                  width: 28,
                  height: 28,
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
                    scale: widget.data.name == '국민카드' 
                        ? 1.8 
                        : widget.data.name == '삼성카드' 
                            ? 1.3 
                            : 1.0,
                    child: Image.asset(
                      widget.data.logoPath,
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.credit_card, size: 16, color: Color(0xFF2F60FF));
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.data.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                ),
              ],
            ),
            
            Expanded(child: Center(child: _buildDonutChart())),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${_formatCurrency(widget.data.spent)}원',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
                ),
                const Text(
                  ' / ',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9098B1)),
                ),
                Text(
                  '${_formatCurrency(widget.data.total)}원',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF9098B1)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDonutChart() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
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
            width: 120,
            height: 120,
            child: CircularProgressIndicator(
              value: widget.data.spentPercent,
              strokeWidth: 8,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2F60FF)),
              strokeCap: StrokeCap.round,
            ),
          ),
          if (widget.data.isOverBudget)
            SizedBox(
              width: 120,
              height: 120,
              child: CircularProgressIndicator(
                value: ((widget.data.spent - widget.data.total) / widget.data.total).clamp(0.0, 1.0),
                strokeWidth: 8,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF453A)),
                strokeCap: StrokeCap.round,
              ),
            ),
          Text(
            _formatCurrency(widget.data.spent),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
          ),
        ],
      ),
    );
  }
}