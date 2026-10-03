import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mira/app/store.dart';
import 'package:mira/app/theme.dart';
import 'package:mira/features/nutrition/recipe_editor.dart';
import 'package:mira/features/nutrition/nutrition_logic.dart';
import 'package:mira/services/database/document.dart';
import 'package:mira/services/nutrition/food_catalog.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/shared/widgets/common.dart';
import 'store_test.dart' show MemoryLocal;

Map<String, dynamic> sourceData() =>
    jsonDecode(File('assets/data/usda_foods.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final catalog = FoodCatalog.fromJson(sourceData());
  CatalogFood food(String id) =>
      catalog.foods.singleWhere((f) => f.fdcId == id);

  test(
    'official catalogue has complete nutrients and distinct cooking states',
    () {
      expect(catalog.foods.length, 62);
      expect(food('171077').nutrition['calories'], 120);
      expect(food('171477').nutrition['calories'], 165);
      expect(catalog.search('КУРИНОЕ филе').length, 3);
      expect(catalog.search('грудка сырая').single.fdcId, '171077');
      expect(catalog.search('гречка вареная').single.fdcId, '170686');
    expect(catalog.search('несуществующий продукт'), isEmpty);
    expect(catalog.search('соль').single.fdcId, '173468');
      for (final f in catalog.foods) {
        expect(knownNutrition(f.toEntry()), isTrue);
        expect(
          f.toEntry().data['nutritionSource'],
          containsPair('fdcId', f.fdcId),
        );
      }
    },
  );

  test(
    'invalid units, duplicate IDs and absent values never become zero nutrition',
    () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (d) => d['basisGrams'] = 1,
        (d) => (d['foods'] as List).add((d['foods'] as List).first),
        (d) => (d['foods'] as List).first.remove('protein'),
        (d) => (d['foods'] as List).first['fat'] = -1,
      ]) {
        final d = sourceData();
        change(d);
        expect(() => FoodCatalog.fromJson(d), throwsFormatException);
      }
    },
  );

  test('catalogue imports deduplicate but never overwrite edited products', () {
    final d = MiraDocument();
    final original = food('171077').forDocument(d);
    d.put(original);
    expect(food('171077').forDocument(d).id, original.id);
    d.put(original.copy(data: {...original.data, 'protein': 30}));
    final fresh = food('171077').forDocument(d);
    expect(fresh.id, isNot(original.id));
    expect(d.find(original.id)!.number('protein'), 30);
    expect(fresh.number('protein'), 22.5);
  });

  test(
    'weighted recipe retains ingredient provenance and historical totals',
    () {
      final d = MiraDocument();
      final chicken = food('171077').toEntry(), oil = food('171413').toEntry();
      d.put(chicken);
      d.put(oil);
      final recipe = makeRecipe(
        'Курица',
        2,
        [
          {'foodId': chicken.id, 'grams': 200},
          {'foodId': oil.id, 'grams': 5},
        ],
        'Приготовить',
        d,
      );
      expect(recipe.number('calories'), closeTo(142.1, .0001));
      expect(recipe.number('protein'), 22.5);
      expect(recipe.number('fat'), closeTo(5.12, .0001));
      final rows = recipe.data['ingredients'] as List;
      expect(rows.first['nutritionSource']['fdcId'], '171077');
      d.put(chicken.copy(data: {...chicken.data, 'calories': 200}));
      expect(recipe.number('calories'), closeTo(142.1, .0001));
      final restored = MiraDocument.fromJson(
        jsonDecode(jsonEncode(d.toJson())),
      );
      expect(restored.find(oil.id)!.data['nutritionSource']['fdcId'], '171413');
    },
  );

  testWidgets(
    'recipe catalogue choice is staged; cancel and failed save write nothing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final local = MemoryLocal();
      final store = MiraStore(local);
      await store.open('catalog-test');
      Widget app() => StoreScope(
        store: store,
        child: MaterialApp(
          theme: miraTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => sheet(context, const RecipeEditor()),
                child: const Text('Открыть рецепт'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      Future<void> selectIngredient() async {
        await tester.tap(find.text('Открыть рецепт'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ингредиент из справочника'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'грудка сырая');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Куриная грудка без кожи · сырая'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Выбрать продукт'));
        await tester.pumpAndSettle();
      }

      await selectIngredient();
      expect(store.of(Kind.food), isEmpty);
      expect(store.of(Kind.recipe), isEmpty);
      Navigator.of(tester.element(find.byType(RecipeEditor))).pop();
      await tester.pumpAndSettle();
      expect(local.values['catalog-test'], isNull);
      await selectIngredient();
      await tester.enterText(find.byType(TextFormField).first, 'Курица');
      final save = find.text('Сохранить');
      await tester.scrollUntilVisible(
        save,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.of(Kind.food), isEmpty);
      expect(store.of(Kind.recipe), isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final instructions = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Как приготовить',
      );
      await tester.enterText(instructions, 'Запечь до готовности.');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.of(Kind.food).single.number('calories'), 120);
      expect(store.of(Kind.recipe).single.number('calories'), 120);
      final restarted = MiraStore(local);
      await restarted.open('catalog-test');
      expect(restarted.of(Kind.recipe).single.data['nutritionKnown'], isTrue);
      expect(
        restarted.of(Kind.food).single.data['nutritionSource']['fdcId'],
        '171077',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
