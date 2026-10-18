import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/schedule_model.dart';
import '../models/situation_model.dart';

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
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  String? _selectedTagFilter;
  String _searchQuery = '';
  bool _isSearching = false;

  static const List<String> _weekdayLabels = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  List<String> get _allTags {
    final tags = <String>{};
    for (final s in widget.situations) {
      if (s.tag.isNotEmpty) tags.add(s.tag);
    }
    for (final sc in widget.schedules) {
      if (sc.tag.isNotEmpty) tags.add(sc.tag);
    }
    return tags.toList();
  }

  Situation? _findSituationByTag(String tag) {
    if (tag.isEmpty) return null;
    for (final s in widget.situations) {
      if (s.tag == tag || s.name == tag) return s;
    }
    return null;
  }

  List<Schedule> _getSchedulesForDay(DateTime day) {
    return widget.schedules.where((schedule) {
      final matchesDay = schedule.occursOn(day);
      final matchesTag = _selectedTagFilter == null ||
          schedule.tag == _selectedTagFilter;
      return matchesDay && matchesTag;
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  List<Schedule> get _searchedSchedules {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return [];
    return widget.schedules.where((sc) {
      return sc.title.toLowerCase().contains(q) ||
          sc.tag.toLowerCase().contains(q) ||
          sc.time.toLowerCase().contains(q);
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

  void _deleteSchedule(Schedule schedule) {
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
            _notifySchedules();
          },
        ),
      ),
    );
  }

  void _showScheduleDialog({DateTime? targetDate, Schedule? existing}) {
    final day = targetDate ?? existing?.date ?? _selectedDay;
    final titleController =
        TextEditingController(text: existing?.title ?? '');
    final tagController = TextEditingController(text: existing?.tag ?? '');
    String selectedTime = existing?.time ?? '09:00';
    final List<int> repeatDays = List<int>.from(existing?.repeatDays ?? []);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null
                    ? '${day.month}월 ${day.day}일 일정 추가'
                    : '일정 수정',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.situations.isNotEmpty) ...[
                      const Text(
                        '외출 상황 불러오기 (선택 시 이름·태그 자동 입력)',
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
                                titleController.text = sit.name;
                                tagController.text = sit.tag;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: titleController,
                      autofocus: existing == null,
                      decoration: const InputDecoration(
                        labelText: '일정 이름',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
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
                            icon: const Icon(Icons.access_time),
                            label: Text('시간: $selectedTime'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tagController,
                      decoration: const InputDecoration(
                        labelText: '태그 (상황과 연동)',
                        prefixText: '#',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '요일별 반복 설정',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      children: List.generate(7, (index) {
                        final weekdayNum = index + 1;
                        final isSelected = repeatDays.contains(weekdayNum);
                        return FilterChip(
                          label: Text(_weekdayLabels[index]),
                          selected: isSelected,
                          onSelected: (selected) {
                            HapticFeedback.selectionClick();
                            setDialogState(() {
                              if (selected) {
                                repeatDays.add(weekdayNum);
                                repeatDays.sort();
                              } else {
                                repeatDays.remove(weekdayNum);
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
                      HapticFeedback.mediumImpact();
                      Navigator.pop(ctx);
                      _deleteSchedule(existing); // 기존 스와이프 삭제 메서드 재사용 (실행 취소 스낵바 지원)
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
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
                    final tag =
                        tagController.text.trim().replaceAll('#', '');
                    if (title.isEmpty) return;

                    HapticFeedback.mediumImpact();
                    if (existing == null) {
                      widget.schedules.add(
                        Schedule(
                          id: DateTime.now()
                              .microsecondsSinceEpoch
                              .toString(),
                          title: title,
                          date: day,
                          time: selectedTime,
                          tag: tag,
                          repeatDays: repeatDays,
                        ),
                      );
                    } else {
                      existing.title = title;
                      existing.time = selectedTime;
                      existing.tag = tag;
                      existing.repeatDays = repeatDays;
                    }
                    _notifySchedules();
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
                                  '등록된 소지품이 없습니다. [상황·소지품] 탭에서 항목을 추가해 보세요.',
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

  @override
  Widget build(BuildContext context) {
    final daySchedules = _getSchedulesForDay(_selectedDay);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _isSearching
                          ? TextField(
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: '전체 일정 이름·태그·시간 검색...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    setState(() {
                                      _isSearching = false;
                                      _searchQuery = '';
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
                                    selected: _selectedTagFilter == null,
                                    onSelected: (_) {
                                      HapticFeedback.selectionClick();
                                      setState(
                                          () => _selectedTagFilter = null);
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  ..._allTags.map((tag) {
                                    final sit = _findSituationByTag(tag);
                                    final isSelected =
                                        _selectedTagFilter == tag;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
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
                                            _selectedTagFilter =
                                                selected ? tag : null;
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
                        tooltip: '전체 일정 검색',
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() => _isSearching = true);
                        },
                      ),
                  ],
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
                            '${sc.date.year}-${sc.date.month.toString().padLeft(2, '0')}-${sc.date.day.toString().padLeft(2, '0')} (${sc.time})  #${sc.tag}',
                          ),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedDay = sc.date;
                              _focusedDay = sc.date;
                              _isSearching = false;
                              _searchQuery = '';
                            });
                          },
                        );
                      },
                    ),
            )
          else ...[
            if (widget.showTips)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
                        '팁: 날짜를 길게 누르면(Long Press) 해당 날짜에 일정을 바로 추가합니다.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            TableCalendar<Schedule>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: _getSchedulesForDay,
              rowHeight: 64,
              headerStyle: const HeaderStyle(
                titleCentered: true,
                formatButtonShowsNext: false,
                formatButtonDecoration: BoxDecoration(
                  border: Border.fromBorderSide(BorderSide(color: Colors.grey)),
                  borderRadius: BorderRadius.all(Radius.circular(12.0)),
                ),
                formatButtonTextStyle: TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              availableCalendarFormats: const {
                CalendarFormat.month: '월간',
                CalendarFormat.twoWeeks: '2주',
                CalendarFormat.week: '주간',
              },
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
              onFormatChanged: (format) {
                setState(() => _calendarFormat = format);
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  if (events.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 30, left: 1, right: 1),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: events.take(2).map((sc) {
                        final sit = _findSituationByTag(sc.tag);
                        final badgeColor = sit?.color ?? Colors.blue;
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 0.5,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
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
            const Divider(height: 1),
            Expanded(
              child: daySchedules.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_selectedDay.month}월 ${_selectedDay.day}일에 등록된 일정이 없습니다.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () =>
                                _showScheduleDialog(targetDate: _selectedDay),
                            icon: const Icon(Icons.add),
                            label: const Text('이 날짜에 일정 추가하기'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                      itemCount: daySchedules.length,
                      itemBuilder: (context, index) {
                        final sc = daySchedules[index];
                        final linkedSituation = _findSituationByTag(sc.tag);
                        final color = linkedSituation?.color ?? Colors.blue;
                        final isComplete =
                            linkedSituation?.isAllChecked ?? false;

                        return Dismissible(
                          key: ValueKey('sched_${sc.id}_${_selectedDay.day}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.centerRight,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.end,
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
                          onDismissed: (_) => _deleteSchedule(sc),
                          child: Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isComplete
                                    ? Colors.green.withValues(alpha: 0.7)
                                    : color.withValues(alpha: 0.3),
                              ),
                            ),
                            child: ListTile(
                              onTap: () {
                                if (linkedSituation != null) {
                                  _showLinkedChecklistSheet(
                                      sc, linkedSituation);
                                } else {
                                  _showScheduleDialog(existing: sc);
                                }
                              },
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.15),
                                child: Icon(
                                  linkedSituation?.iconData ?? Icons.event,
                                  color: color,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      sc.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (sc.tag.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '#${sc.tag}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: color,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
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
                                      if (sc.repeatDays.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.repeat, size: 14),
                                        const SizedBox(width: 2),
                                        Text(
                                          sc.repeatDays
                                              .map((d) =>
                                                  _weekdayLabels[d - 1])
                                              .join('·'),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (linkedSituation != null &&
                                      linkedSituation.items.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: linkedSituation.progress,
                                              minHeight: 6,
                                              backgroundColor: Colors.grey
                                                  .withValues(alpha: 0.2),
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
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
                                              : '소지품 ${linkedSituation.checkedCount}/${linkedSituation.items.length}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
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
                                      tooltip: '소지품 체크리스트 열기',
                                      icon: Icon(
                                        Icons.fact_check_outlined,
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
                                        _showScheduleDialog(existing: sc),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
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