import 'dart:async';

import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:ahla_shabab_management_os/core/network/session_cleanup.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/auth/login_page.dart';
import 'package:ahla_shabab_management_os/features/auth/set_password_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/release_governance.dart';
import 'package:ahla_shabab_management_os/features/workspaces/employee_workspace.dart';
import 'package:ahla_shabab_management_os/features/workspaces/executive_workspace.dart';
import 'package:ahla_shabab_management_os/features/workspaces/manager_workspace.dart';
import 'package:ahla_shabab_management_os/features/workspaces/operations_workspace.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      // لا نحجب التطبيق أثناء التحقق أو عند تعذّره — قد يكون المستخدم دون
      // شبكة موثوقة، وإيقافه قبل صفحة الدخول تجربة سيئة. التحقق يجري في
      // الخلفية؛ نحجب فقط إذا قرر الخادم صراحةً (تحديث إلزامي/صيانة/تعطيل).
      loading: () => const _AuthenticatedGate(),
      error: (_, _) => const _AuthenticatedGate(),
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

class _AuthenticatedGate extends ConsumerStatefulWidget {
  const _AuthenticatedGate();

  @override
  ConsumerState<_AuthenticatedGate> createState() => _AuthenticatedGateState();
}

class _AuthenticatedGateState extends ConsumerState<_AuthenticatedGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  Future<void> _handleAppResumed() async {
    try {
      final supabase = ref.read(supabaseProvider);
      final session = supabase.auth.currentSession;
      if (session != null) {
        final expiresAt = session.expiresAt;
        final isExpiredOrExpiringSoon = session.isExpired ||
            (expiresAt != null &&
                DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
                    .isBefore(DateTime.now().add(const Duration(minutes: 10))));

        if (isExpiredOrExpiringSoon) {
          try {
            await supabase.auth.refreshSession();
            if (mounted) {
              ref.invalidate(authSessionProvider);
              ref.invalidate(accessContextProvider);
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[AppGate] Proactive resume token refresh failed: $e');
            }
          }
        }

        // Re-affirm FCM token registration in background
        try {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null && token.isNotEmpty) {
            final platform = defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android';
            await supabase.rpc<dynamic>(
              'upsert_my_push_token',
              params: {'p_fcm_token': token, 'p_platform': platform},
            );
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final supabase = ref.read(supabaseProvider);

    void signOut() {
      cleanupOnSignOut(userId: supabase.auth.currentUser?.id);
      supabase.auth.signOut();
      ref.invalidate(authSessionProvider);
      ref.invalidate(accessContextProvider);
    }

    final recoveryAsync = ref.watch(passwordRecoveryActiveProvider);
    if (recoveryAsync.value == true) return const SetPasswordPage();

    final session = ref.watch(authSessionProvider);
    final connectivity = ref.watch(connectivityProvider);
    // 0471-UX: عند انقطاع الشبكة لا معنى لعرض «تسجيل الخروج» — الحل هو
    // إعادة المحاولة بعد عودة الاتصال. الخروج يُعرض فقط عند اتصال سليم
    // (أي أن المشكلة في الجلسة نفسها لا في الشبكة).
    final offlineLike = connectivity == ConnectivityState.offline ||
        connectivity == ConnectivityState.reconnecting ||
        connectivity == ConnectivityState.serverUnavailable;

    // 0471-UX: عند عودة الاتصال بعد انقطاع، نعيد تحميل الصلاحيات تلقائيًا
    // إن كانت في حالة خطأ — بدل ترك المستخدم أمام زر إعادة المحاولة.
    ref.listen(connectivityProvider, (previous, next) {
      if (previous != ConnectivityState.online &&
          next == ConnectivityState.online) {
        if (ref.read(accessContextProvider) is AsyncError) {
          ref.invalidate(accessContextProvider);
        }
      }
    });

    return session.when(
      loading: () => _TimedLoadingPage(
        label: 'جارٍ استعادة الجلسة…',
        timeout: const Duration(seconds: 15),
        onRetry: () {
          ref.invalidate(authSessionProvider);
          ref.invalidate(accessContextProvider);
        },
        onSignOut: offlineLike ? null : signOut,
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
              message: 'انقطع الاتصال بالخادم. تحقق من الشبكة وأعد المحاولة.',
              onRetry: () {
                ref.invalidate(authSessionProvider);
                ref.invalidate(accessContextProvider);
              },
            );
          }
          return const LoginPage();
        }
        if (value.user.appMetadata['must_change_password'] == true) {
          return const SetPasswordPage();
        }
        OfflineCache.instance.setCurrentUser(value.user.id);
        // Device registration is non-blocking for the UI but remains observable in Riverpod.
        ref.watch(deviceRegistrationProvider);
        final access = ref.watch(accessContextProvider);
        return access.when(
          loading: () => _TimedLoadingPage(
            label: 'جارٍ تحميل الصلاحيات…',
            timeout: const Duration(seconds: 20),
            onRetry: () => ref.invalidate(accessContextProvider),
            onSignOut: offlineLike ? null : signOut,
          ),
          error: (_, _) => _ErrorPage(
            message: offlineLike
                ? 'انقطع الاتصال أثناء تحميل الصلاحيات. سيتم إعادة المحاولة تلقائيًا — أو اضغط إعادة المحاولة بعد عودة الإنترنت.'
                : 'تعذر تحميل صلاحيات الحساب. تحقق من الاتصال وأعد المحاولة.',
            onRetry: () => ref.invalidate(accessContextProvider),
            onSignOut: offlineLike ? null : signOut,
          ),
          data: (contextData) {
            if (contextData == null) return const LoginPage();
            if (contextData.isSuspendedAccount) {
              return _SuspendedAccountPage(
                access: contextData,
                onRetry: () => ref.invalidate(accessContextProvider),
                onSignOut: signOut,
              );
            }
            final workspace = _mobileWorkspace(contextData);
            if (workspace != null) {
              return switch (workspace) {
                WorkspaceId.executive => ExecutiveWorkspace(access: contextData),
                WorkspaceId.manager => ManagerWorkspace(access: contextData),
                WorkspaceId.fieldOperations =>
                  OperationsWorkspace(access: contextData),
                WorkspaceId.employee => EmployeeWorkspace(access: contextData),
                _ => _buildAdminOrUnassignedPage(
                    contextData,
                    signOut,
                    () => ref.invalidate(accessContextProvider),
                  ),
              };
            }
            return _buildAdminOrUnassignedPage(
              contextData,
              signOut,
              () => ref.invalidate(accessContextProvider),
            );
          },
        );
      },
    );
  }

  WorkspaceId? _mobileWorkspace(AccessContext context) {
    // حسابات الأدمين "الويب فقط" تُمنع من الموبايل. يحيى له دورين (admin +
    // executive-secretary) فيُسمح له كسكرتير. من لديه admin فقط يُحال إلى
    // صفحة "ويب فقط". (دفاع عميق بجانب المنع في identifier-sign-in.)
    const webOnlySlugs = {'admin', 'super-admin', 'super_admin', 'system-admin'};
    if (context.roles.any(webOnlySlugs.contains) &&
        !context.roles.contains('executive-secretary')) {
      return null;
    }
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
    if (context.workspaces.contains(WorkspaceId.employee)) {
      return WorkspaceId.employee;
    }
    return null;
  }

  Widget _buildAdminOrUnassignedPage(
    AccessContext context,
    VoidCallback onSignOut,
    VoidCallback onRetry,
  ) {
    const adminOrExecutiveSlugs = {
      'admin',
      'super-admin',
      'super_admin',
      'system-admin',
      'executive',
      'executive-director',
    };
    final isAdminOrExecutive = context.roles.any(adminOrExecutiveSlugs.contains) ||
        context.workspaces.contains(WorkspaceId.mainAdmin) ||
        context.workspaces.contains(WorkspaceId.executive);

    if (isAdminOrExecutive) {
      return _WebOnlyPage(
        access: context,
        onSignOut: onSignOut,
        onRetry: onRetry,
      );
    }

    return _UnassignedWorkspacePage(
      access: context,
      onSignOut: onSignOut,
      onRetry: onRetry,
    );
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

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.message, this.onRetry, this.onSignOut});
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOffline = message.contains('الاتصال') || message.contains('الشبكة');
    final icon = isOffline ? Icons.cloud_off_outlined : Icons.error_outline;

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
                      Icon(
                        icon,
                        size: 64,
                        color: theme.colorScheme.error.withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isOffline ? 'انقطع الاتصال' : 'تعذر تحميل النظام',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(height: 1.7),
                      ),
                      const SizedBox(height: 22),
                      if (onRetry != null)
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      if (onSignOut != null) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: onSignOut,
                          icon: const Icon(Icons.logout),
                          label: const Text('تسجيل الخروج'),
                        ),
                      ],
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
    final colorScheme = Theme.of(context).colorScheme;
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
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: .35),
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        widget.label,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (!_showFallback) ...[
                        const SizedBox(height: 12),
                        Text(
                          'يرجى الانتظار…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            height: 1.7,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (_showFallback) ...[
                        const SizedBox(height: 12),
                        Text(
                          'يبدو أن العملية تأخرت.\nتحقق من اتصالك بالإنترنت وجرّب الخيارات التالية:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            height: 1.7,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (widget.onRetry != null)
                          FilledButton.icon(
                            onPressed: widget.onRetry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                          ),
                        if (widget.onSignOut != null) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: widget.onSignOut,
                            icon: const Icon(Icons.logout),
                            label: const Text('تسجيل الخروج'),
                          ),
                        ],
                      ],
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

