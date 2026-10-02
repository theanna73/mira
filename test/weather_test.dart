import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mira/services/weather/weather_service.dart';

void main() {
  test('AI weather context uses dated forecasts and city timezone', () async {
    final service = WeatherService(
      client: MockClient((request) async {
        expect(request.url.queryParameters['timezone'], 'auto');
        expect(request.url.queryParameters['forecast_days'], '7');
        return http.Response(
          jsonEncode({
            'timezone': 'Europe/Moscow',
            'daily': {
              'time': ['2026-10-02', '2026-10-03'],
              'temperature_2m_min': [8, 7],
              'temperature_2m_max': [13, 12],
              'weather_code': [0, 3],
            },
          }),
          200,
        );
      }),
    );
    final weather = await service.context({
      'latitude': 55.75,
      'longitude': 37.62,
      'city': 'Москва',
    });
    expect(weather['timezone'], 'Europe/Moscow');
    expect((weather['forecast'] as List)[1]['date'], '2026-10-03');
    expect((weather['forecast'] as List)[1]['maxTemperature'], 12);
    expect((weather['forecast'] as List)[1]['description'], 'Облачно');
  });
  test(
    'missing location and service errors never produce fabricated forecast',
    () async {
      final service = WeatherService(
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );
      await expectLater(service.context({}), throwsStateError);
      await expectLater(
        service.context({'latitude': 55, 'longitude': 37}),
        throwsStateError,
      );
    },
  );
}
