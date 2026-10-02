import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/config.dart';
import '../../shared/models/entry.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/editor.dart';
import '../../services/storage/photo_service.dart';

const clothingCategories = {
  'top': 'Верх',
  'bottom': 'Низ',
  'dress': 'Платье',
  'outer': 'Верхняя одежда',
  'shoes': 'Обувь',
  'accessory': 'Аксессуары',
};
Future<void> editClothing(BuildContext context, Kind kind, [Entry? entry]) =>
    sheet(
      context,
      EntryEditor(
        kind: kind,
        heading: kind == Kind.wishlist
            ? 'Желаемая покупка'
            : 'Вещь в гардеробе',
        entry: entry,
        defaults: const {'category': 'top', 'season': 'all'},
        fields: const [
          FieldSpec(
            'category',
            'Категория',
            type: FieldType.choice,
            choices: clothingCategories,
          ),
          FieldSpec('color', 'Цвет'),
          FieldSpec(
            'season',
            'Сезон',
            type: FieldType.choice,
            choices: {
              'all': 'Любой',
              'summer': 'Лето',
              'winter': 'Зима',
              'mid': 'Весна / осень',
            },
          ),
          FieldSpec('brand', 'Бренд'),
          FieldSpec('price', 'Стоимость, ₽', type: FieldType.number),
          FieldSpec('notes', 'Заметки'),
        ],
        save: StoreScope.of(context).put,
      ),
    );

Future<void> editOutfit(BuildContext context, [Entry? entry]) {
  final store = StoreScope.of(context);
  return sheet(
    context,
    EntryEditor(
      kind: Kind.outfit,
      heading: 'Образ',
      entry: entry,
      fields: [
        FieldSpec(
          'items',
          'Вещи в образе',
          type: FieldType.multi,
          choices: {for (final e in store.of(Kind.wardrobe)) e.id: e.title},
        ),
        const FieldSpec(
          'occasion',
          'Случай',
          type: FieldType.choice,
          choices: {
            'casual': 'На каждый день',
            'work': 'На работу',
            'evening': 'Вечер',
            'sport': 'Спорт',
          },
        ),
        const FieldSpec('favorite', 'В избранное', type: FieldType.toggle),
        const FieldSpec('notes', 'Заметки'),
      ],
      defaults: const {'occasion': 'casual'},
      save: (e) async {
        if (e.ids('items').isEmpty) {
          throw const FormatException('Выберите хотя бы одну вещь');
        }
        await store.put(e);
      },
    ),
  );
}

Future<void> planOutfit(BuildContext context, Entry outfit) async {
  final store = StoreScope.of(context);
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) {
    return;
  }
  final existing = store
      .of(Kind.plannedOutfit)
      .where((e) => e.text('date') == dayKey(date))
      .toList();
  if (existing.isNotEmpty &&
      !await confirm(
        context,
        'Заменить образ?',
        'На эту дату уже запланирован образ.',
      )) {
    return;
  }
  if (context.mounted) {
    await perform(
      context,
      () => store.mutate((d) {
        for (final e in existing) {
          d.remove(e.id);
        }
        d.put(
          Entry(
            kind: Kind.plannedOutfit,
            title: outfit.title,
            data: {'outfitId': outfit.id, 'date': dayKey(date), 'worn': false},
          ),
        );
      }),
    );
  }
}

class ClothingPhoto extends StatefulWidget {
  final String path;
  const ClothingPhoto(this.path, {super.key});
  @override
  State<ClothingPhoto> createState() => _ClothingPhotoState();
}

class _ClothingPhotoState extends State<ClothingPhoto> {
  late Future<dynamic> image;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant ClothingPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      load();
    }
  }

  void load() => image = PhotoService().read(
    widget.path,
    Config.cloudEnabled ? Supabase.instance.client : null,
  );
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 68,
    height: 80,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder(
        future: image,
        builder: (context, snapshot) => snapshot.hasData
            ? Image.memory(snapshot.data, fit: BoxFit.cover)
            : const Icon(Icons.checkroom_outlined, size: 36),
      ),
    ),
  );
}

class StylePage extends StatefulWidget {
  const StylePage({super.key});
  @override
  State<StylePage> createState() => _StylePageState();
}

