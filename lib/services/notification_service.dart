import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/schedule_model.dart';
import '../models/situation_model.dart';
import '../models/todo_model.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String channelId = 'bygo_alerts_channel';
  static const String channelName = '일정 및 할 일 알림';
  static const String channelDescription = '일정 사전 준비시간 및 할 일 사전 알림을 제공합니다.';

  static const String prefKeyScheduleNotifs = 'pref_schedule_notifications_enabled';
  static const String prefKeyTodoNotifs = 'pref_todo_notifications_enabled';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final ValueNotifier<String?> onNotificationPayload = ValueNotifier<String?>(null);

  bool _isInitialized = false;
  bool _scheduleNotificationsEnabled = true;
  bool _todoNotificationsEnabled = true;

  bool get scheduleNotificationsEnabled => _scheduleNotificationsEnabled;
  bool get todoNotificationsEnabled => _todoNotificationsEnabled;

  Future<void> init() async {
    if (_isInitialized) return;

    // Timezone 초기화
    tz.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('[NotificationService] Local timezone error: $e');
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          onNotificationPayload.value = response.payload;
        }
      },
    );

    // Android 알림 채널 등록 (Heads-up 상단 팝업 지원)
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    // 알림 활성화 설정 로드
    final prefs = await SharedPreferences.getInstance();
    _scheduleNotificationsEnabled = prefs.getBool(prefKeyScheduleNotifs) ?? true;
    _todoNotificationsEnabled = prefs.getBool(prefKeyTodoNotifs) ?? true;

    _isInitialized = true;
  }

  /// 최초 실행 시 시스템 권한 요청
  Future<bool> requestPermissions() async {
    bool granted = true;
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final notifGranted =
          await androidPlugin.requestNotificationsPermission() ?? false;
      await androidPlugin.requestExactAlarmsPermission();
      granted = notifGranted;
    }

    final iosPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final iosGranted = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      granted = iosGranted;
    }
    return granted;
  }

  Future<void> setScheduleNotificationsEnabled(bool enabled, List<Schedule> schedules,
      {Map<String, Situation>? situations}) async {
    _scheduleNotificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKeyScheduleNotifs, enabled);
    await syncScheduleNotifications(schedules, situations: situations);
  }

  Future<void> setTodoNotificationsEnabled(bool enabled, List<TodoItem> todos) async {
    _todoNotificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKeyTodoNotifs, enabled);
    await syncTodoNotifications(todos);
  }

  int _generateNotificationId(String key) {
    return key.hashCode & 0x7FFFFFFF;
  }

  NotificationDetails _notificationDetails({String? subText}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        icon: '@mipmap/ic_launcher',
        subText: subText,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  /// 단일 일정의 사전 준비시간 알림 예약 (향후 14일 내 발생 항목)
  Future<void> scheduleForSchedule(Schedule schedule,
      {Situation? situation, DateTime? fromDate}) async {
    // 이전 등록 알림 정리 (향후 14일 발생 범위 ID 취소)
    await cancelForSchedule(schedule.id);

    if (!_scheduleNotificationsEnabled ||
        schedule.isDeleted ||
        schedule.isAutoRecord ||
        !schedule.hasPrepTime) {
      return;
    }

    final now = DateTime.now();
    final startDay = fromDate ?? DateTime(now.year, now.month, now.day);

    // 단일 또는 반복 일정에 대해 향후 14일 발생 분 확인 후 알림 등록
    final maxDays = schedule.isRepeating ? 14 : 1;
    for (int i = 0; i < maxDays; i++) {
      final day = startDay.add(Duration(days: i));
      if (!schedule.occursOn(day)) continue;

      final prepDateTime = schedule.prepDateTimeForDay(day);
      if (prepDateTime == null || !prepDateTime.isAfter(now)) continue;

      final tzScheduled = tz.TZDateTime.from(prepDateTime, tz.local);
      final notifId = _generateNotificationId('sc_${schedule.id}_${day.year}_${day.month}_${day.day}');

      String body = '일정 시간: ${schedule.time}';
      if (situation != null && situation.name.isNotEmpty) {
        body += ' (${situation.name} 체크리스트 연결)';
      }

      final prepLabel = schedule.prepSummaryText ?? '준비시간';

      try {
        await _localNotifications.zonedSchedule(
          notifId,
          '[$prepLabel] ${schedule.title}',
          body,
          tzScheduled,
          _notificationDetails(subText: '일정 준비'),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'schedule:${schedule.id}',
        );
      } catch (e) {
        debugPrint('[NotificationService] zonedSchedule error for schedule: $e');
      }
    }
  }

  /// 일정 알림 취소
  Future<void> cancelForSchedule(String scheduleId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 앞뒤 30일 범위 ID 취소
    for (int i = -1; i <= 30; i++) {
      final day = today.add(Duration(days: i));
      final notifId = _generateNotificationId('sc_${scheduleId}_${day.year}_${day.month}_${day.day}');
      await _localNotifications.cancel(notifId);
    }
  }

  /// 모든 일정 알림 일괄 동기화
  Future<void> syncScheduleNotifications(List<Schedule> schedules,
      {Map<String, Situation>? situations}) async {
    for (final schedule in schedules) {
      Situation? sit;
      if (schedule.situationName != null && situations != null) {
        sit = situations[schedule.situationName];
      }
      await scheduleForSchedule(schedule, situation: sit);
    }
  }

  /// 단일 투두의 알림 예약 (정시 알림 없이 '알림 시간' 시점에만 발송)
  Future<void> scheduleForTodo(TodoItem todo) async {
    await cancelForTodo(todo.id);

    if (!_todoNotificationsEnabled ||
        todo.isDeleted ||
        todo.isCompleted ||
        !todo.hasReminder ||
        todo.dueDate == null ||
        todo.dueTime == null) {
      return;
    }

    final reminderDt = todo.reminderDateTime;
    final now = DateTime.now();
    if (reminderDt == null || !reminderDt.isAfter(now)) return;

    final tzScheduled = tz.TZDateTime.from(reminderDt, tz.local);
    final notifId = _generateNotificationId('todo_${todo.id}');

    final reminderLabel = todo.reminderSummaryText ?? '알림 시간';
    final body = '마감 시간: ${todo.dueTime} ($reminderLabel)';

    try {
      await _localNotifications.zonedSchedule(
        notifId,
        '[할 일 알림] ${todo.title}',
        body,
        tzScheduled,
        _notificationDetails(subText: '할 일 마감 임박'),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'todo:${todo.id}',
      );
    } catch (e) {
      debugPrint('[NotificationService] zonedSchedule error for todo: $e');
    }
  }

  /// 투두 알림 취소
  Future<void> cancelForTodo(String todoId) async {
    final notifId = _generateNotificationId('todo_$todoId');
    await _localNotifications.cancel(notifId);
  }

  /// 모든 투두 알림 일괄 동기화
  Future<void> syncTodoNotifications(List<TodoItem> todos) async {
    for (final todo in todos) {
      await scheduleForTodo(todo);
    }
  }

  /// 전체 알림 취소
  Future<void> cancelAll() async {
    await _localNotifications.cancelAll();
  }
}
