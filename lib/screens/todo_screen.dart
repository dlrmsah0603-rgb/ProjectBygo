import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/todo_model.dart';

class TodoScreen extends StatefulWidget {
  final List<TodoItem> todos;
  final ValueChanged<List<TodoItem>> onTodosChanged;
  final bool showTips;

  const TodoScreen({
    super.key,
    required this.todos,
    required this.onTodosChanged,
    this.showTips = true,
  });

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  // 진행 중은 기본 펼침(true), 완료됨은 기본 접힘(false)
  bool _isInProgressExpanded = true;
  bool _isCompletedExpanded = false;

  static const List<String> _weekdayLabels = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime? d) {
    if (d == null) return 'NO_DEADLINE';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _formatDateHeader(DateTime? d) {
    if (d == null) return '기한 없음';
    final now = DateTime.now();
    final today = _dateOnly(now);
    final target = _dateOnly(d);
    final diff = target.difference(today).inDays;
    final weekday = _weekdayLabels[target.weekday - 1];

    String suffix = '';
    if (diff == 0) {
      suffix = ' · 오늘';
    } else if (diff == 1) {
      suffix = ' · 내일';
    } else if (diff == -1) {
      suffix = ' · 어제';
    }

    if (target.year == today.year) {
      return '${target.month}월 ${target.day}일 ($weekday)$suffix';
    }
    return '${target.year}년 ${target.month}월 ${target.day}일 ($weekday)$suffix';
  }

  /// 마감 기한 순 정렬 (B안: 기한 없음은 맨 아래)
  List<TodoItem> _sortTodos(List<TodoItem> list) {
    final sorted = List<TodoItem>.from(list);
    sorted.sort((a, b) {
      if (a.dueDate == null && b.dueDate == null) {
        return a.title.compareTo(b.title);
      }
      if (a.dueDate == null) return 1; // 기한 없음은 맨 아래
      if (b.dueDate == null) return -1;

      final da = _dateOnly(a.dueDate!);
      final db = _dateOnly(b.dueDate!);
      final dateCmp = da.compareTo(db);
      if (dateCmp != 0) return dateCmp;

      // 같은 날짜 내에서는 시간이 있는 항목이 먼저, 시간 오름차순 정렬
      final ta = a.dueTime;
      final tb = b.dueTime;
      if (ta == null && tb == null) return a.title.compareTo(b.title);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta.compareTo(tb);
    });
    return sorted;
  }

  void _notifyParent() {
    setState(() {});
    widget.onTodosChanged(widget.todos);
  }

  List<TodoItem> _cloneTodosSnapshot() {
    return widget.todos.map((t) => t.copyWith()).toList();
  }

  void _deleteTodoWithUndo(TodoItem todo) {
    final snapshot = _cloneTodosSnapshot();
    HapticFeedback.mediumImpact();
    setState(() {
      widget.todos.removeWhere((t) => t.id == todo.id);
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
            setState(() {
              widget.todos
                ..clear()
                ..addAll(snapshot);
            });
            widget.onTodosChanged(widget.todos);
          },
        ),
      ),
    );
  }

  void _toggleTodoStatus(TodoItem todo, bool? value) {
    final target = value ?? !todo.isCompleted;
    if (target) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {
      todo.toggleCompleted(target, DateTime.now());
    });
    widget.onTodosChanged(widget.todos);
  }

  void _showTodoDialog({TodoItem? existing}) {
    HapticFeedback.selectionClick();
    final titleController = TextEditingController(text: existing?.title ?? '');
    DateTime? selectedDate = existing?.dueDate != null
        ? _dateOnly(existing!.dueDate!)
        : null;
    String? selectedTime = existing?.dueTime;
    TodoRepeatType selectedRepeat =
        existing?.repeatType ?? TodoRepeatType.none;
    final List<TodoSubItem> editingSubItems = existing != null
        ? existing.subItems.map((s) => s.copyWith()).toList()
        : [];
    final subItemController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void addSubItemFromField() {
              final text = subItemController.text.trim();
              if (text.isEmpty) return;
              HapticFeedback.selectionClick();
              setDialogState(() {
                editingSubItems.add(
                  TodoSubItem(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    title: text,
                  ),
                );
                subItemController.clear();
              });
            }

            return AlertDialog(
              title: Text(existing == null ? '할 일 추가' : '할 일 수정'),
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
                          hintText: '예: 공과금 납부, 보고서 제출',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Text(
                            '마감 기한',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (selectedDate != null)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setDialogState(() {
                                  selectedDate = null;
                                  selectedTime = null;
                                });
                              },
                              icon: const Icon(Icons.close, size: 15),
                              label: const Text(
                                '기한 없음으로 변경',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: selectedDate ?? now,
                                  firstDate: DateTime(2020, 1, 1),
                                  lastDate: DateTime(2035, 12, 31),
                                );
                                if (picked != null) {
                                  HapticFeedback.selectionClick();
                                  setDialogState(() {
                                    selectedDate = _dateOnly(picked);
                                  });
                                }
                              },
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(
                                selectedDate == null
                                    ? '기한 없음 (날짜 선택)'
                                    : '${selectedDate!.year}.${selectedDate!.month.toString().padLeft(2, '0')}.${selectedDate!.day.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          if (selectedDate != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final parts = (selectedTime ?? '18:00')
                                      .split(':');
                                  final h =
                                      int.tryParse(parts.firstOrNull ?? '18') ??
                                          18;
                                  final m = int.tryParse(
                                        parts.length > 1 ? parts[1] : '0',
                                      ) ??
                                      0;
                                  final picked = await showTimePicker(
                                    context: ctx,
                                    initialTime: TimeOfDay(hour: h, minute: m),
                                  );
                                  if (picked != null) {
                                    HapticFeedback.selectionClick();
                                    final hh = picked.hour
                                        .toString()
                                        .padLeft(2, '0');
                                    final mm = picked.minute
                                        .toString()
                                        .padLeft(2, '0');
                                    setDialogState(() {
                                      selectedTime = '$hh:$mm';
                                    });
                                  }
                                },
                                icon: const Icon(Icons.access_time, size: 16),
                                label: Text(
                                  selectedTime ?? '시간 지정 안 함',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                            if (selectedTime != null)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: '시간 해제 (날짜만 지정)',
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  setDialogState(() {
                                    selectedTime = null;
                                  });
                                },
                                icon: const Icon(Icons.clear, size: 18),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '반복 설정',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: TodoRepeatType.values.map((repeat) {
                          final isSelected = selectedRepeat == repeat;
                          return ChoiceChip(
                            label: Text(
                              repeat.label,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: isSelected,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              setDialogState(() {
                                selectedRepeat = repeat;
                                // 반복을 설정했는데 마감 날짜가 없으면 오늘 날짜를 기본으로 세팅
                                if (repeat != TodoRepeatType.none &&
                                    selectedDate == null) {
                                  final now = DateTime.now();
                                  if (repeat ==
                                      TodoRepeatType.monthlyLastDay) {
                                    selectedDate = DateTime(
                                      now.year,
                                      now.month + 1,
                                      0,
                                    );
                                  } else {
                                    selectedDate = _dateOnly(now);
                                  }
                                } else if (repeat ==
                                        TodoRepeatType.monthlyLastDay &&
                                    selectedDate != null) {
                                  selectedDate = DateTime(
                                    selectedDate!.year,
                                    selectedDate!.month + 1,
                                    0,
                                  );
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '세부 사항',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: subItemController,
                              decoration: const InputDecoration(
                                hintText: '세부 사항 입력 후 추가 (+)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => addSubItemFromField(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: addSubItemFromField,
                            icon: const Icon(Icons.add),
                            tooltip: '세부 사항 추가',
                          ),
                        ],
                      ),
                      if (editingSubItems.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              editingSubItems.length,
                              (idx) {
                                final sub = editingSubItems[idx];
                                return ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  leading: Checkbox(
                                    value: sub.isChecked,
                                    onChanged: (val) {
                                      setDialogState(() {
                                        sub.isChecked = val ?? false;
                                      });
                                    },
                                  ),
                                  title: Text(
                                    sub.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      decoration: sub.isChecked
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      setDialogState(() {
                                        editingSubItems.removeAt(idx);
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
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

                    // 입력창에 남아있는 세부 사항 텍스트가 있으면 함께 추가
                    if (subItemController.text.trim().isNotEmpty) {
                      editingSubItems.add(
                        TodoSubItem(
                          id: DateTime.now()
                              .microsecondsSinceEpoch
                              .toString(),
                          title: subItemController.text.trim(),
                        ),
                      );
                    }

                    HapticFeedback.mediumImpact();
                    if (existing == null) {
                      // 새 할 일 추가 시 무조건 [진행 중] 란에 추가
                      final created = TodoItem(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        title: title,
                        dueDate: selectedDate,
                        dueTime: selectedDate != null ? selectedTime : null,
                        repeatType: selectedRepeat,
                        subItems: editingSubItems,
                        isCompleted: false,
                      );
                      setState(() {
                        widget.todos.add(created);
                        _isInProgressExpanded = true;
                      });
                    } else {
                      setState(() {
                        existing.title = title;
                        existing.dueDate = selectedDate;
                        existing.dueTime =
                            selectedDate != null ? selectedTime : null;
                        existing.repeatType = selectedRepeat;
                        existing.subItems = editingSubItems;
                      });
                    }
                    widget.onTodosChanged(widget.todos);
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

  /// 마감 기한 그룹별로 묶어서 최상단에 날짜 헤더를 표시하고, 할 일 카드 리스트를 생성
  List<Widget> _buildGroupedTodoWidgets(
    List<TodoItem> sortedTodos, {
    required bool isCompletedSection,
  }) {
    if (sortedTodos.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              isCompletedSection
                  ? '완료된 할 일이 없습니다.'
                  : '진행 중인 할 일이 없습니다. 아래 [할 일 추가] 버튼으로 새 할 일을 등록해 보세요!',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ];
    }

    final now = DateTime.now();
    final today = _dateOnly(now);
    final List<Widget> widgets = [];
    String? lastKey;

    for (final todo in sortedTodos) {
      final key = _dateKey(todo.dueDate);
      final isGroupOverdue = !isCompletedSection &&
          todo.dueDate != null &&
          _dateOnly(todo.dueDate!).isBefore(today);

      if (key != lastKey) {
        lastKey = key;
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
            child: Row(
              children: [
                Icon(
                  todo.dueDate == null
                      ? Icons.inbox_outlined
                      : (isGroupOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.event_available_outlined),
                  size: 15,
                  color: isGroupOverdue
                      ? Colors.redAccent
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDateHeader(todo.dueDate),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isGroupOverdue
                        ? Colors.redAccent
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (isGroupOverdue) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '기한 지남',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }

      widgets.add(_buildTodoCard(todo, now));
    }

    return widgets;
  }

  Widget _buildTodoCard(TodoItem todo, DateTime now) {
    final isOverdue = todo.isOverdueAt(now);
    final primaryColor = Theme.of(context).colorScheme.primary;
    final accentColor = todo.isCompleted
        ? Colors.grey
        : (isOverdue ? Colors.redAccent : primaryColor);

    final hasSubtitleRow =
        (todo.dueTime != null && todo.dueTime!.trim().isNotEmpty) ||
        todo.isRepeating ||
        (todo.isCompleted && todo.nextActivationDate != null);

    return Dismissible(
      key: ValueKey('todo_${todo.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _deleteTodoWithUndo(todo),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        elevation: todo.isCompleted ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isOverdue
                ? Colors.redAccent.withValues(alpha: 0.75)
                : Colors.grey.withValues(alpha: 0.25),
            width: isOverdue ? 1.5 : 1.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: todo.isCompleted,
                    activeColor: accentColor,
                    onChanged: (val) => _toggleTodoStatus(todo, val),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showTodoDialog(existing: todo),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isOverdue)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.error_outline,
                                      size: 15,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    todo.title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
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
                                ),
                              ],
                            ),
                            if (hasSubtitleRow) ...[
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  // 시간은 할 일 이름 밑에 작게 기입
                                  if (todo.dueTime != null &&
                                      todo.dueTime!.trim().isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 12,
                                          color: isOverdue
                                              ? Colors.redAccent
                                              : Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          todo.dueTime!,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: isOverdue
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isOverdue
                                                ? Colors.redAccent
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (todo.isRepeating)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.repeat,
                                          size: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          todo.repeatType.label,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (todo.isCompleted &&
                                      todo.nextActivationDate != null)
                                    Text(
                                      '(${todo.nextActivationDate!.month}/${todo.nextActivationDate!.day} 자정에 진행 중으로 복귀)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: primaryColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: '할 일 수정',
                    onPressed: () => _showTodoDialog(existing: todo),
                  ),
                ],
              ),
              // 세부 사항 표시 (세부 사항을 모두 체크해도 할 일 자체는 따로 체크해야 함)
              if (todo.subItems.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 36,
                    right: 8,
                    bottom: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: todo.subItems.map((sub) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          sub.isChecked = !sub.isChecked;
                          _notifyParent();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.5),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: sub.isChecked,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (val) {
                                    HapticFeedback.selectionClick();
                                    sub.isChecked = val ?? false;
                                    _notifyParent();
                                  },
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  sub.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    decoration: (sub.isChecked ||
                                            todo.isCompleted)
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: (sub.isChecked || todo.isCompleted)
                                        ? Colors.grey
                                        : null,
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

  Widget _buildSectionHeader({
    required String title,
    required int count,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Color badgeColor,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.selectionClick();
        onToggle();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_right_rounded,
              size: 22,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inProgressList = _sortTodos(
      widget.todos.where((t) => !t.isCompleted).toList(),
    );
    final completedList = _sortTodos(
      widget.todos.where((t) => t.isCompleted).toList(),
    );
    final primaryColor = Theme.of(context).colorScheme.primary;

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
                  Icon(Icons.lightbulb_outline, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '팁: 마감 기한 순으로 자동 정렬되며, 완료된 반복 할 일은 다음 주기 자정에 진행 중으로 자동 복귀합니다.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                // 1. 진행 중 섹션 (기본 펼침)
                _buildSectionHeader(
                  title: '진행 중',
                  count: inProgressList.length,
                  isExpanded: _isInProgressExpanded,
                  badgeColor: primaryColor,
                  onToggle: () {
                    setState(() {
                      _isInProgressExpanded = !_isInProgressExpanded;
                    });
                  },
                ),
                if (_isInProgressExpanded)
                  ..._buildGroupedTodoWidgets(
                    inProgressList,
                    isCompletedSection: false,
                  ),
                const SizedBox(height: 16),
                // 2. 완료됨 섹션 (기본 접힘)
                _buildSectionHeader(
                  title: '완료됨',
                  count: completedList.length,
                  isExpanded: _isCompletedExpanded,
                  badgeColor: Colors.grey,
                  onToggle: () {
                    setState(() {
                      _isCompletedExpanded = !_isCompletedExpanded;
                    });
                  },
                ),
                if (_isCompletedExpanded)
                  ..._buildGroupedTodoWidgets(
                    completedList,
                    isCompletedSection: true,
                  ),
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
  }
}