import 'package:flutter_test/flutter_test.dart';
import 'package:mira/services/database/document.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/features/nutrition/nutrition_logic.dart';
import 'package:mira/services/ai/ai_service.dart';

void main() {
  test(
    'recipe and meal snapshots keep their nutrition after source deletion',
    () {
      final document = MiraDocument();
      final food = Entry(
        kind: Kind.food,
        title: 'Продукт с упаковки',
        data: {'calories': 200, 'protein': 10, 'fat': 5, 'carbs': 20},
      );
      document.put(food);
      final recipe = makeRecipe(
        'Мой рецепт',
        2,
        [
          {'foodId': food.id, 'grams': 300},
        ],
        '',
        document,
      );
      document.put(recipe);
      expect(recipe.number('calories'), 300);
      expect(recipe.number('protein'), 15);
      final meal = Entry(
        kind: Kind.meal,
        title: recipe.title,
        data: {
          'sourceId': recipe.id,
          'date': '2026-10-02',
          ...nutritionSnapshot(recipe, 1.5),
        },
      );
      document.put(meal);
      document.remove(recipe.id);
      expect(document.totals(DateTime(2026, 10, 2)).calories, 450);
      expect(document.find(meal.id)!.text('sourceId'), isEmpty);
      expect(document.totals(DateTime(2026, 10, 3)).calories, 0);
    },
  );
  test('outfit links drive cost per wear without copying wardrobe data', () {
    final d = MiraDocument();
    final item = Entry(
      kind: Kind.wardrobe,
      title: 'Рубашка',
      data: {'price': 6000},
    );
    d.put(item);
    final outfit = Entry(
      kind: Kind.outfit,
      title: 'Работа',
      data: {
        'items': [item.id],
      },
    );
    d.put(outfit);
    expect(d.costPerWear(item), isNull);
    for (var day = 1; day <= 2; day++) {
      d.put(
        Entry(
          kind: Kind.plannedOutfit,
          title: 'План',
          data: {'outfitId': outfit.id, 'date': '2026-10-0$day', 'worn': true},
        ),
      );
    }
    expect(d.wears(item.id), 2);
    expect(d.costPerWear(item), 3000);
    d.remove(item.id);
    expect(d.find(outfit.id)!.ids('items'), isEmpty);
    d.remove(outfit.id);
    expect(d.of(Kind.plannedOutfit).length, 2);
    expect(
      d.of(Kind.plannedOutfit).every((e) => e.text('outfitId').isEmpty),
      isTrue,
    );
  });
  test(
    'AI checks references and rejects replacing an existing outfit plan',
    () {
      final d = MiraDocument();
      final item = Entry(kind: Kind.wardrobe, title: 'Вещь');
      d.put(item);
      final outfit = Entry(
        kind: Kind.outfit,
        title: 'Образ',
        data: {
          'items': [item.id],
        },
      );
      d.put(outfit);
      final action = AiAction(
        type: 'plan_outfit',
        title: 'Образ',
        date: '2026-10-02',
        referenceId: outfit.id,
      );
      d.put(action.toEntry(d));
      expect(() => action.toEntry(d), throwsFormatException);
      expect(
        () => AiAction(
          type: 'create_task',
          title: 'Тест',
          date: '2026-02-31',
        ).toEntry(d),
        throwsFormatException,
      );
      expect(
        () => AiAction(
          type: 'delete_all',
          title: 'Тест',
          date: '2026-10-02',
        ).toEntry(d),
        throwsFormatException,
      );
    },
  );
  test('unsupported schemas and broken foreign references fail explicitly', () {
    expect(
      () => MiraDocument.fromJson({'schemaVersion': 99}),
      throwsFormatException,
    );
    expect(
      () => MiraDocument().put(
        Entry(
          kind: Kind.outfit,
          title: 'Тест',
          data: {
            'items': ['missing'],
          },
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => nutritionSnapshot(Entry(kind: Kind.food, title: 'Тест'), 0),
      throwsFormatException,
    );
  });
  test(
    'deleted ingredient detaches reference while retaining saved nutrition',
    () {
      final d = MiraDocument();
      final food = Entry(
        kind: Kind.food,
        title: 'Chicken',
        data: {'calories': 120, 'protein': 22.5, 'fat': 2.62, 'carbs': 0},
      );
      d.put(food);
      final recipe = makeSuggestedRecipe(
        'Dinner',
        1,
        [
          {'foodId': food.id, 'title': food.title, 'grams': 200},
        ],
        'Cook',
        d,
      );
      d.put(recipe);
      d.put(
        Entry(
          kind: Kind.meal,
          title: recipe.title,
          data: {
            'date': '2026-10-03',
            'sourceId': recipe.id,
            ...nutritionSnapshot(recipe, 1),
          },
        ),
      );
      d.remove(food.id);
      final retained = d.find(recipe.id)!;
      final row = (retained.data['ingredients'] as List).single;
      expect(row['foodId'], '');
      expect(row['title'], 'Chicken');
      expect(row['calories'], 240);
      expect(retained.number('calories'), 240);
      expect(d.totals(DateTime(2026, 10, 3)).calories, 240);
      final edited = makeSuggestedRecipe(
        'Updated dinner',
        1,
        [
          {'foodId': row['foodId'], 'title': row['title'], 'grams': 200},
        ],
        'Cook',
        d,
        id: recipe.id,
      );
      d.put(edited);
      expect(edited.data['nutritionKnown'], isFalse);
      expect(d.totals(DateTime(2026, 10, 3)).calories, 240);
    },
  );
}
