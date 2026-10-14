import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/situation_model.dart';
import '../models/schedule_model.dart';

class StorageService {
  static const String _situationsKey = 'situations_data';
  static const String _schedulesKey = 'schedules_data';

  static Future<List<Situation>> loadSituations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_situationsKey);

    if (data == null) {
      final defaultList = [
        Situation(
          id: 'sit_1',
          title: '출근',
          tag: '출근',
          items: [
            PackingItem(id: 'item_1', name: '사원증'),
            PackingItem(id: 'item_2', name: '노트북 및 충전기'),
            PackingItem(id: 'item_3', name: '지갑 / 교통카드'),
          ],
        ),
        Situation(
          id: 'sit_2',
          title: '운동',
          tag: '운동',
          items: [
            PackingItem(id: 'item_4', name: '텀블러'),
            PackingItem(id: 'item_5', name: '실내 운동화'),
            PackingItem(id: 'item_6', name: '스트랩'),
          ],
        ),
      ];
      await saveSituations(defaultList);
      return defaultList;
    }

    final List<dynamic> decoded = jsonDecode(data);
    return decoded.map((e) => Situation.fromJson(e)).toList();
  }

  static Future<void> saveSituations(List<Situation> situations) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        jsonEncode(situations.map((e) => e.toJson()).toList());
    await prefs.setString(_situationsKey, encoded);
  }

  static Future<List<Schedule>> loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_schedulesKey);
    if (data == null) return [];

    final List<dynamic> decoded = jsonDecode(data);
    return decoded.map((e) => Schedule.fromJson(e)).toList();
  }

  static Future<void> saveSchedules(List<Schedule> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        jsonEncode(schedules.map((e) => e.toJson()).toList());
    await prefs.setString(_schedulesKey, encoded);
  }
}