import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/widgets/common.dart';

class AuthPanel extends StatefulWidget {
  const AuthPanel({super.key});
  @override
  State<AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<AuthPanel> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  bool register = false, busy = false;
  String? message;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  String get redirect => kIsWeb ? Uri.base.origin : 'app.mira://auth';
  Future<void> submit() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (register) {
        final response = await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: redirect,
        );
        if (response.session == null) {
          setState(
            () => message =
                'Подтвердите адрес по ссылке из письма, затем войдите.',
          );
        } else if (mounted) {
          Navigator.pop(context);
        }
      } else {
        await auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => message = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Сервис недоступен. Проверьте интернет и конфигурацию Supabase.',
        );
      }
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .8,
    child: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            register ? 'Создать аккаунт' : 'Войти в MIRA',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) =>
                v == null ||
                    !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())
                ? 'Введите email'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: password,
            obscureText: true,
            autofillHints: [
              register ? AutofillHints.newPassword : AutofillHints.password,
            ],
            decoration: const InputDecoration(labelText: 'Пароль'),
            validator: (v) => (v?.length ?? 0) < (register ? 8 : 1)
                ? 'Минимум ${register ? 8 : 1} символов'
                : null,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(
              busy
                  ? 'Подождите…'
                  : register
                  ? 'Зарегистрироваться'
                  : 'Войти',
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => setState(() => register = !register),
            child: Text(register ? 'Уже есть аккаунт' : 'Создать аккаунт'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    if (!RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch(email.text.trim())) {
                      setState(() => message = 'Сначала введите email');
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await Supabase.instance.client.auth.resetPasswordForEmail(
                        email.text.trim(),
                        redirectTo: redirect,
                      );
                      if (mounted) {
                        setState(
                          () => message =
                              'Если аккаунт существует, письмо для восстановления отправлено.',
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(() => message = 'Не удалось отправить письмо');
                      }
                    }
                    if (mounted) {
                      setState(() => busy = false);
                    }
                  },
            child: const Text('Забыли пароль?'),
          ),
          if (message != null) Text(message!),
          const SizedBox(height: 16),
          const Text(
            'Данные гостевого режима и аккаунта хранятся отдельно. После входа их можно перенести через профиль.',
          ),
        ],
      ),
    ),
  );
}

class RecoveryPanel extends StatefulWidget {
  const RecoveryPanel({super.key});
  @override
  State<RecoveryPanel> createState() => _RecoveryPanelState();
}

class _RecoveryPanelState extends State<RecoveryPanel> {
  final password = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Новый пароль', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Не менее 8 символов'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (password.text.length < 8) {
                    return;
                  }
                  setState(() => busy = true);
                  await perform(context, () async {
                    await Supabase.instance.client.auth.updateUser(
                      UserAttributes(password: password.text),
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  });
                  if (mounted) {
                    setState(() => busy = false);
                  }
                },
          child: const Text('Обновить пароль'),
        ),
      ],
    ),
  );
}
