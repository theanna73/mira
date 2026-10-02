import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/today/today_page.dart';
import '../features/planner/planner_page.dart';
import '../features/style/style_page.dart';
import '../features/nutrition/nutrition_page.dart';
import '../features/profile/profile_page.dart';
import '../features/profile/auth_panel.dart';
import '../services/database/cloud_repository.dart';
import '../services/notifications/reminders.dart';
import '../shared/widgets/common.dart';
import '../shared/widgets/ai_panel.dart';
import 'config.dart';
import 'store.dart';
import 'theme.dart';

class MiraApp extends StatefulWidget {
  final MiraStore store;
  const MiraApp({super.key, required this.store});
  @override
  State<MiraApp> createState() => _MiraAppState();
}

class _MiraAppState extends State<MiraApp> with WidgetsBindingObserver {
  final reminders = Reminders();
  final navigator = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? auth;
  Timer? syncTimer, reminderTimer;
  Future<void> accountQueue = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(changed);
    unawaited(widget.store.sync());
    if (Config.cloudEnabled) {
      auth = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final context = navigator.currentContext;
            if (context != null) {
              sheet(context, const RecoveryPanel());
            }
          });
        }
        if (state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.signedOut ||
            state.event == AuthChangeEvent.initialSession) {
          final user = state.session?.user;
          final scope = user?.id ?? 'guest';
          if (scope != widget.store.scope || !widget.store.ready) {
            widget.store.pauseForAccountChange();
            accountQueue = accountQueue
                .then((_) async {
                  if ((Supabase.instance.client.auth.currentUser?.id ??
                          'guest') !=
                      scope) {
                    return;
                  }
                  await widget.store.open(
                    scope,
                    synchronize: false,
                    repository: user == null
                        ? null
                        : SupabaseRepository(
                            Supabase.instance.client,
                            userId: user.id,
                          ),
                  );
                  unawaited(widget.store.sync());
                })
                .catchError((Object e) {
                  widget.store.reportError(
                    'Не удалось открыть данные аккаунта: $e',
                  );
                });
          }
        }
      });
    }
    syncTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(widget.store.sync());
      }
    });
    changed();
  }

  void changed() {
    reminderTimer?.cancel();
    reminderTimer = Timer(const Duration(seconds: 1), () async {
      try {
        await reminders.reconcile(
          widget.store.document.entries,
          widget.store.profile['notifications'] == true,
        );
      } catch (_) {
        /* Scheduling failures never prevent data persistence. */
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.store.sync());
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(changed);
    auth?.cancel();
    syncTimer?.cancel();
    reminderTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StoreScope(
    store: widget.store,
    child: MaterialApp(
      navigatorKey: navigator,
      title: 'MIRA',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: miraTheme(Brightness.light),
      darkTheme: miraTheme(Brightness.dark),
      home: Builder(
        builder: (context) {
          final store = StoreScope.of(context);
          if (!store.ready) {
            return Scaffold(
              body: Center(
                child: store.error == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(store.error!),
                      ),
              ),
            );
          }
          return store.profile['onboarded'] != true
              ? const OnboardingPage()
              : MiraShell(reminders: reminders);
        },
      ),
    ),
  );
}

class MiraShell extends StatefulWidget {
  final Reminders reminders;
  const MiraShell({super.key, required this.reminders});
  @override
  State<MiraShell> createState() => _MiraShellState();
}

class _MiraShellState extends State<MiraShell> {
  String selected = 'today';
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sections = <String, NavigationDestination>{
      'today': const NavigationDestination(
        icon: Icon(Icons.wb_sunny_outlined),
        selectedIcon: Icon(Icons.wb_sunny),
        label: 'Сегодня',
      ),
      if (store.enabled('planner'))
        'planner': const NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          label: 'План',
        ),
      if (store.enabled('style'))
        'style': const NavigationDestination(
          icon: Icon(Icons.checkroom_outlined),
          label: 'Стиль',
        ),
      if (store.enabled('nutrition'))
        'nutrition': const NavigationDestination(
          icon: Icon(Icons.restaurant_outlined),
          label: 'Питание',
        ),
      'profile': const NavigationDestination(
        icon: Icon(Icons.person_outline),
        label: 'Я',
      ),
    };
    if (!sections.containsKey(selected)) {
      selected = 'today';
    }
    return PopScope(
      canPop: selected == 'today',
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() => selected = 'today');
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 850),
              child: Column(
                children: [
                  if (store.error != null)
                    MaterialBanner(
                      content: Text(store.error!),
                      actions: [
                        TextButton(
                          onPressed: () => perform(context, store.sync),
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: switch (selected) {
                      'planner' => const PlannerPage(),
                      'style' => const StylePage(),
                      'nutrition' => const NutritionPage(),
                      'profile' => ProfilePage(reminders: widget.reminders),
                      _ => const TodayPage(),
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: selected == 'profile'
            ? null
            : FloatingActionButton(
                tooltip: 'Спросить MIRA',
                onPressed: () => sheet(context, AiPanel(module: selected)),
                child: const Text('✦', style: TextStyle(fontSize: 28)),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: sections.keys.toList().indexOf(selected),
          onDestinationSelected: (index) =>
              setState(() => selected = sections.keys.elementAt(index)),
          destinations: sections.values.toList(),
        ),
      ),
    );
  }
}
