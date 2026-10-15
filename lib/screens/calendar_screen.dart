import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/schedule_model.dart';
import '../models/situation_model.dart';
import '../services/storage_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  List<Schedule> _schedules = [];
  List<Situation> _situations = [];
  String? _selectedTagFilter;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final loadedSchedules = await StorageService.loadSchedules();
    final loadedSituations = await StorageService.loadSituations();
    setState(() {
      _schedules = loadedSchedules;
      _situations = loadedSituations;
    });
  }

  List<String> get _allTags {
    final tags = <String>{};
    for (var s in _situations) {
      if (s.tag.isNotEmpty) tags.add(s.tag);
    }
    for (var sc in _schedules) {
      if (sc.tag != null && sc.tag!.isNotEmpty) tags.add(sc.tag!);
    }
    return tags.toList();
  }

  List<Schedule> _getSchedulesForDay(DateTime day) {
    return _schedules.where((schedule) {
      final sameDay = isSameDay(schedule.dateTime, day);
      if (!sameDay) return false;
      if (_selectedTagFilter != null && _selectedTagFilter!.isNotEmpty) {
        return schedule.tag == _selectedTagFilter;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  Situation? _findSituation(Schedule schedule) {
    if (schedule.situationId != null) {
      try {
        return _situations.firstWhere((s) => s.id == schedule.situationId);
      } catch (_) {}
    }
    if (schedule.tag != null && schedule.tag!.isNotEmpty) {
      try {
        return _situations.firstWhere((s) => s.tag == schedule.tag);
      } catch (_) {}
    }
    return null;
  }

  void _showAddScheduleDialog() {
    final titleController = TextEditingController();
    final tagController = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    Situation? selectedSituation;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('새 일정 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_situations.isNotEmpty) ...[
                  const Text(
                    '외출 상황 불러오기 (선택 시 자동 입력)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: _situations.map((sit) {
                      final isSelected = selectedSituation?.id == sit.id;
                      return ChoiceChip(
                        label: Text(sit.title),
                        selected: isSelected,
                        onSelected: (selected) {
                          setDialogState(() {
                            selectedSituation = selected ? sit : null;
                            if (selected) {
                              if (titleController.text.isEmpty) {
                                titleController.text = sit.title;
                              }
                              tagController.text = sit.tag;
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(height: 24),
                ],
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '일정 이름',
                    hintText: '예: 저녁 헬스장, 오전 출근',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagController,
                  decoration: const InputDecoration(
                    labelText: '태그',
                    hintText: '예: 운동, 출근',
                    prefixText: '# ',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('일정 시간: ${selectedTime.format(context)}'),
                    TextButton.icon(
                      icon: const Icon(Icons.access_time, size: 18),
                      label: const Text('시간 변경'),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;

                final scheduleDateTime = DateTime(
                  _selectedDay.year,
                  _selectedDay.month,
                  _selectedDay.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                final newSchedule = Schedule(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: title,
                  dateTime: scheduleDateTime,
                  tag: tagController.text.trim().isEmpty
                      ? null
                      : tagController.text.trim(),
                  situationId: selectedSituation?.id,
                );

                _schedules.add(newSchedule);
                Navigator.pop(dialogContext);
                await StorageService.saveSchedules(_schedules);
                if (!mounted) return;
                setState(() {});
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(DateTime day, {bool isSelected = false, bool isToday = false}) {
    final daySchedules = _getSchedulesForDay(day);

    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 3),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.indigo.withValues(alpha: 0.12)
            : isToday
                ? Colors.amber.withValues(alpha: 0.15)
                : null,
        border: Border.all(
          color: isSelected ? Colors.indigo : Colors.grey.shade300,
          width: isSelected ? 1.5 : 0.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${day.day}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.indigo : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: daySchedules.length > 2 ? 2 : daySchedules.length,
              itemBuilder: (context, idx) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade100,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    daySchedules[idx].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Colors.indigo),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDaySchedules = _getSchedulesForDay(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('캘린더 및 일정'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: '오늘로 이동',
            onPressed: () {
              setState(() {
                _focusedDay = DateTime.now();
                _selectedDay = DateTime.now();
              });
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_allTags.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('전체'),
                    selected: _selectedTagFilter == null,
                    onSelected: (_) => setState(() => _selectedTagFilter = null),
                  ),
                  const SizedBox(width: 6),
                  ..._allTags.map((tag) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('#$tag'),
                        selected: _selectedTagFilter == tag,
                        onSelected: (selected) {
                          setState(() {
                            _selectedTagFilter = selected ? tag : null;
                          });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          TableCalendar<Schedule>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedDay,
            rowHeight: 68,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) => _buildDayCell(day),
              selectedBuilder: (context, day, focusedDay) =>
                  _buildDayCell(day, isSelected: true),
              todayBuilder: (context, day, focusedDay) =>
                  _buildDayCell(day, isToday: true),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '${_selectedDay.month}월 ${_selectedDay.day}일 세부 일정 (${selectedDaySchedules.length}건)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          Expanded(
            child: selectedDaySchedules.isEmpty
                ? const Center(
                    child: Text('등록된 일정이 없습니다. 우측 하단 + 버튼으로 추가해 보세요!'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: selectedDaySchedules.length,
                    itemBuilder: (context, idx) {
                      final schedule = selectedDaySchedules[idx];
                      final linkedSituation = _findSituation(schedule);
                      final timeString =
                          '${schedule.dateTime.hour.toString().padLeft(2, '0')}:${schedule.dateTime.minute.toString().padLeft(2, '0')}';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          leading: Checkbox(
                            value: schedule.isCompleted,
                            onChanged: (val) async {
                              schedule.isCompleted = val ?? false;
                              await StorageService.saveSchedules(_schedules);
                              setState(() {});
                            },
                          ),
                          title: Text(
                            schedule.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: schedule.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              const Icon(Icons.schedule, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(timeString),
                              if (schedule.tag != null && schedule.tag!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${schedule.tag}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.indigo),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () async {
                              _schedules.removeWhere((s) => s.id == schedule.id);
                              await StorageService.saveSchedules(_schedules);
                              setState(() {});
                              if (!mounted) return;
                            },
                          ),
                          children: [
                            if (linkedSituation == null)
                              const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Text(
                                  '연동된 외출 소지품 체크리스트가 없습니다.',
                                  style: TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              )
                            else ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                color: Colors.grey.shade100,
                                child: Text(
                                  '🎒 [${linkedSituation.title}] 챙겨야 할 소지품',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              ...linkedSituation.items.map((item) {
                                return CheckboxListTile(
                                  dense: true,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: Text(
                                    item.name,
                                    style: TextStyle(
                                      decoration: item.isChecked
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  value: item.isChecked,
                                  onChanged: (val) async {
                                    item.isChecked = val ?? false;
                                    await StorageService.saveSituations(_situations);
                                    setState(() {});
                                    if (!mounted) return;
                                  },
                                );
                              }),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddScheduleDialog,
        icon: const Icon(Icons.add),
        label: const Text('일정 추가'),
      ),
    );
  }
}