enum ScheduleRepeatType {
  none,
  daily,
  weekly,
  monthly,
  yearly,
}

extension ScheduleRepeatTypeExt on ScheduleRepeatType {
  String get unitLabel {
    switch (this) {
      case ScheduleRepeatType.none:
        return '반복 안 함';
      case ScheduleRepeatType.daily:
        return '일마다';
      case ScheduleRepeatType.weekly:
        return '주마다';
      case ScheduleRepeatType.monthly:
        return '개월마다';
      case ScheduleRepeatType.yearly:
        return '년마다';
    }
  }

  String get label => unitLabel;
}

class Schedule {
  /// 준비시간 알림 중복 발생 방지용 키 집합 (main.dart 연동)
  static final Set<String> notifiedKeys = <String>{};

  String id;
  DateTime date; // 단일 일정 날짜 또는 반복 일정 시작일
  String title;
  String time; // "HH:mm" 형식 (예: "09:00")
  List<String> tags; // 다중 태그 목록
  String? situationName; // 연결된 단일 외출 상황 이름

  ScheduleRepeatType repeatType;
  int repeatInterval; // n일/주/개월/년 간격 (기본값 1)
  List<int> repeatWeekdays; // 1(월) ~ 7(일)
  DateTime? repeatEndDate; // 반복 종료일
  int? repeatCount; // 총 반복 횟수 제한
  List<String> excludedDates; // 예외(삭제/분리) 처리된 날짜 목록 ('yyyy-MM-dd')

  int? prepMinutesBefore; // 사전 준비시간(분)
  bool isAllDay; // 종일 일정 여부
  bool isAutoRecord; // 체크리스트 100% 완료 시 자동 생성된 기록 일정 여부

  // --- 구글 캘린더 양방향 동기화 필드 ---
  String? googleEventId;
  DateTime lastEditedTime;
  bool isDeleted;

  Schedule({
    required this.id,
    required this.date,
    required this.title,
    required this.time,
    List<String>? tags,
    String? tag,
    this.situationName,
    this.repeatType = ScheduleRepeatType.none,
    int repeatInterval = 1,
    List<int>? repeatWeekdays,
    this.repeatEndDate,
    this.repeatCount,
    List<String>? excludedDates,
    this.prepMinutesBefore,
    this.isAllDay = false,
    this.isAutoRecord = false,
    this.googleEventId,
    DateTime? lastEditedTime,
    this.isDeleted = false,
  })  : tags = tags != null
            ? List<String>.from(tags)
            : (tag != null && tag.trim().isNotEmpty
                ? <String>[tag.trim()]
                : <String>[]),
        repeatInterval = repeatInterval < 1 ? 1 : repeatInterval,
        repeatWeekdays = repeatWeekdays != null
            ? List<int>.from(repeatWeekdays)
            : <int>[],
        excludedDates = excludedDates != null
            ? List<String>.from(excludedDates)
            : <String>[],
        lastEditedTime = lastEditedTime ?? DateTime.now() {
    // 하위 호환: 요일 리스트만 넘어오고 repeatType이 none인 경우 weekly로 자동 보정
    if (repeatType == ScheduleRepeatType.none &&
        this.repeatWeekdays.isNotEmpty) {
      repeatType = ScheduleRepeatType.weekly;
    }
  }

  String get name => title;
  set name(String value) => title = value;

