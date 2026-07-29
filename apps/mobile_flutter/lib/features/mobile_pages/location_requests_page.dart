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
                                  child: Icon(
                                    Icons.location_off_outlined,
                                    size: 52,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'لا توجد طلبات موقع',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
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
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) => _RequestCard(
                            request: items[index], access: access),
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
    final pending = request.status == 'pending';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'طلب من ${request.requesterName}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                MobileStatusPill(request.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_mode(request.mode)} · ${request.durationMinutes} دقيقة · ${DateFormat('d MMM - h:mm a', 'ar').format(request.requestedAt.toLocal())}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (_issueKind == _LocationIssueKind.gpsOff) ...[
                const SizedBox(height: 6),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Geolocator.openLocationSettings(),
                  icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                  label: const Text('فتح إعدادات الموقع'),
                ),
              ],
              if (_issueKind == _LocationIssueKind.deniedForever) ...[
                const SizedBox(height: 6),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Geolocator.openAppSettings(),
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('فتح إعدادات التطبيق'),
                ),
              ],
              if (_issueKind == _LocationIssueKind.permissionDenied) ...[
                const SizedBox(height: 6),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade800,
                    foregroundColor: Colors.white,
                  ),
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
              ],
            ],
            if (pending) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : () => _respond(false),
                      child: const Text('رفض'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : () => _respond(true),
                      child:
                          Text(busy ? 'جارٍ التنفيذ...' : 'موافقة ومشاركة'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
