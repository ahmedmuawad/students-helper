import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../common/ui_helpers.dart';

/// طرق الدخول المتاحة.
enum _Method { phone, email }

/// شاشة تسجيل الدخول.
///
/// الحساب **اختياري**: التطبيق شغّال من غيره، والحساب بيضيف المزامنة بين
/// الأجهزة ومتابعة ولي الأمر. عشان كده في زرار "أكمل من غير حساب" واضح
/// مش مخبّي في ركن.
class SignInScreen extends StatefulWidget {
  /// بتتنادى بعد نجاح الدخول أو التخطي.
  final VoidCallback? onDone;

  /// هل نسمح بالتخطي؟ (لأ لو المستخدم فتح الشاشة من الإعدادات)
  final bool allowSkip;

  const SignInScreen({super.key, this.onDone, this.allowSkip = true});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  _Method _method = _Method.phone;
  bool _registering = false;
  bool _codeSent = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيل الدخول'),
        actions: [
          if (widget.allowSkip)
            TextButton(
              onPressed: auth.isBusy ? null : _skip,
              child: const Text('من غير حساب'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            _Intro(theme: theme),
            const SizedBox(height: 20),

            if (!auth.isAvailable) ...[
              _Notice(
                icon: Icons.info_outline,
                color: theme.colorScheme.tertiary,
                title: 'تسجيل الدخول لسه مش متظبط',
                body: auth.setupProblem ??
                    'إعدادات Firebase ناقصة على النسخة دي. التطبيق شغّال '
                        'عادي، بس البيانات على الجهاز ده بس.',
              ),
              const SizedBox(height: 20),
            ],

            SegmentedButton<_Method>(
              segments: const [
                ButtonSegment(
                  value: _Method.phone,
                  icon: Icon(Icons.phone_android),
                  label: Text('موبايل'),
                ),
                ButtonSegment(
                  value: _Method.email,
                  icon: Icon(Icons.alternate_email),
                  label: Text('إيميل'),
                ),
              ],
              selected: {_method},
              onSelectionChanged: auth.isBusy
                  ? null
                  : (selection) => setState(() {
                        _method = selection.first;
                        _codeSent = false;
                        context.read<AuthState>().clearError();
                      }),
            ),
            const SizedBox(height: 20),

            Form(
              key: _formKey,
              child: _method == _Method.phone
                  ? _phoneFields(auth)
                  : _emailFields(auth),
            ),

            if (auth.lastError != null) ...[
              const SizedBox(height: 14),
              _Notice(
                icon: Icons.error_outline,
                color: theme.colorScheme.error,
                title: 'ما نفعش',
                body: auth.lastError!,
              ),
            ],

            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('أو', style: theme.textTheme.bodySmall),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),

            OutlinedButton.icon(
              onPressed:
                  auth.isBusy || !auth.isAvailable ? null : _signInWithGoogle,
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('الدخول بحساب جوجل'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),

            const SizedBox(height: 24),
            Text(
              'بياناتك بتتخزّن على سيرفر التطبيق مش عند جوجل. جوجل بتتأكد '
              'إنك انت انت وبس.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ----- الموبايل -----

  Widget _phoneFields(AuthState auth) {
    if (!_codeSent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
            decoration: const InputDecoration(
              labelText: 'رقم الموبايل',
              hintText: '01xxxxxxxxx',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (value) {
              final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
              if (digits.length < 10) return 'اكتب رقم الموبايل كامل';
              return null;
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed:
                auth.isBusy || !auth.isAvailable ? null : _sendCode,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: auth.isBusy
                ? const _Spinner()
                : const Text('ابعتلي كود'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'بعتنا كود لـ ${_phone.text.trim()}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _code,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'الكود',
            counterText: '',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
          validator: (value) =>
              (value ?? '').trim().length < 6 ? 'الكود ٦ أرقام' : null,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: auth.isBusy ? null : _confirmCode,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: auth.isBusy ? const _Spinner() : const Text('تأكيد'),
        ),
        TextButton(
          onPressed: auth.isBusy
              ? null
              : () => setState(() {
                    _codeSent = false;
                    _code.clear();
                  }),
          child: const Text('غيّر الرقم أو اطلب كود تاني'),
        ),
      ],
    );
  }

  // ----- الإيميل -----

  Widget _emailFields(AuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_registering) ...[
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'الاسم',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'اكتب اسمك' : null,
          ),
          const SizedBox(height: 14),
        ],
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'الإيميل',
            prefixIcon: Icon(Icons.alternate_email),
          ),
          validator: (value) {
            final text = (value ?? '').trim();
            if (!text.contains('@') || !text.contains('.')) {
              return 'الإيميل مش مكتوب صح';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _password,
          obscureText: !_showPassword,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: 'كلمة السر',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          validator: (value) =>
              (value ?? '').length < 6 ? '٦ حروف على الأقل' : null,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: auth.isBusy || !auth.isAvailable ? null : _submitEmail,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: auth.isBusy
              ? const _Spinner()
              : Text(_registering ? 'اعمل حساب' : 'دخول'),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: auth.isBusy
                  ? null
                  : () => setState(() => _registering = !_registering),
              child: Text(_registering ? 'عندي حساب' : 'اعمل حساب جديد'),
            ),
            if (!_registering)
              TextButton(
                onPressed: auth.isBusy ? null : _resetPassword,
                child: const Text('نسيت كلمة السر'),
              ),
          ],
        ),
      ],
    );
  }

  // ----- الأفعال -----

  void _skip() {
    final done = widget.onDone;
    if (done != null) {
      done();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _sendCode() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthState>();
    await auth.sendPhoneCode(
      _phone.text,
      onCodeSent: () {
        if (mounted) setState(() => _codeSent = true);
      },
    );
  }

  Future<void> _confirmCode() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await context.read<AuthState>().confirmPhoneCode(_code.text);
    if (ok) _finish();
  }

  Future<void> _submitEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthState>();
    final ok = _registering
        ? await auth.registerWithEmail(
            _email.text, _password.text, _name.text)
        : await auth.signInWithEmail(_email.text, _password.text);
    if (ok) _finish();
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showSnack(context, 'اكتب إيميلك الأول');
      return;
    }
    final ok = await context.read<AuthState>().sendPasswordReset(email);
    if (ok && mounted) {
      showSnack(context, 'بعتنا لينك على إيميلك');
    }
  }

  Future<void> _signInWithGoogle() async {
    final ok = await context.read<AuthState>().signInWithGoogle();
    if (ok) _finish();
  }

  void _finish() {
    if (!mounted) return;
    showSnack(context, 'أهلاً بيك — بياناتك هتتزامن دلوقتي');
    final done = widget.onDone;
    if (done != null) {
      done();
    } else {
      Navigator.of(context).maybePop();
    }
  }
}

class _Intro extends StatelessWidget {
  final ThemeData theme;

  const _Intro({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.cloud_sync_outlined,
            size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          'خلّي بياناتك معاك في أي مكان',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'بحساب، جدولك ودروسك ومهامك بتتحفظ على السيرفر وبترجع لو غيّرت '
          'التليفون — وولي أمرك يقدر يتابعك لو انت سمحت.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}
