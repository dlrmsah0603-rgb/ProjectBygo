enum TodoRepeatType {
  none,
  daily,
  weekly,
  monthly,
  monthlyLastDay,
  yearly,
}

extension TodoRepeatTypeExtension on TodoRepeatType {
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
      case TodoRepeatType.monthlyLastDay:
        return '매달 마지막 날';
      case TodoRepeatType.yearly:
        return '매년';
    }
  }
}

class TodoSubItem {
  String id;
  String title;
  bool isChecked;

  TodoSubItem({
    required this.id,
    required this.title,
    this.isChecked = false,
  });

  TodoSubItem copyWith({
    String? id,
    String? title,
    bool? isChecked,
  }) {
    return TodoSubItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isChecked: isChecked ?? this.isChecked,
    );
  }

  factory TodoSubItem.fromJson(Map<String, dynamic> json) {
    return TodoSubItem(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: (json['title'] as String?) ?? (json['name'] as String?) ?? '',
      isChecked: (json['isChecked'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isChecked': isChecked,
    };
  }
}

class TodoItem {
  String id;
  String title;
  DateTime? dueDate; // null이면 '기한 없음' (연, 월, 일만 사용)
  String? dueTime; // 'HH:mm' 형식, null이면 날짜만 지정(시간 없음)
  TodoRepeatType repeatType;
  List<TodoSubItem> subItems;
  bool isCompleted;
  DateTime? completedAt;
  DateTime? nextActivationDate; // 반복 할 일 완료 시 다음 주기에 진행 중으로 돌아올 날짜

  TodoItem({
    required this.id,
    required this.title,
    this.dueDate,
    this.dueTime,
    this.repeatType = TodoRepeatType.none,
    List<TodoSubItem>? subItems,
    this.isCompleted = false,
    this.completedAt,
    this.nextActivationDate,
  }) : subItems = subItems != null ? List<TodoSubItem>.from(subItems) : [];

  bool get isRepeating => repeatType != TodoRepeatType.none;

  /// 마감 기한이 지났는지 여부 (진행 중인 할 일만 해당)
  bool isOverdueAt(DateTime now) {
    if (isCompleted || dueDate == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    final dDate = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);

    if (dueTime == null || dueTime!.trim().isEmpty) {
      return dDate.isBefore(today);
    }

    final parts = dueTime!.split(':');
    final h = int.tryParse(parts.firstOrNull ?? '23') ?? 23;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '59') ?? 59;
    final exactDue = DateTime(dDate.year, dDate.month, dDate.day, h, m);
    return now.isAfter(exactDue);
  }

  /// 특정 날짜(base) 기준으로 다음 반복 주기의 마감 날짜를 계산
  DateTime calculateNextCycleDate(DateTime base) {
    final d = DateTime(base.year, base.month, base.day);
    switch (repeatType) {
      case TodoRepeatType.none:
        return d;
      case TodoRepeatType.daily:
        return d.add(const Duration(days: 1));
      case TodoRepeatType.weekly:
        return d.add(const Duration(days: 7));
      case TodoRepeatType.monthly:
        final nextMonth = d.month == 12 ? 1 : d.month + 1;
        final nextYear = d.month == 12 ? d.year + 1 : d.year;
        final maxDays = DateTime(nextYear, nextMonth + 1, 0).day;
        final targetDay = d.day > maxDays ? maxDays : d.day;
        return DateTime(nextYear, nextMonth, targetDay);
      case TodoRepeatType.monthlyLastDay:
        final nextMonth = d.month == 12 ? 1 : d.month + 1;
        final nextYear = d.month == 12 ? d.year + 1 : d.year;
        final lastDay = DateTime(nextYear, nextMonth + 1, 0).day;
        return DateTime(nextYear, nextMonth, lastDay);
      case TodoRepeatType.yearly:
        final nextYear = d.year + 1;
        final maxDays = DateTime(nextYear, d.month + 1, 0).day;
        final targetDay = d.day > maxDays ? maxDays : d.day;
        return DateTime(nextYear, d.month, targetDay);
    }
  }

  /// 할 일 체크/해제 토글 시 상태 및 반복 재활성화 예정일(nextActivationDate) 처리
  void toggleCompleted(bool completed, DateTime now) {
    isCompleted = completed;
    if (completed) {
      completedAt = now;
      if (isRepeating) {
        final today = DateTime(now.year, now.month, now.day);
        final base = dueDate != null
            ? DateTime(dueDate!.year, dueDate!.month, dueDate!.day)
            : today;
        DateTime nextDate = calculateNextCycleDate(base);
        while (!nextDate.isAfter(today)) {
          nextDate = calculateNextCycleDate(nextDate);
        }
        nextActivationDate = nextDate;
      } else {
        nextActivationDate = null;
      }
    } else {
      completedAt = null;
      nextActivationDate = null;
    }
  }

  /// 완료된 반복 할 일이 다음 주기 날짜의 '하루 시작 시간(dailyResetTime)'에 도달했는지 확인
  bool shouldReactivateAt(DateTime now, {String dailyResetTime = '00:00'}) {
    if (!isCompleted || !isRepeating || nextActivationDate == null) {
      return false;
    }
    final parts = dailyResetTime.split(':');
    final resetHour =
        (int.tryParse(parts.firstOrNull ?? '0') ?? 0).clamp(0, 23);
    final resetMinute =
        (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0).clamp(0, 59);

    final targetDateTime = DateTime(
      nextActivationDate!.year,
      nextActivationDate!.month,
      nextActivationDate!.day,
      resetHour,
      resetMinute,
    );

    return !now.isBefore(targetDateTime);
  }

  /// 다음 주기로 업데이트하고 다시 [진행 중] 상태로 되돌리기
  void reactivateForNextCycle(DateTime now) {
    if (nextActivationDate == null) return;

    isCompleted = false;
    completedAt = null;
    if (dueDate != null) {
      dueDate = DateTime(
        nextActivationDate!.year,
        nextActivationDate!.month,
        nextActivationDate!.day,
      );
    }
    nextActivationDate = null;

    for (final sub in subItems) {
      sub.isChecked = false;
    }
  }

  /// 기존 호출부와도 호환되는 헬퍼 메서드
  bool checkAndReactivateIfDue(
    DateTime now, {
    String dailyResetTime = '00:00',
  }) {
    if (shouldReactivateAt(now, dailyResetTime: dailyResetTime)) {
      reactivateForNextCycle(now);
      return true;
    }
    return false;
  }

  TodoItem copyWith({
    String? id,
    String? title,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? dueTime,
    bool clearDueTime = false,
    TodoRepeatType? repeatType,
    List<TodoSubItem>? subItems,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? nextActivationDate,
    bool clearNextActivationDate = false,
  }) {
    return TodoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
      repeatType: repeatType ?? this.repeatType,
      subItems: subItems != null
          ? subItems.map((e) => e.copyWith()).toList()
          : this.subItems.map((e) => e.copyWith()).toList(),
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
      nextActivationDate: clearNextActivationDate
          ? null
          : (nextActivationDate ?? this.nextActivationDate),
    );
  }

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    final repeatStr = (json['repeatType'] as String?) ?? 'none';
    final parsedRepeat = TodoRepeatType.values.firstWhere(
      (e) => e.name == repeatStr,
      orElse: () => TodoRepeatType.none,
    );

    final rawSubs = (json['subItems'] as List<dynamic>?) ?? [];
    final parsedSubs = rawSubs
        .map((e) => TodoSubItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return TodoItem(
      id: (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: (json['title'] as String?) ?? '',
      dueDate: json['dueDate'] != null
          ? DateTime.tryParse(json['dueDate'].toString())
          : null,
      dueTime: json['dueTime'] as String?,
      repeatType: parsedRepeat,
      subItems: parsedSubs,
      isCompleted: (json['isCompleted'] as bool?) ?? false,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
      nextActivationDate: json['nextActivationDate'] != null
          ? DateTime.tryParse(json['nextActivationDate'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'dueDate': dueDate?.toIso8601String(),
      'dueTime': dueTime,
      'repeatType': repeatType.name,
      'subItems': subItems.map((e) => e.toJson()).toList(),
      'isCompleted': isCompleted,
      'completedAt': completedAt?.toIso8601String(),
      'nextActivationDate': nextActivationDate?.toIso8601String(),
    };
  }
}