class _StylePageState extends State<StylePage> {
  String tab = 'wardrobe', query = '', filter = 'all';
  Future<void> photo(Entry e) async {
    final store = StoreScope.of(context);
    final source = await sheet<ImageSource>(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Из галереи'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Снять фото'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ],
      ),
    );
    if (source == null || !mounted) {
      return;
    }
    await perform(context, () async {
      final path = await PhotoService().pick(
        source,
        Config.cloudEnabled ? Supabase.instance.client : null,
      );
      if (path != null) {
        await store.put(e.copy(data: {...e.data, 'photo': path}));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final kind = tab == 'wardrobe'
        ? Kind.wardrobe
        : tab == 'wishlist'
        ? Kind.wishlist
        : Kind.outfit;
    final entries = store
        .of(kind)
        .where(
          (e) =>
              e.title.toLowerCase().contains(query.toLowerCase()) &&
              (kind == Kind.outfit ||
                  filter == 'all' ||
                  e.text('category') == filter),
        )
        .toList();
    return PageBody(
      title: 'Стиль',
      subtitle: 'Твой гардероб, твои сочетания',
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'wardrobe', label: Text('Вещи')),
            ButtonSegment(value: 'outfits', label: Text('Образы')),
            ButtonSegment(value: 'wishlist', label: Text('Хочу')),
          ],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Поиск',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        if (kind != Kind.outfit)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 6,
              children: {'all': 'Все', ...clothingCategories}.entries
                  .map(
                    (e) => ChoiceChip(
                      label: Text(e.value),
                      selected: filter == e.key,
                      onSelected: (_) => setState(() => filter = e.key),
                    ),
                  )
                  .toList(),
            ),
          ),
        Section(
          kind == Kind.outfit
              ? 'Образы'
              : kind == Kind.wishlist
              ? 'Список желаний'
              : 'Гардероб',
          action: IconButton(
            tooltip: 'Добавить',
            onPressed: () => kind == Kind.outfit
                ? editOutfit(context)
                : editClothing(context, kind),
            icon: const Icon(Icons.add),
          ),
        ),
        if (entries.isEmpty)
          EmptyCard(
            kind == Kind.outfit
                ? 'Добавьте вещи и соберите первый образ'
                : 'Добавьте вещь, чтобы начать',
          ),
        ...entries.map(
          (e) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: kind == Kind.wardrobe && e.text('photo').isNotEmpty
                        ? ClothingPhoto(e.text('photo'))
                        : Icon(
                            kind == Kind.outfit
                                ? Icons.auto_awesome_outlined
                                : Icons.checkroom_outlined,
                          ),
                    title: Text('${e.flag('favorite') ? '♡ ' : ''}${e.title}'),
                    subtitle: Text(
                      kind == Kind.outfit
                          ? e
                                .ids('items')
                                .map(
                                  (id) => store.document.find(id)?.title ?? '',
                                )
                                .join(' · ')
                          : '${clothingCategories[e.text('category')] ?? 'Вещь'} · ${e.text('color')}\n${e.number('price').toStringAsFixed(0)} ₽${kind == Kind.wardrobe ? ' · надето ${store.document.wears(e.id)} раз\nЦена носки: ${store.document.costPerWear(e) == null ? 'ещё нет носок' : '${store.document.costPerWear(e)!.toStringAsFixed(0)} ₽'}' : ''}',
                    ),
                    onTap: () => kind == Kind.outfit
                        ? editOutfit(context, e)
                        : editClothing(context, kind, e),
                    trailing: IconButton(
                      tooltip: 'Удалить',
                      onPressed: () async {
                        if (await confirm(
                              context,
                              'Удалить?',
                              '${e.title}. Связанные планы образов будут удалены, вещи останутся в гардеробе.',
                            ) &&
                            context.mounted) {
                          await perform(context, () => store.remove(e.id));
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (kind == Kind.wardrobe)
                        TextButton.icon(
                          onPressed: () => photo(e),
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('Фото'),
                        ),
                      if (kind == Kind.outfit) ...[
                        TextButton.icon(
                          onPressed: () => planOutfit(context, e),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: const Text('На дату'),
                        ),
                        IconButton(
                          tooltip: 'Избранное',
                          onPressed: () => perform(
                            context,
                            () => store.put(
                              e.copy(
                                data: {
                                  ...e.data,
                                  'favorite': !e.flag('favorite'),
                                },
                              ),
                            ),
                          ),
                          icon: Icon(
                            e.flag('favorite')
                                ? Icons.favorite
                                : Icons.favorite_border,
                          ),
                        ),
                      ],
                      if (kind == Kind.wishlist)
                        TextButton(
                          onPressed: () => perform(
                            context,
                            () => store.mutate((d) {
                              d.put(
                                Entry(
                                  kind: Kind.wardrobe,
                                  title: e.title,
                                  data: {...e.data},
                                ),
                              );
                              d.remove(e.id);
                            }),
                          ),
                          child: const Text('Куплено → в гардероб'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (kind == Kind.outfit) ...[
          const Section('Запланированные образы'),
          ...store
              .of(Kind.plannedOutfit)
              .map(
                (p) => Card(
                  child: ListTile(
                    title: Text(
                      store.document.find(p.text('outfitId'))?.title ?? p.title,
                    ),
                    subtitle: Text(p.text('date')),
                    leading: Checkbox(
                      value: p.flag('worn'),
                      onChanged: (v) => perform(
                        context,
                        () => store.put(p.copy(data: {...p.data, 'worn': v})),
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Отменить план',
                      icon: const Icon(Icons.close),
                      onPressed: () =>
                          perform(context, () => store.remove(p.id)),
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}
