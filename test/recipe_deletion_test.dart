import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mira/app/store.dart';
import 'package:mira/features/nutrition/recipe_editor.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/shared/widgets/common.dart';
import 'store_test.dart' show MemoryLocal;

void main() {
  testWidgets('legacy recipe with deleted ingredient can be edited and saved', (
    tester,
  ) async {
    final local = MemoryLocal();
    final store = MiraStore(local);
    await store.open('recipe-recovery');
    final recipe = Entry(
      kind: Kind.recipe,
      title: 'Dinner',
      data: {
        'servings': 1,
        'instructions': 'Cook',
        'ingredients': [
          {'foodId': 'deleted-food', 'title': 'Chicken', 'grams': 200},
        ],
        'nutritionKnown': true,
        'calories': 240,
        'protein': 45,
        'fat': 5.24,
        'carbs': 0,
      },
    );
    await store.put(recipe);
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => sheet(context, RecipeEditor(entry: recipe)),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Updated dinner');
    await tester.scrollUntilVisible(
      find.text('Сохранить'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeEditor), findsNothing);
    final saved = store.of(Kind.recipe).single;
    expect(saved.title, 'Updated dinner');
    expect(saved.data['nutritionKnown'], false);
    expect((saved.data['ingredients'] as List).single['foodId'], '');
    final restarted = MiraStore(local);
    await restarted.open('recipe-recovery');
    expect(restarted.of(Kind.recipe).single.title, 'Updated dinner');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
