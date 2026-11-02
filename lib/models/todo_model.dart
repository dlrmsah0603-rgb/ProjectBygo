enum TodoRepeatType {
  none,
  daily,
  weekly,
  monthly,
  yearly,
}

extension TodoRepeatTypeExt on TodoRepeatType {
  String get optionLabel {
    switch (this) {
      case TodoRepeatType.none:
        return '반복 안 함';
      case TodoRepeatType.daily:
        return 'n일마다';
      case TodoRepeatType.weekly:
        return 'n주마다';
      case TodoRepeatType.monthly:
        return 'n개월마다';
      case TodoRepeatType.yearly:
        return 'n년마다';
    }
  }

  String get unitLabel {
    switch (this) {
      case TodoRepeatType.none:
        return '';
      case TodoRepeatType.daily:
        return '일마다';
      case TodoRepeatType.weekly:
        return '주마다';
      case TodoRepeatType.monthly:
        return '개월마다';
      case TodoRepeatType.yearly:
        return '년마다';
    }
  }
}

class TodoSubItem {
  String id;
  String name;
  bool isChecked;

  TodoSubItem({
    required this.id,
    required this.name,
    this.isChecked = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isChecked': isChecked,
      };

  factory TodoSubItem.fromJson(Map<String, dynamic> json) => TodoSubItem(
        id: (json['id'] as String?) ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: (json['name'] as String?) ?? '',
        isChecked: (json['isChecked'] as bool?) ?? false,
      );
}

class TodoItem {
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
  String title;
  DateTime? dueDate;
  String? dueTime; // "HH:mm" 형식 (예: "14:30")

  TodoRepeatType repeatType;
  int repeatInterval; // n (기본값 1)
  List<int> repeatWeekdays; // 1(월) ~ 7(일), weekly일 때 사용
  DateTime? repeatEndDate; // 반복 종료일 (null이면 무기한 또는 횟수 기준)
  int? repeatCount; // 총 반복 횟수 (null이면 무기한 또는 종료일 기준)
  int completedCycles; // 현재까지 완료한 반복 횟수 누적
  int? anchorDay; // 월/년 반복 시 기준 일자 보존 (예: 31일 말일 보정용)

  bool isCompleted;
  DateTime? completedAt;
  List<TodoSubItem> subItems;

  TodoItem({
    required this.id,
    required this.title,
    this.dueDate,
    this.dueTime,
    this.repeatType = TodoRepeatType.none,
    int repeatInterval = 1,
    List<int>? repeatWeekdays,
    this.repeatEndDate,
    this.repeatCount,
    this.completedCycles = 0,
    int? anchorDay,
    this.isCompleted = false,
    this.completedAt,
    List<TodoSubItem>? subItems,
  })  : repeatInterval = repeatInterval < 1 ? 1 : repeatInterval,
        repeatWeekdays =
            repeatWeekdays != null ? List<int>.from(repeatWeekdays) : [],
        anchorDay = anchorDay ?? dueDate?.day,
        subItems = subItems ?? [];

  bool get isRepeating => repeatType != TodoRepeatType.none;

  bool get hasSubItems => subItems.isNotEmpty;

  int get checkedSubItemsCount => subItems.where((i) => i.isChecked).length;

  bool get isAllSubItemsChecked =>
      subItems.isNotEmpty && checkedSubItemsCount == subItems.length;

  static int _daysInMonth(int year, int month) {
    return DateTime.utc(year, month + 1, 0).day;
  }

  /// 할 일 카드에 표시할 반복 요약 텍스트 (일정과 동일한 포맷)
  String get repeatSummaryText {
    if (!isRepeating) return '';
    final n = repeatInterval < 1 ? 1 : repeatInterval;
    final refDate = dueDate ?? DateTime.now();
    final targetAnchorDay = anchorDay ?? refDate.day;
    String base = '';

    switch (repeatType) {
      case TodoRepeatType.none:
        return '';
      case TodoRepeatType.daily:
        base = n == 1 ? '매일' : '$n일마다';
        break;
      case TodoRepeatType.weekly:
        final days =
            repeatWeekdays.isEmpty ? [refDate.weekday] : repeatWeekdays;
        final sorted = List<int>.from(days)..sort();
        final dayStr =
            sorted.map((d) => weekdayLabels[(d - 1).clamp(0, 6)]).join('·');
        base = n == 1 ? '매주 $dayStr' : '$n주마다 ($dayStr)';
        break;
      case TodoRepeatType.monthly:
        base = n == 1 ? '매달 $targetAnchorDay일' : '$n개월마다 ($targetAnchorDay일)';
        break;
      case TodoRepeatType.yearly:
        base = n == 1
            ? '매년 ${refDate.month}/$targetAnchorDay'
            : '$n년마다 (${refDate.month}/$targetAnchorDay)';
        break;
    }

    if (repeatEndDate != null) {
      base += ' (~${repeatEndDate!.month}/${repeatEndDate!.day})';
    } else if (repeatCount != null && repeatCount! > 0) {
      base += ' (총 $repeatCount회)';
    }
    return base;
  }

