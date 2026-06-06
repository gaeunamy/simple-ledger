import 'package:flutter/material.dart';

void main() {
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

class MultiCardScreen extends StatefulWidget {
  const MultiCardScreen({super.key});

  @override
  State<MultiCardScreen> createState() => _MultiCardScreenState();
}

class _MultiCardScreenState extends State<MultiCardScreen> {
  final List<CardData> cards = [
    CardData(name: '신한카드', spent: 106500, total: 150000),
    CardData(name: '국민카드', spent: 170000, total: 150000),
    CardData(name: '하나카드', spent: 35000, total: 150000),
    CardData(name: '롯데카드', spent: 150000, total: 150000),
  ];

  // 팝업 모달 띄우기 함수
  void _showAddExpenseModal(BuildContext context) {
    int selectedCardIndex = 0;
    final TextEditingController amountController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 키보드가 올라올 때 모달이 밀려 올라가도록 설정
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, // 키보드 높이만큼 여백 추가
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
                    const Text(
                      '지출 내역 추가',
                      style: TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.bold, 
                        color: Color(0xFF2D3142)
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // 1열 4행 카드사 선택 탭
                    Container(
                      height: 50,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D9E6), // 음각 느낌 배경
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
                                  cards[index].name.substring(0, 2), // 카드사 이름 두 글자만
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
                    
                    // 소비 금액 입력창
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
                                borderSide: BorderSide(color: Color(0xFF14546A), width: 2),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Color(0xFF14546A), width: 2),
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
                    
                    // 확인 (추가) 버튼 - 파란색 입체 뉴모피즘 스타일 적용
                    GestureDetector(
                      onTap: () {
                        if (amountController.text.isNotEmpty) {
                          int amount = int.tryParse(amountController.text.replaceAll(',', '')) ?? 0;
                          if (amount > 0) {
                            setState(() {
                              cards[selectedCardIndex].spent += amount;
                            });
                            Navigator.pop(context); // 적용 후 모달 닫기
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
                              Color(0xFF4A7DFF), // 좌상단: 밝은 파랑
                              Color(0xFF1A4BFF), // 우하단: 진한 파랑
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

String _formatCurrency(int amount) {
  return amount.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

void _showSummaryModal(BuildContext context) {
  final totalSpent =
      cards.fold<int>(0, (sum, card) => sum + card.spent);

  final totalBudget =
      cards.fold<int>(0, (sum, card) => sum + card.total);

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
                    subText: '/ ${_formatCurrency(totalBudget)}원',
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
                        CircleAvatar(
                          radius: 28,
                          backgroundColor:
                              const Color(0xFF2A2A2D),
                          child: Text(
                            card.name[0],
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
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
          children: [
            const Text(
              '내 플랜',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3142), 
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => _showSummaryModal(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E5EC),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    const BoxShadow(
                      color: Colors.white,
                      offset: Offset(-2, -2),
                      blurRadius: 4,
                    ),
                    BoxShadow(
                      color: const Color(0xFFA3B1C6).withOpacity(0.5),
                      offset: const Offset(2, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Text(
                  '요약',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9098B1), fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF2D3142), size: 28),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Color(0xFF2D3142)),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProgressSection(progressPercent, now.day, currentMonth),
              const SizedBox(height: 48),
              _buildCardGrid(),
              const SizedBox(height: 48),
              
              // 메인 화면 하단 - 글자 크기에 맞춘 입체적인 파란색 뉴모피즘 버튼
              Center(
                child: GestureDetector(
                  onTap: () => _showAddExpenseModal(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), // 글자 크기에 맞춰지도록 패딩 설정
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF4A7DFF), // 좌상단: 밝은 파랑
                          Color(0xFF1A4BFF), // 우하단: 진한 파랑
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
        Text(
          '$currentMonth월 진행 상황', 
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF9098B1),
            fontWeight: FontWeight.w600,
          ),
        ),
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

  Widget _buildCardGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 20,
        mainAxisSpacing: 28,
        childAspectRatio: 0.85, 
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) => BudgetCardWidget(data: cards[index]),
    );
  }
}

class CardData {
  final String name;
  int spent; 
  final int total;

  CardData({required this.name, required this.spent, required this.total});

  bool get isOverBudget => spent > total;
  double get spentPercent => (spent / total).clamp(0.0, 1.0);
}

class BudgetCardWidget extends StatefulWidget {
  final CardData data;
  const BudgetCardWidget({super.key, required this.data});
  @override
  State<BudgetCardWidget> createState() => _BudgetCardWidgetState();
}

class _BudgetCardWidgetState extends State<BudgetCardWidget> {
  bool _isHovered = false;
  bool _isButtonPressed = false;

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    // 1. MouseRegion 제거 (카드 전체의 상호작용 삭제)
    return Container(
      // 2. AnimatedContainer를 일반 Container로 변경 (상태 변화 애니메이션 제거)
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
                  child: Text(
                    widget.data.name[0],
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2F60FF)),
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
            
            const Center(
              child: Text('지출 금액', style: TextStyle(fontSize: 13, color: Color(0xFF9098B1), fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
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
                BoxShadow(color: Color(0xFFA3B1C6), offset: Offset(4, 4), blurRadius: 8), // 오타 수정 완료
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