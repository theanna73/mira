import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mira/app/app.dart';
import 'package:mira/app/store.dart';
import 'package:mira/shared/models/entry.dart';
import 'store_test.dart' show MemoryLocal;

void main() {
  testWidgets('onboarding saves module selection and all five tabs open', (
    tester,
  ) async {
    await initializeDateFormatting('ru');
    final store = MiraStore(MemoryLocal());
    await store.open('guest');
    await tester.pumpWidget(MiraApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Твой день в гармонии'), findsOneWidget);
    await tester.tap(find.text('Начать ›'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Далее ›'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Аня');
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Далее ›'));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      find.text('Начать мой день'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Начать мой день'));
    await tester.pumpAndSettle();
    expect(find.text('Твой день, Аня'), findsOneWidget);
    for (final tab in ['План', 'Стиль', 'Питание', 'Я', 'Сегодня']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('small-screen forms save real records', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await initializeDateFormatting('ru');
    final store = MiraStore(MemoryLocal());
    await store.open('guest');
    await store.setProfile({'onboarded': true});
    await tester.pumpWidget(MiraApp(store: store));
    await tester.pumpAndSettle();
    for (final scenario in [
      ('План', 'Добавить задачу', Kind.task),
      ('План', 'Добавить событие', Kind.event),
      ('Стиль', 'Добавить', Kind.wardrobe),
    ]) {
      await tester.tap(find.text(scenario.$1).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip(scenario.$2));
      await tester.tap(find.byTooltip(scenario.$2));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Моя запись');
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(store.of(scenario.$3).single.title, 'Моя запись');
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Питание').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Добавить продукт'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Продукт');
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(store.of(Kind.food).single.title, 'Продукт');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
