import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final loaded = await StorageService.loadSituations();
    setState(() {
      _situations = loaded;
      if (_selectedIndex >= _situations.length) {
        _selectedIndex = 0;
      }
    });
  }

  Future<void> _saveAndRefresh() async {
    await StorageService.saveSituations(_situations);
    setState(() {});
  }

  void _showAddSituationDialog() {
    final titleController = TextEditingController();
    final tagController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 외출 상황 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: '상황 이름 (예: 여행, 카공)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tagController,
              decoration: const InputDecoration(
                labelText: '연동할 태그 (예: 여행)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) return;
              final newSituation = Situation(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                title: titleController.text.trim(),
                tag: tagController.text.trim().isEmpty
                    ? titleController.text.trim()
                    : tagController.text.trim(),
                items: [],
              );
              _situations.add(newSituation);
              _selectedIndex = _situations.length - 1;
              _saveAndRefresh();
              Navigator.pop(context);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  void _showItemDialog({PackingItem? existingItem}) {
    if (_situations.isEmpty) return;
    final nameController =
        TextEditingController(text: existingItem?.name ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingItem == null ? '소지품 추가' : '소지품 수정'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '소지품 이름 (예: 충전기, 여권)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = nameController.text.trim();
              if (text.isEmpty) return;

              if (existingItem == null) {
                _situations[_selectedIndex].items.add(
                      PackingItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: text,
                      ),
                    );
              } else {
                existingItem.name = text;
              }
              _saveAndRefresh();
              Navigator.pop(context);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSituation =
        _situations.isNotEmpty ? _situations[_selectedIndex] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('외출 상황별 소지품'),
        actions: [
          if (currentSituation != null)
            TextButton.icon(
              onPressed: () {
                for (var item in currentSituation.items) {
                  item.isChecked = false;
                }
                _saveAndRefresh();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('체크 초기화'),
            ),
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
                ...List.generate(_situations.length, (index) {
                  final sit = _situations[index];
                  final isSelected = index == _selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text('${sit.title} (#${sit.tag})'),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => _selectedIndex = index);
                      },
                    ),
                  );
                }),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('상황 추가'),
                  onPressed: _showAddSituationDialog,
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: currentSituation == null
                ? const Center(child: Text('상단에서 외출 상황을 추가해 보세요!'))
                : currentSituation.items.isEmpty
                    ? const Center(child: Text('우측 하단 + 버튼을 눌러 소지품을 추가하세요.'))
                    : ListView.builder(
                        itemCount: currentSituation.items.length,
                        itemBuilder: (context, idx) {
                          final item = currentSituation.items[idx];
                          return ListTile(
                            leading: Checkbox(
                              value: item.isChecked,
                              onChanged: (val) {
                                item.isChecked = val ?? false;
                                _saveAndRefresh();
                              },
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () =>
                                      _showItemDialog(existingItem: item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showItemDialog(),
        icon: const Icon(Icons.add),
        label: const Text('소지품 추가'),
      ),
    );
  }
}