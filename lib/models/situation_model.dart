import 'package:flutter/material.dart';

class ChecklistItem {
  String id;
  String name;
  bool isChecked;

  ChecklistItem({
    required this.id,
    String? name,
    String? title,
    this.isChecked = false,
  }) : name = name ?? title ?? '';

  String get title => name;
  set title(String value) => name = value;

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: (json['name'] as String?) ?? (json['title'] as String?) ?? '',
      isChecked: (json['isChecked'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'title': name,
      'isChecked': isChecked,
    };
  }
}

class Situation {
  String id;
  String name;
  String tag;
  List<ChecklistItem> items;
  int iconCodePoint;
  int colorValue;

  Situation({
    required this.id,
    String? name,
    String? title,
    required this.tag,
    required this.items,
    this.iconCodePoint = 0xe8f9, // Icons.work
    this.colorValue = 0xFF2196F3, // Colors.blue
  }) : name = name ?? title ?? '';

  String get title => name;
  set title(String value) => name = value;

  IconData get iconData =>
      // ignore: non_const_argument_for_const_parameter
      IconData(iconCodePoint, fontFamily: 'MaterialIcons');

  Color get color => Color(colorValue);

  int get checkedCount => items.where((item) => item.isChecked).length;

  double get progress =>
      items.isEmpty ? 0.0 : checkedCount / items.length;

  bool get isAllChecked =>
      items.isNotEmpty && checkedCount == items.length;

  factory Situation.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>?) ?? [];
    final parsedItems = <ChecklistItem>[];

    for (var i = 0; i < rawItems.length; i++) {
      final element = rawItems[i];
      if (element is String) {
        parsedItems.add(
          ChecklistItem(
            id: '${DateTime.now().microsecondsSinceEpoch}_$i',
            name: element,
            isChecked: false,
          ),
        );
      } else if (element is Map<String, dynamic>) {
        parsedItems.add(ChecklistItem.fromJson(element));
      } else if (element is Map) {
        parsedItems.add(
          ChecklistItem.fromJson(Map<String, dynamic>.from(element)),
        );
      }
    }

    return Situation(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: (json['name'] as String?) ?? (json['title'] as String?) ?? '',
      tag: (json['tag'] as String?) ?? '',
      items: parsedItems,
      iconCodePoint: (json['iconCodePoint'] as int?) ?? Icons.work.codePoint,
      colorValue: (json['colorValue'] as int?) ?? Colors.blue.toARGB32(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'title': name,
      'tag': tag,
      'items': items.map((e) => e.toJson()).toList(),
      'iconCodePoint': iconCodePoint,
      'colorValue': colorValue,
    };
  }
}