import 'dart:async';

import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/auth/login_page.dart';
import 'package:ahla_shabab_management_os/features/auth/set_password_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/release_governance.dart';
import 'package:ahla_shabab_management_os/features/workspaces/committee_workspace.dart';
import 'package:ahla_shabab_management_os/features/workspaces/employee_workspace.dart';
import 'package:ahla_shabab_management_os/features/workspaces/executive_workspace.dart';
import 'package:ahla_shabab_management_os/features/workspaces/manager_workspace.dart';
import 'package:ahla_shabab_management_os/features/workspaces/operations_workspace.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activate connectivity-aware auto-refresh (P0-21).
    ref.watch(connectivityRefreshProvider);
    // Non-production escape hatch: skip the release-gate network check entirely
    // (e.g. UI previews on web without a live backend).
    if (AppConfig.releaseGateBypassed) {
      return const _AuthenticatedGate();
    }
    final release = ref.watch(releasePolicyProvider);
    return release.when(
      loading: () => const _LoadingPage(label: 'جارٍ التحقق من إصدار التطبيق…'),
      error: (_, _) => _ReleaseCheckError(
        message: 'تعذر التحقق من صلاحية الإصدار الآن. تحقق من الاتصال وأعد المحاولة.',
        allowTemporaryContinue: AppConfig.environment != 'production',
        onRetry: () => ref.invalidate(releasePolicyProvider),
      ),
      data: (policy) {
        if (policy.blocksApplication) {
          return _ReleaseStatusPage(
            policy: policy,
            onRetry: () => ref.invalidate(releasePolicyProvider),
          );
        }
        return const _AuthenticatedGate();
      },
    );
  }
}

class _AuthenticatedGate extends ConsumerWidget {
  const _AuthenticatedGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void signOut() {
      ref.read(supabaseProvider).auth.signOut();
      ref.invalidate(authSessionProvider);
      ref.invalidate(accessContextProvider);
    }

    final recoveryAsync = ref.watch(passwordRecoveryActiveProvider);
    if (recoveryAsync.value == true) return const SetPasswordPage();

    final session = ref.watch(authSessionProvider);
    final connectivity = ref.watch(connectivityProvider);

    return session.when(
      loading: () => _TimedLoadingPage(
        label: 'جارٍ استعادة الجلسة…',
        timeout: const Duration(seconds: 15),
        onRetry: () {
          ref.invalidate(authSessionProvider);
          ref.invalidate(accessContextProvider);
        },
        onSignOut: signOut,
      ),
      error: (_, _) => _ErrorPage(
        message: 'تعذر استعادة جلسة الدخول بأمان. أعد تسجيل الدخول.',
        onRetry: () {
          ref.invalidate(authSessionProvider);
          ref.invalidate(accessContextProvider);
        },
        onSignOut: signOut,
      ),
      data: (value) {
        if (value == null) {
          // P0-20: If offline, show connection error instead of login page.
          // Prevents silent logout on temporary DNS/network failure.
          if (connectivity == ConnectivityState.offline ||
              connectivity == ConnectivityState.reconnecting) {
            return _ErrorPage(
              isOffline: true,
              message: 'انقطع الاتصال بالخادم. تحقق من الشبكة وأعد المحاولة.',
              onRetry: () {
                ref.invalidate(authSessionProvider);
                ref.invalidate(accessContextProvider);
              },
            );
          }
          return const LoginPage();
        }
        if (value.user.userMetadata?['must_change_password'] == true) {
          return const SetPasswordPage();
        }
        // Device registration is non-blocking for the UI but remains observable in Riverpod.
        ref.watch(deviceRegistrationProvider);
        final access = ref.watch(accessContextProvider);
        return access.when(
          loading: () => _TimedLoadingPage(
            label: 'جارٍ تحميل الصلاحيات…',
            timeout: const Duration(seconds: 20),
            onRetry: () => ref.invalidate(accessContextProvider),
            onSignOut: signOut,
          ),
          error: (_, _) => _ErrorPage(
            message: 'تعذر تحميل صلاحيات الحساب. تحقق من الاتصال وأعد المحاولة.',
            onRetry: () => ref.invalidate(accessContextProvider),
            onSignOut: signOut,
          ),
          data: (contextData) {
            if (contextData == null) return const LoginPage();
            return switch (_mobileWorkspace(contextData)) {
              WorkspaceId.executive => ExecutiveWorkspace(access: contextData),
              WorkspaceId.manager => ManagerWorkspace(access: contextData),
              WorkspaceId.fieldOperations =>
                OperationsWorkspace(access: contextData),
              WorkspaceId.committee => CommitteeWorkspace(access: contextData),
              WorkspaceId.employee => EmployeeWorkspace(access: contextData),
              _ => _WebOnlyPage(access: contextData),
            };
          },
        );
      },
    );
  }

  WorkspaceId? _mobileWorkspace(AccessContext context) {
    if (context.workspaces.contains(WorkspaceId.executive)) {
      return WorkspaceId.executive;
    }
    // السكرتير التنفيذي / الأدمن — يرى مساحة المدير (ليس التنفيذية).
    // يشوف البصمة + الطلبات + KPI حسب صلاحياته، بدون لوحة القيادة التنفيذية.
    if (context.workspaces.contains(WorkspaceId.mainAdmin)) {
      return WorkspaceId.manager;
    }
    if (context.workspaces.contains(WorkspaceId.fieldOperations)) {
      return WorkspaceId.fieldOperations;
    }
    // مدير HR — يرى مساحة المدير (فريقي + الطلبات + KPI)
    if (context.workspaces.contains(WorkspaceId.hr)) {
      return WorkspaceId.manager;
    }
    if (context.workspaces.contains(WorkspaceId.manager)) {
      return WorkspaceId.manager;
    }
    if (context.workspaces.contains(WorkspaceId.committee)) {
      return WorkspaceId.committee;
    }
    if (context.workspaces.contains(WorkspaceId.employee)) {
      return WorkspaceId.employee;
    }
    return null;
  }
}

