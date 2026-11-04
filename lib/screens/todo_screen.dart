import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/todo_model.dart';
import '../services/google_sync_service.dart';
import 'settings_screen.dart';

class TodoScreen extends StatefulWidget {
  final List<TodoItem> todos;
  final bool showTips;
  final bool? isGoogleTasksSynced;
  final bool isSyncingTasks;
  final VoidCallback? onSyncGoogleTasks;
  final ValueChanged<List<TodoItem>> onTodosChanged;

  const TodoScreen({
    super.key,
    required this.todos,
    this.showTips = true,
    this.isGoogleTasksSynced,
    this.isSyncingTasks = false,
    this.onSyncGoogleTasks,
    required this.onTodosChanged,
  });

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  static const List<String> _weekdayLabels = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  bool _isOngoingExpanded = true;
  bool _isCompletedExpanded = false;
  bool _localSyncing = false;

  @override
  void initState() {
    super.initState();
    SettingsScreen.ensureSyncPrefsLoaded();
  }

  List<TodoItem> get _activeTodos =>
      widget.todos.where((t) => !t.isDeleted).toList();

  void _notifyParent() {
    setState(() {});
    widget.onTodosChanged(widget.todos);
  }

  Future<void> _triggerTasksSync() async {
    if (widget.onSyncGoogleTasks != null) {
      widget.onSyncGoogleTasks!();
      return;
    }
    if (_localSyncing) return;
    HapticFeedback.selectionClick();
    setState(() => _localSyncing = true);

    try {
      final result = await GoogleSyncService.instance.syncTodos(
        localTodos: widget.todos,
      );
      if (!mounted) return;
      setState(() {
        widget.todos
          ..clear()
          ..addAll(result.items);
        _localSyncing = false;
      });
      widget.onTodosChanged(widget.todos);
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
            GoogleSyncService.formatSyncError(e, featureName: '구글 할 일'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<TodoItem> _sortTodos(List<TodoItem> list) {
    final copy = List<TodoItem>.from(list);
    copy.sort((a, b) {
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1; // 기한 없음은 최하단 배치
      if (b.dueDate == null) return -1;

      final da = DateTime(a.dueDate!.year, a.dueDate!.month, a.dueDate!.day);
      final db = DateTime(b.dueDate!.year, b.dueDate!.month, b.dueDate!.day);
      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;

      final ta = a.dueTime ?? '23:59';
      final tb = b.dueTime ?? '23:59';
      return ta.compareTo(tb);
    });
    return copy;
  }

  void _deleteTodo(TodoItem todo) {
    final snapshot = widget.todos
        .map((t) => t.copyWith(lastEditedTime: t.lastEditedTime))
        .toList();

    HapticFeedback.mediumImpact();
    setState(() {
      if (todo.googleTaskId != null && todo.googleTaskId!.isNotEmpty) {
        final idx = widget.todos.indexWhere((t) => t.id == todo.id);
        if (idx != -1) {
          widget.todos[idx] = todo.copyWith(
            isDeleted: true,
            lastEditedTime: DateTime.now(),
          );
        }
      } else {
        widget.todos.removeWhere((t) => t.id == todo.id);
      }
    });
    _notifyParent();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("'${todo.title}' 할 일이 삭제되었습니다."),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '실행 취소',
          onPressed: () {
            HapticFeedback.lightImpact();
            setState(() {
              widget.todos
                ..clear()
                ..addAll(snapshot);
            });
            _notifyParent();
          },
        ),
      ),
    );
  }

