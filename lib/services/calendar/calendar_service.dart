import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../shared/models/entry.dart';

abstract final class CalendarService {
  static const _channel = MethodChannel('app.mira/calendar');
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static Future<bool> add(Entry event) async {
    if (!supported) {
      throw UnsupportedError('Системный календарь доступен на iOS и Android');
    }
    return await _channel.invokeMethod<bool>('add', {
          'title': event.title,
          'notes': event.text('notes'),
          'location': event.text('location'),
          'start': event.time('start')!.millisecondsSinceEpoch,
          'end': event.time('end')!.millisecondsSinceEpoch,
        }) ??
        false;
  }
}
