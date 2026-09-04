import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shown after the user clicks the activation / password-recovery email link
/// and the app opens via deep link. The Supabase session is already active
/// (PASSWORD_RECOVERY event fired), so we just call updateUser with the new
/// password and let authSessionProvider refresh the gate.
class SetPasswordPage extends ConsumerStatefulWidget {
  const SetPasswordPage({super.key});

  @override
  ConsumerState<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends ConsumerState<SetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseProvider);

      // 0457: تحقق من قوة كلمة المرور على الخادم أولاً
      final strengthResult = await client
          .rpc<Map<String, dynamic>>('validate_password_strength',
              params: {'p_password': _password.text})
          .timeout(const Duration(seconds: 10));
      final valid = strengthResult['valid'] == true;
      if (!valid) {
        final issues = (strengthResult['issues'] as List<dynamic>?)
                ?.map((e) => '• $e')
                .join('\n') ??
            '';
        if (mounted) {
          setState(() => _error =
              'كلمة المرور لا تلبي متطلبات الأمان:\n$issues');
        }
        return;
      }

      await client.auth.updateUser(
        UserAttributes(password: _password.text),
      );

      // try بعد التحديث مباشرة — أحياناً يفشل التفعيل إذا الطلب أبطأ من المعتاد
      // لكن نحتاج التعامل مع no_employee_record بشكل سلس
      final raw = await client.rpc<dynamic>('activate_employee_after_first_login')
          .timeout(const Duration(seconds: 15));
      if (raw == null) {
        throw StateError('تعذر تفعيل سجل الموظف — الخادم لم يستجب. تواصل مع مسؤول النظام.');
      }
      final activation = Map<String, dynamic>.from(raw as Map<dynamic, dynamic>);
      // 0457: قبول no_employee_record كما هو — كلمة المرور تم تعيينها بالفعل عبر GoTrue
      final activationAccepted = activation['activated'] == true ||
          activation['reason'] == 'already_active' ||
          activation['reason'] == 'no_employee_record';
      if (!activationAccepted) {
        throw StateError('تعذر تفعيل سجل الموظف. تواصل مع مسؤول النظام.');
      }
      // SEC: إزالة علامة must_change_password من app_metadata عبر SECURITY DEFINER
      try {
        await client.rpc<dynamic>('clear_must_change_password')
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // ثانوي — كلمة المرور تم تعيينها بنجاح
      }
      if (mounted) setState(() => _done = true);
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('session') ||
          msg.contains('expired') ||
          msg.contains('not found') ||
          msg.contains('token')) {
        if (mounted) {
          setState(() => _error =
              'انتهت صلاحية رابط التفعيل. اطلب رابطًا جديدًا من مسؤول الموارد البشرية.');
        }
      } else if (msg.contains('reauthentication') ||
          msg.contains('recent login')) {
        if (mounted) {
          setState(() => _error =
              'يجب إعادة تسجيل الدخول قبل تغيير كلمة المرور. سجّل الدخول ثم أعد المحاولة.');
        }
      } else {
        if (mounted) setState(() => _error = humanizeError(e));
      }
    } catch (e, stack) {
      if (mounted) setState(() => _error = humanizeError(e, stack));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _done ? _buildDone(scheme) : _buildForm(scheme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDone(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline_rounded,
            size: 72, color: scheme.primary),
        const SizedBox(height: 20),
        const Text(
          'تم تفعيل حسابك',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'تم تعيين كلمة المرور بنجاح. سيتم توجيهك للتطبيق تلقائياً.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.7),
        ),
      ],
    );
  }

  Widget _buildForm(ColorScheme scheme) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandLogo(markSize: 56),
          const SizedBox(height: 24),
          Text(
            'تعيين كلمة المرور',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: scheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'أدخل كلمة مرور جديدة لتفعيل حسابك.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: _password,
            obscureText: _obscure1,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'كلمة المرور الجديدة',
              helperText: '8 أحرف على الأقل (أحرف وأرقام سهلة ومقبولة)',
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure1
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure1 = !_obscure1),
              ),
            ),
            validator: (value) {
              final pass = value ?? '';
              if (pass.length < 8) return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل.';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirm,
            obscureText: _obscure2,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'تأكيد كلمة المرور',
              prefixIcon: const Icon(Icons.lock_reset_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure2
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure2 = !_obscure2),
              ),
            ),
            validator: (value) {
              if ((value ?? '') != _password.text) return 'كلمتا المرور غير متطابقتين.';
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: scheme.onErrorContainer),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : () async => _submit(),
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('تفعيل الحساب'),
          ),
        ],
      ),
    );
  }
}