  void _showTodoDialog({TodoItem? existing}) {
    HapticFeedback.selectionClick();
    final titleController =
        TextEditingController(text: existing?.title ?? '');
    final subItemController = TextEditingController();
    final intervalController = TextEditingController(
      text: (existing?.repeatInterval ?? 1).toString(),
    );
    final countController = TextEditingController(
      text: (existing?.repeatCount ?? 10).toString(),
    );

    DateTime? selectedDueDate = existing?.dueDate;
    int? reminderMinutesBefore = existing?.reminderMinutesBefore;
    String? selectedDueTime = existing?.dueTime;
    TodoRepeatType repeatType = existing?.repeatType ?? TodoRepeatType.none;
    final List<int> repeatWeekdays = List<int>.from(
      existing?.repeatWeekdays.isNotEmpty == true
          ? existing!.repeatWeekdays
          : <int>[(selectedDueDate ?? DateTime.now()).weekday],
    );

    String repeatEndMode = 'infinite';
    if (existing?.repeatCount != null && existing!.repeatCount! > 0) {
      repeatEndMode = 'count';
    } else if (existing?.repeatEndDate != null) {
      repeatEndMode = 'endDate';
    }
    DateTime repeatEndDate = existing?.repeatEndDate ??
        (selectedDueDate ?? DateTime.now()).add(const Duration(days: 30));

    final List<TodoSubItem> subItems =
        existing?.subItems.map((e) => e.copyWith()).toList() ?? <TodoSubItem>[];

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? '새 할 일 추가' : '할 일 수정'),
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
                          labelText: '할 일 제목 *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 마감 기한 날짜 선택 (미지정 시 '기한 없음')
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate:
                                      selectedDueDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2035),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    selectedDueDate = picked;
                                    if (!repeatWeekdays
                                        .contains(picked.weekday)) {
                                      repeatWeekdays
                                        ..clear()
                                        ..add(picked.weekday);
                                    }
                                  });
                                }
                              },
                              icon: const Icon(Icons.event, size: 16),
                              label: Text(
                                selectedDueDate == null
                                    ? '마감일: 기한 없음'
                                    : '마감일: ${selectedDueDate!.year}.${selectedDueDate!.month}.${selectedDueDate!.day}',
                              ),
                            ),
                          ),
                          if (selectedDueDate != null)
                            IconButton(
                              tooltip: '기한 없음으로 변경',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                setDialogState(() {
                                  selectedDueDate = null;
                                  selectedDueTime = null;
                                  repeatType = TodoRepeatType.none;
                                });
                              },
                            ),
                        ],
                      ),

                      if (selectedDueDate != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  TimeOfDay initial =
                                      const TimeOfDay(hour: 18, minute: 0);
                                  if (selectedDueTime != null &&
                                      selectedDueTime!.contains(':')) {
                                    final parts = selectedDueTime!.split(':');
                                    initial = TimeOfDay(
                                      hour: int.tryParse(parts[0]) ?? 18,
                                      minute: int.tryParse(parts[1]) ?? 0,
                                    );
                                  }
                                  final picked = await showTimePicker(
                                    context: ctx,
                                    initialTime: initial,
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      selectedDueTime =
                                          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                    });
                                  }
                                },
                                icon: const Icon(Icons.access_time, size: 16),
                                label: Text(
                                  selectedDueTime == null
                                      ? '시간 미지정 (하루 종일)'
                                      : '마감 시간: $selectedDueTime',
                                ),
                              ),
                            ),
                            if (selectedDueTime != null)
                              IconButton(
                                tooltip: '시간 지우기',
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setDialogState(
                                    () { selectedDueTime = null; reminderMinutesBefore = null; }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        if (selectedDueTime != null) ...[
                          const SizedBox(height: 12),
                          const Text(
                            '알림 시간',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int?>(
                            initialValue: reminderMinutesBefore,
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
                                setDialogState(() => reminderMinutesBefore = val),
                          ),
                        ],
                        // 반복 주기 설정 (일정과 동일한 n일/주/개월/년 + 요일 + 종료 조건)
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
                            if (repeatType != TodoRepeatType.none) ...[
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
                              child: DropdownButtonFormField<TodoRepeatType>(
                                initialValue: repeatType,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                items: TodoRepeatType.values
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
                        if (repeatType == TodoRepeatType.weekly) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 4,
                            children: List.generate(7, (idx) {
                              final wNum = idx + 1;
                              final isSelected = repeatWeekdays.contains(wNum);
                              return FilterChip(
                                label: Text(_weekdayLabels[idx]),
                                selected: isSelected,
                                onSelected: (sel) {
                                  HapticFeedback.selectionClick();
                                  setDialogState(() {
                                    if (sel) {
                                      repeatWeekdays.add(wNum);
                                      repeatWeekdays.sort();
                                    } else if (repeatWeekdays.length > 1) {
                                      repeatWeekdays.remove(wNum);
                                    }
                                  });
                                },
                              );
                            }),
                          ),
                        ],
                        if (repeatType != TodoRepeatType.none) ...[
                          const SizedBox(height: 8),
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
                                  firstDate:
                                      selectedDueDate ?? DateTime.now(),
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

                      const SizedBox(height: 16),
                      const Text(
                        '세부 사항',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...subItems.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final sub = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.subdirectory_arrow_right,
                                  size: 16, color: Colors.grey),
                              const SizedBox(width: 6),
                              Expanded(child: Text(sub.name)),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setDialogState(() => subItems.removeAt(idx));
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: subItemController,
                              decoration: const InputDecoration(
                                hintText: '세부 사항 입력 후 추가',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (val) {
                                final text = val.trim();
                                if (text.isNotEmpty) {
                                  setDialogState(() {
                                    subItems.add(
                                      TodoSubItem(
                                        id: DateTime.now()
                                            .microsecondsSinceEpoch
                                            .toString(),
                                        name: text,
                                      ),
                                    );
                                    subItemController.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: () {
                              final text = subItemController.text.trim();
                              if (text.isNotEmpty) {
                                setDialogState(() {
                                  subItems.add(
                                    TodoSubItem(
                                      id: DateTime.now()
                                          .microsecondsSinceEpoch
                                          .toString(),
                                      name: text,
                                    ),
                                  );
                                  subItemController.clear();
                                });
                              }
                            },
                            child: const Text('추가'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteTodo(existing);
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

                    final parsedInterval =
                        (int.tryParse(intervalController.text.trim()) ?? 1)
                            .clamp(1, 365);
                    final parsedCount = repeatEndMode == 'count'
                        ? (int.tryParse(countController.text.trim()) ?? 1)
                            .clamp(1, 999)
                        : null;
                    final finalEndDate =
                        repeatEndMode == 'endDate' ? repeatEndDate : null;
                    final effectiveRepeat = selectedDueDate == null
                        ? TodoRepeatType.none
                        : repeatType;

                    HapticFeedback.mediumImpact();
                    if (existing == null) {
                      widget.todos.add(
                        TodoItem(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          title: title,
                          dueDate: selectedDueDate,
                          dueTime: selectedDueTime,
                          repeatType: effectiveRepeat,
                          repeatInterval: parsedInterval,
                          repeatWeekdays:
                              effectiveRepeat == TodoRepeatType.weekly
                                  ? List<int>.from(repeatWeekdays)
                                  : <int>[],
                          repeatEndDate: finalEndDate,
                          repeatCount: parsedCount,
                          anchorDay:
                              effectiveRepeat == TodoRepeatType.lastDayOfMonth
                                  ? 31
                                  : selectedDueDate?.day,
                          reminderMinutesBefore: reminderMinutesBefore,
                          subItems: subItems,
                          lastEditedTime: DateTime.now(),
                        ),
                      );
                    } else {
                      existing.title = title;
                      existing.dueDate = selectedDueDate;
                      existing.dueTime = selectedDueTime;
                      existing.repeatType = effectiveRepeat;
                      existing.repeatInterval = parsedInterval;
                      existing.repeatWeekdays =
                          effectiveRepeat == TodoRepeatType.weekly
                              ? List<int>.from(repeatWeekdays)
                              : <int>[];
                      existing.repeatEndDate = finalEndDate;
                      existing.repeatCount = parsedCount;
                      existing.anchorDay =
                          effectiveRepeat == TodoRepeatType.lastDayOfMonth
                              ? 31
                              : selectedDueDate?.day;
                      existing.reminderMinutesBefore = reminderMinutesBefore;
                      existing.subItems = subItems;
                      existing.markUpdated();
                    }

                    _notifyParent();
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

  String _formatDateHeader(DateTime? d) {
    if (d == null) return '기한 없음';
    const weekdays = ['', '월', '화', '수', '목', '금', '토', '일'];
    return '${d.year}년 ${d.month}월 ${d.day}일 (${weekdays[d.weekday]})';
  }

  Widget _buildTodoCard(TodoItem todo, DateTime now) {
    final isOverdue = todo.isOverdueAt(now);
    final scheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey('todo_${todo.id}'),
      direction: DismissDirection.horizontal,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _deleteTodo(todo),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isOverdue
                ? Colors.redAccent.withValues(alpha: 0.7)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: Checkbox(
                  value: todo.isCompleted,
                  onChanged: (val) {
                    HapticFeedback.lightImpact();
                    setState(() {
                      todo.toggleCompleted(val ?? false, DateTime.now());
                    });
                    _notifyParent();
                  },
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        todo.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration: todo.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: todo.isCompleted
                              ? Colors.grey
                              : (isOverdue ? Colors.redAccent : null),
                        ),
                      ),
                    ),
                    if (todo.googleTaskId != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.cloud_done_outlined,
                        size: 15,
                        color: scheme.primary,
                      ),
                    ],
                  ],
                ),
                subtitle: (todo.dueTime != null || todo.isRepeating || todo.hasReminder)
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (todo.dueTime != null)
                              Text(
                                '⏰ ${todo.dueTime}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isOverdue
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isOverdue ? Colors.redAccent : null,
                                ),
                              ),
                            if (todo.hasReminder)
                              Text(
                                '🔔 ${todo.reminderSummaryText}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.primary,
                                ),
                              ),
                            if (todo.isRepeating)
                              Text(
                                '🔁 ${todo.repeatSummaryText}',
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      )
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _showTodoDialog(existing: todo),
                ),
                onTap: () => _showTodoDialog(existing: todo),
              ),

              // 세부 사항(Sub-tasks) 개별 체크 리스트 (모두 체크해도 상위 할 일은 별도 체크)
              if (todo.hasSubItems)
                Padding(
                  padding:
                      const EdgeInsets.only(left: 56, right: 16, bottom: 8),
                  child: Column(
                    children: todo.subItems.map((sub) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            sub.isChecked = !sub.isChecked;
                            todo.markUpdated();
                          });
                          _notifyParent();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(
                                sub.isChecked
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                size: 18,
                                color: sub.isChecked
                                    ? scheme.primary
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  sub.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    decoration: sub.isChecked
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: sub.isChecked ? Colors.grey : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDateGroupedItems(List<TodoItem> list, DateTime now) {
    final sorted = _sortTodos(list);
    final widgets = <Widget>[];
    String? lastHeader;

    for (final todo in sorted) {
      final header = _formatDateHeader(todo.dueDate);
      if (header != lastHeader) {
        lastHeader = header;
        final isHeaderOverdue = !todo.isCompleted &&
            todo.dueDate != null &&
            DateTime(todo.dueDate!.year, todo.dueDate!.month,
                    todo.dueDate!.day, 23, 59, 59)
                .isBefore(now);
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              header,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isHeaderOverdue ? Colors.redAccent : Colors.grey.shade700,
              ),
            ),
          ),
        );
      }
      widgets.add(_buildTodoCard(todo, now));
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final ongoingTodos =
        _activeTodos.where((t) => !t.isCompleted).toList();
    final completedTodos =
        _activeTodos.where((t) => t.isCompleted).toList();

    return ValueListenableBuilder<bool>(
      valueListenable: SettingsScreen.googleTasksSyncNotifier,
      builder: (context, notifierTaskSynced, _) {
        final showSyncButton =
            widget.isGoogleTasksSynced ?? notifierTaskSynced;
        final isSyncing = widget.isSyncingTasks || _localSyncing;

        return Scaffold(
          body: Column(
            children: [
              if (widget.showTips)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: const Row(
                    children: [
                      Icon(Icons.swipe_outlined, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '팁: 할 일을 좌우로 밀면 삭제되며, 반복 할 일은 완료 후 다음 주기 하루 시작 시간에 자동으로 진행 중으로 복귀합니다.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    // --- [진행 중] 섹션 헤더 수정 ---
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
                      child: Row(
                        children: [
                          // 헤더 전체 영역 터치 가능하게 묶기
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _isOngoingExpanded = !_isOngoingExpanded);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                child: Row(
                                  children: [
                                    Text(
                                      '진행 중 (${ongoingTodos.length})',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
                                      _isOngoingExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      color: Colors.grey.shade700,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 구글 태스크 동기화 버튼 (동기화 켜져 있을 때만 우측에 표시)
                          if (showSyncButton) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Google 태스크 동기화',
                              onPressed: isSyncing ? null : _triggerTasksSync,
                              icon: isSyncing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(
                                      Icons.sync,
                                      color: scheme.primary,
                                      size: 20,
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (_isOngoingExpanded)
                      if (ongoingTodos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              '진행 중인 할 일이 없습니다.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ..._buildDateGroupedItems(ongoingTodos, now),

                    const Divider(height: 24),

                    // --- [완료됨] 섹션 헤더 수정 ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _isCompletedExpanded = !_isCompletedExpanded);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Row(
                              children: [
                                Text(
                                  '완료됨 (${completedTodos.length})',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  _isCompletedExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: Colors.grey.shade700,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_isCompletedExpanded)
                      if (completedTodos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              '완료된 할 일이 없습니다.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ..._buildDateGroupedItems(completedTodos, now),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showTodoDialog(),
            icon: const Icon(Icons.add_task),
            label: const Text('할 일 추가'),
          ),
        );
      },
    );
  }
}