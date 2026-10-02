import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/entry.dart';
import 'common.dart';

enum FieldType { text, number, date, dateTime, toggle, choice, multi }

class FieldSpec {
  final String key, label;
  final FieldType type;
  final bool required;
  final Map<String, String> choices;
  const FieldSpec(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.choices = const {},
  });
}

class EntryEditor extends StatefulWidget {
  final Kind kind;
  final String heading;
  final Entry? entry;
  final List<FieldSpec> fields;
  final Map<String, dynamic> defaults;
  final Future<void> Function(Entry) save;
  const EntryEditor({
    super.key,
    required this.kind,
    required this.heading,
    this.entry,
    required this.fields,
    this.defaults = const {},
    required this.save,
  });
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final Map<String, dynamic> values;
  final controllers = <String, TextEditingController>{};
  bool saving = false;
  String? ownerScope;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ownerScope ??= StoreScope.of(context).scope;
  }

  @override
  void initState() {
    super.initState();
    title = TextEditingController(
      text: widget.entry?.title ?? widget.defaults['title']?.toString() ?? '',
    );
    values = {...widget.defaults, ...?widget.entry?.data};
    for (final f in widget.fields) {
      if (f.type == FieldType.text || f.type == FieldType.number) {
        controllers[f.key] = TextEditingController(
          text: values[f.key]?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    title.dispose();
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pickDate(FieldSpec f) async {
    final current =
        DateTime.tryParse(values[f.key]?.toString() ?? '') ?? DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) {
      return;
    }
    if (f.type == FieldType.dateTime) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(current),
      );
      if (time == null || !mounted) {
        return;
      }
      setState(
        () => values[f.key] = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ).toIso8601String(),
      );
    } else {
      setState(() => values[f.key] = dayKey(day));
    }
  }

  Widget field(FieldSpec f) {
    switch (f.type) {
      case FieldType.text:
      case FieldType.number:
        return TextFormField(
          controller: controllers[f.key],
          decoration: InputDecoration(labelText: f.label),
          keyboardType: f.type == FieldType.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          maxLength: f.type == FieldType.text ? 2000 : null,
          validator: (value) {
            if (f.required && (value == null || value.trim().isEmpty)) {
              return 'Обязательное поле';
            }
            if (f.type == FieldType.number && value!.isNotEmpty) {
              final n = double.tryParse(value.replaceAll(',', '.'));
              if (n == null || !n.isFinite || n < 0 || n > 10000000) {
                return 'Введите число от 0 до 10 000 000';
              }
            }
            return null;
          },
        );
      case FieldType.toggle:
        return SwitchListTile(
          title: Text(f.label),
          value: values[f.key] == true,
          onChanged: (v) => setState(() => values[f.key] = v),
        );
      case FieldType.date:
      case FieldType.dateTime:
        return FormField<String>(
          validator: (_) =>
              f.required && values[f.key] == null ? 'Выберите дату' : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(f.label),
                subtitle: Text(
                  values[f.key] == null
                      ? 'Не выбрана'
                      : DateFormat(
                          f.type == FieldType.date
                              ? 'd MMMM y'
                              : 'd MMMM y, HH:mm',
                          'ru',
                        ).format(DateTime.parse(values[f.key])),
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () => pickDate(f),
              ),
              if (state.hasError)
                Text(
                  state.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        );
      case FieldType.choice:
        return DropdownButtonFormField<String>(
          initialValue: f.choices.containsKey(values[f.key])
              ? values[f.key]
              : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: f.label),
          items: f.choices.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (v) => values[f.key] = v,
          validator: (v) =>
              f.required && v == null ? 'Выберите значение' : null,
        );
      case FieldType.multi:
        final selected = List<String>.from(values[f.key] as List? ?? []);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label),
            Wrap(
              spacing: 8,
              children: f.choices.entries
                  .map(
                    (e) => FilterChip(
                      label: Text(e.value),
                      selected: selected.contains(e.key),
                      onSelected: (v) => setState(() {
                        if (v) {
                          selected.add(e.key);
                        } else {
                          selected.remove(e.key);
                        }
                        values[f.key] = selected;
                      }),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
    }
  }

  Future<void> save() async {
    if (ownerScope != StoreScope.of(context).scope) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Аккаунт изменился. Откройте форму заново.'),
        ),
      );
      return;
    }
    if (!form.currentState!.validate()) {
      return;
    }
    for (final f in widget.fields) {
      if (controllers.containsKey(f.key)) {
        final raw = controllers[f.key]!.text.trim();
        values[f.key] = f.type == FieldType.number
            ? double.tryParse(raw.replaceAll(',', '.')) ?? 0
            : raw;
      }
    }
    setState(() => saving = true);
    try {
      await widget.save(
        Entry(
          id: widget.entry?.id,
          kind: widget.kind,
          title: title.text.trim(),
          data: values,
        ),
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is FormatException ? e.message : e.toString()),
          ),
        );
      }
    }
    if (mounted) {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .86,
    child: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.heading,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: title,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Название'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Введите название' : null,
          ),
          ...widget.fields.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: field(f),
            ),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Сохранение…' : 'Сохранить'),
          ),
        ],
      ),
    ),
  );
}
