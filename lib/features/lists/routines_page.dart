import 'package:flutter/material.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/editor.dart';

int? daysSince(Entry entry, DateTime now) {
  final last = entry.time('lastDone');
  if (last == null) return null;
  return DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(last.year, last.month, last.day)).inDays;
}

bool routineDue(Entry entry, DateTime now) {
  final elapsed = daysSince(entry, now);
  return elapsed == null || elapsed >= entry.number('intervalDays', 7);
}

String routineLabel(Entry entry, DateTime now) {
  final elapsed = daysSince(entry, now);
  return elapsed == null
      ? 'Ещё не отмечено'
      : 'Последний раз: ${displayDate(entry.text('lastDone'))} · $elapsed дн. назад';
}

Future<void> editRoutine(BuildContext context, [Entry? entry]) => sheet(
  context,
  EntryEditor(
    kind: Kind.routine,
    heading: 'Последний раз',
    entry: entry,
    defaults: const {'intervalDays': 7},
    fields: const [
      FieldSpec(
        'intervalDays',
        'Повторять через столько дней',
        type: FieldType.number,
        required: true,
      ),
      FieldSpec('lastDone', 'Последнее выполнение', type: FieldType.date),
      FieldSpec('notes', 'Заметки'),
    ],
    save: (e) async {
      if (e.number('intervalDays') < 1 || e.number('intervalDays') % 1 != 0) {
        throw const FormatException('Период: целое число дней от 1');
      }
      if (e.time('lastDone')?.isAfter(DateTime.now()) ?? false) {
        throw const FormatException(
          'Последнее выполнение не может быть в будущем',
        );
      }
      await StoreScope.of(context).put(e);
    },
  ),
);

class RoutinesPage extends StatelessWidget {
  const RoutinesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final entries = store.of(Kind.routine);
    return Scaffold(
      appBar: AppBar(title: const Text('Последний раз')),
      body: PageBody(
        title: 'Маленькие заботы',
        subtitle: 'Быт, уход и повторяющиеся дела',
        action: IconButton(
          tooltip: 'Новое повторяющееся дело',
          icon: const Icon(Icons.add),
          onPressed: () => editRoutine(context),
        ),
        children: [
          if (entries.isEmpty)
            const EmptyCard(
              'Например: сменить постельное бельё или помыть кисти',
            ),
          ...entries.map(
            (e) => Card(
              child: ListTile(
                onTap: () => editRoutine(context, e),
                leading: Icon(
                  routineDue(e, DateTime.now())
                      ? Icons.history
                      : Icons.check_circle_outline,
                ),
                title: Text(e.title),
                subtitle: Text(
                  '${routineLabel(e, DateTime.now())}\nПериод: ${e.number('intervalDays').toInt()} дн.',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'done') {
                      await perform(
                        context,
                        () => store.put(
                          e.copy(
                            data: {
                              ...e.data,
                              'lastDone': dayKey(DateTime.now()),
                            },
                          ),
                        ),
                      );
                    }
                    if (v == 'delete' &&
                        context.mounted &&
                        await confirm(context, 'Удалить дело?', e.title) &&
                        context.mounted) {
                      await perform(context, () => store.remove(e.id));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'done',
                      child: Text('Сделано сегодня'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
