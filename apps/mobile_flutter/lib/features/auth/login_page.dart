import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  // V12 §17: «نسيت كلمة المرور» لا يظهر إلا بعد فشل بيانات الاعتماد.
  bool _showForgotLink = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseProvider);
      final response = await client.functions
          .invoke(
            'identifier-sign-in',
            body: {
              'identifier': _identifier.text.trim(),
              'password': _password.text,
            },
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      // الرد قد لا يكون Map (مثلاً "Invalid API key" كنص عادي من بوابة Supabase).
      final Map<String, dynamic> payload;
      final raw = response.data;
      if (raw is Map) {
        payload = Map<String, dynamic>.from(raw);
      } else {
        // نص خطأ عادي — نمرره كرسالة خام لمعالجة الأخطاء.
        final rawStr = raw?.toString() ?? '';
        throw StateError(rawStr.isNotEmpty ? rawStr : 'استجابة غير صالحة من الخادم.');
      }
      final refreshToken = payload['refresh_token'] as String?;
      if (response.status != 200 || refreshToken == null) {
        final code = payload['error'] as String?;
        // V12 §17: إظهار «نسيت كلمة المرور» فقط عند فشل بيانات الاعتماد
        // (INVALID_CREDENTIALS أو رد 401 غير TOO_MANY_ATTEMPTS).
        // لا يظهر عند: انقطاع الإنترنت / timeout / حساب معطّل / rate limit.
        if (code != 'TOO_MANY_ATTEMPTS') {
          setState(() => _showForgotLink = true);
        }
        throw AuthException(
          code == 'TOO_MANY_ATTEMPTS'
              ? 'محاولات كثيرة. انتظر قليلًا ثم حاول مرة أخرى.'
              : 'بيانات الدخول غير صحيحة أو الحساب غير متاح.',
        );
      }
      // نجاح الدخول: إخفاء الرابط.
      setState(() => _showForgotLink = false);
      await client.auth.setSession(refreshToken);
      ref.invalidate(accessContextProvider);
      if (mounted) context.go('/');
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error, stack) {
      // أخطاء الشبكة/timeout/DNS: لا يظهر «نسيت كلمة المرور» (V12 §17.2).
      if (mounted) setState(() => _error = humanizeError(error, stack));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForgotPassword() async {
    final value = _identifier.text.trim();
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ForgotPasswordDialog(initialEmail: value.contains('@') ? value : ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    scheme.primary,
                    AppColors.brandPrimaryStrong,
                    AppColors.darkSurface,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -90,
            left: -75,
            child: _GlowCircle(
              size: 260,
              color: Colors.white.withValues(alpha: .07),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -100,
            child: _GlowCircle(
              size: 360,
              color: scheme.secondary.withValues(alpha: .13),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 56,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandLogo(inverse: true, markSize: 58),
                      const SizedBox(height: 44),
                      const Text(
                        'كل يومك الإداري\nفي مكان واحد.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          height: 1.25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'الحضور والطلبات والمهام والتقييمات والقرارات حسب دورك وصلاحياتك.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .78),
                          fontSize: 14,
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Card(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: .98),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'تسجيل الدخول',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'استخدم حساب المؤسسة المصرح به.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 22),
                                if (_error != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: scheme.errorContainer,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.error_outline_rounded,
                                          color: scheme.onErrorContainer,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _error!,
                                            style: TextStyle(
                                              color: scheme.onErrorContainer,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              setState(() => _error = null),
                                          icon: const Icon(Icons.close_rounded),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                TextFormField(
                                  controller: _identifier,
                                  keyboardType: TextInputType.text,
                                  textDirection: TextDirection.ltr,
                                  autofillHints: const [AutofillHints.username],
                                  decoration: const InputDecoration(
                                    labelText: 'البريد أو الهاتف أو كود الموظف',
                                    prefixIcon: Icon(
                                      Icons.alternate_email_rounded,
                                    ),
                                  ),
                                  validator: (value) =>
                                      value != null && value.trim().length >= 2
                                      ? null
                                      : 'أدخل البريد أو الهاتف أو كود الموظف.',
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _password,
                                  obscureText: _obscurePassword,
                                  textDirection: TextDirection.ltr,
                                  autofillHints: const [AutofillHints.password],
                                  decoration: InputDecoration(
                                    labelText: 'كلمة المرور',
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'إظهار كلمة المرور'
                                          : 'إخفاء كلمة المرور',
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      value != null && value.length >= 8
                                      ? null
                                      : 'كلمة المرور لا تقل عن 8 أحرف.',
                                ),
                                // V12 §17: الرابط مخفي ابتداءً ويظهر فقط بعد فشل بيانات الاعتماد.
                                if (_showForgotLink)
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: TextButton.icon(
                                      onPressed: _loading
                                          ? null
                                          : _openForgotPassword,
                                      icon: const Icon(
                                        Icons.help_outline_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('نسيت كلمة المرور؟'),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: _loading ? null : _submit,
                                  icon: _loading
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.login_rounded),
                                  label: Text(
                                    _loading
                                        ? 'جارٍ التحقق…'
                                        : 'تسجيل الدخول بأمان',
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.shield_outlined,
                                      size: 16,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'جلسة مشفرة وصلاحيات من الخادم',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _TrustChip(
                            icon: Icons.fingerprint_rounded,
                            label: 'Passkey',
                          ),
                          SizedBox(width: 8),
                          _TrustChip(
                            icon: Icons.privacy_tip_outlined,
                            label: 'خصوصية',
                          ),
                          SizedBox(width: 8),
                          _TrustChip(
                            icon: Icons.verified_user_outlined,
                            label: 'RLS',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForgotPasswordDialog extends ConsumerStatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<_ForgotPasswordDialog> createState() =>
      _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<_ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(supabaseProvider)
          .auth
          .resetPasswordForEmail(
            _email.text.trim().toLowerCase(),
            redirectTo: AppConfig.passwordRecoveryUrl,
          );
      if (mounted) setState(() => _sent = true);
    } on AuthException {
      if (mounted) {
        setState(
          () => _error =
              'تعذر إرسال رابط الاسترداد الآن. انتظر قليلًا ثم حاول مرة أخرى.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(
        _sent ? Icons.mark_email_read_outlined : Icons.lock_reset_rounded,
        color: _sent ? AppColors.statusSuccess : scheme.primary,
        size: 36,
      ),
      title: Text(_sent ? 'تم إرسال الرابط' : 'نسيت كلمة المرور؟'),
      content: _sent
          ? const Text(
              'إذا كان البريد مسجلًا فستصلك رسالة تتضمن رابطًا آمنًا لتعيين كلمة مرور جديدة. افتح أحدث رسالة فقط.',
              textAlign: TextAlign.center,
            )
          : Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'أدخل بريدك المسجل وسنرسل رابط الاسترداد إليه.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _email,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      return RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(email)
                          ? null
                          : 'أدخل بريدًا إلكترونيًا صحيحًا.';
                    },
                    onFieldSubmitted: (_) async {
                      if (!_loading) await _send();
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
      actions: [
        if (!_sent)
          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        if (!_sent)
          FilledButton.icon(
            onPressed: _loading ? null : _send,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_loading ? 'جارٍ الإرسال…' : 'إرسال الرابط'),
          ),
        if (_sent)
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تم'),
          ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 38),
    ),
  );
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}
