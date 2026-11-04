import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/schedule_model.dart';
import '../models/situation_model.dart';
import '../models/todo_model.dart';
import '../services/google_sync_service.dart';
import 'settings_screen.dart';

enum _CalendarHeightStage { twoWeeks, month, expanded }

class CalendarScreen extends StatefulWidget {
  final List<Schedule> schedules;
  final List<Situation> situations;
  final List<TodoItem> todos;
  final List<String> tagOrder;
  final bool showTips;
  final bool? isGoogleCalendarSynced;
  final bool isSyncingCalendar;
  final VoidCallback? onSyncGoogleCalendar;
  final ValueChanged<Schedule>? onScheduleSavedOrUpdated;
  final ValueChanged<List<Schedule>> onSchedulesChanged;
  final ValueChanged<List<Situation>> onSituationsChanged;
  final ValueChanged<List<TodoItem>>? onTodosChanged;
  final ValueChanged<List<String>>? onTagOrderChanged;

  const CalendarScreen({
    super.key,
    required this.schedules,
    required this.situations,
    this.todos = const [],
    this.tagOrder = const [],
    this.showTips = true,
    this.isGoogleCalendarSynced,
    this.isSyncingCalendar = false,
    this.onSyncGoogleCalendar,
    this.onScheduleSavedOrUpdated,
    required this.onSchedulesChanged,
    required this.onSituationsChanged,
    this.onTodosChanged,
    this.onTagOrderChanged,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const String _todoFilterKey = '__BYGO_TODO_FILTER__';
  static const List<String> _weekdayLabels = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  _CalendarHeightStage _heightStage = _CalendarHeightStage.month;
  double? _dragHeightOverride;

  final Set<String> _selectedFilterKeys = <String>{};
  final Set<String> _knownTags = <String>{};
  bool _filtersInitialized = false;

  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _localSyncing = false;

  List<Schedule> get _activeSchedules =>
      widget.schedules.where((s) => !s.isDeleted).toList();

  List<TodoItem> get _activeTodos =>
      widget.todos.where((t) => !t.isDeleted).toList();

  @override
  void initState() {
    super.initState();
    SettingsScreen.ensureSyncPrefsLoaded();
    _syncFilterTags();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFilterTags();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _allTags {
    final tagSet = <String>{};
    for (final sc in _activeSchedules) {
      for (final t in sc.tags) {
        final clean = t.trim();
        if (clean.isNotEmpty) tagSet.add(clean);
      }
      if (sc.tag.trim().isNotEmpty) {
        tagSet.add(sc.tag.trim());
      }
    }
    final ordered = <String>[];
    for (final t in widget.tagOrder) {
      if (tagSet.contains(t)) {
        ordered.add(t);
        tagSet.remove(t);
      }
    }
    ordered.addAll(tagSet);
    return ordered;
  }

  void _syncFilterTags() {
    final currentTags = _allTags;
    if (!_filtersInitialized) {
      _selectedFilterKeys.add(_todoFilterKey);
      _selectedFilterKeys.addAll(currentTags);
      _knownTags.addAll(currentTags);
      _filtersInitialized = true;
      return;
    }
    for (final t in currentTags) {
      if (!_knownTags.contains(t)) {
        _knownTags.add(t);
        _selectedFilterKeys.add(t);
      }
    }
  }

  Situation? _findSituationForSchedule(Schedule sc) {
    final sitName = (sc.situationName ?? '').trim();
    if (sitName.isNotEmpty) {
      for (final s in widget.situations) {
        if (s.name.trim() == sitName) return s;
      }
    }
    final cleanTag = sc.tag.trim();
    if (cleanTag.isNotEmpty) {
      for (final s in widget.situations) {
        if (s.name.trim() == cleanTag || s.tag.trim() == cleanTag) return s;
      }
    }
    return null;
  }

  List<Schedule> _getSchedulesForDay(DateTime day) {
    final allTags = _allTags;
    final activeTagFilters =
        _selectedFilterKeys.where((k) => k != _todoFilterKey).toSet();

    if (_selectedFilterKeys.isEmpty) return [];

    return _activeSchedules.where((sc) {
      if (!sc.occursOn(day)) return false;

      if (sc.tags.isEmpty && sc.tag.trim().isEmpty) {
        return activeTagFilters.isNotEmpty || allTags.isEmpty;
      }
      final scTags = sc.tags.isNotEmpty ? sc.tags : <String>[sc.tag.trim()];
      return scTags.any((t) => activeTagFilters.contains(t.trim()));
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  List<TodoItem> _getTodosForDay(DateTime day) {
    if (!_selectedFilterKeys.contains(_todoFilterKey)) return [];
    return _activeTodos.where((todo) {
      if (todo.dueDate == null) return false;
      return todo.dueDate!.year == day.year &&
          todo.dueDate!.month == day.month &&
          todo.dueDate!.day == day.day;
    }).toList();
  }

  List<Schedule> get _searchedSchedules {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _activeSchedules.where((sc) {
      final matchTitle = sc.title.toLowerCase().contains(q);
      final matchSit = (sc.situationName ?? '').toLowerCase().contains(q);
      final matchTag = sc.tags.any((t) => t.toLowerCase().contains(q)) ||
          sc.tag.toLowerCase().contains(q);
      final matchTime = sc.time.toLowerCase().contains(q);
      return matchTitle || matchSit || matchTag || matchTime;
    }).toList();
  }

  void _notifySchedules() {
    setState(() {});
    widget.onSchedulesChanged(widget.schedules);
  }

  void _notifySituations() {
    setState(() {});
    widget.onSituationsChanged(widget.situations);
  }

  Future<void> _triggerCalendarSync() async {
    if (widget.onSyncGoogleCalendar != null) {
      widget.onSyncGoogleCalendar!();
      return;
    }
    if (_localSyncing) return;
    HapticFeedback.selectionClick();
    setState(() => _localSyncing = true);

    try {
      final result = await GoogleSyncService.instance.syncSchedules(
        localSchedules: widget.schedules,
        situations: widget.situations,
      );
      if (!mounted) return;
      setState(() {
        widget.schedules
          ..clear()
          ..addAll(result.items);
        _localSyncing = false;
      });
      widget.onSchedulesChanged(widget.schedules);
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _localSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            GoogleSyncService.formatSyncError(e, featureName: '구글 캘린더'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Schedule> _cloneSchedulesSnapshot() {
    return widget.schedules
        .map((s) => s.copyWith(lastEditedTime: s.lastEditedTime))
        .toList();
  }

  void _removeOrSoftDeleteSchedule(Schedule schedule) {
    if (schedule.googleEventId != null && schedule.googleEventId!.isNotEmpty) {
      final idx = widget.schedules.indexWhere((s) => s.id == schedule.id);
      if (idx != -1) {
        widget.schedules[idx] = schedule.copyWith(
          isDeleted: true,
          lastEditedTime: DateTime.now(),
        );
      }
    } else {
      widget.schedules.removeWhere((s) => s.id == schedule.id);
    }
  }

  void _showUndoSnackBar(String message, List<Schedule> snapshot) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '실행 취소',
          onPressed: () {
            HapticFeedback.lightImpact();
            setState(() {
              widget.schedules
                ..clear()
                ..addAll(snapshot);
            });
            widget.onSchedulesChanged(widget.schedules);
          },
        ),
      ),
    );
  }

  Future<void> _deleteScheduleWithOptions(
    Schedule schedule,
    DateTime targetDay,
  ) async {
    final snapshot = _cloneSchedulesSnapshot();

    if (!schedule.isRepeating) {
      HapticFeedback.mediumImpact();
      setState(() => _removeOrSoftDeleteSchedule(schedule));
      _notifySchedules();
      _showUndoSnackBar("'${schedule.title}' 일정이 삭제되었습니다.", snapshot);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('반복 일정 삭제'),
        content: Text(
          "'${schedule.title}' 일정은 반복 일정입니다.\n삭제 범위를 선택해 주세요.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'only_this'),
            child: const Text('이 일정만 삭제'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'this_and_following'),
            child: const Text('이 일정 및 이후 일정 삭제'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text(
              '전체 반복 일정 삭제',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;
    HapticFeedback.mediumImpact();

    setState(() {
      if (choice == 'only_this') {
        final key = Schedule.dateKey(targetDay);
        if (!schedule.excludedDates.contains(key)) {
          schedule.excludedDates.add(key);
          schedule.markUpdated();
        }
      } else if (choice == 'this_and_following') {
        final dayBefore =
            DateTime(targetDay.year, targetDay.month, targetDay.day)
                .subtract(const Duration(days: 1));
        final startNorm = DateTime(
            schedule.date.year, schedule.date.month, schedule.date.day);
        if (dayBefore.isBefore(startNorm)) {
          _removeOrSoftDeleteSchedule(schedule);
        } else {
          schedule.repeatEndDate = dayBefore;
          schedule.repeatCount = null;
          schedule.markUpdated();
        }
      } else if (choice == 'all') {
        _removeOrSoftDeleteSchedule(schedule);
      }
    });

    _notifySchedules();
    _showUndoSnackBar('반복 일정 삭제가 반영되었습니다.', snapshot);
  }

  void _showScheduleDialog({DateTime? targetDate, Schedule? existing}) {
    final initialDay = targetDate ?? existing?.date ?? _selectedDay;
    DateTime startDate = DateTime(
      initialDay.year,
      initialDay.month,
      initialDay.day,
    );

    final titleController =
        TextEditingController(text: existing?.title ?? '');
    final tagInputController = TextEditingController();
    final intervalController = TextEditingController(
      text: (existing?.repeatInterval ?? 1).toString(),
    );
    final countController = TextEditingController(
      text: (existing?.repeatCount ?? 10).toString(),
    );

    String selectedTime = existing?.time ?? '09:00';
    String? selectedSituationName = existing?.situationName;
    final List<String> selectedTags = List<String>.from(existing?.tags ?? []);
    if (selectedTags.isEmpty &&
        existing != null &&
        existing.tag.trim().isNotEmpty) {
      selectedTags.add(existing.tag.trim());
    }

    int? prepMinutesBefore = existing?.prepMinutesBefore;
    ScheduleRepeatType repeatType =
        existing?.repeatType ?? ScheduleRepeatType.none;
    final List<int> repeatWeekdays = List<int>.from(
      existing?.repeatWeekdays.isNotEmpty == true
          ? existing!.repeatWeekdays
          : <int>[startDate.weekday],
    );

    // 'infinite' | 'endDate' | 'count'
    String repeatEndMode = 'infinite';
    if (existing?.repeatCount != null && existing!.repeatCount! > 0) {
      repeatEndMode = 'count';
    } else if (existing?.repeatEndDate != null) {
      repeatEndMode = 'endDate';
    }
    DateTime repeatEndDate =
        existing?.repeatEndDate ?? startDate.add(const Duration(days: 30));

    final tagPool = <String>{..._allTags, ...selectedTags};

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null
                    ? '${startDate.month}월 ${startDate.day}일 일정 추가'
                    : '일정 수정',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. 외출 상황 체크리스트 연결 (단일 선택)
                      if (widget.situations.isNotEmpty) ...[
                        const Text(
                          '외출 상황 체크리스트 연결',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ChoiceChip(
                              label: const Text('연결 안 함'),
                              selected: selectedSituationName == null ||
                                  selectedSituationName!.isEmpty,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                setDialogState(
                                    () => selectedSituationName = null);
                              },
                            ),
                            ...widget.situations.map((sit) {
                              final isSelected =
                                  selectedSituationName == sit.name;
                              return ChoiceChip(
                                avatar: Icon(
                                  sit.iconData,
                                  size: 16,
                                  color: isSelected ? Colors.white : sit.color,
                                ),
                                label: Text(sit.name),
                                selected: isSelected,
                                selectedColor: sit.color,
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : null,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                onSelected: (sel) {
                                  HapticFeedback.selectionClick();
                                  setDialogState(() {
                                    selectedSituationName =
                                        sel ? sit.name : null;
                                    if (sel &&
                                        titleController.text.trim().isEmpty) {
                                      titleController.text = sit.name;
                                    }
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],

                      // 2. 일정 이름
                      TextField(
                        controller: titleController,
                        autofocus: existing == null,
                        decoration: const InputDecoration(
                          labelText: '일정 이름 *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 3. 시작일 및 시간
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: startDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (picked != null) {
                                  setDialogState(() => startDate = picked);
                                }
                              },
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                '${startDate.year}.${startDate.month}.${startDate.day}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                HapticFeedback.selectionClick();
                                final parts = selectedTime.split(':');
                                final initial = TimeOfDay(
                                  hour: int.tryParse(parts[0]) ?? 9,
                                  minute: parts.length > 1
                                      ? (int.tryParse(parts[1]) ?? 0)
                                      : 0,
                                );
                                final picked = await showTimePicker(
                                  context: ctx,
                                  initialTime: initial,
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    selectedTime =
                                        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                  });
                                }
                              },
                              icon: const Icon(Icons.access_time, size: 16),
                              label: Text('시간: $selectedTime'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // 4. 다중 태그 선택 및 직접 추가
                      const Text(
                        '태그',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (tagPool.isNotEmpty) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: tagPool.map((t) {
                            final isSelected = selectedTags.contains(t);
                            return FilterChip(
                              label: Text('#$t'),
                              selected: isSelected,
                              onSelected: (sel) {
                                HapticFeedback.selectionClick();
                                setDialogState(() {
                                  if (sel) {
                                    selectedTags.add(t);
                                  } else {
                                    selectedTags.remove(t);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: tagInputController,
                              decoration: const InputDecoration(
                                hintText: '새 태그 입력',
                                prefixText: '#',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (val) {
                                final clean =
                                    val.trim().replaceAll('#', '');
                                if (clean.isNotEmpty) {
                                  setDialogState(() {
                                    tagPool.add(clean);
                                    if (!selectedTags.contains(clean)) {
                                      selectedTags.add(clean);
                                    }
                                    tagInputController.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: () {
                              final clean = tagInputController.text
                                  .trim()
                                  .replaceAll('#', '');
                              if (clean.isNotEmpty) {
                                setDialogState(() {
                                  tagPool.add(clean);
                                  if (!selectedTags.contains(clean)) {
                                    selectedTags.add(clean);
                                  }
                                  tagInputController.clear();
                                });
                              }
                            },
                            child: const Text('태그 추가'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // 5. 사전 준비시간 알림 설정
                      const Text(
                        '준비시간',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int?>(
                        initialValue: prepMinutesBefore,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('설정 안 함')),
                          DropdownMenuItem(value: 10, child: Text('10분 전')),
                          DropdownMenuItem(value: 15, child: Text('15분 전')),
                          DropdownMenuItem(value: 30, child: Text('30분 전')),
                          DropdownMenuItem(value: 60, child: Text('1시간 전')),
                          DropdownMenuItem(value: 120, child: Text('2시간 전')),
                        ],
                        onChanged: (val) =>
                            setDialogState(() => prepMinutesBefore = val),
                      ),
                      const SizedBox(height: 14),

                      // 6. 반복 설정 (n일/주/개월/년 + 요일 + 종료 조건)
                      const Text(
                        '반복 주기 설정',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (repeatType != ScheduleRepeatType.none) ...[
                            SizedBox(
                              width: 64,
                              child: TextField(
                                controller: intervalController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: DropdownButtonFormField<ScheduleRepeatType>(
                              initialValue: repeatType,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              items: ScheduleRepeatType.values
                                  .map(
                                    (rt) => DropdownMenuItem(
                                      value: rt,
                                      child: Text(rt.unitLabel),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() => repeatType = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      if (repeatType == ScheduleRepeatType.weekly) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 4,
                          children: List.generate(7, (index) {
                            final weekdayNum = index + 1;
                            final isSelected =
                                repeatWeekdays.contains(weekdayNum);
                            return FilterChip(
                              label: Text(_weekdayLabels[index]),
                              selected: isSelected,
                              onSelected: (selected) {
                                HapticFeedback.selectionClick();
                                setDialogState(() {
                                  if (selected) {
                                    repeatWeekdays.add(weekdayNum);
                                    repeatWeekdays.sort();
                                  } else if (repeatWeekdays.length > 1) {
                                    repeatWeekdays.remove(weekdayNum);
                                  }
                                });
                              },
                            );
                          }),
                        ),
                      ],

                      if (repeatType != ScheduleRepeatType.none) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: repeatEndMode,
                          decoration: const InputDecoration(
                            labelText: '반복 종료 조건',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'infinite',
                              child: Text('계속 반복'),
                            ),
                            DropdownMenuItem(
                              value: 'endDate',
                              child: Text('종료일 지정'),
                            ),
                            DropdownMenuItem(
                              value: 'count',
                              child: Text('반복 횟수(N회) 지정'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => repeatEndMode = val);
                            }
                          },
                        ),
                        if (repeatEndMode == 'endDate') ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: repeatEndDate,
                                firstDate: startDate,
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setDialogState(() => repeatEndDate = picked);
                              }
                            },
                            icon: const Icon(Icons.event_busy, size: 16),
                            label: Text(
                              '종료일: ${repeatEndDate.year}.${repeatEndDate.month}.${repeatEndDate.day}',
                            ),
                          ),
                        ] else if (repeatEndMode == 'count') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: countController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '총 반복 횟수 (회)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteScheduleWithOptions(existing, _selectedDay);
                    },
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                    label: const Text(
                      '삭제',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;

                    final parsedInterval =
                        (int.tryParse(intervalController.text.trim()) ?? 1)
                            .clamp(1, 365);
                    final parsedCount = repeatEndMode == 'count'
                        ? (int.tryParse(countController.text.trim()) ?? 1)
                            .clamp(1, 999)
                        : null;
                    final finalEndDate =
                        repeatEndMode == 'endDate' ? repeatEndDate : null;
                    final finalWeekdays =
                        repeatType == ScheduleRepeatType.weekly
                            ? List<int>.from(repeatWeekdays)
                            : <int>[];

                    for (final t in selectedTags) {
                      _knownTags.add(t);
                      _selectedFilterKeys.add(t);
                    }

                    HapticFeedback.mediumImpact();

                    if (existing == null) {
                      final created = Schedule(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        date: startDate,
                        title: title,
                        time: selectedTime,
                        tags: selectedTags,
                        situationName: selectedSituationName,
                        repeatType: repeatType,
                        repeatInterval: parsedInterval,
                        repeatWeekdays: finalWeekdays,
                        repeatEndDate: finalEndDate,
                        repeatCount: parsedCount,
                        prepMinutesBefore: prepMinutesBefore,
                        lastEditedTime: DateTime.now(),
                      );
                      widget.schedules.add(created);
                      widget.onScheduleSavedOrUpdated?.call(created);
                      _notifySchedules();
                      if (ctx.mounted) Navigator.pop(ctx);
                      return;
                    }

                    if (!existing.isRepeating) {
                      existing.date = startDate;
                      existing.title = title;
                      existing.time = selectedTime;
                      existing.tags = List<String>.from(selectedTags);
                      existing.situationName = selectedSituationName;
                      existing.repeatType = repeatType;
                      existing.repeatInterval = parsedInterval;
                      existing.repeatWeekdays = finalWeekdays;
                      existing.repeatEndDate = finalEndDate;
                      existing.repeatCount = parsedCount;
                      existing.prepMinutesBefore = prepMinutesBefore;
                      existing.markUpdated();
                      widget.onScheduleSavedOrUpdated?.call(existing);
                      _notifySchedules();
                      if (ctx.mounted) Navigator.pop(ctx);
                      return;
                    }

                    // 기존 반복 일정 수정 시 범위 선택 다이얼로그
                    final editScope = await showDialog<String>(
                      context: ctx,
                      builder: (scopeCtx) => AlertDialog(
                        title: const Text('반복 일정 수정'),
                        content: const Text('변경 사항을 적용할 범위를 선택해 주세요.'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(scopeCtx, 'only_this'),
                            child: const Text('이 일정만 변경'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(scopeCtx, 'this_and_following'),
                            child: const Text('이 일정 및 이후 일정 변경'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(scopeCtx, 'all'),
                            child: const Text(
                              '전체 반복 일정 변경',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (editScope == null) return;

                    if (editScope == 'only_this') {
                      final key = Schedule.dateKey(_selectedDay);
                      if (!existing.excludedDates.contains(key)) {
                        existing.excludedDates.add(key);
                        existing.markUpdated();
                      }
                      final single = Schedule(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        date: _selectedDay,
                        title: title,
                        time: selectedTime,
                        tags: selectedTags,
                        situationName: selectedSituationName,
                        repeatType: ScheduleRepeatType.none,
                        prepMinutesBefore: prepMinutesBefore,
                        lastEditedTime: DateTime.now(),
                      );
                      widget.schedules.add(single);
                      widget.onScheduleSavedOrUpdated?.call(single);
                    } else if (editScope == 'this_and_following') {
                      final dayBefore = DateTime(
                        _selectedDay.year,
                        _selectedDay.month,
                        _selectedDay.day,
                      ).subtract(const Duration(days: 1));
                      existing.repeatEndDate = dayBefore;
                      existing.repeatCount = null;
                      existing.markUpdated();

                      final split = Schedule(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        date: _selectedDay,
                        title: title,
                        time: selectedTime,
                        tags: selectedTags,
                        situationName: selectedSituationName,
                        repeatType: repeatType,
                        repeatInterval: parsedInterval,
                        repeatWeekdays: finalWeekdays,
                        repeatEndDate: finalEndDate,
                        repeatCount: parsedCount,
                        prepMinutesBefore: prepMinutesBefore,
                        lastEditedTime: DateTime.now(),
                      );
                      widget.schedules.add(split);
                      widget.onScheduleSavedOrUpdated?.call(split);
                    } else {
                      existing.date = startDate;
                      existing.title = title;
                      existing.time = selectedTime;
                      existing.tags = List<String>.from(selectedTags);
                      existing.situationName = selectedSituationName;
                      existing.repeatType = repeatType;
                      existing.repeatInterval = parsedInterval;
                      existing.repeatWeekdays = finalWeekdays;
                      existing.repeatEndDate = finalEndDate;
                      existing.repeatCount = parsedCount;
                      existing.prepMinutesBefore = prepMinutesBefore;
                      existing.markUpdated();
                      widget.onScheduleSavedOrUpdated?.call(existing);
                    }

                    _notifySchedules();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLinkedChecklistSheet(Schedule schedule, Situation situation) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final total = situation.items.length;
            final checked = situation.checkedCount;
            final progress = situation.progress;
            final isComplete = situation.isAllChecked;
            final activeColor = isComplete ? Colors.green : situation.color;

            void refreshBoth() {
              setSheetState(() {});
              _notifySituations();
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                activeColor.withValues(alpha: 0.15),
                            child: Icon(
                              isComplete ? Icons.verified : situation.iconData,
                              color: activeColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${schedule.title} (${schedule.time})',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  isComplete
                                      ? '외출 준비 완료! 🎉'
                                      : '${situation.name} 체크리스트 현황: $checked / $total개 (${(progress * 100).round()}%)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isComplete
                                        ? Colors.green
                                        : Colors.grey.shade600,
                                    fontWeight: isComplete
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (total > 0)
                            FilledButton.tonalIcon(
                              onPressed: () {
                                final nextState = !isComplete;
                                if (nextState) {
                                  HapticFeedback.heavyImpact();
                                } else {
                                  HapticFeedback.lightImpact();
                                }
                                for (final item in situation.items) {
                                  item.isChecked = nextState;
                                }
                                refreshBoth();
                              },
                              icon: Icon(
                                isComplete
                                    ? Icons.restart_alt
                                    : Icons.done_all,
                                size: 18,
                              ),
                              label: Text(isComplete ? '전체 해제' : '전체 체크'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 250),
                        builder: (context, value, _) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 8,
                              backgroundColor:
                                  Colors.grey.withValues(alpha: 0.2),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(activeColor),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: situation.items.isEmpty
                            ? const Center(
                                child: Text(
                                  '등록된 체크리스트 항목이 없습니다. [상황·체크리스트] 탭에서 추가해 보세요.',
                                ),
                              )
                            : ReorderableListView.builder(
                                scrollController: scrollController,
                                itemCount: situation.items.length,
                                onReorderStart: (_) =>
                                    HapticFeedback.selectionClick(),
                                onReorderItem: (oldIndex, newIndex) {
                                  HapticFeedback.mediumImpact();
                                  if (newIndex > oldIndex) newIndex -= 1;
                                  final moved =
                                      situation.items.removeAt(oldIndex);
                                  situation.items.insert(newIndex, moved);
                                  refreshBoth();
                                },
                                itemBuilder: (context, idx) {
                                  final item = situation.items[idx];
                                  return CheckboxListTile(
                                    key: ValueKey('sheet_${item.id}'),
                                    value: item.isChecked,
                                    activeColor: activeColor,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(
                                      item.name,
                                      style: TextStyle(
                                        decoration: item.isChecked
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: item.isChecked
                                            ? Colors.grey
                                            : null,
                                      ),
                                    ),
                                    secondary: const Icon(Icons.drag_handle),
                                    onChanged: (val) {
                                      item.isChecked = val ?? false;
                                      if (situation.isAllChecked) {
                                        HapticFeedback.heavyImpact();
                                      } else {
                                        HapticFeedback.lightImpact();
                                      }
                                      refreshBoth();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  double _targetHeightForStage(_CalendarHeightStage stage, double maxHeight) {
    switch (stage) {
      case _CalendarHeightStage.twoWeeks:
        return (maxHeight * 0.30).clamp(185.0, 260.0);
      case _CalendarHeightStage.month:
        return (maxHeight * 0.52).clamp(320.0, 430.0);
      case _CalendarHeightStage.expanded:
        return (maxHeight * 0.74).clamp(440.0, 620.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final daySchedules = _getSchedulesForDay(_selectedDay);
    final dayTodos = _getTodosForDay(_selectedDay);
    final allTags = _allTags;
    final allChipsSelected = _selectedFilterKeys.contains(_todoFilterKey) &&
        allTags.every((t) => _selectedFilterKeys.contains(t));

    return ValueListenableBuilder<bool>(
      valueListenable: SettingsScreen.googleCalendarSyncNotifier,
      builder: (context, notifierCalSynced, _) {
        final showSyncButton =
            widget.isGoogleCalendarSynced ?? notifierCalSynced;
        final isSyncing = widget.isSyncingCalendar || _localSyncing;

        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final maxH = constraints.maxHeight;
              final calendarHeight = _dragHeightOverride ??
                  _targetHeightForStage(_heightStage, maxH);
              final rowHeight =
                  ((calendarHeight - 72) /
                          (_heightStage == _CalendarHeightStage.twoWeeks
                              ? 2.2
                              : 6.0))
                      .clamp(38.0, 74.0);

              return Column(
                children: [
                  // --- 상단 다중 태그·할 일 필터 바 & 검색 & 구글 캘린더 동기화 버튼 (옵션 B) ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _isSearching
                              ? TextField(
                                  controller: _searchController,
                                  autofocus: true,
                                  decoration: InputDecoration(
                                    hintText: '일정 이름·태그·상황·시간 검색...',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        setState(() {
                                          _isSearching = false;
                                          _searchQuery = '';
                                          _searchController.clear();
                                        });
                                      },
                                    ),
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onChanged: (val) =>
                                      setState(() => _searchQuery = val),
                                )
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      FilterChip(
                                        label: const Text('전체'),
                                        selected: allChipsSelected,
                                        onSelected: (_) {
                                          HapticFeedback.selectionClick();
                                          setState(() {
                                            if (allChipsSelected) {
                                              _selectedFilterKeys.clear();
                                            } else {
                                              _selectedFilterKeys
                                                  .add(_todoFilterKey);
                                              _selectedFilterKeys
                                                  .addAll(allTags);
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      FilterChip(
                                        avatar: const Icon(
                                          Icons.task_alt,
                                          size: 16,
                                          color: Colors.teal,
                                        ),
                                        label: const Text('할 일'),
                                        selected: _selectedFilterKeys
                                            .contains(_todoFilterKey),
                                        onSelected: (sel) {
                                          HapticFeedback.selectionClick();
                                          setState(() {
                                            if (sel) {
                                              _selectedFilterKeys
                                                  .add(_todoFilterKey);
                                            } else {
                                              _selectedFilterKeys
                                                  .remove(_todoFilterKey);
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      ...allTags.map((tag) {
                                        final isSelected =
                                            _selectedFilterKeys.contains(tag);
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(right: 6),
                                          child: FilterChip(
                                            label: Text('#$tag'),
                                            selected: isSelected,
                                            onSelected: (selected) {
                                              HapticFeedback.selectionClick();
                                              setState(() {
                                                if (selected) {
                                                  _selectedFilterKeys.add(tag);
                                                } else {
                                                  _selectedFilterKeys
                                                      .remove(tag);
                                                }
                                              });
                                            },
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                        ),
                        if (!_isSearching)
                          IconButton(
                            tooltip: '일정 검색',
                            icon: const Icon(Icons.search),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => _isSearching = true);
                            },
                          ),
                        // 옵션 B: 구글 캘린더 연동 시 화면 상단 내부 동기화(🔄) 버튼 표시
                        if (showSyncButton)
                          IconButton(
                            tooltip: 'Google 캘린더 동기화',
                            onPressed: isSyncing ? null : _triggerCalendarSync,
                            icon: isSyncing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(Icons.sync, color: scheme.primary),
                          ),
                      ],
                    ),
                  ),

                  if (_isSearching && _searchQuery.trim().isNotEmpty)
                    Expanded(
                      child: _searchedSchedules.isEmpty
                          ? const Center(child: Text('일치하는 일정이 없습니다.'))
                          : ListView.builder(
                              itemCount: _searchedSchedules.length,
                              itemBuilder: (context, idx) {
                                final sc = _searchedSchedules[idx];
                                return ListTile(
                                  leading: const Icon(Icons.event_note),
                                  title: Text(sc.title),
                                  subtitle: Text(
                                    '${Schedule.dateKey(sc.date)} (${sc.time})  ${sc.tags.map((t) => '#$t').join(' ')}',
                                  ),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _selectedDay = sc.date;
                                      _focusedDay = sc.date;
                                      _isSearching = false;
                                      _searchQuery = '';
                                      _searchController.clear();
                                    });
                                  },
                                );
                              },
                            ),
                    )
                  else ...[
                    if (widget.showTips)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.touch_app,
                              size: 14,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '팁: 날짜를 길게 누르면 일정을 바로 추가하며, 달력 하단 바를 끌어 높이를 3단계로 조절할 수 있습니다.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // --- 3단계 반응형 높이 조절 달력 ---
                    AnimatedContainer(
                      duration: _dragHeightOverride != null
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      height: calendarHeight,
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: TableCalendar<Object>(
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2035, 12, 31),
                          focusedDay: _focusedDay,
                          calendarFormat:
                              _heightStage == _CalendarHeightStage.twoWeeks
                                  ? CalendarFormat.twoWeeks
                                  : CalendarFormat.month,
                          selectedDayPredicate: (day) =>
                              isSameDay(_selectedDay, day),
                          rowHeight: rowHeight,
                          headerStyle: const HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                          ),
                          eventLoader: (day) => <Object>[
                            ..._getSchedulesForDay(day),
                            ..._getTodosForDay(day),
                          ],
                          onDaySelected: (selectedDay, focusedDay) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                            });
                          },
                          onDayLongPressed: (selectedDay, focusedDay) {
                            HapticFeedback.heavyImpact();
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                            });
                            _showScheduleDialog(targetDate: selectedDay);
                          },
                          onPageChanged: (focusedDay) {
                            _focusedDay = focusedDay;
                          },
                          calendarBuilders: CalendarBuilders(
                            markerBuilder: (context, date, events) {
                              if (events.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: events.take(2).map((ev) {
                                    if (ev is Schedule) {
                                      final sit = _findSituationForSchedule(ev);
                                      final badgeColor =
                                          sit?.color ?? scheme.primary;
                                      return Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 0.5,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 3),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withValues(
                                              alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          ev.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: badgeColor,
                                          ),
                                        ),
                                      );
                                    } else if (ev is TodoItem) {
                                      return Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 0.5,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.teal
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          ev.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.teal,
                                            decoration: ev.isCompleted
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }).toList(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                    // --- 3단계 자석 스냅 드래그 핸들 바 ---
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        setState(() {
                          _dragHeightOverride =
                              (calendarHeight + details.delta.dy)
                                  .clamp(170.0, maxH * 0.78);
                        });
                      },
                      onVerticalDragEnd: (_) {
                        final current = _dragHeightOverride ?? calendarHeight;
                        final hTwo = _targetHeightForStage(
                            _CalendarHeightStage.twoWeeks, maxH);
                        final hMon = _targetHeightForStage(
                            _CalendarHeightStage.month, maxH);
                        final hExp = _targetHeightForStage(
                            _CalendarHeightStage.expanded, maxH);

                        final d1 = (current - hTwo).abs();
                        final d2 = (current - hMon).abs();
                        final d3 = (current - hExp).abs();

                        HapticFeedback.selectionClick();
                        setState(() {
                          _dragHeightOverride = null;
                          if (d1 <= d2 && d1 <= d3) {
                            _heightStage = _CalendarHeightStage.twoWeeks;
                          } else if (d2 <= d3) {
                            _heightStage = _CalendarHeightStage.month;
                          } else {
                            _heightStage = _CalendarHeightStage.expanded;
                          }
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        alignment: Alignment.center,
                        child: Container(
                          width: 44,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),

                    // --- 선택된 날짜의 일정 및 할 일 리스트 ---
                    Expanded(
                      child: _selectedFilterKeys.isEmpty
                          ? const Center(
                              child: Text(
                                '선택된 필터가 없습니다. 상단 필터를 1개 이상 선택해 주세요.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : (daySchedules.isEmpty && dayTodos.isEmpty)
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${_selectedDay.month}월 ${_selectedDay.day}일에 등록된 일정이 없습니다.',
                                        style: const TextStyle(
                                            color: Colors.grey),
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: () => _showScheduleDialog(
                                            targetDate: _selectedDay),
                                        icon: const Icon(Icons.add),
                                        label:
                                            const Text('이 날짜에 일정 추가하기'),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 8, 12, 88),
                                  children: [
                                    ...daySchedules.map((sc) {
                                      final linkedSituation =
                                          _findSituationForSchedule(sc);
                                      final color = linkedSituation?.color ??
                                          scheme.primary;
                                      final isComplete =
                                          linkedSituation?.isAllChecked ??
                                              false;

                                      return Dismissible(
                                        key: ValueKey(
                                            'sched_${sc.id}_${_selectedDay.day}'),
                                        direction: DismissDirection.endToStart,
                                        confirmDismiss: (_) async {
                                          await _deleteScheduleWithOptions(
                                              sc, _selectedDay);
                                          return false;
                                        },
                                        background: Container(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 20),
                                          alignment: Alignment.centerRight,
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              Text(
                                                '일정 삭제',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(Icons.delete_outline,
                                                  color: Colors.white),
                                            ],
                                          ),
                                        ),
                                        child: Card(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            side: BorderSide(
                                              color: isComplete
                                                  ? Colors.green
                                                      .withValues(alpha: 0.7)
                                                  : color.withValues(
                                                      alpha: 0.3),
                                            ),
                                          ),
                                          child: ListTile(
                                            onTap: () {
                                              if (linkedSituation != null) {
                                                _showLinkedChecklistSheet(
                                                    sc, linkedSituation);
                                              } else {
                                                _showScheduleDialog(
                                                    existing: sc);
                                              }
                                            },
                                            leading: CircleAvatar(
                                              backgroundColor: color
                                                  .withValues(alpha: 0.15),
                                              child: Icon(
                                                linkedSituation?.iconData ??
                                                    Icons.event,
                                                color: color,
                                              ),
                                            ),
                                            title: Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    sc.title,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                if (sc.googleEventId !=
                                                    null) ...[
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    Icons.cloud_done_outlined,
                                                    size: 15,
                                                    color: scheme.primary,
                                                  ),
                                                ],
                                              ],
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                            Icons.access_time,
                                                            size: 14),
                                                        const SizedBox(
                                                            width: 3),
                                                        Text(sc.time),
                                                      ],
                                                    ),
                                                    if (sc.isRepeating)
                                                      Text(
                                                        '🔁 ${sc.repeatSummaryText}',
                                                        style: const TextStyle(
                                                            fontSize: 12),
                                                      ),
                                                    if (sc.hasPrepTime)
                                                      Text(
                                                        '⏰ ${sc.prepSummaryText}',
                                                        style: const TextStyle(
                                                            fontSize: 12),
                                                      ),
                                                  ],
                                                ),
                                                if (sc.tags.isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    spacing: 4,
                                                    children: sc.tags
                                                        .map(
                                                          (t) => Text(
                                                            '#$t',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: color,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        )
                                                        .toList(),
                                                  ),
                                                ],
                                                if (linkedSituation != null &&
                                                    linkedSituation
                                                        .items.isNotEmpty) ...[
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                          child:
                                                              LinearProgressIndicator(
                                                            value:
                                                                linkedSituation
                                                                    .progress,
                                                            minHeight: 6,
                                                            backgroundColor: Colors
                                                                .grey
                                                                .withValues(
                                                                    alpha: 0.2),
                                                            valueColor:
                                                                AlwaysStoppedAnimation<
                                                                    Color>(
                                                              isComplete
                                                                  ? Colors.green
                                                                  : color,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        isComplete
                                                            ? '준비 완료 🎉'
                                                            : '${linkedSituation.name} ${linkedSituation.checkedCount}/${linkedSituation.items.length}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isComplete
                                                              ? Colors.green
                                                              : color,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (linkedSituation != null)
                                                  IconButton(
                                                    tooltip:
                                                        '체크리스트 열기',
                                                    icon: Icon(
                                                      Icons
                                                          .fact_check_outlined,
                                                      color: isComplete
                                                          ? Colors.green
                                                          : color,
                                                    ),
                                                    onPressed: () =>
                                                        _showLinkedChecklistSheet(
                                                      sc,
                                                      linkedSituation,
                                                    ),
                                                  ),
                                                IconButton(
                                                  tooltip: '일정 수정',
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 20,
                                                  ),
                                                  onPressed: () =>
                                                      _showScheduleDialog(
                                                          existing: sc),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }),

                                    // --- 캘린더에 연동 표시되는 할 일(To-Do) 카드 (완료 시 취소선) ---
                                    ...dayTodos.map((todo) {
                                      final isOverdue =
                                          todo.isOverdueAt(DateTime.now());
                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: CheckboxListTile(
                                          value: todo.isCompleted,
                                          activeColor: Colors.teal,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          title: Text(
                                            todo.title,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              decoration: todo.isCompleted
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              color: todo.isCompleted
                                                  ? Colors.grey
                                                  : (isOverdue
                                                      ? Colors.redAccent
                                                      : null),
                                            ),
                                          ),
                                          subtitle: Text(
                                            todo.dueTime != null
                                                ? '할 일 · 마감 ${todo.dueTime}'
                                                : '할 일 · 하루 종일',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isOverdue
                                                  ? Colors.redAccent
                                                  : null,
                                            ),
                                          ),
                                          onChanged: (val) {
                                            HapticFeedback.lightImpact();
                                            setState(() {
                                              todo.toggleCompleted(
                                                val ?? false,
                                                DateTime.now(),
                                              );
                                            });
                                            widget.onTodosChanged
                                                ?.call(widget.todos);
                                          },
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                    ),
                  ],
                ],
              );
            },
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showScheduleDialog(targetDate: _selectedDay),
            icon: const Icon(Icons.add),
            label: const Text('일정 추가'),
          ),
        );
      },
    );
  }
}