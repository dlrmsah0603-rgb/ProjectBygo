import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/schedule_model.dart';
import '../models/situation_model.dart';
import '../models/todo_model.dart';

enum _CalendarStage { twoWeeks, month, expanded }

enum _RepeatEndMode { forever, untilDate, count }

class CalendarScreen extends StatefulWidget {
  final List<Schedule> schedules;
  final List<Situation> situations;
  final List<TodoItem> todos;
  final bool showTips;
  final ValueChanged<Schedule>? onScheduleSavedOrUpdated;
  final ValueChanged<List<Schedule>> onSchedulesChanged;
  final ValueChanged<List<Situation>> onSituationsChanged;
  final ValueChanged<List<TodoItem>>? onTodosChanged;

  const CalendarScreen({
    super.key,
    required this.schedules,
    required this.situations,
    this.todos = const [],
    this.showTips = true,
    this.onScheduleSavedOrUpdated,
    required this.onSchedulesChanged,
    required this.onSituationsChanged,
    this.onTodosChanged,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const String _tagOrderPrefsKey = 'bygo_calendar_tag_order';
  static const String _knownTagsPrefsKey = 'bygo_known_tags_pool';
  static const String _todoFilterKey = '__TODO_FILTER__';

  static const List<String> _weekdayLabels = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  static const List<MapEntry<String, int?>> _prepOptions = [
    MapEntry('설정 안 함', null),
    MapEntry('10분 전', 10),
    MapEntry('15분 전', 15),
    MapEntry('30분 전', 30),
    MapEntry('1시간 전', 60),
    MapEntry('2시간 전', 120),
  ];

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  // 다중 태그 필터 상태
  bool _isAllFilterSelected = true;
  final Set<String> _selectedFilterTags = <String>{};
  List<String> _savedTagOrder = [];
  Set<String> _knownTagsPool = <String>{};

  // 검색 상태
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // 캘린더 3단계(2주 / 한달 / 확장) 높이 조절 및 드래그 스냅 상태
  _CalendarStage _stage = _CalendarStage.month;
  double? _dragCalendarHeight;

  @override
  void initState() {
    super.initState();
    _loadSavedTagMetadata();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedTagMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final order = prefs.getStringList(_tagOrderPrefsKey);
      final pool = prefs.getStringList(_knownTagsPrefsKey);
      if (mounted) {
        setState(() {
          if (order != null) _savedTagOrder = order;
          if (pool != null) _knownTagsPool = pool.toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveTagOrderToPrefs(List<String> order) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_tagOrderPrefsKey, order);
    } catch (_) {}
  }

  Future<void> _addTagsToKnownPool(Iterable<String> newTags) async {
    bool modified = false;
    for (final t in newTags) {
      final clean = t.trim().replaceAll('#', '');
      if (clean.isNotEmpty && !_knownTagsPool.contains(clean)) {
        _knownTagsPool.add(clean);
        modified = true;
      }
    }
    if (modified) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_knownTagsPrefsKey, _knownTagsPool.toList());
      } catch (_) {}
    }
  }

  /// 캘린더 상단 필터 바 및 일정 추가 창에서 사용할 전체 태그 목록
  /// (오직 일정들에 등록된 태그 및 사용자가 추가한 태그만 수집, 상황 이름은 섞지 않음)
  List<String> get _orderedTags {
    final currentTags = <String>{..._knownTagsPool};
    for (final sc in widget.schedules) {
      for (final rawTag in sc.tags) {
        final t = rawTag.trim();
        if (t.isNotEmpty) currentTags.add(t);
      }
    }

    final result = <String>[];
    for (final saved in _savedTagOrder) {
      if (currentTags.contains(saved)) {
        result.add(saved);
        currentTags.remove(saved);
      }
    }
    result.addAll(currentTags);
    return result;
  }

  bool get _hasNoFilterSelected =>
      !_isAllFilterSelected && _selectedFilterTags.isEmpty;

  bool get _shouldShowTodos =>
      _isAllFilterSelected || _selectedFilterTags.contains(_todoFilterKey);

  /// 상황 이름(situationName)으로 Situation 객체 조회
  Situation? _findSituationByName(String? situationName) {
    final clean = situationName?.trim() ?? '';
    if (clean.isEmpty) return null;
    for (final s in widget.situations) {
      if (s.name.trim() == clean) return s;
    }
    return null;
  }

  bool _scheduleMatchesFilter(Schedule schedule) {
    if (_hasNoFilterSelected) return false;
    if (_isAllFilterSelected) return true;
    if (schedule.tags.isEmpty) return false;
    return schedule.tags.any((t) => _selectedFilterTags.contains(t.trim()));
  }

