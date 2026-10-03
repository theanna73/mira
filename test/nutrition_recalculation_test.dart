import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mira/app/store.dart';
import 'package:mira/app/theme.dart';
import 'package:mira/features/nutrition/nutrition_logic.dart';
import 'package:mira/features/nutrition/nutrition_page.dart';
import 'package:mira/services/database/document.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/shared/widgets/common.dart';
import 'store_test.dart' show MemoryLocal, MemoryCloud;

Entry packagedFood() => Entry(
  kind: Kind.food,
  title: 'Продукт',
  data: {'calories': 200, 'protein': 10, 'fat': 5, 'carbs': 20},
);

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> editorApp(
  WidgetTester tester,
  MiraStore store,
  Future<void> Function(BuildContext) open,
) async {
  await initializeDateFormatting('ru');
  await tester.pumpWidget(
    StoreScope(
      store: store,
      child: MaterialApp(
        theme: miraTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('Изменить запись'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Изменить запись'));
  await tester.pumpAndSettle();
}

void main() {
  test('food grams and recipe portions scale every macro', () {
    final food = packagedFood();
    final doc = MiraDocument()..put(food);
    final recipe = makeRecipe(
      'Блюдо',
      2,
      [
        {'foodId': food.id, 'grams': 300},
      ],
      '',
      doc,
    );
    expect(nutritionSnapshot(food, 250), {
      'nutritionKnown': true,
      'calories': 500.0,
      'protein': 25.0,
      'fat': 12.5,
      'carbs': 50.0,
    });
    expect(nutritionSnapshot(recipe, 1.5), {
      'nutritionKnown': true,
      'calories': 450.0,
      'protein': 22.5,
      'fat': 11.25,
      'carbs': 45.0,
    });
  });

  test('missing nutrition differs from four explicit zeros', () {
    final incomplete = packagedFood().copy(data: {'calories': 200});
    expect(nutritionSnapshot(incomplete, 100)['nutritionKnown'], false);
    final zero = packagedFood().copy(
      data: {'calories': 0, 'protein': 0, 'fat': 0, 'carbs': 0},
    );
    expect(nutritionSnapshot(zero, 100)['nutritionKnown'], true);
    expect(nutritionSnapshot(zero, 100)['calories'], 0);
  });

  test('both recipe builders respect unknown ingredient flags', () {
    final food = packagedFood();
    final unknown = food.copy(data: {...food.data, 'nutritionKnown': false});
    final doc = MiraDocument()..put(unknown);
    final ingredients = [
      {'foodId': food.id, 'title': food.title, 'grams': 100},
    ];
    for (final recipe in [
      makeRecipe('Блюдо', 1, ingredients, '', doc),
      makeSuggestedRecipe('Блюдо', 1, ingredients, 'Приготовить.', doc),
    ]) {
      expect(recipe.data['nutritionKnown'], false);
      expect(recipe.data.containsKey('calories'), false);
    }
  });

  test('nonfinite input and scaled overflow cannot become known macros', () {
    final food = packagedFood();
    for (final quantity in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => nutritionSnapshot(food, quantity), throwsFormatException);
    }
    final huge = food.copy(data: {...food.data, 'calories': double.maxFinite});
    expect(() => nutritionSnapshot(huge, 300), throwsFormatException);
    final invalid = food.copy(data: {...food.data, 'fat': double.nan});
    expect(knownNutrition(invalid), false);
  });

  test('recalculated recipe and history survive cloud restart', () async {
    final local = MemoryLocal();
    final cloud = MemoryCloud();
    final store = MiraStore(local);
    await store.open('nutrition-qa', repository: cloud);
    final food = packagedFood();
    await store.put(food);
    final recipe = makeRecipe(
      'Блюдо',
      2,
      [
        {'foodId': food.id, 'grams': 300},
      ],
      '',
      store.document,
    );
    await store.put(recipe);
    final date = DateTime(2026, 10, 3);
    final meal = Entry(
      kind: Kind.meal,
      title: recipe.title,
      data: {
        'date': dayKey(date),
        'sourceId': recipe.id,
        'quantity': 1.5,
        ...nutritionSnapshot(recipe, 1.5),
      },
    );
    await store.put(meal);
    await store.put(food.copy(data: {...food.data, 'calories': 300}));
    final updated = makeRecipe(
      'Блюдо',
      4,
      [
        {'foodId': food.id, 'grams': 450},
      ],
      '',
      store.document,
      id: recipe.id,
    );
    await store.put(updated);
    expect(updated.number('calories'), 337.5);
    expect(updated.number('protein'), 11.25);
    expect(store.document.totals(date).calories, 450);
    await store.sync();
    final restarted = MiraStore(MemoryLocal());
    await restarted.open('nutrition-qa', repository: cloud);
    expect(restarted.document.totals(date).calories, 450);
    expect(restarted.of(Kind.recipe).single.number('calories'), 337.5);
    await restarted.put(
      meal.copy(
        data: {
          ...meal.data,
          'quantity': 2,
          ...nutritionSnapshot(restarted.of(Kind.recipe).single, 2),
        },
      ),
    );
    await restarted.sync();
    final next = MiraStore(local);
    await next.open('nutrition-qa', repository: cloud);
    expect(next.document.totals(date).calories, 675);
    expect(next.document.totals(date).protein, 22.5);
  });

  testWidgets('meal edit clears stale unknown flag and scales quantity', (
    tester,
  ) async {
    final store = MiraStore(MemoryLocal());
    await store.open('qa');
    final food = packagedFood();
    await store.put(food);
    final meal = Entry(
      kind: Kind.meal,
      title: food.title,
      data: {
        'sourceId': food.id,
        'date': dayKey(DateTime.now()),
        'slot': 'dinner',
        'quantity': 100,
        'nutritionKnown': false,
      },
    );
    await store.put(meal);
    await editorApp(
      tester,
      store,
      (context) => editMeal(context, DateTime.now(), entry: meal),
    );
    await tester.enterText(
      field('Количество: граммы продукта / порции рецепта'),
      '250',
    );
    await reveal(tester, find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(store.of(Kind.meal).single.data['nutritionKnown'], true);
    expect(store.document.totals(DateTime.now()).calories, 500);
    expect(store.of(Kind.meal).single.number('protein'), 25);
    expect(tester.takeException(), isNull);
  });

  testWidgets('food editor saves blanks as unknown and zeros as known', (
    tester,
  ) async {
    final store = MiraStore(MemoryLocal());
    await store.open('qa');
    await editorApp(tester, store, (context) => editFood(context));
    await tester.enterText(field('Название'), 'Вода');
    await reveal(tester, find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    final incomplete = store.of(Kind.food).single;
    expect(incomplete.data.containsKey('calories'), false);
    expect(incomplete.data['nutritionKnown'], false);
    await editorApp(tester, store, (context) => editFood(context, incomplete));
    for (final label in [
      'Ккал на 100 г',
      'Белки, г',
      'Жиры, г',
      'Углеводы, г',
    ]) {
      await reveal(tester, field(label));
      await tester.enterText(field(label), '0');
    }
    await reveal(tester, find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(store.of(Kind.food).single.data['nutritionKnown'], true);
    expect(store.of(Kind.food).single.number('calories'), 0);
    expect(tester.takeException(), isNull);
  });
}
