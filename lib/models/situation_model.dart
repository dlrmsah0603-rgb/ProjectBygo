import 'package:flutter/material.dart';

class PackingItem {
  String id;
  String name;
  bool isChecked;

  PackingItem({
    required this.id,
    required this.name,
    this.isChecked = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isChecked': isChecked,
      };

  factory PackingItem.fromJson(Map<String, dynamic> json) => PackingItem(
        id: json['id'] as String,
        name: json['name'] as String,
        isChecked: json['isChecked'] as bool? ?? false,
      );
}

class Situation {
  String id;
  String title;
  String tag;
  List<PackingItem> items;
  int iconIndex;
  int colorValue;

  Situation({
    required this.id,
    required this.title,
    required this.tag,
    required this.items,
    this.iconIndex = 0,
    this.colorValue = 0xFF3F51B5,
  });

  static const List<IconData> presetIcons = [
    Icons.backpack_outlined,
    Icons.work_outline,
    Icons.fitness_center,
    Icons.flight_takeoff,
    Icons.menu_book_outlined,
    Icons.local_cafe_outlined,
    Icons.shopping_bag_outlined,
  ];

  static const List<Color> presetColors = [
    Color(0xFF3F51B5), // Indigo
    Color(0xFF1E88E5), // Blue
    Color(0xFF43A047), // Green
    Color(0xFFFB8C00), // Orange
    Color(0xFFE53935), // Red
    Color(0xFF8E24AA), // Purple
    Color(0xFF00897B), // Teal
  ];

  IconData get icon =>
      presetIcons[iconIndex.clamp(0, presetIcons.length - 1)];

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'tag': tag,
        'items': items.map((e) => e.toJson()).toList(),
        'iconIndex': iconIndex,
        'colorValue': colorValue,
      };

  factory Situation.fromJson(Map<String, dynamic> json) => Situation(
        id: json['id'] as String,
        title: json['title'] as String,
        tag: json['tag'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => PackingItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        iconIndex: json['iconIndex'] as int? ?? 0,
        colorValue: json['colorValue'] as int? ?? 0xFF3F51B5,
      );
}