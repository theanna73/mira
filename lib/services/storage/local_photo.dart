import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<String> save(Uint8List bytes, String id) async {
  final directory = await getApplicationSupportDirectory();
  final file = File('${directory.path}/mira/photos/$id');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Uint8List> read(String path) => File(path).readAsBytes();
