import '../../services/calendar/calendar_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/editor.dart';

const categories = {
  'personal': 'Личное',
  'work': 'Работа',
  'study': 'Учёба',
  'rest': 'Отдых',
};
Future<void> editPlanner(
  BuildContext context,
  Kind kind,
  DateTime date, [
  Entry? entry,
]) async {
  final store = StoreScope.of(context);
  final fields = switch (kind) {
    Kind.event => [
      const FieldSpec(
        'start',
        'Начало',
        type: FieldType.dateTime,
        required: true,
      ),
      const FieldSpec(
        'end',
        'Окончание',
        type: FieldType.dateTime,
        required: true,
      ),
      const FieldSpec(
        'category',
        'Категория',
        type: FieldType.choice,
        choices: categories,
      ),
      const FieldSpec('location', 'Место'),
      const FieldSpec('notes', 'Заметки'),
      const FieldSpec(
        'reminder',
        'Напомнить за 15 минут',
        type: FieldType.toggle,
      ),
    ],
    Kind.task => [
      const FieldSpec('date', 'Дата', type: FieldType.date, required: true),
      const FieldSpec(
        'priority',
        'Приоритет',
        type: FieldType.choice,
        choices: {'normal': 'Обычный', 'high': 'Высокий'},
      ),
      const FieldSpec('notes', 'Заметки'),
    ],
    _ => [const FieldSpec('notes', 'Зачем мне эта привычка')],
  };
  await sheet(
    context,
    EntryEditor(
      kind: kind,
      heading: entry == null
          ? {
              Kind.event: 'Новое событие',
              Kind.task: 'Новая задача',
              Kind.habit: 'Новая привычка',
            }[kind]!
          : 'Редактировать',
      entry: entry,
      fields: fields,
      defaults: {
        'date': dayKey(date),
        'start': DateTime(date.year, date.month, date.day, 9).toIso8601String(),
        'end': DateTime(date.year, date.month, date.day, 10).toIso8601String(),
        'category': 'personal',
        'priority': 'normal',
      },
      save: (e) async {
        if (kind == Kind.event && !e.time('end')!.isAfter(e.time('start')!)) {
          throw const FormatException('Окончание должно быть позже начала');
        }
        await store.put(e);
      },
    ),
  );
}

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  DateTime date = DateTime.now();
  String mode = 'day';
  bool inPeriod(Entry e) {
    final value = e.kind == Kind.event ? e.time('start') : e.time('date');
    if (value == null) {
      return false;
    }
    if (mode == 'month') {
      return value.year == date.year && value.month == date.month;
    }
    if (mode == 'week') {
      final start = DateTime(
        date.year,
        date.month,
        date.day,
      ).subtract(Duration(days: date.weekday - 1));
      return !value.isBefore(start) &&
          value.isBefore(start.add(const Duration(days: 7)));
    }
    return sameDay(value, date);
  }

  void move(int direction) => setState(
    () => date = mode == 'month'
        ? DateTime(date.year, date.month + direction, 1)
        : DateTime(
            date.year,
            date.month,
            date.day + direction * (mode == 'week' ? 7 : 1),
          ),
  );
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final events = store.of(Kind.event).where(inPeriod).toList()
      ..sort((a, b) => a.text('start').compareTo(b.text('start')));
    final tasks = store.of(Kind.task).where(inPeriod).toList()
      ..sort((a, b) => a.text('date').compareTo(b.text('date')));
    return PageBody(
      title: 'План',
      subtitle: 'Время для того, что важно',
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'day', label: Text('День')),
            ButtonSegment(value: 'week', label: Text('Неделя')),
            ButtonSegment(value: 'month', label: Text('Месяц')),
          ],
          selected: {mode},
          onSelectionChanged: (v) => setState(() => mode = v.first),
        ),
        Row(
          children: [
            IconButton(
              onPressed: () => move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  final v = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (v != null) {
                    setState(() => date = v);
                  }
                },
                child: Text(
                  DateFormat(
                    mode == 'month' ? 'LLLL y' : 'dd/MM/yyyy',
                    'ru',
                  ).format(date),
                ),
              ),
            ),
            IconButton(
              onPressed: () => move(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (mode == 'month')
          CalendarDatePicker(
            initialDate: date,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            onDateChanged: (v) => setState(() {
              date = v;
              mode = 'day';
            }),
          ),
        Section(
          'События',
          action: IconButton(
            tooltip: 'Добавить событие',
            onPressed: () => editPlanner(context, Kind.event, date),
            icon: const Icon(Icons.add),
          ),
        ),
        if (events.isEmpty) const EmptyCard('Нет событий в этом периоде'),
        ...events.map(
          (e) => Card(
            child: ListTile(
              title: Text(e.title),
              subtitle: Text(
                '${DateFormat('dd/MM/yyyy, HH:mm', 'ru').format(e.time('start')!)} · ${categories[e.text('category')] ?? 'Личное'}${e.text('location').isEmpty ? '' : '\n${e.text('location')}'}',
              ),
              onTap: () => editPlanner(context, Kind.event, date, e),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    await editPlanner(context, Kind.event, date, e);
                  }
                  if (v == 'delete' &&
                      context.mounted &&
                      await confirm(context, 'Удалить событие?', e.title) &&
                      context.mounted) {
                    await perform(context, () => store.remove(e.id));
                  }
                  if (v == 'calendar' && context.mounted) {
                    await perform(context, () async {
                      await CalendarService.add(e);
                    });
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Редактировать'),
                  ),
                  if (CalendarService.supported)
                    const PopupMenuItem(
                      value: 'calendar',
                      child: Text('В системный календарь'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ),
          ),
        ),
        Section(
          'Задачи',
          action: IconButton(
            tooltip: 'Добавить задачу',
            onPressed: () => editPlanner(context, Kind.task, date),
            icon: const Icon(Icons.add),
          ),
        ),
        if (tasks.isEmpty) const EmptyCard('Добавьте задачу на выбранную дату'),
        ...tasks.map(
          (e) => Card(
            child: CheckboxListTile(
              value: e.flag('done'),
              onChanged: (v) => perform(
                context,
                () => store.put(e.copy(data: {...e.data, 'done': v})),
              ),
              title: Text(
                e.title,
                style: TextStyle(
                  decoration: e.flag('done')
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              subtitle: Text(
                '${displayDate(e.text('date'))} · ${e.text('priority') == 'high' ? 'Высокий приоритет' : 'Обычный приоритет'}',
              ),
              secondary: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    await editPlanner(context, Kind.task, date, e);
                  } else if (await confirm(
                        context,
                        'Удалить задачу?',
                        e.title,
                      ) &&
                      context.mounted) {
                    await perform(context, () => store.remove(e.id));
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Редактировать'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ),
          ),
        ),
        Section(
          'Привычки',
          action: IconButton(
            tooltip: 'Добавить привычку',
            onPressed: () => editPlanner(context, Kind.habit, date),
            icon: const Icon(Icons.add),
          ),
        ),
        if (store.of(Kind.habit).isEmpty)
          const EmptyCard('Маленькое действие каждый день'),
        ...store
            .of(Kind.habit)
            .map(
              (h) => Card(
                child: CheckboxListTile(
                  title: Text(h.title),
                  subtitle: Text(
                    'Отметка за ${DateFormat('dd/MM', 'ru').format(date)}',
                  ),
                  value: store
                      .of(Kind.habitLog)
                      .any(
                        (l) =>
                            l.text('habitId') == h.id &&
                            l.text('date') == dayKey(date),
                      ),
                  onChanged: (_) =>
                      perform(context, () => store.toggleHabit(h, date)),
                  secondary: IconButton(
                    tooltip: 'Настроить привычку',
                    onPressed: () => sheet(
                      context,
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: const Text('Редактировать'),
                            onTap: () {
                              Navigator.pop(context);
                              editPlanner(context, Kind.habit, date, h);
                            },
                          ),
                          ListTile(
                            title: const Text('Удалить привычку и отметки'),
                            onTap: () async {
                              Navigator.pop(context);
                              if (await confirm(
                                    context,
                                    'Удалить привычку?',
                                    h.title,
                                  ) &&
                                  context.mounted) {
                                await perform(
                                  context,
                                  () => store.remove(h.id),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.more_horiz),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
