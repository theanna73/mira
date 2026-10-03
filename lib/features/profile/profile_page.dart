import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/config.dart';
import '../../services/database/local_repository.dart';
import '../../services/notifications/reminders.dart';
import '../../services/storage/photo_service.dart';
import '../../services/weather/weather_service.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';
import 'auth_panel.dart';
import '../supplies/supplies_page.dart';
import '../lists/lists_page.dart';
import '../lists/routines_page.dart';
import '../today/today_settings.dart';

class ProfilePage extends StatefulWidget {
  final Reminders reminders;
  const ProfilePage({super.key, required this.reminders});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<void> editText(
    String key,
    String label, {
    bool numeric = false,
  }) async {
    final store = StoreScope.of(context);
    final operationScope = store.scope;
    final controller = TextEditingController(
      text: store.profile[key]?.toString() ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          maxLength: numeric ? 7 : 1000,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    // Dispose after the closing route has released its TextField.
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    if (result != null && mounted) {
      await perform(context, () async {
        if (numeric &&
            (int.tryParse(result) == null ||
                int.parse(result) <= 0 ||
                int.parse(result) > 100000)) {
          throw const FormatException('Введите число от 1 до 100 000');
        }
        await store.setProfile({
          key: numeric ? int.parse(result) : result,
        }, expectedScope: operationScope);
      });
    }
  }

  Future<void> chooseCity() async {
    final store = StoreScope.of(context);
    final operationScope = store.scope;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Город'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Название города'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Найти'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    if (name == null || name.isEmpty || !mounted) {
      return;
    }
    await perform(context, () async {
      final cities = await WeatherService().cities(name);
      if (!mounted) {
        return;
      }
      if (cities.isEmpty) {
        throw const FormatException('Город не найден');
      }
      final selected = await sheet<Map<String, dynamic>>(
        context,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: cities
              .map(
                (c) => ListTile(
                  title: Text('${c['name']}, ${c['country'] ?? ''}'),
                  subtitle: Text(c['admin1']?.toString() ?? ''),
                  onTap: () => Navigator.pop(context, c),
                ),
              )
              .toList(),
        ),
      );
      if (selected != null) {
        await store.setProfile({
          'city': selected['name'],
          'latitude': selected['latitude'],
          'longitude': selected['longitude'],
        }, expectedScope: operationScope);
      }
    });
  }

  Future<void> importGuest() async {
    final store = StoreScope.of(context);
    final importScope = store.scope;
    if (!await confirm(
          context,
          'Перенести данные гостя?',
          'Текущие данные аккаунта будут заменены гостевыми данными этого устройства. Гостевая копия останется. Фотографии будут загружены в ваш приватный аккаунт.',
        ) ||
        !mounted) {
      return;
    }
    await perform(context, () async {
      final raw = await store.local.read('guest');
      if (raw == null) {
        throw const FormatException('Нет гостевых данных');
      }
      final guest = StoredDocument.fromJson(raw).document;
      final client = Supabase.instance.client;
      if (store.scope != importScope ||
          client.auth.currentUser?.id != importScope) {
        throw StateError('Аккаунт изменился. Повторите перенос.');
      }
      for (final item in guest.of(Kind.wardrobe)) {
        if (store.scope != importScope ||
            client.auth.currentUser?.id != importScope) {
          throw StateError('Аккаунт изменился. Повторите перенос.');
        }
        final path = item.text('photo');
        if (path.isNotEmpty && !path.startsWith('storage:')) {
          final uploaded = await PhotoService().uploadLocal(path, client);
          guest.put(item.copy(data: {...item.data, 'photo': uploaded}));
        }
      }
      await store.mutate((d) {
        if (store.scope != importScope) {
          throw const FormatException('Аккаунт изменился. Повторите перенос.');
        }
        d.profile.clear();
        d.profile.addAll(guest.profile);
        d.entries.clear();
        d.entries.addAll(guest.entries);
      });
      await store.sync();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final profile = store.profile;
    final client = Config.cloudEnabled ? Supabase.instance.client : null;
    final user = client?.auth.currentUser;
    final completed = store.of(Kind.task).where((e) => e.flag('done')).length;
    return PageBody(
      title: 'Я',
      subtitle: 'Настрой MIRA под себя',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('Запасы и сроки'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SuppliesPage()),
              ),
            ),
            ActionChip(
              label: const Text('Мои списки'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const ListsPage()),
              ),
            ),
            ActionChip(
              label: const Text('Последний раз'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const RoutinesPage()),
              ),
            ),
            ActionChip(
              label: const Text('Настроить Сегодня'),
              onPressed: () => sheet(context, const TodaySettings()),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(
              profile['name']?.toString().isNotEmpty == true
                  ? profile['name'].toString()
                  : 'Ваше имя',
            ),
            subtitle: Text(user?.email ?? 'На этом устройстве · без аккаунта'),
            onTap: () => editText('name', 'Имя'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_city_outlined),
            title: Text(profile['city']?.toString() ?? 'Выберите город'),
            subtitle: const Text('Погода по выбранному городу'),
            onTap: chooseCity,
          ),
        ),
        const Section('Мои разделы'),
        ...{
          'planner': 'План',
          'style': 'Стиль',
          'nutrition': 'Питание',
        }.entries.map(
          (e) => SwitchListTile(
            title: Text(e.value),
            value: store.enabled(e.key),
            onChanged: (v) => perform(context, () {
              final modules = List<String>.from(profile['modules'] as List);
              if (v) {
                modules.add(e.key);
              } else {
                modules.remove(e.key);
              }
              return store.setProfile({'modules': modules});
            }),
          ),
        ),
        const Section('Мои цели'),
        Card(
          child: ListTile(
            title: const Text('Цель / приоритет'),
            subtitle: Text(
              profile['goal']?.toString() ?? 'Что для вас сейчас важно?',
            ),
            onTap: () => editText('goal', 'Моя цель'),
          ),
        ),
        const Section('Питание'),
        DropdownButtonFormField<String>(
          initialValue: profile['nutritionMode'] ?? 'planning',
          decoration: const InputDecoration(labelText: 'Режим'),
          items: const [
            DropdownMenuItem(value: 'planning', child: Text('Планирование')),
            DropdownMenuItem(
              value: 'balance',
              child: Text('Регулярные приёмы пищи'),
            ),
            DropdownMenuItem(value: 'calories', child: Text('Калории и БЖУ')),
          ],
          onChanged: (v) =>
              perform(context, () => store.setProfile({'nutritionMode': v})),
        ),
        Card(
          child: ListTile(
            title: const Text('Цель по воде, мл'),
            subtitle: Text('${profile['waterGoal'] ?? 2000}'),
            onTap: () =>
                editText('waterGoal', 'Цель по воде, мл', numeric: true),
          ),
        ),
        if (profile['nutritionMode'] == 'calories')
          Card(
            child: ListTile(
              title: const Text('Цель по калориям'),
              subtitle: Text('${profile['calorieGoal'] ?? 2000}'),
              onTap: () =>
                  editText('calorieGoal', 'Цель по калориям', numeric: true),
            ),
          ),
        if (profile['nutritionMode'] == 'calories')
          for (final goal in {
            'proteinGoal': 'Цель по белкам, г',
            'fatGoal': 'Цель по жирам, г',
            'carbsGoal': 'Цель по углеводам, г',
          }.entries)
            Card(
              child: ListTile(
                title: Text(goal.value),
                subtitle: Text('${profile[goal.key] ?? 'Не задана'}'),
                onTap: () => editText(goal.key, goal.value, numeric: true),
              ),
            ),
        Card(
          child: ListTile(
            title: const Text('Предпочтения и ограничения'),
            subtitle: Text(
              profile['preferences']?.toString() ??
                  'Продукты, аллергии и предпочтения',
            ),
            onTap: () => editText('preferences', 'Предпочтения и ограничения'),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Предпочтения в стиле'),
            subtitle: Text(
              profile['stylePreferences']?.toString() ??
                  'Любимые цвета и сочетания',
            ),
            onTap: () => editText('stylePreferences', 'Мой стиль'),
          ),
        ),
        const Section('Статистика'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Завершено задач: $completed\nОтметок привычек: ${store.of(Kind.habitLog).length}\nВещей в гардеробе: ${store.of(Kind.wardrobe).length}\nОбразов: ${store.of(Kind.outfit).length}\nЗаписей питания: ${store.of(Kind.meal).length}',
            ),
          ),
        ),
        const Section('Настройки'),
        SwitchListTile(
          title: const Text('Напоминания о событиях'),
          subtitle: const Text('За 15 минут · на этом устройстве'),
          value: profile['notifications'] == true,
          onChanged: (v) => perform(context, () async {
            if (v && !await widget.reminders.request()) {
              throw const FormatException(
                'Уведомления недоступны или разрешение не выдано',
              );
            }
            await store.setProfile({'notifications': v});
            await widget.reminders.reconcile(store.document.entries, v);
          }),
        ),
        SwitchListTile(
          title: const Text('Передавать контекст в MIRA AI'),
          subtitle: const Text(
            'Текст планов, гардероба и питания через сервер AI-провайдеру',
          ),
          value: profile['aiConsent'] == true,
          onChanged: (v) =>
              perform(context, () => store.setProfile({'aiConsent': v})),
        ),
        const Section('Аккаунт и облако'),
        if (!Config.cloudEnabled)
          const EmptyCard(
            'Приложение работает локально. Для облака нужны SUPABASE_URL и SUPABASE_ANON_KEY при сборке.',
          ),
        if (Config.cloudEnabled && user == null)
          FilledButton(
            onPressed: () => sheet(context, const AuthPanel()),
            child: const Text('Войти или зарегистрироваться'),
          ),
        if (user != null) ...[
          Card(
            child: ListTile(
              title: Text(
                store.syncing
                    ? 'Синхронизация…'
                    : store.conflict
                    ? 'Конфликт данных'
                    : store.dirty
                    ? 'Есть локальные изменения'
                    : 'Синхронизировано',
              ),
              subtitle: Text(
                store.error ?? 'Версия в облаке: ${store.revision}',
              ),
              trailing: IconButton(
                tooltip: 'Синхронизировать',
                icon: const Icon(Icons.sync),
                onPressed: store.syncing
                    ? null
                    : () => perform(context, store.sync),
              ),
            ),
          ),
          if (store.conflict)
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    if (await confirm(
                          context,
                          'Заменить локальные данные?',
                          'Будет загружена облачная версия. Локальные несинхронизированные изменения будут потеряны.',
                        ) &&
                        context.mounted) {
                      await perform(
                        context,
                        () => store.resolveConflict(useLocal: false),
                      );
                    }
                  },
                  child: const Text('Загрузить облако'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    if (await confirm(
                          context,
                          'Заменить облачные данные?',
                          'На сервер будет отправлена версия этого устройства вместо версии другого устройства.',
                        ) &&
                        context.mounted) {
                      await perform(
                        context,
                        () => store.resolveConflict(useLocal: true),
                      );
                    }
                  },
                  child: const Text('Сохранить мою версию'),
                ),
              ],
            ),
          TextButton(
            onPressed: importGuest,
            child: const Text('Перенести гостевые данные'),
          ),
          TextButton(
            onPressed: () => perform(context, () async {
              await store.sync();
              if (store.dirty &&
                  context.mounted &&
                  !await confirm(
                    context,
                    'Выйти с локальными изменениями?',
                    'Изменения останутся на этом устройстве и будут доступны после входа в тот же аккаунт.',
                  )) {
                return;
              }
              await client!.auth.signOut();
            }),
            child: const Text('Выйти'),
          ),
          TextButton(
            onPressed: () async {
              final deletionScope = store.scope;
              final deletionUserId = user.id;
              if (await confirm(
                    context,
                    'Удалить аккаунт навсегда?',
                    'Все облачные данные и фотографии будут удалены. Действие нельзя отменить.',
                  ) &&
                  context.mounted) {
                await perform(context, () async {
                  if (!store.ready ||
                      store.scope != deletionScope ||
                      client!.auth.currentUser?.id != deletionUserId) {
                    throw StateError('Аккаунт изменился. Повторите действие.');
                  }
                  final cleared = store.document.clone()
                    ..entries.clear()
                    ..chat.clear()
                    ..profile.clear();
                  final response = await client.functions.invoke(
                    'delete-account',
                  );
                  if (response.status != 200) {
                    throw StateError('Не удалось удалить аккаунт');
                  }
                  try {
                    await store.local.write(
                      deletionScope,
                      StoredDocument(cleared).toJson(),
                    );
                  } finally {
                    if (client.auth.currentUser?.id == deletionUserId) {
                      await client.auth.signOut();
                    }
                  }
                });
              }
            },
            child: const Text('Удалить аккаунт'),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'MIRA 0.3.0 · Open-Meteo: погода и геокодирование',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
