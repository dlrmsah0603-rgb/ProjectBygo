import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/schedule_model.dart';
import '../models/situation_model.dart';

enum CalendarViewStage {
  twoWeeks, // 0: 2주 보기
  month, // 1: 한달 보기 (기본)
  expanded, // 2: 캘린더 확장 (바 최하단 위치)
}

enum _RepeatEndType {
  none, // 계속 반복
  untilDate, // 종료일 지정
  afterCount, // 반복 횟수 지정
}

enum _RepeatActionScope {
  onlyThis, // 이 일정만
  thisAndFuture, // 이 일정 및 이후 일정
  all, // 전체 반복 일정
}

class CalendarScreen extends StatefulWidget {
  final List<Schedule> schedules;
  final List<Situation> situations;
  final ValueChanged<List<Schedule>> onSchedulesChanged;
  final ValueChanged<List<Situation>> onSituationsChanged;
  final bool showTips;
  final List<String>? tagOrder;
  final ValueChanged<List<String>>? onTagOrderChanged;
  final ValueChanged<Schedule>? onScheduleSavedOrUpdated;

  const CalendarScreen({
    super.key,
    required this.schedules,
    required this.situations,
    required this.onSchedulesChanged,
    required this.onSituationsChanged,
    this.showTips = true,
    this.tagOrder,
    this.onTagOrderChanged,
    this.onScheduleSavedOrUpdated,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const String _tagOrderPrefKey = 'bygo_calendar_tag_order';

  CalendarViewStage _viewStage = CalendarViewStage.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  String? _selectedFilterTag;
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // 태그 순서 관리
  List<String> _customTagOrder = [];

  // 실시간 드래그 추적 상태
  bool _isDraggingBar = false;
  double? _dragCalendarHeight;

  static const double _baseRowHeight = 58.0;
  static const double _calendarChromeHeight = 78.0;
  static const double _handleBarHeight = 52.0;

  static const List<String> _weekdayLabels = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  static const List<int?> _prepPresetMinutes = [
    null, // 설정 안 함
    0, // 정각
    10, // 10분 전
    15, // 15분 전
    30, // 30분 전
    60, // 1시간 전
  ];

  @override
  void initState() {
    super.initState();
    if (widget.tagOrder != null) {
      _customTagOrder = List<String>.from(widget.tagOrder!);
    }
    _loadSavedTagOrder();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tagOrder != null && widget.tagOrder != oldWidget.tagOrder) {
      _customTagOrder = List<String>.from(widget.tagOrder!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedTagOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_tagOrderPrefKey);
      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() {
          _customTagOrder = List<String>.from(saved);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveTagOrder(List<String> newOrder) async {
    setState(() {
      _customTagOrder = List<String>.from(newOrder);
    });
    widget.onTagOrderChanged?.call(_customTagOrder);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_tagOrderPrefKey, _customTagOrder);
    } catch (_) {}
  }

  /// 체크리스트가 모두 완료되었을 때 오늘 날짜에 기록용 일정을 자동 등록
  void _registerCompletedChecklistToCalendar(Situation situation) {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final currentTimeStr = '$hh:$mm';
    final recordTitle = '${situation.name} 준비 완료!';

    Schedule? existingTodayRecord;
    for (final sc in widget.schedules) {
      if (sc.isAutoRecord &&
          sc.tag.trim() == situation.tag.trim() &&
          isSameDay(sc.date, today)) {
        existingTodayRecord = sc;
        break;
      }
    }

    Schedule? addedOrUpdated;
    bool wasAdded = false;

    setState(() {
      if (existingTodayRecord != null) {
        existingTodayRecord.time = currentTimeStr;
        existingTodayRecord.title = recordTitle;
        addedOrUpdated = existingTodayRecord;
        wasAdded = false;
      } else {
        addedOrUpdated = Schedule(
          id: 'record_${now.microsecondsSinceEpoch}',
          date: today,
          title: recordTitle,
          time: currentTimeStr,
          tag: situation.tag,
          isAutoRecord: true,
        );
        widget.schedules.add(addedOrUpdated!);
        wasAdded = true;
      }
    });

    widget.onSchedulesChanged(widget.schedules);
    _saveSchedulesDirectlyToPrefs();

    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "🎉 '${situation.name}' 체크리스트 완료! 캘린더에 기록 일정이 자동 등록되었습니다.",
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
                  _saveSchedulesDirectlyToPrefs();
                },
              )
            : null,
      ),
    );
  }

  Future<void> _saveSchedulesDirectlyToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        widget.schedules.map((s) => s.toJson()).toList(),
      );
      await prefs.setString('schedules', encoded);
    } catch (_) {}
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _formatShortDate(DateTime d) => '${d.year}.${d.month}.${d.day}';

  String _formatMonthDay(DateTime d) => '${d.month}월 ${d.day}일';

  String _stageLabel(CalendarViewStage stage) {
    switch (stage) {
      case CalendarViewStage.twoWeeks:
        return '2주';
      case CalendarViewStage.month:
        return '한달';
      case CalendarViewStage.expanded:
        return '확장';
    }
  }

  int _getWeekRowCount(DateTime monthDate) {
    final firstOfMonth = DateTime(monthDate.year, monthDate.month, 1);
    final lastOfMonth = DateTime(monthDate.year, monthDate.month + 1, 0);
    final firstDayOffset = firstOfMonth.weekday % 7;
    final totalCells = firstDayOffset + lastOfMonth.day;
    return (totalCells / 7.0).ceil().clamp(4, 6);
  }

  Map<CalendarViewStage, double> _getStageHeights(double availableHeight) {
    final weekRows = _getWeekRowCount(_focusedDay);
    final maxCalendarHeight =
        math.max(120.0, availableHeight - _handleBarHeight);

    final rawTwoWeeks = _calendarChromeHeight + (_baseRowHeight * 2);
    final rawMonth = _calendarChromeHeight + (_baseRowHeight * weekRows);

    final hExpanded = maxCalendarHeight;
    final hMonth = rawMonth.clamp(120.0, hExpanded);
    final hTwoWeeks = rawTwoWeeks.clamp(120.0, hMonth);

    return {
      CalendarViewStage.twoWeeks: hTwoWeeks,
      CalendarViewStage.month: hMonth,
      CalendarViewStage.expanded: hExpanded,
    };
  }

  CalendarViewStage _findNearestStage(
    double currentHeight,
    Map<CalendarViewStage, double> stageHeights,
  ) {
    CalendarViewStage nearest = _viewStage;
    double minDistance = double.infinity;

    for (final entry in stageHeights.entries) {
      final distance = (currentHeight - entry.value).abs();
      if (distance < minDistance) {
        minDistance = distance;
        nearest = entry.key;
      }
    }
    return nearest;
  }

  void _setViewStage(CalendarViewStage newStage) {
    HapticFeedback.selectionClick();
    setState(() {
      _isDraggingBar = false;
      _dragCalendarHeight = null;
      _viewStage = newStage;
    });
  }

  void _stepViewStage(int delta) {
    final nextIndex = (_viewStage.index + delta)
        .clamp(0, CalendarViewStage.values.length - 1);
    if (nextIndex == _viewStage.index) return;
    _setViewStage(CalendarViewStage.values[nextIndex]);
  }

  void _onBarDragStart(
    DragStartDetails details,
    Map<CalendarViewStage, double> stageHeights,
  ) {
    setState(() {
      _isDraggingBar = true;
      _dragCalendarHeight = stageHeights[_viewStage]!;
    });
  }

  void _onBarDragUpdate(
    DragUpdateDetails details,
    Map<CalendarViewStage, double> stageHeights,
  ) {
    final minH = stageHeights[CalendarViewStage.twoWeeks]!;
    final maxH = stageHeights[CalendarViewStage.expanded]!;
    final prevH = _dragCalendarHeight ?? stageHeights[_viewStage]!;
    final nextH = (prevH + details.delta.dy).clamp(minH, maxH);

    final prevNearest = _findNearestStage(prevH, stageHeights);
    final nextNearest = _findNearestStage(nextH, stageHeights);
    if (prevNearest != nextNearest) {
      HapticFeedback.selectionClick();
    }

    setState(() {
      _isDraggingBar = true;
      _dragCalendarHeight = nextH;
    });
  }

  void _onBarDragEnd(
    DragEndDetails details,
    Map<CalendarViewStage, double> stageHeights,
  ) {
    final currentH = _dragCalendarHeight ?? stageHeights[_viewStage]!;
    final nearestStage = _findNearestStage(currentH, stageHeights);

    HapticFeedback.lightImpact();
    setState(() {
      _viewStage = nearestStage;
      _isDraggingBar = false;
      _dragCalendarHeight = null;
    });
  }

  void _onBarDragCancel(Map<CalendarViewStage, double> stageHeights) {
    final currentH = _dragCalendarHeight ?? stageHeights[_viewStage]!;
    final nearestStage = _findNearestStage(currentH, stageHeights);

    setState(() {
      _viewStage = nearestStage;
      _isDraggingBar = false;
      _dragCalendarHeight = null;
    });
  }

  List<String> get _allAvailableTags {
    final tagSet = <String>{};
    for (final s in widget.situations) {
      if (s.tag.trim().isNotEmpty) tagSet.add(s.tag.trim());
    }
    for (final sc in widget.schedules) {
      if (sc.tag.trim().isNotEmpty) tagSet.add(sc.tag.trim());
    }

    final ordered = <String>[];
    for (final t in _customTagOrder) {
      if (tagSet.contains(t)) {
        ordered.add(t);
        tagSet.remove(t);
      }
    }
    ordered.addAll(tagSet);
    return ordered;
  }

  Situation? _findSituationByTag(String tag) {
    if (tag.trim().isEmpty) return null;
    for (final s in widget.situations) {
      if (s.tag.trim() == tag.trim()) return s;
    }
    return null;
  }

  List<Schedule> _getEventsForDay(DateTime day) {
    final events = widget.schedules.where((sc) {
      final matchesDay = sc.occursOn(day);
      final matchesTag = _selectedFilterTag == null ||
          sc.tag.trim() == _selectedFilterTag!.trim();
      final matchesSearch = _searchQuery.trim().isEmpty ||
          sc.title.toLowerCase().contains(_searchQuery.trim().toLowerCase()) ||
          sc.tag.toLowerCase().contains(_searchQuery.trim().toLowerCase());
      return matchesDay && matchesTag && matchesSearch;
    }).toList();

    events.sort((a, b) => a.time.compareTo(b.time));
    return events;
  }

  String _buildRepeatSummaryText(Schedule sc) {
    final daysText =
        sc.repeatWeekdays.map((w) => _weekdayLabels[w - 1]).join('·');
    if (sc.repeatEndDate != null) {
      return '$daysText (${_formatShortDate(sc.date)}~${_formatShortDate(sc.repeatEndDate!)})';
    }
    if (sc.repeatCount != null && sc.repeatCount! > 0) {
      return '$daysText (총 ${sc.repeatCount}회)';
    }
    return daysText;
  }

  List<Schedule> _cloneSchedulesSnapshot() {
    return widget.schedules.map((s) => s.copyWith()).toList();
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

  Future<_RepeatActionScope?> _showRepeatScopeDialog({
    required String title,
    required DateTime targetDate,
    required String onlyThisLabel,
    required String thisAndFutureLabel,
    required String allLabel,
    bool isDestructive = false,
  }) {
    final dateStr = _formatMonthDay(targetDate);
    final accentColor = isDestructive
        ? Colors.redAccent
        : Theme.of(context).colorScheme.primary;

    return showDialog<_RepeatActionScope>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '선택한 날짜($dateStr) 기준으로 적용할 범위를 선택해 주세요.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: Icon(Icons.today, color: accentColor),
                title: Text(
                  onlyThisLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '$dateStr 일정에만 적용합니다.',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, _RepeatActionScope.onlyThis),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: Icon(Icons.upcoming, color: accentColor),
                title: Text(
                  thisAndFutureLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '$dateStr부터 이후 반복 일정에 모두 적용합니다.',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () =>
                    Navigator.pop(ctx, _RepeatActionScope.thisAndFuture),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: Icon(Icons.repeat, color: accentColor),
                title: Text(
                  allLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  '과거와 미래를 포함한 전체 반복 일정에 적용합니다.',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, _RepeatActionScope.all),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _requestDeleteSchedule(
    Schedule schedule,
    DateTime occurrenceDate,
  ) async {
    final targetDay = _dateOnly(occurrenceDate);
    final snapshot = _cloneSchedulesSnapshot();

    if (!schedule.isRepeating) {
      if (!widget.schedules.contains(schedule)) return;
      setState(() {
        widget.schedules.remove(schedule);
      });
      HapticFeedback.mediumImpact();
      widget.onSchedulesChanged(widget.schedules);
      _showUndoSnackBar("'${schedule.title}' 일정이 삭제되었습니다.", snapshot);
      return;
    }

    final scope = await _showRepeatScopeDialog(
      title: '반복 일정 삭제',
      targetDate: targetDay,
      onlyThisLabel: '이 일정만 삭제',
      thisAndFutureLabel: '이 일정 및 이후 일정 삭제',
      allLabel: '전체 반복 일정 삭제',
      isDestructive: true,
    );

    if (scope == null || !mounted) return;

    HapticFeedback.mediumImpact();
    String snackMsg = '';

    setState(() {
      switch (scope) {
        case _RepeatActionScope.onlyThis:
          final key = Schedule.dateKey(targetDay);
          if (!schedule.excludedDates.contains(key)) {
            schedule.excludedDates.add(key);
          }
          snackMsg =
              "'${schedule.title}' (${_formatMonthDay(targetDay)}) 일정만 삭제되었습니다.";
          break;

        case _RepeatActionScope.thisAndFuture:
          final startDay = _dateOnly(schedule.date);
          if (!targetDay.isAfter(startDay)) {
            widget.schedules.remove(schedule);
          } else {
            schedule.repeatEndDate =
                targetDay.subtract(const Duration(days: 1));
            schedule.repeatCount = null;
          }
          snackMsg =
              "'${schedule.title}' (${_formatMonthDay(targetDay)} 이후) 일정이 삭제되었습니다.";
          break;

        case _RepeatActionScope.all:
          widget.schedules.remove(schedule);
          snackMsg = "'${schedule.title}' 전체 반복 일정이 삭제되었습니다.";
          break;
      }
    });

    widget.onSchedulesChanged(widget.schedules);
    _showUndoSnackBar(snackMsg, snapshot);
  }

  String _prepPresetLabel(int? minutes) {
    if (minutes == null) return '설정 안 함';
    if (minutes == 0) return '정각';
    if (minutes == 60) return '1시간 전';
    return '$minutes분 전';
  }

  String _calculatePreviewPrepTime(String scheduleTimeText, int prepMinutes) {
    final parts = scheduleTimeText.split(':');
    final h = int.tryParse(parts.firstOrNull ?? '9') ?? 9;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    int total = (h * 60 + m) - prepMinutes;
    while (total < 0) {
      total += 24 * 60;
    }
    total = total % (24 * 60);
    final hh = (total ~/ 60).toString().padLeft(2, '0');
    final mm = (total % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _showScheduleDialog({
    Schedule? existing,
    DateTime? defaultDate,
    DateTime? occurrenceDate,
  }) {
    HapticFeedback.selectionClick();
    final activeOccurrenceDay = _dateOnly(
      occurrenceDate ?? defaultDate ?? _selectedDay ?? DateTime.now(),
    );
    DateTime repeatStartDate =
        _dateOnly(existing?.date ?? activeOccurrenceDay);

    final titleController = TextEditingController(text: existing?.title ?? '');
    final timeController = TextEditingController(
      text: existing?.time ?? '09:00',
    );
    final tagController = TextEditingController(text: existing?.tag ?? '');
    final selectedWeekdays = List<int>.from(existing?.repeatWeekdays ?? []);
    // 새 일정 추가 시 기본 준비시간 30분 전으로 제공 (원치 않으면 '설정 안 함' 선택 가능)
    int? selectedPrepMinutes =
        existing != null ? existing.prepMinutesBefore : 30;

    _RepeatEndType repeatEndType = _RepeatEndType.none;
    if (existing?.repeatEndDate != null) {
      repeatEndType = _RepeatEndType.untilDate;
    } else if (existing?.repeatCount != null && existing!.repeatCount! > 0) {
      repeatEndType = _RepeatEndType.afterCount;
    }

    DateTime repeatEndDate = _dateOnly(
      existing?.repeatEndDate ??
          repeatStartDate.add(const Duration(days: 30)),
    );
    final countController = TextEditingController(
      text: (existing?.repeatCount ?? 10).toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isCustomPrep = selectedPrepMinutes != null &&
                !_prepPresetMinutes.contains(selectedPrepMinutes);

            return AlertDialog(
              title: Text(existing == null ? '일정 추가' : '일정 수정'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.situations.isNotEmpty) ...[
                      const Text(
                        '외출 상황으로 빠르게 채우기',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: widget.situations.map((sit) {
                          return ActionChip(
                            avatar: Icon(
                              sit.iconData,
                              size: 16,
                              color: sit.color,
                            ),
                            label: Text(sit.name),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setDialogState(() {
                                if (titleController.text.trim().isEmpty) {
                                  titleController.text = sit.name;
                                }
                                tagController.text = sit.tag;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: '일정 이름',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: timeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: '일정 시간',
                              prefixIcon: Icon(Icons.access_time),
                              border: OutlineInputBorder(),
                            ),
                            onTap: () async {
                              final parts = timeController.text.split(':');
                              final initHour =
                                  int.tryParse(parts.firstOrNull ?? '9') ?? 9;
                              final initMin = int.tryParse(
                                    parts.length > 1 ? parts[1] : '0',
                                  ) ??
                                  0;
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay(
                                  hour: initHour,
                                  minute: initMin,
                                ),
                              );
                              if (picked != null) {
                                final hh =
                                    picked.hour.toString().padLeft(2, '0');
                                final mm =
                                    picked.minute.toString().padLeft(2, '0');
                                setDialogState(() {
                                  timeController.text = '$hh:$mm';
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: tagController,
                            decoration: const InputDecoration(
                              labelText: '태그',
                              prefixText: '#',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '준비시간 및 푸시 알림 (준비시간 ~ 일정시간 자동 포커싱·위젯 연동)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ..._prepPresetMinutes.map((presetMin) {
                          final isSelected = selectedPrepMinutes == presetMin;
                          return ChoiceChip(
                            label: Text(
                              _prepPresetLabel(presetMin),
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: isSelected,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              setDialogState(() {
                                selectedPrepMinutes = presetMin;
                              });
                            },
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.alarm, size: 16),
                          backgroundColor: isCustomPrep
                              ? Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                              : null,
                          label: Text(
                            isCustomPrep
                                ? '직접 지정 (${_calculatePreviewPrepTime(timeController.text, selectedPrepMinutes!)})'
                                : '직접 시간 지정',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            final sParts = timeController.text.split(':');
                            final sHour =
                                int.tryParse(sParts.firstOrNull ?? '9') ?? 9;
                            final sMin = int.tryParse(
                                  sParts.length > 1 ? sParts[1] : '0',
                                ) ??
                                0;

                            final picked = await showTimePicker(
                              context: ctx,
                              helpText: '체크리스트를 확인할 준비시간 선택',
                              initialTime: TimeOfDay(
                                hour: (sHour - 1).clamp(0, 23),
                                minute: sMin,
                              ),
                            );
                            if (picked != null) {
                              final scheduleTotal = sHour * 60 + sMin;
                              final pickedTotal =
                                  picked.hour * 60 + picked.minute;
                              int diff = scheduleTotal - pickedTotal;
                              if (diff < 0) {
                                diff += 24 * 60;
                              }
                              setDialogState(() {
                                selectedPrepMinutes = diff;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (selectedPrepMinutes != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.notifications_active_outlined,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${_calculatePreviewPrepTime(timeController.text, selectedPrepMinutes!)} ~ ${timeController.text} 동안 미완료 체크리스트 자동 포커싱 및 위젯이 활성화되며, ${timeController.text}에 자동 초기화됩니다.',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      '요일 반복 설정 (선택 시 매주 반복)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: List.generate(7, (idx) {
                        final weekday = idx + 1;
                        final isSelected = selectedWeekdays.contains(weekday);
                        return FilterChip(
                          label: Text(_weekdayLabels[idx]),
                          selected: isSelected,
                          onSelected: (val) {
                            HapticFeedback.selectionClick();
                            setDialogState(() {
                              if (val) {
                                selectedWeekdays.add(weekday);
                                selectedWeekdays.sort();
                              } else {
                                selectedWeekdays.remove(weekday);
                              }
                            });
                          },
                        );
                      }),
                    ),
                    if (selectedWeekdays.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '반복 기간 설정',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.play_arrow_rounded, size: 18),
                                const SizedBox(width: 4),
                                const Text(
                                  '시작일:',
                                  style: TextStyle(fontSize: 13),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                  ),
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      initialDate: repeatStartDate,
                                      firstDate: DateTime(2020, 1, 1),
                                      lastDate: DateTime(2035, 12, 31),
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        repeatStartDate = _dateOnly(picked);
                                        if (repeatEndDate
                                            .isBefore(repeatStartDate)) {
                                          repeatEndDate = repeatStartDate.add(
                                            const Duration(days: 7),
                                          );
                                        }
                                      });
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.calendar_today,
                                    size: 14,
                                  ),
                                  label: Text(
                                    _formatShortDate(repeatStartDate),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ChoiceChip(
                                  label: const Text(
                                    '계속 반복',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  selected:
                                      repeatEndType == _RepeatEndType.none,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    setDialogState(() {
                                      repeatEndType = _RepeatEndType.none;
                                    });
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text(
                                    '종료일 지정',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  selected:
                                      repeatEndType == _RepeatEndType.untilDate,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    setDialogState(() {
                                      repeatEndType = _RepeatEndType.untilDate;
                                      if (repeatEndDate
                                          .isBefore(repeatStartDate)) {
                                        repeatEndDate = repeatStartDate.add(
                                          const Duration(days: 30),
                                        );
                                      }
                                    });
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text(
                                    '횟수 지정',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  selected: repeatEndType ==
                                      _RepeatEndType.afterCount,
                                  onSelected: (_) {
                                    HapticFeedback.selectionClick();
                                    setDialogState(() {
                                      repeatEndType =
                                          _RepeatEndType.afterCount;
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (repeatEndType == _RepeatEndType.untilDate) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.event_available, size: 18),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '종료일:',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                    ),
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: repeatEndDate
                                                .isBefore(repeatStartDate)
                                            ? repeatStartDate
                                            : repeatEndDate,
                                        firstDate: repeatStartDate,
                                        lastDate: DateTime(2035, 12, 31),
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          repeatEndDate = _dateOnly(picked);
                                        });
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.event,
                                      size: 14,
                                    ),
                                    label: Text(
                                      _formatShortDate(repeatEndDate),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (repeatEndType ==
                                _RepeatEndType.afterCount) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.tag, size: 18),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '총 반복 횟수:',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      final cur = int.tryParse(
                                            countController.text,
                                          ) ??
                                          10;
                                      if (cur > 1) {
                                        HapticFeedback.selectionClick();
                                        setDialogState(() {
                                          countController.text =
                                              (cur - 1).toString();
                                        });
                                      }
                                    },
                                  ),
                                  SizedBox(
                                    width: 56,
                                    child: TextField(
                                      controller: countController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 8,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      final cur = int.tryParse(
                                            countController.text,
                                          ) ??
                                          10;
                                      HapticFeedback.selectionClick();
                                      setDialogState(() {
                                        countController.text =
                                            (cur + 1).toString();
                                      });
                                    },
                                  ),
                                  const Text(
                                    '회',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _requestDeleteSchedule(existing, activeOccurrenceDay);
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

                    final cleanTag =
                        tagController.text.trim().replaceAll('#', '');
                    final cleanTime = timeController.text.trim();

                    final DateTime? newEndDate = (selectedWeekdays.isNotEmpty &&
                            repeatEndType == _RepeatEndType.untilDate)
                        ? repeatEndDate
                        : null;
                    final int? newRepeatCount = (selectedWeekdays.isNotEmpty &&
                            repeatEndType == _RepeatEndType.afterCount)
                        ? (int.tryParse(countController.text.trim()) ?? 1)
                            .clamp(1, 9999)
                        : null;

                    if (existing == null) {
                      HapticFeedback.mediumImpact();
                      final created = Schedule(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        date: selectedWeekdays.isNotEmpty
                            ? repeatStartDate
                            : activeOccurrenceDay,
                        title: title,
                        time: cleanTime,
                        tag: cleanTag,
                        repeatWeekdays: selectedWeekdays,
                        repeatEndDate: newEndDate,
                        repeatCount: newRepeatCount,
                        prepMinutesBefore: selectedPrepMinutes,
                      );
                      setState(() {
                        widget.schedules.add(created);
                      });
                      widget.onScheduleSavedOrUpdated?.call(created);
                      widget.onSchedulesChanged(widget.schedules);
                      Navigator.pop(ctx);
                      return;
                    }

                    if (!existing.isRepeating) {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        existing.date = selectedWeekdays.isNotEmpty
                            ? repeatStartDate
                            : existing.date;
                        existing.title = title;
                        existing.time = cleanTime;
                        existing.tag = cleanTag;
                        existing.repeatWeekdays = selectedWeekdays;
                        existing.repeatEndDate = newEndDate;
                        existing.repeatCount = newRepeatCount;
                        existing.prepMinutesBefore = selectedPrepMinutes;
                      });
                      widget.onScheduleSavedOrUpdated?.call(existing);
                      widget.onSchedulesChanged(widget.schedules);
                      Navigator.pop(ctx);
                      return;
                    }

                    final scope = await _showRepeatScopeDialog(
                      title: '반복 일정 변경',
                      targetDate: activeOccurrenceDay,
                      onlyThisLabel: '이 일정만 변경',
                      thisAndFutureLabel: '이 일정 및 이후 일정 변경',
                      allLabel: '전체 반복 일정 변경',
                    );

                    if (scope == null || !mounted) return;

                    HapticFeedback.mediumImpact();
                    Schedule? targetNotifiedSchedule = existing;
                    setState(() {
                      switch (scope) {
                        case _RepeatActionScope.onlyThis:
                          final key = Schedule.dateKey(activeOccurrenceDay);
                          if (!existing.excludedDates.contains(key)) {
                            existing.excludedDates.add(key);
                          }
                          final singleCreated = Schedule(
                            id: DateTime.now()
                                .microsecondsSinceEpoch
                                .toString(),
                            date: activeOccurrenceDay,
                            title: title,
                            time: cleanTime,
                            tag: cleanTag,
                            repeatWeekdays: [],
                            prepMinutesBefore: selectedPrepMinutes,
                          );
                          widget.schedules.add(singleCreated);
                          targetNotifiedSchedule = singleCreated;
                          break;

                        case _RepeatActionScope.thisAndFuture:
                          final origStart = _dateOnly(existing.date);
                          final splitStart =
                              repeatStartDate != origStart
                                  ? repeatStartDate
                                  : activeOccurrenceDay;

                          if (!activeOccurrenceDay.isAfter(origStart)) {
                            existing.date = splitStart;
                            existing.title = title;
                            existing.time = cleanTime;
                            existing.tag = cleanTag;
                            existing.repeatWeekdays = selectedWeekdays;
                            existing.repeatEndDate = newEndDate;
                            existing.repeatCount = newRepeatCount;
                            existing.prepMinutesBefore = selectedPrepMinutes;
                          } else {
                            existing.repeatEndDate = activeOccurrenceDay
                                .subtract(const Duration(days: 1));
                            existing.repeatCount = null;

                            final splitCreated = Schedule(
                              id: DateTime.now()
                                  .microsecondsSinceEpoch
                                  .toString(),
                              date: splitStart,
                              title: title,
                              time: cleanTime,
                              tag: cleanTag,
                              repeatWeekdays: selectedWeekdays,
                              repeatEndDate: newEndDate,
                              repeatCount: newRepeatCount,
                              prepMinutesBefore: selectedPrepMinutes,
                            );
                            widget.schedules.add(splitCreated);
                            targetNotifiedSchedule = splitCreated;
                          }
                          break;

                        case _RepeatActionScope.all:
                          existing.date = selectedWeekdays.isNotEmpty
                              ? repeatStartDate
                              : existing.date;
                          existing.title = title;
                          existing.time = cleanTime;
                          existing.tag = cleanTag;
                          existing.repeatWeekdays = selectedWeekdays;
                          existing.repeatEndDate = newEndDate;
                          existing.repeatCount = newRepeatCount;
                          existing.prepMinutesBefore = selectedPrepMinutes;
                          break;
                      }
                    });

                    if (targetNotifiedSchedule != null) {
                      widget.onScheduleSavedOrUpdated
                          ?.call(targetNotifiedSchedule!);
                    }
                    widget.onSchedulesChanged(widget.schedules);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
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

  void _showChecklistBottomSheet(Schedule schedule, Situation situation) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final total = situation.items.length;
            final checked = situation.checkedCount;
            final progress = situation.progress;
            final isComplete = situation.isAllChecked;
            final activeColor = isComplete ? Colors.green : situation.color;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: activeColor.withValues(alpha: 0.15),
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
                                '${schedule.title} (${situation.name})',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                isComplete
                                    ? '외출 준비 완료! 🎉'
                                    : '체크리스트 진행 현황: $checked / $total개 (${(progress * 100).round()}%)',
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
                          TextButton.icon(
                            onPressed: () {
                              final wasAllChecked = situation.isAllChecked;
                              final target = !isComplete;
                              if (target) {
                                HapticFeedback.heavyImpact();
                              } else {
                                HapticFeedback.mediumImpact();
                              }
                              setSheetState(() {
                                for (final item in situation.items) {
                                  item.isChecked = target;
                                }
                              });
                              setState(() {});
                              widget.onSituationsChanged(widget.situations);
                              if (!wasAllChecked && situation.isAllChecked) {
                                _registerCompletedChecklistToCalendar(
                                  situation,
                                );
                              }
                            },
                            icon: Icon(
                              isComplete ? Icons.restart_alt : Icons.done_all,
                              size: 18,
                            ),
                            label: Text(isComplete ? '초기화' : '전체체크'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey.withValues(alpha: 0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(activeColor),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (situation.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            '등록된 체크리스트가 없습니다. [상황·체크리스트] 탭에서 항목을 추가해 보세요.',
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: situation.items.length,
                          itemBuilder: (context, idx) {
                            final item = situation.items[idx];
                            return CheckboxListTile(
                              value: item.isChecked,
                              activeColor: activeColor,
                              title: Text(
                                item.name,
                                style: TextStyle(
                                  decoration: item.isChecked
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: item.isChecked ? Colors.grey : null,
                                ),
                              ),
                              onChanged: (val) {
                                final wasAllChecked = situation.isAllChecked;
                                setSheetState(() {
                                  item.isChecked = val ?? false;
                                });
                                if (situation.isAllChecked) {
                                  HapticFeedback.heavyImpact();
                                } else {
                                  HapticFeedback.lightImpact();
                                }
                                setState(() {});
                                widget.onSituationsChanged(widget.situations);
                                if (!wasAllChecked && situation.isAllChecked) {
                                  _registerCompletedChecklistToCalendar(
                                    situation,
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTagChipContent(
    String tag,
    Situation? sit,
    bool isSelected, {
    bool isFeedback = false,
  }) {
    return Material(
      color: Colors.transparent,
      elevation: isFeedback ? 4 : 0,
      borderRadius: BorderRadius.circular(8),
      child: FilterChip(
        avatar: sit != null
            ? Icon(
                sit.iconData,
                size: 16,
                color: sit.color,
              )
            : null,
        label: Text('#$tag'),
        selected: isSelected,
        onSelected: (selected) {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedFilterTag = selected ? tag : null;
          });
        },
      ),
    );
  }

  Widget _buildReorderableTagBar(List<String> tags) {
    return Row(
      children: [
        FilterChip(
          label: const Text('전체'),
          selected: _selectedFilterTag == null,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            setState(() => _selectedFilterTag = null);
          },
        ),
        const SizedBox(width: 8),
        ...tags.map((tag) {
          final sit = _findSituationByTag(tag);
          final isSelected = _selectedFilterTag == tag;

          return Padding(
            key: ValueKey('tag_chip_$tag'),
            padding: const EdgeInsets.only(right: 8),
            child: DragTarget<String>(
              onWillAcceptWithDetails: (details) {
                final draggedTag = details.data;
                if (draggedTag == tag) return false;

                final currentList = List<String>.from(tags);
                final oldIdx = currentList.indexOf(draggedTag);
                final newIdx = currentList.indexOf(tag);
                if (oldIdx != -1 && newIdx != -1 && oldIdx != newIdx) {
                  HapticFeedback.selectionClick();
                  currentList.removeAt(oldIdx);
                  currentList.insert(newIdx, draggedTag);
                  _saveTagOrder(currentList);
                }
                return true;
              },
              builder: (context, candidateData, rejectedData) {
                return LongPressDraggable<String>(
                  data: tag,
                  delay: const Duration(milliseconds: 300),
                  onDragStarted: () => HapticFeedback.mediumImpact(),
                  feedback: Transform.scale(
                    scale: 1.06,
                    child: _buildTagChipContent(
                      tag,
                      sit,
                      isSelected,
                      isFeedback: true,
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.35,
                    child: _buildTagChipContent(tag, sit, isSelected),
                  ),
                  child: _buildTagChipContent(tag, sit, isSelected),
                );
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTableCalendar({
    required CalendarFormat format,
    required double rowHeight,
    required int maxMarkers,
    required Map<CalendarViewStage, double> stageHeights,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onPrimaryColor = Theme.of(context).colorScheme.onPrimary;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (d) => _onBarDragStart(d, stageHeights),
      onVerticalDragUpdate: (d) => _onBarDragUpdate(d, stageHeights),
      onVerticalDragEnd: (d) => _onBarDragEnd(d, stageHeights),
      onVerticalDragCancel: () => _onBarDragCancel(stageHeights),
      child: TableCalendar<Schedule>(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2035, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: format,
        availableGestures: AvailableGestures.horizontalSwipe,
        rowHeight: rowHeight,
        daysOfWeekHeight: 22,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        eventLoader: _getEventsForDay,
        onDaySelected: (selectedDay, focusedDay) {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        onDayLongPressed: (selectedDay, focusedDay) {
          HapticFeedback.mediumImpact();
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
          _showScheduleDialog(
            defaultDate: selectedDay,
            occurrenceDate: selectedDay,
          );
        },
        onPageChanged: (focusedDay) {
          setState(() {
            _focusedDay = focusedDay;
          });
        },
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          headerPadding: EdgeInsets.symmetric(vertical: 4),
          headerMargin: EdgeInsets.zero,
        ),
        calendarStyle: CalendarStyle(
          cellMargin: const EdgeInsets.all(2),
          todayDecoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          todayTextStyle: TextStyle(
            color: onPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
          selectedDecoration: BoxDecoration(
            color: primaryColor,
            shape: BoxShape.circle,
          ),
          selectedTextStyle: TextStyle(
            color: onPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, date, events) {
            if (events.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(
                top: 30,
                left: 1,
                right: 1,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: events.take(maxMarkers).map((sc) {
                  final sit = _findSituationByTag(sc.tag);
                  final badgeColor = sc.isAutoRecord
                      ? Colors.green
                      : (sit?.color ?? primaryColor);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 0.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 0.5,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      sc.title,
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
                }).toList(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSchedulePanelHeader({
    required DateTime activeDay,
    required int eventCount,
    required CalendarViewStage activeStageHighlight,
    required Map<CalendarViewStage, double> stageHeights,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final onPrimaryColor = Theme.of(context).colorScheme.onPrimary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (d) => _onBarDragStart(d, stageHeights),
      onVerticalDragUpdate: (d) => _onBarDragUpdate(d, stageHeights),
      onVerticalDragEnd: (d) => _onBarDragEnd(d, stageHeights),
      onVerticalDragCancel: () => _onBarDragCancel(stageHeights),
      onTap: () {
        if (_viewStage == CalendarViewStage.expanded) {
          _setViewStage(CalendarViewStage.month);
        } else {
          _setViewStage(CalendarViewStage.expanded);
        }
      },
      child: Container(
        height: _handleBarHeight,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: _isDraggingBar ? 0.65 : 0.4),
          border: Border(
            top: BorderSide(
              color: Colors.grey.withValues(alpha: 0.25),
              width: 1,
            ),
            bottom: BorderSide(
              color: Colors.grey.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: _isDraggingBar
                    ? primaryColor
                    : Colors.grey.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.event_note,
                  size: 16,
                  color: primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  '${activeDay.month}월 ${activeDay.day}일 일정 ($eventCount)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: CalendarViewStage.values.map((stage) {
                      final isSelected = activeStageHighlight == stage;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _setViewStage(stage),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isSelected ? primaryColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _stageLabel(stage),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? onPrimaryColor
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleList(
    DateTime activeDay,
    List<Schedule> selectedEvents,
    Map<CalendarViewStage, double> stageHeights,
  ) {
    if (selectedEvents.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (d) => _onBarDragStart(d, stageHeights),
        onVerticalDragUpdate: (d) => _onBarDragUpdate(d, stageHeights),
        onVerticalDragEnd: (d) => _onBarDragEnd(d, stageHeights),
        onVerticalDragCancel: () => _onBarDragCancel(stageHeights),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight < 40) return const SizedBox.shrink();
            return Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Text(
                  '선택한 날짜에 일정이 없습니다.\n(바를 잡고 움직여 2주 / 한달 / 확장 조절)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    final now = DateTime.now();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!_isDraggingBar && notification is OverscrollNotification) {
          if (notification.overscroll < -16) {
            _stepViewStage(1);
            return true;
          }
          if (notification.overscroll > 16) {
            _stepViewStage(-1);
            return true;
          }
        }
        return false;
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
        itemCount: selectedEvents.length,
        itemBuilder: (context, index) {
          final sc = selectedEvents[index];
          final linkedSit = _findSituationByTag(sc.tag);
          final isComplete =
              sc.isAutoRecord || (linkedSit?.isAllChecked ?? false);
          final isInPrepNow =
              isSameDay(activeDay, now) && sc.isInPrepWindowAt(now);
          final cardColor = isComplete
              ? Colors.green
              : (linkedSit?.color ?? Theme.of(context).colorScheme.primary);

          return Dismissible(
            key: ValueKey('${sc.id}_${Schedule.dateKey(activeDay)}'),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.centerRight,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Colors.white,
              ),
            ),
            confirmDismiss: (_) async {
              await _requestDeleteSchedule(sc, activeDay);
              return false;
            },
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isInPrepNow
                      ? Colors.orange
                      : cardColor.withValues(alpha: 0.35),
                  width: isInPrepNow ? 2 : 1,
                ),
              ),
              child: ListTile(
                onTap: () {
                  if (linkedSit != null) {
                    _showChecklistBottomSheet(sc, linkedSit);
                  } else {
                    _showScheduleDialog(
                      existing: sc,
                      occurrenceDate: activeDay,
                    );
                  }
                },
                leading: CircleAvatar(
                  backgroundColor: cardColor.withValues(alpha: 0.15),
                  child: Icon(
                    isComplete
                        ? Icons.verified
                        : (linkedSit?.iconData ?? Icons.event),
                    color: cardColor,
                  ),
                ),
                title: Row(
                  children: [
                    if (sc.isAutoRecord)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '기록',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    if (isInPrepNow)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '⏰ 준비시간',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        sc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (sc.tag.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '#${sc.tag}',
                          style: TextStyle(
                            fontSize: 11,
                            color: cardColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time, size: 14),
                            const SizedBox(width: 4),
                            Text(sc.time),
                          ],
                        ),
                        if (sc.prepSummaryText != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.notifications_active_outlined,
                                size: 14,
                                color: cardColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                sc.prepSummaryText!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cardColor,
                                ),
                              ),
                            ],
                          ),
                        if (sc.isRepeating)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.repeat, size: 14),
                              const SizedBox(width: 2),
                              Text(
                                _buildRepeatSummaryText(sc),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (linkedSit != null && linkedSit.items.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: linkedSit.progress,
                                minHeight: 5,
                                backgroundColor:
                                    Colors.grey.withValues(alpha: 0.2),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(cardColor),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '체크리스트 ${linkedSit.checkedCount}/${linkedSit.items.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: cardColor,
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
                    if (linkedSit != null)
                      IconButton(
                        icon: Icon(
                          Icons.checklist_rtl,
                          color: cardColor,
                        ),
                        tooltip: '체크리스트 열기',
                        onPressed: () => _showChecklistBottomSheet(
                          sc,
                          linkedSit,
                        ),
                      ),
                    IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 20,
                      ),
                      tooltip: '일정 수정',
                      onPressed: () => _showScheduleDialog(
                        existing: sc,
                        occurrenceDate: activeDay,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDay = _selectedDay ?? _focusedDay;
    final selectedEvents = _getEventsForDay(activeDay);
    final tags = _allAvailableTags;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildReorderableTagBar(tags),
                  ),
                ),
                IconButton(
                  icon: Icon(_isSearching ? Icons.close : Icons.search),
                  tooltip: '일정 검색',
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchQuery = '';
                        _searchController.clear();
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '일정 이름 또는 #태그 검색...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
          if (widget.showTips)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
                      '팁: #태그 버튼을 꾹 눌러 순서를 바꾸고, 바를 움직여 2주/한달/확장을 조절하세요.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight;
                final stageHeights = _getStageHeights(availableHeight);
                final hTwoWeeks = stageHeights[CalendarViewStage.twoWeeks]!;
                final hMonth = stageHeights[CalendarViewStage.month]!;
                final hExpanded = stageHeights[CalendarViewStage.expanded]!;

                final targetCalendarHeight = _isDraggingBar
                    ? (_dragCalendarHeight ?? stageHeights[_viewStage]!)
                        .clamp(hTwoWeeks, hExpanded)
                    : stageHeights[_viewStage]!;

                final activeStageHighlight = _isDraggingBar
                    ? _findNearestStage(targetCalendarHeight, stageHeights)
                    : _viewStage;

                final weekRows = _getWeekRowCount(_focusedDay);

                return Column(
                  children: [
                    AnimatedContainer(
                      duration: _isDraggingBar
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      height: targetCalendarHeight,
                      child: LayoutBuilder(
                        builder: (context, calConstraints) {
                          final currentH = calConstraints.maxHeight;
                          final twoWeeksMidpoint = (hTwoWeeks + hMonth) / 2.0;

                          final CalendarFormat activeFormat =
                              currentH <= twoWeeksMidpoint
                                  ? CalendarFormat.twoWeeks
                                  : CalendarFormat.month;

                          final double dynamicRowHeight = currentH > hMonth
                              ? ((currentH - _calendarChromeHeight) / weekRows)
                                  .clamp(_baseRowHeight, 160.0)
                              : _baseRowHeight;

                          final int maxMarkers = dynamicRowHeight >= 90
                              ? 4
                              : (dynamicRowHeight >= 70 ? 3 : 2);

                          return ClipRect(
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: _buildTableCalendar(
                                format: activeFormat,
                                rowHeight: dynamicRowHeight,
                                maxMarkers: maxMarkers,
                                stageHeights: stageHeights,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildSchedulePanelHeader(
                      activeDay: activeDay,
                      eventCount: selectedEvents.length,
                      activeStageHighlight: activeStageHighlight,
                      stageHeights: stageHeights,
                    ),
                    Expanded(
                      child: ClipRect(
                        child: _buildScheduleList(
                          activeDay,
                          selectedEvents,
                          stageHeights,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: _viewStage == CalendarViewStage.expanded ? 48.0 : 0.0,
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showScheduleDialog(occurrenceDate: activeDay),
          icon: const Icon(Icons.add),
          label: const Text('일정 추가'),
        ),
      ),
    );
  }
}