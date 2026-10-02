import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'local_photo.dart' if (dart.library.html) 'web_photo.dart' as local;

class PhotoService {
  String extension(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return 'jpg';
    }
    throw const FormatException('Выберите фотографию в формате JPEG или PNG');
  }

  Future<String> uploadLocal(String path, SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Войдите в аккаунт');
    }
    final bytes = await local.read(path);
    final ext = extension(bytes);
    final target = '${user.id}/${const Uuid().v4()}.$ext';
    await client.storage
        .from('wardrobe')
        .uploadBinary(
          target,
          bytes,
          fileOptions: FileOptions(
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
          ),
        );
    return 'storage:$target';
  }

  Future<String?> pick(ImageSource source, SupabaseClient? client) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 80,
    );
    if (file == null) {
      return null;
    }
    final bytes = await file.readAsBytes();
    final ext = extension(bytes);
    if (bytes.length > 6 * 1024 * 1024) {
      throw StateError('Фото должно быть меньше 6 МБ');
    }
    final id = const Uuid().v4();
    final user = client?.auth.currentUser;
    if (user != null) {
      final path = '${user.id}/$id.$ext';
      await client!.storage
          .from('wardrobe')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
              upsert: false,
            ),
          );
      return 'storage:$path';
    }
    if (kIsWeb) {
      throw StateError(
        'Для сохранения фотографий в браузере войдите в аккаунт',
      );
    }
    return local.save(bytes, id);
  }

  Future<Uint8List> read(String path, SupabaseClient? client) async {
    if (path.startsWith('storage:')) {
      if (client?.auth.currentUser == null) {
        throw StateError('Войдите в аккаунт');
      }
      return client!.storage.from('wardrobe').download(path.substring(8));
    }
    return local.read(path);
  }
}
