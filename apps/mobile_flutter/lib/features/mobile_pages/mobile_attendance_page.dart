import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/gps_preflight_banner.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_history_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class MobileAttendancePage extends ConsumerStatefulWidget {
  const MobileAttendancePage({super.key});

  @override
  ConsumerState<MobileAttendancePage> createState() =>
      _MobileAttendancePageState();
}

class _MobileAttendancePageState extends ConsumerState<MobileAttendancePage>
    with WidgetsBindingObserver {
  bool _working = false;

  /// نوع مشكلة الموقع — لتحديد زر الإعدادات المناسب.
  _LocationIssueKind? _issueKind;

  /// العملية المعلقة بعد العودة من إعدادات GPS.
  _PendingRetry? _pendingRetry;

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

  /// عند العودة من إعدادات الموقع أو التطبيق — إعادة المحاولة تلقائياً.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _issueKind != null &&
        _pendingRetry != null &&
        !_working) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _issueKind != null && _pendingRetry != null && !_working) {
          _recheckAndRetry();
        }
      });
    }
  }

  Future<void> _recheckAndRetry() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!enabled) return;

    final permission = await Geolocator.checkPermission();
    if (!mounted) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      final newPerm = await Geolocator.requestPermission();
      if (!mounted) return;
      if (newPerm == LocationPermission.denied ||
          newPerm == LocationPermission.deniedForever) {
        return;
      }
    }

    // كلا الشرطين تحققا — امسح الخطأ وأعد العملية المعلقة
    final retry = _pendingRetry;
    setState(() {
      _issueKind = null;
      _pendingRetry = null;
    });
    if (retry == _PendingRetry.register) {
      _register(skipDialog: true);
    } else if (retry != null) {
      _punch(retry.action!, skipDialog: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(attendanceStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الحضور والانصراف')),
      body: SafeArea(
        child: Column(
          children: [
            const GpsPreflightBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(attendanceStateProvider),
                child: state.when(
                  loading: () => LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      children: [
                        SizedBox(
                          height: constraints.maxHeight,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                      ],
                    ),
                  ),
                  error: (error, _) => ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _ErrorCard(
                        message: humanizeError(error),
                        onRetry: () => ref.invalidate(attendanceStateProvider),
                      ),
                    ],
                  ),
                  data: (value) => _body(value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(AttendanceState value) {
    if (!value.attendanceRequired || !value.selfPunchEnabled) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _InfoBanner(
            icon: Icons.verified_user_outlined,
            title: 'لا توجد بصمة شخصية لهذا الحساب',
            body:
                'سياسة الحساب الحالية لا تتطلب حضورًا أو انصرافًا شخصيًا.',
          ),
          const SizedBox(height: 16),
          _QuickLinksRow(working: _working),
        ],
      );
    }

    final action = value.suggestedAction == 'CHECK_OUT'
        ? 'CHECK_OUT'
        : 'CHECK_IN';
    final actionLabel = action == 'CHECK_IN'
        ? 'تسجيل الحضور'
        : 'تسجيل الانصراف';
    final actionIcon = action == 'CHECK_IN' ? Icons.login : Icons.logout;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── بطاقة الإجراء الرئيسية ──
        _PunchCard(
          actionLabel: actionLabel,
          actionIcon: actionIcon,
          isCheckIn: action == 'CHECK_IN',
          hasActiveDevice: value.hasActiveLocalDevice,
          devicePending: value.localDeviceStatus == 'pending',
          canPunch: value.canPunch,
          working: _working,
          onRegister: _register,
          onPunch: () => _punch(action),
        ),
        const SizedBox(height: 14),

        // ── بطاقة حالة اليوم ──
        _TodayStatusCard(state: value),
        const SizedBox(height: 14),

        // ── روابط سريعة ──
        _QuickLinksRow(working: _working),
        const SizedBox(height: 14),

        // ── ملاحظة أمان مختصرة ──
        const _SecurityNote(),
      ],
    );
  }

  Future<void> _register({bool skipDialog = false}) async {
    setState(() => _working = true);
    try {
      await ref.read(mobileCommandsProvider).registerLocalBiometricDevice();
      ref.invalidate(attendanceStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل بصمة الجهاز بنجاح.')),
        );
      }
    } on GpsDisabledException {
      if (mounted) {
        setState(() => _issueKind = _LocationIssueKind.gpsOff);
        final opened = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('الموقع مغلق'),
            content: const Text(
              'يرجى تفعيل خدمة الموقع (GPS) لتتمكن من تسجيل بصمة الجهاز.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تفعيل الموقع'),
              ),
            ],
          ),
        );
        if (opened == true) {
          _pendingRetry = _PendingRetry.register;
          await Geolocator.openLocationSettings();
        } else {
          setState(() {
            _issueKind = null;
            _pendingRetry = null;
          });
        }
      }
    } on GpsPermissionDeniedException catch (e) {
      if (mounted) {
        if (e.isDeniedForever) {
          setState(() => _issueKind = _LocationIssueKind.deniedForever);
          final opened = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('صلاحية الموقع مرفوضة'),
              content: const Text(
                'صلاحية الموقع مرفوضة نهائيًا. افتح إعدادات التطبيق لتفعيلها.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('فتح الإعدادات'),
                ),
              ],
            ),
          );
          if (opened == true) {
            _pendingRetry = _PendingRetry.register;
            await Geolocator.openAppSettings();
          } else {
            setState(() {
              _issueKind = null;
              _pendingRetry = null;
            });
          }
        } else {
          // صلاحية مرفوضة (ليست نهائية) — نطلبها مباشرة
          final perm = await Geolocator.requestPermission();
          if (!mounted) return;
          if (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) {
            _register(skipDialog: true);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى منح صلاحية الموقع للمتابعة.')),
          );
        }
      }
    } on GpsAccuracyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (error) {
      if (mounted) {
        final msg = error.toString().toLowerCase();
        final text =
            msg.contains('cancel') || msg.contains('dismissed')
            ? 'تم إلغاء التحقق بالبصمة.'
            : msg.contains('الجهاز لا يدعم')
            ? 'جهازك لا يدعم التحقق بالبصمة.'
            : humanizeError(error);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _punch(String action, {bool skipDialog = false}) async {
    if (!skipDialog) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            action == 'CHECK_IN'
                ? 'تأكيد تسجيل الحضور'
                : 'تأكيد تسجيل الانصراف',
          ),
          content: const Text(
            'سيتم قراءة موقعك الحالي وطلب بصمة أو قفل الجهاز للتحقق.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _working = true);
    try {
      final result = await ref
          .read(mobileCommandsProvider)
          .punchAttendanceLocal(
            eventType: action,
          );

      // الخادم يرجع ok: false عند رفض العملية (خارج النطاق، تكرار، إلخ)
      if (result['ok'] != true) {
        if (mounted) {
          final errorCode = result['error'] as String? ?? 'unknown_error';
          // أخطاء الإعدادات (نطاق جغرافي غير معرّف) — بانر معلوماتي برتقالي.
          // أخطاء الانتهاك (خارج النطاق، موقع مزيف) — بانر أحمر.
          final isConfigIssue =
              errorCode == 'attendance_geofence_not_configured';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_humanizePunchError(errorCode)),
              backgroundColor:
                  isConfigIssue ? Colors.orange.shade700 : Colors.red.shade700,
            ),
          );
        }
        return;
      }

      // punchAttendanceLocal() already invalidates providers.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'CHECK_IN'
                  ? 'تم تسجيل الحضور بنجاح ✓'
                  : 'تم تسجيل الانصراف بنجاح ✓',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on GpsDisabledException {
      if (mounted) {
        setState(() => _issueKind = _LocationIssueKind.gpsOff);
        final opened = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('الموقع مغلق'),
            content: const Text('يرجى تفعيل خدمة الموقع (GPS) للمتابعة.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تفعيل الموقع'),
              ),
            ],
          ),
        );
        if (opened == true) {
          _pendingRetry = _PendingRetry.punch(action);
          await Geolocator.openLocationSettings();
        } else {
          setState(() {
            _issueKind = null;
            _pendingRetry = null;
          });
        }
      }
    } on GpsPermissionDeniedException catch (e) {
      if (mounted) {
        if (e.isDeniedForever) {
          setState(() => _issueKind = _LocationIssueKind.deniedForever);
          final opened = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('صلاحية الموقع مرفوضة'),
              content: const Text(
                'صلاحية الموقع مرفوضة نهائيًا. افتح إعدادات التطبيق لتفعيلها.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('فتح الإعدادات'),
                ),
              ],
            ),
          );
          if (opened == true) {
            _pendingRetry = _PendingRetry.punch(action);
            await Geolocator.openAppSettings();
          } else {
            setState(() {
              _issueKind = null;
              _pendingRetry = null;
            });
          }
        } else {
          final perm = await Geolocator.requestPermission();
          if (!mounted) return;
          if (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) {
            _punch(action, skipDialog: true);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى منح صلاحية الموقع للمتابعة.')),
          );
        }
      }
    } on GpsAccuracyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (error) {
      if (mounted) {
        final msg = error.toString().toLowerCase();
        final text =
            msg.contains('cancel') || msg.contains('dismissed')
            ? 'تم إلغاء التحقق بالبصمة.'
            : humanizeError(error);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// ترجمة أكواد الخطأ من الخادم إلى رسائل عربية واضحة للمستخدم.
  String _humanizePunchError(String code) {
    switch (code) {
      case 'attendance_outside_complex':
        return 'أنت خارج نطاق المجمع. يُرجى التسجيل من داخل موقع العمل.';
      case 'attendance_mock_location_rejected':
        return 'تم رفض الموقع — يُشتبه في استخدام موقع مزيف.';
      case 'attendance_location_accuracy_too_low':
        return 'دقة الموقع منخفضة جداً. حاول في مكان مفتوح.';
      case 'attendance_geofence_not_configured':
        return 'لم يتم تحديد نطاق جغرافي لحضورك. تواصل مع المسؤول.';
      case 'attendance_location_required':
        return 'الموقع مطلوب لتسجيل الحضور.';
      case 'duplicate_attendance_event':
        return 'تم تسجيل هذا الحدث مسبقاً.';
      case 'attendance_period_finalized':
        return 'فترة الحضور مغلقة ولا يمكن التعديل عليها.';
      case 'attendance_check_in_required':
        return 'يجب تسجيل الحضور أولاً قبل الانصراف.';
      case 'attendance_check_out_required':
        return 'يجب تسجيل الانصراف أولاً قبل حضور جديد.';
      default:
        return 'حدث خطأ غير متوقع ($code). حاول مرة أخرى.';
    }
  }
}

/// العملية المعلقة بعد العودة من إعدادات GPS — لإعادة المحاولة تلقائياً.
class _PendingRetry {
  const _PendingRetry._(this.action);
  static const register = _PendingRetry._(null);
  factory _PendingRetry.punch(String action) => _PendingRetry._(action);
  final String? action;
}

/// نوع مشكلة الموقع — يحدد سلوك إعادة المحاولة التلقائية.
enum _LocationIssueKind {
  gpsOff,
  deniedForever,
}

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقة البصمة الرئيسية — إجراء واحد واضح
// ═══════════════════════════════════════════════════════════════════════════════

class _PunchCard extends StatelessWidget {
  const _PunchCard({
    required this.actionLabel,
    required this.actionIcon,
    required this.isCheckIn,
    required this.hasActiveDevice,
    required this.devicePending,
    required this.canPunch,
    required this.working,
    required this.onRegister,
    required this.onPunch,
  });

  final String actionLabel;
  final IconData actionIcon;
  final bool isCheckIn;
  final bool hasActiveDevice;
  final bool devicePending;
  final bool canPunch;
  final bool working;
  final VoidCallback onRegister;
  final VoidCallback onPunch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ألوان ديناميكية حسب نوع الحركة
    final colorA = isCheckIn
        ? scheme.primary
        : (isDark ? scheme.secondary : scheme.tertiary);
    final colorB = isCheckIn ? scheme.tertiary : scheme.primary;

    return Card(
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // البانر العلوي مع تدرج ديناميكي
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colorA, colorB],
              ),
            ),
            child: Column(
              children: [
                // أيقونة ديناميكية داخل دائرة شفافة
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCheckIn ? Icons.fingerprint : Icons.logout_rounded,
                    color: scheme.onPrimary,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  actionLabel,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'بصمة الجهاز + الموقع → التحقق خادمياً',
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.72),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // زر الإجراء
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: _buildActionButton(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    if (devicePending) {
      return _StatusBanner(
        tone: _BannerTone.warning,
        icon: Icons.hourglass_top_rounded,
        text: 'جهازك مسجل وينتظر موافقة المسؤول',
      );
    }

    if (!hasActiveDevice) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: working ? null : onRegister,
          icon: working
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fingerprint),
          label: const Text('تفعيل الحضور ببصمة الجهاز'),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: working || !canPunch ? null : onPunch,
        icon: working
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(actionIcon),
        label: Text(actionLabel),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقة حالة اليوم — تُخفي الحقول الفارغة
// ═══════════════════════════════════════════════════════════════════════════════

class _TodayStatusCard extends StatelessWidget {
  const _TodayStatusCard({required this.state});
  final AttendanceState state;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('h:mm a', 'ar');
    final scheme = Theme.of(context).colorScheme;
    final hasEvent = state.lastEventType != null;
    final hasStatus = state.todayStatus != null &&
        state.todayStatus != '—' &&
        state.todayStatus!.isNotEmpty;

    return Card(
      elevation: 1,
      shadowColor: scheme.shadow.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.today_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'حالة اليوم',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                if (hasStatus) MobileStatusPill(state.todayStatus!),
              ],
            ),
            const SizedBox(height: 12),

            // بصمة الجهاز
            _StatusRow(
              icon: state.hasActiveLocalDevice
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
              label: 'أمان الجهاز',
              value: state.hasActiveLocalDevice ? 'مفعلة' : 'غير مفعلة',
              valueColor: state.hasActiveLocalDevice
                  ? const Color(0xFF0F9F6E)
                  : scheme.error,
            ),

            // آخر عملية (فقط عند وجود بيانات)
            if (hasEvent) ...[
              const SizedBox(height: 8),
              _StatusRow(
                icon: state.lastEventType == 'CHECK_IN'
                    ? Icons.login_rounded
                    : Icons.logout_rounded,
                label: 'آخر عملية',
                value:
                    '${state.lastEventType == 'CHECK_IN' ? 'حضور' : 'انصراف'}'
                    '${state.lastEventAt != null ? ' · ${formatter.format(state.lastEventAt!.toLocal())}' : ''}',
              ),
            ],

            // حالة التحقق (فقط عند وجودها)
            if (state.lastEventStatus != null) ...[
              const SizedBox(height: 8),
              _StatusRow(
                icon: Icons.verified_rounded,
                label: 'التحقق',
                trailing: MobileStatusPill(state.lastEventStatus!),
              ),
            ],

            // رسالة عندما لا يوجد أي نشاط
            if (!hasEvent && !hasStatus) ...[
              const SizedBox(height: 4),
              Text(
                'لم تُسجَّل أي عملية حضور اليوم',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        const Spacer(),
        if (trailing != null) trailing!
        else Text(
          value ?? '—',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// روابط سريعة — شبكة 3 أزرار مدمجة
// ═══════════════════════════════════════════════════════════════════════════════

class _QuickLinksRow extends StatelessWidget {
  const _QuickLinksRow({required this.working});
  final bool working;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _QuickLink(
          icon: Icons.history_rounded,
          label: 'السجل',
          onTap: working
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AttendanceHistoryPage(),
                    ),
                  ),
        ),
        const SizedBox(width: 8),
        _QuickLink(
          icon: Icons.calendar_month_outlined,
          label: 'كشف الشهر',
          onTap: working
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MonthlyAttendanceStatementPage(),
                    ),
                  ),
        ),
        const SizedBox(width: 8),
        _QuickLink(
          icon: Icons.devices_outlined,
          label: 'أجهزتي',
          onTap: working
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PasskeyDevicesPage(),
                    ),
                  ),
        ),
      ],
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0.5,
        shadowColor: scheme.shadow.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ملاحظة الأمان — مدمجة وغير مشتتة
// ═══════════════════════════════════════════════════════════════════════════════

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'البصمة تُحقَّق داخل الجهاز فقط، ثم يتحقق الخادم من الجلسة والجهاز والموقع.',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقات مساعدة
// ═══════════════════════════════════════════════════════════════════════════════

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: scheme.error),
            const SizedBox(height: 10),
            const Text(
              'تعذر تحميل حالة الحضور',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// مناسبة الألوان لـ banner — يحافظ على تباين النص
enum _BannerTone { warning, error, info }

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.tone,
    required this.icon,
    required this.text,
  });

  final _BannerTone tone;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      _BannerTone.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _BannerTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      _BannerTone.info => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
