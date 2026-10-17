import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/situation_model.dart';
import '../models/schedule_model.dart';

class StorageService {
  static const String _situationsKey = 'situations_data';
  static const String _schedulesKey = 'schedules_data';
  static const String _darkModeKey = 'dark_mode_enabled';
  static const String _themeColorKey = 'theme_color_value';
  static const String _showTipsKey = 'show_tips_enabled';

  static Future<List<Situation>> loadSituations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_situationsKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded
        .map((item) => Situation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveSituations(List<Situation> situations) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(situations.map((s) => s.toJson()).toList());
    await prefs.setString(_situationsKey, encoded);
  }

  static Future<List<Schedule>> loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_schedulesKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded
        .map((item) => Schedule.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveSchedules(List<Schedule> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(schedules.map((s) => s.toJson()).toList());
    await prefs.setString(_schedulesKey, encoded);
  }

  static Future<bool> loadIsDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  static Future<void> saveIsDarkMode(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, isDark);
  }

  static Future<int> loadThemeColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_themeColorKey) ?? Colors.indigo.toARGB32();
  }

  static Future<void> saveThemeColor(int colorValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeColorKey, colorValue);
  }

  static Future<bool> loadShowTips() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showTipsKey) ?? true;
  }

  static Future<void> saveShowTips(bool showTips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTipsKey, showTips);
  }

  static Future<String> exportBackupJson() async {
    final situations = await loadSituations();
    final schedules = await loadSchedules();
    final backupData = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'situations': situations.map((s) => s.toJson()).toList(),
      'schedules': schedules.map((sc) => sc.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(backupData);
  }

  static Future<void> importBackupJson(String jsonString) async {
    final Map<String, dynamic> data =
        jsonDecode(jsonString) as Map<String, dynamic>;

    if (!data.containsKey('situations') && !data.containsKey('schedules')) {
      throw const FormatException('유효한 백업 파일 형식이 아닙니다.');
    }

    final situationsList = (data['situations'] as List<dynamic>? ?? [])
        .map((item) => Situation.fromJson(item as Map<String, dynamic>))
        .toList();
    final schedulesList = (data['schedules'] as List<dynamic>? ?? [])
        .map((item) => Schedule.fromJson(item as Map<String, dynamic>))
        .toList();

    await saveSituations(situationsList);
    await saveSchedules(schedulesList);
  }

  static Future<String?> exportBackupToFile() async {
    final jsonString = await exportBackupJson();
    final bytes = utf8.encode(jsonString);
    final now = DateTime.now();
    final dateStamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final defaultFileName = 'bygo_backup_$dateStamp.json';

    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: '백업 JSON 파일 저장 위치 선택',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );

    if (outputFile == null) {
      return null;
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final file = File(outputFile);
      await file.writeAsBytes(bytes);
    }

    return outputFile;
  }

  static Future<bool> importBackupFromFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: '복원할 백업 JSON 파일 선택',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return false;
    }

    final pickedFile = result.files.single;
    String jsonString;

    if (pickedFile.path != null) {
      final file = File(pickedFile.path!);
      jsonString = await file.readAsString(encoding: utf8);
    } else if (pickedFile.bytes != null) {
      jsonString = utf8.decode(pickedFile.bytes!);
    } else {
      throw Exception('파일을 읽을 수 없습니다.');
    }

    await importBackupJson(jsonString);
    return true;
  }
}