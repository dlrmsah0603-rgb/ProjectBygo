class Schedule {
  String id;
  String title;
  DateTime date;
  String time;
  String tag;
  List<int> repeatDays; // 1(월) ~ 7(일)

  Schedule({
    required this.id,
    String? title,
    String? name,
    required this.date,
    required this.time,
    required this.tag,
    this.repeatDays = const [],
  }) : title = title ?? name ?? '';

  String get name => title;
  set name(String value) => title = value;

  bool occursOn(DateTime targetDate) {
    final isSameDate = date.year == targetDate.year &&
        date.month == targetDate.month &&
        date.day == targetDate.day;
    if (isSameDate) return true;
    if (repeatDays.contains(targetDate.weekday)) return true;
    return false;
  }

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: (json['title'] as String?) ?? (json['name'] as String?) ?? '',
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      time: (json['time'] as String?) ?? '09:00',
      tag: (json['tag'] as String?) ?? '',
      repeatDays: ((json['repeatDays'] as List<dynamic>?) ?? [])
          .map((e) => e as int)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'name': title,
      'date': date.toIso8601String(),
      'time': time,
      'tag': tag,
      'repeatDays': repeatDays,
    };
  }
}