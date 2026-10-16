import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../main.dart';
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

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

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
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final loadedSchedules = await StorageService.loadSchedules();
    final loadedSituations = await StorageService.loadSituations();
    if (!mounted) return;
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

  bool _matchesFilterAndSearch(Schedule schedule) {
    if (_selectedTagFilter != null && _selectedTagFilter!.isNotEmpty) {
      if (schedule.tag != _selectedTagFilter) return false;
    }

    if (_searchKeyword.isNotEmpty) {
      final keyword = _searchKeyword.toLowerCase();
      final matchTitle = schedule.title.toLowerCase().contains(keyword);
      final matchTag = schedule.tag?.toLowerCase().contains(keyword) ?? false;
      final linkedSit = _findSituation(schedule);
      final matchSit =
          linkedSit?.title.toLowerCase().contains(keyword) ?? false;
      if (!matchTitle && !matchTag && !matchSit) return false;
    }

    return true;
  }

  List<Schedule> _getSchedulesForDay(DateTime day) {
    return _schedules.where((schedule) {
      if (!schedule.occursOn(day)) return false;
      return _matchesFilterAndSearch(schedule);
    }).toList()
      ..sort((a, b) {
        final aMin = a.dateTime.hour * 60 + a.dateTime.minute;
        final bMin = b.dateTime.hour * 60 + b.dateTime.minute;
        return aMin.compareTo(bMin);
      });
  }

  List<Schedule> _getAllSearchedSchedules() {
    return _schedules.where(_matchesFilterAndSearch).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  String _formatRepeatDays(List<int> days) {
    if (days.isEmpty) return '';
    if (days.length == 7) return '매일';
    final sorted = [...days]..sort();
    if (sorted.length == 5 && sorted[0] == 1 && sorted[4] == 5) {
      return '평일마다';
    }
    return '매주 ${sorted.map((d) => _weekdayLabels[d - 1]).join(', ')}';
  }

  String _formatDateLabel(Schedule schedule) {
    if (schedule.repeatDays.isNotEmpty) {
      return _formatRepeatDays(schedule.repeatDays);
    }
    final d = schedule.dateTime;
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }

  void _showScheduleDialog({Schedule? existingSchedule}) {
    final titleController =
        TextEditingController(text: existingSchedule?.title ?? '');
    final tagController =
        TextEditingController(text: existingSchedule?.tag ?? '');
    TimeOfDay selectedTime = existingSchedule != null
        ? TimeOfDay(
            hour: existingSchedule.dateTime.hour,
            minute: existingSchedule.dateTime.minute,
          )
        : TimeOfDay.now();
    Situation? selectedSituation =
        existingSchedule != null ? _findSituation(existingSchedule) : null;
    List<int> selectedRepeatDays =
        existingSchedule != null ? [...existingSchedule.repeatDays] : [];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingSchedule == null ? '새 일정 추가' : '일정 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_situations.isNotEmpty) ...[
                  const Text(
                    '외출 상황 불러오기 (선택 시 자동 연동)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: _situations.map((sit) {
                      final isSelected = selectedSituation?.id == sit.id;
                      return ChoiceChip(
                        avatar: Icon(
                          sit.icon,
                          size: 16,
                          color: isSelected ? Colors.white : sit.color,
                        ),
                        label: Text(sit.title),
                        selected: isSelected,
                        selectedColor: sit.color,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : null,
                        ),
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
                const SizedBox(height: 12),
                const Text(
                  '요일별 반복 설정 (미선택 시 단일 일정)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: List.generate(7, (idx) {
                    final weekday = idx + 1;
                    final isSelected = selectedRepeatDays.contains(weekday);
                    return FilterChip(
                      label: Text(_weekdayLabels[idx]),
                      selected: isSelected,
                      visualDensity: VisualDensity.compact,
                      onSelected: (val) {
                        setDialogState(() {
                          if (val) {
                            selectedRepeatDays.add(weekday);
                          } else {
                            selectedRepeatDays.remove(weekday);
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
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;

                final baseDate = existingSchedule?.dateTime ?? _selectedDay;
                final scheduleDateTime = DateTime(
                  baseDate.year,
                  baseDate.month,
                  baseDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );
                final tagText = tagController.text.trim().isEmpty
                    ? null
                    : tagController.text.trim();
                selectedRepeatDays.sort();

                if (existingSchedule == null) {
                  _schedules.add(
                    Schedule(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: title,
                      dateTime: scheduleDateTime,
                      tag: tagText,
                      situationId: selectedSituation?.id,
                      repeatDays: selectedRepeatDays,
                    ),
                  );
                } else {
                  existingSchedule.title = title;
                  existingSchedule.dateTime = scheduleDateTime;
                  existingSchedule.tag = tagText;
                  existingSchedule.situationId = selectedSituation?.id;
                  existingSchedule.repeatDays = selectedRepeatDays;
                }

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

  // 파일 다운로드/업로드 방식의 백업 및 복원 다이얼로그
  void _showBackupDialog() {
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('데이터 백업 및 복원'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '현재 등록된 모든 일정과 외출 상황·소지품 데이터를 JSON 파일(.json)로 저장하거나 불러옵니다.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.download_outlined),
                label: const Text('백업 파일 다운로드 (.json 저장)'),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  try {
                    final savedPath =
                        await StorageService.exportBackupToFile();
                    if (savedPath != null) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('백업 파일이 저장되었습니다: $savedPath'),
                        ),
                      );
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('백업 파일 저장 중 오류가 발생했습니다.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('백업 파일 업로드 (.json 불러오기)'),
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  try {
                    final restored =
                        await StorageService.importBackupFromFile();
                    if (restored) {
                      await _loadAllData();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('백업 파일에서 데이터가 성공적으로 복원되었습니다!'),
                        ),
                      );
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('올바른 백업 JSON 파일이 아니거나 읽기에 실패했습니다.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleDarkMode() async {
    final isDark = themeNotifier.value == ThemeMode.dark;
    final nextDark = !isDark;
    themeNotifier.value = nextDark ? ThemeMode.dark : ThemeMode.light;
    await StorageService.saveIsDarkMode(nextDark);
  }

  Widget _buildDayCell(
    DateTime day, {
    bool isSelected = false,
    bool isToday = false,
  }) {
    final daySchedules = _getSchedulesForDay(day);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 3),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.indigo.withValues(alpha: 0.18)
            : isToday
                ? Colors.amber.withValues(alpha: 0.15)
                : null,
        border: Border.all(
          color: isSelected
              ? Colors.indigo
              : isDark
                  ? Colors.grey.shade700
                  : Colors.grey.shade300,
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
              fontWeight:
                  isSelected || isToday ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? (isDark ? Colors.indigo.shade200 : Colors.indigo)
                  : null,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: daySchedules.length > 2 ? 2 : daySchedules.length,
              itemBuilder: (context, idx) {
                final sc = daySchedules[idx];
                final sit = _findSituation(sc);
                final badgeColor = sit?.color ?? Colors.indigo;

                return Container(
                  margin: const EdgeInsets.only(bottom: 1.5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    sc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark ? Colors.white : badgeColor,
                      fontWeight: FontWeight.w600,
                    ),
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
    final bool isGlobalSearchActive = _searchKeyword.isNotEmpty;
    final List<Schedule> displayedSchedules = isGlobalSearchActive
        ? _getAllSearchedSchedules()
        : _getSchedulesForDay(_selectedDay);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '전체 일정에서 이름, 태그, 상황 검색...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(fontSize: 15),
                ),
                onChanged: (val) => setState(() => _searchKeyword = val.trim()),
              )
            : const Text('캘린더 및 일정'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? '검색 닫기' : '전체 일정 검색',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchKeyword = '';
                }
              });
            },
          ),
          if (!_isSearching) ...[
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
            IconButton(
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode_outlined),
              tooltip: '다크 모드 전환',
              onPressed: _toggleDarkMode,
            ),
            IconButton(
              icon: const Icon(Icons.import_export),
              tooltip: '데이터 백업 및 복원 (파일)',
              onPressed: _showBackupDialog,
            ),
          ],
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
                    onSelected: (_) =>
                        setState(() => _selectedTagFilter = null),
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
          if (!isGlobalSearchActive) ...[
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
                defaultBuilder: (context, day, focusedDay) =>
                    _buildDayCell(day),
                selectedBuilder: (context, day, focusedDay) =>
                    _buildDayCell(day, isSelected: true),
                todayBuilder: (context, day, focusedDay) =>
                    _buildDayCell(day, isToday: true),
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isGlobalSearchActive
                      ? '🔍 전체 일정 검색 결과 (${displayedSchedules.length}건)'
                      : '${_selectedDay.month}월 ${_selectedDay.day}일 세부 일정 (${displayedSchedules.length}건)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (isGlobalSearchActive)
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: const Text('달력 보기'),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchKeyword = '';
                        _isSearching = false;
                      });
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: displayedSchedules.isEmpty
                ? Center(
                    child: Text(
                      isGlobalSearchActive
                          ? '\'$_searchKeyword\'에 해당하는 일정이 없습니다.'
                          : '등록된 일정이 없습니다. 우측 하단 + 버튼으로 추가해 보세요!',
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: displayedSchedules.length,
                    itemBuilder: (context, idx) {
                      final schedule = displayedSchedules[idx];
                      final linkedSituation = _findSituation(schedule);
                      final themeColor =
                          linkedSituation?.color ?? Colors.indigo;
                      final targetDay = isGlobalSearchActive
                          ? schedule.dateTime
                          : _selectedDay;
                      final isDone = schedule.isCompletedOn(targetDay);
                      final timeString =
                          '${schedule.dateTime.hour.toString().padLeft(2, '0')}:${schedule.dateTime.minute.toString().padLeft(2, '0')}';
                      final dateOrRepeatLabel = _formatDateLabel(schedule);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          leading: Checkbox(
                            activeColor: themeColor,
                            value: isDone,
                            onChanged: (val) async {
                              schedule.setCompletedOn(
                                targetDay,
                                val ?? false,
                              );
                              await StorageService.saveSchedules(_schedules);
                              if (!mounted) return;
                              setState(() {});
                            },
                          ),
                          title: Row(
                            children: [
                              if (linkedSituation != null) ...[
                                Icon(
                                  linkedSituation.icon,
                                  size: 18,
                                  color: themeColor,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  schedule.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    decoration: isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (isGlobalSearchActive ||
                                  schedule.repeatDays.isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      schedule.repeatDays.isNotEmpty
                                          ? Icons.repeat
                                          : Icons.event,
                                      size: 13,
                                      color: themeColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      dateOrRepeatLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: themeColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(timeString),
                                ],
                              ),
                              if (schedule.tag != null &&
                                  schedule.tag!.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: themeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${schedule.tag}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: themeColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isGlobalSearchActive &&
                                  schedule.repeatDays.isEmpty)
                                IconButton(
                                  icon: const Icon(
                                    Icons.calendar_today,
                                    size: 18,
                                  ),
                                  tooltip: '이 날짜로 이동',
                                  onPressed: () {
                                    setState(() {
                                      _selectedDay = schedule.dateTime;
                                      _focusedDay = schedule.dateTime;
                                      _isSearching = false;
                                      _searchController.clear();
                                      _searchKeyword = '';
                                    });
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: '일정 수정',
                                onPressed: () => _showScheduleDialog(
                                  existingSchedule: schedule,
                                ),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 20),
                                tooltip: '일정 삭제',
                                onPressed: () async {
                                  _schedules.removeWhere(
                                    (s) => s.id == schedule.id,
                                  );
                                  await StorageService.saveSchedules(
                                    _schedules,
                                  );
                                  if (!mounted) return;
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                          children: [
                            if (linkedSituation == null)
                              const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Text(
                                  '연동된 외출 소지품 체크리스트가 없습니다.',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            else ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                color: themeColor.withValues(alpha: 0.08),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          linkedSituation.icon,
                                          size: 16,
                                          color: themeColor,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '[${linkedSituation.title}] 소지품 (${linkedSituation.items.where((i) => i.isChecked).length}/${linkedSituation.items.length})',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: themeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        TextButton(
                                          onPressed: () async {
                                            for (var item
                                                in linkedSituation.items) {
                                              item.isChecked = true;
                                            }
                                            await StorageService.saveSituations(
                                              _situations,
                                            );
                                            if (!mounted) return;
                                            setState(() {});
                                          },
                                          child: const Text(
                                            '모두 체크',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            for (var item
                                                in linkedSituation.items) {
                                              item.isChecked = false;
                                            }
                                            await StorageService.saveSituations(
                                              _situations,
                                            );
                                            if (!mounted) return;
                                            setState(() {});
                                          },
                                          child: const Text(
                                            '체크 리셋',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              ...linkedSituation.items.map((item) {
                                return CheckboxListTile(
                                  dense: true,
                                  activeColor: themeColor,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
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
                                    await StorageService.saveSituations(
                                      _situations,
                                    );
                                    if (!mounted) return;
                                    setState(() {});
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
        onPressed: () => _showScheduleDialog(),
        icon: const Icon(Icons.add),
        label: const Text('일정 추가'),
      ),
    );
  }
}