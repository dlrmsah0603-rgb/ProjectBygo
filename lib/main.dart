import 'services/notification_service.dart';
// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/schedule_model.dart';
import 'models/situation_model.dart';
import 'models/todo_model.dart';
import 'screens/calendar_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/situation_screen.dart';
import 'screens/todo_screen.dart';
import 'services/google_sync_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  runApp(const BygoApp());
}

/// 준비시간 ~ 일정 시간 내에 동일한 상황(또는 태그)을 공유하는 상황 및 일정 묶음
class ActivePrepGroup {
  final Situation situation;
  final List<Schedule> schedules;

  const ActivePrepGroup({
    required this.situation,
    required this.schedules,
  });
}

class BygoApp extends StatefulWidget {
  const BygoApp({super.key});

  @override
  State<BygoApp> createState() => _BygoAppState();
}

class _BygoAppState extends State<BygoApp> with WidgetsBindingObserver {
  //static const String _prefGoogleCalSync = 'bygo_google_calendar_sync_enabled';
  //static const String _prefGoogleTaskSync = 'bygo_google_tasks_sync_enabled';
  //static const String _prefGoogleEmail = 'bygo_google_connected_email';

  final StorageService _storage = StorageService();
  final PageController _pageController = PageController();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  List<Schedule> _schedules = [];
  List<Situation> _situations = [];
  List<TodoItem> _todos = [];
  ThemeMode _themeMode = ThemeMode.system;
  int _seedColorValue = Colors.indigo.toARGB32();
  bool _showTips = true;
  bool _autoResetOnScheduleTime = true;
  bool _autoResetDaily = true;
  String _dailyResetTime = '00:00';
  String? _lastDailyResetKey;
  bool _showHomeWidgetPanel = false;
  int _currentIndex = 0;
  bool _isLoaded = false;

  // --- 구글 캘린더 / 태스크 양방향 동기화 상태 ---
  bool _isGoogleCalendarSynced = false;
  bool _isGoogleTasksSynced = false;
  bool _isSyncingCalendar = false;
  bool _isSyncingTasks = false;
 String? _googleConnectedEmail;

