import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/weather/weather_service.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});
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
    return PageBody(
      title: name.isEmpty ? 'Сегодня' : 'Твой день, $name',
      subtitle: DateFormat('EEEE, d MMMM', 'ru').format(now),
      children: [
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
        if (store.enabled('planner')) ...[
          const Section('Твой план'),
          if (events.isEmpty && tasks.isEmpty)
            const EmptyCard(
              'Свободный день. Добавьте события и задачи в разделе «План».',
            ),
          ...events.map(
            (e) => Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(e.title),
                subtitle: Text(
                  '${DateFormat('HH:mm').format(e.time('start')!)} · ${e.text('location')}',
                ),
              ),
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
        if (store.enabled('style')) ...[
          const Section('Образ дня'),
          if (outfits.isEmpty)
            const EmptyCard(
              'Соберите образ в разделе «Стиль» и запланируйте его на сегодня',
            ),
          ...outfits.map(
            (e) => Card(
              child: CheckboxListTile(
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
        const SizedBox(height: 24),
        const Text('MIRA ✦  Твой день в гармонии', textAlign: TextAlign.center),
      ],
    );
  }
}
