import 'package:flutter/material.dart';
import '../../shared/widgets/common.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final name = TextEditingController();
  final modules = {'planner', 'style', 'nutrition'};
  String mode = 'planning';
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const SizedBox(height: 36),
              Text('MIRA ✦', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 12),
              Text(
                'Твой день в гармонии',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Как тебя зовут?'),
              ),
              const Section('Что тебе нужно?'),
              ...{
                'planner': 'План · события, задачи и привычки',
                'style': 'Стиль · вещи и образы',
                'nutrition': 'Питание · планы и дневник',
              }.entries.map(
                (e) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: modules.contains(e.key),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      modules.add(e.key);
                    } else {
                      modules.remove(e.key);
                    }
                  }),
                ),
              ),
              if (modules.contains('nutrition')) ...[
                const Section('Твой подход к питанию'),
                ...{
                  'planning': 'Только планирование',
                  'balance': 'Регулярные приёмы пищи',
                  'calories': 'Калории и БЖУ',
                }.entries.map(
                  (e) => CheckboxListTile(
                    title: Text(e.value),
                    value: mode == e.key,
                    onChanged: (_) => setState(() => mode = e.key),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        await perform(
                          context,
                          () => StoreScope.of(context).setProfile({
                            'name': name.text.trim(),
                            'modules': modules.toList(),
                            'nutritionMode': mode,
                            'onboarded': true,
                          }),
                        );
                        if (mounted) {
                          setState(() => busy = false);
                        }
                      },
                child: const Text('Начать мой день'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Выбранные разделы и режим можно изменить в профиле. Данные сохраняются на устройстве; облако доступно после входа.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
