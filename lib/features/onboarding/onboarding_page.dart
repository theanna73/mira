import 'package:flutter/material.dart';
import '../../app/config.dart';
import '../../shared/widgets/common.dart';
import '../profile/auth_panel.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final name = TextEditingController(),
      city = TextEditingController(),
      restrictions = TextEditingController(),
      disliked = TextEditingController();
  final modules = {'planner', 'style', 'nutrition'};
  String mode = 'planning', assistantMode = 'request';
  int step = 0;
  bool busy = false;
  final labels = [
    'Твой день в гармонии',
    'Что ты хочешь от MIRA?',
    'Расскажи немного о себе',
    'Настроим MIRA под тебя',
    'Как тебе помогать?',
    'Твоя MIRA',
  ];
  @override
  void dispose() {
    name.dispose();
    city.dispose();
    restrictions.dispose();
    disliked.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    final store = StoreScope.of(context);
    setState(() => busy = true);
    try {
      await store.setProfile({
        'name': name.text.trim(),
        'city': city.text.trim(),
        'modules': modules.toList(),
        'nutritionMode': mode,
        'preferences': restrictions.text.trim(),
        'dislikedFoods': disliked.text.trim(),
        'assistantMode': assistantMode,
        'onboarded': true,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $e')));
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Widget option(String key, String label, IconData icon, Color color) => Card(
    child: CheckboxListTile(
      secondary: CircleAvatar(
        backgroundColor: color,
        foregroundColor: const Color(0xFF454946),
        child: Icon(icon),
      ),
      title: Text(label),
      value: modules.contains(key),
      onChanged: (v) =>
          setState(() => v == true ? modules.add(key) : modules.remove(key)),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                child: Row(
                  children: [
                    if (step > 0)
                      IconButton(
                        tooltip: 'Назад',
                        onPressed: busy ? null : () => setState(() => step--),
                        icon: const Icon(Icons.chevron_left),
                      ),
                    Text(
                      '${step + 1} из 6',
                      style: const TextStyle(color: Color(0xFF858680)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (step + 1) / 6,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : finish,
                      child: const Text('Пропустить'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                  children: [
                    Text(
                      'MIRA',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: step == 0 ? 88 : 62,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 2,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      labels[step],
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 20),
                    if (step == 0) ...[
                      const Text(
                        'Планы, стиль и питание\nв одном приложении.',
                        style: TextStyle(fontSize: 19, height: 1.6),
                      ),
                      const SizedBox(height: 26),
                      OutlinedButton.icon(
                        onPressed: Config.cloudEnabled
                            ? () => sheet(context, const AuthPanel())
                            : null,
                        icon: const Icon(Icons.login),
                        label: const Text('Уже есть аккаунт? Войти'),
                      ),
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/images/welcome-hero.png',
                          height: 290,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          alignment: Alignment.bottomCenter,
                        ),
                      ),
                    ],
                    if (step == 1) ...[
                      const Text(
                        'Выбери нужные разделы. Их можно изменить позже.',
                      ),
                      const SizedBox(height: 16),
                      option(
                        'planner',
                        'Мои планы',
                        Icons.calendar_today_outlined,
                        const Color(0xFFE2EFEB),
                      ),
                      option(
                        'style',
                        'Гардероб и образы',
                        Icons.checkroom_outlined,
                        const Color(0xFFEDE5EF),
                      ),
                      option(
                        'nutrition',
                        'Питание',
                        Icons.ramen_dining_outlined,
                        const Color(0xFFF4E4DF),
                      ),
                    ],
                    if (step == 2) ...[
                      TextField(
                        controller: name,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Как к тебе обращаться?',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: city,
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Город (необязательно)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Координаты для погоды можно выбрать в профиле. Все настройки доступны после знакомства.',
                      ),
                    ],
                    if (step == 3) ...[
                      if (modules.contains('planner'))
                        const EmptyCard(
                          'План · события, задачи, привычки и отдельные списки',
                        ),
                      if (modules.contains('style'))
                        const EmptyCard(
                          'Стиль · свои вещи, образы и планирование на дату',
                        ),
                      if (modules.contains('nutrition')) ...[
                        const Section('Твой подход к питанию'),
                        for (final e in {
                          'planning': 'Планировать рацион',
                          'balance': 'Следить за регулярностью',
                          'calories': 'Калории и БЖУ',
                        }.entries)
                          CheckboxListTile(
                            title: Text(e.value),
                            value: e.key == mode,
                            onChanged: (_) => setState(() => mode = e.key),
                          ),
                        TextField(
                          controller: restrictions,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: 'Ограничения и аллергии',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: disliked,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: 'Продукты, которые не любишь',
                          ),
                        ),
                      ],
                      if (modules.isEmpty)
                        const EmptyCard(
                          'Разделы можно включить в профиле в любое время',
                        ),
                    ],
                    if (step == 4) ...[
                      const Text(
                        'MIRA AI отвечает в чате и предлагает изменения для подтверждения.',
                      ),
                      const SizedBox(height: 16),
                      for (final e in {
                        'request': 'Только по запросу',
                        'suggest': 'Предлагать варианты в ответах',
                        'together': 'Планировать вместе со мной',
                      }.entries)
                        CheckboxListTile(
                          title: Text(e.value),
                          value: e.key == assistantMode,
                          onChanged: (_) =>
                              setState(() => assistantMode = e.key),
                        ),
                      const EmptyCard(
                        'Выбранный режим задаёт стиль ответов. Автоматические рассылки не включаются. Доступ к AI разрешается отдельно при первом открытии чата.',
                      ),
                    ],
                    if (step == 5) ...[
                      Text(
                        name.text.trim().isEmpty
                            ? 'Всё настроено'
                            : 'Всё настроено, ${name.text.trim()}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      for (final e in {
                        'planner': 'План',
                        'style': 'Стиль',
                        'nutrition': 'Питание',
                      }.entries)
                        if (modules.contains(e.key))
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.check_circle_outline),
                              title: Text(e.value),
                            ),
                          ),
                      const SizedBox(height: 20),
                      const EmptyCard(
                        'Ты можешь изменить всё это в профиле. Начнём с твоего дня.',
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : step == 5
                          ? finish
                          : () => setState(() => step++),
                      child: Text(
                        busy
                            ? 'Сохраняю…'
                            : step == 5
                            ? 'Начать мой день'
                            : step == 0
                            ? 'Начать ›'
                            : 'Далее ›',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
