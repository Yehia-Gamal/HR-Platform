import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:flutter/foundation.dart';
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

  void _showWebLocationHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline, color: Colors.blue, size: 36),
        title: const Text('تفعيل الموقع في المتصفح', textAlign: TextAlign.center),
        content: const Text(
          'للسماح بالوصول إلى موقعك من المتصفح:\n'
          '1. انقر على أيقونة القفل أو الأذونات بجانب رابط الصفحة (شريط العنوان).\n'
          '2. اختر "الموقع" (Location) واضبطه على "سماح" (Allow).\n'
          '3. أعد تحديث الصفحة.',
          textAlign: TextAlign.start,
          style: TextStyle(height: 1.6),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً، فهمت'),
          ),
        ],
      ),
    );
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
          onTap = () {
            if (kIsWeb) {
              _showWebLocationHelp(context);
            } else {
              Geolocator.openLocationSettings();
            }
          };
        } else if (result.isDeniedForever) {
          color = Colors.red.shade700;
          icon = Icons.location_disabled_rounded;
          text = 'صلاحية الموقع مرفوضة نهائيًا';
          buttonLabel = 'فتح الإعدادات';
          onTap = () {
            if (kIsWeb) {
              _showWebLocationHelp(context);
            } else {
              Geolocator.openAppSettings();
            }
          };
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

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: color.withValues(alpha: 0.16),
                    foregroundColor: color,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onTap,
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
