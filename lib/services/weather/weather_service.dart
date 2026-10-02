import 'dart:convert';
import 'package:http/http.dart' as http;

class Weather {
  final double temperature;
  final int code;
  final String city;
  Weather(this.temperature, this.code, this.city);
  String get description => switch (code) {
    0 => 'Ясно',
    1 || 2 || 3 => 'Облачно',
    45 || 48 => 'Туман',
    >= 71 && <= 77 => 'Снег',
    >= 95 => 'Гроза',
    _ => 'Осадки',
  };
}

class WeatherService {
  final http.Client? client;
  WeatherService({this.client});
  Future<http.Response> get(Uri uri) => client?.get(uri) ?? http.get(uri);

  Future<Map<String, dynamic>> context(Map<String, dynamic> profile) async {
    if (profile['latitude'] == null || profile['longitude'] == null) {
      throw StateError('Выберите город в профиле');
    }
    final response = await get(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': profile['latitude'].toString(),
        'longitude': profile['longitude'].toString(),
        'daily': 'temperature_2m_max,temperature_2m_min,weather_code',
        'forecast_days': '7',
        'timezone': 'auto',
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError('Прогноз недоступен');
    final data = jsonDecode(response.body) as Map;
    final daily = data['daily'] as Map;
    final dates = daily['time'] as List;
    return {
      'city': profile['city']?.toString() ?? '',
      'timezone': data['timezone'],
      'source': 'Open-Meteo',
      'forecast': [
        for (var i = 0; i < dates.length; i++)
          {
            'date': dates[i],
            'minTemperature': daily['temperature_2m_min'][i],
            'maxTemperature': daily['temperature_2m_max'][i],
            'description': Weather(
              0,
              (daily['weather_code'][i] as num).toInt(),
              '',
            ).description,
          },
      ],
    };
  }

  Future<List<Map<String, dynamic>>> cities(String name) async {
    final response = await get(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': name,
        'count': '5',
        'language': 'ru',
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Поиск города недоступен');
    }
    return (jsonDecode(response.body)['results'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Weather> current(Map<String, dynamic> profile) async {
    if (profile['latitude'] == null || profile['longitude'] == null) {
      throw StateError('Выберите город в профиле');
    }
    final response = await get(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': profile['latitude'].toString(),
        'longitude': profile['longitude'].toString(),
        'current': 'temperature_2m,weather_code',
        'timezone': 'auto',
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Погода временно недоступна');
    }
    final current = jsonDecode(response.body)['current'] as Map;
    return Weather(
      (current['temperature_2m'] as num).toDouble(),
      (current['weather_code'] as num).toInt(),
      profile['city']?.toString() ?? '',
    );
  }
}
