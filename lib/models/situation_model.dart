import 'package:flutter/material.dart';

class ChecklistItem {
  String id;
  String name;
  bool isChecked;

  ChecklistItem({
    required this.id,
    required this.name,
    this.isChecked = false,
  });

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
  // String tag; // 추후 사용 가능성을 위해 주석 보존 (현재는 상황 이름 name으로만 식별)
  List<ChecklistItem> items;
  int iconCodePoint;
  int colorValue;

  Situation({
    required this.id,
    required this.name,
    String tag = '', // 기존 StorageService 기본 프리셋 호출 하위 호환용 (사용하지 않음)
    required this.items,
    this.iconCodePoint = 0xe8f9, // Icons.work
    this.colorValue = 0xFF2196F3, // Colors.blue
  });

  String get title => name;
  set title(String value) => name = value;

  static const List<IconData> availableIcons = [
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

  IconData get iconData {
    return availableIcons.firstWhere(
      (icon) => icon.codePoint == iconCodePoint,
      orElse: () => Icons.work,
    );
  }

  Color get color => Color(colorValue);

  int get checkedCount => items.where((item) => item.isChecked).length;

  double get progress =>
      items.isEmpty ? 0.0 : checkedCount / items.length;

  bool get isAllChecked =>
      items.isNotEmpty && checkedCount == items.length;

  factory Situation.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>?) ?? [];
    return Situation(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: (json['name'] as String?) ?? (json['title'] as String?) ?? '',
      // tag: (json['tag'] as String?) ?? '',
      items: rawItems
          .map(
            (e) => ChecklistItem.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      iconCodePoint: (json['iconCodePoint'] as int?) ?? Icons.work.codePoint,
      colorValue: (json['colorValue'] as int?) ?? Colors.blue.toARGB32(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'title': name,
      // 'tag': tag,
      'items': items.map((e) => e.toJson()).toList(),
      'iconCodePoint': iconCodePoint,
      'colorValue': colorValue,
    };
  }
}