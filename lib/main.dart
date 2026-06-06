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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            ],
          ),
        ),
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
                // 오늘 날짜를 표시하는 말풍선
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
                            '$currentDay일', // 오늘 날짜가 표시됩니다.
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
  final int spent;
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

  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: const Color(0xFFE0E5EC),
          borderRadius: BorderRadius.circular(24),
          boxShadow: _isHovered
              ? [
                  BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.4), offset: const Offset(3, 3), blurRadius: 6),
                  const BoxShadow(color: Colors.white, offset: Offset(-3, -3), blurRadius: 6)
                ]
              : [
                  BoxShadow(color: const Color(0xFFA3B1C6).withOpacity(0.6), offset: const Offset(8, 8), blurRadius: 16),
                  const BoxShadow(color: Colors.white, offset: Offset(-8, -8), blurRadius: 16)
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 좌측 상단 카드사 로고 & 이름
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
              const SizedBox(height: 14),
              
              // 배경과 동일한 색상의 뉴모피즘 스타일 '상세보기' 버튼
              Container(
                width: double.infinity,
                height: 48, 
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // 기존 배경색(0xFFE0E5EC)보다 한 톤 어두운 색상으로 쏙 들어간 느낌을 줍니다.
                  color: const Color(0xFFD1D9E6), 
                  borderRadius: BorderRadius.circular(16), 
                ),
                child: const Text(
                  '상세보기', 
                  style: TextStyle(
                    fontSize: 14, 
                    fontWeight: FontWeight.bold, 
                    color: Color(0xFF9098B1), // 텍스트도 튀지 않게 은은한 색상 유지
                  ),
                ),
              ),
            ],
          ),
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