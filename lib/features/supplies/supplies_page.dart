import 'package:flutter/material.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/editor.dart';
import 'expiry_logic.dart';

Future<void> editSupply(BuildContext context, [Entry? entry]) => sheet(
  context,
  EntryEditor(
    kind: Kind.supply,
    heading: entry == null ? 'Новая упаковка' : 'Сроки и хранение',
    entry: entry,
    defaults: const {'category': 'food', 'notifyDays': 7},
    fields: const [
      FieldSpec(
        'category',
        'Категория',
        type: FieldType.choice,
        choices: supplyCategories,
      ),
      FieldSpec('amount', 'Количество', type: FieldType.number),
      FieldSpec('unit', 'Единица / размер упаковки'),
      FieldSpec('location', 'Место хранения'),
      FieldSpec('expiry', 'Годен до (на упаковке)', type: FieldType.date),
      FieldSpec('opened', 'Дата открытия', type: FieldType.date),
      FieldSpec(
        'openMonths',
        'Срок после открытия, месяцев (6M › 6)',
        type: FieldType.number,
      ),
      FieldSpec(
        'notifyDays',
        'Показать на «Сегодня» за столько дней',
        type: FieldType.number,
      ),
      FieldSpec('notes', 'Условия хранения / заметки'),
    ],
    save: StoreScope.of(context).put,
  ),
);

class SuppliesPage extends StatefulWidget {
  const SuppliesPage({super.key});
  @override
  State<SuppliesPage> createState() => _SuppliesPageState();
}

class _SuppliesPageState extends State<SuppliesPage> {
  String category = 'all';
  bool showUsed = false;
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final entries =
        [...store.of(Kind.supply), ...store.of(Kind.pantry)]
            .where(
              (e) =>
                  (showUsed || !e.flag('usedUp')) &&
                  (category == 'all' ||
                      (e.kind == Kind.pantry ? 'food' : e.text('category')) ==
                          category),
            )
            .toList()
          ..sort(
            (a, b) => (effectiveExpiry(a) ?? DateTime(9999)).compareTo(
              effectiveExpiry(b) ?? DateTime(9999),
            ),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Запасы и сроки')),
      body: PageBody(
        title: 'Забота о запасах',
        subtitle: 'Продукты · лекарства · косметика · уход',
        action: IconButton(
          tooltip: 'Добавить упаковку',
          onPressed: () => editSupply(context),
          icon: const Icon(Icons.add),
        ),
        children: [
          Wrap(
            spacing: 6,
            children: {'all': 'Все', ...supplyCategories}.entries
                .map(
                  (e) => ChoiceChip(
                    label: Text(e.value),
                    selected: category == e.key,
                    onSelected: (_) => setState(() => category = e.key),
                  ),
                )
                .toList(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Показать использованные'),
            value: showUsed,
            onChanged: (v) => setState(() => showUsed = v),
          ),
          const Text(
            'Учитываем более ранний срок: на упаковке или после открытия. При особых условиях хранения следуйте маркировке производителя.',
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const EmptyCard('Добавьте первую упаковку и её срок годности'),
          ...entries.map(
            (e) => Card(
              child: ListTile(
                leading: Icon(
                  e.kind == Kind.pantry || e.text('category') == 'food'
                      ? Icons.kitchen_outlined
                      : Icons.inventory_2_outlined,
                ),
                title: Text(e.title),
                subtitle: Text(
                  '${expiryLabel(e, DateTime.now())}${e.text('location').isEmpty ? '' : '\n${e.text('location')}'}',
                ),
                onTap: () => e.kind == Kind.supply
                    ? editSupply(context, e)
                    : sheet(
                        context,
                        EntryEditor(
                          kind: Kind.pantry,
                          heading: 'Продукт дома',
                          entry: e,
                          fields: const [
                            FieldSpec(
                              'expiry',
                              'Годен до',
                              type: FieldType.date,
                            ),
                            FieldSpec(
                              'opened',
                              'Дата открытия',
                              type: FieldType.date,
                            ),
                            FieldSpec(
                              'openMonths',
                              'Срок после открытия, месяцев',
                              type: FieldType.number,
                            ),
                          ],
                          save: store.put,
                        ),
                      ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'used') {
                      await perform(
                        context,
                        () => store.put(
                          e.copy(
                            data: {...e.data, 'usedUp': !e.flag('usedUp')},
                          ),
                        ),
                      );
                    }
                    if (v == 'delete' &&
                        context.mounted &&
                        await confirm(context, 'Удалить упаковку?', e.title) &&
                        context.mounted) {
                      await perform(context, () => store.remove(e.id));
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'used',
                      child: Text(
                        e.flag('usedUp') ? 'Вернуть в запасы' : 'Использовано',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Удалить'),
                    ),
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
