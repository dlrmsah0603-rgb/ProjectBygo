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

  /// 각 단계(2주 / 한달 / 확장)에서의 캘린더 영역 높이(= 바의 Y 위치) 계산
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

  /// 주어진 바 위치(height)에서 가장 가까운 단계 반환
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

    // 드래그 중 가장 가까운 단계가 바뀔 때 가벼운 햅틱 피드백 제공
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

  void _deleteSchedule(Schedule schedule) {
    final originalIndex = widget.schedules.indexOf(schedule);
    if (originalIndex == -1) return;

    setState(() {
      widget.schedules.removeAt(originalIndex);
    });
    HapticFeedback.mediumImpact();
    widget.onSchedulesChanged(widget.schedules);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("'${schedule.title}' 일정이 삭제되었습니다."),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '실행 취소',
          onPressed: () {
            HapticFeedback.lightImpact();
            setState(() {
              final insertIdx =
                  originalIndex.clamp(0, widget.schedules.length);
              widget.schedules.insert(insertIdx, schedule);
            });
            widget.onSchedulesChanged(widget.schedules);
          },
        ),
      ),
    );
  }

  void _showScheduleDialog({Schedule? existing, DateTime? defaultDate}) {
    HapticFeedback.selectionClick();
    final targetDate =
        existing?.date ?? defaultDate ?? _selectedDay ?? DateTime.now();
    final titleController = TextEditingController(text: existing?.title ?? '');
    final timeController = TextEditingController(
      text: existing?.time ?? '09:00',
    );
    final tagController = TextEditingController(text: existing?.tag ?? '');
    final selectedWeekdays = List<int>.from(existing?.repeatWeekdays ?? []);

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
                  ],
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteSchedule(existing);
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
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;

                    HapticFeedback.mediumImpact();
                    final cleanTag =
                        tagController.text.trim().replaceAll('#', '');

                    setState(() {
                      if (existing == null) {
                        widget.schedules.add(
                          Schedule(
                            id: DateTime.now()
                                .microsecondsSinceEpoch
                                .toString(),
                            date: targetDate,
                            title: title,
                            time: timeController.text.trim(),
                            tag: cleanTag,
                            repeatWeekdays: selectedWeekdays,
                          ),
                        );
                      } else {
                        existing.title = title;
                        existing.time = timeController.text.trim();
                        existing.tag = cleanTag;
                        existing.repeatWeekdays = selectedWeekdays;
                      }
                    });
                    widget.onSchedulesChanged(widget.schedules);
                    Navigator.pop(ctx);
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
          _showScheduleDialog(defaultDate: selectedDay);
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
            key: ValueKey('${sc.id}_${sc.date}'),
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
            onDismissed: (_) => _deleteSchedule(sc),
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
                    _showScheduleDialog(existing: sc);
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
                          Text(
                            sc.repeatWeekdays
                                .map((w) => _weekdayLabels[w - 1])
                                .join('·'),
                            style: const TextStyle(fontSize: 12),
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
                      onPressed: () => _showScheduleDialog(existing: sc),
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
          onPressed: () => _showScheduleDialog(),
          icon: const Icon(Icons.add),
          label: const Text('일정 추가'),
        ),
      ),
    );
  }
}