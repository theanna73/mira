import 'package:supabase_flutter/supabase_flutter.dart';
import 'document.dart';

class CloudSnapshot {
  final int revision;
  final MiraDocument document;
  CloudSnapshot(this.revision, this.document);
}

class SyncConflict implements Exception {}

abstract interface class CloudRepository {
  Future<CloudSnapshot?> read();
  Future<int> save(MiraDocument document, int expectedRevision);
}

class SupabaseRepository implements CloudRepository {
  final SupabaseClient client;
  final String userId;
  SupabaseRepository(this.client, {String? userId})
    : userId = userId ?? client.auth.currentUser!.id;
  void verifyAccount() {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Аккаунт изменился');
    }
  }

  @override
  Future<CloudSnapshot?> read() async {
    verifyAccount();
    final row = await client
        .from('mira_documents')
        .select('revision,payload')
        .eq('user_id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 15));
    verifyAccount();
    return row == null
        ? null
        : CloudSnapshot(
            row['revision'] as int,
            MiraDocument.fromJson(
              Map<String, dynamic>.from(row['payload'] as Map),
            ),
          );
  }

  @override
  Future<int> save(MiraDocument document, int expectedRevision) async {
    verifyAccount();
    try {
      return (await client
                  .rpc(
                    'save_mira_document',
                    params: {
                      'new_payload': document.toJson(),
                      'expected_revision': expectedRevision,
                      'expected_user': userId,
                    },
                  )
                  .timeout(const Duration(seconds: 15))
              as num)
          .toInt();
    } on PostgrestException catch (e) {
      if (e.code == '40001') {
        throw SyncConflict();
      }
      rethrow;
    }
  }
}
