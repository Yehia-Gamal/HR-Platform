import 'dart:async';

import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/session_cleanup.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shown after the user clicks the activation / password-recovery email link,
/// or if an admin requires them to change their password on first login.
///
/// Provides full exit controls (sign out / cancel) so an employee is never trapped,
/// immediately checks if must_change_password was already cleared in the backend,
/// and refreshes the Supabase auth session after updating the password so the app
/// unlocks immediately.
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
  Timer? _autoRedirectTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfAlreadyCleared();
    });
  }

  @override
  void dispose() {
    _autoRedirectTimer?.cancel();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Checks if the backend has already removed `must_change_password`.
  /// If so, invalidates providers so AppGate immediately advances into the workspace.
  Future<void> _checkIfAlreadyCleared() async {
    try {
      final client = ref.read(supabaseProvider);
      final session = client.auth.currentSession;
      if (session == null) return;

      final refreshed = await client.auth.refreshSession();
      final user = refreshed.user ?? client.auth.currentUser;
      final mustChange = user?.appMetadata['must_change_password'] == true;
      final isRecovery = ref.read(passwordRecoveryActiveProvider).value == true;

      if (!mustChange && !isRecovery && mounted) {
        ref.invalidate(authSessionProvider);
        ref.invalidate(accessContextProvider);
      }
    } catch (_) {
      // Best-effort check on mount; ignore transient network drops.
    }
  }

  /// Escape hatch: logs out cleanly and returns the user to the login screen.
  Future<void> _signOut() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseProvider);
      final userId = client.auth.currentUser?.id;
      await cleanupOnSignOut(userId: userId);
      await client.auth.signOut();
      ref.invalidate(authSessionProvider);
      ref.invalidate(accessContextProvider);
    } catch (e) {
      if (mounted) setState(() => _error = humanizeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Moves into the main application by refreshing providers.
  void _proceedToApp() {
    _autoRedirectTimer?.cancel();
    ref.invalidate(authSessionProvider);
    ref.invalidate(accessContextProvider);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
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
      try {
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
      } catch (e) {
        // Fallback: local length validation if RPC fails or is unreachable
        if (_password.text.length < 8) {
          if (mounted) {
            setState(() => _error = 'كلمة المرور يجب أن تكون 8 أحرف على الأقل.');
          }
          return;
        }
      }

      await client.auth.updateUser(
        UserAttributes(password: _password.text),
      );

      // تفعيل سجل الموظف بعد أول تسجيل دخول
      try {
        final raw = await client.rpc<dynamic>('activate_employee_after_first_login')
            .timeout(const Duration(seconds: 15));
        if (raw != null) {
          final activation = Map<String, dynamic>.from(raw as Map<dynamic, dynamic>);
          final activationAccepted = activation['activated'] == true ||
              activation['reason'] == 'already_active' ||
              activation['reason'] == 'no_employee_record';
          if (!activationAccepted) {
            debugPrint('[SetPassword] Notice: activation status: ${activation['reason']}');
          }
        }
      } catch (e) {
        debugPrint('[SetPassword] Warning on activation RPC: $e');
      }

      // SEC: إزالة علامة must_change_password من app_metadata عبر SECURITY DEFINER
      try {
        await client.rpc<dynamic>('clear_must_change_password')
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[SetPassword] Warning on clear_must_change_password: $e');
      }

      // CRITICAL: Refresh Supabase session to update local JWT app_metadata!
      try {
        await client.auth.refreshSession().timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('[SetPassword] Session refresh: $e');
      }

      ref.invalidate(authSessionProvider);
      ref.invalidate(accessContextProvider);

      if (mounted) {
        setState(() => _done = true);
        // Automatic redirection after 1.5 seconds
        _autoRedirectTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) {
            _proceedToApp();
          }
        });
      }
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _done ? 'اكتمال التفعيل' : 'أمان الحساب',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (!_done)
            TextButton.icon(
              onPressed: _loading ? null : _signOut,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('تسجيل الخروج'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
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
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_rounded,
            size: 64,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'تم تفعيل الحساب بنجاح',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'تم تعيين كلمة المرور الجديدة وتحديث بيانات الأمان بنجاح. سيتم توجيهك للتطبيق تلقائياً...',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: _proceedToApp,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('الدخول للتطبيق الآن'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
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
          const SizedBox(height: 20),
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
            'أدخل كلمة مرور جديدة للبدء في استخدام التطبيق.',
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
              helperText: '8 أحرف على الأقل',
              helperMaxLines: 1,
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
            const SizedBox(height: 16),
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
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'حفظ والدخول للتطبيق',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _signOut,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('إلغاء وتسجيل الخروج'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