  /// 단일 태그 하위 호환 Getter / Setter
  String get tag => tags.isNotEmpty ? tags.first : (situationName ?? '');
  set tag(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      tags.clear();
    } else if (tags.isEmpty) {
      tags.add(trimmed);
    } else {
      tags[0] = trimmed;
    }
  }

  bool get isRepeating =>
      repeatType != ScheduleRepeatType.none || repeatWeekdays.isNotEmpty;

  bool get hasPrepTime =>
      !isAllDay && prepMinutesBefore != null && prepMinutesBefore! > 0;

  void markUpdated() {
    lastEditedTime = DateTime.now();
  }

  static String dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String formatDateKey(DateTime d) => dateKey(d);

  static int daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  Schedule copyWith({
    String? id,
    DateTime? date,
    String? title,
    String? time,
    List<String>? tags,
    String? tag,
    String? situationName,
    bool clearSituationName = false,
    ScheduleRepeatType? repeatType,
    int? repeatInterval,
    List<int>? repeatWeekdays,
    DateTime? repeatEndDate,
    bool clearRepeatEndDate = false,
    int? repeatCount,
    bool clearRepeatCount = false,
    List<String>? excludedDates,
    int? prepMinutesBefore,
    bool clearPrepMinutes = false,
    bool clearPrepMinutesBefore = false,
    bool? isAllDay,
    bool? isAutoRecord,
    String? googleEventId,
    bool clearGoogleEventId = false,
    DateTime? lastEditedTime,
    bool? isDeleted,
  }) {
    List<String> nextTags;
    if (tags != null) {
      nextTags = List<String>.from(tags);
    } else if (tag != null) {
      nextTags = tag.trim().isEmpty ? <String>[] : <String>[tag.trim()];
    } else {
      nextTags = List<String>.from(this.tags);
    }

    return Schedule(
      id: id ?? this.id,
      date: date ?? this.date,
      title: title ?? this.title,
      time: time ?? this.time,
      tags: nextTags,
      situationName:
          clearSituationName ? null : (situationName ?? this.situationName),
      repeatType: repeatType ?? this.repeatType,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      repeatWeekdays: repeatWeekdays != null
          ? List<int>.from(repeatWeekdays)
          : List<int>.from(this.repeatWeekdays),
      repeatEndDate:
          clearRepeatEndDate ? null : (repeatEndDate ?? this.repeatEndDate),
      repeatCount: clearRepeatCount ? null : (repeatCount ?? this.repeatCount),
      excludedDates: excludedDates != null
          ? List<String>.from(excludedDates)
          : List<String>.from(this.excludedDates),
      prepMinutesBefore: (clearPrepMinutes || clearPrepMinutesBefore)
          ? null
          : (prepMinutesBefore ?? this.prepMinutesBefore),
      isAllDay: isAllDay ?? this.isAllDay,
      isAutoRecord: isAutoRecord ?? this.isAutoRecord,
      googleEventId:
          clearGoogleEventId ? null : (googleEventId ?? this.googleEventId),
      lastEditedTime: lastEditedTime ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  /// 특정 날짜(day)에 이 일정의 예정 시각(DateTime) 반환
  DateTime scheduleDateTimeForDay(DateTime day) {
    final parts = time.split(':');
    final hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 9) : 9;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  DateTime scheduledDateTimeOn(DateTime day) => scheduleDateTimeForDay(day);

  /// 특정 날짜(day)의 준비 시작 시각(DateTime) 반환
  DateTime? prepDateTimeForDay(DateTime day) {
    if (!hasPrepTime) return null;
    return scheduleDateTimeForDay(day)
        .subtract(Duration(minutes: prepMinutesBefore!));
  }

  DateTime? prepStartDateTimeOn(DateTime day) => prepDateTimeForDay(day);

  /// 준비 시작 시각 포맷 문자열 ("HH:mm")
  String? get prepTimeString {
    if (!hasPrepTime) return null;
    final prepDt = prepDateTimeForDay(date);
    if (prepDt == null) return null;
    final hh = prepDt.hour.toString().padLeft(2, '0');
    final mm = prepDt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// 준비시간 요약 문구 (예: "30분 전 (08:30)")
  String? get prepSummaryText {
    if (!hasPrepTime) return null;
    final mins = prepMinutesBefore!;
    final pTime = prepTimeString ?? '';
    if (mins % 60 == 0) {
      return '${mins ~/ 60}시간 전 ($pTime)';
    } else if (mins > 60) {
      return '${mins ~/ 60}시간 ${mins % 60}분 전 ($pTime)';
    }
    return '$mins분 전 ($pTime)';
  }

  /// 반복 설정 요약 문구
  String get repeatSummaryText {
    if (!isRepeating) return '';
    final effectiveType =
        repeatType == ScheduleRepeatType.none && repeatWeekdays.isNotEmpty
            ? ScheduleRepeatType.weekly
            : repeatType;
    final n = repeatInterval < 1 ? 1 : repeatInterval;
    String base = '';

    switch (effectiveType) {
      case ScheduleRepeatType.none:
        return '';
      case ScheduleRepeatType.daily:
        base = n == 1 ? '매일' : '$n일마다';
        break;
      case ScheduleRepeatType.weekly:
        const dayNames = ['', '월', '화', '수', '목', '금', '토', '일'];
        final sorted = List<int>.from(repeatWeekdays)..sort();
        final daysStr = sorted
            .where((d) => d >= 1 && d <= 7)
            .map((d) => dayNames[d])
            .join('·');
        final prefix = n == 1 ? '매주' : '$n주마다';
        base = daysStr.isNotEmpty ? '$prefix ($daysStr)' : prefix;
        break;
      case ScheduleRepeatType.monthly:
        base = n == 1 ? '매달 ${date.day}일' : '$n개월마다 ${date.day}일';
        if (date.day >= 29) base += ' (말일 보정)';
        break;
      case ScheduleRepeatType.yearly:
        base = n == 1
            ? '매년 ${date.month}/${date.day}'
            : '$n년마다 ${date.month}/${date.day}';
        break;
    }

    if (repeatCount != null && repeatCount! > 0) {
      return '$base (총 $repeatCount회)';
    } else if (repeatEndDate != null) {
      return '$base (~${repeatEndDate!.month}/${repeatEndDate!.day}까지)';
    }
    return base;
  }

  /// 현재 시각(now)이 이 일정의 준비시간 구간 [준비시작 ~ 일정정각) 내에 있는지 판별
  bool isInPrepWindowAt(DateTime now) {
    if (isDeleted || isAutoRecord || !hasPrepTime) return false;
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    for (final candidateDay in [today, tomorrow]) {
      if (!occursOn(candidateDay)) continue;
      final prepStart = prepDateTimeForDay(candidateDay);
      final schedTime = scheduleDateTimeForDay(candidateDay);
      if (prepStart != null &&
          !now.isBefore(prepStart) &&
          now.isBefore(schedTime)) {
        return true;
      }
    }
    return false;
  }

  bool _matchesPatternOn(DateTime target, DateTime start) {
    final effectiveType =
        repeatType == ScheduleRepeatType.none && repeatWeekdays.isNotEmpty
            ? ScheduleRepeatType.weekly
            : repeatType;
    final interval = repeatInterval < 1 ? 1 : repeatInterval;

    switch (effectiveType) {
      case ScheduleRepeatType.none:
        return isSameDay(target, start);
      case ScheduleRepeatType.daily:
        final diffDays = target.difference(start).inDays;
        return diffDays >= 0 && diffDays % interval == 0;
      case ScheduleRepeatType.weekly:
        final weekdays =
            repeatWeekdays.isEmpty ? <int>[start.weekday] : repeatWeekdays;
        if (!weekdays.contains(target.weekday)) return false;
        final startMonday =
            start.subtract(Duration(days: start.weekday - 1));
        final targetMonday =
            target.subtract(Duration(days: target.weekday - 1));
        final diffWeeks = targetMonday.difference(startMonday).inDays ~/ 7;
        return diffWeeks >= 0 && diffWeeks % interval == 0;
      case ScheduleRepeatType.monthly:
        final monthDiff =
            (target.year - start.year) * 12 + (target.month - start.month);
        if (monthDiff < 0 || monthDiff % interval != 0) return false;
        final maxDay = daysInMonth(target.year, target.month);
        final expectedDay = start.day > maxDay ? maxDay : start.day;
        return target.day == expectedDay;
      case ScheduleRepeatType.yearly:
        final yearDiff = target.year - start.year;
        if (yearDiff < 0 || yearDiff % interval != 0) return false;
        if (target.month != start.month) return false;
        final maxDay = daysInMonth(target.year, target.month);
        final expectedDay = start.day > maxDay ? maxDay : start.day;
        return target.day == expectedDay;
    }
  }

  int _occurrenceIndexOn(DateTime target, DateTime start) {
    final effectiveType =
        repeatType == ScheduleRepeatType.none && repeatWeekdays.isNotEmpty
            ? ScheduleRepeatType.weekly
            : repeatType;
    final interval = repeatInterval < 1 ? 1 : repeatInterval;

    switch (effectiveType) {
      case ScheduleRepeatType.none:
        return 1;
      case ScheduleRepeatType.daily:
        return (target.difference(start).inDays ~/ interval) + 1;
      case ScheduleRepeatType.weekly:
        final weekdays =
            (repeatWeekdays.isEmpty ? <int>[start.weekday] : repeatWeekdays)
                .toSet()
                .toList()
              ..sort();
        final startMonday =
            start.subtract(Duration(days: start.weekday - 1));
        final targetMonday =
            target.subtract(Duration(days: target.weekday - 1));
        final diffWeeks = targetMonday.difference(startMonday).inDays ~/ 7;
        final cycleIndex = diffWeeks ~/ interval;

        if (cycleIndex == 0) {
          return weekdays
              .where((w) => w >= start.weekday && w <= target.weekday)
              .length;
        }
        final firstWeekCount =
            weekdays.where((w) => w >= start.weekday).length;
        final middleCyclesCount = (cycleIndex - 1) * weekdays.length;
        final targetWeekCount =
            weekdays.where((w) => w <= target.weekday).length;
        return firstWeekCount + middleCyclesCount + targetWeekCount;
      case ScheduleRepeatType.monthly:
        final monthDiff =
            (target.year - start.year) * 12 + (target.month - start.month);
        return (monthDiff ~/ interval) + 1;
      case ScheduleRepeatType.yearly:
        final yearDiff = target.year - start.year;
        return (yearDiff ~/ interval) + 1;
    }
  }

  /// 특정 날짜(day)에 이 일정이 발생하는지 O(1)로 판별
  bool occursOn(DateTime day) {
    if (isDeleted) return false;

    final normalizedDay = DateTime(day.year, day.month, day.day);
    final normalizedStart = DateTime(date.year, date.month, date.day);

    if (excludedDates.contains(dateKey(normalizedDay))) {
      return false;
    }

    if (normalizedDay.isBefore(normalizedStart)) {
      return false;
    }

    if (!isRepeating) {
      return isSameDay(normalizedDay, normalizedStart);
    }

    if (repeatEndDate != null) {
      final normalizedEnd = DateTime(
        repeatEndDate!.year,
        repeatEndDate!.month,
        repeatEndDate!.day,
      );
      if (normalizedDay.isAfter(normalizedEnd)) {
        return false;
      }
    }

    if (!_matchesPatternOn(normalizedDay, normalizedStart)) {
      return false;
    }

    if (repeatCount != null && repeatCount! > 0) {
      final occIndex = _occurrenceIndexOn(normalizedDay, normalizedStart);
      if (occIndex > repeatCount!) {
        return false;
      }
    }

    return true;
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'title': title,
        'name': title,
        'time': time,
        'tags': tags,
        'tag': tag,
        'situationName': situationName,
        'repeatType': repeatType.index,
        'repeatInterval': repeatInterval,
        'repeatWeekdays': repeatWeekdays,
        'repeatEndDate': repeatEndDate?.toIso8601String(),
        'repeatCount': repeatCount,
        'excludedDates': excludedDates,
        'prepMinutesBefore': prepMinutesBefore,
        'isAllDay': isAllDay,
        'isAutoRecord': isAutoRecord,
        'googleEventId': googleEventId,
        'lastEditedTime': lastEditedTime.toIso8601String(),
        'isDeleted': isDeleted,
      };

  factory Schedule.fromJson(Map<String, dynamic> json) {
    final parsedWeekdays = ((json['repeatWeekdays'] as List<dynamic>?) ??
            (json['repeatDays'] as List<dynamic>?) ??
            const [])
        .map((e) => (e as num).toInt())
        .toList();

    ScheduleRepeatType parsedRepeatType = ScheduleRepeatType.none;
    if (json['repeatType'] is int) {
      final idx = (json['repeatType'] as int)
          .clamp(0, ScheduleRepeatType.values.length - 1);
      parsedRepeatType = ScheduleRepeatType.values[idx];
    } else if (json['repeatType'] is String) {
      final str = json['repeatType'] as String;
      parsedRepeatType = ScheduleRepeatType.values.firstWhere(
        (e) => e.name == str,
        orElse: () => ScheduleRepeatType.none,
      );
    } else if (parsedWeekdays.isNotEmpty) {
      parsedRepeatType = ScheduleRepeatType.weekly;
    }

    List<String> parsedTags = <String>[];
    if (json['tags'] is List) {
      parsedTags = (json['tags'] as List<dynamic>)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (json['tag'] is String &&
        (json['tag'] as String).trim().isNotEmpty) {
      parsedTags = <String>[(json['tag'] as String).trim()];
    }

    String? parsedSitName = json['situationName'] as String?;
    if ((parsedSitName == null || parsedSitName.trim().isEmpty) &&
        json['tag'] is String &&
        (json['tag'] as String).trim().isNotEmpty) {
      parsedSitName = (json['tag'] as String).trim();
    }

    return Schedule(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      date: json['date'] != null
          ? (DateTime.tryParse(json['date'] as String) ?? DateTime.now())
          : DateTime.now(),
      title: (json['title'] as String?) ?? (json['name'] as String?) ?? '',
      time: (json['time'] as String?) ?? '09:00',
      tags: parsedTags,
      situationName: parsedSitName,
      repeatType: parsedRepeatType,
      repeatInterval: (json['repeatInterval'] as num?)?.toInt() ?? 1,
      repeatWeekdays: parsedWeekdays,
      repeatEndDate: json['repeatEndDate'] != null
          ? DateTime.tryParse(json['repeatEndDate'] as String)
          : null,
      repeatCount: (json['repeatCount'] as num?)?.toInt(),
      excludedDates: ((json['excludedDates'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      prepMinutesBefore: (json['prepMinutesBefore'] as num?)?.toInt(),
      isAllDay: (json['isAllDay'] as bool?) ?? false,
      isAutoRecord: (json['isAutoRecord'] as bool?) ?? false,
      googleEventId: json['googleEventId'] as String?,
      lastEditedTime: json['lastEditedTime'] != null
          ? (DateTime.tryParse(json['lastEditedTime'] as String) ??
              DateTime.now())
          : DateTime.now(),
      isDeleted: (json['isDeleted'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => toJson();
  factory Schedule.fromMap(Map<String, dynamic> map) => Schedule.fromJson(map);
}