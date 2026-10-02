import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/database/cloud_repository.dart';
import '../services/database/document.dart';
import '../services/database/local_repository.dart';
import '../shared/models/entry.dart';

class MiraStore extends ChangeNotifier {
  final LocalRepository local;
  CloudRepository? cloud;
  String scope = 'guest';
  MiraDocument document = MiraDocument();
  int revision = 0;
  bool dirty = false, syncing = false, conflict = false, ready = false;
  String? error;
  Future<void> _queue = Future.value();
  MiraStore(this.local);
  void pauseForAccountChange() {
    ready = false;
    error = null;
    notifyListeners();
  }

  void reportError(String message) {
    error = message;
    notifyListeners();
  }

  List<Entry> of(Kind kind) => document.of(kind);
  Map<String, dynamic> get profile => document.profile;
  bool enabled(String module) =>
      (profile['modules'] as List? ?? []).contains(module);
  Future<void> open(
    String nextScope, {
    CloudRepository? repository,
    bool synchronize = true,
  }) async {
    ready = false;
    notifyListeners();
    await _queue;
    scope = nextScope;
    cloud = repository;
    ready = false;
    error = null;
    conflict = false;
    final raw = await local.read(scope);
    final stored = raw == null
        ? StoredDocument(MiraDocument())
        : StoredDocument.fromJson(raw);
    document = stored.document;
    revision = stored.revision;
    dirty = stored.dirty;
    ready = true;
    notifyListeners();
    if (synchronize) {
      await sync();
    }
  }

  Future<void> mutate(void Function(MiraDocument) action) {
    final operationScope = scope;
    final result = _queue.then((_) async {
      if (operationScope != scope || !ready) {
        throw StateError('Аккаунт изменился. Откройте форму заново.');
      }
      final next = document.clone();
      action(next);
      await local.write(
        scope,
        StoredDocument(next, revision: revision, dirty: true).toJson(),
      );
      document = next;
      dirty = true;
      error = null;
      notifyListeners();
    });
    _queue = result.catchError((Object e) {
      error = 'Не удалось сохранить изменение: $e';
      notifyListeners();
    });
    return result;
  }

  Future<void> put(Entry e) => mutate((d) => d.put(e));
  Future<void> remove(String id) => mutate((d) => d.remove(id));
  Future<void> setProfile(Map<String, dynamic> changes) =>
      mutate((d) => d.profile.addAll(changes));
  Future<void> toggleHabit(Entry habit, DateTime date) => mutate((d) {
    final logs = d
        .of(Kind.habitLog)
        .where(
          (e) =>
              e.text('habitId') == habit.id && e.text('date') == dayKey(date),
        )
        .toList();
    if (logs.isNotEmpty) {
      for (final log in logs) {
        d.remove(log.id);
      }
    } else {
      d.put(
        Entry(
          kind: Kind.habitLog,
          title: habit.title,
          data: {'habitId': habit.id, 'date': dayKey(date)},
        ),
      );
    }
  });
  Future<void> consumePlan(Entry plan) => mutate((d) {
    final current = d.find(plan.id);
    if (current == null || current.kind != Kind.mealPlan) {
      return;
    }
    d.put(
      Entry(kind: Kind.meal, title: current.title, data: {...current.data}),
    );
    d.remove(plan.id);
  });
  Future<void> sync() async {
    if (cloud == null || syncing || conflict || !ready) {
      return;
    }
    syncing = true;
    notifyListeners();
    final job = _queue.then((_) async {
      try {
        final remote = await cloud!.read();
        if (dirty) {
          if ((remote?.revision ?? 0) != revision) {
            throw SyncConflict();
          }
          revision = await cloud!.save(document, revision);
          dirty = false;
        } else if (remote != null) {
          document = remote.document;
          revision = remote.revision;
        }
        await local.write(
          scope,
          StoredDocument(document, revision: revision, dirty: dirty).toJson(),
        );
        error = null;
      } on SyncConflict {
        conflict = true;
        error =
            'Данные изменились на другом устройстве. Выберите версию в профиле.';
      } catch (_) {
        error =
            'Облако недоступно. Изменения сохранены на устройстве; повторите синхронизацию позже.';
      }
    });
    _queue = job.catchError((Object e) {
      error = e.toString();
    });
    await _queue;
    syncing = false;
    notifyListeners();
  }

  Future<void> resolveConflict({required bool useLocal}) async {
    final operationScope = scope;
    final repository = cloud;
    if (repository == null || !conflict) return;
    final job = _queue.then((_) async {
      if (operationScope != scope || !ready) {
        throw StateError('Аккаунт изменился');
      }
      final remote = await repository.read();
      final nextDocument = useLocal
          ? document
          : remote?.document ?? MiraDocument();
      final nextRevision = remote?.revision ?? 0;
      final nextDirty = useLocal;
      await local.write(
        scope,
        StoredDocument(
          nextDocument,
          revision: nextRevision,
          dirty: nextDirty,
        ).toJson(),
      );
      document = nextDocument;
      revision = nextRevision;
      dirty = nextDirty;
      conflict = false;
      error = null;
      notifyListeners();
    });
    _queue = job.catchError((Object e) {
      error = 'Не удалось разрешить конфликт. Повторите попытку.';
      notifyListeners();
    });
    await job;
    await sync();
  }
}