class _ReleaseStatusPage extends StatelessWidget {
  const _ReleaseStatusPage({required this.policy, required this.onRetry});
  final MobileReleasePolicy policy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final blocked = policy.action == MobileReleaseAction.blocked;
    final maintenance = policy.action == MobileReleaseAction.maintenance;
    final icon = blocked
        ? Icons.phonelink_erase_outlined
        : maintenance
        ? Icons.engineering_outlined
        : Icons.system_update_alt;
    final title = blocked
        ? 'تم إبطال هذا الجهاز'
        : maintenance
        ? 'النظام تحت الصيانة'
        : 'يجب تحديث التطبيق';
    final defaultMessage = blocked
        ? 'تم إيقاف هذا التثبيت لأسباب أمنية. تواصل مع مسؤول النظام.'
        : maintenance
        ? 'نعمل على تحديث النظام. أعد المحاولة بعد قليل.'
        : 'هذه النسخة لم تعد مدعومة. حدّث التطبيق للمتابعة بأمان.';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 64),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        policy.messageAr ?? defaultMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(height: 1.7),
                      ),
                      const SizedBox(height: 12),
                      if (policy.action == MobileReleaseAction.updateRequired)
                        Text(
                          'نسختك ${policy.currentVersion}+${policy.currentBuild} · الحد الأدنى ${policy.minSupportedVersion}+${policy.minSupportedBuild}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 22),
                      if (policy.action == MobileReleaseAction.updateRequired &&
                          policy.storeUrl != null)
                        FilledButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(policy.storeUrl!),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('فتح صفحة التحديث'),
                        ),
                      const SizedBox(height: 10),
                      if (!blocked)
                        OutlinedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة التحقق'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReleaseCheckError extends ConsumerWidget {
  const _ReleaseCheckError({
    required this.message,
    required this.allowTemporaryContinue,
    required this.onRetry,
  });
  final String message;
  final bool allowTemporaryContinue;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandLogo(compact: true, markSize: 40),
                  const SizedBox(height: 36),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: .10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cloud_off_rounded,
                      size: 46,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'تعذر التحقق من حالة الإصدار',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'تحقق من الإنترنت ثم أعد المحاولة.\nلا تُعرض بيانات العمل قبل اجتياز بوابة الإصدار.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.7,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
                  if (allowTemporaryContinue) ...[
                    const SizedBox(height: 14),
                    Text(
                      'بيئة غير إنتاجية: يمكن لفريق التطوير تعطيل بوابة الإصدار مؤقتًا عبر إعداد البيئة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(compact: true, markSize: 40),
            const SizedBox(height: 40),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

/// صفحة الخطأ/انقطاع الاتصال — تصميم حديث مع إعادة محاولة تلقائية عند عودة الاتصال.
class _ErrorPage extends ConsumerStatefulWidget {
  const _ErrorPage({
    required this.message,
    this.onRetry,
    this.onSignOut,
    this.isOffline = false,
  });
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;
  final bool isOffline;

  @override
  ConsumerState<_ErrorPage> createState() => _ErrorPageState();
}

class _ErrorPageState extends ConsumerState<_ErrorPage>
    with SingleTickerProviderStateMixin {
  bool _autoRetrying = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // إعادة محاولة تلقائية عند عودة الاتصال.
    ref.listen<ConnectivityState>(connectivityProvider, (prev, next) {
      if ((prev == ConnectivityState.offline ||
              prev == ConnectivityState.serverUnavailable) &&
          (next == ConnectivityState.reconnecting ||
              next == ConnectivityState.online)) {
        if (widget.onRetry != null && !_autoRetrying) {
          setState(() => _autoRetrying = true);
          _pulseController.repeat();
          widget.onRetry!();
        }
      }
    });

    final iconData = widget.isOffline
        ? Icons.wifi_off_rounded
        : Icons.cloud_off_rounded;
    final iconColor = widget.isOffline
        ? Colors.orange.shade700
        : scheme.error;
    final iconBgColor = widget.isOffline
        ? Colors.orange.withValues(alpha: isDark ? .15 : .10)
        : scheme.errorContainer.withValues(alpha: isDark ? .4 : .35);
    final title = _autoRetrying
        ? 'جارٍ إعادة الاتصال…'
        : widget.isOffline
            ? 'لا يوجد اتصال'
            : 'انقطع الاتصال';
    final subtitle = _autoRetrying
        ? 'تم اكتشاف عودة الشبكة، يُعاد تحميل البيانات…'
        : widget.message;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // الشعار
                  const BrandLogo(compact: true, markSize: 40),
                  const SizedBox(height: 40),

                  // الأيقونة داخل دائرة ملونة
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = _autoRetrying
                          ? 1.0 + (_pulseController.value * 0.06)
                          : 1.0;
                      return Transform.scale(scale: scale, child: child);
                    },
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: _autoRetrying
                            ? scheme.primaryContainer.withValues(alpha: .5)
                            : iconBgColor,
                        shape: BoxShape.circle,
                      ),
                      child: _autoRetrying
                          ? Padding(
                              padding: const EdgeInsets.all(28),
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: scheme.primary,
                              ),
                            )
                          : Icon(iconData, size: 48, color: iconColor),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // العنوان
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      title,
                      key: ValueKey(title),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // الوصف
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      subtitle,
                      key: ValueKey(subtitle),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        height: 1.7,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  // الأزرار — تختفي عند إعادة المحاولة التلقائية
                  if (!_autoRetrying) ...[
                    const SizedBox(height: 32),
                    if (widget.onRetry != null)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ),
                    if (widget.onSignOut != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: widget.onSignOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('تسجيل الخروج'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// صفحة تحميل تُظهر أزرار إعادة المحاولة وتسجيل الخروج بعد مهلة زمنية
/// لمنع تعليق المستخدم على سبينر بلا نهاية.
class _TimedLoadingPage extends StatefulWidget {
  const _TimedLoadingPage({
    required this.label,
    required this.timeout,
    this.onRetry,
    this.onSignOut,
  });
  final String label;
  final Duration timeout;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  State<_TimedLoadingPage> createState() => _TimedLoadingPageState();
}

class _TimedLoadingPageState extends State<_TimedLoadingPage> {
  bool _showFallback = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.timeout, () {
      if (mounted) setState(() => _showFallback = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandLogo(compact: true, markSize: 40),
                const SizedBox(height: 40),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(widget.label),
                if (_showFallback) ...[
                  const SizedBox(height: 24),
                  Text(
                    'يبدو أن العملية تأخرت. جرّب الخيارات التالية:',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  if (widget.onRetry != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: widget.onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ),
                  if (widget.onSignOut != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onSignOut,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('تسجيل الخروج'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WebOnlyPage extends ConsumerWidget {
  const _WebOnlyPage({required this.access});
  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    void signOut() {
      ref.read(supabaseProvider).auth.signOut();
      ref.invalidate(authSessionProvider);
      ref.invalidate(accessContextProvider);
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandLogo(compact: true, markSize: 40),
                  const SizedBox(height: 36),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: .4),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.desktop_windows_outlined,
                      size: 46,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'مساحة العمل على الويب فقط',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'مرحبًا ${access.displayName}',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'صلاحياتك الحالية متاحة فقط على لوحة الويب.\nاستخدم المتصفح للوصول إلى النظام.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.7,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('تسجيل الخروج'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
