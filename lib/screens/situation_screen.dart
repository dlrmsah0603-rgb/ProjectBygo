import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/situation_model.dart';

class SituationScreen extends StatefulWidget {
  final List<Situation> situations;
  final ValueChanged<List<Situation>> onSituationsChanged;
  final bool showTips;

  const SituationScreen({
    super.key,
    required this.situations,
    required this.onSituationsChanged,
    this.showTips = true,
  });

  @override
  State<SituationScreen> createState() => _SituationScreenState();
}

class _SituationScreenState extends State<SituationScreen> {
  String? _selectedSituationId;

  // 다중 선택 및 순서 변경 모드 상태
  bool _isMultiSelectMode = false;
  final Set<String> _multiSelectedIds = {};

  static const List<IconData> _availableIcons = [
    Icons.work,
    Icons.fitness_center,
    Icons.flight_takeoff,
    Icons.school,
    Icons.shopping_bag,
    Icons.coffee,
    Icons.hiking,
    Icons.medical_services,
    Icons.celebration,
    Icons.directions_car,
  ];

  static const List<Color> _availableColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
  ];

  Situation? get _selectedSituation {
    if (_selectedSituationId == null) return null;
    for (final s in widget.situations) {
      if (s.id == _selectedSituationId) return s;
    }
    return null;
  }

  void _notifyParent() {
    setState(() {});
    widget.onSituationsChanged(widget.situations);
  }

  void _exitMultiSelectMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _isMultiSelectMode = false;
      _multiSelectedIds.clear();
    });
  }

  void _deleteSelectedSituations() {
    if (_multiSelectedIds.isEmpty) {
      _exitMultiSelectMode();
      return;
    }

    final backupList = List<Situation>.from(widget.situations);
    final deletedCount = _multiSelectedIds.length;

    HapticFeedback.heavyImpact();
    setState(() {
      widget.situations.removeWhere((s) => _multiSelectedIds.contains(s.id));
      if (_selectedSituationId != null &&
          _multiSelectedIds.contains(_selectedSituationId)) {
        _selectedSituationId = null;
      }
      _multiSelectedIds.clear();
      _isMultiSelectMode = false;
    });
    widget.onSituationsChanged(widget.situations);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$deletedCount개의 외출 상황이 삭제되었습니다.'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '실행 취소',
          onPressed: () {
            HapticFeedback.lightImpact();
            setState(() {
              widget.situations
                ..clear()
                ..addAll(backupList);
            });
            widget.onSituationsChanged(widget.situations);
          },
        ),
      ),
    );
  }

  void _toggleAllItems(Situation situation) {
    final targetState = !situation.isAllChecked;
    if (targetState) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
    for (final item in situation.items) {
      item.isChecked = targetState;
    }
    _notifyParent();
  }

  void _toggleSingleItem(Situation situation, ChecklistItem item) {
    item.isChecked = !item.isChecked;
    if (situation.isAllChecked) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    _notifyParent();
  }

  void _deleteChecklistItem(Situation situation, int index) {
    final removedItem = situation.items.removeAt(index);
    HapticFeedback.mediumImpact();
    _notifyParent();

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("'${removedItem.name}' 소지품이 삭제되었습니다."),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '실행 취소',
          onPressed: () {
            HapticFeedback.lightImpact();
            final insertIndex = index.clamp(0, situation.items.length);
            situation.items.insert(insertIndex, removedItem);
            _notifyParent();
          },
        ),
      ),
    );
  }

  void _showSituationDialog({Situation? existing}) {
    HapticFeedback.selectionClick();
    final nameController = TextEditingController(text: existing?.name ?? '');
    final tagController = TextEditingController(text: existing?.tag ?? '');
    int selectedIconCode = existing?.iconCodePoint ?? Icons.work.codePoint;
    int selectedColorValue =
        existing?.colorValue ?? Colors.blue.toARGB32();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? '새 외출 상황 추가' : '외출 상황 수정'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '상황 이름 (예: 출근, 운동, 여행)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tagController,
                      decoration: const InputDecoration(
                        labelText: '연동 태그 (예: 출근)',
                        prefixText: '#',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '아이콘 선택',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableIcons.map((icon) {
                        final isSelected = icon.codePoint == selectedIconCode;
                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setDialogState(
                              () => selectedIconCode = icon.codePoint,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Color(selectedColorValue)
                                      .withValues(alpha: 0.2)
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? Color(selectedColorValue)
                                    : Colors.grey.shade400,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              icon,
                              color: isSelected
                                  ? Color(selectedColorValue)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '테마 컬러 선택',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _availableColors.map((color) {
                        final colorVal = color.toARGB32();
                        final isSelected = colorVal == selectedColorValue;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setDialogState(() => selectedColorValue = colorVal);
                          },
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: color,
                            child: isSelected
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final tag =
                        tagController.text.trim().replaceAll('#', '');
                    if (name.isEmpty) return;

                    HapticFeedback.mediumImpact();
                    if (existing == null) {
                      final newSituation = Situation(
                        id: DateTime.now()
                            .microsecondsSinceEpoch
                            .toString(),
                        name: name,
                        tag: tag.isEmpty ? name : tag,
                        items: [],
                        iconCodePoint: selectedIconCode,
                        colorValue: selectedColorValue,
                      );
                      widget.situations.add(newSituation);
                      _selectedSituationId = newSituation.id;
                    } else {
                      existing.name = name;
                      existing.tag = tag.isEmpty ? name : tag;
                      existing.iconCodePoint = selectedIconCode;
                      existing.colorValue = selectedColorValue;
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

  void _showItemDialog(Situation situation, {ChecklistItem? existing}) {
    HapticFeedback.selectionClick();
    final controller = TextEditingController(text: existing?.name ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '소지품 추가' : '소지품 이름 수정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '소지품 이름 (예: 지갑, 무선 이어폰, 우산)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            HapticFeedback.lightImpact();
            if (existing == null) {
              situation.items.add(
                ChecklistItem(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  name: text,
                ),
              );
            } else {
              existing.name = text;
            }
            _notifyParent();
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              HapticFeedback.lightImpact();
              if (existing == null) {
                situation.items.add(
                  ChecklistItem(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: text,
                  ),
                );
              } else {
                existing.name = text;
              }
              _notifyParent();
              Navigator.pop(ctx);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Widget _buildSituationChipContent(
    Situation situation, {
    required bool isSelected,
    required bool isMultiSelected,
    bool isFeedback = false,
  }) {
    final isComplete = situation.isAllChecked;
    final baseColor = isComplete ? Colors.green : situation.color;
    final effectiveColor =
        (_isMultiSelectMode && isMultiSelected) ? Colors.redAccent : baseColor;
    final isFilled =
        _isMultiSelectMode ? isMultiSelected : isSelected;

    return Material(
      color: isFilled
          ? effectiveColor
          : effectiveColor.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      elevation: (isFilled || isFeedback) ? 4 : 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isFilled
                  ? effectiveColor
                  : effectiveColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isMultiSelectMode) ...[
                Icon(
                  isMultiSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: isFilled ? Colors.white : effectiveColor,
                ),
                const SizedBox(width: 6),
              ] else ...[
                Icon(
                  isComplete ? Icons.verified : situation.iconData,
                  size: 18,
                  color: isFilled ? Colors.white : effectiveColor,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  situation.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isFilled ? Colors.white : effectiveColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSituationButtons() {
    final allSelected =
        widget.situations.isNotEmpty &&
        _multiSelectedIds.length == widget.situations.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isMultiSelectMode
                      ? '${_multiSelectedIds.length}개 선택됨 · 드래그하여 순서 변경'
                      : '외출 상황 선택 (꾹 눌러 순서 변경·다중 삭제)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _isMultiSelectMode
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                ),
              ),
              if (_isMultiSelectMode) ...[
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (allSelected) {
                        _multiSelectedIds.clear();
                      } else {
                        _multiSelectedIds.addAll(
                          widget.situations.map((s) => s.id),
                        );
                      }
                    });
                  },
                  child: Text(allSelected ? '전체 해제' : '전체 선택'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _exitMultiSelectMode,
                  child: const Text('완료'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: widget.situations.map((situation) {
              final isSelected = situation.id == _selectedSituationId;
              final isMultiSelected = _multiSelectedIds.contains(situation.id);

              return DragTarget<String>(
                key: ValueKey(situation.id),
                onWillAcceptWithDetails: (details) {
                  final draggedId = details.data;
                  if (draggedId == situation.id) return false;

                  final oldIndex = widget.situations
                      .indexWhere((s) => s.id == draggedId);
                  final newIndex = widget.situations
                      .indexWhere((s) => s.id == situation.id);

                  if (oldIndex != -1 &&
                      newIndex != -1 &&
                      oldIndex != newIndex) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      final moved = widget.situations.removeAt(oldIndex);
                      widget.situations.insert(newIndex, moved);
                    });
                  }
                  return true;
                },
                onAcceptWithDetails: (_) {
                  widget.onSituationsChanged(widget.situations);
                },
                builder: (context, candidateData, rejectedData) {
                  return LongPressDraggable<String>(
                    data: situation.id,
                    delay: const Duration(milliseconds: 350),
                    onDragStarted: () {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        if (!_isMultiSelectMode) {
                          _isMultiSelectMode = true;
                          _multiSelectedIds.add(situation.id);
                        }
                      });
                    },
                    onDragEnd: (_) {
                      widget.onSituationsChanged(widget.situations);
                    },
                    feedback: Transform.scale(
                      scale: 1.06,
                      child: _buildSituationChipContent(
                        situation,
                        isSelected: isSelected,
                        isMultiSelected: isMultiSelected,
                        isFeedback: true,
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: _buildSituationChipContent(
                        situation,
                        isSelected: isSelected,
                        isMultiSelected: isMultiSelected,
                      ),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (_isMultiSelectMode) {
                            if (_multiSelectedIds.contains(situation.id)) {
                              _multiSelectedIds.remove(situation.id);
                              if (_multiSelectedIds.isEmpty) {
                                _isMultiSelectMode = false;
                              }
                            } else {
                              _multiSelectedIds.add(situation.id);
                            }
                          } else {
                            if (_selectedSituationId == situation.id) {
                              _selectedSituationId = null;
                            } else {
                              _selectedSituationId = situation.id;
                            }
                          }
                        });
                      },
                      child: _buildSituationChipContent(
                        situation,
                        isSelected: isSelected,
                        isMultiSelected: isMultiSelected,
                      ),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedSituationChecklist(Situation situation) {
    final total = situation.items.length;
    final checked = situation.checkedCount;
    final progress = situation.progress;
    final isComplete = situation.isAllChecked;
    final activeColor = isComplete ? Colors.green : situation.color;

    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        child: Card(
          elevation: isComplete ? 3 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isComplete
                  ? Colors.green.withValues(alpha: 0.7)
                  : situation.color.withValues(alpha: 0.3),
              width: isComplete ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  situation.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                constraints: const BoxConstraints(maxWidth: 90),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      situation.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '#${situation.tag}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: situation.color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            total == 0
                                ? '소지품을 추가해 주세요'
                                : isComplete
                                    ? '준비 완료! 모든 소지품을 챙겼습니다 🎉'
                                    : '$checked / $total개 챙김 (${(progress * 100).round()}%)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isComplete
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isComplete
                                  ? Colors.green
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (total > 0)
                      Tooltip(
                        message: isComplete ? '전체 체크 해제' : '전체 체크 완료',
                        child: TextButton.icon(
                          onPressed: () => _toggleAllItems(situation),
                          icon: Icon(
                            isComplete ? Icons.restart_alt : Icons.done_all,
                            size: 18,
                          ),
                          label: Text(
                            isComplete ? '초기화' : '전체체크',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _showSituationDialog(existing: situation);
                        } else if (value == 'delete') {
                          HapticFeedback.mediumImpact();
                          widget.situations.remove(situation);
                          _selectedSituationId = null;
                          _notifyParent();
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('상황 수정'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('상황 삭제'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (total > 0) ...[
                  const SizedBox(height: 10),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 250),
                    builder: (context, value, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor: Colors.grey.withValues(alpha: 0.2),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(activeColor),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 8),
                if (situation.items.isNotEmpty)
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: situation.items.length,
                    onReorderStart: (_) => HapticFeedback.selectionClick(),
                    onReorderItem: (oldIndex, newIndex) {
                      HapticFeedback.mediumImpact();
                      final moved = situation.items.removeAt(oldIndex);
                      situation.items.insert(newIndex, moved);
                      _notifyParent();
                    },
                    itemBuilder: (context, iIndex) {
                      final item = situation.items[iIndex];
                      return Dismissible(
                        key: ValueKey('${situation.id}_${item.id}'),
                        direction: DismissDirection.horizontal,
                        background: Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                item.isChecked
                                    ? Icons.remove_done
                                    : Icons.check_circle,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                item.isChecked ? '체크 해제' : '챙김 완료!',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        secondaryBackground: Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
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
                              Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                        confirmDismiss: (direction) async {
                          if (direction == DismissDirection.startToEnd) {
                            _toggleSingleItem(situation, item);
                            return false;
                          }
                          return true;
                        },
                        onDismissed: (_) {
                          _deleteChecklistItem(situation, iIndex);
                        },
                        child: ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: Checkbox(
                            value: item.isChecked,
                            activeColor: activeColor,
                            onChanged: (_) =>
                                _toggleSingleItem(situation, item),
                          ),
                          title: Text(
                            item.name,
                            style: TextStyle(
                              decoration: item.isChecked
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: item.isChecked ? Colors.grey : null,
                            ),
                          ),
                          onTap: () => _toggleSingleItem(situation, item),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                ),
                                tooltip: '소지품 수정',
                                onPressed: () => _showItemDialog(
                                  situation,
                                  existing: item,
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: iIndex,
                                child: const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Icon(
                                    Icons.drag_handle,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _showItemDialog(situation),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('소지품 항목 추가'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedSituation = _selectedSituation;

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
                  Icon(Icons.touch_app_outlined, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '팁: 상황 버튼을 꾹 누르면 순서 변경 및 다중 삭제가 가능합니다.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.situations.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.backpack_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    const Text('등록된 외출 상황이 없습니다.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _showSituationDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('첫 외출 상황 만들기'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _buildSituationButtons(),
            const Divider(height: 1),
            if (selectedSituation == null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '위에서 외출 상황 버튼을 선택하면\n소지품 체크리스트가 표시됩니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              _buildSelectedSituationChecklist(selectedSituation),
          ],
        ],
      ),
      floatingActionButton: _isMultiSelectMode
          ? FloatingActionButton.extended(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              onPressed: _deleteSelectedSituations,
              icon: const Icon(Icons.delete_outline),
              label: Text(
                _multiSelectedIds.isEmpty
                    ? '선택 취소'
                    : '${_multiSelectedIds.length}개 상황 삭제',
              ),
            )
          : FloatingActionButton.extended(
              onPressed: () => _showSituationDialog(),
              icon: const Icon(Icons.add),
              label: const Text('새 상황 추가'),
            ),
    );
  }
}