import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/gps_preflight_banner.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_history_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
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
                      _MessageCard(
                        icon: Icons.error_outline,
                        title: 'تعذر تحميل حالة الحضور',
                        body: 'تحقق من الاتصال وأعد المحاولة.',
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
        children: const [
          _MessageCard(
            icon: Icons.verified_user_outlined,
            title: 'لا توجد بصمة شخصية لهذا الحساب',
            body: 'سياسة الحساب الحالية لا تتطلب حضورًا أو انصرافًا شخصيًا.',
          ),
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
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.fingerprint,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 42,
              ),
              const SizedBox(height: 14),
              Text(
                actionLabel,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'سيطلب التطبيق بصمة الجهاز والموقع الحالي، ثم يتحقق الخادم من النطاق والسياسة.',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AttendanceStatusCard(state: value),
        const SizedBox(height: 16),
        if (value.localDeviceStatus == 'pending') ...[
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.hourglass_top_outlined, color: Colors.orange, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'جهازك مسجل وينتظر موافقة المسؤول — لا يمكنك تسجيل الحضور حالياً',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ] else if (!value.hasActiveLocalDevice)
          FilledButton.icon(
            onPressed: _working ? null : _register,
            icon: _working
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fingerprint),
            label: const Text('تفعيل الحضور ببصمة الجهاز'),
          )
        else
          FilledButton.icon(
            onPressed: _working || !value.canPunch
                ? null
                : () => _punch(action),
            icon: _working
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(actionIcon),
            label: Text(actionLabel),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _working
              ? null
              : () => ref.invalidate(attendanceStateProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('تحديث الحالة'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AttendanceHistoryPage(),
                  ),
                ),
                icon: const Icon(Icons.history),
                label: const Text('سجل الحضور'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PasskeyDevicesPage()),
                ),
                icon: const Icon(Icons.devices_outlined),
                label: const Text('أجهزتي'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MonthlyAttendanceStatementPage(),
            ),
          ),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('كشف الشهر'),
        ),
        const SizedBox(height: 16),
        const _MessageCard(
          icon: Icons.security_outlined,
          title: 'حماية العملية',
          body:
              'لا تُرسل بيانات البصمة الحيوية إلى الخادم. التحقق يتم داخل الجهاز، ثم يتحقق الخادم من الجلسة والجهاز المسجل والموقع ويسجل الوقت من ساعته.',
        ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_humanizePunchError(
                result['error'] as String? ?? 'unknown_error',
              )),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return;
      }

      ref.invalidate(attendanceStateProvider);
      ref.invalidate(employeeHomeProvider);
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
/// permissionDenied لا يُخزَّن هنا — يُعالج فوراً بطلب الصلاحية.
enum _LocationIssueKind {
  gpsOff,
  deniedForever,
}

class _AttendanceStatusCard extends StatelessWidget {
  const _AttendanceStatusCard({required this.state});
  final AttendanceState state;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('d MMMM، h:mm a', 'ar');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'حالة اليوم',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            _statusRow('الحالة', state.todayStatus),
            _row('بصمة الجهاز', state.hasActiveLocalDevice ? 'مفعلة' : 'غير مفعلة'),
            _row(
              'آخر عملية',
              state.lastEventType == null
                  ? 'لا توجد'
                  : state.lastEventType == 'CHECK_IN'
                  ? 'حضور'
                  : 'انصراف',
            ),
            _row(
              'وقت آخر عملية',
              state.lastEventAt == null
                  ? '—'
                  : formatter.format(state.lastEventAt!.toLocal()),
            ),
            if (state.lastEventStatus != null)
              _statusRow('حالة التحقق', state.lastEventStatus),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );

  // Renders known status keys as a shared MobileStatusPill (semantic color +
  // screen-reader text); unknown keys fall back to a translated bold label so
  // no raw English key is shown.
  Widget _statusRow(String label, String? value) {
    const pillKeys = {
      'present',
      'late',
      'absent',
      'flagged',
      'pending',
      'accepted',
    };
    final Widget valueWidget = value != null && pillKeys.contains(value)
        ? MobileStatusPill(value)
        : Text(
            _status(value),
            style: const TextStyle(fontWeight: FontWeight.w800),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          valueWidget,
        ],
      ),
    );
  }

  String _status(String? value) => switch (value) {
    'present' || 'accepted' => 'حاضر',
    'late' => 'متأخر',
    'absent' => 'غائب',
    'flagged' => 'قيد المراجعة',
    'pending' => 'جارٍ التحقق',
    'incomplete' => 'غير مكتمل',
    _ => value ?? '—',
  };
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
