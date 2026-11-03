enum TodoRepeatType {
  none,
  daily,
  weekly,
  monthly,
  lastDayOfMonth,
  yearly,
}

extension TodoRepeatTypeExt on TodoRepeatType {
  String get label {
    switch (this) {
      case TodoRepeatType.none:
        return '반복 안 함';
      case TodoRepeatType.daily:
        return '매일';
      case TodoRepeatType.weekly:
        return '매주';
      case TodoRepeatType.monthly:
        return '매달';
      case TodoRepeatType.lastDayOfMonth:
        return '매달 마지막 날';
      case TodoRepeatType.yearly:
        return '매년';
    }
  }

  String get unitLabel {
    switch (this) {
      case TodoRepeatType.none:
        return '반복 안 함';
      case TodoRepeatType.daily:
        return '일마다';
      case TodoRepeatType.weekly:
        return '주마다';
      case TodoRepeatType.monthly:
        return '개월마다';
      case TodoRepeatType.lastDayOfMonth:
        return '매달 말일마다';
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

  TodoSubItem copyWith({
    String? id,
    String? name,
    bool? isChecked,
  }) {
    return TodoSubItem(
      id: id ?? this.id,
      name: name ?? this.name,
      isChecked: isChecked ?? this.isChecked,
    );
  }

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
  String id;
  String title;
  DateTime? dueDate;
  String? dueTime; // "HH:mm" 형식 (예: "14:30")
  TodoRepeatType repeatType;
  int repeatInterval; // n일/주/개월/년 간격 (기본 1)
  List<int> repeatWeekdays; // 1(월) ~ 7(일)
  DateTime? repeatEndDate; // 반복 종료일
  int? repeatCount; // 총 반복 횟수 제한
  int completedCycles; // 누적 완료 주기 횟수
  int? anchorDay; // 말일 보정용 기준 일자 (1~31)

  bool isCompleted;
  DateTime? completedAt;
  DateTime? nextActivationDate; // 완료 시 계산된 다음 주기 활성화 예정일
  List<TodoSubItem> subItems;
  int? reminderMinutesBefore; // 마감 전 사전 알림 시간(분)

  // --- 구글 태스크 양방향 동기화 필드 ---
  String? googleTaskId;
  DateTime lastEditedTime;
  bool isDeleted;

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
    this.nextActivationDate,
    List<TodoSubItem>? subItems,
    this.reminderMinutesBefore,
    this.googleTaskId,
    DateTime? lastEditedTime,
    this.isDeleted = false,
  })  : repeatInterval = repeatInterval < 1 ? 1 : repeatInterval,
        repeatWeekdays = List<int>.from(repeatWeekdays ?? const []),
        anchorDay = anchorDay ??
            (repeatType == TodoRepeatType.lastDayOfMonth
                ? 31
                : dueDate?.day),
        subItems = subItems ?? [],
        lastEditedTime = lastEditedTime ?? DateTime.now();

  bool get hasReminder =>
      reminderMinutesBefore != null && reminderMinutesBefore! > 0;

  DateTime? get reminderDateTime {
    if (dueDate == null || dueTime == null || !hasReminder) return null;
    final parts = dueTime!.split(':');
    final hh = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
    final mm = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final fullDt =
        DateTime(dueDate!.year, dueDate!.month, dueDate!.day, hh, mm);
    return fullDt.subtract(Duration(minutes: reminderMinutesBefore!));
  }

  String? get reminderSummaryText {
    if (!hasReminder) return null;
    final mins = reminderMinutesBefore!;
    if (mins % 60 == 0) {
      return '${mins ~/ 60}시간 전';
    } else if (mins > 60) {
      return '${mins ~/ 60}시간 ${mins % 60}분 전';
    }
    return '$mins분 전';
  }
  bool get isRepeating => repeatType != TodoRepeatType.none;
  bool get hasSubItems => subItems.isNotEmpty;
  int get checkedSubItemsCount => subItems.where((i) => i.isChecked).length;
  bool get isAllSubItemsChecked =>
      subItems.isNotEmpty && checkedSubItemsCount == subItems.length;

  void markUpdated() {
    lastEditedTime = DateTime.now();
  }

