import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supplies/supplies_page.dart';
import '../supplies/expiry_logic.dart';
import '../lists/lists_page.dart';
import '../lists/routines_page.dart';
import 'today_settings.dart';
import '../../services/weather/weather_service.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';

class TodayPage extends StatefulWidget {
  final ValueChanged<String>? onNavigate;
  const TodayPage({super.key, this.onNavigate});
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Future<Weather>? weather;
  String cityKey = '';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = StoreScope.of(context).profile;
    final key = '${profile['latitude']},${profile['longitude']}';
    if (key != cityKey) {
      cityKey = key;
      weather = profile['latitude'] == null
          ? null
          : WeatherService().current(profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final now = DateTime.now();
    final date = dayKey(now);
    final name = store.profile['name'] as String? ?? '';
    final events =
        store
            .of(Kind.event)
            .where((e) => sameDay(e.time('start'), now))
            .toList()
          ..sort((a, b) => a.text('start').compareTo(b.text('start')));
    final tasks = store
        .of(Kind.task)
        .where((e) => e.text('date') == date)
        .toList();
    final outfits = store
        .of(Kind.plannedOutfit)
        .where((e) => e.text('date') == date)
        .toList();
    final plans = store
        .of(Kind.mealPlan)
        .where((e) => e.text('date') == date)
        .toList();
    final meals = store
        .of(Kind.meal)
        .where((e) => e.text('date') == date)
        .toList();
    final water = store
        .of(Kind.water)
        .where((e) => e.text('date') == date)
        .fold(0.0, (sum, e) => sum + e.number('amount'));
    final hidden = (store.profile['todayHidden'] as List? ?? [])
        .cast<String>()
        .toSet();
    final blocks = <String, List<Widget>>{
      'weather': [
        if (weather == null)
          const EmptyCard('Выберите город в профиле, чтобы видеть погоду')
        else
          FutureBuilder<Weather>(
            future: weather,
            builder: (context, snapshot) => Card(
              child: ListTile(
                leading: const Icon(Icons.wb_sunny_outlined),
                title: Text(
                  snapshot.hasData
                      ? '${snapshot.data!.temperature.toStringAsFixed(0)}° · ${snapshot.data!.description}'
                      : snapshot.hasError
                      ? 'Погода недоступна'
                      : 'Загружаю погоду…',
                ),
                subtitle: Text(
                  snapshot.data?.city ??
                      store.profile['city']?.toString() ??
                      '',
                ),
                trailing: IconButton(
                  tooltip: 'Обновить погоду',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(
                    () => weather = WeatherService().current(store.profile),
                  ),
                ),
              ),
            ),
          ),
      ],
      'planner': [
        if (store.enabled('planner')) ...[
          const Section('Твой план'),
          if (events.isEmpty && tasks.isEmpty)
            const EmptyCard(
              'Свободный день. Добавьте события и задачи в разделе «План».',
            ),
          if (events.isNotEmpty)
            Card(
              child: Column(
                children: [
                  for (final e in events)
                    ListTile(
                      leading: Text(
                        DateFormat('HH:mm').format(e.time('start')!),
                        style: const TextStyle(fontSize: 14),
                      ),
                      title: Text(e.title),
                      subtitle: Text(e.text('location')),
                      dense: true,
                      onTap: () => widget.onNavigate?.call('planner'),
                    ),
                ],
              ),
            ),
          ...tasks.map(
            (e) => Card(
              child: CheckboxListTile(
                title: Text(e.title),
                value: e.flag('done'),
                onChanged: (v) => perform(
                  context,
                  () => store.put(e.copy(data: {...e.data, 'done': v})),
                ),
              ),
            ),
          ),
        ],
      ],
      'style': [
        if (store.enabled('style')) ...[
          const Section('Образ дня'),
          if (outfits.isEmpty)
            const EmptyCard(
              'Соберите образ в разделе «Стиль» и запланируйте его на сегодня',
            ),
          ...outfits.map(
            (e) => Card(
              child: CheckboxListTile(
                secondary: const Icon(Icons.checkroom_outlined),
                title: Text(
                  store.document.find(e.text('outfitId'))?.title ?? e.title,
                ),
                subtitle: const Text('Отметьте, если надели этот образ'),
                value: e.flag('worn'),
                onChanged: (v) => perform(
                  context,
                  () => store.put(e.copy(data: {...e.data, 'worn': v})),
                ),
              ),
            ),
          ),
        ],
      ],
      'nutrition': [
        if (store.enabled('nutrition')) ...[
          const Section('Питание сегодня'),
          if (plans.isEmpty && meals.isEmpty)
            const EmptyCard('Добавьте план питания или запишите приём пищи'),
          ...plans.map(
            (e) => Card(
              child: ListTile(
                title: Text(e.title),
                subtitle: const Text('Запланировано'),
                trailing: TextButton(
                  onPressed: () => perform(context, () => store.consumePlan(e)),
                  child: const Text('Съедено'),
                ),
              ),
            ),
          ),
          ...meals.map(
            (e) => Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(e.title),
                subtitle: const Text('Записано в дневник'),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.water_drop_outlined),
              title: Text('Вода: ${water.toStringAsFixed(0)} мл'),
              trailing: TextButton(
                onPressed: () => perform(
                  context,
                  () => store.put(
                    Entry(
                      kind: Kind.water,
                      title: 'Вода',
                      data: {'date': date, 'amount': 250},
                    ),
                  ),
                ),
                child: const Text('+250 мл'),
              ),
            ),
          ),
        ],
      ],
      'habits': [
        if (store.enabled('planner') && store.of(Kind.habit).isNotEmpty) ...[
          const Section('Привычки'),
          ...store
              .of(Kind.habit)
              .map(
                (h) => Card(
                  child: CheckboxListTile(
                    title: Text(h.title),
                    value: store
                        .of(Kind.habitLog)
                        .any(
                          (l) =>
                              l.text('habitId') == h.id &&
                              l.text('date') == date,
                        ),
                    onChanged: (_) =>
                        perform(context, () => store.toggleHabit(h, now)),
                  ),
                ),
              ),
        ],
      ],
      'expiry': [
        Section(
          'Скоро истекает',
          action: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SuppliesPage()),
            ),
            child: const Text('Все запасы ›'),
          ),
        ),
        for (final e in [
          ...store.of(Kind.supply),
          ...store.of(Kind.pantry),
        ].where((e) => expiryDue(e, now)))
          Card(
            child: ListTile(
              leading: Icon(
                (daysUntilExpiry(e, now) ?? 0) < 0
                    ? Icons.warning_amber
                    : Icons.hourglass_bottom,
                color: (daysUntilExpiry(e, now) ?? 0) < 0
                    ? const Color(0xFFAA5449)
                    : null,
              ),
              title: Text(e.title),
              subtitle: Text(expiryLabel(e, now)),
            ),
          ),
        if (![
          ...store.of(Kind.supply),
          ...store.of(Kind.pantry),
        ].any((e) => expiryDue(e, now)))
          const EmptyCard('Нет упаковок с приближающимся сроком'),
      ],
      'routines': [
        Section(
          'Пора сделать',
          action: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const RoutinesPage()),
            ),
            child: const Text('Все дела ›'),
          ),
        ),
        for (final e in store.of(Kind.routine).where((e) => routineDue(e, now)))
          Card(
            child: ListTile(
              title: Text(e.title),
              subtitle: Text(routineLabel(e, now)),
              trailing: IconButton(
                tooltip: 'Сделано сегодня',
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () => perform(
                  context,
                  () => store.put(e.copy(data: {...e.data, 'lastDone': date})),
                ),
              ),
            ),
          ),
        if (!store.of(Kind.routine).any((e) => routineDue(e, now)))
          const EmptyCard('Повторяющиеся дела в порядке'),
      ],
      'lists': [
        Section(
          'Мои списки',
          action: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ListsPage()),
            ),
            child: const Text('Все списки ›'),
          ),
        ),
        for (final list
            in store.of(Kind.shoppingList).where((e) => e.flag('pinned')))
          Card(
            child: ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(list.title),
              subtitle: Text(
                '${store.of(Kind.listItem).where((e) => e.text('listId') == list.id && !e.flag('done')).length} осталось',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ListDetailPage(listId: list.id),
                ),
              ),
            ),
          ),
        if (!store.of(Kind.shoppingList).any((e) => e.flag('pinned')))
          const EmptyCard('Закрепи список, чтобы видеть его здесь'),
      ],
    };
    return PageBody(
      title: name.isEmpty ? 'Сегодня' : 'Твой день, $name',
      subtitle: DateFormat('EEEE, dd/MM', 'ru').format(now),
      action: IconButton(
        tooltip: 'Настроить Сегодня',
        onPressed: () => sheet(context, const TodaySettings()),
        icon: const Icon(Icons.tune),
      ),
      children: [
        ChipStrip(
          spacing: 8,
          children: [
            for (final e in {
              'style': ('Стиль', Icons.checkroom_outlined),
              'nutrition': ('Питание', Icons.ramen_dining_outlined),
              'planner': ('План', Icons.calendar_today_outlined),
            }.entries)
              if (store.enabled(e.key))
                ActionChip(
                  avatar: Icon(e.value.$2, size: 18),
                  label: Text(e.value.$1),
                  onPressed: () => widget.onNavigate?.call(e.key),
                ),
            ActionChip(
              avatar: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('Запасы'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SuppliesPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final key in todayOrder(store.profile))
          if (!hidden.contains(key)) ...blocks[key]!,
        const SizedBox(height: 24),
        const Text(
          'Маленькие решения для твоего дня',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF898A82)),
        ),
      ],
    );
  }
}
