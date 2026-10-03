import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mira/app/store.dart';
import 'package:mira/features/nutrition/meal_food_picker.dart';
import 'package:mira/services/database/document.dart';
import 'package:mira/services/nutrition/food_catalog.dart';
import 'package:mira/shared/models/entry.dart';
import 'store_test.dart' show MemoryLocal;

FoodCatalog catalog() => FoodCatalog.fromJson(
  jsonDecode(File('assets/data/usda_foods.json').readAsStringSync())
      as Map<String, dynamic>,
);
void main() {
  test(
    'meal import saves selected date and slot, snapshot and source atomically',
    () async {
      final local = MemoryLocal();
      final store = MiraStore(local);
      await store.open('meal-search');
      final food = catalog().foods.first;
      final choice = MealFoodChoice(food.toEntry(), 150, food);
      final date = DateTime(2026, 10, 2);
      local.fail = true;
      await expectLater(
        store.mutate((d) => choice.saveTo(d, date, 'dinner')),
        throwsStateError,
      );
      expect(store.of(Kind.food), isEmpty);
      expect(store.of(Kind.meal), isEmpty);
      local.fail = false;
      await store.mutate((d) => choice.saveTo(d, date, 'dinner'));
      final meal = store.of(Kind.meal).single;
      expect(meal.text('date'), '2026-10-02');
      expect(meal.text('slot'), 'dinner');
      expect(
        meal.number('calories'),
        closeTo(food.nutrition['calories']! * 1.5, .0001),
      );
      expect(store.of(Kind.mealPlan), isEmpty);
      await store.mutate((d) => choice.saveTo(d, date, 'breakfast'));
      expect(store.of(Kind.food), hasLength(1));
      final restarted = MiraStore(local);
      await restarted.open('meal-search');
      expect(restarted.of(Kind.meal), hasLength(2));
      expect(restarted.of(Kind.food), hasLength(1));
    },
  );
  test('deleted saved source cannot create a meal', () {
    final food = Entry(kind: Kind.food, title: 'Удалённый');
    final d = MiraDocument();
    expect(
      () => MealFoodChoice(food, 100).saveTo(d, DateTime(2026), 'lunch'),
      throwsFormatException,
    );
    expect(d.of(Kind.meal), isEmpty);
  });
  testWidgets('search stages source and quantity until explicit confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MealFoodChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<MealFoodChoice>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MealFoodPicker(
                    title: 'Обед',
                    foods: const [],
                    catalog: Future.value(catalog()),
                  ),
                );
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'творог');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Зернёный творог (cottage cheese) · 2%'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.enterText(find.byType(TextField), '0');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '150,5');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Записать в дневник'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Записать в дневник'));
    await tester.pumpAndSettle();
    expect(result!.quantity, 150.5);
    expect(result!.catalogFood, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