  /// 기한 경과 여부 판단
  bool isOverdueAt(DateTime now) {
    if (isCompleted || dueDate == null) return false;

    if (dueTime != null && dueTime!.contains(':')) {
      final parts = dueTime!.split(':');
      final h = int.tryParse(parts[0]) ?? 23;
      final m = int.tryParse(parts[1]) ?? 59;
      final specificTarget =
          DateTime(dueDate!.year, dueDate!.month, dueDate!.day, h, m, 0);
      return now.isAfter(specificTarget);
    }

    final targetDate =
        DateTime(dueDate!.year, dueDate!.month, dueDate!.day, 23, 59, 59);
    return now.isAfter(targetDate);
  }

  /// 완료 상태 토글
  void toggleCompleted(bool complete, DateTime now) {
    if (complete && !isCompleted) {
      completedCycles += 1;
    } else if (!complete && isCompleted && completedCycles > 0) {
      completedCycles -= 1;
    }

    isCompleted = complete;
    if (complete) {
      completedAt = now;
      if (hasSubItems) {
        for (final sub in subItems) {
          sub.isChecked = true;
        }
      }
    } else {
      completedAt = null;
    }
  }

  /// 현재 시각(now) 및 설정된 하루 시작 시간(dailyResetTime) 기준으로 다음 주기에 재활성화할지 판단
  bool shouldReactivateAt(DateTime now, {String dailyResetTime = '00:00'}) {
    if (!isCompleted || !isRepeating || completedAt == null) {
      return false;
    }

    // 1) 반복 횟수 종료 조건 확인
    if (repeatCount != null &&
        repeatCount! > 0 &&
        completedCycles >= repeatCount!) {
      return false;
    }

    final baseDate = dueDate ??
        DateTime(completedAt!.year, completedAt!.month, completedAt!.day);
    final nextCycleDate = _calculateNextCycleDate(baseDate);
    if (nextCycleDate == null) return false;

    // 2) 반복 종료 날짜 조건 확인
    if (repeatEndDate != null) {
      final endOnly = DateTime(
        repeatEndDate!.year,
        repeatEndDate!.month,
        repeatEndDate!.day,
      );
      final nextOnly = DateTime(
        nextCycleDate.year,
        nextCycleDate.month,
        nextCycleDate.day,
      );
      if (nextOnly.isAfter(endOnly)) {
        return false;
      }
    }

    final parts = dailyResetTime.split(':');
    final resetH = (int.tryParse(parts.firstOrNull ?? '0') ?? 0).clamp(0, 23);
    final resetM =
        (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0).clamp(0, 59);

    var threshold = DateTime(
      nextCycleDate.year,
      nextCycleDate.month,
      nextCycleDate.day,
      resetH,
      resetM,
    );

    // 만약 사용자가 미래의 할 일을 미리 체크해 둔 경우, 적어도 완료 시각 이후의 다음 기준 시각에 복귀
    while (!threshold.isAfter(completedAt!)) {
      threshold = threshold.add(const Duration(days: 1));
    }

    return !now.isBefore(threshold);
  }

  /// 다음 주기 마감일로 업데이트하고 미완료 상태로 되돌리기
  void reactivateForNextCycle(DateTime now) {
    final baseDate = dueDate ??
        (completedAt != null
            ? DateTime(completedAt!.year, completedAt!.month, completedAt!.day)
            : DateTime(now.year, now.month, now.day));

    final nextDate = _calculateNextCycleDate(baseDate);
    if (nextDate == null) return;

    if (repeatEndDate != null) {
      final endOnly = DateTime(
        repeatEndDate!.year,
        repeatEndDate!.month,
        repeatEndDate!.day,
      );
      final nextOnly = DateTime(nextDate.year, nextDate.month, nextDate.day);
      if (nextOnly.isAfter(endOnly)) return;
    }

    if (dueDate != null) {
      dueDate = nextDate;
    }
    isCompleted = false;
    completedAt = null;
    if (hasSubItems) {
      for (final sub in subItems) {
        sub.isChecked = false;
      }
    }
  }

