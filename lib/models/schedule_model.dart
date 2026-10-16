class Schedule {
  String id;
  String title;
  DateTime dateTime;
  String? tag;
  String? situationId;
  bool isCompleted;
  List<int> repeatDays; // 1(월) ~ 7(일), 비어있으면 단일 일정
  List<String> completedDates; // 반복 일정의 날짜별 완료 기록 (yyyy-MM-dd)

  Schedule({
    required this.id,
    required this.title,
    required this.dateTime,
    this.tag,
    this.situationId,
    this.isCompleted = false,
    List<int>? repeatDays,
    List<String>? completedDates,
  })  : repeatDays = repeatDays ?? [],
        completedDates = completedDates ?? [];

  static String dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  bool occursOn(DateTime day) {
    if (repeatDays.isEmpty) {
      return dateTime.year == day.year &&
          dateTime.month == day.month &&
          dateTime.day == day.day;
    }
    return repeatDays.contains(day.weekday);
  }

  bool isCompletedOn(DateTime day) {
    if (repeatDays.isEmpty) return isCompleted;
    return completedDates.contains(dateKey(day));
  }

  void setCompletedOn(DateTime day, bool completed) {
    if (repeatDays.isEmpty) {
      isCompleted = completed;
    } else {
      final key = dateKey(day);
      if (completed) {
        if (!completedDates.contains(key)) completedDates.add(key);
      } else {
        completedDates.remove(key);
      }
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dateTime': dateTime.toIso8601String(),
        'tag': tag,
        'situationId': situationId,
        'isCompleted': isCompleted,
        'repeatDays': repeatDays,
        'completedDates': completedDates,
      };

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
        id: json['id'] as String,
        title: json['title'] as String,
        dateTime: DateTime.parse(json['dateTime'] as String),
        tag: json['tag'] as String?,
        situationId: json['situationId'] as String?,
        isCompleted: json['isCompleted'] as bool? ?? false,
        repeatDays: (json['repeatDays'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
        completedDates: (json['completedDates'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
      );
}