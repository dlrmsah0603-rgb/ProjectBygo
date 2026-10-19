import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final int seedColorValue;
  final bool showTips;
  final bool autoResetOnScheduleTime;
  final bool showHomeWidgetPanel;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<int> onSeedColorChanged;
  final ValueChanged<bool> onShowTipsChanged;
  final ValueChanged<bool>? onAutoResetChanged;
  final ValueChanged<bool>? onShowHomeWidgetPanelChanged;
  final Future<String> Function()? onExportBackup;
  final Future<bool> Function(String jsonText)? onImportBackup;
  final VoidCallback? onResetData;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.seedColorValue,
    this.showTips = true,
    this.autoResetOnScheduleTime = true,
    this.showHomeWidgetPanel = false,
    required this.onThemeModeChanged,
    required this.onSeedColorChanged,
    required this.onShowTipsChanged,
    this.onAutoResetChanged,
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

  Future<void> _showExportDialog(BuildContext context) async {
    if (onExportBackup == null) return;
    HapticFeedback.selectionClick();
    final jsonText = await onExportBackup!();
    await Clipboard.setData(ClipboardData(text: jsonText));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('백업 데이터가 클립보드에 복사되었습니다.'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('데이터 백업 (내보내기)'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '아래 JSON 백업 코드가 클립보드에 복사되었습니다. 메모장이나 안전한 곳에 보관해 주세요.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonText,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: jsonText));
              if (!ctx.mounted) return;
              HapticFeedback.lightImpact();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('백업 데이터가 다시 복사되었습니다.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('다시 복사'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    if (onImportBackup == null) return;
    HapticFeedback.selectionClick();
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('데이터 불러오기 (복원)'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '백업해 둔 JSON 데이터를 아래에 붙여넣고 [복원하기]를 눌러주세요.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final clip = await Clipboard.getData(Clipboard.kTextPlain);
                    if (clip?.text != null) {
                      controller.text = clip!.text!;
                      HapticFeedback.selectionClick();
                    }
                  },
                  icon: const Icon(Icons.paste, size: 16),
                  label: const Text('클립보드에서 붙여넣기'),
                ),
              ),
              TextField(
                controller: controller,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: '{\n  "version": 1,\n  "schedules": [...]\n}',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final raw = controller.text.trim();
              if (raw.isEmpty) return;

              final success = await onImportBackup!(raw);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).clearSnackBars();
              if (success) {
                HapticFeedback.heavyImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('백업 데이터를 성공적으로 불러왔습니다! 🎉'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } else {
                HapticFeedback.vibrate();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('올바른 백업 데이터 형식이 아닙니다. 다시 확인해 주세요.'),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            icon: const Icon(Icons.restore, size: 18),
            label: const Text('복원하기'),
          ),
        ],
      ),
    );
  }

  void _confirmResetDialog(BuildContext context) {
    if (onResetData == null) return;
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 데이터 초기화'),
        content: const Text(
          '저장된 모든 일정과 외출 상황·체크리스트를 초기 기본 상태로 되돌리시겠습니까?\n(필요한 경우 먼저 데이터 백업을 진행해 주세요.)',
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
                    Icons.upload_file_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text(
                    '데이터 백업 (내보내기)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '현재 일정과 체크리스트 데이터를 JSON 코드로 클립보드에 복사합니다.',
                  ),
                  onTap: () => _showExportDialog(context),
                ),
              if (onImportBackup != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.download_for_offline_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text(
                    '데이터 불러오기 (복원)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    '백업해 둔 JSON 코드를 붙여넣어 일정과 체크리스트를 복구합니다.',
                  ),
                  onTap: () => _showImportDialog(context),
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
                    '전체 일정 및 체크리스트 초기화',
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