  static int daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  TodoItem copyWith({
    String? id,
    String? title,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? dueTime,
    bool clearDueTime = false,
    TodoRepeatType? repeatType,
    int? repeatInterval,
    List<int>? repeatWeekdays,
    DateTime? repeatEndDate,
    bool clearRepeatEndDate = false,
    int? repeatCount,
    bool clearRepeatCount = false,
    int? completedCycles,
    int? anchorDay,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? nextActivationDate,
    bool clearNextActivationDate = false,
    List<TodoSubItem>? subItems,
    int? reminderMinutesBefore,
    bool clearReminderMinutes = false,
    String? googleTaskId,
    bool clearGoogleTaskId = false,
    DateTime? lastEditedTime,
    bool? isDeleted,
  }) {
    return TodoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
      repeatType: repeatType ?? this.repeatType,
      repeatInterval: repeatInterval ?? this.repeatInterval,
      repeatWeekdays: repeatWeekdays != null
          ? List<int>.from(repeatWeekdays)
          : List<int>.from(this.repeatWeekdays),
      repeatEndDate:
          clearRepeatEndDate ? null : (repeatEndDate ?? this.repeatEndDate),
      repeatCount: clearRepeatCount ? null : (repeatCount ?? this.repeatCount),
      completedCycles: completedCycles ?? this.completedCycles,
      anchorDay: anchorDay ?? this.anchorDay,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
      nextActivationDate: clearNextActivationDate
          ? null
          : (nextActivationDate ?? this.nextActivationDate),
      subItems: subItems ?? this.subItems.map((e) => e.copyWith()).toList(),
      reminderMinutesBefore: clearReminderMinutes ? null : (reminderMinutesBefore ?? this.reminderMinutesBefore),
      googleTaskId:
          clearGoogleTaskId ? null : (googleTaskId ?? this.googleTaskId),
      lastEditedTime: lastEditedTime ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  String get repeatSummaryText {
    if (!isRepeating) return '';
    final n = repeatInterval < 1 ? 1 : repeatInterval;
    final targetDay = anchorDay ?? dueDate?.day ?? 1;
    String base = '';

    switch (repeatType) {
      case TodoRepeatType.none:
        return '';
      case TodoRepeatType.daily:
        base = n == 1 ? '매일' : '$n일마다';
        break;
      case TodoRepeatType.weekly:
        const dayNames = ['', '월', '화', '수', '목', '금', '토', '일'];
        final sorted = List<int>.from(repeatWeekdays)..sort();
        final daysStr = sorted
            .where((d) => d >= 1 && d <= 7)
            .map((d) => dayNames[d])
            .join('·');
        final prefix = n == 1 ? '매주' : '$n주마다';
        base = daysStr.isNotEmpty ? '$prefix ($daysStr)' : prefix;
        break;
      case TodoRepeatType.monthly:
        base = n == 1 ? '매달 $targetDay일' : '$n개월마다 $targetDay일';
        if (targetDay >= 29) base += ' (말일 보정)';
        break;
      case TodoRepeatType.lastDayOfMonth:
        base = n == 1 ? '매달 마지막 날' : '$n개월마다 마지막 날';
        break;
      case TodoRepeatType.yearly:
        final m = dueDate?.month ?? 1;
        base = n == 1 ? '매년 $m/$targetDay' : '$n년마다 $m/$targetDay';
        break;
    }

    if (repeatCount != null && repeatCount! > 0) {
      return '$base · 총 $repeatCount회 중 ${completedCycles + 1}회차';
    } else if (repeatEndDate != null) {
      return '$base · ~${repeatEndDate!.month}/${repeatEndDate!.day}까지';
    }
    return base;
  }

  /// 마감 기한 경과(Overdue) 여부 판별
  bool isOverdueAt(DateTime now) {
    if (isDeleted || isCompleted || dueDate == null) return false;

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

  /// 상위 할 일 완료 체크/해제 토글 (세부 사항은 별개 유지하되 완료 시 다음 주기 예정일 계산)
  void toggleCompleted(bool complete, DateTime now) {
    isCompleted = complete;
    if (complete) {
      completedAt = now;
      if (isRepeating) {
        final baseDate = dueDate ?? DateTime(now.year, now.month, now.day);
        nextActivationDate = _calculateNextCycleDate(baseDate);
      } else {
        nextActivationDate = null;
      }
    } else {
      completedAt = null;
      nextActivationDate = null;
    }
    markUpdated();
  }

  DateTime? _calculateNextCycleDate(DateTime current) {
    if (!isRepeating) return null;
    final n = repeatInterval < 1 ? 1 : repeatInterval;
    final baseDay = repeatType == TodoRepeatType.lastDayOfMonth
        ? 31
        : (anchorDay ?? current.day);

    DateTime nextDate;
    switch (repeatType) {
      case TodoRepeatType.none:
        return null;
      case TodoRepeatType.daily:
        nextDate = DateTime(current.year, current.month, current.day)
            .add(Duration(days: n));
        break;
      case TodoRepeatType.weekly:
        final weekdays =
            (repeatWeekdays.isEmpty ? <int>[current.weekday] : repeatWeekdays)
                .toSet()
                .toList()
              ..sort();
        int? nextWeekdayInSameWeek;
        for (final w in weekdays) {
          if (w > current.weekday) {
            nextWeekdayInSameWeek = w;
            break;
          }
        }
        if (nextWeekdayInSameWeek != null) {
          final diff = nextWeekdayInSameWeek - current.weekday;
          nextDate = DateTime(current.year, current.month, current.day)
              .add(Duration(days: diff));
        } else {
          final currentMonday =
              DateTime(current.year, current.month, current.day)
                  .subtract(Duration(days: current.weekday - 1));
          final nextCycleMonday = currentMonday.add(Duration(days: 7 * n));
          final firstWeekday = weekdays.first;
          nextDate = nextCycleMonday.add(Duration(days: firstWeekday - 1));
        }
        break;
      case TodoRepeatType.monthly:
      case TodoRepeatType.lastDayOfMonth:
        final totalMonths = current.year * 12 + (current.month - 1) + n;
        final targetYear = totalMonths ~/ 12;
        final targetMonth = (totalMonths % 12) + 1;
        final maxDay = daysInMonth(targetYear, targetMonth);
        final clampedDay = baseDay > maxDay ? maxDay : baseDay;
        nextDate = DateTime(targetYear, targetMonth, clampedDay);
        break;
      case TodoRepeatType.yearly:
        final targetYear = current.year + n;
        final targetMonth = current.month;
        final maxDay = daysInMonth(targetYear, targetMonth);
        final clampedDay = baseDay > maxDay ? maxDay : baseDay;
        nextDate = DateTime(targetYear, targetMonth, clampedDay);
        break;
    }

    if (repeatEndDate != null) {
      final endNormalized = DateTime(
        repeatEndDate!.year,
        repeatEndDate!.month,
        repeatEndDate!.day,
      );
      if (nextDate.isAfter(endNormalized)) {
        return null;
      }
    }

    if (repeatCount != null && repeatCount! > 0) {
      if (completedCycles + 1 >= repeatCount!) {
        return null;
      }
    }

    return nextDate;
  }

  /// 완료된 반복 할 일이 다음 주기 활성화 시점(하루 시작 시간 기준)에 도달했는지 판별
  bool shouldReactivateAt(DateTime now, {String dailyResetTime = '00:00'}) {
    if (isDeleted || !isCompleted || !isRepeating) return false;

    final targetDate = nextActivationDate ??
        (dueDate != null ? _calculateNextCycleDate(dueDate!) : null);
    if (targetDate == null) return false;

    final parts = dailyResetTime.split(':');
    final resetHour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
    final resetMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final threshold = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      resetHour,
      resetMinute,
    );

    return !now.isBefore(threshold);
  }

  /// 다음 주기 마감일로 갱신하고 [진행 중] 상태로 복귀
  void reactivateForNextCycle(DateTime now) {
    final targetDate = nextActivationDate ??
        (dueDate != null ? _calculateNextCycleDate(dueDate!) : null);
    if (targetDate == null) return;

    dueDate = targetDate;
    nextActivationDate = null;
    completedCycles += 1;
    isCompleted = false;
    completedAt = null;
    for (final sub in subItems) {
      sub.isChecked = false;
    }
    markUpdated();
  }

  /// 기존 커밋 호환용: 확인과 재활성화를 한 번에 수행하고 변경 여부(bool) 반환
  bool checkAndReactivateIfDue(DateTime now, {String dailyResetTime = '00:00'}) {
    if (shouldReactivateAt(now, dailyResetTime: dailyResetTime)) {
      reactivateForNextCycle(now);
      return true;
    }
    return false;
  }

  // --- 구글 태스크 설명란(Notes) 텍스트 포맷팅 및 역파싱 ---
  String toGoogleTaskNotes() {
    final buffer = StringBuffer();
    if (dueTime != null && dueTime!.trim().isNotEmpty) {
      buffer.writeln('⏰ 시간: ${dueTime!.trim()}');
    }
    if (subItems.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      for (final sub in subItems) {
        buffer.writeln('${sub.isChecked ? "[x]" : "[ ]"} ${sub.name}');
      }
    }
    return buffer.toString().trim();
  }

  void applyFromGoogleTaskNotes(String? notes) {
    if (notes == null || notes.trim().isEmpty) return;
    final lines = notes.split('\n');
    final parsedSubs = <TodoSubItem>[];
    String? parsedTime;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.startsWith('⏰ 시간:')) {
        parsedTime = line.replaceFirst('⏰ 시간:', '').trim();
      } else if (line.startsWith('[x]') || line.startsWith('[X]')) {
        final name = line.substring(3).trim();
        if (name.isNotEmpty) {
          parsedSubs.add(TodoSubItem(
            id: '${DateTime.now().microsecondsSinceEpoch}_${parsedSubs.length}',
            name: name,
            isChecked: true,
          ));
        }
      } else if (line.startsWith('[ ]')) {
        final name = line.substring(3).trim();
        if (name.isNotEmpty) {
          parsedSubs.add(TodoSubItem(
            id: '${DateTime.now().microsecondsSinceEpoch}_${parsedSubs.length}',
            name: name,
            isChecked: false,
          ));
        }
      }
    }

