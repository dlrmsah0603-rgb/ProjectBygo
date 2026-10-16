import 'package:flutter/material.dart';
import '../main.dart';
import '../models/situation_model.dart';
import '../services/storage_service.dart';

class SituationScreen extends StatefulWidget {
  const SituationScreen({super.key});

  @override
  State<SituationScreen> createState() => _SituationScreenState();
}

class _SituationScreenState extends State<SituationScreen> {
  List<Situation> _situations = [];
  int _selectedIndex = 0;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final loaded = await StorageService.loadSituations();
    if (!mounted) return;
    setState(() {
      _situations = loaded;
      if (_selectedIndex >= _situations.length) {
        _selectedIndex = 0;
      }
    });
  }

  Future<void> _saveAndRefresh() async {
    await StorageService.saveSituations(_situations);
    if (!mounted) return;
    setState(() {});
  }

  List<Situation> get _filteredSituations {
    if (_searchKeyword.isEmpty) return _situations;
    final keyword = _searchKeyword.toLowerCase();
    return _situations.where((sit) {
      final matchTitle = sit.title.toLowerCase().contains(keyword);
      final matchTag = sit.tag.toLowerCase().contains(keyword);
      final matchItem = sit.items.any((i) => i.name.toLowerCase().contains(keyword));
      return matchTitle || matchTag || matchItem;
    }).toList();
  }

  void _showSituationDialog({Situation? existingSituation}) {
    final titleController = TextEditingController(text: existingSituation?.title ?? '');
    final tagController = TextEditingController(text: existingSituation?.tag ?? '');
    int selectedIconIdx = existingSituation?.iconIndex ?? 0;
    int selectedColorVal = existingSituation?.colorValue ?? Situation.presetColors[0].toARGB32();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingSituation == null ? '새 외출 상황 추가' : '외출 상황 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '상황 이름 (예: 출근, 운동, 여행)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tagController,
                  decoration: const InputDecoration(labelText: '연동할 태그 (예: 출근)', prefixText: '# '),
                ),
                const SizedBox(height: 16),
                const Text('대표 아이콘 선택', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(Situation.presetIcons.length, (idx) {
                    final isSelected = selectedIconIdx == idx;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setDialogState(() => selectedIconIdx = idx),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? Color(selectedColorVal).withValues(alpha: 0.2) : null,
                          border: Border.all(
                            color: isSelected ? Color(selectedColorVal) : Colors.grey.shade400,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Situation.presetIcons[idx], color: isSelected ? Color(selectedColorVal) : Colors.grey.shade700),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                const Text('테마 색상 선택', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: Situation.presetColors.map((color) {
                    final colorVal = color.toARGB32();
                    final isSelected = selectedColorVal == colorVal;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColorVal = colorVal),
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: color,
                        child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                final tag = tagController.text.trim().isEmpty ? title : tagController.text.trim();

                if (existingSituation == null) {
                  final newSituation = Situation(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: title,
                    tag: tag,
                    items: [],
                    iconIndex: selectedIconIdx,
                    colorValue: selectedColorVal,
                  );
                  _situations.add(newSituation);
                  _selectedIndex = _situations.length - 1;
                } else {
                  existingSituation.title = title;
                  existingSituation.tag = tag;
                  existingSituation.iconIndex = selectedIconIdx;
                  existingSituation.colorValue = selectedColorVal;
                }

                Navigator.pop(dialogContext);
                _saveAndRefresh();
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSituation(Situation situation) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('상황 템플릿 삭제'),
        content: Text('\'${situation.title}\' 상황과 포함된 소지품 목록(${situation.items.length}개)을 모두 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              _situations.remove(situation);
              if (_selectedIndex >= _situations.length && _situations.isNotEmpty) {
                _selectedIndex = _situations.length - 1;
              } else if (_situations.isEmpty) {
                _selectedIndex = 0;
              }
              Navigator.pop(dialogContext);
              _saveAndRefresh();
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  void _showItemDialog({PackingItem? existingItem, required Situation targetSituation}) {
    final nameController = TextEditingController(text: existingItem?.name ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existingItem == null ? '소지품 추가' : '소지품 수정'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: '소지품 이름 (예: 충전기, 여권)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('취소')),
          ElevatedButton(
            onPressed: () {
              final text = nameController.text.trim();
              if (text.isEmpty) return;

              if (existingItem == null) {
                targetSituation.items.add(PackingItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: text,
                ));
              } else {
                existingItem.name = text;
              }
              Navigator.pop(dialogContext);
              _saveAndRefresh();
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _handleResetOption(String option, Situation currentSituation) {
    if (option == 'reset_current') {
      for (var item in currentSituation.items) {
        item.isChecked = false;
      }
    } else if (option == 'check_all_current') {
      for (var item in currentSituation.items) {
        item.isChecked = true;
      }
    } else if (option == 'reset_all') {
      for (var sit in _situations) {
        for (var item in sit.items) {
          item.isChecked = false;
        }
      }
    }
    _saveAndRefresh();
  }

  Future<void> _toggleDarkMode() async {
    final isDark = themeNotifier.value == ThemeMode.dark;
    final nextDark = !isDark;
    themeNotifier.value = nextDark ? ThemeMode.dark : ThemeMode.light;
    await StorageService.saveIsDarkMode(nextDark);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSituations;
    if (_selectedIndex >= filtered.length && filtered.isNotEmpty) {
      _selectedIndex = 0;
    }
    final currentSituation = filtered.isNotEmpty ? filtered[_selectedIndex] : null;
    final checkedCount = currentSituation?.items.where((i) => i.isChecked).length ?? 0;
    final totalCount = currentSituation?.items.length ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '상황, 태그 또는 소지품 검색...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(fontSize: 15),
                ),
                onChanged: (val) => setState(() => _searchKeyword = val.trim()),
              )
            : const Text('외출 상황별 소지품'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? '검색 닫기' : '상황 검색',
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
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode_outlined),
              tooltip: '다크 모드 전환',
              onPressed: _toggleDarkMode,
            ),
            if (currentSituation != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.checklist_rtl),
                tooltip: '체크 초기화 옵션',
                onSelected: (opt) => _handleResetOption(opt, currentSituation),
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'reset_current', child: Text('[${currentSituation.title}] 체크 모두 해제')),
                  PopupMenuItem(value: 'check_all_current', child: Text('[${currentSituation.title}] 모두 체크 완료')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'reset_all', child: Text('모든 상황 체크 일괄 초기화')),
                ],
              ),
          ],
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ...List.generate(filtered.length, (index) {
                  final sit = filtered[index];
                  final isSelected = index == _selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      avatar: Icon(sit.icon, size: 18, color: isSelected ? Colors.white : sit.color),
                      label: Text('${sit.title} (#${sit.tag})'),
                      selected: isSelected,
                      selectedColor: sit.color,
                      labelStyle: TextStyle(color: isSelected ? Colors.white : null, fontWeight: isSelected ? FontWeight.bold : null),
                      onSelected: (_) => setState(() => _selectedIndex = index),
                    ),
                  );
                }),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('상황 추가'),
                  onPressed: () => _showSituationDialog(),
                ),
              ],
            ),
          ),
          if (currentSituation != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: currentSituation.color.withValues(alpha: 0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(currentSituation.icon, size: 20, color: currentSituation.color),
                      const SizedBox(width: 8),
                      Text(
                        '챙긴 소지품: $checkedCount / $totalCount 완료',
                        style: TextStyle(fontWeight: FontWeight.bold, color: currentSituation.color),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('상황 수정'),
                        onPressed: () => _showSituationDialog(existingSituation: currentSituation),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        label: const Text('상황 삭제', style: TextStyle(color: Colors.red)),
                        onPressed: () => _confirmDeleteSituation(currentSituation),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: currentSituation == null
                ? const Center(child: Text('등록된 외출 상황이 없습니다.'))
                : currentSituation.items.isEmpty
                    ? const Center(child: Text('우측 하단 + 버튼을 눌러 소지품을 추가하세요.'))
                    : ListView.builder(
                        itemCount: currentSituation.items.length,
                        itemBuilder: (context, idx) {
                          final item = currentSituation.items[idx];
                          return ListTile(
                            leading: Checkbox(
                              activeColor: currentSituation.color,
                              value: item.isChecked,
                              onChanged: (val) {
                                item.isChecked = val ?? false;
                                _saveAndRefresh();
                              },
                            ),
                            title: Text(
                              item.name,
                              style: TextStyle(
                                decoration: item.isChecked ? TextDecoration.lineThrough : null,
                                color: item.isChecked ? Colors.grey : null,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _showItemDialog(existingItem: item, targetSituation: currentSituation),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () {
                                    currentSituation.items.removeAt(idx);
                                    _saveAndRefresh();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: currentSituation == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: currentSituation.color,
              foregroundColor: Colors.white,
              onPressed: () => _showItemDialog(targetSituation: currentSituation),
              icon: const Icon(Icons.add),
              label: const Text('소지품 추가'),
            ),
    );
  }
}