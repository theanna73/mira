import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'document.dart';

abstract interface class LocalRepository {
  Future<Map<String, dynamic>?> read(String scope);
  Future<void> write(String scope, Map<String, dynamic> value);
}

class PreferencesRepository implements LocalRepository {
  final SharedPreferences prefs;
  PreferencesRepository(this.prefs);
  @override
  Future<Map<String, dynamic>?> read(String scope) async {
    final raw = prefs.getString('mira.v1.$scope');
    return raw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> write(String scope, Map<String, dynamic> value) async {
    if (!await prefs.setString('mira.v1.$scope', jsonEncode(value))) {
      throw StateError('Не удалось сохранить данные на устройстве');
    }
  }
}

class StoredDocument {
  final MiraDocument document;
  final int revision;
  final bool dirty;
  StoredDocument(this.document, {this.revision = 0, this.dirty = false});
  Map<String, dynamic> toJson() => {
    'document': document.toJson(),
    'revision': revision,
    'dirty': dirty,
  };
  factory StoredDocument.fromJson(Map<String, dynamic> json) => StoredDocument(
    MiraDocument.fromJson(Map<String, dynamic>.from(json['document'] as Map)),
    revision: json['revision'] as int,
    dirty: json['dirty'] as bool,
  );
}
