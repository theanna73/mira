import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/config.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/chat_message.dart';
import '../../services/database/document.dart';
import '../../services/weather/weather_service.dart';
import '../models/entry.dart';
import 'common.dart';

typedef ChatRequest =
    Future<AiSuggestion> Function(
      String question,
      String module,
      String date,
      MiraDocument document,
      Map<String, dynamic>? weather,
      List<ChatMessage> history,
    );

class AiPanel extends StatefulWidget {
  final String module;
  final ChatRequest? request;
  const AiPanel({super.key, required this.module, this.request});
  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  final question = TextEditingController();
  final scroll = ScrollController();
  bool busy = false;
  String? error, visibleScope;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = StoreScope.of(context).scope;
    if (visibleScope != scope) {
      visibleScope = scope;
      generation++;
      busy = false;
      question.clear();
      error = null;
      scrollToEnd();
    }
  }

  @override
  void dispose() {
    question.dispose();
    scroll.dispose();
    super.dispose();
  }

  void scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> ask({bool retry = false}) async {
    if (busy) return;
    final store = StoreScope.of(context);
    final scope = store.scope;
    final requestGeneration = generation;
    final last = store.document.chat.lastOrNull;
    final text = retry && last?.role == 'user'
        ? last!.content
        : question.text.trim();
    if (text.isEmpty || text.length > 2000) {
      setState(() => error = 'Введите сообщение до 2000 символов');
      return;
    }
    if (store.profile['aiConsent'] != true || !store.ready) return;
    final previous = List<ChatMessage>.from(store.document.chat);
    if (retry && previous.lastOrNull?.role == 'user') previous.removeLast();
    final history = previous.skip(math.max(0, previous.length - 16)).toList();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!retry) {
        await store.mutate((d) {
          if (store.scope != scope || d.profile['aiConsent'] != true) {
            throw StateError('Аккаунт изменился');
          }
          d.addMessage(ChatMessage(role: 'user', content: text));
        });
        if (mounted) question.clear();
      }
      scrollToEnd();
      final pendingId = store.document.chat.last.id;
      final snapshot = store.document.clone();
      Map<String, dynamic>? weather;
      if (widget.request == null) {
        try {
          weather = await WeatherService().context(snapshot.profile);
        } catch (_) {
          /* Optional current weather. */
        }
      }
      if (store.scope != scope ||
          !store.ready ||
          store.profile['aiConsent'] != true) {
        return;
      }
      final answer = widget.request != null
          ? await widget.request!(
              text,
              widget.module,
              dayKey(DateTime.now()),
              snapshot,
              weather,
              history,
            )
          : await AiService(Supabase.instance.client).ask(
              text,
              widget.module,
              dayKey(DateTime.now()),
              snapshot,
              weather,
              history: history,
            );
      if (store.scope != scope ||
          !store.ready ||
          store.profile['aiConsent'] != true) {
        return;
      }
      await store.mutate((d) {
        if (store.scope != scope ||
            d.profile['aiConsent'] != true ||
            d.chat.lastOrNull?.id != pendingId) {
          throw const FormatException(
            'Диалог изменился. Отправьте сообщение заново.',
          );
        }
        d.addMessage(
          ChatMessage(
            role: 'assistant',
            content: answer.message,
            actions: answer.actions.map((a) => a.toJson()).toList(),
          ),
        );
      });
      scrollToEnd();
    } catch (e) {
      if (mounted && store.scope == scope) {
        setState(() => error = aiErrorMessage(e));
      }
    } finally {
      if (mounted && generation == requestGeneration) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> apply(ChatMessage message, int index) async {
    if (busy) return;
    final store = StoreScope.of(context);
    final scope = store.scope;
    final action = AiAction.fromJson(message.actions[index]);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await confirm(
            context,
            'Применить предложение?',
            action.details(store.document),
          ) ||
          !mounted) {
        return;
      }
      await store.mutate((d) {
        if (store.scope != scope ||
            d.profile['aiConsent'] != true ||
            d.chat.lastOrNull?.id != message.id) {
          throw const FormatException(
            'Получите новое предложение в текущем диалоге.',
          );
        }
        final current = d.chat.last;
        if (current.applied.contains(index)) return;
        action.apply(d);
        d.chat[d.chat.length - 1] = current.markApplied(index);
      });
    } catch (e) {
      if (mounted && store.scope == scope) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Не удалось сохранить предложение. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> clearChat() async {
    if (busy) return;
    final store = StoreScope.of(context);
    final scope = store.scope;
    setState(() => busy = true);
    try {
      if (!await confirm(
            context,
            'Очистить переписку?',
            'История диалога будет удалена. Созданные задачи, образы и планы останутся.',
          ) ||
          !mounted) {
        return;
      }
      await store.mutate((d) {
        if (store.scope != scope) throw StateError('Аккаунт изменился');
        d.chat.clear();
      });
      if (mounted) setState(() => error = null);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final available =
        widget.request != null ||
        (Config.cloudEnabled &&
            Supabase.instance.client.auth.currentUser != null);
    final consent = store.profile['aiConsent'] == true;
    final messages = store.document.chat;
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final height = math.max(
      120.0,
      math.min(
        media.size.height * .92,
        media.size.height - media.viewInsets.bottom - media.padding.top,
      ),
    );
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'MIRA AI',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Очистить переписку',
                  onPressed: busy || messages.isEmpty
                      ? null
                      : () => perform(context, clearChat),
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  tooltip: 'Закрыть чат',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: !available
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Войдите в аккаунт в разделе «Я», чтобы общаться с MIRA. Для AI требуется подключение Supabase.',
                      ),
                    ),
                  )
                : !consent
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text(
                        'MIRA поможет с планами, гардеробом и питанием. Текст переписки и контекст этих разделов будут переданы AI-провайдеру. Фотографии не передаются. Разрешение можно отключить в профиле.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => perform(
                          context,
                          () => store.setProfile({'aiConsent': true}),
                        ),
                        child: const Text('Разрешить и начать чат'),
                      ),
                    ],
                  )
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (messages.isEmpty) ...[
                        Text(
                          'Чем помочь сегодня?',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Обсудим планы, соберём образ или выберем еду. Можно задавать уточнения. Изменения сохраняются после вашего подтверждения.',
                        ),
                        const SizedBox(height: 20),
                        for (final prompt in [
                          'Помоги спланировать завтра',
                          'Подбери образ из моего гардероба',
                          'Что приготовить на ужин?',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      question.text = prompt;
                                      ask();
                                    },
                              child: Text(prompt),
                            ),
                          ),
                      ],
                      for (final message in messages) ...[
                        Align(
                          alignment: message.role == 'user'
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 580),
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: message.role == 'user'
                                  ? colors.primaryContainer
                                  : colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.role == 'user' ? 'Вы' : 'MIRA',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                                const SizedBox(height: 6),
                                SelectableText(message.content),
                                for (var i = 0; i < message.actions.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AiAction.fromJson(
                                            message.actions[i],
                                          ).details(store.document),
                                        ),
                                        const SizedBox(height: 8),
                                        FilledButton.tonal(
                                          onPressed:
                                              busy ||
                                                  message.applied.contains(i) ||
                                                  message.id != messages.last.id
                                              ? null
                                              : () => apply(message, i),
                                          child: Text(
                                            message.applied.contains(i)
                                                ? 'Сохранено'
                                                : message.id != messages.last.id
                                                ? 'Предложение из предыдущего ответа'
                                                : 'Посмотреть и подтвердить',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (busy)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('MIRA отвечает…'),
                        ),
                    ],
                  ),
          ),
          if (available && consent) ...[
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(error!, style: TextStyle(color: colors.error)),
              ),
            if (!busy && messages.lastOrNull?.role == 'user')
              TextButton(
                onPressed: () => ask(retry: true),
                child: const Text('Повторить запрос'),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: question,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        hintText: 'Напишите MIRA…',
                        counterText: '',
                      ),
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Отправить',
                    onPressed: busy ? null : () => ask(),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