class _WebOnlyPage extends StatelessWidget {
  const _WebOnlyPage({
    required this.access,
    required this.onSignOut,
    required this.onRetry,
  });

  final AccessContext access;
  final VoidCallback onSignOut;
  final VoidCallback onRetry;

  static const String webUrl = 'https://ahla-shabab-management-os.vercel.app';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final badgeColor =
        isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA);
    final badgeBg = isDark
        ? const Color(0xFF312E81).withValues(alpha: 0.5)
        : const Color(0xFFEEF2FF);
    final cardBorder = isDark
        ? const Color(0xFF4F46E5).withValues(alpha: 0.3)
        : const Color(0xFFC7D2FE);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: isDark ? 2 : 4,
                color: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: cardBorder, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.admin_panel_settings_rounded,
                          size: 52,
                          color: badgeColor,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Text(
                          'منصة الويب للإدارة والتحكم',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'مرحبًا ${access.displayName}',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'هذا الحساب مخصص للإدارة والقيادة التنفيذية عبر منصة الويب بالمتصفح، لإدارة شؤون المنظومة والتقارير المتقدمة والعمليات المالية.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.65,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            launchUrl(
                              Uri.parse(webUrl),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.open_in_browser_rounded),
                          label: const Text('فتح لوحة التحكم على الويب'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            Clipboard.setData(
                              const ClipboardData(text: webUrl),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تم نسخ رابط لوحة الويب إلى الحافظة',
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('نسخ رابط المنصة'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة التحقق من الصلاحيات'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: onSignOut,
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
        ),
      ),
    );
  }
}

