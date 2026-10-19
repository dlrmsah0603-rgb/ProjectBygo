class Schedule {
  String id;
  DateTime date; // 단일 일정 날짜 또는 반복 일정의 시작일
  String title;
  String time; // 'HH:mm'
  String tag;
  List<int> repeatWeekdays; // 1(월) ~ 7(일)
  DateTime? repeatEndDate; // 반복 종료일
  int? repeatCount; // 총 반복 횟수
  List<String> excludedDates; // 예외 처리된 날짜 키 ('yyyy-MM-dd')
  int? prepMinutesBefore; // 일정 몇 분 전에 준비시간을 시작할지 (null이면 미설정)
  bool isAutoRecord; // 체크리스트 완료 시 자동 등록된 기록 일정 여부

  // 중복 푸시 알림 방지를 위한 런타임 기록 Set ('scheduleId_yyyy-MM-dd_prepMin')
  static final Set<String> notifiedKeys = <String>{};

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
    this.prepMinutesBefore,
    this.isAutoRecord = false,
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

  /// 일정 시간('HH:mm')에서 prepMinutesBefore만큼 뺀 준비시간('HH:mm') 반환
  String? get prepTimeString {
    if (prepMinutesBefore == null) return null;
    final parts = time.split(':');
    final hour = int.tryParse(parts.firstOrNull ?? '9') ?? 9;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    int totalMinutes = (hour * 60 + minute) - prepMinutesBefore!;
    while (totalMinutes < 0) {
      totalMinutes += 24 * 60;
    }
    totalMinutes = totalMinutes % (24 * 60);

    final prepH = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final prepM = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$prepH:$prepM';
  }

  /// 카드 및 다이얼로그에 표시할 준비시간 요약 텍스트
  String? get prepSummaryText {
    final pTime = prepTimeString;
    if (pTime == null || prepMinutesBefore == null) return null;
    if (prepMinutesBefore == 0) {
      return '준비 $pTime (정각)';
    }
    if (prepMinutesBefore! % 60 == 0 && prepMinutesBefore! >= 60) {
      return '준비 $pTime (${prepMinutesBefore! ~/ 60}시간 전)';
    }
    return '준비 $pTime ($prepMinutesBefore분 전)';
  }

  /// 특정 날짜 기준 해당 일정의 시작 시각 DateTime 반환
  DateTime scheduleDateTimeForDay(DateTime day) {
    final parts = time.split(':');
    final hour = int.tryParse(parts.firstOrNull ?? '9') ?? 9;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  /// 특정 날짜 기준 준비시간의 정확한 DateTime 반환
  DateTime? prepDateTimeForDay(DateTime day) {
    if (prepMinutesBefore == null) return null;
    final scheduleDt = scheduleDateTimeForDay(day);
    return scheduleDt.subtract(Duration(minutes: prepMinutesBefore!));
  }

  /// 현재 시각(now)이 [준비시간 <= now < 해당 일정 시간] 구간 내에 있는지 확인
  bool isInPrepWindowAt(DateTime now) {
    if (isAutoRecord || prepMinutesBefore == null || prepMinutesBefore! <= 0) {
      return false;
    }
    final baseDay = DateTime(now.year, now.month, now.day);
    // 자정을 걸치는 준비시간도 정확히 감지하기 위해 어제/오늘/내일 날짜를 모두 확인
    for (int offset = -1; offset <= 1; offset++) {
      final candidateDay = baseDay.add(Duration(days: offset));
      if (!occursOn(candidateDay)) continue;

      final prepDt = prepDateTimeForDay(candidateDay);
      final schedDt = scheduleDateTimeForDay(candidateDay);
      if (prepDt == null) continue;

      if (!now.isBefore(prepDt) && now.isBefore(schedDt)) {
        return true;
      }
    }
    return false;
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
    int? prepMinutesBefore,
    bool clearPrepMinutesBefore = false,
    bool? isAutoRecord,
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
      prepMinutesBefore: clearPrepMinutesBefore
          ? null
          : (prepMinutesBefore ?? this.prepMinutesBefore),
      isAutoRecord: isAutoRecord ?? this.isAutoRecord,
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
      'prepMinutesBefore': prepMinutesBefore,
      'isAutoRecord': isAutoRecord,
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
      prepMinutesBefore: (json['prepMinutesBefore'] as num?)?.toInt(),
      isAutoRecord: (json['isAutoRecord'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => toJson();

  factory Schedule.fromMap(Map<String, dynamic> map) => Schedule.fromJson(map);
}