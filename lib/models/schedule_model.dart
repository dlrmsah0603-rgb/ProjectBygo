class Schedule {
  String id;
  DateTime date; // 단일 일정 날짜 또는 반복 일정의 시작일
  String title;
  String time;
  String tag;
  List<int> repeatWeekdays; // 1(월) ~ 7(일)
  DateTime? repeatEndDate; // 반복 종료일
  int? repeatCount; // 총 반복 횟수
  List<String> excludedDates; // 예외 처리된 날짜 키 ('yyyy-MM-dd')

  Schedule({
    required this.id,
    required this.date,
    required this.title,
    required this.time,
    this.tag = '',
    List<int>? repeatWeekdays,
    this.repeatEndDate,
    this.repeatCount,
    List<String>? excludedDates,
  })  : repeatWeekdays =
            repeatWeekdays != null ? List<int>.from(repeatWeekdays) : [],
        excludedDates =
            excludedDates != null ? List<String>.from(excludedDates) : [];

  bool get isRepeating => repeatWeekdays.isNotEmpty;

  static String dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Schedule copyWith({
    String? id,
    DateTime? date,
    String? title,
    String? time,
    String? tag,
    List<int>? repeatWeekdays,
    DateTime? repeatEndDate,
    bool clearRepeatEndDate = false,
    int? repeatCount,
    bool clearRepeatCount = false,
    List<String>? excludedDates,
  }) {
    return Schedule(
      id: id ?? this.id,
      date: date ?? this.date,
      title: title ?? this.title,
      time: time ?? this.time,
      tag: tag ?? this.tag,
      repeatWeekdays: repeatWeekdays != null
          ? List<int>.from(repeatWeekdays)
          : List<int>.from(this.repeatWeekdays),
      repeatEndDate:
          clearRepeatEndDate ? null : (repeatEndDate ?? this.repeatEndDate),
      repeatCount: clearRepeatCount ? null : (repeatCount ?? this.repeatCount),
      excludedDates: excludedDates != null
          ? List<String>.from(excludedDates)
          : List<String>.from(this.excludedDates),
    );
  }

  bool occursOn(DateTime day) {
    final target = DateTime.utc(day.year, day.month, day.day);
    final start = DateTime.utc(date.year, date.month, date.day);

    if (excludedDates.contains(dateKey(target))) {
      return false;
    }

    if (!isRepeating) {
      return target.year == start.year &&
          target.month == start.month &&
          target.day == start.day;
    }

    if (target.isBefore(start)) {
      return false;
    }

    if (repeatEndDate != null) {
      final end = DateTime.utc(
        repeatEndDate!.year,
        repeatEndDate!.month,
        repeatEndDate!.day,
      );
      if (target.isAfter(end)) {
        return false;
      }
    }

    if (!repeatWeekdays.contains(target.weekday)) {
      return false;
    }

    if (repeatCount != null && repeatCount! > 0) {
      final weekdaySet = repeatWeekdays.toSet();
      final totalDays = target.difference(start).inDays + 1;
      final fullWeeks = totalDays ~/ 7;
      final remainderDays = totalDays % 7;

      int occurrences = fullWeeks * weekdaySet.length;
      for (int i = 0; i < remainderDays; i++) {
        final w = ((start.weekday - 1 + i) % 7) + 1;
        if (weekdaySet.contains(w)) {
          occurrences++;
        }
      }

      if (occurrences > repeatCount!) {
        return false;
      }
    }

    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'title': title,
      'time': time,
      'tag': tag,
      'repeatWeekdays': repeatWeekdays,
      'repeatEndDate': repeatEndDate?.toIso8601String(),
      'repeatCount': repeatCount,
      'excludedDates': excludedDates,
    };
  }

 factory Schedule.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final rawDate = json['date'];
    if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return Schedule(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      date: parsedDate,
      title: (json['title'] as String?) ?? '',
      time: (json['time'] as String?) ?? '09:00',
      tag: (json['tag'] as String?) ?? '',
      repeatWeekdays: (json['repeatWeekdays'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      repeatEndDate: json['repeatEndDate'] != null
          ? DateTime.tryParse(json['repeatEndDate'].toString())
          : null,
      repeatCount: (json['repeatCount'] as num?)?.toInt(),
      excludedDates: (json['excludedDates'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() => toJson();

  factory Schedule.fromMap(Map<String, dynamic> map) => Schedule.fromJson(map);
}