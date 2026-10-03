import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mira/app/store.dart';
import 'package:mira/app/theme.dart';
import 'package:mira/features/today/today_page.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/shared/widgets/common.dart';
import 'store_test.dart' show MemoryLocal, MemoryCloud;

Entry dinnerPlan() => Entry(
  kind: Kind.mealPlan,
  title: 'Ужин',
  data: {
    'date': dayKey(DateTime.now()),
    'mealTime': '19:00',
    'slot': 'dinner',
    'quantity': 2,
    'calories': 800,
    'nutritionKnown': true,
  },
);

void main() {
  test('failed consumption preserves plan on restart', () async {
    final local = MemoryLocal();
    final store = MiraStore(local);
    await store.open('qa');
    final plan = dinnerPlan();
    await store.put(plan);
    local.fail = true;
    await expectLater(
      store.consumePlan(plan, source: MealConsumptionSource.nutrition),
      throwsStateError,
    );
    expect(store.of(Kind.meal), isEmpty);
    expect(store.of(Kind.mealPlan).single.id, plan.id);
    local.fail = false;
    final restarted = MiraStore(local);
    await restarted.open('qa');
    expect(restarted.of(Kind.meal), isEmpty);
    expect(restarted.of(Kind.mealPlan).single.id, plan.id);
    await restarted.consumePlan(plan, source: MealConsumptionSource.nutrition);
    expect(restarted.of(Kind.mealPlan), isEmpty);
    expect(restarted.of(Kind.meal), hasLength(1));
  });

  test('offline consumption and its origin survive sync and restart', () async {
    final local = MemoryLocal();
    final cloud = MemoryCloud();
    final store = MiraStore(local);
    await store.open('qa', repository: cloud);
    final plan = dinnerPlan();
    await store.put(plan);
    await store.sync();
    cloud.offline = true;
    final before = DateTime.now().toUtc();
    await store.consumePlan(plan, source: MealConsumptionSource.today);
    final meal = store.of(Kind.meal).single;
    final consumedAt = DateTime.parse(meal.text('consumedAt'));
    expect(consumedAt.isUtc, isTrue);
    expect(consumedAt.isBefore(before), isFalse);
    expect(consumedAt.isAfter(DateTime.now().toUtc()), isFalse);
    expect(meal.text('consumedFromPlanId'), plan.id);
    expect(meal.text('consumedVia'), 'today');
    expect(meal.text('mealTime'), '19:00');
    expect(meal.number('quantity'), 2);
    await store.sync();
    final restarted = MiraStore(local);
    await restarted.open('qa', repository: cloud);
    expect(restarted.of(Kind.mealPlan), isEmpty);
    expect(restarted.of(Kind.meal).single.toJson(), meal.toJson());
    cloud.offline = false;
    await restarted.sync();
    final secondDevice = MiraStore(MemoryLocal());
    await secondDevice.open('qa', repository: cloud);
    expect(secondDevice.of(Kind.mealPlan), isEmpty);
    expect(secondDevice.of(Kind.meal).single.toJson(), meal.toJson());
    await secondDevice.consumePlan(plan);
    expect(secondDevice.of(Kind.meal), hasLength(1));
    expect(secondDevice.of(Kind.meal).single.toJson(), meal.toJson());
  });

  test('device conflict does not merge duplicate meals', () async {
    final cloud = MemoryCloud();
    final first = MiraStore(MemoryLocal());
    final second = MiraStore(MemoryLocal());
    await first.open('qa', repository: cloud);
    final plan = dinnerPlan();
    await first.put(plan);
    await first.sync();
    await second.open('qa', repository: cloud);
    await first.consumePlan(plan, source: MealConsumptionSource.nutrition);
    await second.consumePlan(plan, source: MealConsumptionSource.today);
    await first.sync();
    await second.sync();
    expect(second.conflict, isTrue);
    expect(cloud.snapshot!.document.of(Kind.meal), hasLength(1));
    await second.resolveConflict(useLocal: false);
    expect(second.of(Kind.mealPlan), isEmpty);
    expect(second.of(Kind.meal), hasLength(1));
    expect(second.of(Kind.meal).single.text('consumedVia'), 'nutrition');
  });

  testWidgets('Today consumes only on its button', (tester) async {
    await initializeDateFormatting('ru');
    final store = MiraStore(MemoryLocal());
    await store.open('qa');
    await store.setProfile({
      'modules': ['nutrition'],
      'todayHidden': [
        'weather',
        'planner',
        'style',
        'habits',
        'expiry',
        'routines',
        'lists',
      ],
    });
    final plan = dinnerPlan();
    await store.put(plan);
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: miraTheme(Brightness.light),
          home: const Scaffold(body: TodayPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ужин'));
    await tester.pumpAndSettle();
    expect(store.of(Kind.meal), isEmpty);
    expect(store.of(Kind.mealPlan).single.id, plan.id);
    await tester.ensureVisible(find.text('Съедено'));
    await tester.tap(find.text('Съедено'));
    await tester.pumpAndSettle();
    expect(store.of(Kind.mealPlan), isEmpty);
    expect(store.of(Kind.meal).single.text('consumedVia'), 'today');
    expect(store.of(Kind.meal).single.text('consumedFromPlanId'), plan.id);
    expect(tester.takeException(), isNull);
  });
}
