import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule_model.dart';
import '../models/situation_model.dart';
import '../models/todo_model.dart';

class StorageService {
  static const String _keySchedules = 'schedules';
  static const String _keySituations = 'situations';
  static const String _keyTodos = 'todos';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keySeedColor = 'seed_color';
  static const String _keyShowTips = 'show_tips';
  static const String _keyAutoResetOnTime = 'auto_reset_on_schedule_time';
  static const String _keyResetExecutedKeys = 'bygo_reset_executed_keys';

  // 일일 기준 시각(기본 00:00) 상황 체크리스트 일괄 리셋 관련 키
  static const String _keyAutoResetDaily = 'bygo_auto_reset_daily';
  static const String _keyDailyResetTime = 'bygo_daily_reset_time';
  static const String _keyLastDailyResetKey = 'bygo_last_daily_reset_key';

  static const String _keyWidgetPayload = 'bygo_home_widget_payload';
  static const String _keyWidgetDisplayText = 'bygo_home_widget_text';

  static const MethodChannel _widgetChannel =
      MethodChannel('com.bygo.app/widget');

  // --- 1. 일정(Schedules) 저장 및 불러오기 ---
  Future<List<Schedule>> loadSchedules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keySchedules);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map(
              (item) => Schedule.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveSchedules(List<Schedule> schedules) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(schedules.map((s) => s.toJson()).toList());
      await prefs.setString(_keySchedules, encoded);
    } catch (_) {}
  }

  // --- 2. 외출 상황 및 체크리스트(Situations) 저장 및 불러오기 ---
  Future<List<Situation>> loadSituations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keySituations);
      if (raw == null || raw.isEmpty) return _defaultSituations();

      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded
            .map(
              (item) => Situation.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
        return list.isNotEmpty ? list : _defaultSituations();
      }
    } catch (_) {}
    return _defaultSituations();
  }

  Future<void> saveSituations(List<Situation> situations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(situations.map((s) => s.toJson()).toList());
      await prefs.setString(_keySituations, encoded);
    } catch (_) {}
  }

  List<Situation> _defaultSituations() {
    return [
      Situation(
        id: 'default_work',
        name: '출근',
        iconCodePoint: Icons.work.codePoint,
        colorValue: Colors.blue.toARGB32(),
        items: [
          ChecklistItem(id: 'w1', name: '사원증 / 카드키'),
          ChecklistItem(id: 'w2', name: '지갑'),
          ChecklistItem(id: 'w3', name: '스마트폰 / 충전기'),
          ChecklistItem(id: 'w4', name: '무선 이어폰'),
        ],
      ),
      Situation(
        id: 'default_gym',
        name: '운동',
        iconCodePoint: Icons.fitness_center.codePoint,
        colorValue: Colors.orange.toARGB32(),
        items: [
          ChecklistItem(id: 'g1', name: '운동복'),
          ChecklistItem(id: 'g2', name: '운동화'),
          ChecklistItem(id: 'g3', name: '물통 (텀블러)'),
          ChecklistItem(id: 'g4', name: '수건'),
        ],
      ),
    ];
  }

  // --- 3. 할 일(Todos) 저장 및 불러오기 ---
  Future<List<TodoItem>> loadTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyTodos);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map(
              (item) => TodoItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveTodos(List<TodoItem> todos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(todos.map((t) => t.toJson()).toList());
      await prefs.setString(_keyTodos, encoded);
    } catch (_) {}
  }

  // --- 4. 테마 모드(ThemeMode) 설정 ---
  Future<ThemeMode> loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_keyThemeMode);
      switch (modeStr) {
        case 'light':
          return ThemeMode.light;
        case 'dark':
          return ThemeMode.dark;
        default:
          return ThemeMode.system;
      }
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String modeStr = 'system';
      if (mode == ThemeMode.light) modeStr = 'light';
      if (mode == ThemeMode.dark) modeStr = 'dark';
      await prefs.setString(_keyThemeMode, modeStr);
    } catch (_) {}
  }

  // --- 5. 테마 대표 색상(Seed Color) 설정 ---
  Future<int> loadSeedColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keySeedColor) ?? Colors.indigo.toARGB32();
    } catch (_) {
      return Colors.indigo.toARGB32();
    }
  }

  Future<void> saveSeedColor(int colorValue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySeedColor, colorValue);
    } catch (_) {}
  }

  // --- 6. 사용 팁 표시 여부 설정 ---
  Future<bool> loadShowTips() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyShowTips) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> saveShowTips(bool show) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowTips, show);
    } catch (_) {}
  }

  // --- 7. 일정 시간 정각 체크리스트 자동 초기화 설정 및 이력 ---
  Future<bool> loadAutoResetOnScheduleTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyAutoResetOnTime) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> saveAutoResetOnScheduleTime(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoResetOnTime, enabled);
    } catch (_) {}
  }

  Future<Set<String>> loadResetExecutedKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyResetExecutedKeys);
      if (list != null) return list.toSet();
    } catch (_) {}
    return <String>{};
  }

  Future<void> saveResetExecutedKeys(Set<String> keys) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = keys.toList();
      final trimmed =
          list.length > 300 ? list.sublist(list.length - 300) : list;
      await prefs.setStringList(_keyResetExecutedKeys, trimmed);
    } catch (_) {}
  }

  // --- 8. 일일 기준 시각(자정 등) 상황 체크리스트 일괄 리셋 설정 및 이력 ---
  Future<bool> loadAutoResetDaily() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyAutoResetDaily) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> saveAutoResetDaily(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoResetDaily, enabled);
    } catch (_) {}
  }

  Future<String> loadDailyResetTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_keyDailyResetTime);
      if (saved != null && saved.contains(':')) {
        return saved;
      }
    } catch (_) {}
    return '00:00';
  }

  Future<void> saveDailyResetTime(String timeStr) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDailyResetTime, timeStr);
    } catch (_) {}
  }

  Future<String?> loadLastDailyResetKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLastDailyResetKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastDailyResetKey(String resetKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastDailyResetKey, resetKey);
    } catch (_) {}
  }

  // --- 9. 홈 화면 위젯 상태 동기화 ---
  Future<void> syncHomeWidgetData({
    required bool hasActivePrepSchedule,
    required String summaryText,
    required List<Map<String, dynamic>> activeGroupsJson,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode({
        'hasActive': hasActivePrepSchedule,
        'emptyMessage': '예정된 일정이 없습니다.',
        'summaryText': summaryText,
        'groups': activeGroupsJson,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await prefs.setString(_keyWidgetPayload, payload);
      await prefs.setString(
        _keyWidgetDisplayText,
        hasActivePrepSchedule ? summaryText : '예정된 일정이 없습니다.',
      );

      try {
        await _widgetChannel.invokeMethod('updateHomeWidget', {
          'payload': payload,
        });
      } on MissingPluginException catch (_) {
      } on PlatformException catch (_) {}
    } catch (_) {}
  }

  // --- 10. 백업(JSON 파일 저장) 및 불러오기(JSON 파일 선택 복원) ---
  Future<String> exportBackupJson() async {
    final schedules = await loadSchedules();
    final situations = await loadSituations();
    final todos = await loadTodos();
    final themeMode = await loadThemeMode();
    final seedColor = await loadSeedColor();
    final showTips = await loadShowTips();
    final autoReset = await loadAutoResetOnScheduleTime();
    final autoResetDaily = await loadAutoResetDaily();
    final dailyResetTime = await loadDailyResetTime();

    final backupData = {
      'version': 3,
      'exportedAt': DateTime.now().toIso8601String(),
      'schedules': schedules.map((s) => s.toJson()).toList(),
      'situations': situations.map((s) => s.toJson()).toList(),
      'todos': todos.map((t) => t.toJson()).toList(),
      'themeMode': themeMode == ThemeMode.light
          ? 'light'
          : (themeMode == ThemeMode.dark ? 'dark' : 'system'),
      'seedColor': seedColor,
      'showTips': showTips,
      'autoResetOnScheduleTime': autoReset,
      'autoResetDaily': autoResetDaily,
      'dailyResetTime': dailyResetTime,
    };

    return const JsonEncoder.withIndent('  ').convert(backupData);
  }

  /// 기기의 기본 다운로드 폴더를 찾아 백업 JSON 파일을 즉시 저장하고 저장된 파일 경로를 반환
  Future<String> exportBackupToDownloadFolder() async {
    final jsonString = await exportBackupJson();
    final bytes = utf8.encode(jsonString);

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final fileName = 'bygo_backup_$stamp.json';

    Directory? targetDir;

    if (Platform.isAndroid) {
      final androidDownload = Directory('/storage/emulated/0/Download');
      if (await androidDownload.exists()) {
        targetDir = androidDownload;
      }
    }

    if (targetDir == null) {
      try {
        targetDir = await getDownloadsDirectory();
      } catch (_) {}
    }

    targetDir ??= await getApplicationDocumentsDirectory();

    final sep = Platform.pathSeparator;
    final cleanDirPath = targetDir.path.endsWith(sep)
        ? targetDir.path.substring(0, targetDir.path.length - 1)
        : targetDir.path;
    final fullPath = '$cleanDirPath$sep$fileName';

    try {
      final file = File(fullPath);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      // Android 11+ Scoped Storage 권한 제약 등으로 직접 쓰기 실패 시 시스템 저장 다이얼로그로 폴백
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: '백업 파일 저장',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(bytes),
      );
      if (savedPath == null) {
        throw Exception('백업 파일 저장이 취소되었습니다.');
      }
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final f = File(savedPath);
        await f.writeAsBytes(bytes, flush: true);
      }
      return savedPath;
    }
  }

  /// 파일 탐색기(FilePicker)에서 백업 JSON 파일을 선택하여 데이터 복원
  /// 반환값: true(성공), false(데이터 형식 오류), null(사용자가 파일 선택 취소)
  Future<bool?> importBackupFromFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '복원할 Bygo 백업 JSON 파일 선택',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null; // 사용자가 취소함
    }

    final picked = result.files.single;
    String rawJson;

    if (picked.path != null) {
      final file = File(picked.path!);
      rawJson = await file.readAsString(encoding: utf8);
    } else if (picked.bytes != null) {
      rawJson = utf8.decode(picked.bytes!);
    } else {
      return false;
    }

    return await importBackupJson(rawJson);
  }

  Future<bool> importBackupJson(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson.trim());
      if (decoded is! Map<String, dynamic>) return false;

      final hasSchedules = decoded['schedules'] is List;
      final hasSituations = decoded['situations'] is List;
      final hasTodos = decoded['todos'] is List;
      if (!hasSchedules && !hasSituations && !hasTodos) return false;

      if (hasSchedules) {
        final schedules = (decoded['schedules'] as List)
            .map((e) => Schedule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        await saveSchedules(schedules);
      }

      if (hasSituations) {
        final situations = (decoded['situations'] as List)
            .map(
              (e) => Situation.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        await saveSituations(situations);
      }

      if (hasTodos) {
        final todos = (decoded['todos'] as List)
            .map((e) => TodoItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        await saveTodos(todos);
      }

      if (decoded['themeMode'] is String) {
        final modeStr = decoded['themeMode'] as String;
        final mode = modeStr == 'light'
            ? ThemeMode.light
            : (modeStr == 'dark' ? ThemeMode.dark : ThemeMode.system);
        await saveThemeMode(mode);
      }

      if (decoded['seedColor'] is num) {
        await saveSeedColor((decoded['seedColor'] as num).toInt());
      }

      if (decoded['showTips'] is bool) {
        await saveShowTips(decoded['showTips'] as bool);
      }

      if (decoded['autoResetOnScheduleTime'] is bool) {
        await saveAutoResetOnScheduleTime(
          decoded['autoResetOnScheduleTime'] as bool,
        );
      }

      if (decoded['autoResetDaily'] is bool) {
        await saveAutoResetDaily(decoded['autoResetDaily'] as bool);
      }

      if (decoded['dailyResetTime'] is String) {
        await saveDailyResetTime(decoded['dailyResetTime'] as String);
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // --- 11. 전체 데이터 초기화 ---
  Future<void> resetAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySchedules);
      await prefs.remove(_keySituations);
      await prefs.remove(_keyTodos);
      await prefs.remove(_keyResetExecutedKeys);
      await prefs.remove(_keyLastDailyResetKey);
    } catch (_) {}
  }
}