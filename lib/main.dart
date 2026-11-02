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
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BygoApp());
}

/// 준비시간 ~ 일정 시간 내에 동일한 태그를 공유하는 상황 및 일정 묶음
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

class _BygoAppState extends State<BygoApp> {
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
  bool _showHomeWidgetPanel = false;
  int _currentIndex = 0;
  bool _isLoaded = false;

  // 자동 포커싱 및 일정 시간 초기화 상태 관리
  String? _selectedSituationId;
  Set<String> _resetExecutedKeys = <String>{};
  final Set<String> _autoFocusedWindowKeys = <String>{};
  Timer? _lifecycleTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _lifecycleTimer?.cancel();
    _pageController.dispose();
    super.dispose();
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

    if (!mounted) return;
    setState(() {
      _schedules = schedules;
      _situations = situations;
      _todos = todos;
      _themeMode = themeMode;
      _seedColorValue = seedColor;
      _showTips = showTips;
      _autoResetOnScheduleTime = autoReset;
      _resetExecutedKeys = resetKeys;
      _isLoaded = true;
    });

    _startLifecycleTimer();
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

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Situation? _findSituationByTag(String tag) {
    final clean = tag.trim();
    if (clean.isEmpty) return null;
    for (final s in _situations) {
      if (s.tag.trim() == clean) return s;
    }
    return null;
  }

  List<ActivePrepGroup> _getActivePrepGroups(DateTime now) {
    final Map<String, List<Schedule>> schedulesByTag = {};

    for (final sc in _schedules) {
      if (sc.isAutoRecord) continue;
      final cleanTag = sc.tag.trim();
      if (cleanTag.isEmpty) continue;
      if (sc.isInPrepWindowAt(now)) {
        schedulesByTag.putIfAbsent(cleanTag, () => []).add(sc);
      }
    }

    final List<ActivePrepGroup> groups = [];
    for (final sit in _situations) {
      final cleanTag = sit.tag.trim();
      final matchedSchedules = schedulesByTag[cleanTag];
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

  void _evaluateScheduleLifecycle() {
    if (!mounted || !_isLoaded) return;
    final now = DateTime.now();
    final today = _dateOnly(now);
    final todayKey = Schedule.dateKey(today);

    bool situationsModified = false;
    bool resetKeysModified = false;
    bool todosModified = false;
    final List<String> resetNoticeMessages = [];

    // 0. 완료된 반복 할 일이 다음 주기 날짜(자정)에 도달했으면 다시 진행 중으로 전환 (B안)
    for (final todo in _todos) {
      if (todo.checkAndReactivateIfDue(now)) {
        todosModified = true;
      }
    }
    if (todosModified) {
      setState(() {});
      _storage.saveTodos(_todos);
    }

    // 1. 일정 정각 도달 시 체크리스트 자동 초기화
    if (_autoResetOnScheduleTime) {
      for (final sc in _schedules) {
        if (sc.isAutoRecord) continue;
        if (!sc.occursOn(today)) continue;

        final schedDt = sc.scheduleDateTimeForDay(today);
        final resetKey = '${sc.id}_${todayKey}_${sc.time}';

        if (!now.isBefore(schedDt) && !_resetExecutedKeys.contains(resetKey)) {
          _resetExecutedKeys.add(resetKey);
          resetKeysModified = true;

          final sit = _findSituationByTag(sc.tag);
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

    final activeGroups = _getActivePrepGroups(now);

    for (final group in activeGroups) {
      final sit = group.situation;
      final isIncomplete = sit.items.isNotEmpty && !sit.isAllChecked;

      for (final sc in group.schedules) {
        final notifyKey = '${sc.id}_${todayKey}_${sc.prepMinutesBefore}';
        if (!Schedule.notifiedKeys.contains(notifyKey)) {
          Schedule.notifiedKeys.add(notifyKey);
          _showPrepPushBanner(sc, sit);
        }

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

  void _showPrepPushBanner(Schedule schedule, Situation situation) {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);

    final messenger = _messengerKey.currentState;
    if (messenger == null) return;

    final prepLabel = schedule.prepSummaryText ?? '준비시간';
    final statusText = situation.isAllChecked
        ? '체크리스트 완료됨 🎉'
        : '체크리스트 진행 현황: ${situation.checkedCount}/${situation.items.length}';

    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        elevation: 4,
        backgroundColor: Colors.orange.shade50,
        leading: const CircleAvatar(
          backgroundColor: Colors.deepOrange,
          child: Icon(
            Icons.notifications_active,
            color: Colors.white,
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⏰ [$prepLabel] ${schedule.title} (${schedule.time})',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "'${situation.name}' 체크리스트가 자동 포커싱되었습니다! ($statusText)",
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              setState(() {
                _selectedSituationId = situation.id;
                // 상황·체크리스트 탭은 이제 2번 인덱스
                _currentIndex = 2;
              });
              _pageController.animateToPage(
                2,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
              );
            },
            child: const Text('체크리스트 보기'),
          ),
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
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
      return {
        'situationId': g.situation.id,
        'situationName': g.situation.name,
        'tag': g.situation.tag,
        'schedules': g.schedules
            .map(
              (s) => {
                'id': s.id,
                'title': s.title,
                'time': s.time,
                'prepTime': s.prepTimeString,
              },
            )
            .toList(),
        'items': g.situation.items
            .map(
              (item) => {
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
          : Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Bygo',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                centerTitle: false,
              ),
              body: PageView(
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
                    onScheduleSavedOrUpdated: _handleScheduleSavedOrUpdated,
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
                    },
                  ),
                  // 1: 할 일 탭 (캘린더 - 상황 사이)
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
                    onImportBackup: (rawJson) async {
                      final ok = await _storage.importBackupJson(rawJson);
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
    );
  }
}