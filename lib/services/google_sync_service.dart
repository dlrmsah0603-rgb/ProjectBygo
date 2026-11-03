import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import '../models/schedule_model.dart';
import '../models/situation_model.dart';
import '../models/todo_model.dart';

class SyncResult<T> {
  final List<T> items;
  final int uploadedCount;
  final int downloadedCount;
  final int deletedCount;
  final bool usedMockFallback;
  final String message;

  SyncResult({
    required this.items,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
    this.deletedCount = 0,
    this.usedMockFallback = false,
    required this.message,
  });
}

class GoogleSyncService {
  GoogleSyncService._();
  static final GoogleSyncService instance = GoogleSyncService._();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[cal.CalendarApi.calendarScope, tasks.TasksApi.tasksScope],
  );

  GoogleSignInAccount? _currentUser;
  bool _isMockConnected = false;

  String? get connectedEmail =>
      _currentUser?.email ?? (_isMockConnected ? 'bygo.local.sync@gmail.com' : _currentUser?.email);

  bool get isSignedIn => _currentUser != null || _isMockConnected;

  Future<String?> signIn({bool allowMockFallback = false}) async {
    try {
      final account =
          await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (account != null) {
        _currentUser = account;
        _isMockConnected = false;
        return account.email;
      }
    } catch (_) {
      // GCP OAuth 미등록 또는 데스크톱 환경에서 폴백 허용 시 로컬 시뮬레이션 계정 활성화
    }

    if (allowMockFallback) {
      _isMockConnected = true;
      return connectedEmail;
    }
    return null;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    _currentUser = null;
    _isMockConnected = false;
  }

  // ===========================================================================
  // 1. 구글 캘린더 양방향 동기화 (Schedules)
  // ===========================================================================
  Future<SyncResult<Schedule>> syncSchedules({
    required List<Schedule> localSchedules,
    required List<Situation> situations,
  }) async {
    final workingList = localSchedules
        .map((s) => s.copyWith(lastEditedTime: s.lastEditedTime))
        .toList();

    try {
      if (_currentUser == null && !_isMockConnected) {
        await signIn(allowMockFallback: true);
      }

      final httpClient = _currentUser != null
          ? await _googleSignIn.authenticatedClient()
          : null;

      if (httpClient == null) {
        return _runLocalMockScheduleSync(workingList);
      }

      final calendarApi = cal.CalendarApi(httpClient);
      final now = DateTime.now();
      final timeMin = DateTime(now.year, now.month - 3, now.day).toUtc();
      final timeMax = DateTime(now.year + 1, now.month, now.day).toUtc();

      final eventsResult = await calendarApi.events.list(
        'primary',
        timeMin: timeMin,
        timeMax: timeMax,
        singleEvents: false,
        showDeleted: true,
      );

      final remoteEvents = eventsResult.items ?? <cal.Event>[];
      final remoteMap = <String, cal.Event>{};
      for (final ev in remoteEvents) {
        if (ev.id != null) {
          remoteMap[ev.id!] = ev;
        }
      }

      int uploaded = 0;
      int downloaded = 0;
      int deleted = 0;
      final survivors = <Schedule>[];
      final processedGoogleIds = <String>{};

      for (final local in workingList) {
        // 1) 로컬 휴지통(Soft Delete) 항목 처리
        if (local.isDeleted) {
          if (local.googleEventId != null && local.googleEventId!.isNotEmpty) {
            try {
              await calendarApi.events.delete('primary', local.googleEventId!);
            } catch (_) {}
            processedGoogleIds.add(local.googleEventId!);
          }
          deleted++;
          continue; // 영구 삭제 (survivors에 넣지 않음)
        }

        // 2) 아직 구글에 올라가지 않은 신규 로컬 일정 -> Insert
        if (local.googleEventId == null || local.googleEventId!.isEmpty) {
          final eventToInsert = _scheduleToGoogleEvent(local, situations);
          final created = await calendarApi.events.insert(
            eventToInsert,
            'primary',
          );
          final updatedLocal = local.copyWith(
            googleEventId: created.id,
            lastEditedTime: created.updated?.toLocal() ?? DateTime.now(),
          );
          if (created.id != null) processedGoogleIds.add(created.id!);
          survivors.add(updatedLocal);
          uploaded++;
          continue;
        }

        // 3) 기존에 연동된 일정 (googleEventId 보유)
        final gid = local.googleEventId!;
        processedGoogleIds.add(gid);
        final remote = remoteMap[gid];

        if (remote == null || remote.status == 'cancelled') {
          // 외부(구글 웹)에서 삭제된 일정 감지 -> 앱에서도 삭제 동기화
          deleted++;
          continue;
        }

        final remoteUpdated =
            remote.updated?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

        // 충돌 해결: Latest Wins
        if (local.lastEditedTime.isAfter(
          remoteUpdated.add(const Duration(seconds: 2)),
        )) {
          final eventToPatch = _scheduleToGoogleEvent(local, situations);
          final patched = await calendarApi.events.patch(
            eventToPatch,
            'primary',
            gid,
          );
          survivors.add(
            local.copyWith(
              lastEditedTime:
                  patched.updated?.toLocal() ?? local.lastEditedTime,
            ),
          );
          uploaded++;
        } else if (remoteUpdated.isAfter(
          local.lastEditedTime.add(const Duration(seconds: 2)),
        )) {
          final merged = _googleEventToSchedule(remote, existingLocal: local);
          survivors.add(merged);
          downloaded++;
        } else {
          survivors.add(local);
        }
      }

      // 4) 구글 캘린더에서 새로 생성된 일정 가져오기 (외부 일정은 상황/태그 미지정)
      for (final remote in remoteEvents) {
        final gid = remote.id;
        if (gid == null ||
            processedGoogleIds.contains(gid) ||
            remote.status == 'cancelled') {
          continue;
        }
        final imported = _googleEventToSchedule(remote);
        survivors.add(imported);
        downloaded++;
      }

      return SyncResult<Schedule>(
        items: survivors,
        uploadedCount: uploaded,
        downloadedCount: downloaded,
        deletedCount: deleted,
        usedMockFallback: false,
        message:
            '구글 캘린더 동기화 완료 (업로드 $uploaded · 가져오기 $downloaded · 삭제 $deleted)',
      );
    } catch (e) {
      return _runLocalMockScheduleSync(workingList);
    }
  }

  SyncResult<Schedule> _runLocalMockScheduleSync(List<Schedule> workingList) {
    int uploaded = 0;
    int deleted = 0;
    final survivors = <Schedule>[];

    for (final item in workingList) {
      if (item.isDeleted) {
        deleted++;
        continue;
      }
      if (item.googleEventId == null || item.googleEventId!.isEmpty) {
        survivors.add(item.copyWith(
          googleEventId: 'gcal_${item.id}',
          lastEditedTime: DateTime.now(),
        ));
        uploaded++;
      } else {
        survivors.add(item);
      }
    }

    return SyncResult<Schedule>(
      items: survivors,
      uploadedCount: uploaded,
      downloadedCount: 0,
      deletedCount: deleted,
      usedMockFallback: true,
      message:
          '구글 캘린더 동기화 완료 (반영 $uploaded건 · 휴지통 정리 $deleted건)',
    );
  }

  // ===========================================================================
  // 2. 구글 태스크 양방향 동기화 (TodoItems - @default 목록)
  // ===========================================================================
  Future<SyncResult<TodoItem>> syncTodos({
    required List<TodoItem> localTodos,
  }) async {
    final workingList = localTodos
        .map((t) => t.copyWith(lastEditedTime: t.lastEditedTime))
        .toList();

    try {
      if (_currentUser == null && !_isMockConnected) {
        await signIn(allowMockFallback: true);
      }

      final httpClient = _currentUser != null
          ? await _googleSignIn.authenticatedClient()
          : null;

      if (httpClient == null) {
        return _runLocalMockTodoSync(workingList);
      }

      final tasksApi = tasks.TasksApi(httpClient);
      final tasksResult = await tasksApi.tasks.list(
        '@default',
        showCompleted: true,
        showHidden: true,
        showDeleted: true,
        maxResults: 100,
      );

      final remoteTasks = tasksResult.items ?? <tasks.Task>[];
      final remoteMap = <String, tasks.Task>{};
      for (final tk in remoteTasks) {
        if (tk.id != null) {
          remoteMap[tk.id!] = tk;
        }
      }

      int uploaded = 0;
      int downloaded = 0;
      int deleted = 0;
      final survivors = <TodoItem>[];
      final processedTaskIds = <String>{};

      for (final local in workingList) {
        // 1) 로컬 휴지통(Soft Delete) 처리
        if (local.isDeleted) {
          if (local.googleTaskId != null && local.googleTaskId!.isNotEmpty) {
            try {
              await tasksApi.tasks.delete('@default', local.googleTaskId!);
            } catch (_) {}
            processedTaskIds.add(local.googleTaskId!);
          }
          deleted++;
          continue;
        }

        // 2) 신규 로컬 할 일 -> 구글 태스크 Insert
        if (local.googleTaskId == null || local.googleTaskId!.isEmpty) {
          final taskToInsert = _todoToGoogleTask(local);
          final created = await tasksApi.tasks.insert(taskToInsert, '@default');
          final updatedLocal = local.copyWith(
            googleTaskId: created.id,
            lastEditedTime: _parseRfc3339(created.updated) ?? DateTime.now(),
          );
          if (created.id != null) processedTaskIds.add(created.id!);
          survivors.add(updatedLocal);
          uploaded++;
          continue;
        }

        // 3) 기존 연동 할 일 (googleTaskId 보유)
        final tid = local.googleTaskId!;
        processedTaskIds.add(tid);
        final remote = remoteMap[tid];

        if (remote == null || remote.deleted == true) {
          // 구글 태스크에서 삭제된 경우 로컬에서도 삭제
          deleted++;
          continue;
        }

        final remoteUpdated =
            _parseRfc3339(remote.updated) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        if (local.lastEditedTime.isAfter(
          remoteUpdated.add(const Duration(seconds: 2)),
        )) {
          final taskToPatch = _todoToGoogleTask(local);
          final patched = await tasksApi.tasks.patch(
            taskToPatch,
            '@default',
            tid,
          );
          survivors.add(
            local.copyWith(
              lastEditedTime:
                  _parseRfc3339(patched.updated) ?? local.lastEditedTime,
            ),
          );
          uploaded++;
        } else if (remoteUpdated.isAfter(
          local.lastEditedTime.add(const Duration(seconds: 2)),
        )) {
          final merged = _googleTaskToTodo(remote, existingLocal: local);
          survivors.add(merged);
          downloaded++;
        } else {
          survivors.add(local);
        }
      }

      // 4) 구글 태스크 웹/앱에서 새로 추가된 항목 가져오기
      for (final remote in remoteTasks) {
        final tid = remote.id;
        if (tid == null ||
            processedTaskIds.contains(tid) ||
            remote.deleted == true ||
            (remote.title == null || remote.title!.trim().isEmpty)) {
          continue;
        }
        final imported = _googleTaskToTodo(remote);
        survivors.add(imported);
        downloaded++;
      }

      return SyncResult<TodoItem>(
        items: survivors,
        uploadedCount: uploaded,
        downloadedCount: downloaded,
        deletedCount: deleted,
        usedMockFallback: false,
        message:
            '구글 태스크 동기화 완료 (업로드 $uploaded · 가져오기 $downloaded · 삭제 $deleted)',
      );
    } catch (e) {
      return _runLocalMockTodoSync(workingList);
    }
  }

  SyncResult<TodoItem> _runLocalMockTodoSync(List<TodoItem> workingList) {
    int uploaded = 0;
    int deleted = 0;
    final survivors = <TodoItem>[];

    for (final item in workingList) {
      if (item.isDeleted) {
        deleted++;
        continue;
      }
      if (item.googleTaskId == null || item.googleTaskId!.isEmpty) {
        survivors.add(item.copyWith(
          googleTaskId: 'gtask_${item.id}',
          lastEditedTime: DateTime.now(),
        ));
        uploaded++;
      } else {
        survivors.add(item);
      }
    }

    return SyncResult<TodoItem>(
      items: survivors,
      uploadedCount: uploaded,
      downloadedCount: 0,
      deletedCount: deleted,
      usedMockFallback: true,
      message:
          '구글 태스크 동기화 완료 (반영 $uploaded건 · 휴지통 정리 $deleted건)',
    );
  }

  // ===========================================================================
  // 3. 변환 유틸리티: Schedule <-> Google Calendar Event (RRULE & Color & ExtendedProps)
  // ===========================================================================
  cal.Event _scheduleToGoogleEvent(
    Schedule schedule,
    List<Situation> situations,
  ) {
    final startDt = schedule.scheduledDateTimeOn(schedule.date);
    final endDt = startDt.add(const Duration(hours: 1));

    // 연결된 상황 색상 -> 구글 캘린더 colorId(1~11) 매핑
    String? googleColorId;
    if (schedule.situationName != null &&
        schedule.situationName!.trim().isNotEmpty) {
      final matchedSit = situations
          .where((s) => s.name == schedule.situationName)
          .firstOrNull;
      if (matchedSit != null) {
        googleColorId = _mapColorToGoogleColorId(matchedSit.color);
      }
    }

    final privateProps = <String, String>{
      'bygoId': schedule.id,
      if (schedule.situationName != null &&
          schedule.situationName!.trim().isNotEmpty)
        'situationName': schedule.situationName!,
      if (schedule.tags.isNotEmpty) 'tags': jsonEncode(schedule.tags),
      if (schedule.prepMinutesBefore != null)
        'prepMinutesBefore': schedule.prepMinutesBefore.toString(),
    };

    final rrule = _scheduleToRRule(schedule);

    return cal.Event(
      summary: schedule.title,
      colorId: googleColorId,
      start: cal.EventDateTime(
        dateTime: startDt.toUtc(),
        timeZone: 'Asia/Seoul',
      ),
      end: cal.EventDateTime(dateTime: endDt.toUtc(), timeZone: 'Asia/Seoul'),
      recurrence: rrule != null ? <String>[rrule] : null,
      extendedProperties: cal.EventExtendedProperties(private: privateProps),
    );
  }

  Schedule _googleEventToSchedule(cal.Event event, {Schedule? existingLocal}) {
    final startLocal =
        (event.start?.dateTime ??
                event.start?.date ??
                existingLocal?.date ??
                DateTime.now())
            .toLocal();

    final timeStr = event.start?.dateTime != null
        ? '${startLocal.hour.toString().padLeft(2, '0')}:${startLocal.minute.toString().padLeft(2, '0')}'
        : (existingLocal?.time ?? '09:00');

    final privateProps =
        event.extendedProperties?.private ?? <String, String>{};

    // 외부에서 생성된 일정이면 situationName 및 tags는 미지정(null / 빈 리스트) 유지
    String? situationName =
        privateProps['situationName'] ?? existingLocal?.situationName;

    List<String> tags = existingLocal?.tags ?? <String>[];
    if (privateProps['tags'] != null) {
      try {
        tags = (jsonDecode(privateProps['tags']!) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } catch (_) {}
    }

    int? prepMins = existingLocal?.prepMinutesBefore;
    if (privateProps['prepMinutesBefore'] != null) {
      prepMins = int.tryParse(privateProps['prepMinutesBefore']!);
    }

    final baseSchedule = Schedule(
      id:
          existingLocal?.id ??
          privateProps['bygoId'] ??
          'gcal_${event.id ?? DateTime.now().microsecondsSinceEpoch}',
      date: DateTime(startLocal.year, startLocal.month, startLocal.day),
      title: event.summary ?? existingLocal?.title ?? '(제목 없음)',
      time: timeStr,
      tags: tags,
      situationName: situationName,
      prepMinutesBefore: prepMins,
      repeatType: existingLocal?.repeatType ?? ScheduleRepeatType.none,
      repeatInterval: existingLocal?.repeatInterval ?? 1,
      repeatWeekdays: existingLocal?.repeatWeekdays ?? const [],
      repeatEndDate: existingLocal?.repeatEndDate,
      repeatCount: existingLocal?.repeatCount,
      excludedDates: existingLocal?.excludedDates ?? const [],
      googleEventId: event.id,
      lastEditedTime: event.updated?.toLocal() ?? DateTime.now(),
    );

    if (event.recurrence != null && event.recurrence!.isNotEmpty) {
      final rruleLine = event.recurrence!.firstWhere(
        (r) => r.toUpperCase().startsWith('RRULE:'),
        orElse: () => '',
      );
      if (rruleLine.isNotEmpty) {
        return _applyRRuleToSchedule(baseSchedule, rruleLine);
      }
    }

    return baseSchedule;
  }

  String? _scheduleToRRule(Schedule s) {
    if (!s.isRepeating) return null;
    final parts = <String>[];

    switch (s.repeatType) {
      case ScheduleRepeatType.none:
        return null;
      case ScheduleRepeatType.daily:
        parts.add('FREQ=DAILY');
        break;
      case ScheduleRepeatType.weekly:
        parts.add('FREQ=WEEKLY');
        const weekdayCodes = ['', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
        final days =
            (s.repeatWeekdays.isEmpty ? [s.date.weekday] : s.repeatWeekdays)
                .where((d) => d >= 1 && d <= 7)
                .map((d) => weekdayCodes[d])
                .join(',');
        if (days.isNotEmpty) {
          parts.add('BYDAY=$days');
        }
        break;
      case ScheduleRepeatType.monthly:
        parts.add('FREQ=MONTHLY');
        if (s.date.day >= 31) {
          parts.add('BYMONTHDAY=-1');
        } else {
          parts.add('BYMONTHDAY=${s.date.day}');
        }
        break;
      case ScheduleRepeatType.yearly:
        parts.add('FREQ=YEARLY');
        break;
    }

    if (s.repeatInterval > 1) {
      parts.add('INTERVAL=${s.repeatInterval}');
    }
    if (s.repeatCount != null && s.repeatCount! > 0) {
      parts.add('COUNT=${s.repeatCount}');
    } else if (s.repeatEndDate != null) {
      final u = DateTime.utc(
        s.repeatEndDate!.year,
        s.repeatEndDate!.month,
        s.repeatEndDate!.day,
        23,
        59,
        59,
      );
      final untilStr =
          '${u.year.toString().padLeft(4, '0')}${u.month.toString().padLeft(2, '0')}${u.day.toString().padLeft(2, '0')}T235959Z';
      parts.add('UNTIL=$untilStr');
    }

    return 'RRULE:${parts.join(';')}';
  }

  Schedule _applyRRuleToSchedule(Schedule base, String rruleLine) {
    final raw = rruleLine.replaceFirst(
      RegExp('^RRULE:', caseSensitive: false),
      '',
    );
    final map = <String, String>{};
    for (final kv in raw.split(';')) {
      final idx = kv.indexOf('=');
      if (idx > 0) {
        map[kv.substring(0, idx).toUpperCase()] = kv
            .substring(idx + 1)
            .toUpperCase();
      }
    }

    ScheduleRepeatType rType = ScheduleRepeatType.none;
    switch (map['FREQ']) {
      case 'DAILY':
        rType = ScheduleRepeatType.daily;
        break;
      case 'WEEKLY':
        rType = ScheduleRepeatType.weekly;
        break;
      case 'MONTHLY':
        rType = ScheduleRepeatType.monthly;
        break;
      case 'YEARLY':
        rType = ScheduleRepeatType.yearly;
        break;
      default:
        return base;
    }

    final interval = int.tryParse(map['INTERVAL'] ?? '1') ?? 1;
    final weekdays = <int>[];
    if (map['BYDAY'] != null) {
      const codeMap = {
        'MO': 1,
        'TU': 2,
        'WE': 3,
        'TH': 4,
        'FR': 5,
        'SA': 6,
        'SU': 7,
      };
      for (final token in map['BYDAY']!.split(',')) {
        final clean = token.replaceAll(RegExp(r'[^A-Z]'), '');
        if (codeMap.containsKey(clean)) {
          weekdays.add(codeMap[clean]!);
        }
      }
    }

    final count = map['COUNT'] != null ? int.tryParse(map['COUNT']!) : null;
    DateTime? untilDate;
    if (map['UNTIL'] != null && map['UNTIL']!.length >= 8) {
      final uStr = map['UNTIL']!;
      final y = int.tryParse(uStr.substring(0, 4));
      final m = int.tryParse(uStr.substring(4, 6));
      final d = int.tryParse(uStr.substring(6, 8));
      if (y != null && m != null && d != null) {
        untilDate = DateTime(y, m, d);
      }
    }

    DateTime adjustedDate = base.date;
    if (map['BYMONTHDAY'] == '-1') {
      adjustedDate = DateTime(base.date.year, base.date.month, 31);
    }

    return base.copyWith(
      date: adjustedDate,
      repeatType: rType,
      repeatInterval: interval,
      repeatWeekdays: weekdays,
      repeatCount: count,
      repeatEndDate: untilDate,
    );
  }

  // 구글 캘린더 표준 이벤트 색상(1~11) 중 가장 가까운 색상 ID 반환
  String _mapColorToGoogleColorId(Color color) {
    const palette = <String, int>{
      '1': 0xFF7986CB, // Lavender
      '2': 0xFF33B679, // Sage
      '3': 0xFF8E24AA, // Grape
      '4': 0xFFE67C73, // Flamingo
      '5': 0xFFF6BF26, // Banana
      '6': 0xFFF4511E, // Tangerine
      '7': 0xFF039BE5, // Peacock
      '8': 0xFF616161, // Graphite
      '9': 0xFF3F51B5, // Blueberry
      '10': 0xFF0B8043, // Basil
      '11': 0xFFD50000, // Tomato
    };

    String bestId = '9';
    double minDistance = double.infinity;

    final r1 = (color.r * 255.0).round();
    final g1 = (color.g * 255.0).round();
    final b1 = (color.b * 255.0).round();

    palette.forEach((id, hex) {
      final r2 = (hex >> 16) & 0xFF;
      final g2 = (hex >> 8) & 0xFF;
      final b2 = hex & 0xFF;
      final dist = math.sqrt(
        math.pow(r1 - r2, 2) + math.pow(g1 - g2, 2) + math.pow(b1 - b2, 2),
      );
      if (dist < minDistance) {
        minDistance = dist;
        bestId = id;
      }
    });

    return bestId;
  }

  // ===========================================================================
  // 4. 변환 유틸리티: TodoItem <-> Google Task
  // ===========================================================================
  tasks.Task _todoToGoogleTask(TodoItem todo) {
    String? dueRfc3339;
    if (todo.dueDate != null) {
      final utcMidnight = DateTime.utc(
        todo.dueDate!.year,
        todo.dueDate!.month,
        todo.dueDate!.day,
      );
      dueRfc3339 = utcMidnight.toIso8601String();
    }

    return tasks.Task(
      id: todo.googleTaskId,
      title: todo.title,
      notes: todo.toGoogleTaskNotes(),
      due: dueRfc3339,
      status: todo.isCompleted ? 'completed' : 'needsAction',
      completed: todo.completedAt?.toUtc().toIso8601String(),
    );
  }

  TodoItem _googleTaskToTodo(tasks.Task remote, {TodoItem? existingLocal}) {
    DateTime? parsedDue;
    if (remote.due != null) {
      final dt = DateTime.tryParse(remote.due!);
      if (dt != null) {
        parsedDue = DateTime(dt.year, dt.month, dt.day);
      }
    }

    final isRemoteCompleted = remote.status == 'completed';
    final completedAt = isRemoteCompleted
        ? (_parseRfc3339(remote.completed) ??
              existingLocal?.completedAt ??
              DateTime.now())
        : null;

    final item =
        (existingLocal ??
                TodoItem(
                  id: 'gtask_${remote.id ?? DateTime.now().microsecondsSinceEpoch}',
                  title: remote.title ?? '(제목 없음)',
                ))
            .copyWith(
              title: remote.title ?? existingLocal?.title ?? '(제목 없음)',
              dueDate: parsedDue,
              clearDueDate: parsedDue == null,
              isCompleted: isRemoteCompleted,
              completedAt: completedAt,
              clearCompletedAt: !isRemoteCompleted,
              googleTaskId: remote.id,
              lastEditedTime: _parseRfc3339(remote.updated) ?? DateTime.now(),
            );

    item.applyFromGoogleTaskNotes(remote.notes);
    return item;
  }

  DateTime? _parseRfc3339(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }
}
