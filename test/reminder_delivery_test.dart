import 'package:flutter_test/flutter_test.dart';
import 'package:mira/services/notifications/reminders.dart';
import 'package:mira/shared/models/entry.dart';

void main() {
  test(
    'pending reminders survive the final fifteen minutes until event start',
    () {
      final event = Entry(
        kind: Kind.event,
        title: 'Meeting',
        data: {'start': '2026-10-03T19:00:00', 'reminder': true},
      );
      final disabled = event.copy(data: {...event.data, 'reminder': false});
      expect(reminderEvents([event], DateTime(2026, 10, 3, 18, 44)), [event]);
      expect(reminderEvents([event], DateTime(2026, 10, 3, 18, 45)), [event]);
      expect(reminderEvents([event], DateTime(2026, 10, 3, 18, 59)), [event]);
      expect(reminderEvents([event], DateTime(2026, 10, 3, 19)), isEmpty);
      expect(
        reminderEvents([disabled], DateTime(2026, 10, 3, 18, 59)),
        isEmpty,
      );
      expect(reminderEvents([], DateTime(2026, 10, 3, 18, 59)), isEmpty);
    },
  );
}
