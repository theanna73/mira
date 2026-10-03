import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mira/app/app.dart';
import 'package:mira/app/store.dart';
import 'package:mira/features/supplies/expiry_logic.dart';
import 'package:mira/features/lists/routines_page.dart';
import 'package:mira/services/database/document.dart';
import 'package:mira/services/ai/ai_service.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/features/lists/lists_page.dart';
import 'package:mira/shared/widgets/common.dart';
import 'store_test.dart' show MemoryLocal;

void main() {
  test('opening expiry clamps month end and uses earlier date', () {
    final e = Entry(
      kind: Kind.supply,
      title: 'Крем',
      data: {'opened': '2026-01-31', 'openMonths': 1, 'expiry': '2026-12-01'},
    );
    expect(dayKey(effectiveExpiry(e)!), '2026-02-28');
    expect(daysUntilExpiry(e, DateTime(2026, 2, 28, 23)), 0);
    expect(
      expiryDue(
        e.copy(data: {...e.data, 'usedUp': true}),
        DateTime(2026, 3, 1),
      ),
      false,
    );
    expect(
      displayDate('2026-10-03T19:00:00', includeTime: true),
      '03/10/2026, 19:00',
    );
  });
  test('suggested recipe is saved with grounded macros and one meal plan', () {
    final d = MiraDocument();
    final food = Entry(
      kind: Kind.food,
      title: 'Яйцо',
      data: {'calories': 150, 'protein': 12, 'fat': 10, 'carbs': 1},
    );
    d.put(food);
    AiAction(
      type: 'create_recipe',
      title: 'Омлет',
      date: '2026-10-03',
      servings: 2,
      quantity: 1,
      mealTime: '19:00',
      instructions: 'Смешать и приготовить.',
      ingredients: [
        {'foodId': food.id, 'title': 'Яйцо', 'grams': 200},
      ],
    ).apply(d);
    final recipe = d.of(Kind.recipe).single;
    final plan = d.of(Kind.mealPlan).single;
    expect(recipe.number('calories'), 150);
    expect(plan.text('sourceId'), recipe.id);
    expect(plan.text('mealTime'), '19:00');
    expect(plan.data['nutritionKnown'], true);
    expect(
      MiraDocument.fromJson(d.toJson()).of(Kind.recipe).single.title,
      'Омлет',
    );
  });
  test('unknown ingredients never count as measured zero calories', () {
    final d = MiraDocument();
    final action = AiAction(
      type: 'create_recipe',
      title: 'Салат',
      date: '2026-10-03',
      instructions: 'Нарезать.',
      ingredients: [
        {'foodId': '', 'title': 'Огурец', 'grams': 100},
      ],
    );
    action.apply(d);
    expect(d.of(Kind.recipe).single.data.containsKey('calories'), false);
    expect(d.of(Kind.mealPlan).single.data['nutritionKnown'], false);
    expect(action.details(d), contains('БЖУ пока неизвестны'));
  });
  test(
    'invalid recipe cannot partially commit and list deletion cascades',
    () async {
      final store = MiraStore(MemoryLocal());
      await store.open('guest');
      await expectLater(
        store.mutate(
          (d) => AiAction(
            type: 'create_recipe',
            title: 'Салат',
            date: '2026-10-03',
            instructions: 'Нарезать.',
            ingredients: [
              {'foodId': 'missing', 'title': 'Огурец', 'grams': 100},
            ],
          ).apply(d),
        ),
        throwsFormatException,
      );
      expect(store.of(Kind.recipe), isEmpty);
      expect(store.of(Kind.mealPlan), isEmpty);
      final list = Entry(kind: Kind.shoppingList, title: 'Покупки');
      await store.put(list);
      await store.put(
        Entry(kind: Kind.listItem, title: 'Молоко', data: {'listId': list.id}),
      );
      await store.remove(list.id);
      expect(store.of(Kind.listItem), isEmpty);
    },
  );
  test('routine interval resets from last completion', () {
    final e = Entry(
      kind: Kind.routine,
      title: 'Бельё',
      data: {'intervalDays': 7, 'lastDone': '2026-10-01'},
    );
    expect(routineDue(e, DateTime(2026, 10, 7)), false);
    expect(routineDue(e, DateTime(2026, 10, 8)), true);
  });
  testWidgets(
    'saved profile bypasses onboarding; inventory and lists accessible on phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await initializeDateFormatting('ru');
      final store = MiraStore(MemoryLocal());
      await store.open('account');
      await store.setProfile({'onboarded': true, 'name': 'Аня'});
      await tester.pumpWidget(MiraApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Уже есть аккаунт? Войти'), findsNothing);
      await tester.tap(find.text('Я').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Запасы и сроки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Добавить упаковку'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Крем');
      await tester.scrollUntilVisible(
        find.text('Сохранить'),
        250,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(store.of(Kind.supply).single.title, 'Крем');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('list item creation and completion persist', (tester) async {
    final store = MiraStore(MemoryLocal());
    await store.open('lists-test');
    final list = Entry(kind: Kind.shoppingList, title: 'Покупки');
    await store.put(list);
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(home: ListDetailPage(listId: list.id)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Яблоки');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(store.of(Kind.listItem).single.title, 'Яблоки');
    await tester.tap(find.text('Яблоки'));
    await tester.pumpAndSettle();
    expect(store.of(Kind.listItem).single.flag('done'), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
