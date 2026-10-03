import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mira/app/app.dart';
import 'package:mira/app/store.dart';
import 'package:mira/services/database/cloud_repository.dart';
import 'package:mira/services/database/document.dart';
import 'store_test.dart' show MemoryLocal, MemoryCloud;

void main() {
  testWidgets('failed first profile load never presents onboarding', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    final local = MemoryLocal();
    final cloud = MemoryCloud()..offline = true;
    final store = MiraStore(local);
    await store.open('account', repository: cloud);
    await tester.pumpWidget(MiraApp(store: store));
    await tester.pumpAndSettle();
    expect(store.awaitingCloudProfile, isTrue);
    expect(find.text('Начать ›'), findsNothing);
    expect(find.textContaining('Не удалось загрузить профиль'), findsOneWidget);
    expect(local.values['account'], isNull);

    cloud.offline = false;
    cloud.snapshot = CloudSnapshot(
      3,
      MiraDocument()..profile.addAll({'onboarded': true, 'name': 'Аня'}),
    );
    await store.sync();
    await tester.pumpAndSettle();
    expect(store.awaitingCloudProfile, isFalse);
    expect(find.text('Твой день, Аня'), findsOneWidget);
    expect(find.text('Начать ›'), findsNothing);
    expect(store.dirty, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cached profile remains usable offline after restart', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    final local = MemoryLocal();
    final first = MiraStore(local);
    await first.open('account');
    await first.setProfile({
      'onboarded': true,
      'name': 'Аня',
      'city': 'Москва',
    });
    final restarted = MiraStore(local);
    await restarted.open('account', repository: MemoryCloud()..offline = true);
    await tester.pumpWidget(MiraApp(store: restarted));
    await tester.pumpAndSettle();
    expect(restarted.awaitingCloudProfile, isFalse);
    expect(restarted.profile['city'], 'Москва');
    expect(find.text('Твой день, Аня'), findsOneWidget);
    expect(find.text('Начать ›'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('confirmed empty cloud profile permits new account onboarding', (
    tester,
  ) async {
    final store = MiraStore(MemoryLocal());
    await store.open('new-account', repository: MemoryCloud());
    await tester.pumpWidget(MiraApp(store: store));
    await tester.pumpAndSettle();
    expect(store.awaitingCloudProfile, isFalse);
    expect(find.text('Начать ›'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'sign out and re-entry restore isolated saved profiles and settings',
    () async {
      final local = MemoryLocal();
      final store = MiraStore(local);
      await store.open('guest');
      await store.setProfile({'onboarded': true, 'name': 'Гость'});
      await store.open('account-a');
      await store.setProfile({
        'onboarded': true,
        'name': 'Аня',
        'modules': ['planner', 'nutrition'],
      });
      await store.open('guest');
      expect(store.profile['name'], 'Гость');
      await store.open('account-b');
      expect(store.profile['name'], isNull);
      await store.open('account-a');
      expect(store.profile['onboarded'], isTrue);
      expect(store.profile['name'], 'Аня');
      expect(store.enabled('nutrition'), isTrue);
      expect(store.enabled('style'), isFalse);
    },
  );
}
