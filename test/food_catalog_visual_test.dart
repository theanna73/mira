import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mira/app/app.dart';
import 'package:mira/app/store.dart';
import 'package:mira/app/theme.dart';
import 'package:mira/features/nutrition/food_catalog_picker.dart';
import 'store_test.dart' show MemoryLocal;

void main() {
  testWidgets('capture actual catalogue and entry point for visual approval', (
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
      await Directory('.review/catalog').create(recursive: true);
    });
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
          '.review/catalog/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    final store = MiraStore(MemoryLocal());
    await store.open('catalog-preview');
    await store.setProfile({'onboarded': true, 'name': 'Аня'});
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MiraApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Питание').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продукты'));
    await capture('01-products');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: miraTheme(Brightness.light),
          home: const Scaffold(body: SafeArea(child: FoodCatalogPicker())),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'куриное филе');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Куриная грудка без кожи · сырая'));
    await capture('02-catalogue');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
