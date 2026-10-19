import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule_model.dart';
import '../models/situation_model.dart';

class StorageService {
  static const String _keySchedules = 'schedules';
  static const String _keySituations = 'situations';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keySeedColor = 'seed_color';
  static const String _keyShowTips = 'show_tips';

  // --- 1. 일정(Schedules) 저장 및 불러오기 ---
  Future<List<Schedule>> loadSchedules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keySchedules);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((item) => Schedule.fromJson(item as Map<String, dynamic>))
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
            .map((item) => Situation.fromJson(item as Map<String, dynamic>))
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

  // 기본 초기 상황 데이터
  List<Situation> _defaultSituations() {
    return [
      Situation(
        id: 'default_work',
        name: '출근',
        tag: '출근',
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
        tag: '운동',
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

  // --- 3. 테마 모드(ThemeMode) 설정 ---
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

  // --- 4. 테마 대표 색상(Seed Color) 설정 ---
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

  // --- 5. 사용 팁 표시 여부 설정 ---
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

  // --- 6. 전체 데이터 초기화 ---
  Future<void> resetAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySchedules);
      await prefs.remove(_keySituations);
    } catch (_) {}
  }
}