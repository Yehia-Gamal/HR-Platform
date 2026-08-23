import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/gps_preflight_banner.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/live_tracking_session_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
// V17 §9: video_verification_page removed — video permanently disabled.
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class LocationRequestsPage extends ConsumerWidget {
  const LocationRequestsPage({required this.access, super.key});
  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(myLocationRequestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الموقع والتحقق')),
      body: Column(
        children: [
          const GpsPreflightBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(myLocationRequestsProvider),
              child: requests.when(
                loading: () => LayoutBuilder(
                  builder: (context, constraints) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child:
                            const Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  ),
                ),
                error: (error, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 72),
                    const Center(child: BrandLogoMark()),
                    const SizedBox(height: 20),
                    Icon(
                      Icons.error_outline_rounded,
                      size: 52,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'تعذر تحميل الطلبات',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      humanizeError(error),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: FilledButton.tonalIcon(
                        onPressed: () =>
                            ref.invalidate(myLocationRequestsProvider),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ),
                  ],
                ),
                data: (items) => items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: [
                          const SizedBox(height: 96),
                          Semantics(
                            label: 'لا توجد طلبات موقع',
                            child: Column(
                              children: [
                                ExcludeSemantics(
                                  child: CircleAvatar(
                                    radius: 36,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest
                                        .withValues(alpha: .6),
                                    child: Icon(
                                      Icons.location_off_outlined,
                                      size: 40,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'لا توجد طلبات موقع',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'ستظهر هنا طلبات الإدارة لمشاركة موقعك —\nوكل مشاركة مؤقتة بموافقتك.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        height: 1.6,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          // ── لافتة الخصوصية — 0451 ──
                          Container(
                            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: .06),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.verified_user_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'مشاركتك بموافقتك فقط، مؤقتة، ومسجلة في سجل التدقيق.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) => _RequestCard(
                                  request: items[index], access: access),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.request, required this.access});
  final MobileLocationRequest request;
  final AccessContext access;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard>
    with WidgetsBindingObserver {
  bool busy = false;
  String? error;

  /// نوع مشكلة الموقع — لتحديد زر الإعدادات المناسب.
  _LocationIssueKind? _issueKind;

  static const _urgentPlatform = MethodChannel(
    'com.ahlashabab/urgent_notification',
  );

  Future<void> _stopUrgentAlarm() async {
    try {
      await _urgentPlatform.invokeMethod<void>('stopUrgentNotification', {
        'requestId': widget.request.id,
      });
    } catch (_) {
      // Older Android builds do not expose the native alarm service.
    }
  }

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
        !busy) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted && !busy && _issueKind != null) {
          _recheckAndRetry();
        }
      });
    }
  }

  Future<void> _recheckAndRetry() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!enabled) return; // لا تزال مغلقة

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

    // كلا الشرطين تحققا — امسح الخطأ وأعد الإرسال
    setState(() {
      error = null;
      _issueKind = null;
    });
    _respond(true);
  }

  Future<void> _respond(bool accept) async {
    // حارس ضد الإرسال المزدوج: منع إعادة الدخول أثناء تنفيذ استجابة حالية.
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      _issueKind = null;
    });
    try {
      await ref
          .read(mobileCommandsProvider)
          .respondLocation(widget.request.id, accept);
      if (!accept) {
        await _stopUrgentAlarm();
        return;
      }
      final position = await LocationService.current();
      final addressAr = await LocationService.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      await ref
          .read(mobileCommandsProvider)
          .submitLocationPoint(
            widget.request.id,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            altitude: position.altitude,
            speed: position.speed,
            heading: position.heading,
            isMock: position.isMocked,
            addressAr: addressAr,
          );
      await _stopUrgentAlarm();
      if (!mounted) return;
      // V17 §9: video path removed — needsVideo always false.
      if (widget.request.isTracking) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                LiveTrackingSessionPage(request: widget.request),
          ),
        );
      }
      ref.invalidate(myLocationRequestsProvider);
    } on GpsDisabledException {
      if (mounted) {
        setState(() {
          error = 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.';
          _issueKind = _LocationIssueKind.gpsOff;
        });
      }
    } on GpsPermissionDeniedException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          _issueKind = e.isDeniedForever
              ? _LocationIssueKind.deniedForever
              : _LocationIssueKind.permissionDenied;
        });
      }
    } on GpsAccuracyException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          _issueKind = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'حدث خطأ أثناء الاستجابة للطلب. أعد المحاولة.';
          _issueKind = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final scheme = Theme.of(context).colorScheme;
    final pending = request.status == 'pending';

    // 0451: عدّاد الانتهاء — تحذير بصري عند اقتراب انتهاء صلاحية الطلب
    final expiresIn = request.expiresAt?.difference(DateTime.now());
    final expiresSoon = pending &&
        expiresIn != null &&
        expiresIn.inSeconds > 0 &&
        expiresIn.inMinutes < 2;
    final expired = pending &&
        (expiresIn == null || expiresIn.inSeconds <= 0);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: pending
              ? (expiresSoon
                    ? scheme.error.withValues(alpha: .5)
                    : scheme.primary.withValues(alpha: .35))
              : scheme.outlineVariant.withValues(alpha: .6),
          width: pending ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── الترويسة: أيقونة + الطالب + الحالة ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: (pending
                          ? scheme.primary
                          : scheme.onSurfaceVariant)
                      .withValues(alpha: .12),
                  child: Icon(
                    request.isTracking
                        ? Icons.my_location_rounded
                        : Icons.location_on_rounded,
                    size: 24,
                    color: pending
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.isTracking
                            ? 'طلب تتبع مباشر'
                            : 'طلب مشاركة موقعك',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'من ${request.requesterName}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                MobileStatusPill(request.status),
              ],
            ),
            const SizedBox(height: 12),

            // ── تفاصيل الطلب ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _metaRow(
                    context,
                    icon: Icons.swap_horiz_rounded,
                    label: 'النوع',
                    value: _mode(request.mode),
                  ),
                  const SizedBox(height: 6),
                  _metaRow(
                    context,
                    icon: Icons.timer_outlined,
                    label: 'المدة',
                    value: '${request.durationMinutes} دقيقة',
                  ),
                  const SizedBox(height: 6),
                  _metaRow(
                    context,
                    icon: Icons.schedule_rounded,
                    label: 'وصل',
                    value: DateFormat(
                      'd MMM · h:mm a',
                      'ar',
                    ).format(request.requestedAt.toLocal()),
                  ),
                ],
              ),
            ),

            // ── سبب الطلب ──
            if (request.reason.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(
                      color: scheme.primary.withValues(alpha: .5),
                      width: 3,
                    ),
                  ),
                  color: scheme.surfaceContainerHighest.withValues(
                    alpha: .3,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  request.reason,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],

            // ─ـ تحذير الانتهاء الوشيك ──
            if (expiresSoon) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_bottom_rounded,
                      size: 16,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ينتهي الطلب خلال ${expiresIn.inMinutes + 1} دقيقة تقريباً',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (expired) ...[
              const SizedBox(height: 10),
              Text(
                'انتهت صلاحية هذا الطلب — لم يعد قابلاً للاستجابة.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],

            // ── أخطاء الموقع وأزرار المعالجة ──
            if (error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_issueKind == _LocationIssueKind.gpsOff) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Geolocator.openLocationSettings(),
                    icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                    label: const Text('فتح إعدادات الموقع'),
                  ),
                ),
              ],
              if (_issueKind == _LocationIssueKind.deniedForever) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Geolocator.openAppSettings(),
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: const Text('فتح إعدادات التطبيق'),
                  ),
                ),
              ],
              if (_issueKind == _LocationIssueKind.permissionDenied) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      final perm = await Geolocator.requestPermission();
                      if (!mounted) return;
                      if (perm == LocationPermission.always ||
                          perm == LocationPermission.whileInUse) {
                        setState(() {
                          error = null;
                          _issueKind = null;
                        });
                        _respond(true);
                      }
                    },
                    icon: const Icon(Icons.location_on_rounded, size: 18),
                    label: const Text('منح صلاحية الموقع'),
                  ),
                ),
              ],
            ],

            // ── أزرار الاستجابة ──
            if (pending && !expired) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => _respond(false),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('رفض'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => _respond(true),
                      icon: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.share_location_rounded,
                              size: 18,
                            ),
                      label: Text(busy ? 'جارٍ التنفيذ...' : 'موافقة ومشاركة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'مشاركتك لمرة واحدة ومسجلة في السجل — يمكنك الرفض بحرية.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// صف معلومات مصغر (أيقونة + تسمية + قيمة) — 0451
  Widget _metaRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  String _mode(String value) => switch (value) {
        'snapshot' => 'لقطة موقع',
        'video_5s' => 'موقع فقط',
        'location_video' => 'موقع فقط',
        'track_5' => 'تتبع 5 دقائق',
        'track_10' => 'تتبع 10 دقائق',
        'track_15' => 'تتبع 15 دقيقة',
        'track_30' => 'تتبع 30 دقيقة',
        _ => value,
      };
}

/// نوع مشكلة الموقع — يحدد زر الإعدادات المعروض.
enum _LocationIssueKind {
  gpsOff,
  permissionDenied,
  deniedForever,
}
