import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final int seedColorValue;
  final bool showTips;
  final bool autoResetOnScheduleTime;
  final bool autoResetDaily;
  final String dailyResetTime;
  final bool showHomeWidgetPanel;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<int> onSeedColorChanged;
  final ValueChanged<bool> onShowTipsChanged;
  final ValueChanged<bool>? onAutoResetChanged;
  final ValueChanged<bool>? onAutoResetDailyChanged;
  final ValueChanged<String>? onDailyResetTimeChanged;
  final ValueChanged<bool>? onShowHomeWidgetPanelChanged;
  final Future<String> Function()? onExportBackup;
  final Future<bool?> Function()? onImportBackup;
  final VoidCallback? onResetData;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.seedColorValue,
    this.showTips = true,
    this.autoResetOnScheduleTime = true,
    this.autoResetDaily = true,
    this.dailyResetTime = '00:00',
    this.showHomeWidgetPanel = false,
    required this.onThemeModeChanged,
    required this.onSeedColorChanged,
    required this.onShowTipsChanged,
    this.onAutoResetChanged,
    this.onAutoResetDailyChanged,
    this.onDailyResetTimeChanged,
    this.onShowHomeWidgetPanelChanged,
    this.onExportBackup,
    this.onImportBackup,
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

  int get _selectedResetHour {
    final parts = dailyResetTime.split(':');
    return (int.tryParse(parts.firstOrNull ?? '0') ?? 0).clamp(0, 23);
  }

  String _formatHourLabel(int hour) {
    if (hour == 0) return '0시 (자정)';
    if (hour == 12) return '12시 (정오)';
    return '$hour시';
  }

  Future<void> _handleExportBackupFile(BuildContext context) async {
    if (onExportBackup == null) return;
    HapticFeedback.selectionClick();

    try {
      final savedPath = await onExportBackup!();
      if (!context.mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('다운로드 폴더에 백업 파일이 저장되었습니다.\n($savedPath)'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('백업 파일 저장 실패: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleImportBackupFile(BuildContext context) async {
    if (onImportBackup == null) return;
    HapticFeedback.selectionClick();

    try {
      final result = await onImportBackup!();
      if (result == null || !context.mounted) return; // 사용자가 파일 선택 취소

      ScaffoldMessenger.of(context).clearSnackBars();
      if (result) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('백업 파일에서 데이터를 성공적으로 복원했습니다! 🎉'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        HapticFeedback.vibrate();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('올바른 백업 파일 형식이 아닙니다. 다시 확인해 주세요.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('파일 불러오기 실패: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmResetDialog(BuildContext context) {
    if (onResetData == null) return;
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 데이터 초기화'),
        content: const Text(
          '저장된 모든 일정, 할 일, 외출 상황·체크리스트를 초기 기본 상태로 되돌리시겠습니까?\n(필요한 경우 먼저 데이터 백업을 진행해 주세요.)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onResetData!();
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('전체 데이터가 초기 상태로 초기화되었습니다.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('초기화'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentHour = _selectedResetHour;

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
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.schedule_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text(
                  '하루 시작 시간 (일일 초기화 기준)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  '상황 체크리스트 일괄 리셋 및 반복 할 일의 다음 주기 복귀 시각에 공통 적용됩니다.',
                ),
                trailing: DropdownButtonHideUnderline(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.4),
                      ),
                    ),
                    child: DropdownButton<int>(
                      value: currentHour,
                      isDense: true,
                      items: List.generate(24, (h) {
                        return DropdownMenuItem<int>(
                          value: h,
                          child: Text(
                            _formatHourLabel(h),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }),
                      onChanged: (selectedHour) {
                        if (selectedHour == null) return;
                        HapticFeedback.selectionClick();
                        final formatted =
                            '${selectedHour.toString().padLeft(2, '0')}:00';
                        onDailyResetTimeChanged?.call(formatted);
                      },
                    ),
                  ),
                ),
              ),
              /*
              const Divider(height: 1),
              SwitchListTile(
                title: Text(
                  '하루 시작 시간(${_formatHourLabel(currentHour)})에 상황 체크리스트 자동 초기화',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  '일정 유무와 관계없이 매일 지정된 하루 시작 시간이 지나면 모든 상황 체크리스트를 일괄 리셋합니다.',
                ),
                value: autoResetDaily,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  onAutoResetDailyChanged?.call(val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text(
                  '일정 시간 정각에 체크리스트 자동 초기화',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  '해당 일정 시간이 되면 체크 여부에 관계없이 연결된 체크리스트를 초기 상태로 리셋합니다.',
                ),
                value: autoResetOnScheduleTime,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  onAutoResetChanged?.call(val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text(
                  '홈 화면 위젯 패널 표시',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  '준비시간 ~ 일정 시간 내의 공유 체크리스트 위젯을 화면 상단에 고정 표시합니다.',
                ),
                value: showHomeWidgetPanel,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  onShowHomeWidgetPanelChanged?.call(val);
                },
              ),
              */
              const Divider(height: 1),
              SwitchListTile(
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
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  '데이터 백업 및 관리',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (onExportBackup != null)
                ListTile(
                  leading: Icon(
                    Icons.download_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text(
                    '데이터 백업 (파일로 저장)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '현재 일정, 할 일, 체크리스트 데이터를 기본 다운로드 폴더에 JSON 파일로 저장합니다.',
                  ),
                  onTap: () => _handleExportBackupFile(context),
                ),
              if (onImportBackup != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.folder_open_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text(
                    '데이터 불러오기 (파일에서 복원)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '저장해 둔 백업 JSON 파일을 선택하여 데이터를 복구합니다.',
                  ),
                  onTap: () => _handleImportBackupFile(context),
                ),
              ],
              if (onResetData != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.restore_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    '전체 일정·할 일·체크리스트 초기화',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text('초기 기본 데이터 상태로 되돌립니다.'),
                  onTap: () => _confirmResetDialog(context),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}