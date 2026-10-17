import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatelessWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final int themeColorValue;
  final ValueChanged<int> onThemeColorChanged;
  final bool showTips;
  final ValueChanged<bool> onShowTipsChanged;
  final VoidCallback onExportBackup;
  final VoidCallback onImportBackup;

  const SettingsScreen({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
    required this.themeColorValue,
    required this.onThemeColorChanged,
    required this.showTips,
    required this.onShowTipsChanged,
    required this.onExportBackup,
    required this.onImportBackup,
  });

  static const List<Map<String, dynamic>> _themeColors = [
    {'name': '인디고', 'color': Colors.indigo},
    {'name': '블루', 'color': Colors.blue},
    {'name': '틸', 'color': Colors.teal},
    {'name': '그린', 'color': Colors.green},
    {'name': '오렌지', 'color': Colors.orange},
    {'name': '퍼플', 'color': Colors.purple},
    {'name': '핑크', 'color': Colors.pink},
    {'name': '레드', 'color': Colors.red},
  ];

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '화면 및 테마',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                secondary: Icon(
                  isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: primaryColor,
                ),
                title: const Text(
                  '다크 모드',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  isDarkMode ? '어두운 화면 테마 사용 중' : '밝은 화면 테마 사용 중',
                ),
                value: isDarkMode,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  onDarkModeChanged(val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: Icon(
                  Icons.lightbulb_outline,
                  color: primaryColor,
                ),
                title: const Text(
                  '화면 상단 팁 표시',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('캘린더 및 상황 화면의 제스처 안내 배너 표시'),
                value: showTips,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  onShowTipsChanged(val);
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette_outlined, color: primaryColor),
                        const SizedBox(width: 16),
                        const Text(
                          '앱 테마 색상',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _themeColors.map((item) {
                        final Color color = item['color'] as Color;
                        final String label = item['name'] as String;
                        final int colorVal = color.toARGB32();
                        final bool isSelected = colorVal == themeColorValue;

                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onThemeColorChanged(colorVal);
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                          width: 3,
                                        )
                                      : null,
                                  boxShadow: [
                                    if (isSelected)
                                      BoxShadow(
                                        color: color.withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                  ],
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 22,
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '데이터 백업 및 복원',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.download_outlined, color: primaryColor),
                title: const Text(
                  '백업 파일 저장 (.json)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('현재 일정과 외출 상황·소지품 목록을 파일로 내보냅니다'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onExportBackup,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.upload_file_outlined, color: primaryColor),
                title: const Text(
                  '백업 파일 불러오기 (.json)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('저장해 둔 백업 파일을 선택해 데이터를 복원합니다'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onImportBackup,
              ),
            ],
          ),
        ),
      ],
    );
  }
}