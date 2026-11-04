import 'dart:async';

import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_probe.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:ahla_shabab_management_os/core/network/session_cleanup.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/core/widgets/phone_display.dart';
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
            final conn = ref.read(connectivityProvider);
            if (conn != ConnectivityState.offline) {
              await supabase.auth.refreshSession();
              if (mounted) {
                ref.invalidate(authSessionProvider);
                ref.invalidate(accessContextProvider);
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[AppGate] Proactive resume token refresh failed: $e');
            }
            // عند انقطاع الشبكة في الخلفية لا نبطل المزودات حتى لا تسقط إلى شاشة الخطأ
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

    // 0471-UX: عند عودة الاتصال بعد انقطاع، نعيد فحص الجلسة والصلاحيات تلقائيًا
    // إن كانت في حالة خطأ — بدل ترك المستخدم أمام زر إعادة المحاولة.
    ref.listen(connectivityProvider, (previous, next) {
      if (previous != ConnectivityState.online &&
          next == ConnectivityState.online) {
        if (ref.read(authSessionProvider) is AsyncError) {
          ref.invalidate(authSessionProvider);
        }
        if (ref.read(accessContextProvider) is AsyncError) {
          ref.invalidate(accessContextProvider);
        }
      }
    });

    return session.when(
      loading: () => _TimedLoadingPage(
        label: 'أستغفر الله العظيم وأتوب إليه',
        timeout: const Duration(seconds: 15),
        onRetry: () {
          ref.read(connectivityProvider.notifier).recheck();
          ref.invalidate(authSessionProvider);
          ref.invalidate(accessContextProvider);
        },
        onSignOut: offlineLike ? null : signOut,
      ),
      error: (err, _) {
        final isNetError = offlineLike ||
            err.toString().contains('SocketException') ||
            err.toString().contains('ClientException') ||
            err.toString().contains('AuthRetryableFetchException') ||
            err.toString().contains('Failed host lookup') ||
            err.toString().contains('TimeoutException');

        final errorMessage = isNetError
            ? 'انقطع الاتصال بالإنترنت مؤقتاً. بياناتك وجلستك محفوظة وسيتم إعادة المحاولة تلقائياً بمجرد توفر الشبكة.'
            : 'تعذر استعادة جلسة الدخول بأمان. أعد المحاولة أو سجّل الدخول مجدداً.';

        return _ErrorPage(
          message: errorMessage,
          onRetry: () {
            ref.read(connectivityProvider.notifier).recheck();
            ref.invalidate(authSessionProvider);
            ref.invalidate(accessContextProvider);
          },
          onSignOut: (offlineLike || isNetError) ? null : signOut,
        );
      },
      data: (value) {
        if (value == null) {
          // P0-20: If offline, show connection error instead of login page.
          // Prevents silent logout on temporary DNS/network failure.
          if (offlineLike) {
            return _ErrorPage(
              message: 'انقطع الاتصال بالخادم. تحقق من توفر الإنترنت وسيتم إعادة المحاولة تلقائياً.',
              onRetry: () {
                ref.read(connectivityProvider.notifier).recheck();
                ref.invalidate(authSessionProvider);
                ref.invalidate(accessContextProvider);
              },
              onSignOut: null,
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
            label: 'اللهم صلِّ وسلِّم وبارك على نبينا محمد ﷺ',
            timeout: const Duration(seconds: 20),
            onRetry: () {
              ref.read(connectivityProvider.notifier).recheck();
              ref.invalidate(accessContextProvider);
            },
            onSignOut: offlineLike ? null : signOut,
          ),
          error: (err, _) => _ErrorPage(
            message: offlineLike
                ? 'انقطع الاتصال أثناء تجهيز البيانات. جاري إعادة المحاولة تلقائياً بمجرد عودة الإنترنت.'
                : humanizeError(err),
            onRetry: () {
              ref.read(connectivityProvider.notifier).recheck();
              ref.invalidate(accessContextProvider);
            },
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
    // 1) المدير التنفيذي — الأولوية الأولى دائمًا لمساحته التنفيذية
    // (حتى وإن كان حسابه يمتلك صلاحيات إدارة عليا أو دور admin).
    if (context.workspaces.contains(WorkspaceId.executive) ||
        context.roles.contains('executive') ||
        context.roles.contains('executive-director')) {
      return WorkspaceId.executive;
    }

    // حسابات الأدمين "الويب فقط" تُمنع من الموبايل. يحيى له دورين (admin +
    // executive-secretary) فيُسمح له كسكرتير. من لديه admin فقط يُحال إلى
    // صفحة "ويب فقط". (دفاع عميق بجانب المنع في identifier-sign-in.)
    const webOnlySlugs = {'admin', 'super-admin', 'super_admin', 'system-admin'};
    if (context.roles.any(webOnlySlugs.contains) &&
        !context.roles.contains('executive-secretary')) {
      return null;
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
    const adminSlugs = {
      'admin',
      'super-admin',
      'super_admin',
      'system-admin',
    };
    final isAdmin = context.roles.any(adminSlugs.contains) ||
        context.workspaces.contains(WorkspaceId.mainAdmin);

    if (isAdmin) {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final blocked = policy.action == MobileReleaseAction.blocked;
    final maintenance = policy.action == MobileReleaseAction.maintenance;
    final icon = blocked
        ? Icons.phonelink_erase_rounded
        : maintenance
        ? Icons.engineering_rounded
        : Icons.system_update_rounded;
    final title = blocked
        ? 'تم إبطال هذا الجهاز'
        : maintenance
        ? 'النظام تحت الصيانة'
        : 'يتوفر تحديث جديد للتطبيق';
    final defaultMessage = blocked
        ? 'تم إيقاف هذا التثبيت لأسباب أمنية. تواصل مع مسؤول النظام للمساعدة.'
        : maintenance
        ? 'نعمل على تحسين النظام حالياً. يرجى إعادة المحاولة بعد قليل.'
        : 'هذه النسخة بحاجة إلى تحديث للاستفادة من أحدث التحسينات ومتابعة العمل بأمان.';

    final Color statusColor = blocked
        ? theme.colorScheme.error
        : maintenance
        ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)) // amber
        : (isDark ? AppColors.darkPrimary : AppColors.brandPrimary);

    final Color statusBg = statusColor.withValues(alpha: isDark ? 0.20 : 0.12);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131D2E) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandLogo(compact: false, markSize: 46),
                    const SizedBox(height: 24),
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: statusBg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.35),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Icon(icon, size: 38, color: statusColor),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      policy.messageAr ?? defaultMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (policy.action == MobileReleaseAction.updateRequired) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'نسختك ${policy.currentVersion}+${policy.currentBuild} · الحد الأدنى ${policy.minSupportedVersion}+${policy.minSupportedBuild}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (policy.action == MobileReleaseAction.updateRequired &&
                        policy.storeUrl != null)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(policy.storeUrl!),
                            mode: LaunchMode.externalApplication,
                          ),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 20),
                          label: const Text(
                            'تحميل التحديث الآن',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    if (!blocked) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: onRetry,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text(
                            'إعادة التحقق',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorPage extends ConsumerStatefulWidget {
  const _ErrorPage({
    required this.message,
    this.onRetry,
    this.onSignOut,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  ConsumerState<_ErrorPage> createState() => _ErrorPageState();
}

class _ErrorPageState extends ConsumerState<_ErrorPage> {
  bool _isRetrying = false;
  Timer? _autoRetryTimer;
  Timer? _dhikrTimer;
  int _dhikrIndex = 0;

  static const List<String> _dhikrItems = [
    'لا حول ولا قوة إلا بالله العلي العظيم',
    'أستغفر الله العظيم وأتوب إليه',
    'سبحان الله وبحمده، سبحان الله العظيم',
    'اللهم صلِّ وسلِّم وبارك على سيدنا محمد ﷺ',
    'حسبي الله لا إله إلا هو عليه توكلت وهو رب العرش العظيم',
    'يا حي يا قيوم برحمتك أستغيث، أصلح لي شأني كله',
  ];

  @override
  void initState() {
    super.initState();
    // تدوير الأذكار بسلاسة لراحة البال واكتساب الأجر
    _dhikrTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        setState(() {
          _dhikrIndex = (_dhikrIndex + 1) % _dhikrItems.length;
        });
      }
    });

    // إذا كان الخطأ متعلقاً بالاتصال أو الشبكة، نقوم بفحص تلقائي دوري
    if (_isNetworkRelated(widget.message)) {
      _autoRetryTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
        if (!mounted || _isRetrying) return;
        try {
          final online = await hasNetworkConnection().timeout(const Duration(seconds: 4));
          if (online && mounted) {
            _triggerRetry();
          }
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    _dhikrTimer?.cancel();
    super.dispose();
  }

  bool _isNetworkRelated(String msg) {
    return msg.contains('الاتصال') ||
        msg.contains('الشبكة') ||
        msg.contains('الإنترنت') ||
        msg.contains('خادم') ||
        msg.contains('Socket') ||
        msg.contains('ClientException') ||
        msg.contains('Timeout');
  }

  bool _isSessionRelated(String msg) {
    return msg.contains('جلسة') ||
        msg.contains('تسجيل الدخول') ||
        msg.contains('صلاحية');
  }

  Future<void> _triggerRetry() async {
    if (_isRetrying || !mounted) return;
    setState(() => _isRetrying = true);
    try {
      ref.read(connectivityProvider.notifier).recheck();
      widget.onRetry?.call();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final connectivity = ref.watch(connectivityProvider);
    final isOffline = connectivity == ConnectivityState.offline ||
        connectivity == ConnectivityState.reconnecting ||
        connectivity == ConnectivityState.serverUnavailable ||
        _isNetworkRelated(widget.message);
    final isSession = !isOffline && _isSessionRelated(widget.message);

    // إعادة المحاولة تلقائياً عند عودة الإنترنت
    ref.listen(connectivityProvider, (previous, next) {
      if (previous != ConnectivityState.online &&
          next == ConnectivityState.online) {
        _triggerRetry();
      }
    });

    final String title = isOffline
        ? 'الاتصال معلق مؤقتاً'
        : isSession
            ? 'استعادة جلسة العمل'
            : 'تعذر تحميل البيانات';

    final String displayMessage = isOffline && !widget.message.contains('بياناتك')
        ? 'انقطع الاتصال بالإنترنت مؤقتاً. بياناتك وجلستك محفوظة بأمان وسنعيد المزامنة تلقائياً بمجرد توفر الشبكة.'
        : widget.message;

    final Color iconColor = isOffline
        ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
        : isSession
            ? (isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5))
            : theme.colorScheme.error;

    final Color iconBgColor = isOffline
        ? (isDark
            ? const Color(0xFF0369A1).withValues(alpha: 0.22)
            : const Color(0xFFE0F2FE))
        : isSession
            ? (isDark
                ? const Color(0xFF4338CA).withValues(alpha: 0.22)
                : const Color(0xFFEEF2FF))
            : (isDark
                ? theme.colorScheme.error.withValues(alpha: 0.18)
                : const Color(0xFFFEE2E2));

    final IconData mainIcon = isOffline
        ? Icons.wifi_off_rounded
        : isSession
            ? Icons.lock_reset_rounded
            : Icons.error_outline_rounded;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131D2E) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الشعار الرسمي لجمعية أحلى شباب
                    const BrandLogo(compact: false, markSize: 46),
                    const SizedBox(height: 24),

                    // الأيقونة البارزة ذات الخلفية الهادئة
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.35),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          mainIcon,
                          size: 38,
                          color: iconColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // العنوان الرئيسي
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),

                    // نص التوضيح المطمئن
                    Text(
                      displayMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // شارة الفحص التلقائي الحيّة في حالة انقطاع الشبكة
                    if (isOffline) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isDark ? AppColors.darkPrimary : AppColors.brandPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'جاري فحص الاتصال تلقائياً...',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark ? AppColors.darkPrimary : AppColors.brandPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // بنر الذكر الروحاني المطمئن للقلب
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.22),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.volunteer_activism_rounded,
                            size: 16,
                            color: Color(0xFF10B981),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 350),
                              child: Text(
                                _dhikrItems[_dhikrIndex],
                                key: ValueKey<int>(_dhikrIndex),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF10B981),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // زر إعادة المحاولة
                    if (widget.onRetry != null)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _isRetrying ? null : _triggerRetry,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          icon: _isRetrying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 20),
                          label: Text(
                            _isRetrying
                                ? 'جاري الفحص والتحديث...'
                                : 'إعادة المحاولة الآن',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),

                    // زر تسجيل الخروج (لا يظهر عند انقطاع الشبكة لمنع خروج الموظف بالخطأ)
                    if (widget.onSignOut != null && !isOffline) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: widget.onSignOut,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          icon: const Icon(Icons.logout_rounded, size: 18),
                          label: const Text(
                            'تسجيل الخروج',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// صفحة تحميل تُظهر أذكار واستغفار وصلاة على النبي ﷺ لكسب الحسنات
/// مع أزرار إعادة المحاولة وتسجيل الخروج بعد مهلة زمنية.
class _TimedLoadingPage extends StatefulWidget {
  const _TimedLoadingPage({
    this.label,
    required this.timeout,
    this.onRetry,
    this.onSignOut,
  });
  final String? label;
  final Duration timeout;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  State<_TimedLoadingPage> createState() => _TimedLoadingPageState();
}

class _TimedLoadingPageState extends State<_TimedLoadingPage> {
  bool _showFallback = false;
  Timer? _timer;
  Timer? _rotationTimer;
  int _dhikrIndex = 0;

  static const List<String> _dhikrItems = [
    'اللهم صلِّ وسلِّم وبارك على سيدنا محمد ﷺ',
    'أستغفر الله العظيم وأتوب إليه',
    'سبحان الله وبحمده، سبحان الله العظيم',
    'لا حول ولا قوة إلا بالله العلي العظيم',
    'لا إله إلا أنت سبحانك إني كنت من الظالمين',
    'سبحان الله، والحمد لله، ولا إله إلا الله، والله أكبر',
    'اللهم صلِّ على محمد وعلى آل محمد كما صليت على إبراهيم وعلى آل إبراهيم',
    'يا حي يا قيوم برحمتك أستغيث، أصلح لي شأني كله',
    'رضيت بالله رباً، وبالإسلام ديناً، وبمحمد ﷺ نبياً ورسولاً',
    'اللهم إنا نسألك التوفيق والبركة والقبول في أعمالنا',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.timeout, () {
      if (mounted) setState(() => _showFallback = true);
    });
    // تدوير الأذكار بسلاسة كل 3 ثوانٍ
    _rotationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        setState(() {
          _dhikrIndex = (_dhikrIndex + 1) % _dhikrItems.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rotationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentDhikr = _dhikrItems[_dhikrIndex];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: const Color(0xFF10B981).withValues(alpha: .2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // المؤشر والرمز الروحاني
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: .12),
                          shape: BoxShape.circle,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: const Color(0xFF10B981),
                                backgroundColor: const Color(0xFF10B981).withValues(alpha: .15),
                              ),
                            ),
                            const Icon(
                              Icons.volunteer_activism_rounded,
                              size: 22,
                              color: Color(0xFF10B981),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // شارة كسب الحسنات
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: .28),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 13,
                                color: Color(0xFF10B981),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'ذكر واستغفار لكسب الحسنات',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // الذكر والصلاة على النبي المتجدد بسلاسة
                      SizedBox(
                        height: 68,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.0, 0.15),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                )),
                                child: child,
                              ),
                            ),
                            child: Text(
                              currentDhikr,
                              key: ValueKey<int>(_dhikrIndex),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      if (!_showFallback) ...[
                        const SizedBox(height: 10),
                        Text(
                          'عطّر لسانك بذكر الله والصلاة على الحبيب ﷺ…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (_showFallback) ...[
                        const SizedBox(height: 12),
                        Text(
                          'استمر في الذكر المبارك… يبدو أن الاستجابة تأخرت قليلاً.\nيمكنك الانتظار أو تجربة الخيارات التالية:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            height: 1.6,
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
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
                            final code = PhoneDisplay.stripCountryCode(access.employeeCode);
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

  static const String yehiaPhone = '+201154869616';
  static const String yehiaWhatsapp = '201154869616';
  static const String yehiaName = 'م. يحيى جمال السبع';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final message = access.suspensionMessage?.trim().isNotEmpty == true
        ? access.suspensionMessage!
        : 'تم إيقافك عن العمل، راجع المسؤول م. يحيى لسداد الغرامات التي عليك';
    final amount = access.suspensionAmount ?? 500.0;
    final contactName = access.managerContactName ?? yehiaName;
    final contactPhone = access.managerContactPhone ?? yehiaPhone;
    final contactWa = access.managerContactWhatsapp ?? yehiaWhatsapp;

    const redColor = Color(0xFFDC2626);
    const redLight = Color(0xFFEF4444);

    final bannerBg = isDark
        ? const Color(0xFF450A0A).withValues(alpha: 0.65)
        : const Color(0xFFFEF2F2);
    final bannerBorder = isDark
        ? const Color(0xFF991B1B).withValues(alpha: 0.6)
        : const Color(0xFFFECACA);
    final bannerTextColor = isDark
        ? const Color(0xFFFCA5A5)
        : const Color(0xFF991B1B);

    final iconCircleBg = isDark
        ? const Color(0xFF7F1D1D).withValues(alpha: 0.45)
        : const Color(0xFFFEE2E2);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: isDark ? 2 : 5,
                color: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF7F1D1D).withValues(alpha: 0.6)
                        : const Color(0xFFFCA5A5),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // علامة في / الإيقاف البارزة
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: iconCircleBg,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: redColor.withValues(alpha: 0.35),
                            width: 2,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.cancel_rounded,
                            size: 58,
                            color: redColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // العنوان الرئيسي الصريح
                      const Text(
                        'تم إيقافك عن العمل',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          color: redColor,
                          letterSpacing: -0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      // شريط التنبيه وتوجيه الموظف لم. يحيى
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: bannerBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: bannerBorder,
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                height: 1.6,
                                color: bannerTextColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'تم تجميد صلاحيات تسجيل البصمة واستخدام التطبيق مؤقتاً حتى سداد الغرامات.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: bannerTextColor.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // بطاقة تفاصيل الحساب والغرامات
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: isDark ? 0.35 : 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
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
                              _buildCodeRow(context, PhoneDisplay.stripCountryCode(access.employeeCode)),
                            ],
                            const Divider(height: 16),
                            _buildInfoRow(
                              context,
                              'إجمالي الغرامات المستحقة:',
                              '${amount.toStringAsFixed(0)} ج.م',
                              isBold: true,
                              valueColor: isDark ? redLight : redColor,
                            ),
                            const Divider(height: 16),
                            _buildInfoRow(
                              context,
                              'المسؤول للمراجعة والسداد:',
                              contactName,
                              isBold: true,
                              valueColor: const Color(0xFF0284C7),
                            ),
                            const Divider(height: 16),
                            _buildInfoRow(
                              context,
                              'حالة الحساب:',
                              'موقوف عن العمل',
                              isBold: true,
                              valueColor: isDark
                                  ? const Color(0xFFFFB74D)
                                  : const Color(0xFFC2410C),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      // زر واتساب مباشر لم. يحيى
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            final code = PhoneDisplay.stripCountryCode(access.employeeCode);
                            final name = access.displayName;
                            final owed = amount.toStringAsFixed(0);
                            final text =
                                'السلام عليكم م. يحيى، أنا الموظف $name${code.isNotEmpty ? ' (كود: $code)' : ''}. تم إيقاف حسابي بالمنظومة لوجود غرامات مستحقة بقيمة $owed ج.م. برجاء مراجعة الحساب وتوضيح إجراءات السداد ورفع الإيقاف.';
                            launchUrl(
                              Uri.parse(
                                'https://wa.me/$contactWa?text=${Uri.encodeComponent(text)}',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.chat_bubble_rounded),
                          label: const Text('مراسلة م. يحيى عبر واتساب للسداد'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // زر اتصال مباشر بم. يحيى
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            launchUrl(
                              Uri.parse('tel:$contactPhone'),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          icon: const Icon(Icons.phone_in_talk_rounded),
                          label: Text('الاتصال بـ $contactName'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // زر إعادة التحقق بعد السداد
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة التحقق من حالة الحساب (بعد السداد)'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // تسجيل الخروج
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: onSignOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('تسجيل الخروج من الحساب'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
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

