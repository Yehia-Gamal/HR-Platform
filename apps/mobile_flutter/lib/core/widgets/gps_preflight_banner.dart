import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// مزوّد حالة GPS — يُحدَّث عند العودة من الإعدادات أو تغيّر حالة التطبيق.
final gpsPreflightProvider =
    FutureProvider.autoDispose<GpsPreflightResult>((ref) {
  return LocationService.preflight();
});

/// شريط تحذيري يظهر أعلى الشاشة عند إيقاف GPS أو رفض صلاحية الموقع.
/// يختفي تلقائياً عند جاهزية GPS. يُستخدم في صفحات تعتمد على الموقع.
class GpsPreflightBanner extends ConsumerStatefulWidget {
  const GpsPreflightBanner({super.key});

  @override
  ConsumerState<GpsPreflightBanner> createState() =>
      _GpsPreflightBannerState();
}

class _GpsPreflightBannerState extends ConsumerState<GpsPreflightBanner>
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

  /// عند العودة من إعدادات الموقع أو التطبيق — نعيد فحص جاهزية GPS.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(gpsPreflightProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preflight = ref.watch(gpsPreflightProvider);

    return preflight.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (result) {
        if (result.isReady) return const SizedBox.shrink();

        final Color color;
        final IconData icon;
        final String text;
        final String buttonLabel;
        final VoidCallback onTap;

        if (result.isGpsOff) {
          color = Colors.orange.shade800;
          icon = Icons.gps_off_rounded;
          text = 'خدمة الموقع (GPS) غير مفعلة';
          buttonLabel = 'تفعيل الموقع';
          onTap = () => Geolocator.openLocationSettings();
        } else if (result.isDeniedForever) {
          color = Colors.red.shade700;
          icon = Icons.location_disabled_rounded;
          text = 'صلاحية الموقع مرفوضة نهائيًا';
          buttonLabel = 'فتح الإعدادات';
          onTap = () => Geolocator.openAppSettings();
        } else {
          color = Colors.amber.shade800;
          icon = Icons.location_off_rounded;
          text = 'صلاحية الموقع غير ممنوحة';
          buttonLabel = 'منح الصلاحية';
          onTap = () async {
            await Geolocator.requestPermission();
            ref.invalidate(gpsPreflightProvider);
          };
        }

        return AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          offset: Offset.zero,
          child: Material(
            color: color,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onTap,
                      child: Text(
                        buttonLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
