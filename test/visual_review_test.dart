import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mira/app/app.dart';
import 'package:mira/app/store.dart';
import 'package:mira/app/theme.dart';
import 'package:mira/features/supplies/supplies_page.dart';
import 'package:mira/services/ai/ai_service.dart';
import 'package:mira/services/ai/chat_message.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/shared/widgets/common.dart';
import 'package:mira/shared/widgets/ai_panel.dart';
import 'store_test.dart' show MemoryLocal;

void main() {
  testWidgets('render phone screens for visual approval using seeded demo data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await initializeDateFormatting('ru');
    await tester.runAsync(() async {
      final config =
          jsonDecode(
                await File('.dart_tool/package_config.json').readAsString(),
              )
              as Map;
      final sdk = Uri.parse('${config['flutterRoot']}/');
      for (final e in {
        'MaterialIcons': File.fromUri(
          sdk.resolve(
            'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ),
        'Roboto': File.fromUri(
          sdk.resolve('bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),
        ),
        'CormorantGaramond': File('assets/fonts/CormorantGaramond.ttf'),
      }.entries) {
        final bytes = await e.value.readAsBytes();
        await (FontLoader(
          e.key,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      await Directory('.review/preview-03').create(recursive: true);
    });
    final store = MiraStore(MemoryLocal());
    await store.open('preview');
    final boundary = GlobalKey();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '.review/preview-03/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MiraApp(store: store),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/welcome-hero.png'),
        boundary.currentContext!,
      ),
    );
    await capture('01-welcome');
    await tester.tap(find.text('Начать ›'));
    await capture('02-modules');
    final now = DateTime.now();
    final date = dayKey(now);
    await store.setProfile({
      'onboarded': true,
      'name': 'Аня',
      'city': 'Москва',
      'nutritionMode': 'calories',
      'calorieGoal': 1750,
      'proteinGoal': 120,
      'fatGoal': 65,
      'carbsGoal': 200,
      'aiConsent': true,
      'todayHidden': ['weather'],
    });
    await store.mutate((d) {
      d.put(
        Entry(
          kind: Kind.event,
          title: 'Работа',
          data: {
            'start': DateTime(
              now.year,
              now.month,
              now.day,
              9,
            ).toIso8601String(),
            'end': DateTime(now.year, now.month, now.day, 12).toIso8601String(),
            'location': 'Офис',
            'category': 'work',
          },
        ),
      );
      d.put(
        Entry(
          kind: Kind.event,
          title: 'Встреча с подругой',
          data: {
            'start': DateTime(
              now.year,
              now.month,
              now.day,
              18,
            ).toIso8601String(),
            'end': DateTime(now.year, now.month, now.day, 19).toIso8601String(),
            'location': 'Кофейня',
            'category': 'personal',
          },
        ),
      );
      d.put(
        Entry(kind: Kind.task, title: 'Купить продукты', data: {'date': date}),
      );
      for (final e in [
        ('Пиджак', 'outer'),
        ('Футболка', 'top'),
        ('Джинсы', 'bottom'),
        ('Кроссовки', 'shoes'),
      ]) {
        d.put(
          Entry(
            kind: Kind.wardrobe,
            title: e.$1,
            data: {'category': e.$2, 'color': 'Нейтральный'},
          ),
        );
      }
      d.put(
        Entry(
          kind: Kind.meal,
          title: 'Овсянка с бананом',
          data: {
            'date': date,
            'slot': 'breakfast',
            'calories': 420,
            'protein': 14,
            'fat': 12,
            'carbs': 65,
            'quantity': 1,
            'unit': 'порц.',
            'mealTime': '08:30',
          },
        ),
      );
      d.put(
        Entry(
          kind: Kind.meal,
          title: 'Курица с рисом',
          data: {
            'date': date,
            'slot': 'lunch',
            'calories': 560,
            'protein': 35,
            'fat': 18,
            'carbs': 62,
            'quantity': 1,
            'unit': 'порц.',
            'mealTime': '13:00',
          },
        ),
      );
      d.put(
        Entry(
          kind: Kind.supply,
          title: 'Йогурт',
          data: {
            'category': 'food',
            'expiry': dayKey(now.add(const Duration(days: 2))),
            'location': 'Холодильник',
          },
        ),
      );
      d.put(
        Entry(
          kind: Kind.supply,
          title: 'Крем для лица',
          data: {
            'category': 'care',
            'expiry': '2027-06-01',
            'opened': '2026-08-01',
            'openMonths': 6,
            'location': 'Ванная',
          },
        ),
      );
      d.addMessage(
        ChatMessage(role: 'user', content: 'Что приготовить на ужин?'),
      );
      d.addMessage(
        ChatMessage(
          role: 'assistant',
          content:
              'Можно приготовить омлет. Предлагаю сохранить рецепт и запланировать ужин на 19:00. Проверь состав и подтверди карточку.',
          actions: [
            AiAction(
              type: 'create_recipe',
              title: 'Омлет',
              date: date,
              instructions: 'Смешать яйца и приготовить на сковороде.',
              ingredients: [
                {'title': 'Яйцо', 'foodId': '', 'grams': 100},
              ],
              mealTime: '19:00',
            ).toJson(),
          ],
        ),
      );
    });
    await capture('03-today');
    for (final e in [
      ('План', '04-planner'),
      ('Стиль', '05-style'),
      ('Питание', '06-nutrition'),
      ('Я', '07-profile'),
    ]) {
      await tester.tap(find.text(e.$1).last);
      await capture(e.$2);
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: StoreScope(
          store: store,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: miraTheme(Brightness.light),
            home: const SuppliesPage(),
          ),
        ),
      ),
    );
    await capture('08-expiry');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: StoreScope(
          store: store,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: miraTheme(Brightness.light),
            home: Scaffold(
              body: AiPanel(
                module: 'nutrition',
                request: (q, m, date, d, w, h) async =>
                    AiSuggestion('Тестовый ответ', []),
              ),
            ),
          ),
        ),
      ),
    );
    await capture('09-chat');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
