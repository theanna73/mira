import 'package:flutter/material.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/editor.dart';

class ListsPage extends StatelessWidget {
  const ListsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final lists = store.of(Kind.shoppingList)
      ..sort(
        (a, b) =>
            (b.flag('pinned') ? 1 : 0).compareTo(a.flag('pinned') ? 1 : 0),
      );
    return Scaffold(
      appBar: AppBar(title: const Text('Мои списки')),
      body: PageBody(
        title: 'Освободи мысли',
        subtitle: 'Покупки, идеи и всё, что хочется сохранить',
        action: IconButton(
          tooltip: 'Новый список',
          icon: const Icon(Icons.add),
          onPressed: () => sheet(
            context,
            EntryEditor(
              kind: Kind.shoppingList,
              heading: 'Новый список',
              fields: const [
                FieldSpec('pinned', 'Закрепить', type: FieldType.toggle),
              ],
              save: store.put,
            ),
          ),
        ),
        children: [
          if (lists.isEmpty)
            const EmptyCard('Создайте список покупок, идей или фильмов'),
          ...lists.map((list) {
            final items = store
                .of(Kind.listItem)
                .where((e) => e.text('listId') == list.id)
                .toList();
            return Card(
              child: ListTile(
                leading: Icon(
                  list.flag('pinned')
                      ? Icons.push_pin_outlined
                      : Icons.checklist,
                ),
                title: Text(list.title),
                subtitle: Text(
                  '${items.where((e) => e.flag('done')).length} / ${items.length} выполнено',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ListDetailPage(listId: list.id),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class ListDetailPage extends StatefulWidget {
  final String listId;
  const ListDetailPage({super.key, required this.listId});
  @override
  State<ListDetailPage> createState() => _ListDetailPageState();
}

class _ListDetailPageState extends State<ListDetailPage> {
  final input = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> add() async {
    if (busy || input.text.trim().isEmpty) return;
    final title = input.text.trim();
    setState(() => busy = true);
    try {
      await StoreScope.of(context).put(
        Entry(
          kind: Kind.listItem,
          title: title,
          data: {'listId': widget.listId, 'done': false},
        ),
      );
      if (mounted) input.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final list = store.document.find(widget.listId);
    if (list == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Список удалён')),
      );
    }
    final items = store
        .of(Kind.listItem)
        .where((e) => e.text('listId') == list.id)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(list.title),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'pin') {
                await perform(
                  context,
                  () => store.put(
                    list.copy(
                      data: {...list.data, 'pinned': !list.flag('pinned')},
                    ),
                  ),
                );
              }
              if (v == 'delete' &&
                  context.mounted &&
                  await confirm(
                    context,
                    'Удалить список?',
                    'Будут удалены все его пункты.',
                  ) &&
                  context.mounted) {
                await perform(context, () => store.remove(list.id));
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pin',
                child: Text(list.flag('pinned') ? 'Открепить' : 'Закрепить'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Удалить список'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (items.isEmpty) const EmptyCard('Добавьте первый пункт'),
                ...items.map(
                  (e) => Card(
                    child: CheckboxListTile(
                      value: e.flag('done'),
                      title: Text(
                        e.title,
                        style: TextStyle(
                          decoration: e.flag('done')
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      onChanged: (v) => perform(
                        context,
                        () => store.put(e.copy(data: {...e.data, 'done': v})),
                      ),
                      secondary: IconButton(
                        tooltip: 'Удалить пункт',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            perform(context, () => store.remove(e.id)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        hintText: 'Добавить пункт…',
                        counterText: '',
                      ),
                      onSubmitted: (_) => add(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Добавить пункт',
                    onPressed: busy ? null : add,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
