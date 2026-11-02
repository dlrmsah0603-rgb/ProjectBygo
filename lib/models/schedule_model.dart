enum ScheduleRepeatType {
  none,
  daily,
  weekly,
  monthly,
  yearly,
}

extension ScheduleRepeatTypeExtension on ScheduleRepeatType {
  String get optionLabel {
    switch (this) {
      case ScheduleRepeatType.none:
        return '반복 안 함';
      case ScheduleRepeatType.daily:
        return 'n일마다';
      case ScheduleRepeatType.weekly:
        return 'n주마다';
      case ScheduleRepeatType.monthly:
        return 'n개월마다';
      case ScheduleRepeatType.yearly:
        return 'n년마다';
    }
  }

  String get unitLabel {
    switch (this) {
      case ScheduleRepeatType.none:
        return '';
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
}

class Schedule {
  static final Set<String> notifiedKeys = <String>{};

  static const List<String> weekdayLabels = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  String id;
  DateTime date; // 단일 일정 날짜 또는 반복 일정의 시작일
  String title;
  String time; // 'HH:mm'

  List<String> tags; // 다중 태그 목록 (캘린더 필터링용)
  String? situationName; // 연결된 외출 상황 이름 (단일 체크리스트 매핑용, 미선택 시 null)

  ScheduleRepeatType repeatType;
  int repeatInterval; // n (기본값 1)
  List<int> repeatWeekdays; // 1(월) ~ 7(일), weekly일 때 사용
  DateTime? repeatEndDate; // 반복 종료일 (null이면 무기한 또는 횟수 기준)
  int? repeatCount; // 총 반복 횟수 (null이면 무기한 또는 종료일 기준)
  List<String> excludedDates; // 예외(삭제/분리) 처리된 날짜 키 목록 ('yyyy-MM-dd')

  int? prepMinutesBefore; // 준비시간 (일정 몇 분 전, null 또는 0이면 미설정)
  bool isAutoRecord; // 체크리스트 완료 자동 기록용 일정 여부

  Schedule({
    required this.id,
    required this.date,
    required this.title,
    required this.time,
    List<String>? tags,
    String tag = '', // 단일 문자열 입력 하위 호환용
    this.situationName,
    ScheduleRepeatType? repeatType,
    int repeatInterval = 1,
    List<int>? repeatWeekdays,
    this.repeatEndDate,
    this.repeatCount,
    List<String>? excludedDates,
    this.prepMinutesBefore,
    this.isAutoRecord = false,
  })  : tags = tags != null
            ? tags
                .map((e) => e.trim().replaceAll('#', ''))
                .where((e) => e.isNotEmpty)
                .toSet()
                .toList()
            : (tag.trim().replaceAll('#', '').isNotEmpty
                ? [tag.trim().replaceAll('#', '')]
                : <String>[]),
        repeatInterval = repeatInterval < 1 ? 1 : repeatInterval,
        repeatWeekdays =
            repeatWeekdays != null ? List<int>.from(repeatWeekdays) : [],
        excludedDates =
            excludedDates != null ? List<String>.from(excludedDates) : [],
        repeatType = repeatType ??
            ((repeatWeekdays != null && repeatWeekdays.isNotEmpty)
                ? ScheduleRepeatType.weekly
                : ScheduleRepeatType.none);

  /// 하위 호환용 대표 태그 getter/setter
  String get tag => tags.isNotEmpty ? tags.first : '';
  set tag(String value) {
    final clean = value.trim().replaceAll('#', '');
    if (clean.isEmpty) {
      tags = [];
    } else {
      tags = [clean];
    }
  }

  bool get hasSituation =>
      situationName != null && situationName!.trim().isNotEmpty;

  bool get isRepeating => repeatType != ScheduleRepeatType.none;

  static String dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static int _daysInMonth(int year, int month) {
    return DateTime.utc(year, month + 1, 0).day;
  }

  /// 특정 날짜(day)에 이 일정의 시간(HH:mm)을 합친 DateTime 반환
  DateTime scheduleDateTimeForDay(DateTime day) {
    final parts = time.split(':');
    final h = (int.tryParse(parts.firstOrNull ?? '9') ?? 9).clamp(0, 23);
    final m =
        (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0).clamp(0, 59);
    return DateTime(day.year, day.month, day.day, h, m);
  }

  /// 준비시간 시각 문자열 ('HH:mm')
  String? get prepTimeString {
    if (prepMinutesBefore == null || prepMinutesBefore! <= 0) return null;
    final dt = scheduleDateTimeForDay(date)
        .subtract(Duration(minutes: prepMinutesBefore!));
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// 준비시간 요약 텍스트 (예: '30분 전', '1시간 30분 전')
  String? get prepSummaryText {
    if (prepMinutesBefore == null || prepMinutesBefore! <= 0) return null;
    final mins = prepMinutesBefore!;
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0 && m > 0) return '$h시간 $m분 전';
    if (h > 0) return '$h시간 전';
    return '$m분 전';
  }

  /// 현재 시각(now)이 준비시간 ~ 일정 정각 사이 구간인지 판별
  bool isInPrepWindowAt(DateTime now) {
    if (isAutoRecord) return false;
    if (prepMinutesBefore == null || prepMinutesBefore! <= 0) return false;

    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    for (final candidateDay in [today, tomorrow]) {
      if (!occursOn(candidateDay)) continue;
      final schedDt = scheduleDateTimeForDay(candidateDay);
      final prepDt = schedDt.subtract(Duration(minutes: prepMinutesBefore!));
      if (!now.isBefore(prepDt) && now.isBefore(schedDt)) {
        return true;
      }
    }
    return false;
  }

  /// 반복 설정 요약 문자열 (캘린더 일정 카드 표시용)
  String get repeatSummaryText {
    if (!isRepeating) return '';
    final n = repeatInterval;
    String base = '';

    switch (repeatType) {
      case ScheduleRepeatType.none:
        return '';
      case ScheduleRepeatType.daily:
        base = n == 1 ? '매일' : '$n일마다';
        break;
      case ScheduleRepeatType.weekly:
        final days = repeatWeekdays.isEmpty ? [date.weekday] : repeatWeekdays;
        final sorted = List<int>.from(days)..sort();
        final dayStr =
            sorted.map((d) => weekdayLabels[(d - 1).clamp(0, 6)]).join('·');
        base = n == 1 ? '매주 $dayStr' : '$n주마다 ($dayStr)';
        break;
      case ScheduleRepeatType.monthly:
        base = n == 1 ? '매달 ${date.day}일' : '$n개월마다 (${date.day}일)';
        break;
      case ScheduleRepeatType.yearly:
        base = n == 1
            ? '매년 ${date.month}/${date.day}'
            : '$n년마다 (${date.month}/${date.day})';
        break;
    }

    if (repeatEndDate != null) {
      base += ' (~${repeatEndDate!.month}/${repeatEndDate!.day})';
    } else if (repeatCount != null && repeatCount! > 0) {
      base += ' (총 $repeatCount회)';
    }
    return base;
  }

  /// 반복 주기 패턴에 부합하는지 확인
  bool _matchesPattern(DateTime start, DateTime target) {
    final n = repeatInterval < 1 ? 1 : repeatInterval;

    switch (repeatType) {
      case ScheduleRepeatType.none:
        return target.year == start.year &&
            target.month == start.month &&
            target.day == start.day;

      case ScheduleRepeatType.daily:
        final diffDays = target.difference(start).inDays;
        return diffDays >= 0 && diffDays % n == 0;

      case ScheduleRepeatType.weekly:
        final weekdays =
            repeatWeekdays.isEmpty ? [start.weekday] : repeatWeekdays;
        if (!weekdays.contains(target.weekday)) return false;

        final startMonday =
            start.subtract(Duration(days: start.weekday - 1));
        final targetMonday =
            target.subtract(Duration(days: target.weekday - 1));
        final diffWeeks = targetMonday.difference(startMonday).inDays ~/ 7;
        return diffWeeks >= 0 && diffWeeks % n == 0;

      case ScheduleRepeatType.monthly:
        final diffMonths =
            (target.year - start.year) * 12 + (target.month - start.month);
        if (diffMonths < 0 || diffMonths % n != 0) return false;
        final maxDay = _daysInMonth(target.year, target.month);
        final expectedDay = start.day > maxDay ? maxDay : start.day;
        return target.day == expectedDay;

      case ScheduleRepeatType.yearly:
        final diffYears = target.year - start.year;
        if (diffYears < 0 || diffYears % n != 0) return false;
        if (target.month != start.month) return false;
        final maxDay = _daysInMonth(target.year, target.month);
        final expectedDay = start.day > maxDay ? maxDay : start.day;
        return target.day == expectedDay;
    }
  }

  /// 시작일(start)부터 대상 날짜(target)까지 몇 번째 반복 발생인지 계산
  int _countOccurrencesUpTo(DateTime start, DateTime target) {
    final n = repeatInterval < 1 ? 1 : repeatInterval;

    switch (repeatType) {
      case ScheduleRepeatType.none:
        return 1;

      case ScheduleRepeatType.daily:
        final diffDays = target.difference(start).inDays;
        return (diffDays ~/ n) + 1;

      case ScheduleRepeatType.weekly:
        final weekdays =
            (repeatWeekdays.isEmpty ? [start.weekday] : repeatWeekdays)
                .toSet()
                .toList()
              ..sort();
        final startMonday =
            start.subtract(Duration(days: start.weekday - 1));
        final targetMonday =
            target.subtract(Duration(days: target.weekday - 1));
        final totalSelectedWeeks =
            targetMonday.difference(startMonday).inDays ~/ 7;

        int count = 0;
        if (totalSelectedWeeks == 0) {
          for (final w in weekdays) {
            if (w >= start.weekday && w <= target.weekday) {
              count++;
            }
          }
          return count;
        }

        for (final w in weekdays) {
          if (w >= start.weekday) {
            count++;
          }
        }

        final intermediateActiveWeeks = (totalSelectedWeeks - 1) ~/ n;
        if (intermediateActiveWeeks > 0) {
          count += intermediateActiveWeeks * weekdays.length;
        }

        if (totalSelectedWeeks % n == 0) {
          for (final w in weekdays) {
            if (w <= target.weekday) {
              count++;
            }
          }
        }
        return count;

      case ScheduleRepeatType.monthly:
        final diffMonths =
            (target.year - start.year) * 12 + (target.month - start.month);
        return (diffMonths ~/ n) + 1;

      case ScheduleRepeatType.yearly:
        final diffYears = target.year - start.year;
        return (diffYears ~/ n) + 1;
    }
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

    if (!_matchesPattern(start, target)) {
      return false;
    }

    if (repeatCount != null && repeatCount! > 0) {
      final occurrences = _countOccurrencesUpTo(start, target);
      if (occurrences > repeatCount!) {
        return false;
      }
    }

    return true;
  }

  Schedule copyWith({
    String? id,
    DateTime? date,
    String? title,
    String? time,
    List<String>? tags,
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
    bool clearPrepMinutesBefore = false,
    bool? isAutoRecord,
  }) {
    return Schedule(
      id: id ?? this.id,
      date: date ?? this.date,
      title: title ?? this.title,
      time: time ?? this.time,
      tags: tags != null ? List<String>.from(tags) : List<String>.from(this.tags),
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
      prepMinutesBefore: clearPrepMinutesBefore
          ? null
          : (prepMinutesBefore ?? this.prepMinutesBefore),
      isAutoRecord: isAutoRecord ?? this.isAutoRecord,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'title': title,
      'time': time,
      'tags': tags,
      'tag': tag, // 하위 호환 유지
      'situationName': situationName,
      'repeatType': repeatType.name,
      'repeatInterval': repeatInterval,
      'repeatWeekdays': repeatWeekdays,
      'repeatEndDate': repeatEndDate?.toIso8601String(),
      'repeatCount': repeatCount,
      'excludedDates': excludedDates,
      'prepMinutesBefore': prepMinutesBefore,
      'isAutoRecord': isAutoRecord,
    };
  }

  factory Schedule.fromJson(Map<String, dynamic> json) {
    final parsedWeekdays = (json['repeatWeekdays'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        [];

    ScheduleRepeatType parsedRepeatType = ScheduleRepeatType.none;
    final rawRepeatType = json['repeatType'] as String?;
    if (rawRepeatType != null && rawRepeatType.isNotEmpty) {
      parsedRepeatType = ScheduleRepeatType.values.firstWhere(
        (e) => e.name == rawRepeatType,
        orElse: () => parsedWeekdays.isNotEmpty
            ? ScheduleRepeatType.weekly
            : ScheduleRepeatType.none,
      );
    } else if (parsedWeekdays.isNotEmpty) {
      parsedRepeatType = ScheduleRepeatType.weekly;
    }

    final List<String> parsedTags = [];
    if (json['tags'] is List) {
      for (final item in (json['tags'] as List)) {
        final clean = item.toString().trim().replaceAll('#', '');
        if (clean.isNotEmpty && !parsedTags.contains(clean)) {
          parsedTags.add(clean);
        }
      }
    } else if (json['tag'] is String) {
      final clean = (json['tag'] as String).trim().replaceAll('#', '');
      if (clean.isNotEmpty) {
        parsedTags.add(clean);
      }
    }

    final rawSitName = (json['situationName'] as String?)?.trim();

    return Schedule(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      date: json['date'] != null
          ? (DateTime.tryParse(json['date'].toString()) ?? DateTime.now())
          : DateTime.now(),
      title: (json['title'] as String?) ?? '',
      time: (json['time'] as String?) ?? '09:00',
      tags: parsedTags,
      situationName:
          (rawSitName != null && rawSitName.isNotEmpty) ? rawSitName : null,
      repeatType: parsedRepeatType,
      repeatInterval: ((json['repeatInterval'] as num?)?.toInt() ?? 1).clamp(
        1,
        999,
      ),
      repeatWeekdays: parsedWeekdays,
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