  List<Schedule> _getSchedulesForDay(DateTime day) {
    if (_hasNoFilterSelected) return [];
    return widget.schedules.where((sc) {
      if (!sc.occursOn(day)) return false;
      return _scheduleMatchesFilter(sc);
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  List<TodoItem> _getTodosForDay(DateTime day) {
    if (!_shouldShowTodos) return [];
    return widget.todos.where((todo) {
      if (todo.dueDate == null) return false;
      return todo.dueDate!.year == day.year &&
          todo.dueDate!.month == day.month &&
          todo.dueDate!.day == day.day;
    }).toList()
      ..sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        final aTime = a.dueTime ?? '99:99';
        final bTime = b.dueTime ?? '99:99';
        return aTime.compareTo(bTime);
      });
  }

  List<Object> _getCalendarEventsForDay(DateTime day) {
    final events = <Object>[];
    events.addAll(_getSchedulesForDay(day));
    events.addAll(_getTodosForDay(day));
    return events;
  }

  List<Schedule> get _searchedSchedules {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return [];
    return widget.schedules.where((sc) {
      final matchesTitle = sc.title.toLowerCase().contains(q);
      final matchesTime = sc.time.toLowerCase().contains(q);
      final matchesTags =
          sc.tags.any((t) => t.toLowerCase().contains(q));
      final matchesSituation =
          (sc.situationName?.toLowerCase().contains(q) ?? false);
      return matchesTitle || matchesTime || matchesTags || matchesSituation;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  void _notifySchedules([Schedule? savedOrUpdated]) {
    setState(() {});
    widget.onSchedulesChanged(widget.schedules);
    if (savedOrUpdated != null) {
      widget.onScheduleSavedOrUpdated?.call(savedOrUpdated);
    }
  }

  void _notifySituations() {
    setState(() {});
    widget.onSituationsChanged(widget.situations);
  }

  void _notifyTodos() {
    setState(() {});
    widget.onTodosChanged?.call(widget.todos);
  }

  void _toggleAllFilter() {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_isAllFilterSelected) {
        _selectedFilterTags.clear();
        _isAllFilterSelected = true;
      } else {
        _isAllFilterSelected = false;
      }
    });
  }

  void _toggleIndividualFilter(String filterKey) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_isAllFilterSelected) {
        _isAllFilterSelected = false;
        _selectedFilterTags
          ..clear()
          ..add(filterKey);
      } else {
        if (_selectedFilterTags.contains(filterKey)) {
          _selectedFilterTags.remove(filterKey);
        } else {
          _selectedFilterTags.add(filterKey);
        }
      }
    });
  }

  void _registerCompletedChecklistToCalendar(Situation situation) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final currentTimeStr = '$hh:$mm';
    final recordTitle = '${situation.name} 체크리스트 완료';

    Schedule? existingRecord;
    for (final sc in widget.schedules) {
      if (sc.isAutoRecord &&
          sc.situationName?.trim() == situation.name.trim() &&
          sc.date.year == today.year &&
          sc.date.month == today.month &&
          sc.date.day == today.day) {
        existingRecord = sc;
        break;
      }
    }

    Schedule? addedOrUpdated;
    bool wasAdded = false;

    setState(() {
      if (existingRecord != null) {
        existingRecord.time = currentTimeStr;
        existingRecord.title = recordTitle;
        addedOrUpdated = existingRecord;
      } else {
        addedOrUpdated = Schedule(
          id: 'record_${now.microsecondsSinceEpoch}',
          date: today,
          title: recordTitle,
          time: currentTimeStr,
          situationName: situation.name,
          isAutoRecord: true,
        );
        widget.schedules.add(addedOrUpdated!);
        wasAdded = true;
      }
    });
    widget.onSchedulesChanged(widget.schedules);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "🎉 '${situation.name}' 체크리스트 완료! 캘린더에 기록이 자동 추가되었습니다.",
        ),
        behavior: SnackBarBehavior.floating,
        action: wasAdded
            ? SnackBarAction(
                label: '실행 취소',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    if (addedOrUpdated != null) {
                      widget.schedules.remove(addedOrUpdated);
                    }
                  });
                  widget.onSchedulesChanged(widget.schedules);
                },
              )
            : null,
      ),
    );
  }

  // --- 일정 삭제 및 반복 일정 예외 삭제 ---
  Future<void> _handleDeleteSchedule(
    Schedule schedule,
    DateTime targetDate,
  ) async {
    if (!schedule.isRepeating) {
      _deleteEntireScheduleWithUndo(schedule);
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('반복 일정 삭제'),
        content: Text(
          "'${schedule.title}'은(는) 반복 일정입니다.\n삭제할 범위를 선택해 주세요.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'only_this'),
            child: const Text('이 일정만 삭제'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'this_and_future'),
            child: const Text('이 일정 및 이후 일정 삭제'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('전체 반복 삭제'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;
    HapticFeedback.mediumImpact();

    if (choice == 'only_this') {
      final key = Schedule.dateKey(targetDate);
      if (!schedule.excludedDates.contains(key)) {
        schedule.excludedDates.add(key);
      }
      _notifySchedules();
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${targetDate.month}/${targetDate.day} 일정만 삭제되었습니다.',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '실행 취소',
            onPressed: () {
              schedule.excludedDates.remove(key);
              _notifySchedules();
            },
          ),
        ),
      );
    } else if (choice == 'this_and_future') {
      final prevEndDate = schedule.repeatEndDate;
      final prevRepeatCount = schedule.repeatCount;
      final dayBefore = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      ).subtract(const Duration(days: 1));
      final startDay = DateTime(
        schedule.date.year,
        schedule.date.month,
        schedule.date.day,
      );

      if (dayBefore.isBefore(startDay)) {
        _deleteEntireScheduleWithUndo(schedule);
        return;
      }

      schedule.repeatEndDate = dayBefore;
      schedule.repeatCount = null;
      _notifySchedules();

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${targetDate.month}/${targetDate.day} 이후 반복 일정이 삭제되었습니다.',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '실행 취소',
            onPressed: () {
              schedule.repeatEndDate = prevEndDate;
              schedule.repeatCount = prevRepeatCount;
              _notifySchedules();
            },
          ),
        ),
      );
    } else if (choice == 'all') {
      _deleteEntireScheduleWithUndo(schedule);
    }
  }

  void _deleteEntireScheduleWithUndo(Schedule schedule) {
    final idx = widget.schedules.indexOf(schedule);
    if (idx == -1) return;
    widget.schedules.removeAt(idx);
    HapticFeedback.mediumImpact();
    _notifySchedules();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("'${schedule.title}' 일정이 삭제되었습니다."),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '실행 취소',
          onPressed: () {
            HapticFeedback.lightImpact();
            final insertIdx = idx.clamp(0, widget.schedules.length);
            widget.schedules.insert(insertIdx, schedule);
            _notifySchedules(schedule);
          },
        ),
      ),
    );
  }

  // --- 일정 추가 / 수정 다이얼로그 (다중 태그 칩 선택 + 단일 상황 선택 + 반복 설정) ---
  void _showScheduleDialog({DateTime? targetDate, Schedule? existing}) {
    final initialDay = targetDate ?? existing?.date ?? _selectedDay;
    DateTime selectedStartDate = DateTime(
      (existing?.date ?? initialDay).year,
      (existing?.date ?? initialDay).month,
      (existing?.date ?? initialDay).day,
    );

    final titleController =
        TextEditingController(text: existing?.title ?? '');
    String selectedTime = existing?.time ?? '09:00';
    int? selectedPrepMinutes = existing?.prepMinutesBefore;

    // 1) 다중 태그 선택 상태
    final List<String> availableTags = List<String>.from(_orderedTags);
    final Set<String> selectedTags = existing != null
        ? existing.tags.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()
        : <String>{};
    for (final t in selectedTags) {
      if (!availableTags.contains(t)) {
        availableTags.add(t);
      }
    }

    // 2) 단일 상황(체크리스트) 선택 상태 (상황 이름으로 매핑, 미선택 시 null)
    String? selectedSituationName = existing?.situationName?.trim();
    if (selectedSituationName != null && selectedSituationName.isEmpty) {
      selectedSituationName = null;
    }

    // 3) 반복 설정 상태
    ScheduleRepeatType selectedRepeatType =
        existing?.repeatType ?? ScheduleRepeatType.none;
    final intervalController = TextEditingController(
      text: (existing?.repeatInterval ?? 1).toString(),
    );

    final List<int> selectedWeekdays = existing != null &&
            existing.repeatWeekdays.isNotEmpty
        ? List<int>.from(existing.repeatWeekdays)
        : [selectedStartDate.weekday];

    _RepeatEndMode endMode = _RepeatEndMode.forever;
    if (existing?.repeatEndDate != null) {
      endMode = _RepeatEndMode.untilDate;
    } else if (existing?.repeatCount != null && existing!.repeatCount! > 0) {
      endMode = _RepeatEndMode.count;
    }

    DateTime selectedEndDate = existing?.repeatEndDate ??
        selectedStartDate.add(const Duration(days: 30));
    final countController = TextEditingController(
      text: (existing?.repeatCount ?? 10).toString(),
    );

    Future<void> promptDirectTagInput(
      StateSetter setDialogState,
    ) async {
      final newTagController = TextEditingController();
      final addedTag = await showDialog<String>(
        context: context,
        builder: (tagCtx) => AlertDialog(
          title: const Text('새 태그 직접 입력'),
          content: TextField(
            controller: newTagController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '태그 이름 (예: 운동, 출근, 병원)',
              prefixText: '#',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (val) => Navigator.pop(tagCtx, val),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(tagCtx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(tagCtx, newTagController.text),
              child: const Text('추가'),
            ),
          ],
        ),
      );

      final clean = (addedTag ?? '').trim().replaceAll('#', '');
      if (clean.isEmpty) return;

      HapticFeedback.selectionClick();
      setDialogState(() {
        if (!availableTags.contains(clean)) {
          availableTags.add(clean);
        }
        selectedTags.add(clean);
      });
      await _addTagsToKnownPool([clean]);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isRepeating = selectedRepeatType != ScheduleRepeatType.none;

            // 현재 등록된 상황 이름 목록 (+ 기존 일정에 연결되어 있던 삭제된 상황 이름 보존)
            final situationNames = <String>[
              ...widget.situations.map((s) => s.name),
            ];
            if (selectedSituationName != null &&
                !situationNames.contains(selectedSituationName)) {
              situationNames.add(selectedSituationName!);
            }

            return AlertDialog(
              title: Text(
                existing == null
                    ? '${selectedStartDate.month}월 ${selectedStartDate.day}일 일정 추가'
                    : '일정 수정',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        autofocus: existing == null,
                        decoration: const InputDecoration(
                          labelText: '일정 이름',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                HapticFeedback.selectionClick();
                                final pickedDate = await showDatePicker(
                                  context: ctx,
                                  initialDate: selectedStartDate,
                                  firstDate: DateTime(2020, 1, 1),
                                  lastDate: DateTime(2035, 12, 31),
                                );
                                if (pickedDate != null) {
                                  setDialogState(() {
                                    selectedStartDate = pickedDate;
                                    if (selectedEndDate
                                        .isBefore(selectedStartDate)) {
                                      selectedEndDate = selectedStartDate
                                          .add(const Duration(days: 30));
                                    }
                                  });
                                }
                              },
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                '${selectedStartDate.year}.${selectedStartDate.month.toString().padLeft(2, '0')}.${selectedStartDate.day.toString().padLeft(2, '0')}',
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
                                  minute: int.tryParse(parts[1]) ?? 0,
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

                      // --- 1. 태그 선택 (다중 선택 가능 + 직접 입력 칩) ---
                      const Text(
                        '태그 선택',
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
                          ...availableTags.map((tag) {
                            final isSelected = selectedTags.contains(tag);
                            return FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: Text('#$tag'),
                              selected: isSelected,
                              onSelected: (selected) {
                                HapticFeedback.selectionClick();
                                setDialogState(() {
                                  if (selected) {
                                    selectedTags.add(tag);
                                  } else {
                                    selectedTags.remove(tag);
                                  }
                                });
                              },
                            );
                          }),
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.add, size: 16),
                            label: const Text('직접 입력'),
                            onPressed: () =>
                                promptDirectTagInput(setDialogState),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // --- 2. 연결할 외출 상황 체크리스트 (단일 선택) ---
                      const Text(
                        '연결할 체크리스트 상황',
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
                            visualDensity: VisualDensity.compact,
                            label: const Text('선택 안 함'),
                            selected: selectedSituationName == null,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              setDialogState(() {
                                selectedSituationName = null;
                              });
                            },
                          ),
                          ...situationNames.map((sitName) {
                            final sitObj = _findSituationByName(sitName);
                            final isSelected =
                                selectedSituationName == sitName;
                            return ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              avatar: sitObj != null
                                  ? Icon(
                                      sitObj.iconData,
                                      size: 16,
                                      color: isSelected
                                          ? Colors.white
                                          : sitObj.color,
                                    )
                                  : const Icon(
                                      Icons.checklist_rtl,
                                      size: 16,
                                    ),
                              label: Text(sitName),
                              selected: isSelected,
                              selectedColor: sitObj?.color,
                              labelStyle: TextStyle(
                                color: (isSelected && sitObj != null)
                                    ? Colors.white
                                    : null,
                              ),
                              onSelected: (selected) {
                                HapticFeedback.selectionClick();
                                setDialogState(() {
                                  selectedSituationName =
                                      selected ? sitName : null;
                                });
                              },
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 14),

                      DropdownButtonFormField<int?>(
                        initialValue: _prepOptions.any(
                                (e) => e.value == selectedPrepMinutes)
                            ? selectedPrepMinutes
                            : null,
                        decoration: const InputDecoration(
                          labelText: '준비 시간',
                          prefixIcon: Icon(Icons.notifications_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _prepOptions.map((entry) {
                          return DropdownMenuItem<int?>(
                            value: entry.value,
                            child: Text(entry.key),
                          );
                        }).toList(),
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setDialogState(() {
                            selectedPrepMinutes = val;
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // --- 3. 반복 옵션 선택 ---
                      DropdownButtonFormField<ScheduleRepeatType>(
                        initialValue: selectedRepeatType,
                        decoration: const InputDecoration(
                          labelText: '반복 설정',
                          prefixIcon: Icon(Icons.repeat),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: ScheduleRepeatType.values.map((type) {
                          return DropdownMenuItem<ScheduleRepeatType>(
                            value: type,
                            child: Text(type.optionLabel),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          HapticFeedback.selectionClick();
                          setDialogState(() {
                            selectedRepeatType = val;
                            if (val == ScheduleRepeatType.weekly &&
                                selectedWeekdays.isEmpty) {
                              selectedWeekdays.add(selectedStartDate.weekday);
                            }
                          });
                        },
                      ),
                      if (isRepeating) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '반복 간격 (n):',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 72,
                                    child: TextField(
                                      controller: intervalController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    selectedRepeatType.unitLabel,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (selectedRepeatType ==
                                  ScheduleRepeatType.weekly) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  '반복 요일 선택',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: List.generate(7, (index) {
                                    final weekdayNum = index + 1;
                                    final isSelected = selectedWeekdays
                                        .contains(weekdayNum);
                                    return FilterChip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(_weekdayLabels[index]),
                                      selected: isSelected,
                                      onSelected: (selected) {
                                        HapticFeedback.selectionClick();
                                        setDialogState(() {
                                          if (selected) {
                                            selectedWeekdays.add(weekdayNum);
                                            selectedWeekdays.sort();
                                          } else if (selectedWeekdays.length >
                                              1) {
                                            selectedWeekdays.remove(weekdayNum);
                                          }
                                        });
                                      },
                                    );
                                  }),
                                ),
                              ],
                              if (selectedRepeatType ==
                                      ScheduleRepeatType.monthly &&
                                  selectedStartDate.day >= 29) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '※ ${selectedStartDate.day}일이 없는 달에는 해당 월의 마지막 날에 일정이 표시됩니다.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                              const Divider(height: 20),
                              const Text(
                                '반복 종료 조건',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SegmentedButton<_RepeatEndMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: _RepeatEndMode.forever,
                                    label: Text(
                                      '계속 반복',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: _RepeatEndMode.count,
                                    label: Text(
                                      '반복 횟수',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: _RepeatEndMode.untilDate,
                                    label: Text(
                                      '종료 날짜',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                                selected: {endMode},
                                onSelectionChanged: (sel) {
                                  HapticFeedback.selectionClick();
                                  setDialogState(() {
                                    endMode = sel.first;
                                  });
                                },
                              ),
                              if (endMode == _RepeatEndMode.count) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Text(
                                      '총 반복 횟수:',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 80,
                                      child: TextField(
                                        controller: countController,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('회 반복 후 종료'),
                                  ],
                                ),
                              ] else if (endMode ==
                                  _RepeatEndMode.untilDate) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      initialDate: selectedEndDate.isBefore(
                                              selectedStartDate)
                                          ? selectedStartDate
                                          : selectedEndDate,
                                      firstDate: selectedStartDate,
                                      lastDate: DateTime(2035, 12, 31),
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        selectedEndDate = picked;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.event, size: 16),
                                  label: Text(
                                    '종료 날짜: ${selectedEndDate.year}.${selectedEndDate.month.toString().padLeft(2, '0')}.${selectedEndDate.day.toString().padLeft(2, '0')}',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
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
                      _handleDeleteSchedule(existing, initialDay);
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

                    final finalTags = selectedTags.toList();
                    await _addTagsToKnownPool(finalTags);

                    final parsedInterval =
                        (int.tryParse(intervalController.text.trim()) ?? 1)
                            .clamp(1, 999);
                    final parsedCount = endMode == _RepeatEndMode.count
                        ? (int.tryParse(countController.text.trim()) ?? 1)
                            .clamp(1, 9999)
                        : null;
                    final parsedEndDate = endMode == _RepeatEndMode.untilDate
                        ? selectedEndDate
                        : null;
                    final finalWeekdays =
                        selectedRepeatType == ScheduleRepeatType.weekly
                            ? (selectedWeekdays.isEmpty
                                ? [selectedStartDate.weekday]
                                : List<int>.from(selectedWeekdays))
                            : <int>[];

                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    HapticFeedback.mediumImpact();

                    if (existing == null) {
                      final created = Schedule(
                        id: DateTime.now()
                            .microsecondsSinceEpoch
                            .toString(),
                        date: selectedStartDate,
                        title: title,
                        time: selectedTime,
                        tags: finalTags,
                        situationName: selectedSituationName,
                        repeatType: selectedRepeatType,
                        repeatInterval: parsedInterval,
                        repeatWeekdays: finalWeekdays,
                        repeatEndDate: parsedEndDate,
                        repeatCount: parsedCount,
                        prepMinutesBefore: selectedPrepMinutes,
                      );
                      widget.schedules.add(created);
                      _notifySchedules(created);
                      return;
                    }

                    // 기존 반복 일정 수정 시 범위 선택
                    if (!mounted) return;
                    if (existing.isRepeating) {
                      final scope = await showDialog<String>(
                        context: context,
                        builder: (sCtx) => AlertDialog(
                          title: const Text('반복 일정 수정'),
                          content: const Text('변경 사항을 적용할 범위를 선택해 주세요.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(sCtx),
                              child: const Text('취소'),
                            ),
                            OutlinedButton(
                              onPressed: () => Navigator.pop(sCtx, 'only_this'),
                              child: const Text('이 일정만 변경'),
                            ),
                            OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(sCtx, 'this_and_future'),
                              child: const Text('이 일정 및 이후 변경'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(sCtx, 'all'),
                              child: const Text('전체 반복 변경'),
                            ),
                          ],
                        ),
                      );

                      if (scope == null || !mounted) return;

                      if (scope == 'only_this') {
                        final exKey = Schedule.dateKey(initialDay);
                        if (!existing.excludedDates.contains(exKey)) {
                          existing.excludedDates.add(exKey);
                        }
                        final singleCreated = Schedule(
                          id: DateTime.now()
                              .microsecondsSinceEpoch
                              .toString(),
                          date: initialDay,
                          title: title,
                          time: selectedTime,
                          tags: finalTags,
                          situationName: selectedSituationName,
                          repeatType: ScheduleRepeatType.none,
                          prepMinutesBefore: selectedPrepMinutes,
                        );
                        widget.schedules.add(singleCreated);
                        _notifySchedules(singleCreated);
                        return;
                      } else if (scope == 'this_and_future') {
                        final dayBefore = DateTime(
                          initialDay.year,
                          initialDay.month,
                          initialDay.day,
                        ).subtract(const Duration(days: 1));
                        existing.repeatEndDate = dayBefore;
                        existing.repeatCount = null;

                        final futureCreated = Schedule(
                          id: DateTime.now()
                              .microsecondsSinceEpoch
                              .toString(),
                          date: selectedStartDate,
                          title: title,
                          time: selectedTime,
                          tags: finalTags,
                          situationName: selectedSituationName,
                          repeatType: selectedRepeatType,
                          repeatInterval: parsedInterval,
                          repeatWeekdays: finalWeekdays,
                          repeatEndDate: parsedEndDate,
                          repeatCount: parsedCount,
                          prepMinutesBefore: selectedPrepMinutes,
                        );
                        widget.schedules.add(futureCreated);
                        _notifySchedules(futureCreated);
                        return;
                      }
                    }

                    // 단일 일정이거나 '전체 반복 변경' 선택한 경우
                    existing.date = selectedStartDate;
                    existing.title = title;
                    existing.time = selectedTime;
                    existing.tags = finalTags;
                    existing.situationName = selectedSituationName;
                    existing.repeatType = selectedRepeatType;
                    existing.repeatInterval = parsedInterval;
                    existing.repeatWeekdays = finalWeekdays;
                    existing.repeatEndDate = parsedEndDate;
                    existing.repeatCount = parsedCount;
                    existing.prepMinutesBefore = selectedPrepMinutes;
                    _notifySchedules(existing);
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
    showModalBottomSheet(
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

            void refreshBoth({bool checkCompletedNow = false}) {
              setSheetState(() {});
              _notifySituations();
              if (checkCompletedNow && situation.isAllChecked) {
                _registerCompletedChecklistToCalendar(situation);
              }
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
                                  '${schedule.title} · ${situation.name} (${schedule.time})',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  isComplete
                                      ? '외출 준비 완료! 🎉'
                                      : '체크리스트 완료 현황: $checked / $total개 (${(progress * 100).round()}%)',
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
                                refreshBoth(checkCompletedNow: nextState);
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
                                  '등록된 체크리스트 항목이 없습니다. [상황·체크리스트] 탭에서 항목을 추가해 보세요.',
                                ),
                              )
                            : ReorderableListView.builder(
                                scrollController: scrollController,
                                itemCount: situation.items.length,
                                onReorderStart: (_) =>
                                    HapticFeedback.selectionClick(),
                                onReorderItem: (oldIndex, newIndex) {
                                  HapticFeedback.mediumImpact();
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
                                      final wasAll = situation.isAllChecked;
                                      item.isChecked = val ?? false;
                                      if (situation.isAllChecked) {
                                        HapticFeedback.heavyImpact();
                                      } else {
                                        HapticFeedback.lightImpact();
                                      }
                                      refreshBoth(
                                        checkCompletedNow:
                                            !wasAll && situation.isAllChecked,
                                      );
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

  Widget _buildFilterChipBar() {
    final orderedTags = _orderedTags;
    final isTodoSelected =
        !_isAllFilterSelected && _selectedFilterTags.contains(_todoFilterKey);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('전체'),
            selected: _isAllFilterSelected,
            onSelected: (_) => _toggleAllFilter(),
          ),
          const SizedBox(width: 6),
          FilterChip(
            avatar: const Icon(Icons.task_alt, size: 16),
            label: const Text('할 일'),
            selected: isTodoSelected,
            onSelected: (_) => _toggleIndividualFilter(_todoFilterKey),
          ),
          const SizedBox(width: 6),
          ...List.generate(orderedTags.length, (idx) {
            final tag = orderedTags[idx];
            final isSelected =
                !_isAllFilterSelected && _selectedFilterTags.contains(tag);

            final chip = FilterChip(
              label: Text('#$tag'),
              selected: isSelected,
              onSelected: (_) => _toggleIndividualFilter(tag),
            );

            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: DragTarget<int>(
                onWillAcceptWithDetails: (details) => details.data != idx,
                onAcceptWithDetails: (details) {
                  HapticFeedback.mediumImpact();
                  final fromIdx = details.data;
                  final currentOrder = List<String>.from(orderedTags);
                  final moved = currentOrder.removeAt(fromIdx);
                  currentOrder.insert(idx, moved);
                  setState(() {
                    _savedTagOrder = currentOrder;
                  });
                  _saveTagOrderToPrefs(currentOrder);
                },
                builder: (context, candidateData, _) {
                  return LongPressDraggable<int>(
                    data: idx,
                    delay: const Duration(milliseconds: 300),
                    onDragStarted: () => HapticFeedback.selectionClick(),
                    feedback: Material(
                      color: Colors.transparent,
                      child: Opacity(opacity: 0.85, child: chip),
                    ),
                    childWhenDragging: Opacity(opacity: 0.35, child: chip),
                    child: chip,
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daySchedules = _getSchedulesForDay(_selectedDay);
    final dayTodos = _getTodosForDay(_selectedDay);
    final now = DateTime.now();

    return Scaffold(
      body: Column(
        children: [
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
                            hintText: '전체 일정 이름·태그·상황·시간 검색...',
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
                      : _buildFilterChipBar(),
                ),
                if (!_isSearching)
                  IconButton(
                    tooltip: '전체 일정 검색',
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isSearching = true);
                    },
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
                        final tagsStr =
                            sc.tags.map((t) => '#$t').join(' ');
                        final sitStr = sc.hasSituation
                            ? ' [${sc.situationName}]'
                            : '';
                        return ListTile(
                          leading: const Icon(Icons.event_note),
                          title: Text(sc.title),
                          subtitle: Text(
                            '${sc.date.year}-${sc.date.month.toString().padLeft(2, '0')}-${sc.date.day.toString().padLeft(2, '0')} (${sc.time})$sitStr  $tagsStr',
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
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalH = constraints.maxHeight;
                  const handleH = 32.0;
                  final tipH = widget.showTips ? 22.0 : 0.0;
                  final availH =
                      (totalH - handleH - tipH).clamp(220.0, 2000.0);

                  final twoWeeksH = (availH * 0.36).clamp(165.0, 260.0);
                  final monthH = (availH * 0.58).clamp(280.0, 430.0);
                  final expandedH = (availH - 4.0).clamp(monthH, availH);

                  double targetCalH;
                  switch (_stage) {
                    case _CalendarStage.twoWeeks:
                      targetCalH = twoWeeksH;
                      break;
                    case _CalendarStage.month:
                      targetCalH = monthH;
                      break;
                    case _CalendarStage.expanded:
                      targetCalH = expandedH;
                      break;
                  }

                  final currentCalH = (_dragCalendarHeight ?? targetCalH)
                      .clamp(twoWeeksH, expandedH);
                  final isTwoWeeksFormat =
                      currentCalH < (twoWeeksH + monthH) / 2;
                  final rowCount = isTwoWeeksFormat ? 2 : 6;
                  final dynamicRowH = ((currentCalH - 76.0) / rowCount)
                      .clamp(38.0, 96.0);

                  return Column(
                    children: [
                      if (widget.showTips)
                        SizedBox(
                          height: tipH,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.touch_app,
                                  size: 13,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '팁: 날짜 롱프레스로 일정 추가 · 태그 롱프레스로 순서 이동 · 하단 바 드래그로 높이 조절',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      AnimatedContainer(
                        duration: _dragCalendarHeight != null
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        height: currentCalH,
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: TableCalendar<Object>(
                            firstDay: DateTime.utc(2020, 1, 1),
                            lastDay: DateTime.utc(2035, 12, 31),
                            focusedDay: _focusedDay,
                            calendarFormat: isTwoWeeksFormat
                                ? CalendarFormat.twoWeeks
                                : CalendarFormat.month,
                            selectedDayPredicate: (day) =>
                                isSameDay(_selectedDay, day),
                            eventLoader: _getCalendarEventsForDay,
                            rowHeight: dynamicRowH,
                            headerStyle: const HeaderStyle(
                              titleCentered: true,
                              formatButtonVisible: false,
                            ),
                            onDaySelected: (selectedDay, focusedDay) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedDay = selectedDay;
                                _focusedDay = focusedDay;
                                if (_stage == _CalendarStage.expanded) {
                                  _stage = _CalendarStage.month;
                                }
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
                                final maxItems = dynamicRowH >= 68 ? 3 : 2;
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: 28,
                                    left: 1,
                                    right: 1,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: events.take(maxItems).map((ev) {
                                      if (ev is Schedule) {
                                        final sit = _findSituationByName(
                                          ev.situationName,
                                        );
                                        final badgeColor =
                                            sit?.color ?? Colors.blue;
                                        return Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 0.5,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                            vertical: 0.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: badgeColor.withValues(
                                              alpha: 0.2,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            ev.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 8.5,
                                              height: 1.1,
                                              fontWeight: FontWeight.w600,
                                              color: badgeColor,
                                            ),
                                          ),
                                        );
                                      } else if (ev is TodoItem) {
                                        final isOverdue = ev.isOverdueAt(now);
                                        final todoColor = ev.isCompleted
                                            ? Colors.grey
                                            : (isOverdue
                                                ? Colors.redAccent
                                                : Colors.teal);
                                        return Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 0.5,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 2,
                                            vertical: 0.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: todoColor.withValues(
                                              alpha: 0.18,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            '✓ ${ev.title}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 8.5,
                                              height: 1.1,
                                              fontWeight: FontWeight.w600,
                                              color: todoColor,
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
                      // --- 3단계 드래그 스냅 핸들 바 ---
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) {
                          setState(() {
                            _dragCalendarHeight = (currentCalH +
                                    details.delta.dy)
                                .clamp(twoWeeksH, expandedH);
                          });
                        },
                        onVerticalDragEnd: (_) {
                          final h = _dragCalendarHeight ?? currentCalH;
                          final dTwo = (h - twoWeeksH).abs();
                          final dMonth = (h - monthH).abs();
                          final dExp = (h - expandedH).abs();

                          _CalendarStage nextStage = _CalendarStage.month;
                          if (dTwo <= dMonth && dTwo <= dExp) {
                            nextStage = _CalendarStage.twoWeeks;
                          } else if (dExp <= dMonth && dExp <= dTwo) {
                            nextStage = _CalendarStage.expanded;
                          } else {
                            nextStage = _CalendarStage.month;
                          }

                          HapticFeedback.selectionClick();
                          setState(() {
                            _stage = nextStage;
                            _dragCalendarHeight = null;
                          });
                        },
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            if (_stage == _CalendarStage.month) {
                              _stage = _CalendarStage.twoWeeks;
                            } else if (_stage == _CalendarStage.twoWeeks) {
                              _stage = _CalendarStage.expanded;
                            } else {
                              _stage = _CalendarStage.month;
                            }
                          });
                        },
                        child: Container(
                          height: handleH,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            border: Border.symmetric(
                              horizontal: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade500,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _stage == _CalendarStage.twoWeeks
                                    ? '2주 보기'
                                    : _stage == _CalendarStage.month
                                        ? '한달 보기'
                                        : '캘린더 확장됨 (탭하여 복귀)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // --- 하단 일정 및 할 일 목록 ---
                      Expanded(
                        child: _hasNoFilterSelected
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.filter_alt_off_outlined,
                                        size: 36,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        '선택된 태그 필터가 없습니다. 상단 태그를 선택하거나 [전체]를 켜주세요.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : (daySchedules.isEmpty && dayTodos.isEmpty)
                                ? Center(
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${_selectedDay.month}월 ${_selectedDay.day}일에 등록된 일정이 없습니다.',
                                            style: const TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton.icon(
                                            onPressed: () =>
                                                _showScheduleDialog(
                                              targetDate: _selectedDay,
                                            ),
                                            icon: const Icon(Icons.add),
                                            label:
                                                const Text('이 날짜에 일정 추가하기'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      88,
                                    ),
                                    children: [
                                      // 1) 일정 카드 목록
                                      ...daySchedules.map((sc) {
                                        final linkedSituation =
                                            _findSituationByName(
                                          sc.situationName,
                                        );
                                        final color =
                                            linkedSituation?.color ??
                                                Colors.blue;
                                        final isComplete =
                                            linkedSituation?.isAllChecked ??
                                                false;
                                        final repeatText = sc.repeatSummaryText;
                                        final prepText = sc.prepSummaryText;

                                        return Dismissible(
                                          key: ValueKey(
                                            'sched_${sc.id}_${Schedule.dateKey(_selectedDay)}',
                                          ),
                                          direction:
                                              DismissDirection.endToStart,
                                          confirmDismiss: (_) async {
                                            await _handleDeleteSchedule(
                                              sc,
                                              _selectedDay,
                                            );
                                            return false;
                                          },
                                          background: Container(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                            ),
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
                                                Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.white,
                                                ),
                                              ],
                                            ),
                                          ),
                                          child: Card(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              side: BorderSide(
                                                color: isComplete
                                                    ? Colors.green.withValues(
                                                        alpha: 0.7,
                                                      )
                                                    : color.withValues(
                                                        alpha: 0.3,
                                                      ),
                                              ),
                                            ),
                                            child: ListTile(
                                              onTap: () {
                                                if (linkedSituation != null &&
                                                    !sc.isAutoRecord) {
                                                  _showLinkedChecklistSheet(
                                                    sc,
                                                    linkedSituation,
                                                  );
                                                } else {
                                                  _showScheduleDialog(
                                                    targetDate: _selectedDay,
                                                    existing: sc,
                                                  );
                                                }
                                              },
                                              leading: CircleAvatar(
                                                backgroundColor:
                                                    color.withValues(
                                                  alpha: 0.15,
                                                ),
                                                child: Icon(
                                                  sc.isAutoRecord
                                                      ? Icons.verified
                                                      : (linkedSituation
                                                              ?.iconData ??
                                                          Icons.event_available),
                                                  color: color,
                                                ),
                                              ),
                                              title: Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    sc.title,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (sc.hasSituation)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 7,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: color.withValues(
                                                          alpha: 0.15,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            linkedSituation
                                                                    ?.iconData ??
                                                                Icons
                                                                    .checklist_rtl,
                                                            size: 12,
                                                            color: color,
                                                          ),
                                                          const SizedBox(
                                                            width: 3,
                                                          ),
                                                          Text(
                                                            sc.situationName!,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: color,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ...sc.tags.map((tag) {
                                                    return Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 7,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey
                                                            .withValues(
                                                          alpha: 0.15,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Text(
                                                        '#$tag',
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                ],
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 4,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    children: [
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons.access_time,
                                                            size: 14,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(sc.time),
                                                        ],
                                                      ),
                                                      if (prepText != null)
                                                        Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            const Icon(
                                                              Icons
                                                                  .notifications_active_outlined,
                                                              size: 13,
                                                              color: Colors
                                                                  .deepOrange,
                                                            ),
                                                            const SizedBox(
                                                              width: 2,
                                                            ),
                                                            Text(
                                                              prepText,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11.5,
                                                                color: Colors
                                                                    .deepOrange,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      if (repeatText.isNotEmpty)
                                                        Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            const Icon(
                                                              Icons.repeat,
                                                              size: 13,
                                                            ),
                                                            const SizedBox(
                                                              width: 2,
                                                            ),
                                                            Text(
                                                              repeatText,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 11.5,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                    ],
                                                  ),
                                                  if (!sc.isAutoRecord &&
                                                      linkedSituation != null &&
                                                      linkedSituation
                                                          .items.isNotEmpty) ...[
                                                    const SizedBox(height: 6),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              4,
                                                            ),
                                                            child:
                                                                LinearProgressIndicator(
                                                              value:
                                                                  linkedSituation
                                                                      .progress,
                                                              minHeight: 6,
                                                              backgroundColor:
                                                                  Colors.grey
                                                                      .withValues(
                                                                alpha: 0.2,
                                                              ),
                                                              valueColor:
                                                                  AlwaysStoppedAnimation<
                                                                      Color>(
                                                                isComplete
                                                                    ? Colors
                                                                        .green
                                                                    : color,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Text(
                                                          isComplete
                                                              ? '준비 완료 🎉'
                                                              : '체크리스트 ${linkedSituation.checkedCount}/${linkedSituation.items.length}',
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
                                                  if (linkedSituation != null &&
                                                      !sc.isAutoRecord)
                                                    IconButton(
                                                      tooltip: '체크리스트 열기',
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
                                                      targetDate: _selectedDay,
                                                      existing: sc,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                      // 2) 마감 할 일(TodoItem) 카드 목록
                                      ...dayTodos.map((todo) {
                                        final isOverdue = todo.isOverdueAt(now);
                                        final accentColor = todo.isCompleted
                                            ? Colors.grey
                                            : (isOverdue
                                                ? Colors.redAccent
                                                : Colors.teal);

                                        return Card(
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            side: BorderSide(
                                              color: accentColor.withValues(
                                                alpha: 0.35,
                                              ),
                                            ),
                                          ),
                                          child: CheckboxListTile(
                                            value: todo.isCompleted,
                                            activeColor: Colors.teal,
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            title: Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    todo.title,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      decoration: todo
                                                              .isCompleted
                                                          ? TextDecoration
                                                              .lineThrough
                                                          : null,
                                                      color: todo.isCompleted
                                                          ? Colors.grey
                                                          : (isOverdue
                                                              ? Colors.redAccent
                                                              : null),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        accentColor.withValues(
                                                      alpha: 0.15,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      8,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '할 일',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: accentColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            subtitle: (todo.dueTime != null &&
                                                    todo.dueTime!.isNotEmpty)
                                                ? Text(
                                                    '마감 시간: ${todo.dueTime}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isOverdue &&
                                                              !todo.isCompleted
                                                          ? Colors.redAccent
                                                          : null,
                                                    ),
                                                  )
                                                : null,
                                            onChanged: (val) {
                                              HapticFeedback.selectionClick();
                                              todo.toggleCompleted(
                                                val ?? false,
                                                DateTime.now(),
                                              );
                                              _notifyTodos();
                                            },
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showScheduleDialog(targetDate: _selectedDay),
        icon: const Icon(Icons.add),
        label: const Text('일정 추가'),
      ),
    );
  }
}