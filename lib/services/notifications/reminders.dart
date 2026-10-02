import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../shared/models/entry.dart';

class Reminders {
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  Future<void> init() async {
    if (!supported) {
      return;
    }
    tzdata.initializeTimeZones();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    initialized = true;
  }

  Future<bool> request() async {
    if (!supported) {
      return false;
    }
    if (!initialized) {
      await init();
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  int id(Entry e) =>
      e.id.codeUnits.fold(0, (v, c) => (v * 31 + c) & 0x7fffffff);
  Future<void> reconcile(List<Entry> entries, bool enabled) async {
    if (!supported) {
      return;
    }
    if (!initialized) {
      await init();
    }
    final existing = await plugin.pendingNotificationRequests();
    if (!enabled) {
      for (final notification in existing) {
        await plugin.cancel(notification.id);
      }
      return;
    }
    final pending =
        entries
            .where(
              (e) =>
                  e.kind == Kind.event &&
                  e.flag('reminder') &&
                  (e
                          .time('start')
                          ?.isAfter(
                            DateTime.now().add(const Duration(minutes: 15)),
                          ) ??
                      false),
            )
            .toList()
          ..sort((a, b) => a.time('start')!.compareTo(b.time('start')!));
    final desired = {for (final e in pending.take(60)) id(e): e};
    for (final notification in existing) {
      if (!desired.containsKey(notification.id)) {
        await plugin.cancel(notification.id);
      }
    }
    for (final e in desired.values) {
      final payload = e.time('start')!.millisecondsSinceEpoch.toString();
      if (existing.any(
        (n) => n.id == id(e) && n.body == e.title && n.payload == payload,
      )) {
        continue;
      }
      await plugin.zonedSchedule(
        id(e),
        'MIRA · Через 15 минут',
        e.title,
        tz.TZDateTime.from(
          e.time('start')!.subtract(const Duration(minutes: 15)),
          tz.UTC,
        ),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'events',
            'События',
            channelDescription: 'Напоминания о событиях MIRA',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  }
}
