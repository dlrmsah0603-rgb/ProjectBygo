import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  const CalendarScreen({
    super.key,
    required this.schedules,
    required this.situations,
    required this.onSchedulesChanged,
    required this.onSituationsChanged,
    this.showTips = true,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarViewStage _viewStage = CalendarViewStage.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  String? _selectedFilterTag;
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // 실시간 드래그 추적 상태
  bool _isDraggingBar = false;
  double? _dragCalendarHeight;

  static const double _baseRowHeight = 58.0;
  static const double _calendarChromeHeight = 78.0; // 헤더(56) + 요일표시줄(22)
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final firstDayOffset = firstOfMonth.weekday % 7; // 일요일 시작 기준
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
    return tagSet.toList();
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

  /// 단일 일정은 즉시 삭제, 반복 일정은 예외 범위 선택 후 삭제 처리
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
                              labelText: '시간',
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

                    // 1. 새 일정 추가인 경우
                    if (existing == null) {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        widget.schedules.add(
                          Schedule(
                            id: DateTime.now()
                                .microsecondsSinceEpoch
                                .toString(),
                            date: selectedWeekdays.isNotEmpty
                                ? repeatStartDate
                                : activeOccurrenceDay,
                            title: title,
                            time: cleanTime,
                            tag: cleanTag,
                            repeatWeekdays: selectedWeekdays,
                            repeatEndDate: newEndDate,
                            repeatCount: newRepeatCount,
                          ),
                        );
                      });
                      widget.onSchedulesChanged(widget.schedules);
                      Navigator.pop(ctx);
                      return;
                    }

                    // 2. 기존 단일 일정 수정인 경우
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
                      });
                      widget.onSchedulesChanged(widget.schedules);
                      Navigator.pop(ctx);
                      return;
                    }

                    // 3. 기존 반복 일정 수정인 경우 -> 예외 처리 적용 범위 선택
                    final scope = await _showRepeatScopeDialog(
                      title: '반복 일정 변경',
                      targetDate: activeOccurrenceDay,
                      onlyThisLabel: '이 일정만 변경',
                      thisAndFutureLabel: '이 일정 및 이후 일정 변경',
                      allLabel: '전체 반복 일정 변경',
                    );

                    if (scope == null || !mounted) return;

                    HapticFeedback.mediumImpact();
                    setState(() {
                      switch (scope) {
                        case _RepeatActionScope.onlyThis:
                          // 선택한 날짜를 기존 반복에서 제외하고 해당 날짜의 단일 일정 생성
                          final key = Schedule.dateKey(activeOccurrenceDay);
                          if (!existing.excludedDates.contains(key)) {
                            existing.excludedDates.add(key);
                          }
                          widget.schedules.add(
                            Schedule(
                              id: DateTime.now()
                                  .microsecondsSinceEpoch
                                  .toString(),
                              date: activeOccurrenceDay,
                              title: title,
                              time: cleanTime,
                              tag: cleanTag,
                              repeatWeekdays: [],
                            ),
                          );
                          break;

                        case _RepeatActionScope.thisAndFuture:
                          final origStart = _dateOnly(existing.date);
                          final splitStart =
                              repeatStartDate != origStart
                                  ? repeatStartDate
                                  : activeOccurrenceDay;

                          if (!activeOccurrenceDay.isAfter(origStart)) {
                            // 시작일 당일(또는 이전)부터 이후 전체 변경이면 원본 자체를 업데이트
                            existing.date = splitStart;
                            existing.title = title;
                            existing.time = cleanTime;
                            existing.tag = cleanTag;
                            existing.repeatWeekdays = selectedWeekdays;
                            existing.repeatEndDate = newEndDate;
                            existing.repeatCount = newRepeatCount;
                          } else {
                            // 원본 일정은 선택일 전날까지만 반복되도록 종료일 설정
                            existing.repeatEndDate = activeOccurrenceDay
                                .subtract(const Duration(days: 1));
                            existing.repeatCount = null;

                            // 선택한 날짜부터 새로운 반복(또는 단일) 일정 추가
                            widget.schedules.add(
                              Schedule(
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
                              ),
                            );
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
                          break;
                      }
                    });

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
                                    : '소지품 챙김 현황: $checked / $total개 (${(progress * 100).round()}%)',
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
                            '등록된 소지품이 없습니다. [상황·소지품] 탭에서 항목을 추가해 보세요.',
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

  Widget _buildTableCalendar({
    required CalendarFormat format,
    required double rowHeight,
    required int maxMarkers,
    required Map<CalendarViewStage, double> stageHeights,
  }) {
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
        calendarStyle: const CalendarStyle(
          cellMargin: EdgeInsets.all(2),
          todayDecoration: BoxDecoration(
            color: Colors.indigoAccent,
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: Colors.indigo,
            shape: BoxShape.circle,
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
                  final badgeColor = sit?.color ?? Colors.blue;
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
                                  ? Colors.white
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
          final isComplete = linkedSit?.isAllChecked ?? false;
          final cardColor =
              isComplete ? Colors.green : (linkedSit?.color ?? Colors.blue);

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
                  color: cardColor.withValues(alpha: 0.35),
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
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 14),
                        const SizedBox(width: 4),
                        Text(sc.time),
                        if (sc.isRepeating) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.repeat, size: 14),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              _buildRepeatSummaryText(sc),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
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
                            '소지품 ${linkedSit.checkedCount}/${linkedSit.items.length}',
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
                        tooltip: '소지품 체크리스트 열기',
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
                    child: Row(
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
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              avatar: sit != null
                                  ? Icon(
                                      sit.iconData,
                                      size: 16,
                                      color: sit.color,
                                    )
                                  : null,
                              label: Text('#$tag'),
                              selected: _selectedFilterTag == tag,
                              onSelected: (selected) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _selectedFilterTag = selected ? tag : null;
                                });
                              },
                            ),
                          );
                        }),
                      ],
                    ),
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
                      '팁: 바를 잡고 위·아래로 움직여 2주 / 한달 / 확장 위치로 조절하세요.',
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