    if (parsedTime != null && parsedTime.isNotEmpty) {
      dueTime = parsedTime;
    }
    if (parsedSubs.isNotEmpty) {
      subItems = parsedSubs;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dueDate': dueDate?.toIso8601String(),
        'dueTime': dueTime,
        'repeatType': repeatType.index,
        'repeatInterval': repeatInterval,
        'repeatWeekdays': repeatWeekdays,
        'repeatEndDate': repeatEndDate?.toIso8601String(),
        'repeatCount': repeatCount,
        'completedCycles': completedCycles,
        'anchorDay': anchorDay,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
        'nextActivationDate': nextActivationDate?.toIso8601String(),
        'subItems': subItems.map((e) => e.toJson()).toList(),
        'reminderMinutesBefore': reminderMinutesBefore,
        'googleTaskId': googleTaskId,
        'lastEditedTime': lastEditedTime.toIso8601String(),
        'isDeleted': isDeleted,
      };

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    final parsedDueDate = json['dueDate'] != null
        ? DateTime.tryParse(json['dueDate'] as String)
        : null;

    TodoRepeatType parsedType = TodoRepeatType.none;
    if (json['repeatType'] is int) {
      final rawIdx = (json['repeatType'] as int)
          .clamp(0, TodoRepeatType.values.length - 1);
      parsedType = TodoRepeatType.values[rawIdx];
    } else if (json['repeatType'] is String) {
      final str = json['repeatType'] as String;
      parsedType = TodoRepeatType.values.firstWhere(
        (e) => e.name == str,
        orElse: () => TodoRepeatType.none,
      );
    }

