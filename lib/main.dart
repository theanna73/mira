import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'app/config.dart';
import 'app/store.dart';
import 'services/database/cloud_repository.dart';
import 'services/database/local_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('ru');
    if (Config.cloudEnabled) {
      await Supabase.initialize(
        url: Config.supabaseUrl,
        publishableKey: Config.supabaseAnonKey,
      );
    }
    final store = MiraStore(
      PreferencesRepository(await SharedPreferences.getInstance()),
    );
    final client = Config.cloudEnabled ? Supabase.instance.client : null;
    await store.open(
      client?.auth.currentUser?.id ?? 'guest',
      synchronize: false,
      repository: client?.auth.currentUser == null
          ? null
          : SupabaseRepository(client!),
    );
    runApp(MiraApp(store: store));
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Не удалось открыть MIRA. Данные не были удалены.\nПроверьте конфигурацию и перезапустите приложение.\n$e',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
