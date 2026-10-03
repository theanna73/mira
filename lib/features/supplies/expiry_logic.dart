import '../../shared/models/entry.dart';

const supplyCategories = {
  'food': 'Продукты',
  'medicine': 'Лекарства',
  'cosmetics': 'Косметика',
  'care': 'Уход',
};

DateTime? effectiveExpiry(Entry entry) {
  final printed = entry.time('expiry');
  final opened = entry.time('opened');
  final months = entry.number('openMonths').toInt();
  DateTime? afterOpening;
  if (opened != null && months > 0) {
    // Clamp to the last day of the target month (31 January + 1 month).
    final first = DateTime(opened.year, opened.month + months, 1);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    afterOpening = DateTime(
      first.year,
      first.month,
      opened.day > lastDay ? lastDay : opened.day,
    );
  }
  if (printed == null) return afterOpening;
  if (afterOpening == null) return printed;
  return printed.isBefore(afterOpening) ? printed : afterOpening;
}

int? daysUntilExpiry(Entry entry, DateTime now) {
  final expiry = effectiveExpiry(entry);
  if (expiry == null) return null;
  final today = DateTime.utc(now.year, now.month, now.day);
  return DateTime.utc(
    expiry.year,
    expiry.month,
    expiry.day,
  ).difference(today).inDays;
}

bool expiryDue(Entry entry, DateTime now) {
  if (entry.flag('usedUp')) return false;
  final days = daysUntilExpiry(entry, now);
  return days != null && days <= entry.number('notifyDays', 7);
}

String expiryLabel(Entry entry, DateTime now) {
  final days = daysUntilExpiry(entry, now);
  if (days == null) return 'Срок не указан';
  final date = displayDate(dayKey(effectiveExpiry(entry)!));
  if (days < 0) return 'Срок истёк · $date';
  if (days == 0) return 'Срок до сегодня · $date';
  return 'До $date · осталось $days дн.';
}