class _UnassignedWorkspacePage extends StatelessWidget {
  const _UnassignedWorkspacePage({
    required this.access,
    required this.onSignOut,
    required this.onRetry,
  });

  final AccessContext access;
  final VoidCallback onSignOut;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final amberColor =
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    final amberBg = isDark
        ? const Color(0xFF78350F).withValues(alpha: 0.35)
        : const Color(0xFFFEF3C7);
    final cardBorder = isDark
        ? const Color(0xFFD97706).withValues(alpha: 0.3)
        : const Color(0xFFFDE68A);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: isDark ? 2 : 4,
                color: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: cardBorder, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: amberBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.hourglass_top_rounded,
                          size: 52,
                          color: amberColor,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'الحساب قيد المراجعة والإعداد',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: amberColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'مرحبًا ${access.displayName}',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'حسابك قيد الإعداد أو بانتظار تعيين مساحة العمل من قبل إدارة الموارد البشرية (HR).',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.65,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة التحقق من حالة الحساب'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            final code = access.employeeCode ?? '';
                            final name = access.displayName;
                            final text =
                                'السلام عليكم، أنا الموظف $name${code.isNotEmpty ? ' (كود: $code)' : ''}. قمت بتسجيل الدخول في التطبيق وبانتظار تفعيل مساحة العمل الخاصة بي.';
                            launchUrl(
                              Uri.parse(
                                'https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('تواصل مع الـ HR (WhatsApp)'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onSignOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('تسجيل الخروج'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
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

class _SuspendedAccountPage extends StatelessWidget {
  const _SuspendedAccountPage({
    required this.access,
    required this.onRetry,
    required this.onSignOut,
  });

  final AccessContext access;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final message = access.suspensionMessage?.trim().isNotEmpty == true
        ? access.suspensionMessage!
        : 'تم وقفك عن العمل لعدم سداد قيمة الخصم 500جنيه توجه الي قسم ال HR لسداد المبلغ';
    final amount = access.suspensionAmount ?? 500.0;

    final errorBase = theme.colorScheme.error;
    final errorContainer = theme.colorScheme.errorContainer;

    final bannerBg = isDark
        ? errorContainer.withValues(alpha: 0.35)
        : const Color(0xFFFDE8E8);
    final bannerBorder = isDark
        ? errorBase.withValues(alpha: 0.45)
        : const Color(0xFFF8B4B4);
    final bannerTextColor = isDark
        ? const Color(0xFFFFDAD6)
        : const Color(0xFF991B1B);

    final iconCircleBg = isDark
        ? errorContainer.withValues(alpha: 0.4)
        : const Color(0xFFFEE2E2);
    final iconColor = isDark
        ? const Color(0xFFFFB4AB)
        : const Color(0xFFDC2626);

    final headerTextColor = isDark
        ? const Color(0xFFFFB4AB)
        : const Color(0xFF991B1B);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: isDark ? 2 : 4,
                color: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: isDark
                        ? errorBase.withValues(alpha: 0.35)
                        : const Color(0xFFFCA5A5).withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: iconCircleBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock_person_rounded,
                          size: 56,
                          color: iconColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'تم إيقاف الحساب عن العمل',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: headerTextColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: bannerBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: bannerBorder,
                          ),
                        ),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.65,
                            color: bannerTextColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: isDark ? 0.35 : 0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              context,
                              'الموظف:',
                              access.displayName,
                            ),
                            if (access.employeeCode != null) ...[
                              const Divider(height: 16),
                              _buildCodeRow(context, access.employeeCode!),
                            ],
                            const Divider(height: 16),
                            _buildInfoRow(
                              context,
                              'قيمة الخصم المستحق:',
                              '${amount.toStringAsFixed(0)} ج.م',
                              isBold: true,
                              valueColor: isDark
                                  ? const Color(0xFFFFB4AB)
                                  : const Color(0xFFDC2626),
                            ),
                            const Divider(height: 16),
                            _buildInfoRow(
                              context,
                              'حالة التطبيق:',
                              'موقوف حتى سداد المبلغ',
                              valueColor: isDark
                                  ? const Color(0xFFFFB74D)
                                  : const Color(0xFFC2410C),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة التحقق من حالة الحساب'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            final code = access.employeeCode ?? '';
                            final name = access.displayName;
                            final owed = amount.toStringAsFixed(0);
                            final text =
                                'السلام عليكم، أنا الموظف $name${code.isNotEmpty ? ' (كود: $code)' : ''}. تم إيقاف حسابي بالمنظومة لعدم سداد الغرامة المستحقة بقيمة $owed ج.م. برجاء المساعدة في تسوية المبلغ لإعادة تفعيل الحساب.';
                            launchUrl(
                              Uri.parse(
                                'https://api.whatsapp.com/send?text=${Uri.encodeComponent(text)}',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('تواصل مع الـ HR لتسوية المبلغ'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onSignOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('تسجيل الخروج'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
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

  Widget _buildCodeRow(BuildContext context, String code) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'الكود الوظيفي:',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              code,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'نسخ الكود',
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'تم نسخ الكود الوظيفي لمراجعته مع قسم الموارد البشرية',
                        textAlign: TextAlign.center,
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