  /// 다음 주기 날짜 계산 (n일/주/월/년 간격, 요일 다중 선택, 말일 보정 반영)
  DateTime? _calculateNextCycleDate(DateTime current) {
    final n = repeatInterval < 1 ? 1 : repeatInterval;
    final cleanCurrent = DateTime(current.year, current.month, current.day);
    final targetDay = anchorDay ?? cleanCurrent.day;

    switch (repeatType) {
      case TodoRepeatType.none:
        return null;

      case TodoRepeatType.daily:
        return cleanCurrent.add(Duration(days: n));

      case TodoRepeatType.weekly:
        final days =
            (repeatWeekdays.isEmpty ? [cleanCurrent.weekday] : repeatWeekdays)
                .toSet()
                .toList()
              ..sort();

        // 같은 주 내에 현재 요일보다 뒤에 남은 선택 요일이 있는지 확인
        for (final w in days) {
          if (w > cleanCurrent.weekday) {
            return cleanCurrent.add(Duration(days: w - cleanCurrent.weekday));
          }
        }

        // 없으면 n주 뒤의 첫 번째 선택 요일로 이동
        final currentMonday =
            cleanCurrent.subtract(Duration(days: cleanCurrent.weekday - 1));
        final nextCycleMonday = currentMonday.add(Duration(days: 7 * n));
        return nextCycleMonday.add(Duration(days: days.first - 1));

      case TodoRepeatType.monthly:
        final totalMonths = (cleanCurrent.year * 12 + (cleanCurrent.month - 1)) + n;
        final nextYear = totalMonths ~/ 12;
        final nextMonth = (totalMonths % 12) + 1;
        final maxDay = _daysInMonth(nextYear, nextMonth);
        final clampedDay = targetDay > maxDay ? maxDay : targetDay;
        return DateTime(nextYear, nextMonth, clampedDay);

      case TodoRepeatType.yearly:
        final nextYear = cleanCurrent.year + n;
        final nextMonth = cleanCurrent.month;
        final maxDay = _daysInMonth(nextYear, nextMonth);
        final clampedDay = targetDay > maxDay ? maxDay : targetDay;
        return DateTime(nextYear, nextMonth, clampedDay);
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dueDate': dueDate?.toIso8601String(),
        'dueTime': dueTime,
        'repeatType': repeatType.name,
        'repeatInterval': repeatInterval,
        'repeatWeekdays': repeatWeekdays,
        'repeatEndDate': repeatEndDate?.toIso8601String(),
        'repeatCount': repeatCount,
        'completedCycles': completedCycles,
        'anchorDay': anchorDay,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
        'subItems': subItems.map((e) => e.toJson()).toList(),
      };

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    final parsedDueDate = json['dueDate'] != null
        ? DateTime.tryParse(json['dueDate'].toString())
        : null;

    TodoRepeatType parsedRepeatType = TodoRepeatType.none;
    int? parsedAnchorDay = (json['anchorDay'] as num?)?.toInt();

    final rawRepeat = json['repeatType'];
    if (rawRepeat is String) {
      if (rawRepeat == 'lastDayOfMonth') {
        parsedRepeatType = TodoRepeatType.monthly;
        parsedAnchorDay ??= 31;
      } else {
        parsedRepeatType = TodoRepeatType.values.firstWhere(
          (e) => e.name == rawRepeat,
          orElse: () => TodoRepeatType.none,
        );
      }
    } else if (rawRepeat is num) {
      // 구버전 enum index 호환: 0:none, 1:daily, 2:weekly, 3:monthly, 4:lastDayOfMonth, 5:yearly
      final idx = rawRepeat.toInt();
      switch (idx) {
        case 1:
          parsedRepeatType = TodoRepeatType.daily;
          break;
        case 2:
          parsedRepeatType = TodoRepeatType.weekly;
          break;
        case 3:
          parsedRepeatType = TodoRepeatType.monthly;
          break;
        case 4:
          parsedRepeatType = TodoRepeatType.monthly;
          parsedAnchorDay ??= 31;
          break;
        case 5:
          parsedRepeatType = TodoRepeatType.yearly;
          break;
        default:
          parsedRepeatType = TodoRepeatType.none;
      }
    }

    final parsedWeekdays = (json['repeatWeekdays'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        [];

    return TodoItem(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: (json['title'] as String?) ?? '',
      dueDate: parsedDueDate,
      dueTime: json['dueTime'] as String?,
      repeatType: parsedRepeatType,
      repeatInterval:
          ((json['repeatInterval'] as num?)?.toInt() ?? 1).clamp(1, 999),
      repeatWeekdays: parsedWeekdays,
      repeatEndDate: json['repeatEndDate'] != null
          ? DateTime.tryParse(json['repeatEndDate'].toString())
          : null,
      repeatCount: (json['repeatCount'] as num?)?.toInt(),
      completedCycles:
          ((json['completedCycles'] as num?)?.toInt() ?? 0).clamp(0, 999999),
      anchorDay: parsedAnchorDay ?? parsedDueDate?.day,
      isCompleted: (json['isCompleted'] as bool?) ?? false,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
      subItems: (json['subItems'] as List<dynamic>? ?? [])
          .map(
            (e) => TodoSubItem.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
    );
  }
}