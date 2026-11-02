import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/todo_model.dart';

enum _TodoRepeatEndMode { forever, untilDate, count }

class TodoScreen extends StatefulWidget {
  final List<TodoItem> todos;
  final bool showTips;
  final ValueChanged<List<TodoItem>> onTodosChanged;

  const TodoScreen({
    super.key,
    required this.todos,
    this.showTips = true,
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

  bool _isInProgressExpanded = true;
  bool _isCompletedExpanded = false;
  final Set<String> _expandedSubItemTodoIds = <String>{};

  void _notifyParent() {
    setState(() {});
    widget.onTodosChanged(widget.todos);
  }

  List<TodoItem> get _inProgressTodos {
    final list = widget.todos.where((t) => !t.isCompleted).toList();
    list.sort(_compareTodosByDeadline);
    return list;
  }

  List<TodoItem> get _completedTodos {
    final list = widget.todos.where((t) => t.isCompleted).toList();
    list.sort((a, b) {
      final aTime = a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return list;
  }

  int _compareTodosByDeadline(TodoItem a, TodoItem b) {
    if (a.dueDate == null && b.dueDate == null) {
      return a.title.compareTo(b.title);
    }
    if (a.dueDate == null) return 1;
    if (b.dueDate == null) return -1;

    final aDateOnly =
        DateTime(a.dueDate!.year, a.dueDate!.month, a.dueDate!.day);
    final bDateOnly =
        DateTime(b.dueDate!.year, b.dueDate!.month, b.dueDate!.day);
    final dateCmp = aDateOnly.compareTo(bDateOnly);
    if (dateCmp != 0) return dateCmp;

    final aTime = (a.dueTime != null && a.dueTime!.isNotEmpty)
        ? a.dueTime!
        : '99:99';
    final bTime = (b.dueTime != null && b.dueTime!.isNotEmpty)
        ? b.dueTime!
        : '99:99';
    return aTime.compareTo(bTime);
  }

  String _formatDateHeader(DateTime? date) {
    if (date == null) return '기한 없음';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    final weekday = _weekdayLabels[(target.weekday - 1).clamp(0, 6)];
    final baseStr = '${target.month}월 ${target.day}일 ($weekday)';

    if (diff == 0) return '오늘 · $baseStr';
    if (diff == 1) return '내일 · $baseStr';
    if (diff == -1) return '어제 · $baseStr';
    if (diff < -1) return '기한 지남 · $baseStr';
    return baseStr;
  }

  void _deleteTodoWithUndo(TodoItem todo) {
    final idx = widget.todos.indexOf(todo);
    if (idx == -1) return;

    HapticFeedback.mediumImpact();
    setState(() {
      widget.todos.removeAt(idx);
    });
    widget.onTodosChanged(widget.todos);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("'${todo.title}' 할 일이 삭제되었습니다."),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '실행 취소',
          onPressed: () {
            HapticFeedback.lightImpact();
            final insertIdx = idx.clamp(0, widget.todos.length);
            setState(() {
              widget.todos.insert(insertIdx, todo);
            });
            widget.onTodosChanged(widget.todos);
          },
        ),
      ),
    );
  }

  void _showTodoDialog({TodoItem? existing}) {
    HapticFeedback.selectionClick();
    final titleController =
        TextEditingController(text: existing?.title ?? '');
    DateTime? selectedDueDate = existing?.dueDate;
    String? selectedDueTime = existing?.dueTime;

    // 일정과 동일한 반복 설정 상태
    TodoRepeatType selectedRepeatType =
        existing?.repeatType ?? TodoRepeatType.none;
    final intervalController = TextEditingController(
      text: (existing?.repeatInterval ?? 1).toString(),
    );

    final defaultWeekday = (selectedDueDate ?? DateTime.now()).weekday;
    final List<int> selectedWeekdays = existing != null &&
            existing.repeatWeekdays.isNotEmpty
        ? List<int>.from(existing.repeatWeekdays)
        : [defaultWeekday];

    _TodoRepeatEndMode endMode = _TodoRepeatEndMode.forever;
    if (existing?.repeatEndDate != null) {
      endMode = _TodoRepeatEndMode.untilDate;
    } else if (existing?.repeatCount != null && existing!.repeatCount! > 0) {
      endMode = _TodoRepeatEndMode.count;
    }

    DateTime selectedEndDate = existing?.repeatEndDate ??
        (selectedDueDate ?? DateTime.now()).add(const Duration(days: 30));
    final countController = TextEditingController(
      text: (existing?.repeatCount ?? 10).toString(),
    );

    // 세부 항목 편집 상태
    final List<TodoSubItem> tempSubItems = existing != null
        ? existing.subItems
            .map(
              (s) => TodoSubItem(
                id: s.id,
                name: s.name,
                isChecked: s.isChecked,
              ),
            )
            .toList()
        : <TodoSubItem>[];
    final subItemInputController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isRepeating = selectedRepeatType != TodoRepeatType.none;
            final refStartDate = selectedDueDate ?? DateTime.now();

            void addSubItem() {
              final text = subItemInputController.text.trim();
              if (text.isEmpty) return;
              HapticFeedback.lightImpact();
              setDialogState(() {
                tempSubItems.add(
                  TodoSubItem(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: text,
                  ),
                );
                subItemInputController.clear();
              });
            }

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
                          labelText: '할 일 제목',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 마감 날짜 및 시간 선택
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                HapticFeedback.selectionClick();
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: selectedDueDate ?? now,
                                  firstDate: DateTime(2020, 1, 1),
                                  lastDate: DateTime(2035, 12, 31),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    selectedDueDate = picked;
                                    if (selectedEndDate.isBefore(picked)) {
                                      selectedEndDate =
                                          picked.add(const Duration(days: 30));
                                    }
                                  });
                                }
                              },
                              icon: const Icon(Icons.event_outlined, size: 16),
                              label: Text(
                                selectedDueDate == null
                                    ? '기한 없음'
                                    : '${selectedDueDate!.year}.${selectedDueDate!.month.toString().padLeft(2, '0')}.${selectedDueDate!.day.toString().padLeft(2, '0')}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (selectedDueDate != null)
                            IconButton(
                              tooltip: '마감일 해제',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setDialogState(() {
                                  selectedDueDate = null;
                                  selectedDueTime = null;
                                });
                              },
                            ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: selectedDueDate == null
                                  ? null
                                  : () async {
                                      HapticFeedback.selectionClick();
                                      TimeOfDay initialTime =
                                          const TimeOfDay(hour: 18, minute: 0);
                                      if (selectedDueTime != null &&
                                          selectedDueTime!.contains(':')) {
                                        final parts =
                                            selectedDueTime!.split(':');
                                        initialTime = TimeOfDay(
                                          hour: int.tryParse(parts[0]) ?? 18,
                                          minute: int.tryParse(parts[1]) ?? 0,
                                        );
                                      }
                                      final picked = await showTimePicker(
                                        context: ctx,
                                        initialTime: initialTime,
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
                                    ? '시간 미지정'
                                    : selectedDueTime!,
                              ),
                            ),
                          ),
                          if (selectedDueTime != null)
                            IconButton(
                              tooltip: '시간 해제',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setDialogState(() {
                                  selectedDueTime = null;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 반복 설정 (일정과 동일한 방식)
                      DropdownButtonFormField<TodoRepeatType>(
                        initialValue: selectedRepeatType,
                        decoration: const InputDecoration(
                          labelText: '반복 설정',
                          prefixIcon: Icon(Icons.repeat),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: TodoRepeatType.values.map((type) {
                          return DropdownMenuItem<TodoRepeatType>(
                            value: type,
                            child: Text(type.optionLabel),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          HapticFeedback.selectionClick();
                          setDialogState(() {
                            selectedRepeatType = val;
                            if (val != TodoRepeatType.none &&
                                selectedDueDate == null) {
                              final now = DateTime.now();
                              selectedDueDate =
                                  DateTime(now.year, now.month, now.day);
                            }
                            if (val == TodoRepeatType.weekly &&
                                selectedWeekdays.isEmpty) {
                              selectedWeekdays.add(
                                (selectedDueDate ?? DateTime.now()).weekday,
                              );
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
                                  TodoRepeatType.weekly) ...[
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
                                      TodoRepeatType.monthly &&
                                  refStartDate.day >= 29) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '※ ${refStartDate.day}일이 없는 달에는 해당 월의 마지막 날로 자동 조정됩니다.',
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
                              SegmentedButton<_TodoRepeatEndMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: _TodoRepeatEndMode.forever,
                                    label: Text(
                                      '계속 반복',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: _TodoRepeatEndMode.count,
                                    label: Text(
                                      '반복 횟수',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: _TodoRepeatEndMode.untilDate,
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
                              if (endMode == _TodoRepeatEndMode.count) ...[
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
                                    const Text('회 완료 후 종료'),
                                  ],
                                ),
                              ] else if (endMode ==
                                  _TodoRepeatEndMode.untilDate) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      initialDate: selectedEndDate
                                              .isBefore(refStartDate)
                                          ? refStartDate
                                          : selectedEndDate,
                                      firstDate: refStartDate,
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

                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // 세부 항목 (하위 체크리스트) 영역
                      const Text(
                        '세부 항목 (선택 사항)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: subItemInputController,
                              decoration: const InputDecoration(
                                hintText: '세부 단계 입력 후 + 버튼',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => addSubItem(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: addSubItem,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      if (tempSubItems.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...List.generate(tempSubItems.length, (sIdx) {
                          final sub = tempSubItems[sIdx];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.subdirectory_arrow_right,
                              size: 18,
                            ),
                            title: Text(sub.name),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setDialogState(() {
                                  tempSubItems.removeAt(sIdx);
                                });
                              },
                            ),
                          );
                        }),
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
                      _deleteTodoWithUndo(existing);
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
                            .clamp(1, 999);
                    final parsedCount = endMode == _TodoRepeatEndMode.count
                        ? (int.tryParse(countController.text.trim()) ?? 1)
                            .clamp(1, 9999)
                        : null;
                    final parsedEndDate =
                        endMode == _TodoRepeatEndMode.untilDate
                            ? selectedEndDate
                            : null;

                    DateTime? finalDueDate = selectedDueDate;
                    if (selectedRepeatType != TodoRepeatType.none &&
                        finalDueDate == null) {
                      final now = DateTime.now();
                      finalDueDate = DateTime(now.year, now.month, now.day);
                    }

                    final finalWeekdays =
                        selectedRepeatType == TodoRepeatType.weekly
                            ? (selectedWeekdays.isEmpty
                                ? [(finalDueDate ?? DateTime.now()).weekday]
                                : List<int>.from(selectedWeekdays))
                            : <int>[];

                    HapticFeedback.mediumImpact();
                    if (existing == null) {
                      final created = TodoItem(
                        id: DateTime.now()
                            .microsecondsSinceEpoch
                            .toString(),
                        title: title,
                        dueDate: finalDueDate,
                        dueTime: selectedDueTime,
                        repeatType: selectedRepeatType,
                        repeatInterval: parsedInterval,
                        repeatWeekdays: finalWeekdays,
                        repeatEndDate: parsedEndDate,
                        repeatCount: parsedCount,
                        anchorDay: finalDueDate?.day,
                        subItems: tempSubItems,
                      );
                      widget.todos.add(created);
                      if (tempSubItems.isNotEmpty) {
                        _expandedSubItemTodoIds.add(created.id);
                      }
                    } else {
                      final dueDateChanged =
                          existing.dueDate?.day != finalDueDate?.day;
                      existing.title = title;
                      existing.dueDate = finalDueDate;
                      existing.dueTime = selectedDueTime;
                      existing.repeatType = selectedRepeatType;
                      existing.repeatInterval = parsedInterval;
                      existing.repeatWeekdays = finalWeekdays;
                      existing.repeatEndDate = parsedEndDate;
                      existing.repeatCount = parsedCount;
                      if (dueDateChanged || existing.anchorDay == null) {
                        existing.anchorDay = finalDueDate?.day;
                      }
                      existing.subItems = tempSubItems;
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

  Widget _buildTodoCard(TodoItem todo, DateTime now) {
    final isOverdue = todo.isOverdueAt(now);
    final hasSubs = todo.hasSubItems;
    final isExpanded = _expandedSubItemTodoIds.contains(todo.id);
    final repeatText = todo.repeatSummaryText;

    final accentColor = todo.isCompleted
        ? Colors.grey
        : (isOverdue ? Colors.redAccent : Colors.teal);

    return Dismissible(
      key: ValueKey('todo_card_${todo.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteTodoWithUndo(todo),
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '삭제',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.delete_outline, color: Colors.white),
          ],
        ),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: accentColor.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              leading: Checkbox(
                value: todo.isCompleted,
                activeColor: Colors.teal,
                onChanged: (val) {
                  final next = val ?? false;
                  if (next) {
                    HapticFeedback.heavyImpact();
                  } else {
                    HapticFeedback.lightImpact();
                  }
                  todo.toggleCompleted(next, DateTime.now());
                  _notifyParent();
                },
              ),
              title: Text(
                todo.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  decoration:
                      todo.isCompleted ? TextDecoration.lineThrough : null,
                  color: todo.isCompleted
                      ? Colors.grey
                      : (isOverdue ? Colors.redAccent : null),
                ),
              ),
              subtitle: (todo.dueTime != null ||
                      repeatText.isNotEmpty ||
                      hasSubs)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (todo.dueTime != null &&
                              todo.dueTime!.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 13,
                                  color: isOverdue && !todo.isCompleted
                                      ? Colors.redAccent
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  todo.dueTime!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isOverdue && !todo.isCompleted
                                        ? Colors.redAccent
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          if (repeatText.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.repeat, size: 13),
                                const SizedBox(width: 3),
                                Text(
                                  repeatText,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          if (hasSubs)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '세부 ${todo.checkedSubItemsCount}/${todo.subItems.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: accentColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : null,
              onTap: () {
                if (hasSubs) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isExpanded) {
                      _expandedSubItemTodoIds.remove(todo.id);
                    } else {
                      _expandedSubItemTodoIds.add(todo.id);
                    }
                  });
                } else {
                  _showTodoDialog(existing: todo);
                }
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasSubs)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: isExpanded ? '세부 항목 접기' : '세부 항목 펼치기',
                      icon: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (isExpanded) {
                            _expandedSubItemTodoIds.remove(todo.id);
                          } else {
                            _expandedSubItemTodoIds.add(todo.id);
                          }
                        });
                      },
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '할 일 수정',
                    icon: const Icon(Icons.edit_outlined, size: 19),
                    onPressed: () => _showTodoDialog(existing: todo),
                  ),
                ],
              ),
            ),
            if (hasSubs && isExpanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 8, bottom: 6),
                child: Column(
                  children: todo.subItems.map((sub) {
                    return CheckboxListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: sub.isChecked,
                      activeColor: Colors.teal,
                      title: Text(
                        sub.name,
                        style: TextStyle(
                          fontSize: 13,
                          decoration: sub.isChecked
                              ? TextDecoration.lineThrough
                              : null,
                          color: sub.isChecked ? Colors.grey : null,
                        ),
                      ),
                      onChanged: (val) {
                        HapticFeedback.lightImpact();
                        sub.isChecked = val ?? false;
                        if (todo.isAllSubItemsChecked && !todo.isCompleted) {
                          HapticFeedback.heavyImpact();
                          todo.toggleCompleted(true, DateTime.now());
                        } else if (!todo.isAllSubItemsChecked &&
                            todo.isCompleted) {
                          todo.toggleCompleted(false, DateTime.now());
                        }
                        _notifyParent();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedInProgressList(
    List<TodoItem> inProgress,
    DateTime now,
  ) {
    final widgets = <Widget>[];
    String? lastHeader;

    for (final todo in inProgress) {
      final header = _formatDateHeader(todo.dueDate);
      if (header != lastHeader) {
        lastHeader = header;
        final isOverdueHeader = header.startsWith('기한 지남');
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Text(
              header,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: isOverdueHeader
                    ? Colors.redAccent
                    : Theme.of(context).colorScheme.primary,
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
    final inProgress = _inProgressTodos;
    final completed = _completedTodos;

    return Scaffold(
      body: Column(
        children: [
          if (widget.showTips)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
              child: const Row(
                children: [
                  Icon(Icons.task_alt, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '팁: 완료된 반복 할 일은 다음 주기 하루 시작 시간에 맞춰 자동으로 다시 진행 중으로 돌아옵니다.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: widget.todos.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.task_alt_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 12),
                        const Text('등록된 할 일이 없습니다.'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _showTodoDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('첫 할 일 추가하기'),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                    children: [
                      // 1. 진행 중 섹션
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isInProgressExpanded = !_isInProgressExpanded;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isInProgressExpanded
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '진행 중 (${inProgress.length})',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isInProgressExpanded) ...[
                        if (inProgress.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                '진행 중인 할 일이 없습니다 🎉',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else
                          ..._buildGroupedInProgressList(inProgress, now),
                      ],

                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 8),

                      // 2. 완료됨 섹션
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isCompletedExpanded = !_isCompletedExpanded;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isCompletedExpanded
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                size: 20,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '완료됨 (${completed.length})',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isCompletedExpanded) ...[
                        if (completed.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: Text(
                                '완료된 할 일이 없습니다.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else
                          ...completed.map((t) => _buildTodoCard(t, now)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTodoDialog(),
        icon: const Icon(Icons.add),
        label: const Text('할 일 추가'),
      ),
    );
  }
}