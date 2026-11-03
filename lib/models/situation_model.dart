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

  ChecklistItem copyWith({
    String? id,
    String? name,
    bool? isChecked,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isChecked: isChecked ?? this.isChecked,
    );
  }

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: (json['name'] as String?) ?? (json['title'] as String?) ?? '',
      isChecked: (json['isChecked'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'title': name,
        'isChecked': isChecked,
      };
}

class Situation {
  String id;
  String name;
  String tag;
  int iconCodePoint;
  int colorValue;
  List<ChecklistItem> items;

  static const List<IconData> availableIcons = [
    Icons.work,
    Icons.fitness_center,
    Icons.flight_takeoff,
    Icons.school,
    Icons.shopping_bag,
    Icons.restaurant,
    Icons.medical_services,
    Icons.pets,
    Icons.music_note,
    Icons.sports_esports,
    Icons.directions_car,
    Icons.home,
    Icons.backpack,
    Icons.beach_access,
    Icons.camera_alt,
    Icons.book,
  ];

  Situation({
    required this.id,
    required this.name,
    String? tag,
    required this.iconCodePoint,
    required this.colorValue,
    List<ChecklistItem>? items,
  })  : tag = (tag != null && tag.trim().isNotEmpty) ? tag.trim() : name.trim(),
        items = items ?? [];

  IconData get iconData {
    for (final icon in availableIcons) {
      if (icon.codePoint == iconCodePoint) {
        return icon;
      }
    }
    return Icons.backpack;
  }

  Color get color => Color(colorValue);

  int get checkedCount => items.where((item) => item.isChecked).length;
  double get progress => items.isEmpty ? 0.0 : checkedCount / items.length;
  bool get isAllChecked => items.isNotEmpty && checkedCount == items.length;

  Situation copyWith({
    String? id,
    String? name,
    String? tag,
    int? iconCodePoint,
    int? colorValue,
    List<ChecklistItem>? items,
  }) {
    final nextName = name ?? this.name;
    return Situation(
      id: id ?? this.id,
      name: nextName,
      tag: tag ?? (name != null ? nextName : this.tag),
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      colorValue: colorValue ?? this.colorValue,
      items: items ?? this.items.map((e) => e.copyWith()).toList(),
    );
  }

  factory Situation.fromJson(Map<String, dynamic> json) {
    final parsedName = (json['name'] as String?) ?? '';
    final parsedTag = (json['tag'] as String?) ?? parsedName;
    return Situation(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: parsedName,
      tag: parsedTag,
      iconCodePoint:
          (json['iconCodePoint'] as int?) ?? Icons.backpack.codePoint,
      colorValue: (json['colorValue'] as int?) ?? Colors.blue.toARGB32(),
      items: ((json['items'] as List<dynamic>?) ?? [])
          .map((item) => ChecklistItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tag': tag.isNotEmpty ? tag : name,
        'iconCodePoint': iconCodePoint,
        'colorValue': colorValue,
        'items': items.map((item) => item.toJson()).toList(),
      };
}