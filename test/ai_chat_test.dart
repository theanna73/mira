import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mira/app/store.dart';
import 'package:mira/app/theme.dart';
import 'package:mira/services/ai/ai_service.dart';
import 'package:mira/services/ai/chat_message.dart';
import 'package:mira/services/database/document.dart';
import 'package:mira/services/database/cloud_repository.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/shared/widgets/ai_panel.dart';
import 'package:mira/shared/widgets/common.dart';
import 'store_test.dart' show MemoryLocal, MemoryCloud;

Future<MiraStore> readyStore() async {
  final store = MiraStore(MemoryLocal());
  await store.open('user');
  await store.setProfile({'aiConsent': true, 'onboarded': true});
  return store;
}

Future<void> showChat(
  WidgetTester tester,
  MiraStore store,
  ChatRequest request,
) async {
  await tester.pumpWidget(
    StoreScope(
      store: store,
      child: MaterialApp(
        theme: miraTheme(Brightness.light),
        home: Scaffold(
          body: AiPanel(module: 'style', request: request),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byTooltip('Отправить'));
  await tester.pumpAndSettle();
}

class DelayedReadCloud extends MemoryCloud {
  final response = Completer<CloudSnapshot?>();
  @override
  Future<CloudSnapshot?> read() => response.future;
}

void main() {
  test(
    'chat survives restart, cloud synchronization and is isolated by account',
    () async {
      final local = MemoryLocal();
      final cloud = MemoryCloud();
      final store = MiraStore(local);
      await store.open('A', repository: cloud);
      await store.mutate(
        (d) => d.addMessage(ChatMessage(role: 'user', content: 'Мой вопрос')),
      );
      await store.sync();
      final second = MiraStore(MemoryLocal());
      await second.open('A', repository: cloud);
      expect(second.document.chat.single.content, 'Мой вопрос');
      final restarted = MiraStore(local);
      await restarted.open('A');
      expect(restarted.document.chat.single.content, 'Мой вопрос');
      await restarted.open('B');
      expect(restarted.document.chat, isEmpty);
      await restarted.open('guest');
      expect(restarted.document.chat, isEmpty);
    },
  );

  test(
    'conflict resolution serializes subsequent edits without losing them',
    () async {
      final cloud = DelayedReadCloud();
      final store = MiraStore(MemoryLocal());
      await store.open('user', repository: cloud, synchronize: false);
      store.conflict = true;
      final remote = MiraDocument();
      remote.put(Entry(kind: Kind.task, title: 'Из облака'));
      final resolving = store.resolveConflict(useLocal: false);
      final editing = store.put(Entry(kind: Kind.task, title: 'Новая правка'));
      cloud.snapshot = CloudSnapshot(1, remote);
      cloud.response.complete(cloud.snapshot);
      await resolving;
      await editing;
      expect(store.of(Kind.task).map((e) => e.title).toSet(), {
        'Из облака',
        'Новая правка',
      });
      expect(cloud.snapshot!.document.of(Kind.task).length, 2);
    },
  );

  test(
    'failed nested mutation does not leak profile or chat changes',
    () async {
      final store = await readyStore();
      await store.mutate(
        (d) => d.addMessage(
          ChatMessage(
            role: 'assistant',
            content: 'Ответ',
            actions: [
              {'title': 'Исходное'},
            ],
          ),
        ),
      );
      (store.local as MemoryLocal).fail = true;
      await expectLater(
        store.mutate((d) {
          (d.profile['modules'] as List).clear();
          d.chat.single.actions.single['title'] = 'Повреждено';
        }),
        throwsStateError,
      );
      expect(store.profile['modules'], ['planner', 'style', 'nutrition']);
      expect(store.document.chat.single.actions.single['title'], 'Исходное');
    },
  );

  test(
    'new outfit uses real item IDs and creates a linked plan atomically',
    () {
      final d = MiraDocument();
      final shirt = Entry(kind: Kind.wardrobe, title: 'Футболка');
      d.put(shirt);
      final action = AiAction(
        type: 'create_outfit',
        title: 'На завтра',
        date: '2026-10-03',
        itemIds: [shirt.id],
      );
      action.apply(d);
      expect(d.of(Kind.outfit).single.ids('items'), [shirt.id]);
      expect(
        d.of(Kind.plannedOutfit).single.text('outfitId'),
        d.of(Kind.outfit).single.id,
      );
      expect(() => action.apply(d), throwsFormatException);
      expect(d.of(Kind.outfit).length, 1);
      expect(
        () => AiAction(
          type: 'create_outfit',
          title: 'Ошибка',
          date: '',
          itemIds: ['fake'],
        ).apply(d),
        throwsFormatException,
      );
      final saveOnly = AiAction(
        type: 'create_outfit',
        title: 'Без даты',
        date: '',
        itemIds: [shirt.id],
      );
      saveOnly.apply(d);
      expect(d.of(Kind.outfit).length, 2);
      expect(d.of(Kind.plannedOutfit).length, 1);
    },
  );

  test('event move preserves the event ID and unrelated fields', () {
    final d = MiraDocument();
    final event = Entry(
      kind: Kind.event,
      title: 'Встреча',
      data: {
        'start': '2026-10-03T18:00:00',
        'end': '2026-10-03T19:00:00',
        'location': 'Офис',
        'reminder': true,
      },
    );
    d.put(event);
    AiAction(
      type: 'reschedule_event',
      title: 'Встреча',
      date: '2026-10-03',
      referenceId: event.id,
      start: '2026-10-03T10:00:00',
      end: '2026-10-03T11:00:00',
    ).apply(d);
    expect(d.of(Kind.event).length, 1);
    expect(d.find(event.id)!.text('start'), '2026-10-03T10:00:00');
    expect(d.find(event.id)!.text('location'), 'Офис');
    expect(d.find(event.id)!.flag('reminder'), isTrue);
    expect(
      () => AiAction(
        type: 'reschedule_event',
        title: 'Встреча',
        date: '2026-10-03',
        referenceId: event.id,
        start: '2026-10-03T10:00:00',
        end: '2026-10-03T09:00:00',
      ).apply(d),
      throwsFormatException,
    );
  });

  testWidgets(
    'follow-up includes previous turns and ordinary answers need no action',
    (tester) async {
      final store = await readyStore();
      final histories = <List<ChatMessage>>[];
      await showChat(tester, store, (q, m, date, d, w, history) async {
        histories.add(history);
        return AiSuggestion(
          histories.length == 1
              ? 'Для какого случая?'
              : 'Учту рабочую встречу.',
          [],
        );
      });
      await send(tester, 'Подбери образ');
      expect(find.text('Для какого случая?'), findsOneWidget);
      await send(tester, 'Для работы');
      expect(histories.last.map((m) => m.content).toList(), [
        'Подбери образ',
        'Для какого случая?',
      ]);
      expect(store.document.chat.length, 4);
      expect(find.text('Посмотреть и подтвердить'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'network error preserves the question and retry does not duplicate it',
    (tester) async {
      final store = await readyStore();
      var calls = 0;
      await showChat(tester, store, (q, m, date, d, w, history) async {
        if (++calls == 1) throw TimeoutException('timeout');
        return AiSuggestion('Ответ после повтора', []);
      });
      await send(tester, 'Помоги с планом');
      expect(
        find.text('MIRA не успела ответить. Повторите запрос.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Повторить запрос'));
      await tester.pumpAndSettle();
      expect(store.document.chat.map((m) => m.role).toList(), [
        'user',
        'assistant',
      ]);
      expect(calls, 2);
    },
  );

  testWidgets(
    'cancel leaves data unchanged, confirm applies once with persisted receipt',
    (tester) async {
      final store = await readyStore();
      await showChat(
        tester,
        store,
        (q, m, date, d, w, history) async => AiSuggestion('Предлагаю задачу', [
          AiAction(type: 'create_task', title: 'Проверка', date: '2026-10-03'),
        ]),
      );
      await send(tester, 'Создай задачу');
      await tester.tap(find.text('Посмотреть и подтвердить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(store.of(Kind.task), isEmpty);
      await tester.tap(find.text('Посмотреть и подтвердить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(store.of(Kind.task).length, 1);
      expect(store.document.chat.last.applied, [0]);
      final restarted = MiraStore(store.local);
      await restarted.open('user');
      await showChat(
        tester,
        restarted,
        (q, m, date, d, w, h) async => AiSuggestion('Ответ', []),
      );
      expect(find.text('Сохранено'), findsOneWidget);
      expect(restarted.of(Kind.task).length, 1);
    },
  );

  testWidgets('account switch discards a late provider response', (
    tester,
  ) async {
    final store = await readyStore();
    final answer = Completer<AiSuggestion>();
    await showChat(tester, store, (q, m, date, d, w, h) => answer.future);
    await send(tester, 'Личный вопрос');
    await store.open('other');
    await tester.pumpAndSettle();
    answer.complete(AiSuggestion('Частный ответ', []));
    await tester.pumpAndSettle();
    expect(store.document.chat, isEmpty);
    expect(find.text('Частный ответ'), findsNothing);
  });

  testWidgets('revoked consent blocks sending and applying', (tester) async {
    final store = await readyStore();
    var calls = 0;
    await showChat(tester, store, (q, m, date, d, w, h) async {
      calls++;
      return AiSuggestion('Ответ', []);
    });
    await store.setProfile({'aiConsent': false});
    await tester.pumpAndSettle();
    expect(find.byTooltip('Отправить'), findsNothing);
    expect(calls, 0);
  });

  testWidgets('chat fits narrow screen with keyboard and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final store = await readyStore();
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: miraTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: AiPanel(
              module: 'today',
              request: (q, m, date, d, w, h) async => AiSuggestion('Ответ', []),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Отправить'), findsOneWidget);
  });
}