    return TodoItem(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: (json['title'] as String?) ?? '',
      dueDate: parsedDueDate,
      dueTime: json['dueTime'] as String?,
      repeatType: parsedType,
      repeatInterval: (json['repeatInterval'] as num?)?.toInt() ?? 1,
      repeatWeekdays: ((json['repeatWeekdays'] as List<dynamic>?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      repeatEndDate: json['repeatEndDate'] != null
          ? DateTime.tryParse(json['repeatEndDate'] as String)
          : null,
      repeatCount: (json['repeatCount'] as num?)?.toInt(),
      completedCycles: (json['completedCycles'] as num?)?.toInt() ?? 0,
      anchorDay: (json['anchorDay'] as num?)?.toInt() ?? parsedDueDate?.day,
      isCompleted: (json['isCompleted'] as bool?) ?? false,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      nextActivationDate: json['nextActivationDate'] != null
          ? DateTime.tryParse(json['nextActivationDate'] as String)
          : null,
      reminderMinutesBefore: (json['reminderMinutesBefore'] as num?)?.toInt(),
      subItems: ((json['subItems'] as List<dynamic>?) ?? const [])
          .map((e) => TodoSubItem.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
      googleTaskId: json['googleTaskId'] as String?,
      lastEditedTime: json['lastEditedTime'] != null
          ? (DateTime.tryParse(json['lastEditedTime'] as String) ??
              DateTime.now())
          : DateTime.now(),
      isDeleted: (json['isDeleted'] as bool?) ?? false,
    );
  }
}