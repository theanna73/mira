import 'dart:typed_data';

Future<String> save(Uint8List bytes, String id) async =>
    throw UnsupportedError('Войдите для сохранения фото');
Future<Uint8List> read(String path) async =>
    throw UnsupportedError('Локальное фото доступно на исходном устройстве');
