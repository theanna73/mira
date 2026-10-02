import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mira/app/store.dart';
import 'package:mira/app/theme.dart';
import 'package:mira/services/ai/ai_service.dart';
import 'package:mira/services/ai/chat_message.dart';
import 'package:mira/shared/models/entry.dart';
import 'package:mira/shared/widgets/ai_panel.dart';
import 'package:mira/shared/widgets/common.dart';
import 'store_test.dart' show MemoryLocal;

void main() {
  testWidgets('render chat preview with explicitly seeded test conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(740, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final config =
          jsonDecode(
                await File('.dart_tool/package_config.json').readAsString(),
              )
              as Map;
      final sdk = Uri.parse('${config['flutterRoot']}/');
      final icons = await File.fromUri(
        sdk.resolve(
          'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
      final bytes = await File.fromUri(
        sdk.resolve('bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),
      ).readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    });
    final store = MiraStore(MemoryLocal());
    await store.open('preview');
    await store.setProfile({'aiConsent': true});
    final shirt = Entry(kind: Kind.wardrobe, title: 'Белая футболка');
    final trousers = Entry(kind: Kind.wardrobe, title: 'Синие брюки');
    await store.mutate((d) {
      d.put(shirt);
      d.put(trousers);
      d.addMessage(ChatMessage(role: 'user', content: 'Что надеть завтра?'));
      d.addMessage(
        ChatMessage(
          role: 'assistant',
          content: 'Для какого случая подбираем образ?',
        ),
      );
      d.addMessage(
        ChatMessage(
          role: 'user',
          content: 'Для работы. Хочу простой удобный вариант.',
        ),
      );
      d.addMessage(
        ChatMessage(
          role: 'assistant',
          content:
              'Можно сочетать белую футболку и синие брюки из вашего гардероба. Обувь пока не добавлена — это частичный комплект. Сохранить и запланировать его на 3 октября?',
          actions: [
            AiAction(
              type: 'create_outfit',
              title: 'На работу',
              date: '2026-10-03',
              itemIds: [shirt.id, trousers.id],
            ).toJson(),
          ],
        ),
      );
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: miraTheme(Brightness.light),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: Material(
                color: const Color(0xFFFAF7F1),
                child: AiPanel(
                  module: 'style',
                  request: (q, m, date, d, w, h) async =>
                      AiSuggestion('Тестовый ответ', []),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'docs/chat-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
