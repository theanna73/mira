import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mira/app/store.dart';
import 'package:mira/app/theme.dart';
import 'package:mira/features/nutrition/nutrition_page.dart';
import 'package:mira/services/ai/ai_service.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/shared/widgets/ai_panel.dart';
import 'package:mira/shared/widgets/common.dart';
import 'store_test.dart' show MemoryLocal, MemoryCloud;

void main() {
  testWidgets(
    'recipe confirmation creates only a plan; consumption requires its button',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final local = MemoryLocal();
      final cloud = MemoryCloud();
      final store = MiraStore(local);
      await store.open('recipe-qa', repository: cloud);
      await store.setProfile({'aiConsent': true, 'onboarded': true});
      await tester.pumpWidget(
        StoreScope(
          store: store,
          child: MaterialApp(
            theme: miraTheme(Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () => sheet(
                        context,
                        AiPanel(
                          module: 'nutrition',
                          request: (q, m, date, d, w, history) async =>
                              AiSuggestion('Предлагаю ужин', [
                                AiAction(
                                  type: 'create_recipe',
                                  title: 'Куриная грудка с овощами',
                                  date: dayKey(DateTime.now()),
                                  mealTime: '19:00',
                                  instructions: 'Нарезать и приготовить.',
                                  ingredients: [
                                    {
                                      'foodId': '',
                                      'title': 'Куриная грудка',
                                      'grams': 200,
                                    },
                                  ],
                                ),
                              ]),
                        ),
                      ),
                      child: const Text('Открыть тестовый чат'),
                    ),
                    const Expanded(child: NutritionPage()),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открыть тестовый чат'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Запланируй ужин');
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();
      expect(store.of(Kind.recipe), isEmpty);
      expect(store.of(Kind.mealPlan), isEmpty);
      expect(store.of(Kind.meal), isEmpty);

      await tester.ensureVisible(find.text('Посмотреть и подтвердить'));
      await tester.tap(find.text('Посмотреть и подтвердить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(store.of(Kind.recipe), isEmpty);
      expect(store.of(Kind.mealPlan), isEmpty);

      await tester.tap(find.text('Посмотреть и подтвердить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(store.of(Kind.recipe), hasLength(1));
      expect(store.of(Kind.mealPlan), hasLength(1));
      expect(store.of(Kind.meal), isEmpty);
      expect(store.document.chat.last.applied, [0]);
      await tester.tap(find.byTooltip('Закрыть чат'));
      await tester.pumpAndSettle();
      expect(store.of(Kind.meal), isEmpty);

      await store.sync();
      final restarted = MiraStore(local);
      await restarted.open('recipe-qa', repository: cloud);
      expect(restarted.of(Kind.mealPlan), hasLength(1));
      expect(restarted.of(Kind.meal), isEmpty);
      expect(cloud.snapshot!.document.of(Kind.meal), isEmpty);

      final consume = find.byTooltip('Отметить как съеденное');
      await tester.ensureVisible(consume);
      await tester.tap(consume);
      await tester.pumpAndSettle();
      expect(store.of(Kind.mealPlan), isEmpty);
      expect(store.of(Kind.meal), hasLength(1));
      expect(store.of(Kind.meal).single.text('mealTime'), '19:00');
      expect(tester.takeException(), isNull);
    },
  );
}
