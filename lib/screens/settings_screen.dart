import '../services/notification_service.dart';
import '../models/schedule_model.dart';
import '../models/situation_model.dart';
import '../models/todo_model.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/google_sync_service.dart';

class SettingsScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final int seedColorValue;
  final bool? isDarkMode;
  final int? themeColorValue;
  final List<Schedule> schedules;
  final List<Situation> situations;
  final List<TodoItem> todos;

  final bool showTips;
  final bool autoResetOnScheduleTime;
  final bool autoResetDaily;
  final String dailyResetTime;
  final bool showHomeWidgetPanel;

  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<bool>? onDarkModeChanged;
  final ValueChanged<int>? onSeedColorChanged;
  final ValueChanged<int>? onThemeColorChanged;
  final ValueChanged<bool> onShowTipsChanged;
  final ValueChanged<bool>? onAutoResetChanged;
  final ValueChanged<bool>? onAutoResetDailyChanged;
  final ValueChanged<String>? onDailyResetTimeChanged;
  final ValueChanged<bool>? onShowHomeWidgetPanelChanged;

  // 구글 개별 연동 상태 및 콜백 (선택적 전달 지원)
  final bool? isGoogleCalendarSynced;
  final ValueChanged<bool>? onGoogleCalendarSyncChanged;
  final bool? isGoogleTasksSynced;
  final ValueChanged<bool>? onGoogleTasksSyncChanged;
  final String? googleConnectedEmail;

  // 0인자 파일 백업 함수와 1인자 JSON 문자열 백업 함수를 모두 수용하도록 Function? 선언
  final Function? onExportBackup;
  final Function? onImportBackup;
  final VoidCallback? onResetData;
  final VoidCallback? onClearAllData;

  const SettingsScreen({
    super.key,
    this.themeMode = ThemeMode.system,
    this.seedColorValue = 0xFF3F51B5,
    this.isDarkMode,
    this.themeColorValue,
    this.schedules = const [],
    this.situations = const [],
    this.todos = const [],
    this.showTips = true,
    this.autoResetOnScheduleTime = true,
    this.autoResetDaily = true,
    this.dailyResetTime = '00:00',
    this.showHomeWidgetPanel = false,
    this.onThemeModeChanged,
    this.onDarkModeChanged,
    this.onSeedColorChanged,
    this.onThemeColorChanged,
    required this.onShowTipsChanged,
    this.onAutoResetChanged,
    this.onAutoResetDailyChanged,
    this.onDailyResetTimeChanged,
    this.onShowHomeWidgetPanelChanged,
    this.isGoogleCalendarSynced,
    this.onGoogleCalendarSyncChanged,
    this.isGoogleTasksSynced,
    this.onGoogleTasksSyncChanged,
    this.googleConnectedEmail,
    this.onExportBackup,
    this.onImportBackup,
    this.onResetData,
    this.onClearAllData,
  });

  // 0xFF000000 = 블랙 앤 화이트 테마 식별 코드
  static const int blackAndWhiteColorValue = 0xFF000000;

  static const String prefKeyGoogleCalSync = 'bygo_google_calendar_sync_enabled';
  static const String prefKeyGoogleTaskSync = 'bygo_google_tasks_sync_enabled';
  static const String prefKeyGoogleDriveSync = 'bygo_google_drive_sync_enabled';
  static const String prefKeyGoogleEmail = 'bygo_google_connected_email';
  static const String prefKeyDailyResetTime = 'bygo_daily_reset_time';
  static const String prefKeyAutoResetDaily = 'bygo_auto_reset_daily';

  /// 캘린더 화면과 할 일 화면에서 동기화(🔄) 버튼 표시 여부를 실시간 구독하기 위한 Notifier
  static final ValueNotifier<bool> googleCalendarSyncNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> googleTasksSyncNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> googleDriveSyncNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<String?> googleEmailNotifier =
      ValueNotifier<String?>(null);

  static bool _prefsInitialized = false;

  static Future<void> ensureSyncPrefsLoaded() async {
    if (_prefsInitialized) return;
    _prefsInitialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString(prefKeyGoogleEmail);
      // 과거 모의 이메일(bygo.local.sync@gmail.com)이나 이메일 없는 상태 정리
      if (savedEmail == null ||
          savedEmail.trim().isEmpty ||
          savedEmail == 'bygo.local.sync@gmail.com') {
        await prefs.remove(prefKeyGoogleEmail);
        await prefs.setBool(prefKeyGoogleCalSync, false);
        await prefs.setBool(prefKeyGoogleTaskSync, false);
        await prefs.setBool(prefKeyGoogleDriveSync, false);
        googleEmailNotifier.value = null;
        googleCalendarSyncNotifier.value = false;
        googleTasksSyncNotifier.value = false;
        googleDriveSyncNotifier.value = false;
        return;
      }
      googleEmailNotifier.value = savedEmail;
      googleCalendarSyncNotifier.value =
          prefs.getBool(prefKeyGoogleCalSync) ?? false;
      googleTasksSyncNotifier.value =
          prefs.getBool(prefKeyGoogleTaskSync) ?? false;
      googleDriveSyncNotifier.value =
          prefs.getBool(prefKeyGoogleDriveSync) ?? false;
    } catch (_) {}
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ignore: unused_field
  late bool _scheduleNotifsEnabled;
  late bool _todoNotifsEnabled;
  // ignore: unused_field
  late bool _localAutoResetDaily;
  late String _localDailyResetTime;
  bool _isAuthBusy = false;

  static final List<MapEntry<String, int>> _themeColorOptions = [
    const MapEntry('블랙 앤 화이트', SettingsScreen.blackAndWhiteColorValue),
    MapEntry('인디고', Colors.indigo.toARGB32()),
    MapEntry('블루', Colors.blue.toARGB32()),
    MapEntry('그린', Colors.green.toARGB32()),
    MapEntry('오렌지', Colors.orange.toARGB32()),
    MapEntry('퍼플', Colors.purple.toARGB32()),
    MapEntry('틸', Colors.teal.toARGB32()),
    MapEntry('핑크', Colors.pink.toARGB32()),
  ];

  static final List<String> _hourOptions = List.generate(
    24,
    (h) => '${h.toString().padLeft(2, '0')}:00',
  );

  @override
  void initState() {
    super.initState();
    _scheduleNotifsEnabled = NotificationService.instance.scheduleNotificationsEnabled;
    _todoNotifsEnabled = NotificationService.instance.todoNotificationsEnabled;
    _localAutoResetDaily = widget.autoResetDaily;
    _localDailyResetTime = widget.dailyResetTime;
    _loadLocalPrefs();
  }

  Future<void> _loadLocalPrefs() async {
    await SettingsScreen.ensureSyncPrefsLoaded();
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDaily = prefs.getBool(SettingsScreen.prefKeyAutoResetDaily);
      final savedTime = prefs.getString(SettingsScreen.prefKeyDailyResetTime);
      if (!mounted) return;
      setState(() {
        if (savedDaily != null) _localAutoResetDaily = savedDaily;
        if (savedTime != null && _hourOptions.contains(savedTime)) {
          _localDailyResetTime = savedTime;
        }
      });
    } catch (_) {}
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isAuthBusy) return;
    HapticFeedback.selectionClick();

    setState(() => _isAuthBusy = true);
    try {
      final email = await GoogleSyncService.instance.signIn();
      if (email == null) {
        if (!mounted) return;
        final errorMsg =
            GoogleSyncService.instance.lastAuthError ?? '구글 로그인에 실패했습니다.';
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SettingsScreen.prefKeyGoogleEmail, email);
      SettingsScreen.googleEmailNotifier.value = email;

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google 계정($email)으로 로그인되었습니다. 원하는 연동 기능을 켜 주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }
  }

  Future<void> _handleGoogleSignOut() async {
    if (_isAuthBusy) return;
    HapticFeedback.selectionClick();

    setState(() => _isAuthBusy = true);
    try {
      await GoogleSyncService.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SettingsScreen.prefKeyGoogleCalSync, false);
      await prefs.setBool(SettingsScreen.prefKeyGoogleTaskSync, false);
      await prefs.setBool(SettingsScreen.prefKeyGoogleDriveSync, false);
      await prefs.remove(SettingsScreen.prefKeyGoogleEmail);

      SettingsScreen.googleCalendarSyncNotifier.value = false;
      SettingsScreen.googleTasksSyncNotifier.value = false;
      SettingsScreen.googleDriveSyncNotifier.value = false;
      SettingsScreen.googleEmailNotifier.value = null;

      widget.onGoogleCalendarSyncChanged?.call(false);
      widget.onGoogleTasksSyncChanged?.call(false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google 계정에서 로그아웃되었습니다. (로컬 데이터 유지)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }
  }

  Future<void> _handleCalendarSyncToggle(bool enabled) async {
    if (_isAuthBusy) return;
    HapticFeedback.selectionClick();

    setState(() => _isAuthBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (enabled) {
        final scopeOk = await GoogleSyncService.instance
            .ensureScope(GoogleSyncService.calendarScope);
        if (!scopeOk) {
          SettingsScreen.googleCalendarSyncNotifier.value = false;
          await prefs.setBool(SettingsScreen.prefKeyGoogleCalSync, false);
          if (!mounted) return;
          final err = GoogleSyncService.instance.lastAuthError ??
              '캘린더 접근 권한이 허용되지 않아 연동이 취소되었습니다.';
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        SettingsScreen.googleCalendarSyncNotifier.value = true;
        await prefs.setBool(SettingsScreen.prefKeyGoogleCalSync, true);
        widget.onGoogleCalendarSyncChanged?.call(true);

        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google 캘린더 연동이 활성화되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        GoogleSyncService.instance.removeScope(GoogleSyncService.calendarScope);
        SettingsScreen.googleCalendarSyncNotifier.value = false;
        await prefs.setBool(SettingsScreen.prefKeyGoogleCalSync, false);
        widget.onGoogleCalendarSyncChanged?.call(false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google 캘린더 연동이 해제되었습니다. (로컬 일정 유지)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }
  }

  Future<void> _handleTasksSyncToggle(bool enabled) async {
    if (_isAuthBusy) return;
    HapticFeedback.selectionClick();

    setState(() => _isAuthBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (enabled) {
        final scopeOk = await GoogleSyncService.instance
            .ensureScope(GoogleSyncService.tasksScope);
        if (!scopeOk) {
          SettingsScreen.googleTasksSyncNotifier.value = false;
          await prefs.setBool(SettingsScreen.prefKeyGoogleTaskSync, false);
          if (!mounted) return;
          final err = GoogleSyncService.instance.lastAuthError ??
              '태스크 접근 권한이 허용되지 않아 연동이 취소되었습니다.';
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        SettingsScreen.googleTasksSyncNotifier.value = true;
        await prefs.setBool(SettingsScreen.prefKeyGoogleTaskSync, true);
        widget.onGoogleTasksSyncChanged?.call(true);

        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google 태스크 연동이 활성화되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        GoogleSyncService.instance.removeScope(GoogleSyncService.tasksScope);
        SettingsScreen.googleTasksSyncNotifier.value = false;
        await prefs.setBool(SettingsScreen.prefKeyGoogleTaskSync, false);
        widget.onGoogleTasksSyncChanged?.call(false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google 태스크 연동이 해제되었습니다. (로컬 할 일 유지)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }
  }

  Future<void> _handleDriveBackupToggle(bool enabled) async {
    if (_isAuthBusy) return;
    HapticFeedback.selectionClick();

    setState(() => _isAuthBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (enabled) {
        final scopeOk = await GoogleSyncService.instance
            .ensureScope(GoogleSyncService.driveAppDataScope);
        if (!scopeOk) {
          SettingsScreen.googleDriveSyncNotifier.value = false;
          await prefs.setBool(SettingsScreen.prefKeyGoogleDriveSync, false);
          if (!mounted) return;
          final err = GoogleSyncService.instance.lastAuthError ??
              '드라이브 앱데이터 접근 권한이 허용되지 않아 백업 활성화가 취소되었습니다.';
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(err),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        SettingsScreen.googleDriveSyncNotifier.value = true;
        await prefs.setBool(SettingsScreen.prefKeyGoogleDriveSync, true);

        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google 드라이브 자동 백업이 활성화되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        GoogleSyncService.instance
            .removeScope(GoogleSyncService.driveAppDataScope);
        SettingsScreen.googleDriveSyncNotifier.value = false;
        await prefs.setBool(SettingsScreen.prefKeyGoogleDriveSync, false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google 드라이브 자동 백업이 비활성화되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }
  }

  Future<void> _handleManualDriveBackup() async {
    if (_isAuthBusy) return;
    HapticFeedback.selectionClick();
    setState(() => _isAuthBusy = true);

    try {
      final scopeOk = await GoogleSyncService.instance
          .ensureScope(GoogleSyncService.driveAppDataScope);
      if (!scopeOk) {
        if (!mounted) return;
        final err = GoogleSyncService.instance.lastAuthError ??
            '드라이브 접근 권한이 허용되지 않았습니다.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final backupJson = widget.onExportBackup != null
          ? await (widget.onExportBackup!() as Future<String>)
          : null;

      if (backupJson == null || backupJson.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('백업할 데이터가 없습니다.')),
        );
        return;
      }

      final fileId = await GoogleSyncService.instance.backupJsonToDrive(
        jsonContent: backupJson,
      );

      if (!mounted) return;
      if (fileId != null) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Google 드라이브(앱데이터)에 안전하게 백업되었습니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('드라이브 백업 중 오류가 발생했습니다. 네트워크 및 권한을 확인해 주세요.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }
  }

  Future<void> _handleRestoreFromDriveDialog() async {
    if (_isAuthBusy) return;
    HapticFeedback.selectionClick();
    setState(() => _isAuthBusy = true);

    List<DriveBackupInfo> backups = [];
    try {
      final scopeOk = await GoogleSyncService.instance
          .ensureScope(GoogleSyncService.driveAppDataScope);
      if (!scopeOk) {
        if (!mounted) return;
        final err = GoogleSyncService.instance.lastAuthError ??
            '드라이브 접근 권한이 허용되지 않았습니다.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      backups = await GoogleSyncService.instance.listDriveBackups();
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }

    if (!mounted) return;
    if (backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google 드라이브에 저장된 백업 파일이 없습니다.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_download_outlined),
            SizedBox(width: 8),
            Text('드라이브 백업 복원'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('복원할 백업 버전을 선택해 주세요 (최대 5개 보관):'),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: backups.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final item = backups[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(item.formattedDate,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${item.fileName} (${(item.sizeBytes / 1024).toStringAsFixed(1)} KB)'),
                      onTap: () async {
                        Navigator.pop(dialogCtx);
                        await _performRestoreFromDrive(item.id);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  Future<void> _performRestoreFromDrive(String fileId) async {
    setState(() => _isAuthBusy = true);
    try {
      final jsonStr = await GoogleSyncService.instance.downloadDriveBackupJson(fileId);
      if (jsonStr == null || jsonStr.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('백업 데이터를 다운로드하지 못했습니다.')),
        );
        return;
      }

      if (widget.onImportBackup != null) {
        final success = await widget.onImportBackup!(jsonStr);
        if (!mounted) return;
        if (success == true) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Google 드라이브 백업에서 성공적으로 복원되었습니다.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('백업 파일 형식이 올바르지 않습니다.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isAuthBusy = false);
    }
  }

  Future<String> _writeJsonToDownloads(String jsonText) async {
    final bytes = utf8.encode(jsonText);
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final fileName = 'bygo_backup_$stamp.json';

    Directory? dir;
    try {
      if (Platform.isAndroid) {
        final androidDown = Directory('/storage/emulated/0/Download');
        if (await androidDown.exists()) dir = androidDown;
      }
      dir ??= await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();

    final sep = Platform.pathSeparator;
    final file = File('${dir.path}$sep$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _handleExportBackupTap(BuildContext context) async {
    if (widget.onExportBackup == null) return;
    HapticFeedback.selectionClick();

    try {
      final result = await Function.apply(widget.onExportBackup!, const []);
      if (!context.mounted) return;

      if (result is String && result.trim().isNotEmpty) {
        final trimmed = result.trim();
        // 반환값이 JSON 문자열인 경우 다운로드 폴더에 파일로 자동 저장
        if (trimmed.startsWith('{')) {
          final savedPath = await _writeJsonToDownloads(trimmed);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('백업 파일이 다운로드 폴더에 저장되었습니다:\n$savedPath'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('백업 파일이 저장되었습니다:\n$trimmed'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('백업 중 오류가 발생했습니다: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleImportBackupTap(BuildContext context) async {
    if (widget.onImportBackup == null) return;
    HapticFeedback.selectionClick();

    try {
      bool? success;
      final fn = widget.onImportBackup!;

      // 0인자 함수(내부에서 FilePicker를 여는 경우)인지 1인자 함수(JSON 문자열을 받는 경우)인지 판별
      if (fn is Future<bool?> Function() ||
          fn is Future<bool> Function() ||
          fn is void Function()) {
        final res = await Function.apply(fn, const []);
        success = res is bool ? res : true;
      } else {
        final picked = await FilePicker.platform.pickFiles(
          dialogTitle: '복원할 Bygo 백업(.json) 파일 선택',
          type: FileType.custom,
          allowedExtensions: ['json'],
          withData: true,
        );
        if (picked == null || picked.files.isEmpty) return;

        final file = picked.files.single;
        String rawJson;
        if (file.path != null) {
          rawJson = await File(file.path!).readAsString(encoding: utf8);
        } else if (file.bytes != null) {
          rawJson = utf8.decode(file.bytes!);
        } else {
          return;
        }
        final res = await Function.apply(fn, [rawJson]);
        success = res is bool ? res : true;
      }

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('백업 복원이 취소되었거나 올바른 파일 형식이 아닙니다.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('복원 중 오류가 발생했습니다: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmResetDialog(BuildContext context) {
    final resetCallback = widget.onResetData ?? widget.onClearAllData;
    if (resetCallback == null) return;
    HapticFeedback.mediumImpact();

    showDialog<void>(
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
              resetCallback();
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
    final effectiveColorValue = widget.themeColorValue ?? widget.seedColorValue;

    return ValueListenableBuilder<bool>(
      valueListenable: SettingsScreen.googleCalendarSyncNotifier,
      builder: (context, notifierCalSynced, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: SettingsScreen.googleTasksSyncNotifier,
          builder: (context, notifierTaskSynced, _) {
            return ValueListenableBuilder<String?>(
              valueListenable: SettingsScreen.googleEmailNotifier,
              builder: (context, notifierEmail, _) {
                // ignore: unused_local_variable
                final calSynced =
                    widget.isGoogleCalendarSynced ?? notifierCalSynced;
                // ignore: unused_local_variable
                final taskSynced =
                    widget.isGoogleTasksSynced ?? notifierTaskSynced;
                // ignore: unused_local_variable
                final connectedEmail = widget.googleConnectedEmail ??
                    notifierEmail ??
                    GoogleSyncService.instance.connectedEmail;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                                        // --- 1. 외부 계정 연동 및 클라우드 백업 카드 ---
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cloud_sync_outlined,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Google 연동 및 클라우드 백업',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (_isAuthBusy)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (connectedEmail == null) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Google 계정으로 로그인하면 캘린더·태스크 양방향 동기화 및 드라이브 자동 백업 기능을 사용할 수 있습니다.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.login_rounded, size: 18),
                                  label: const Text(
                                    'Google 계정으로 로그인',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  onPressed:
                                      _isAuthBusy ? null : _handleGoogleSignIn,
                                ),
                              ),
                            ),
                          ] else ...[
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 12, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Chip(
                                        avatar: const Icon(
                                          Icons.account_circle,
                                          size: 18,
                                        ),
                                        label: Text(
                                          connectedEmail,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _isAuthBusy
                                        ? null
                                        : _handleGoogleSignOut,
                                    icon: const Icon(
                                      Icons.logout_rounded,
                                      size: 16,
                                      color: Colors.redAccent,
                                    ),
                                    label: const Text(
                                      '로그아웃',
                                      style: TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              secondary:
                                  const Icon(Icons.calendar_month_outlined),
                              title: const Text(
                                'Google 캘린더 연동',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: const Text(
                                '일정·반복(RRULE)·상황/태그 메타데이터를 양방향 동기화하며, 활성화 시 캘린더 화면 상단에 동기화 버튼이 표시됩니다.',
                              ),
                              value: calSynced,
                              onChanged: _isAuthBusy
                                  ? null
                                  : _handleCalendarSyncToggle,
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              secondary: const Icon(Icons.task_alt_outlined),
                              title: const Text(
                                'Google 태스크 연동',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: const Text(
                                '기본 할 일 목록(@default)과 시간·세부항목(Notes)을 양방향 동기화하며, 활성화 시 할 일 화면 상단에 동기화 버튼이 표시됩니다.',
                              ),
                              value: taskSynced,
                              onChanged:
                                  _isAuthBusy ? null : _handleTasksSyncToggle,
                            ),
                            const Divider(height: 1),
                            ValueListenableBuilder<bool>(
                              valueListenable:
                                  SettingsScreen.googleDriveSyncNotifier,
                              builder: (ctx, driveSynced, _) => Column(
                                children: [
                                  SwitchListTile(
                                    secondary: const Icon(
                                        Icons.add_to_drive_outlined),
                                    title: const Text(
                                      'Google 드라이브 자동 백업',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: const Text(
                                      '드라이브 숨김 앱폴더에 매일 1회 안전하게 백업합니다 (최신 5개 버전 보관).',
                                    ),
                                    value: driveSynced,
                                    onChanged: _isAuthBusy
                                        ? null
                                        : _handleDriveBackupToggle,
                                  ),
                                  if (driveSynced)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 4, 16, 12),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              icon: const Icon(
                                                  Icons.cloud_upload_outlined,
                                                  size: 18),
                                              label:
                                                  const Text('지금 드라이브에 백업'),
                                              onPressed: _isAuthBusy
                                                  ? null
                                                  : _handleManualDriveBackup,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              icon: const Icon(
                                                  Icons.history_outlined,
                                                  size: 18),
                                              label: const Text('드라이브에서 복원'),
                                              onPressed: _isAuthBusy
                                                  ? null
                                                  : _handleRestoreFromDriveDialog,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // --- 2. 화면 모드 카드 ---
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
                              selected: {widget.themeMode},
                              onSelectionChanged: (selection) {
                                HapticFeedback.selectionClick();
                                final mode = selection.first;
                                widget.onThemeModeChanged?.call(mode);
                                widget.onDarkModeChanged
                                    ?.call(mode == ThemeMode.dark);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // --- 3. 앱 테마 색상 카드 ---
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
                                final isSelected =
                                    effectiveColorValue == colorVal;
                                final isBW = colorVal ==
                                    SettingsScreen.blackAndWhiteColorValue;

                                return ChoiceChip(
                                  avatar: isBW
                                      ? Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border:
                                                Border.all(color: Colors.grey),
                                            gradient: const LinearGradient(
                                              colors: [
                                                Colors.black,
                                                Colors.white
                                              ],
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
                                    widget.onSeedColorChanged?.call(colorVal);
                                    widget.onThemeColorChanged?.call(colorVal);
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // --- 4. 하루 시작 시간 및 자동 초기화 설정 카드 ---
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.wb_twilight_outlined),
                            title: const Text(
                              '하루 시작 시간 (일괄 초기화 기준 시각)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              '매일 상황 체크리스트 일괄 리셋 및 완료된 반복 할 일의 재활성화 기준 시각입니다.',
                            ),
                            trailing: DropdownButton<String>(
                              value: _hourOptions.contains(_localDailyResetTime)
                                  ? _localDailyResetTime
                                  : '05:00',
                              onChanged: (val) async {
                                if (val == null) return;
                                HapticFeedback.selectionClick();
                                setState(() => _localDailyResetTime = val);
                                widget.onDailyResetTimeChanged?.call(val);
                                try {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setString(
                                      SettingsScreen.prefKeyDailyResetTime,
                                      val);
                                } catch (_) {}
                              },
                              items: _hourOptions
                                  .map((h) => DropdownMenuItem(
                                        value: h,
                                        child: Text(h),
                                      ))
                                  .toList(),
                            ),
                          ),
                          const Divider(height: 1),
                          /*
                          SwitchListTile(
                            title: Text(
                              '매일 하루 시작 시간($_localDailyResetTime)에 전체 상황 체크리스트 초기화',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              '일정 유무와 관계없이 매일 지정된 하루 시작 시간이 지나면 모든 상황 체크리스트를 일괄 리셋합니다.',
                            ),
                            value: _localAutoResetDaily,
                            onChanged: (val) async {
                              HapticFeedback.selectionClick();
                              setState(() => _localAutoResetDaily = val);
                              widget.onAutoResetDailyChanged?.call(val);
                              try {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setBool(
                                    SettingsScreen.prefKeyAutoResetDaily, val);
                              } catch (_) {}
                            },
                          ),
                          const Divider(height: 1),
                          */
                          /*
                          SwitchListTile(
                            title: const Text(
                              '일정 시간 정각에 체크리스트 자동 초기화',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              '해당 일정 시간이 되면 체크 여부에 관계없이 연결된 체크리스트를 초기 상태로 리셋합니다.',
                            ),
                            value: widget.autoResetOnScheduleTime,
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              widget.onAutoResetChanged?.call(val);
                            },
                          ),
                          const Divider(height: 1),
                          */
                          /*
                          SwitchListTile(
                            title: const Text(
                              '홈 화면 위젯 패널 표시',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              '준비시간 ~ 일정 시간 내의 공유 체크리스트 위젯을 화면 상단에 고정 표시합니다.',
                            ),
                            value: widget.showHomeWidgetPanel,
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              widget.onShowHomeWidgetPanelChanged?.call(val);
                            },
                          ),
                          const Divider(height: 1),
                          */
                          SwitchListTile(
                            title: const Text(
                              '화면 상단 사용 팁 표시',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              '캘린더 및 체크리스트 화면 상단의 조작 안내 팁을 표시합니다.',
                            ),
                            value: widget.showTips,
                            onChanged: (val) {
                              HapticFeedback.selectionClick();
                              widget.onShowTipsChanged(val);
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // --- 푸시 알림 설정 카드 ---
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text(
                              '일정 준비시간 알림',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              '설정된 준비시간에 맞춰 상태 표시줄로 푸시 알림을 수신합니다.',
                            ),
                            value: _scheduleNotifsEnabled,
                            onChanged: (val) async {
                              HapticFeedback.selectionClick();                              if (val) {
                                final granted = await NotificationService
                                    .instance
                                    .requestPermissions();
                                if (!granted && context.mounted) {
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '알림 권한이 허용되지 않았습니다. 휴대폰 설정에서 알림 권한을 확인해 주세요.',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                              setState(() => _scheduleNotifsEnabled = val);
                              await NotificationService.instance
                                  .setScheduleNotificationsEnabled(
                                val,
                                widget.schedules,
                                situations: {
                                  for (var s in widget.situations) s.name: s
                                },
                              );
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text(
                              '할 일(Todo) 알림',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              '할 일 마감 전 설정된 알림 시간에 맞춰 상태 표시줄로 푸시 알림을 수신합니다.',
                            ),
                            value: _todoNotifsEnabled,
                            onChanged: (val) async {
                              HapticFeedback.selectionClick();                              if (val) {
                                final granted = await NotificationService
                                    .instance
                                    .requestPermissions();
                                if (!granted && context.mounted) {
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '알림 권한이 허용되지 않았습니다. 휴대폰 설정에서 알림 권한을 확인해 주세요.',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                              setState(() => _todoNotifsEnabled = val);
                              await NotificationService.instance
                                  .setTodoNotificationsEnabled(
                                val,
                                widget.todos,
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // --- 5. 데이터 백업 및 관리 (.json 파일 저장/복원) ---
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
                              '데이터 백업 및 관리 (.json 파일)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (widget.onExportBackup != null)
                            ListTile(
                              leading: Icon(
                                Icons.download_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: const Text(
                                '백업 파일 저장 (내보내기)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: const Text(
                                '다운로드 폴더에 bygo_backup_YYYYMMDD_HHmmss.json 파일로 저장합니다.',
                              ),
                              onTap: () => _handleExportBackupTap(context),
                            ),
                          if (widget.onImportBackup != null) ...[
                            const Divider(height: 1),
                            ListTile(
                              leading: Icon(
                                Icons.folder_open_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: const Text(
                                '백업 파일 불러오기 (복원)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: const Text(
                                '파일 탐색기에서 저장해 둔 .json 백업 파일을 선택하여 복구합니다.',
                              ),
                              onTap: () => _handleImportBackupTap(context),
                            ),
                          ],
                          if (widget.onResetData != null ||
                              widget.onClearAllData != null) ...[
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
                              subtitle:
                                  const Text('초기 기본 데이터 상태로 되돌립니다.'),
                              onTap: () => _confirmResetDialog(context),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}