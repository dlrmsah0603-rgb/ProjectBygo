import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

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

  static String? _cachedLocalTimeZone;

  static Future<String> _getLocalTimeZone() async {
    if (_cachedLocalTimeZone != null && _cachedLocalTimeZone!.isNotEmpty) {
      return _cachedLocalTimeZone!;
    }
    try {
      final tz = await FlutterTimezone.getLocalTimezone();
      if (tz.isNotEmpty) {
        _cachedLocalTimeZone = tz;
        return tz;
      }
    } catch (e) {
      debugPrint('[GoogleSyncService] getLocalTimezone error: $e');
    }
    _cachedLocalTimeZone = 'Asia/Seoul';
    return _cachedLocalTimeZone!;
  }

  /// 사용자 화면에 출력할 간결하고 정돈된 동기화 안내 문구를 반환합니다. (상세 시스템/API 오류 내용은 노출하지 않음)
  static String formatSyncError(dynamic error, {required String featureName}) {
    final str = error.toString();
    if (str.contains('calendar-json.googleapis.com') ||
        str.contains('has not been used in project') ||
        str.contains('it is disabled')) {
      return '$featureName 동기화 실패: Google Cloud Console에서 $featureName API 활성화가 필요합니다.';
    }
    if (str.contains('403') ||
        str.contains('Access denied') ||
        str.contains('insufficientPermissions')) {
      return '$featureName 접근 권한이 없거나 거부되었습니다.';
    }
    if (str.contains('SocketException') ||
        str.contains('Failed host lookup') ||
        str.contains('NetworkImage') ||
        str.contains('HandshakeException')) {
      return '네트워크 연결 상태를 확인한 후 다시 시도해 주세요.';
    }
    return '$featureName 동기화에 실패했습니다. 잠시 후 다시 시도해 주세요.';
  }

  static const String calendarScope = cal.CalendarApi.calendarScope;
  static const String tasksScope = tasks.TasksApi.tasksScope;
  static const String driveAppDataScope = drive.DriveApi.driveAppdataScope;

  final Set<String> _grantedScopes = <String>{};

  GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>['email'],
  );

  GoogleSignInAccount? _currentUser;

  String? get connectedEmail => _currentUser?.email;

  bool get isSignedIn => _currentUser != null;

  String? lastAuthError;

  void _rebuildGoogleSignInInstance() {
    _googleSignIn = GoogleSignIn(
      scopes: <String>['email', ..._grantedScopes],
    );
  }

  /// 앱 시작 시 로그인 창을 띄우지 않고 기존 세션만 조용히 복원합니다.
  Future<String?> restoreSessionSilently({
    List<String> expectedScopes = const [],
  }) async {
    try {
      _grantedScopes
        ..clear()
        ..addAll(expectedScopes);
      _rebuildGoogleSignInInstance();
      final account = await _googleSignIn.signInSilently(suppressErrors: true);
      if (account != null) {
        _currentUser = account;
        return account.email;
      }
    } catch (_) {}
    _currentUser = null;
    return null;
  }

  /// 설정 화면의 'Google 계정으로 로그인' 버튼 클릭 시 호출되는 명시적 로그인
  Future<String?> signIn() async {
    lastAuthError = null;
    try {
      _grantedScopes.clear();
      _rebuildGoogleSignInInstance();
      // 이전 실패/취소로 인해 남아있을 수 있는 캐시 상태를 먼저 초기화하여 재시도 시 먹통 방지
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final account = await _googleSignIn.signIn();
      if (account != null) {
        _currentUser = account;
        return account.email;
      } else {
        lastAuthError = '사용자가 구글 로그인을 취소했습니다.';
      }
    } catch (e) {
      lastAuthError =
          '구글 계정 인증에 실패했습니다. GCP OAuth 클라이언트 ID 및 키해시(SHA-1) 설정을 확인해 주세요.';
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
    }

    _currentUser = null;
    return null;
  }

  /// 개별 기능(캘린더/태스크/드라이브) 활성화 시 권한 요청.
  /// 실패하더라도 내부 requestedScopes 오염을 초기화하여 언제든 재시도 가능하게 보장합니다.
  Future<bool> ensureScope(String scope) async {
    lastAuthError = null;
    try {
      _currentUser ??= _googleSignIn.currentUser ??
          await _googleSignIn.signInSilently(suppressErrors: true);
      if (_currentUser == null) {
        lastAuthError = ' 먼저 Google 계정에 로그인해 주세요.';
        return false;
      }

      final granted = await _googleSignIn.requestScopes(<String>[scope]);
      if (granted) {
        _grantedScopes.add(scope);
        _currentUser = _googleSignIn.currentUser ?? _currentUser;
        try {
          await _currentUser?.clearAuthCache();
        } catch (_) {}
        return true;
      } else {
        lastAuthError = '권한 요청이 거부되었습니다. 다시 스위치를 켜서 권한을 허용해 주세요.';
      }
    } catch (e) {
      lastAuthError = '권한 요청 중 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
    }

    // 권한 획득 실패 시 네이티브 플러그인의 requestedScopes 목록에서 거부된 scope를 제거하기 위해 인스턴스 재구성
    _grantedScopes.remove(scope);
    _rebuildGoogleSignInInstance();
    try {
      _currentUser = await _googleSignIn.signInSilently(suppressErrors: true) ??
          _currentUser;
    } catch (_) {}
    return false;
  }

  void removeScope(String scope) {
    _grantedScopes.remove(scope);
  }

  Future<void> signOut() async {
    _grantedScopes.clear();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    _rebuildGoogleSignInInstance();
    _currentUser = null;
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
      _currentUser ??= _googleSignIn.currentUser ??
          await _googleSignIn.signInSilently(suppressErrors: true);

      final httpClient = _currentUser != null
          ? await _googleSignIn.authenticatedClient()
          : null;

      if (httpClient == null) {
        throw Exception('Google 계정에 로그인되어 있지 않거나 인증 클라이언트를 생성할 수 없습니다. 설정에서 다시 로그인해 주세요.');
      }

      final calendarApi = cal.CalendarApi(httpClient);
      final localTimeZone = await _getLocalTimeZone();
      final now = DateTime.now();
      final timeMin = DateTime(now.year - 1, 1, 1).toUtc();
      final timeMax = DateTime(now.year + 2, 12, 31, 23, 59, 59).toUtc();

      final eventsResult = await calendarApi.events.list(
        'primary',
        timeMin: timeMin,
        timeMax: timeMax,
        maxResults: 2500,
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
          if (local.googleEventId != null &&
              local.googleEventId!.trim().isNotEmpty &&
              !local.googleEventId!.startsWith('gcal_')) {
            try {
              await calendarApi.events.delete('primary', local.googleEventId!);
            } catch (_) {}
            processedGoogleIds.add(local.googleEventId!);
          }
          deleted++;
          continue; // 영구 삭제 (survivors에 넣지 않음)
        }

        // 2) 아직 구글에 올라가지 않은 신규 로컬 일정 또는 이전 목(mock) ID 일정 -> Insert
        final isNotUploadedYet = local.googleEventId == null ||
            local.googleEventId!.trim().isEmpty ||
            local.googleEventId!.startsWith('gcal_');

        if (isNotUploadedYet) {
          try {
            final eventToInsert = _scheduleToGoogleEvent(
              local,
              situations,
              timeZone: localTimeZone,
            );
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
          } catch (insertErr) {
            debugPrint('[GoogleSyncService] insert failed for "${local.title}": $insertErr');
            survivors.add(local);
          }
          continue;
        }

        // 3) 기존에 연동된 일정 (googleEventId 보유)
        final gid = local.googleEventId!;
        processedGoogleIds.add(gid);
        final remote = remoteMap[gid];

        if (remote != null && remote.status == 'cancelled') {
          // 외부(구글 웹)에서 삭제(취소)된 일정 감지 -> 앱에서도 삭제 동기화
          deleted++;
          continue;
        }

        if (remote == null) {
          // 검색 범위 밖이거나 일시적 조회 누락 시 로컬 일정 안전 보존
          survivors.add(local);
          continue;
        }

        final remoteUpdated =
            remote.updated?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);

        // 충돌 해결: Latest Wins
        if (local.lastEditedTime.isAfter(
          remoteUpdated.add(const Duration(seconds: 2)),
        )) {
          final eventPayload = _scheduleToGoogleEvent(
            local,
            situations,
            timeZone: localTimeZone,
          );
          cal.Event updatedRemote;
          try {
            final isRecurringInstance = remote.recurringEventId != null &&
                remote.recurringEventId!.isNotEmpty;

            remote.summary = eventPayload.summary;
            remote.colorId = eventPayload.colorId;
            remote.start = eventPayload.start;
            remote.end = eventPayload.end;
            if (!isRecurringInstance) {
              remote.recurrence = eventPayload.recurrence;
            } else {
              remote.recurrence = null;
            }
            remote.extendedProperties = eventPayload.extendedProperties;

            updatedRemote = await calendarApi.events.update(
              remote,
              'primary',
              gid,
            );
            survivors.add(
              local.copyWith(
                lastEditedTime:
                    updatedRemote.updated?.toLocal() ?? local.lastEditedTime,
              ),
            );
            uploaded++;
          } catch (updateErr) {
            debugPrint(
              '[GoogleSyncService] update failed ($updateErr), trying patch for $gid ("${local.title}")',
            );
            try {
              final isRecurringInstance = remote.recurringEventId != null &&
                  remote.recurringEventId!.isNotEmpty;

              final patchEvent = cal.Event(
                summary: eventPayload.summary,
                colorId: eventPayload.colorId,
                start: eventPayload.start,
                end: eventPayload.end,
                recurrence: !isRecurringInstance ? eventPayload.recurrence : null,
                extendedProperties: eventPayload.extendedProperties,
              );

              updatedRemote = await calendarApi.events.patch(
                patchEvent,
                'primary',
                gid,
              );
              survivors.add(
                local.copyWith(
                  lastEditedTime:
                      updatedRemote.updated?.toLocal() ?? local.lastEditedTime,
                ),
              );
              uploaded++;
            } catch (patchErr) {
              debugPrint(
                '[GoogleSyncService] patch also failed for $gid ("${local.title}"): $patchErr. Keeping local safe.',
              );
              survivors.add(local);
            }
          }
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
    } catch (e, stack) {
      debugPrint('[GoogleSyncService] syncSchedules error: $e\n$stack');
      rethrow;
    }
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
      _currentUser ??= _googleSignIn.currentUser ??
          await _googleSignIn.signInSilently(suppressErrors: true);

      final httpClient = _currentUser != null
          ? await _googleSignIn.authenticatedClient()
          : null;

      if (httpClient == null) {
        throw Exception('Google 계정에 로그인되어 있지 않거나 인증 클라이언트를 생성할 수 없습니다. 설정에서 다시 로그인해 주세요.');
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
          if (local.googleTaskId != null &&
              local.googleTaskId!.trim().isNotEmpty &&
              !local.googleTaskId!.startsWith('gtask_')) {
            try {
              await tasksApi.tasks.delete('@default', local.googleTaskId!);
            } catch (_) {}
            processedTaskIds.add(local.googleTaskId!);
          }
          deleted++;
          continue;
        }

        // 2) 아직 구글에 올라가지 않은 신규 로컬 할 일 또는 이전 목(mock) ID 할 일 -> 구글 태스크 Insert
        final isNotUploadedYet = local.googleTaskId == null ||
            local.googleTaskId!.trim().isEmpty ||
            local.googleTaskId!.startsWith('gtask_');

        if (isNotUploadedYet) {
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

        if (remote != null && remote.deleted == true) {
          // 구글 태스크에서 삭제된 경우 로컬에서도 삭제
          deleted++;
          continue;
        }

        if (remote == null) {
          // 일시적 조회 누락 시 로컬 할 일 안전 보존
          survivors.add(local);
          continue;
        }

        final remoteUpdated =
            _parseRfc3339(remote.updated) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        if (local.lastEditedTime.isAfter(
          remoteUpdated.add(const Duration(seconds: 2)),
        )) {
          final taskToPatch = _todoToGoogleTask(local, existingRemote: remote);
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
    } catch (e, stack) {
      debugPrint('[GoogleSyncService] syncTodos error: $e\n$stack');
      rethrow;
    }
  }


  // ===========================================================================
  // 3. 변환 유틸리티: Schedule <-> Google Calendar Event (RRULE & Color & ExtendedProps)
  // ===========================================================================
  cal.Event _scheduleToGoogleEvent(
    Schedule schedule,
    List<Situation> situations, {
    String? timeZone,
  }) {
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
      'isAllDay': schedule.isAllDay.toString(),
    };

    final rrule = _scheduleToRRule(schedule);

    // 1) 종일 일정인 경우 (All-day event)
    // 구글 캘린더 API 규격: start.date = YYYY-MM-DD, end.date = YYYY-MM-DD (종료일 + 1일)
    // dateTime과 timeZone은 전달하지 않아야 400 충돌 에러가 발생하지 않습니다.
    if (schedule.isAllDay) {
      final startDate = DateTime(
        schedule.date.year,
        schedule.date.month,
        schedule.date.day,
      );
      final nextDay = startDate.add(const Duration(days: 1));

      return cal.Event(
        summary: schedule.title.trim().isEmpty ? '(일정)' : schedule.title.trim(),
        colorId: googleColorId,
        start: cal.EventDateTime(date: startDate),
        end: cal.EventDateTime(date: nextDay),
        recurrence: rrule != null ? <String>[rrule] : null,
        extendedProperties: cal.EventExtendedProperties(private: privateProps),
      );
    }

    // 2) 시간 지정 일정인 경우 (Timed event)
    DateTime baseDate = schedule.date;
    if (schedule.repeatType == ScheduleRepeatType.weekly &&
        schedule.repeatWeekdays.isNotEmpty) {
      if (!schedule.repeatWeekdays.contains(baseDate.weekday)) {
        for (int offset = 1; offset <= 7; offset++) {
          final nextD = baseDate.add(Duration(days: offset));
          if (schedule.repeatWeekdays.contains(nextD.weekday)) {
            baseDate = DateTime(nextD.year, nextD.month, nextD.day);
            break;
          }
        }
      }
    }

    final startDt = schedule.scheduledDateTimeOn(baseDate);
    final endDt = startDt.add(const Duration(hours: 1));
    final effectiveTz = timeZone ?? _cachedLocalTimeZone ?? 'Asia/Seoul';

    return cal.Event(
      summary: schedule.title.trim().isEmpty ? '(일정)' : schedule.title.trim(),
      colorId: googleColorId,
      start: cal.EventDateTime(
        dateTime: startDt,
        timeZone: effectiveTz,
      ),
      end: cal.EventDateTime(
        dateTime: endDt,
        timeZone: effectiveTz,
      ),
      recurrence: rrule != null ? <String>[rrule] : null,
      extendedProperties: cal.EventExtendedProperties(private: privateProps),
    );
  }

  Schedule _googleEventToSchedule(cal.Event event, {Schedule? existingLocal}) {
    // 구글 캘린더에서 온 종일 일정 여부 판별 (start.date 존재 및 dateTime 없음)
    final isGoogleAllDay =
        event.start?.date != null && event.start?.dateTime == null;
    final privateProps =
        event.extendedProperties?.private ?? <String, String>{};

    final isAllDay = isGoogleAllDay ||
        (privateProps['isAllDay'] == 'true') ||
        (existingLocal?.isAllDay ?? false);

    DateTime eventDate;
    if (isGoogleAllDay && event.start?.date != null) {
      final d = event.start!.date!.toLocal();
      eventDate = DateTime(d.year, d.month, d.day);
    } else {
      final startLocal = (event.start?.dateTime ??
              event.start?.date ??
              existingLocal?.date ??
              DateTime.now())
          .toLocal();
      eventDate = DateTime(startLocal.year, startLocal.month, startLocal.day);
    }

    final String timeStr;
    if (isAllDay) {
      timeStr = existingLocal?.time ?? '00:00';
    } else if (event.start?.dateTime != null) {
      final startLocal = event.start!.dateTime!.toLocal();
      timeStr =
          '${startLocal.hour.toString().padLeft(2, '0')}:${startLocal.minute.toString().padLeft(2, '0')}';
    } else {
      timeStr = existingLocal?.time ?? '09:00';
    }

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

    int? prepMins = isAllDay ? null : existingLocal?.prepMinutesBefore;
    if (!isAllDay && privateProps['prepMinutesBefore'] != null) {
      prepMins = int.tryParse(privateProps['prepMinutesBefore']!);
    }

    final baseSchedule = Schedule(
      id:
          existingLocal?.id ??
          privateProps['bygoId'] ??
          'gcal_${event.id ?? DateTime.now().microsecondsSinceEpoch}',
      date: eventDate,
      title: event.summary ?? existingLocal?.title ?? '(제목 없음)',
      time: timeStr,
      isAllDay: isAllDay,
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
  tasks.Task _todoToGoogleTask(TodoItem todo, {tasks.Task? existingRemote}) {
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
      notes: todo.toGoogleTaskNotes(existingRawNotes: existingRemote?.notes),
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

  // ===========================================================================
  // 5. 구글 드라이브 앱데이터 자동 JSON 백업 및 복원 (drive.appdata)
  // ===========================================================================
  static const String _driveBackupPrefix = 'bygo_backup_';
  static const int _maxDriveBackupVersions = 5;

  Future<String?> backupJsonToDrive({
    required String jsonContent,
    bool allowMock = true,
  }) async {
    try {
      _currentUser ??= _googleSignIn.currentUser ??
          await _googleSignIn.signInSilently(suppressErrors: true);

      final httpClient = _currentUser != null
          ? await _googleSignIn.authenticatedClient()
          : null;

      if (httpClient == null) {
        // 모의 백업 성공 시뮬레이션
        return 'mock_drive_backup_${DateTime.now().millisecondsSinceEpoch}';
      }

      final driveApi = drive.DriveApi(httpClient);
      final now = DateTime.now();
      final yyyy = now.year.toString().padLeft(4, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      final hh = now.hour.toString().padLeft(2, '0');
      final mi = now.minute.toString().padLeft(2, '0');
      final ss = now.second.toString().padLeft(2, '0');
      final fileName = '$_driveBackupPrefix$yyyy$mm${dd}_$hh$mi$ss.json';

      final fileMetadata = drive.File()
        ..name = fileName
        ..parents = ['appDataFolder']
        ..description = 'Bygo 자동 클라우드 백업 파일'
        ..mimeType = 'application/json';

      final bytes = utf8.encode(jsonContent);
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );

      final uploadedFile = await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
      );

      // 최대 5개 유지: 초과된 이전 백업 파일 자동 정리(Rolling Prune)
      await _pruneDriveBackups(driveApi);

      return uploadedFile.id;
    } catch (_) {
      return null;
    }
  }

  Future<List<DriveBackupInfo>> listDriveBackups() async {
    try {
      _currentUser ??= _googleSignIn.currentUser ??
          await _googleSignIn.signInSilently(suppressErrors: true);

      final httpClient = _currentUser != null
          ? await _googleSignIn.authenticatedClient()
          : null;

      if (httpClient == null) {
        return [
          DriveBackupInfo(
            id: 'mock_1',
            fileName: 'bygo_backup_mock_latest.json',
            createdTime: DateTime.now(),
            sizeBytes: 1024,
          ),
        ];
      }

      final driveApi = drive.DriveApi(httpClient);
      final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name contains '$_driveBackupPrefix' and trashed = false",
        orderBy: 'createdTime desc',
        $fields: 'files(id, name, createdTime, size)',
      );

      final files = fileList.files ?? <drive.File>[];
      return files.map((f) {
        return DriveBackupInfo(
          id: f.id ?? '',
          fileName: f.name ?? 'unknown.json',
          createdTime: f.createdTime?.toLocal() ?? DateTime.now(),
          sizeBytes: int.tryParse(f.size ?? '0') ?? 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> downloadDriveBackupJson(String fileId) async {
    try {
      _currentUser ??= _googleSignIn.currentUser ??
          await _googleSignIn.signInSilently(suppressErrors: true);

      final httpClient = _currentUser != null
          ? await _googleSignIn.authenticatedClient()
          : null;

      if (httpClient == null) {
        return null;
      }

      final driveApi = drive.DriveApi(httpClient);
      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pruneDriveBackups(drive.DriveApi driveApi) async {
    try {
      final fileList = await driveApi.files.list(
        spaces: 'appDataFolder',
        q: "name contains '$_driveBackupPrefix' and trashed = false",
        orderBy: 'createdTime desc',
        $fields: 'files(id, name, createdTime)',
      );

      final files = fileList.files ?? <drive.File>[];
      if (files.length > _maxDriveBackupVersions) {
        final toDelete = files.sublist(_maxDriveBackupVersions);
        for (final f in toDelete) {
          if (f.id != null) {
            try {
              await driveApi.files.delete(f.id!);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}

class DriveBackupInfo {
  final String id;
  final String fileName;
  final DateTime createdTime;
  final int sizeBytes;

  DriveBackupInfo({
    required this.id,
    required this.fileName,
    required this.createdTime,
    required this.sizeBytes,
  });

  String get formattedDate {
    final y = createdTime.year;
    final m = createdTime.month.toString().padLeft(2, '0');
    final d = createdTime.day.toString().padLeft(2, '0');
    final hh = createdTime.hour.toString().padLeft(2, '0');
    final mm = createdTime.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