  // 자동 포커싱 및 일정 시간 초기화 상태 관리
  String? _selectedSituationId;
  Set<String> _resetExecutedKeys = <String>{};
  final Set<String> _autoFocusedWindowKeys = <String>{};
  Timer? _lifecycleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.onNotificationPayload.addListener(_handleNotificationPayload);
    _loadInitialData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.instance.onNotificationPayload.removeListener(_handleNotificationPayload);
    _lifecycleTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _evaluateScheduleLifecycle();
      _triggerBackgroundAutoSync();
    }
  }

  void _handleNotificationPayload() {
    final payload = NotificationService.instance.onNotificationPayload.value;
    if (payload == null || payload.isEmpty) return;
    NotificationService.instance.onNotificationPayload.value = null;

    if (payload.startsWith('schedule:')) {
      final scheduleId = payload.replaceFirst('schedule:', '');
      final sc = _schedules.where((s) => s.id == scheduleId).firstOrNull;
      if (sc != null && sc.situationName != null) {
        final sit = _situations.where((s) => s.name == sc.situationName).firstOrNull;
        if (sit != null) {
          setState(() {
            _selectedSituationId = sit.id;
            _currentIndex = 2;
          });
          _pageController.jumpToPage(2);
          return;
        }
      }
      setState(() => _currentIndex = 0);
      _pageController.jumpToPage(0);
    } else if (payload.startsWith('todo:')) {
      setState(() => _currentIndex = 1);
      _pageController.jumpToPage(1);
    }
  }
  Future<void> _loadInitialData() async {
    final schedules = await _storage.loadSchedules();
    final situations = await _storage.loadSituations();
    final todos = await _storage.loadTodos();
    final themeMode = await _storage.loadThemeMode();
    final seedColor = await _storage.loadSeedColor();
    final showTips = await _storage.loadShowTips();
    final autoReset = await _storage.loadAutoResetOnScheduleTime();
    final resetKeys = await _storage.loadResetExecutedKeys();

    bool autoResetDaily = true;
    String dailyResetTime = '00:00';
    String? lastDailyResetKey;
    try {
      autoResetDaily = await _storage.loadAutoResetDaily();
      dailyResetTime = await _storage.loadDailyResetTime();
      lastDailyResetKey = await _storage.loadLastDailyResetKey();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _schedules = schedules.where((s) => !s.isDeleted).toList();
      _situations = situations;
      _todos = todos.where((t) => !t.isDeleted).toList();
      _themeMode = themeMode;
      _seedColorValue = seedColor;
      _showTips = showTips;
      _autoResetOnScheduleTime = autoReset;
      _autoResetDaily = autoResetDaily;
      _dailyResetTime = dailyResetTime;
      _lastDailyResetKey = lastDailyResetKey;
      _resetExecutedKeys = resetKeys;
      _selectedSituationId ??=
          situations.isNotEmpty ? situations.first.id : null;
      _isLoaded = true;
    });

    _startLifecycleTimer();
    _triggerBackgroundAutoSync();

    // 알림 권한 확인 및 초기 스케줄링 동기화
    await NotificationService.instance.requestPermissions();
    final sitMap = {for (var s in _situations) s.name: s};
    await NotificationService.instance.syncScheduleNotifications(_schedules, situations: sitMap);
    await NotificationService.instance.syncTodoNotifications(_todos);
  }

  void _startLifecycleTimer() {
    _lifecycleTimer?.cancel();
    _lifecycleTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _evaluateScheduleLifecycle(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluateScheduleLifecycle();
    });
  }

  // ===========================================================================
  // 구글 캘린더 / 태스크 양방향 동기화 제어
  // ===========================================================================
  Future<void> _triggerBackgroundAutoSync() async {
    if (_isGoogleCalendarSynced) {
      await _syncGoogleCalendar(silent: true);
    }
    if (_isGoogleTasksSynced) {
      await _syncGoogleTasks(silent: true);
    }
  }

  Future<void> _syncGoogleCalendar({bool silent = false}) async {
    if (_isSyncingCalendar) return;
    setState(() => _isSyncingCalendar = true);

    try {
      final result = await GoogleSyncService.instance.syncSchedules(
        localSchedules: _schedules,
        situations: _situations,
      );
      if (!mounted) return;
      setState(() {
        _schedules = result.items;
        _isSyncingCalendar = false;
      });
      await _storage.saveSchedules(_schedules);
      _evaluateScheduleLifecycle();
      final sitMap = {for (var s in _situations) s.name: s};
      NotificationService.instance.syncScheduleNotifications(_schedules, situations: sitMap);

      if (!silent) {
        _messengerKey.currentState?.clearSnackBars();
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(result.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSyncingCalendar = false);
      if (!silent) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('캘린더 동기화 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _syncGoogleTasks({bool silent = false}) async {
    if (_isSyncingTasks) return;
    setState(() => _isSyncingTasks = true);

    try {
      final result = await GoogleSyncService.instance.syncTodos(
        localTodos: _todos,
      );
      if (!mounted) return;
      setState(() {
        _todos = result.items;
        _isSyncingTasks = false;
      });
      await _storage.saveTodos(_todos);
      NotificationService.instance.syncTodoNotifications(_todos);

      if (!silent) {
        _messengerKey.currentState?.clearSnackBars();
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(result.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSyncingTasks = false);
      if (!silent) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('할 일 동기화 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  // ignore: unused_element
  Future<void> _toggleGoogleCalendarSync(bool enabled) async {
    if (enabled) {
      final email =
          await GoogleSyncService.instance.signIn(allowMockFallback: true);
      if (email == null) return;
      setState(() {
        _isGoogleCalendarSynced = true;
        _googleConnectedEmail = email;
      });
      await _syncGoogleCalendar(silent: false);
    } else {
      // 연동 해제 시 이미 가져온 로컬 일정 데이터는 그대로 유지
      setState(() => _isGoogleCalendarSynced = false);
      if (!_isGoogleTasksSynced) {
        await GoogleSyncService.instance.signOut();
        setState(() => _googleConnectedEmail = null);
      }
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Google 캘린더 연동이 해제되었습니다. (로컬 일정 유지)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ignore: unused_element
  Future<void> _toggleGoogleTasksSync(bool enabled) async {
    if (enabled) {
      final email =
          await GoogleSyncService.instance.signIn(allowMockFallback: true);
      if (email == null) return;
      setState(() {
        _isGoogleTasksSynced = true;
        _googleConnectedEmail = email;
      });
      await _syncGoogleTasks(silent: false);
    } else {
      // 연동 해제 시 이미 가져온 로컬 할 일 데이터는 그대로 유지
      setState(() => _isGoogleTasksSynced = false);
      if (!_isGoogleCalendarSynced) {
        await GoogleSyncService.instance.signOut();
        setState(() => _googleConnectedEmail = null);
      }
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Google 태스크 연동이 해제되었습니다. (로컬 할 일 유지)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

/*
  void _showGoogleSyncSettingsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cloud_sync_outlined),
              SizedBox(width: 8),
              Text('Google 캘린더 / 태스크 연동'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_googleConnectedEmail != null &&
                  (_isGoogleCalendarSynced || _isGoogleTasksSynced))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Chip(
                    avatar: const Icon(Icons.account_circle, size: 18),
                    label: Text(_googleConnectedEmail!),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Google 캘린더 양방향 연동'),
                subtitle: const Text('일정·반복(RRULE)·상황/태그 메타데이터 보존'),
                value: _isGoogleCalendarSynced,
                onChanged: (val) async {
                  await _toggleGoogleCalendarSync(val);
                  if (ctx.mounted) setDialogState(() {});
                },
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Google 태스크 양방향 연동'),
                subtitle: const Text('할 일(@default)·시간 및 세부항목(Notes) 연동'),
                value: _isGoogleTasksSynced,
                onChanged: (val) async {
                  await _toggleGoogleTasksSync(val);
                  if (ctx.mounted) setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }
  */

  // ===========================================================================
  // 외출 준비 라이프사이클 엔진 (일일 리셋 + 반복 할 일 복귀 + 준비시간 포커싱 + 정각 리셋)
  // ===========================================================================
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Situation? _findSituationForSchedule(Schedule sc) {
    final sitName = (sc.situationName ?? '').trim();
    if (sitName.isNotEmpty) {
      for (final s in _situations) {
        if (s.name.trim() == sitName) return s;
      }
    }
    final cleanTag = sc.tag.trim();
    if (cleanTag.isNotEmpty) {
      for (final s in _situations) {
        if (s.name.trim() == cleanTag || s.tag.trim() == cleanTag) return s;
      }
    }
    return null;
  }

  List<ActivePrepGroup> _getActivePrepGroups(DateTime now) {
    final Map<String, List<Schedule>> schedulesBySitId = {};

    for (final sc in _schedules) {
      if (sc.isDeleted || sc.isAutoRecord) continue;
      if (!sc.isInPrepWindowAt(now)) continue;

      final sit = _findSituationForSchedule(sc);
      if (sit == null) continue;
      schedulesBySitId.putIfAbsent(sit.id, () => []).add(sc);
    }

    final List<ActivePrepGroup> groups = [];
    for (final sit in _situations) {
      final matchedSchedules = schedulesBySitId[sit.id];
      if (matchedSchedules != null && matchedSchedules.isNotEmpty) {
        matchedSchedules.sort((a, b) => a.time.compareTo(b.time));
        groups.add(
          ActivePrepGroup(
            situation: sit,
            schedules: matchedSchedules,
          ),
        );
      }
    }
    return groups;
  }

  void _handleScheduleSavedOrUpdated(Schedule sc) {
    final now = DateTime.now();
    final today = _dateOnly(now);
    if (sc.occursOn(today)) {
      final schedDt = sc.scheduleDateTimeForDay(today);
      final resetKey = '${sc.id}_${Schedule.dateKey(today)}_${sc.time}';
      if (!now.isBefore(schedDt)) {
        _resetExecutedKeys.add(resetKey);
        _storage.saveResetExecutedKeys(_resetExecutedKeys);
      } else {
        _resetExecutedKeys.remove(resetKey);
      }
    }
    _evaluateScheduleLifecycle();
  }

  DateTime _getLatestDailyResetThreshold(DateTime now) {
    final parts = _dailyResetTime.split(':');
    final resetH = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
    final resetM = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final todayThreshold =
        DateTime(now.year, now.month, now.day, resetH, resetM);
    if (now.isBefore(todayThreshold)) {
      return todayThreshold.subtract(const Duration(days: 1));
    }
    return todayThreshold;
  }

  void _evaluateScheduleLifecycle() {
    if (!mounted || !_isLoaded) return;
    final now = DateTime.now();
    final today = _dateOnly(now);
    final todayKey = Schedule.dateKey(today);

    bool situationsModified = false;
    bool resetKeysModified = false;
    bool todosModified = false;
    final List<String> resetNoticeMessages = [];

    // 0-A. 하루 시작 시간(_dailyResetTime) 기준 상황 체크리스트 일괄 초기화
    if (_autoResetDaily) {
      final threshold = _getLatestDailyResetThreshold(now);
      final thresholdKey =
          '${Schedule.dateKey(threshold)}_${threshold.hour.toString().padLeft(2, '0')}:${threshold.minute.toString().padLeft(2, '0')}';

      if (_lastDailyResetKey == null) {
        _lastDailyResetKey = thresholdKey;
        try {
          _storage.saveLastDailyResetKey(thresholdKey);
        } catch (_) {}
      } else if (_lastDailyResetKey != thresholdKey) {
        _lastDailyResetKey = thresholdKey;
        try {
          _storage.saveLastDailyResetKey(thresholdKey);
        } catch (_) {}

        for (final sit in _situations) {
          for (final item in sit.items) {
            if (item.isChecked) {
              item.isChecked = false;
              situationsModified = true;
            }
          }
        }
      }
    }

    // 0-B. 완료된 반복 할 일이 다음 주기 날짜(하루 시작 시간 기준)에 도달했으면 다시 진행 중으로 전환
    for (final todo in _todos) {
      if (todo.checkAndReactivateIfDue(now, dailyResetTime: _dailyResetTime)) {
        todosModified = true;
      }
    }
    if (todosModified) {
      setState(() {});
      _storage.saveTodos(_todos);
      if (_isGoogleTasksSynced) {
        _syncGoogleTasks(silent: true);
      }
    }

    // 1. 일정 정각 도달 시 연결된 상황 체크리스트 자동 초기화
    if (_autoResetOnScheduleTime) {
      for (final sc in _schedules) {
        if (sc.isDeleted || sc.isAutoRecord) continue;
        if (!sc.occursOn(today)) continue;

        final schedDt = sc.scheduleDateTimeForDay(today);
        final resetKey = '${sc.id}_${todayKey}_${sc.time}';

        if (!now.isBefore(schedDt) && !_resetExecutedKeys.contains(resetKey)) {
          _resetExecutedKeys.add(resetKey);
          resetKeysModified = true;

          final sit = _findSituationForSchedule(sc);
          if (sit != null && sit.items.isNotEmpty) {
            for (final item in sit.items) {
              item.isChecked = false;
            }
            situationsModified = true;
            resetNoticeMessages.add(
              "⏰ '${sc.title}' 일정 시간(${sc.time})이 되어 '${sit.name}' 체크리스트가 초기화되었습니다.",
            );
          }
        }
      }
    }

    if (resetKeysModified) {
      _storage.saveResetExecutedKeys(_resetExecutedKeys);
    }

    if (situationsModified) {
      setState(() {});
      _storage.saveSituations(_situations);
      if (resetNoticeMessages.isNotEmpty) {
        HapticFeedback.mediumImpact();
        _messengerKey.currentState?.clearSnackBars();
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(resetNoticeMessages.last),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    // 2. 준비시간 진입 그룹 확인, 상단 배너 표시 및 미완료 상황 자동 포커싱
    final activeGroups = _getActivePrepGroups(now);

    for (final group in activeGroups) {
      final sit = group.situation;
      final isIncomplete = sit.items.isNotEmpty && !sit.isAllChecked;

      for (final sc in group.schedules) {

        final focusWindowKey =
            'focus_${sit.id}_${sc.id}_${todayKey}_${sc.time}';
        if (isIncomplete && !_autoFocusedWindowKeys.contains(focusWindowKey)) {
          _autoFocusedWindowKeys.add(focusWindowKey);
          if (_selectedSituationId != sit.id) {
            setState(() {
              _selectedSituationId = sit.id;
            });
          }
        }
      }
    }

    final firstIncompleteGroup = activeGroups
        .where((g) => g.situation.items.isNotEmpty && !g.situation.isAllChecked)
        .firstOrNull;
    if (firstIncompleteGroup != null) {
      final currentSelectedSit = _situations
          .where((s) => s.id == _selectedSituationId)
          .firstOrNull;
      final isCurrentAlsoIncompleteActive = currentSelectedSit != null &&
          activeGroups.any(
            (g) =>
                g.situation.id == currentSelectedSit.id &&
                !g.situation.isAllChecked,
          );
      if (!isCurrentAlsoIncompleteActive &&
          _selectedSituationId != firstIncompleteGroup.situation.id) {
        setState(() {
          _selectedSituationId = firstIncompleteGroup.situation.id;
        });
      }
    }

    _syncHomeWidget(activeGroups);
  }


  void _syncHomeWidget(List<ActivePrepGroup> activeGroups) {
    if (activeGroups.isEmpty) {
      _storage.syncHomeWidgetData(
        hasActivePrepSchedule: false,
        summaryText: '예정된 일정이 없습니다.',
        activeGroupsJson: const [],
      );
      return;
    }

    final summaryParts = activeGroups.map((g) {
      final schedNames =
          g.schedules.map((s) => '${s.title}(${s.time})').join(', ');
      return '[${g.situation.name}] $schedNames - ${g.situation.checkedCount}/${g.situation.items.length}';
    }).toList();

    final groupsJson = activeGroups.map((g) {
      return <String, dynamic>{
        'situationId': g.situation.id,
        'situationName': g.situation.name,
        'tag': g.situation.tag,
        'schedules': g.schedules
            .map(
              (s) => <String, dynamic>{
                'id': s.id,
                'title': s.title,
                'time': s.time,
                'prepTime': s.prepTimeString,
              },
            )
            .toList(),
        'items': g.situation.items
            .map(
              (item) => <String, dynamic>{
                'id': item.id,
                'name': item.name,
                'isChecked': item.isChecked,
              },
            )
            .toList(),
      };
    }).toList();

    _storage.syncHomeWidgetData(
      hasActivePrepSchedule: true,
      summaryText: summaryParts.join(' | '),
      activeGroupsJson: groupsJson,
    );
  }

  void _registerCompletedChecklistFromWidget(Situation situation) {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final currentTimeStr = '$hh:$mm';
    final recordTitle = '${situation.name} 체크리스트 완료';

    Schedule? existingRecord;
    for (final sc in _schedules) {
      if (!sc.isDeleted &&
          sc.isAutoRecord &&
          (sc.situationName == situation.name ||
              sc.tag.trim() == situation.tag.trim()) &&
          sc.date.year == today.year &&
          sc.date.month == today.month &&
          sc.date.day == today.day) {
        existingRecord = sc;
        break;
      }
    }

    setState(() {
      if (existingRecord != null) {
        existingRecord.time = currentTimeStr;
        existingRecord.title = recordTitle;
        existingRecord.markUpdated();
      } else {
        _schedules.add(
          Schedule(
            id: 'record_${now.microsecondsSinceEpoch}',
            date: today,
            title: recordTitle,
            time: currentTimeStr,
            tag: situation.tag,
            situationName: situation.name,
            isAutoRecord: true,
            lastEditedTime: now,
          ),
        );
      }
    });
    _storage.saveSchedules(_schedules);

    _messengerKey.currentState?.clearSnackBars();
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          "🎉 '${situation.name}' 체크리스트 완료! 캘린더에 기록이 자동 추가되었습니다.",
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildHomeScreenWidgetCard(List<ActivePrepGroup> activeGroups) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: activeGroups.isNotEmpty
              ? scheme.primary.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.widgets_rounded,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Bygo 홈 화면 위젯',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              if (activeGroups.isNotEmpty)
                const Text(
                  '준비시간 ~ 일정시간 활성',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepOrange,
                  ),
                ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showHomeWidgetPanel = false);
                },
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16),
                ),
              ),
            ],
          ),
          const Divider(height: 14),
          if (activeGroups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  '예정된 일정이 없습니다.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 210),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: activeGroups.map((group) {
                    final sit = group.situation;
                    final schedulesText = group.schedules
                        .map(
                          (s) =>
                              '${s.title} (${s.prepTimeString ?? ""}~${s.time})',
                        )
                        .join(', ');
                    final isComplete = sit.isAllChecked;
                    final accentColor = isComplete ? Colors.green : sit.color;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isComplete ? Icons.verified : sit.iconData,
                                size: 16,
                                color: accentColor,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${sit.name} · $schedulesText',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                '${sit.checkedCount}/${sit.items.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (sit.items.isEmpty)
                            const Text(
                              '등록된 체크리스트 항목이 없습니다.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            )
                          else
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: sit.items.map((item) {
                                return FilterChip(
                                  visualDensity: VisualDensity.compact,
                                  selected: item.isChecked,
                                  selectedColor:
                                      accentColor.withValues(alpha: 0.2),
                                  checkmarkColor: accentColor,
                                  label: Text(
                                    item.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      decoration: item.isChecked
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  onSelected: (val) {
                                    final wasAllChecked = sit.isAllChecked;
                                    setState(() {
                                      item.isChecked = val;
                                    });
                                    if (sit.isAllChecked) {
                                      HapticFeedback.heavyImpact();
                                    } else {
                                      HapticFeedback.lightImpact();
                                    }
                                    _storage.saveSituations(_situations);
                                    if (!wasAllChecked && sit.isAllChecked) {
                                      _registerCompletedChecklistFromWidget(
                                        sit,
                                      );
                                    }
                                    _evaluateScheduleLifecycle();
                                  },
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isBlackAndWhite =
        _seedColorValue == SettingsScreen.blackAndWhiteColorValue;

    if (isBlackAndWhite) {
      final isDark = brightness == Brightness.dark;
      final bwScheme = isDark
          ? const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              primaryContainer: Color(0xFF2C2C2C),
              onPrimaryContainer: Colors.white,
              secondary: Color(0xFFD0D0D0),
              onSecondary: Colors.black,
              surface: Color(0xFF121212),
              onSurface: Colors.white,
              surfaceContainerHighest: Color(0xFF262626),
            )
          : const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              primaryContainer: Color(0xFFE6E6E6),
              onPrimaryContainer: Colors.black,
              secondary: Color(0xFF333333),
              onSecondary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
              surfaceContainerHighest: Color(0xFFEEEEEE),
            );

      return ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: bwScheme,
        scaffoldBackgroundColor: bwScheme.surface,
        appBarTheme: AppBarTheme(
          backgroundColor: bwScheme.surface,
          foregroundColor: bwScheme.onSurface,
          elevation: 0,
        ),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: Color(_seedColorValue),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bygo',
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: !_isLoaded
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : Builder(
              builder: (innerContext) => Scaffold(
                appBar: AppBar(
                  title: const Text(
                    'Bygo',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  centerTitle: false,
                  actions: [
                    // 캘린더 탭(0)이고 구글 캘린더 연동 활성화 시 동기화 버튼
                    /*
                    if (_currentIndex == 0 && _isGoogleCalendarSynced)
                      IconButton(
                        tooltip: 'Google 캘린더 동기화',
                        onPressed: _isSyncingCalendar
                            ? null
                            : () => _syncGoogleCalendar(silent: false),
                        icon: _isSyncingCalendar
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                      ),
                    // 할 일 탭(1)이고 구글 태스크 연동 활성화 시 동기화 버튼 표시
                    if (_currentIndex == 1 && _isGoogleTasksSynced)
                      IconButton(
                        tooltip: 'Google 태스크 동기화',
                        onPressed: _isSyncingTasks
                            ? null
                            : () => _syncGoogleTasks(silent: false),
                        icon: _isSyncingTasks
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                      ),
                    // 구글 연동 설정 다이얼로그 열기 버튼
                    IconButton(
                      tooltip: 'Google 캘린더/태스크 연동 설정',
                      icon: Icon(
                        (_isGoogleCalendarSynced || _isGoogleTasksSynced)
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_sync_outlined,
                      ),
                      onPressed: () =>
                          _showGoogleSyncSettingsDialog(innerContext),
                    ),
                    */
                  ],
                ),
                body: Column(
                  children: [
                    if (_showHomeWidgetPanel)
                      _buildHomeScreenWidgetCard(
                        _getActivePrepGroups(DateTime.now()),
                      ),
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: (idx) {
                          setState(() => _currentIndex = idx);
                          if (idx == 1 || idx == 2) {
                            _evaluateScheduleLifecycle();
                          }
                        },
                        children: [
                          // 0: 캘린더 탭
                          CalendarScreen(
                            schedules: _schedules,
                            situations: _situations,
                            todos: _todos,
                            showTips: _showTips,
                            onScheduleSavedOrUpdated:
                                _handleScheduleSavedOrUpdated,
                            onSchedulesChanged: (updated) {
                              setState(() => _schedules = List.from(updated));
                              _storage.saveSchedules(_schedules);
                              _evaluateScheduleLifecycle();
                            },
                            onSituationsChanged: (updated) {
                              setState(() => _situations = List.from(updated));
                              _storage.saveSituations(_situations);
                              _evaluateScheduleLifecycle();
                            },
                            onTodosChanged: (updated) {
                              setState(() => _todos = List.from(updated));
                              _storage.saveTodos(_todos);
                              NotificationService.instance.syncTodoNotifications(_todos);
                            },
                          ),
                          // 1: 할 일 탭
                          TodoScreen(
                            todos: _todos,
                            showTips: _showTips,
                            onTodosChanged: (updated) {
                              setState(() => _todos = List.from(updated));
                              _storage.saveTodos(_todos);
                            },
                          ),
                          // 2: 상황·체크리스트 탭
                          SituationScreen(
                            situations: _situations,
                            schedules: _schedules,
                            showTips: _showTips,
                            selectedSituationId: _selectedSituationId,
                            onSelectedSituationChanged: (id) {
                              setState(() => _selectedSituationId = id);
                            },
                            onSituationsChanged: (updated) {
                              setState(() => _situations = List.from(updated));
                              _storage.saveSituations(_situations);
                              _evaluateScheduleLifecycle();
                            },
                            onSchedulesChanged: (updated) {
                              setState(() => _schedules = List.from(updated));
                              _storage.saveSchedules(_schedules);
                              _evaluateScheduleLifecycle();
                            },
                          ),
                          // 3: 설정 탭
                          SettingsScreen(
                            themeMode: _themeMode,
                            seedColorValue: _seedColorValue,
                            showTips: _showTips,
                            autoResetOnScheduleTime: _autoResetOnScheduleTime,
                            showHomeWidgetPanel: _showHomeWidgetPanel,
                            onThemeModeChanged: (mode) {
                              setState(() => _themeMode = mode);
                              _storage.saveThemeMode(mode);
                            },
                            onSeedColorChanged: (colorVal) {
                              setState(() => _seedColorValue = colorVal);
                              _storage.saveSeedColor(colorVal);
                            },
                            onShowTipsChanged: (val) {
                              setState(() => _showTips = val);
                              _storage.saveShowTips(val);
                            },
                            onAutoResetChanged: (val) {
                              setState(() => _autoResetOnScheduleTime = val);
                              _storage.saveAutoResetOnScheduleTime(val);
                            },
                            onShowHomeWidgetPanelChanged: (val) {
                              setState(() => _showHomeWidgetPanel = val);
                            },
                            onExportBackup: () => _storage.exportBackupJson(),
                            onImportBackup: ([rawJson]) async {
                              if (rawJson == null) return null;
                              final ok =
                                  await _storage.importBackupJson(rawJson);
                              if (ok) {
                                await _loadInitialData();
                              }
                              return ok;
                            },
                            onResetData: () async {
                              await _storage.resetAllData();
                              await _loadInitialData();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (idx) {
                    HapticFeedback.selectionClick();
                    setState(() => _currentIndex = idx);
                    if (idx == 1 || idx == 2) {
                      _evaluateScheduleLifecycle();
                    }
                    _pageController.animateToPage(
                      idx,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                    );
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month),
                      label: '캘린더',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.task_alt_outlined),
                      selectedIcon: Icon(Icons.task_alt),
                      label: '할 일',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.checklist_rtl_outlined),
                      selectedIcon: Icon(Icons.checklist_rtl),
                      label: '상황·체크리스트',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: '설정',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
