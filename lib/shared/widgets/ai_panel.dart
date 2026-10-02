import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/config.dart';
import '../../services/ai/ai_service.dart';
import '../../services/weather/weather_service.dart';
import '../models/entry.dart';
import 'common.dart';

class AiPanel extends StatefulWidget {
  final String module;
  const AiPanel({super.key, required this.module});
  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  final question = TextEditingController();
  AiSuggestion? suggestion;
  bool busy = false;
  String? error;
  final applied = <int>{};
  String? suggestionScope;
  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  Future<void> ask() async {
    if (question.text.trim().isEmpty || question.text.length > 2000) {
      setState(() => error = 'Введите вопрос до 2000 символов');
      return;
    }
    final store = StoreScope.of(context);
    final requestScope = store.scope;
    setState(() {
      busy = true;
      error = null;
      suggestion = null;
      applied.clear();
    });
    try {
      Map<String, dynamic>? weather;
      try {
        final w = await WeatherService().current(store.profile);
        weather = {
          'temperature': w.temperature,
          'description': w.description,
          'city': w.city,
          'date': dayKey(DateTime.now()),
        };
      } catch (_) {
        /* Weather is optional, never fabricated. */
      }
      final answer = await AiService(Supabase.instance.client).ask(
        question.text.trim(),
        widget.module,
        dayKey(DateTime.now()),
        store.document,
        weather,
      );
      if (mounted) {
        if (store.scope != requestScope || store.profile['aiConsent'] != true) {
          throw StateError('Аккаунт или согласие изменились');
        }
        setState(() {
          suggestion = answer;
          suggestionScope = requestScope;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Не удалось получить ответ. Проверьте вход, интернет и настройку функции mira-ai.',
        );
      }
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> apply(int index) async {
    final store = StoreScope.of(context);
    if (suggestionScope != store.scope || store.profile['aiConsent'] != true) {
      setState(
        () => error =
            'Аккаунт или согласие изменились. Получите новое предложение.',
      );
      return;
    }
    final action = suggestion!.actions[index];
    if (!await confirm(context, 'Применить предложение?', action.preview) ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      await store.mutate((d) {
        final module = action.type == 'create_task'
            ? 'planner'
            : action.type == 'plan_outfit'
            ? 'style'
            : 'nutrition';
        if (!(d.profile['modules'] as List).contains(module)) {
          throw const FormatException('Включите этот раздел в профиле');
        }
        d.put(action.toEntry(d));
      });
      if (mounted) {
        setState(() => applied.add(index));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Не удалось применить предложение',
        );
      }
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available =
        Config.cloudEnabled &&
        Supabase.instance.client.auth.currentUser != null;
    final consent = StoreScope.of(context).profile['aiConsent'] == true;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .86,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('MIRA ✦', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 12),
          const Text('Сначала предложение, затем ваше подтверждение.'),
          const SizedBox(height: 16),
          if (!available)
            const EmptyCard(
              'Для AI настройте Supabase и войдите в аккаунт в разделе «Я».',
            )
          else if (!consent) ...[
            const Text(
              'Для ответа текст вопроса, ваши планы, гардероб, питание и предпочтения будут переданы AI-провайдеру через сервер MIRA. Фотографии не передаются. Вы можете отключить это в профиле.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => perform(
                context,
                () => StoreScope.of(context).setProfile({'aiConsent': true}),
              ),
              child: const Text('Разрешить передачу данных'),
            ),
          ] else ...[
            TextField(
              controller: question,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Чем помочь?',
                hintText: 'Что надеть сегодня? Что приготовить на ужин?',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : ask,
              child: Text(busy ? 'Получаю ответ…' : 'Спросить MIRA'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (suggestion != null) ...[
              const SizedBox(height: 24),
              Text(suggestion!.message),
              for (var i = 0; i < suggestion!.actions.length; i++)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(suggestion!.actions[i].preview),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: busy || applied.contains(i)
                              ? null
                              : () => apply(i),
                          child: Text(
                            applied.contains(i)
                                ? 'Применено'
                                : 'Предпросмотр и подтверждение',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
