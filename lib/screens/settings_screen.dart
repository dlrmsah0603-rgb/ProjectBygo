import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final int seedColorValue;
  final bool showTips;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<int> onSeedColorChanged;
  final ValueChanged<bool> onShowTipsChanged;
  final VoidCallback? onResetData;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.seedColorValue,
    this.showTips = true,
    required this.onThemeModeChanged,
    required this.onSeedColorChanged,
    required this.onShowTipsChanged,
    this.onResetData,
  });

  // 0xFF000000 = 블랙 앤 화이트 테마 식별 코드
  static const int blackAndWhiteColorValue = 0xFF000000;

  static final List<MapEntry<String, int>> _themeColorOptions = [
    const MapEntry('블랙 앤 화이트', blackAndWhiteColorValue),
    MapEntry('인디고', Colors.indigo.toARGB32()),
    MapEntry('블루', Colors.blue.toARGB32()),
    MapEntry('그린', Colors.green.toARGB32()),
    MapEntry('오렌지', Colors.orange.toARGB32()),
    MapEntry('퍼플', Colors.purple.toARGB32()),
    MapEntry('틸', Colors.teal.toARGB32()),
    MapEntry('핑크', Colors.pink.toARGB32()),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '화면 모드',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto),
                      label: Text('시스템'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode),
                      label: Text('라이트'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode),
                      label: Text('다크'),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) {
                    HapticFeedback.selectionClick();
                    onThemeModeChanged(selection.first);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '앱 테마 색상',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _themeColorOptions.map((entry) {
                    final label = entry.key;
                    final colorVal = entry.value;
                    final isSelected = seedColorValue == colorVal;
                    final isBW = colorVal == blackAndWhiteColorValue;

                    return ChoiceChip(
                      avatar: isBW
                          ? Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey),
                                gradient: const LinearGradient(
                                  colors: [Colors.black, Colors.white],
                                  stops: [0.5, 0.5],
                                ),
                              ),
                            )
                          : CircleAvatar(
                              backgroundColor: Color(colorVal),
                              radius: 9,
                            ),
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        onSeedColorChanged(colorVal);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SwitchListTile(
            title: const Text(
              '화면 상단 사용 팁 표시',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              '캘린더 및 체크리스트 화면 상단의 조작 안내 팁을 표시합니다.',
            ),
            value: showTips,
            onChanged: (val) {
              HapticFeedback.selectionClick();
              onShowTipsChanged(val);
            },
          ),
        ),
        if (onResetData != null) ...[
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.restore_outlined,
                color: Colors.redAccent,
              ),
              title: const Text(
                '전체 일정 및 체크리스트 초기화',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('초기 기본 데이터 상태로 되돌립니다.'),
              onTap: onResetData,
            ),
          ),
        ],
      ],
    );
  }
}