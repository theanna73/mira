import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mira/app/store.dart';
import 'package:mira/services/database/cloud_repository.dart';
import 'package:mira/services/database/document.dart';
import 'package:mira/services/database/local_repository.dart';
import 'package:mira/shared/models/entry.dart';

class MemoryLocal implements LocalRepository {
  final values = <String, Map<String, dynamic>>{};
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> read(String scope) async => values[scope];
  @override
  Future<void> write(String scope, Map<String, dynamic> value) async {
    if (fail) {
      throw StateError('disk full');
    }
    values[scope] = jsonDecode(jsonEncode(value));
  }
}

class MemoryCloud implements CloudRepository {
  CloudSnapshot? snapshot;
  bool offline = false;
  int reads = 0;
  @override
  Future<CloudSnapshot?> read() async {
    reads++;
    if (offline) {
      throw StateError('offline');
    }
    return snapshot;
  }

  @override
  Future<int> save(MiraDocument document, int expectedRevision) async {
    if (offline) {
      throw StateError('offline');
    }
    if ((snapshot?.revision ?? 0) != expectedRevision) {
      throw SyncConflict();
    }
    final revision = expectedRevision + 1;
    snapshot = CloudSnapshot(revision, document.clone());
    return revision;
  }
}

void main() {
  test(
    'local startup can open without waiting for an unavailable cloud',
    () async {
      final local = MemoryLocal();
      final old = MiraStore(local);
      await old.open('user');
      await old.put(Entry(kind: Kind.task, title: 'Локальная задача'));
      final cloud = MemoryCloud()..offline = true;
      final store = MiraStore(local);
      await store.open('user', repository: cloud, synchronize: false);
      expect(store.ready, isTrue);
      expect(store.of(Kind.task).single.title, 'Локальная задача');
      expect(cloud.reads, 0);
    },
  );

  test('failed local save leaves the visible document unchanged', () async {
    final local = MemoryLocal();
    final store = MiraStore(local);
    await store.open('guest');
    local.fail = true;
    await expectLater(
      store.put(Entry(kind: Kind.task, title: 'Задача')),
      throwsStateError,
    );
    expect(store.of(Kind.task), isEmpty);
  });
  test('offline changes survive restart and upload on reconnection', () async {
    final local = MemoryLocal();
    final cloud = MemoryCloud()..offline = true;
    final first = MiraStore(local);
    await first.open('user-a', repository: cloud);
    await first.put(Entry(kind: Kind.task, title: 'Без интернета'));
    await first.sync();
    expect(first.dirty, isTrue);
    final next = MiraStore(local);
    await next.open('user-a', repository: cloud);
    expect(next.of(Kind.task).single.title, 'Без интернета');
    cloud.offline = false;
    await next.sync();
    expect(next.dirty, isFalse);
    expect(
      cloud.snapshot!.document.of(Kind.task).single.title,
      'Без интернета',
    );
  });
  test('remote concurrent changes are never silently overwritten', () async {
    final cloud = MemoryCloud();
    final first = MiraStore(MemoryLocal()), second = MiraStore(MemoryLocal());
    await first.open('user', repository: cloud);
    await first.setProfile({'name': 'Аня'});
    await first.sync();
    await second.open('user', repository: cloud);
    await first.put(Entry(kind: Kind.task, title: 'Первое устройство'));
    await first.sync();
    await second.put(Entry(kind: Kind.task, title: 'Второе устройство'));
    await second.sync();
    expect(second.conflict, isTrue);
    expect(
      cloud.snapshot!.document.of(Kind.task).single.title,
      'Первое устройство',
    );
    await second.resolveConflict(useLocal: false);
    expect(second.of(Kind.task).single.title, 'Первое устройство');
    expect(second.conflict, isFalse);
  });
  test('account switching never mixes guest and user data', () async {
    final local = MemoryLocal();
    final store = MiraStore(local);
    await store.open('guest');
    await store.put(Entry(kind: Kind.task, title: 'Гость'));
    await store.open('user-a');
    expect(store.of(Kind.task), isEmpty);
    await store.put(Entry(kind: Kind.task, title: 'Аккаунт'));
    await store.open('guest');
    expect(store.of(Kind.task).single.title, 'Гость');
  });
  test('rapid plan consumption creates only one meal', () async {
    final store = MiraStore(MemoryLocal());
    await store.open('guest');
    final plan = Entry(
      kind: Kind.mealPlan,
      title: 'Обед',
      data: {'date': '2026-10-02', 'calories': 400},
    );
    await store.put(plan);
    await Future.wait([store.consumePlan(plan), store.consumePlan(plan)]);
    expect(store.of(Kind.meal).length, 1);
    expect(store.of(Kind.mealPlan), isEmpty);
  });
  test(
    'failed cloud cache write does not publish an uncached document',
    () async {
      final local = MemoryLocal();
      final cloud = MemoryCloud();
      final store = MiraStore(local);
      await store.open('user', repository: cloud);
      cloud.snapshot = CloudSnapshot(
        1,
        MiraDocument(profile: {'name': 'Cloud'}),
      );
      local.fail = true;
      await store.sync();
      expect(store.revision, 0);
      expect(store.profile['name'], '');
      expect(store.error, isNotNull);
      local.fail = false;
      await store.sync();
      expect(store.revision, 1);
      expect(store.profile['name'], 'Cloud');
      final restarted = MiraStore(local);
      await restarted.open('user', synchronize: false);
      expect(restarted.profile['name'], 'Cloud');
    },
  );

  test(
    'upload followed by cache failure recovers after restart without conflict',
    () async {
      final local = MemoryLocal();
      final cloud = MemoryCloud();
      final store = MiraStore(local);
      await store.open('user', repository: cloud);
      await store.put(Entry(kind: Kind.task, title: 'Upload once'));
      local.fail = true;
      await store.sync();
      expect(cloud.snapshot!.revision, 1);
      expect(store.dirty, isTrue);
      expect(store.revision, 0);
      local.fail = false;
      final restarted = MiraStore(local);
      await restarted.open('user', repository: cloud);
      expect(restarted.conflict, isFalse);
      expect(restarted.dirty, isFalse);
      expect(restarted.revision, 1);
      expect(cloud.snapshot!.revision, 1);
      expect(restarted.of(Kind.task).single.title, 'Upload once');
    },
  );

  test(
    'document equality tolerates database map order and numeric normalization',
    () {
      final first = MiraDocument(
        profile: {
          'nested': {
            'a': 1.0,
            'b': [2, 3],
          },
        },
      );
      final same = MiraDocument(
        profile: {
          'nested': {
            'b': [2.0, 3],
            'a': 1,
          },
        },
      );
      expect(first.sameContent(same), isTrue);
      final different = MiraDocument(
        profile: {
          'nested': {
            'b': [3, 2],
            'a': 1,
          },
        },
      );
      expect(first.sameContent(different), isFalse);
    },
  );
}
