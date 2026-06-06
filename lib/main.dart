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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF191919),
      ),
      home: const MultiCardScreen(),
    );
  }
}

class MultiCardScreen extends StatelessWidget {
  const MultiCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            const Text('내 플랜', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('요약', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_horiz, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          children: [
            // 1. 한 달이 얼마나 지났는지 보여주는 상단 선
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbColor: Colors.white,
                activeTrackColor: Colors.grey[600], // 지나간 시간
                inactiveTrackColor: Colors.white, // 남은 시간
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value: 0.3, // 0.0 ~ 1.0 사이 (예: 한 달의 30% 지남)
                onChanged: (val) {},
              ),
            ),
            const SizedBox(height: 40),

            // 2. 4개의 카드를 보여주는 2x2 그리드
            Expanded(
              child: Column(
                children: [
                  // 첫 번째 줄
                  Expanded(
                    child: Row(
                      children: [
                        // 정상 지출 상태 (15만원 중 10만 6천원 사용)
                        Expanded(child: _buildCardItem('신한카드', 106500, 150000)),
                        // 🚨 예산 초과 상태 (15만원 중 17만원 사용) - 빨간색으로 초과분 표시됨
                        Expanded(child: _buildCardItem('국민카드', 170000, 150000)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 두 번째 줄
                  Expanded(
                    child: Row(
                      children: [
                        // 지출이 적은 상태
                        Expanded(child: _buildCardItem('하나카드', 35000, 150000)),
                        // 딱 맞게 쓴 상태
                        Expanded(child: _buildCardItem('롯데카드', 150000, 150000)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 숫자를 한국 돈 표기법(콤마)으로 바꿔주는 헬퍼 함수
  String _formatCurrency(int amount) {
    return amount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
  }

  // 붕어빵 틀: 카드 원형 그래프 생성기
  Widget _buildCardItem(String cardName, int spent, int total) {
    // 정상 지출 비율 (최대 1.0 즉 100%까지만 파란색으로 채움)
    double normalRatio = (spent / total).clamp(0.0, 1.0);
    // 초과 지출 비율 (예산을 넘은 경우만 계산, 안 넘었으면 0)
    double overRatio = spent > total ? ((spent - total) / total).clamp(0.0, 1.0) : 0.0;
    
    // 예산을 넘었는지 확인하는 스위치
    bool isOverBudget = spent > total;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. 기본 배경 원 (어두운 회색)
              const SizedBox(
                width: 150,
                height: 150,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 8,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2C2C2E)),
                ),
              ),
              // 2. 정상 지출 원 (파란색)
              SizedBox(
                width: 150,
                height: 150,
                child: CircularProgressIndicator(
                  value: normalRatio,
                  strokeWidth: 8,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2F80ED)),
                ),
              ),
              // 3. 초과 지출 원 (빨간색) - 초과율이 0보다 클 때만 그 위에 덮어씌움
              if (overRatio > 0)
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CircularProgressIndicator(
                    value: overRatio,
                    strokeWidth: 8,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF453A)), // 강렬한 빨간색
                  ),
                ),
                
              // 원 안쪽 텍스트
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isOverBudget ? '초과 지출!' : '지출 금액', 
                    style: TextStyle(fontSize: 10, color: isOverBudget ? const Color(0xFFFF453A) : Colors.grey, fontWeight: isOverBudget ? FontWeight.bold : FontWeight.normal)
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${_formatCurrency(spent)}원', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      Icon(Icons.chevron_right, size: 16, color: Colors.grey[600]),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('/ ${_formatCurrency(total)}원', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // 하단 카드 이름 버튼
        Container(
          width: 110,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            // 초과 지출 시 버튼 색상도 약간 붉은빛이 돌게 경고를 줄 수 있습니다. (현재는 파란색 유지)
            color: const Color(0xFF2F80ED),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            cardName,
            style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}