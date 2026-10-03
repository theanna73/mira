import 'package:flutter/material.dart';
import '../../shared/widgets/common.dart';

const todayBlocks = {
  'weather': 'Погода',
  'planner': 'Твой день',
  'style': 'Образ дня',
  'nutrition': 'Питание',
  'habits': 'Привычки',
  'expiry': 'Скоро истекает',
  'routines': 'Пора сделать',
  'lists': 'Мои списки',
};
List<String> todayOrder(Map<String, dynamic> profile) {
  final stored = (profile['todayOrder'] as List? ?? [])
      .whereType<String>()
      .where(todayBlocks.containsKey)
      .toSet()
      .toList();
  return [...stored, ...todayBlocks.keys.where((key) => !stored.contains(key))];
}

class TodaySettings extends StatefulWidget {
  const TodaySettings({super.key});
  @override
  State<TodaySettings> createState() => _TodaySettingsState();
}

class _TodaySettingsState extends State<TodaySettings> {
  List<String>? order;
  Set<String>? hidden;
  String? scope;
  bool busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    order ??= todayOrder(store.profile);
    hidden ??= (store.profile['todayHidden'] as List? ?? [])
        .cast<String>()
        .toSet();
    scope ??= store.scope;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .8,
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Настроить «Сегодня»', style: TextStyle(fontSize: 23)),
        ),
        const Text('Выбери блоки и перетащи их в нужном порядке'),
        Expanded(
          child: ReorderableListView(
            onReorder: (old, next) => setState(() {
              if (next > old) next--;
              order!.insert(next, order!.removeAt(old));
            }),
            children: [
              for (final key in order!)
                CheckboxListTile(
                  key: ValueKey(key),
                  title: Text(todayBlocks[key]!),
                  value: !hidden!.contains(key),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      hidden!.remove(key);
                    } else {
                      hidden!.add(key);
                    }
                  }),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final store = StoreScope.of(context);
                    if (store.scope != scope) {
                      Navigator.pop(context);
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await store.setProfile({
                        'todayOrder': order,
                        'todayHidden': hidden!.toList(),
                      });
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('Сохранить'),
          ),
        ),
      ],
    ),
  );
}
