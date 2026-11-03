import 'package:flutter_test/flutter_test.dart';
import 'package:projectbygo/models/schedule_model.dart';
import 'package:projectbygo/models/todo_model.dart';

void main() {
  group('Notification & Reminder calculations', () {
    test('TodoItem reminder calculation with due time', () {
      final todo = TodoItem(
        id: '1',
        title: '과제 제출',
        dueDate: DateTime(2026, 11, 4),
        dueTime: '15:00',
        reminderMinutesBefore: 30,
      );

      expect(todo.hasReminder, isTrue);
      expect(todo.reminderSummaryText, '30분 전');
      expect(todo.reminderDateTime, DateTime(2026, 11, 4, 14, 30));
    });

    test('TodoItem without reminder or dueTime returns null reminderDateTime', () {
      final todoNoTime = TodoItem(
        id: '2',
        title: '시간 미지정 할 일',
        dueDate: DateTime(2026, 11, 4),
        reminderMinutesBefore: 30,
      );
      expect(todoNoTime.reminderDateTime, isNull);

      final todoNoReminder = TodoItem(
        id: '3',
        title: '알림 미설정 할 일',
        dueDate: DateTime(2026, 11, 4),
        dueTime: '18:00',
      );
      expect(todoNoReminder.hasReminder, isFalse);
      expect(todoNoReminder.reminderDateTime, isNull);
    });

    test('Schedule prepDateTime calculation', () {
      final schedule = Schedule(
        id: 's1',
        title: '회의',
        date: DateTime(2026, 11, 4),
        time: '10:00',
        prepMinutesBefore: 15,
      );

      expect(schedule.hasPrepTime, isTrue);
      expect(schedule.prepSummaryText, '15분 전 (09:45)');
      final prepDt = schedule.prepDateTimeForDay(DateTime(2026, 11, 4));
      expect(prepDt, DateTime(2026, 11, 4, 9, 45));
    });

    test('TodoItem copyWith and JSON serialization preserves reminderMinutesBefore', () {
      final original = TodoItem(
        id: 't_json',
        title: '테스트',
        dueDate: DateTime(2026, 11, 4),
        dueTime: '20:00',
        reminderMinutesBefore: 60,
      );

      final json = original.toJson();
      expect(json['reminderMinutesBefore'], 60);

      final fromJson = TodoItem.fromJson(json);
      expect(fromJson.reminderMinutesBefore, 60);
      expect(fromJson.reminderSummaryText, '1시간 전');

      final copied = fromJson.copyWith(clearReminderMinutes: true);
      expect(copied.reminderMinutesBefore, isNull);
      expect(copied.hasReminder, isFalse);
    });
  });
}

