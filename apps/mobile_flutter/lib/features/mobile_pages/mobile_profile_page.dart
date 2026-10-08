import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/theme/brand_gradients.dart';
import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/core/widgets/host_app_bar_scope.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/widgets/phone_display.dart';
import 'package:ahla_shabab_management_os/core/theme/theme_mode_controller.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_team_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MobileProfilePage extends ConsumerWidget {
  const MobileProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(mobileProfileProvider);
    return Scaffold(
      // تبويب «حسابي» تحت رأس المساحة (فيه الشعار) — لا شريط ثانٍ
      appBar: HostAppBarScope.isActive(context)
          ? null
          : AppBar(
              title: const Text('حسابي وملفي الوظيفي'),
              actions: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Center(child: BrandLogoMark(size: 34)),
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mobileProfileProvider);
          ref.invalidate(attendanceStateProvider);
          ref.invalidate(mobileTeamProvider);
          ref.invalidate(myPasskeysProvider);
        },
        child: profile.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 120),
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 16),
                Center(
                  child: FilledButton.icon(
                    onPressed: () {
                      ref.invalidate(mobileProfileProvider);
                      ref.invalidate(attendanceStateProvider);
                      ref.invalidate(mobileTeamProvider);
                      ref.invalidate(myPasskeysProvider);
                    },
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (item) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _DigitalIdCardWidget(item: item),
              const SizedBox(height: 14),
              const _MyDailyStatusCard(),
              const SizedBox(height: 14),
              const _TeamDailyStatusCard(),
              const SizedBox(height: 14),
              _InfoSection(item: item),
              const SizedBox(height: 14),
              const _DeviceSecuritySection(),
              const SizedBox(height: 14),
              const _ThemePreferenceCard(),
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: const Text('تغيير الرقم السري'),
                  subtitle: const Text('تحديث بيانات الدخول الخاصة بك'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => const _ChangePasswordDialog(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _ShareLocationCard(),
              const SizedBox(height: 14),
              const _AppVersionCard(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePreferenceCard extends ConsumerWidget {
  const _ThemePreferenceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مظهر التطبيق',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'اختر المظهر أو اتركه متوافقًا مع إعداد الجهاز.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('النظام'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('فاتح'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('داكن'),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  ref.read(themeModeProvider.notifier).setMode(selection.first);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DigitalIdCardWidget extends ConsumerStatefulWidget {
  const _DigitalIdCardWidget({required this.item});
  final MobileProfile item;

  @override
  ConsumerState<_DigitalIdCardWidget> createState() => _DigitalIdCardWidgetState();
}

class _DigitalIdCardWidgetState extends ConsumerState<_DigitalIdCardWidget> {
  bool _isUploading = false;

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (picked == null) return;

    if (!mounted) return;
    setState(() => _isUploading = true);
    try {
      final originalBytes = await picked.readAsBytes();
      if (originalBytes.length > 5 * 1024 * 1024) {
        throw StateError('حجم الصورة أكبر من 5 ميجابايت.');
      }
      final sourceExt = picked.name.split('.').last.toLowerCase();
      if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(sourceExt)) {
        throw StateError('الصيغة غير مدعومة. استخدم JPG أو PNG أو WEBP.');
      }
      final bytes = await _prepareSquareAvatar(originalBytes);
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final path = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.png';
      final bucket = Supabase.instance.client.storage.from('employee-avatars');

      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/png', upsert: false),
      ).timeout(const Duration(seconds: 60));
      final rawUrl = bucket.getPublicUrl(path);

      await Supabase.instance.client.rpc("set_my_photo_url", params: {"p_photo_url": rawUrl}).timeout(const Duration(seconds: 20));
      final previousPath = _employeeAvatarPath(widget.item.photoUrl);
      if (previousPath != null && previousPath != path) {
        try {
          await bucket.remove([previousPath]);
        } catch (_) {
          // The new photo is already active; cleanup can be retried later.
        }
      }
      ref.invalidate(mobileProfileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الصورة بنجاح')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<Uint8List> _prepareSquareAvatar(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final source = frame.image;
    try {
      if (source.width < 512 || source.height < 512) {
        throw StateError('دقة الصورة منخفضة. استخدم صورة لا تقل عن 512×512 بكسل.');
      }
      final sourceEdge = source.width < source.height
          ? source.width.toDouble()
          : source.height.toDouble();
      final outputEdge = sourceEdge > 1024 ? 1024 : sourceEdge.round();
      final sourceRect = ui.Rect.fromLTWH(
        (source.width - sourceEdge) / 2,
        (source.height - sourceEdge) / 2,
        sourceEdge,
        sourceEdge,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        sourceRect,
        ui.Rect.fromLTWH(0, 0, outputEdge.toDouble(), outputEdge.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(outputEdge, outputEdge);
      picture.dispose();
      try {
        final data = await output.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('تعذر تجهيز الصورة.');
        final result = data.buffer.asUint8List();
        if (result.length > 5 * 1024 * 1024) {
          throw StateError('تعذر ضغط الصورة إلى أقل من 5 ميجابايت.');
        }
        return result;
      } finally {
        output.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  String? _employeeAvatarPath(String? url) {
    if (url == null || url.isEmpty) return null;
    for (final marker in [
      '/storage/v1/object/public/employee-avatars/',
      '/storage/v1/object/authenticated/employee-avatars/',
    ]) {
      final index = url.indexOf(marker);
      if (index < 0) continue;
      final raw = url.substring(index + marker.length).split('?').first;
      try {
        return Uri.decodeComponent(raw);
      } catch (_) {
        return raw;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: BrandGradients.hero,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: .18),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimaryStrong.withValues(alpha: .28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Logo + Title + Verified Badge
            Row(
              children: [
                const BrandLogoMark(inverse: true, size: 32),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'بطاقة الهوية الوظيفية الذكية',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'منظومة الموارد البشرية والعمليات',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: .6)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, size: 13, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text(
                        'موثّق رسمياً',
                        style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 26),

            // Middle section: Avatar (with upload trigger) + Details
            Row(
              children: [
                Semantics(
                  button: true,
                  enabled: !_isUploading,
                  label: 'تغيير الصورة الشخصية',
                  child: GestureDetector(
                    onTap: _isUploading ? null : _pickAndUploadPhoto,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFBBF24).withValues(alpha: .8),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFBBF24).withValues(alpha: .25),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          AppAvatar(
                            name: item.fullNameAr,
                            photoUrl: item.photoUrl,
                            radius: 32,
                          ),
                          if (_isUploading)
                            const Positioned.fill(
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                            )
                          else
                            PositionedDirectional(
                              bottom: 0,
                              end: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFBBF24),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 12,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.fullNameAr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (item.fullNameEn != null && item.fullNameEn!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.fullNameEn!,
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24).withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFBBF24).withValues(alpha: .45),
                          ),
                        ),
                        child: Text(
                          item.jobTitle ?? 'موظف',
                          style: const TextStyle(
                            color: Color(0xFFFDE68A),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.corporate_fare_rounded, size: 13, color: Colors.white60),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${item.department ?? "الإدارة العامة"} • ${item.branch ?? "مقر الجمعية الرئيسي"}',
                              style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Footer Bar: Employee Code with Copy Action + Worksite
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    'كود الموظف: ${PhoneDisplay.stripCountryCode(item.employeeCode)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: PhoneDisplay.stripCountryCode(item.employeeCode)));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم نسخ كود الموظف'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: .8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // موقع العمل قد يطول («العمل من خلال المجمع بدوام كامل») —
                  // يأخذ المساحة المتبقية ويُختصر بدل تجاوز البطاقة.
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          item.workSite != null && item.workSite!.isNotEmpty
                              ? Icons.location_on_outlined
                              : Icons.business_rounded,
                          size: 13,
                          color: Colors.white60,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            item.workSite != null && item.workSite!.isNotEmpty
                                ? item.workSite!
                                : (item.branch ?? 'مقر الجمعية الرئيسي'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyDailyStatusCard extends ConsumerWidget {
  const _MyDailyStatusCard();

  Color _attendanceColor(String? status) => switch (status) {
    'present' => const Color(0xFF0F9F6E),
    'late' => const Color(0xFFD97706),
    'absent' => const Color(0xFFDC2626),
    'convoy' => const Color(0xFF7C3AED),
    'fundraising' => const Color(0xFF0D9488),
    'mission' => const Color(0xFF2563EB),
    'on_leave' => const Color(0xFF0284C7),
    'holiday' || 'weekend' => const Color(0xFF6B7280),
    'partial' => const Color(0xFFD97706),
    'pending' => Colors.blueGrey,
    _ => Colors.grey,
  };

  String _attendanceLabel(String? status) => switch (status) {
    'present' => 'حاضر في الجمعية',
    'late' => 'متأخر',
    'absent' => 'غائب',
    'convoy' => 'في قافلة',
    'fundraising' => 'في فاندي ترفيهي',
    'mission' => 'في مأمورية',
    'on_leave' => 'إجازة',
    'holiday' => 'عطلة',
    'weekend' => 'إجازة أسبوعية',
    'partial' => 'حضور جزئي',
    'pending' => 'قيد التحقق',
    'not_recorded' => 'لم تسجل بعد',
    'checked_out' => 'انصرفت',
    'missing_checkout' => 'لم يُسجَّل الانصراف',
    'exempt' => 'معفى من البصمة',
    null => 'لم تسجل بعد',
    // لا يظهر رمز إنجليزي خام للمستخدم
    _ => 'متابعة الدوام',
  };

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('hh:mm a', 'ar').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attStateAsync = ref.watch(attendanceStateProvider);

    return attStateAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (att) {
        final status = att.todayStatus;
        final color = _attendanceColor(status);
        final label = _attendanceLabel(status);
        final checkIn = att.todayCheckInAt;
        final checkOut = att.todayCheckOutAt;
        final todayStr = DateFormat('EEEE، d MMMM', 'ar').format(DateTime.now());

        String hint;
        if (att.missionToday != null) {
          final mType = switch (att.missionToday!.type) {
            'convoy' => 'قافلة',
            'fundraising' => 'يوم ترفيهي (فاندي)',
            _ => 'مأمورية عمل',
          };
          hint = '$mType نشطة اليوم';
        } else if (status == 'on_leave' || status == 'leave') {
          // كانت تظهر «بانتظار تسجيل بصمة الحضور» مع حالة «إجازة».
          hint = 'أنت في إجازة اليوم — لا يلزم تسجيل الحضور';
        } else if (status == 'weekend' || status == 'holiday') {
          hint = 'لا يوجد دوام اليوم';
        } else if (att.suggestedAction == 'CHECK_IN') {
          hint = 'بانتظار تسجيل بصمة الحضور';
        } else if (att.suggestedAction == 'CHECK_OUT') {
          hint = 'أنت قيد العمل — يُرجى تسجيل الانصراف عند المغادرة';
        } else if (att.suggestedAction == 'DAY_COMPLETED') {
          hint = 'تم اكتمال دوام اليوم بنجاح';
        } else {
          hint = 'متابعة الدوام اليومي';
        }

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: (status == null || status == 'absent')
                  ? theme.colorScheme.outlineVariant.withValues(alpha: .6)
                  : color.withValues(alpha: .35),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.fingerprint_rounded,
                        color: color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'حالتي اليوم',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            todayStr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: .6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    _MiniStatTile(
                      icon: Icons.login_rounded,
                      value: _fmtTime(checkIn),
                      label: 'الحضور',
                    ),
                    _MiniStatTile(
                      icon: Icons.logout_rounded,
                      value: _fmtTime(checkOut),
                      label: 'الانصراف',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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

class _TeamDailyStatusCard extends ConsumerWidget {
  const _TeamDailyStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final teamAsync = ref.watch(mobileTeamProvider);

    return teamAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (members) {
        if (members.isEmpty) return const SizedBox.shrink();

        final present = members.where((m) => m.attendanceStatus == 'present').length;
        final late = members.where((m) => m.attendanceStatus == 'late').length;
        final absent = members.where((m) => m.attendanceStatus == 'absent').length;
        final onLeave = members.where((m) => m.attendanceStatus == 'on_leave').length;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.groups_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'حالة فريقي اليوم',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${arMembers(members.length)} في الفريق',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MyTeamPage()),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('عرض الكل'),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    _TeamCounterBadge(
                      count: present,
                      label: 'حاضر',
                      color: Colors.green,
                    ),
                    _TeamCounterBadge(
                      count: late,
                      label: 'متأخر',
                      color: Colors.orange,
                    ),
                    _TeamCounterBadge(
                      count: absent,
                      label: 'غائب',
                      color: Colors.red,
                    ),
                    _TeamCounterBadge(
                      count: onLeave,
                      label: 'إجازة',
                      color: Colors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: members.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final m = members[idx];
                      final stColor = switch (m.attendanceStatus) {
                        'present' => const Color(0xFF0F9F6E),
                        'late' => const Color(0xFFD97706),
                        'absent' => const Color(0xFFDC2626),
                        'convoy' => const Color(0xFF7C3AED),
                        'fundraising' => const Color(0xFF0D9488),
                        'mission' => const Color(0xFF2563EB),
                        'on_leave' => const Color(0xFF0284C7),
                        _ => Colors.grey,
                      };
                      return InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EmployeeProfilePage(
                              employeeId: m.id,
                              employeeName: m.name,
                            ),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(24),
                        child: Stack(
                          children: [
                            AppAvatar(name: m.name, photoUrl: m.photoUrl, radius: 22),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: stColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.colorScheme.surface,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

class _MiniStatTile extends StatelessWidget {
  const _MiniStatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamCounterBadge extends StatelessWidget {
  const _TeamCounterBadge({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.item});
  final MobileProfile item;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MobileSectionHeader(title: 'البيانات الوظيفية'),
          const SizedBox(height: 10),
          _row(Icons.account_tree_outlined, 'الإدارة', item.department),
          _row(Icons.badge_outlined, 'المسمى الوظيفي', item.jobTitle),
          _row(Icons.business_outlined, 'الفرع', item.branch),
          _row(Icons.location_on_outlined, 'موقع العمل', item.workSite),
          _row(
            Icons.supervisor_account_outlined,
            'المدير المباشر',
            item.managerName,
          ),
          _phoneRow(context, item.phoneE164),
          _row(
            Icons.event_outlined,
            'تاريخ التعيين',
            item.hireDate == null
                ? null
                : DateFormat('d MMM y', 'ar').format(item.hireDate!),
          ),
          /// V17 §4.2.5 — Contract end date hidden (not relevant for current org).
        ],
      ),
    ),
  );

  Widget _phoneRow(BuildContext context, String? phone) {
    final display = phone?.fixIntlPhoneOrder() ?? '—';
    return InkWell(
      onTap: phone == null || phone.isEmpty
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: display));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم نسخ رقم الهاتف'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.phone_outlined, size: 20),
            const SizedBox(width: 16),
            const Text('الهاتف'),
            const SizedBox(width: 12),
            Expanded(
              child: Directionality(
                textDirection: ui.TextDirection.ltr,
                child: Text(
                  display,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 16),
        Text(label),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value ?? '—',
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// V17 §4.2.3/§4.2.4 — _DocumentsSection and _AssetsSection removed;
/// re-add when the backend journey is ready.

class _DeviceSecuritySection extends ConsumerStatefulWidget {
  const _DeviceSecuritySection();

  @override
  ConsumerState<_DeviceSecuritySection> createState() =>
      _DeviceSecuritySectionState();
}

class _DeviceSecuritySectionState
    extends ConsumerState<_DeviceSecuritySection> {
  bool _registering = false;
  String? _revokingId;
  bool? _localBiometricSupported;

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
  }

  Future<void> _checkBiometricSupport() async {
    try {
      final localAuth = LocalAuthentication();
      final supported = await localAuth.isDeviceSupported() &&
          await localAuth.canCheckBiometrics;
      if (mounted) setState(() => _localBiometricSupported = supported);
    } catch (_) {
      if (mounted) setState(() => _localBiometricSupported = false);
    }
  }

  Future<void> _register() async {
    setState(() => _registering = true);
    try {
      await ref.read(mobileCommandsProvider).registerPasskey();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل الجهاز بنجاح.')),
        );
      }
    } catch (error) {
      if (mounted) {
        final msg = error.toString();
        final text = msg.contains('cancelled')
            ? 'تم إلغاء التحقق.'
            : msg.contains('الجهاز لا يدعم')
                ? 'فعّل قفل الشاشة (نقش أو PIN) من إعدادات الجهاز.'
                : 'تعذر تسجيل الجهاز. أعد المحاولة.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _revoke(PasskeyDevice device) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء الجهاز الموثوق'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سيتم منع ${device.deviceLabel} من إثبات الحضور مستقبلًا.'),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLength: 240,
              decoration: const InputDecoration(
                labelText: 'سبب الإلغاء',
                hintText: 'مثال: تم تغيير الهاتف أو فقد الجهاز',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إلغاء الجهاز'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    if (!mounted) {
      reasonController.dispose();
      return;
    }
    setState(() => _revokingId = device.id);
    try {
      await ref
          .read(mobileCommandsProvider)
          .revokePasskey(device.id, reasonController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء الجهاز.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => _revokingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final devices = ref.watch(myPasskeysProvider);
    final formatter = DateFormat('d MMMM y، h:mm a', 'ar');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MobileSectionHeader(
              title: 'أمان الجهاز والبصمة',
              subtitle: 'إدارة أجهزتك الموثوقة لإثبات الحضور.',
            ),
            const SizedBox(height: 12),
            // حالة دعم البصمة على هذا الجهاز
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _localBiometricSupported == true
                    ? scheme.primaryContainer.withValues(alpha: 0.4)
                    : _localBiometricSupported == false
                        ? scheme.errorContainer.withValues(alpha: 0.4)
                        : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _localBiometricSupported == true
                        ? Icons.fingerprint
                        : _localBiometricSupported == false
                            ? Icons.fingerprint
                            : Icons.hourglass_empty_rounded,
                    color: _localBiometricSupported == true
                        ? scheme.primary
                        : _localBiometricSupported == false
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'أمان هذا الجهاز',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          _localBiometricSupported == null
                              ? 'جارٍ الفحص…'
                              : _localBiometricSupported!
                                  ? 'الجهاز يدعم البصمة وقفل الشاشة الآمن'
                                  : 'لا توجد بصمة — يمكن استخدام النقش أو PIN',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // قائمة الأجهزة المسجلة
            devices.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تعذر تحميل الأجهزة. اسحب لأسفل لإعادة المحاولة.',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.phonelink_lock_outlined,
                          size: 36,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'لا توجد أجهزة مسجلة',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'سجل هذا الجهاز لاستخدام البصمة أو النقش في إثبات الحضور.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                // الأجهزة في حالات نهاية (مستبدل/ملغى/محظور) تُطوى في لوحة
                // مختصرة — منع تكديس بطاقات كاملة كما في القوائم الطويلة.
                const terminal = {'revoked', 'replaced', 'blocked', 'auto_revoked'};
                final live =
                    items.where((d) => !terminal.contains(d.status)).toList();
                final past =
                    items.where((d) => terminal.contains(d.status)).toList();
                return Column(
                  children: [
                    ...live.map((device) {
                      final active = device.status == 'active';
                      final isRevoking = _revokingId == device.id;
                      return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: active
                                ? scheme.primary.withValues(alpha: 0.3)
                                : scheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: active
                                      ? scheme.primaryContainer
                                      : scheme.surfaceContainerHighest,
                                  child: Icon(
                                    active
                                        ? Icons.phonelink_lock
                                        : Icons.mobile_off_outlined,
                                    size: 20,
                                    color: active
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        device.deviceLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      MobileStatusPill(
                                        active ? 'active' : device.status,
                                      ),
                                    ],
                                  ),
                                ),
                                if (device.trusted)
                                  Tooltip(
                                    message: 'موثوق من الخادم',
                                    child: Icon(
                                      Icons.verified_user_outlined,
                                      color: scheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                            const Divider(height: 18),
                            Text(
                              'أضيف: ${formatter.format(device.createdAt.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              device.lastUsedAt == null
                                  ? 'لم يُستخدم بعد'
                                  : 'آخر استخدام: ${formatter.format(device.lastUsedAt!.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (active) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed:
                                      isRevoking ? null : () => _revoke(device),
                                  icon: isRevoking
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.block_outlined),
                                  label: const Text('إلغاء هذا الجهاز'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                    }),
                    if (past.isNotEmpty)
                      _InactiveDevicesPanel(devices: past),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _registering ? null : _register,
                icon: _registering
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_moderator_outlined),
                label: const Text('تسجيل هذا الجهاز'),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PasskeyDevicesPage(),
                  ),
                ),
                icon: const Icon(Icons.devices_outlined),
                label: const Text('إدارة جميع الأجهزة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// الأجهزة السابقة (مستبدلة/ملغاة/محظورة) — لوحة مطوية مختصرة بدل بطاقات
/// كاملة لكل جهاز، لتفادي تكديس القوائم الطويلة.
class _InactiveDevicesPanel extends StatelessWidget {
  const _InactiveDevicesPanel({required this.devices});

  final List<PasskeyDevice> devices;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: Icon(
            Icons.history_rounded,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(
            'أجهزة سابقة (${devices.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'معطّلة أو مستبدلة — لا تُستخدم لإثبات الحضور.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: [
            for (final d in devices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.mobile_off_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d.deviceLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    MobileStatusPill(d.status),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // 0457: تحقق من قوة كلمة المرور على الخادم أولاً مع مسار احتياطي آمن
      try {
        final strengthResult = await client
            .rpc<Map<String, dynamic>>('validate_password_strength',
                params: {'p_password': _passwordController.text})
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
      } catch (_) {
        // في حال تعذر الوصول لدالة الخادم، نتحقق محلياً (بنفس حد.validator)
        if (_passwordController.text.length < 12) {
          if (mounted) {
            setState(() => _error = 'الرقم السري يجب أن يكون 12 حرفًا على الأقل.');
          }
          return;
        }
      }

      final response = await client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      if (response.user == null) {
        throw Exception('تعذر التحديث');
      }

      // SEC: إزالة علامة must_change_password في حال تم تعيينها بواسطة الإدارة
      try {
        await client.rpc<dynamic>('clear_must_change_password')
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // ثانوي
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('تم تغيير الرقم السري بنجاح')),
        );
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      String errorMsg;
      if (msg.contains('reauthentication') || msg.contains('recent login')) {
        errorMsg = 'يجب إعادة تسجيل الدخول قبل تغيير كلمة المرور. سجّل الدخول ثم أعد المحاولة.';
      } else if (msg.contains('session') || msg.contains('expired')) {
        errorMsg = 'انتهت صلاحية الجلسة. سجّل الدخول من جديد.';
      } else {
        errorMsg = 'تعذر تغيير الرقم السري. تحقق من المتطلبات وأعد المحاولة.';
      }
      if (mounted) setState(() => _error = errorMsg);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تغيير الرقم السري بأمان. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: bottomInset > 0 ? bottomInset + 24 : 48,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تغيير الرقم السري',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'الرقم السري الجديد',
                helperText: '12 حرفًا على الأقل — يُفضَّل مزيج حروف وأرقام',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (val) {
                if (val == null || val.length < 12) {
                  return 'الرقم السري يجب أن يكون 12 حرفًا على الأقل';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: 'تأكيد الرقم السري',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (val) {
                if (val != _passwordController.text) {
                  return 'كلمتا المرور غير متطابقتين';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isLoading ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('حفظ الرقم السري'),
            ),
          ],
        ),
      ),
    );
  }
}
class _AppVersionCard extends StatefulWidget {
  const _AppVersionCard();

  @override
  State<_AppVersionCard> createState() => _AppVersionCardState();
}

class _AppVersionCardState extends State<_AppVersionCard> {
  String _version = '';
  String _deviceModel = '';
  String _osVersion = '';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = '${packageInfo.version}+${packageInfo.buildNumber}';

      String model;
      String os;
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isIOS) {
          final info = await deviceInfo.iosInfo;
          model = info.name;
          os = 'iOS ${info.systemVersion}';
        } else {
          final info = await deviceInfo.androidInfo;
          model = '${info.manufacturer} ${info.model}'.trim();
          os = 'Android ${info.version.release}';
        }
      } catch (_) {
        model = '';
        os = '';
      }

      if (mounted) {
        setState(() {
          _version = version;
          _deviceModel = model;
          _osVersion = os;
        });
      }
    } catch (_) {
      // PackageInfo failed — leave empty.
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'معلومات التطبيق والجهاز',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (_version.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              _infoRow(Icons.info_outline, 'الإصدار', _version, muted),
              if (_deviceModel.isNotEmpty)
                _infoRow(Icons.phone_android, 'الجهاز', _deviceModel, muted),
              if (_osVersion.isNotEmpty)
                _infoRow(Icons.android, 'نظام التشغيل', _osVersion, muted),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: style?.color),
          const SizedBox(width: 8),
          Text('$label: ', style: style?.copyWith(fontWeight: FontWeight.w700)),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}

/// بطاقة مشاركة الموقع استباقياً مع المدير.
class _ShareLocationCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ShareLocationCard> createState() => _ShareLocationCardState();
}

class _ShareLocationCardState extends ConsumerState<_ShareLocationCard> {
  bool _sending = false;
  String? _result;

  Future<void> _share() async {
    setState(() { _sending = true; _result = null; });
    try {
      final location = await LocationService.current();
      // فشل العنوان (reverse geocode) لا يمنع الإرسال — الموقع هو الأهم.
      String addr = 'غير متاح';
      try {
        addr = await LocationService.reverseGeocode(
              location.latitude, location.longitude,
            ) ??
            'غير متاح';
      } catch (_) {
        addr = 'غير متاح';
      }
      await ref.read(mobileCommandsProvider)
          .shareMyLocationProactively(
            latitude: location.latitude,
            longitude: location.longitude,
            accuracy: location.accuracy,
            durationMinutes: 30,
            reason: 'مشاركة موقع استباقية من البروفايل',
            batteryLevel: null,
          );
      if (mounted) {
        setState(() {
          _result = 'تم إرسال موقعك للمدير المباشر. العنوان: $addr';
          _sending = false;
        });
      }
    } catch (e, stack) {
      if (mounted) {
        setState(() {
          _result = humanizeError(e, stack);
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'مشاركة موقعي مع المدير',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'إرسل موقعك الحالي مباشرة لمديرك دون انتظار طلب منه.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            if (_result != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_result!, style: TextStyle(fontSize: 12)),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _sending ? null : _share,
              icon: _sending
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_sending ? 'جارٍ الإرسال…' : 'مشاركة موقعي الآن'),
            ),
          ],
        ),
      ),
    );
  }
}
