import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    required this.name,
    this.photoUrl,
    this.radius = 22,
    this.announceName = true,
    super.key,
  });

  final String name;
  final String? photoUrl;
  final double radius;
  final bool announceName;

  static const String _publicMarker =
      '/storage/v1/object/public/employee-avatars/';
  static const String _authMarker =
      '/storage/v1/object/authenticated/employee-avatars/';

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '؟' : String.fromCharCode(trimmed.runes.first);
  }

  /// يستخرج مسار الملف داخل bucket employee-avatars من الرابط المخزّن.
  /// يُعيد null لو كان الرابط خارجيًا (mock/CDN) ليُحمَّل مباشرة.
  static String? _extractAvatarPath(String url) {
    for (final marker in [_publicMarker, _authMarker]) {
      final index = url.indexOf(marker);
      if (index >= 0) {
        final raw = url.substring(index + marker.length).split('?').first;
        try {
          return Uri.decodeComponent(raw);
        } catch (_) {
          return raw;
        }
      }
    }
    return null;
  }

  /// يحمّل صورة من bucket employee-avatars الخاص عبر SDK المصادق عليه.
  /// SDK يستخدم مسار `authenticated` تلقائيًا عند download ما يُفعّل سياسة
  /// RLS `employee_avatars_select` (المُضافة في 0211). بهذا يستمرbucket
  /// خاصًا بينما تظهر الصور للمستخدمين المُسجَّلين فقط.
  static Future<ImageProvider<Object>> _loadPrivateImage(String url) async {
    final path = _extractAvatarPath(url);
    if (path == null) {
      // رابط خارجي — حمّله مباشرة.
      return NetworkImage(url);
    }
    final Uint8List bytes = await Supabase.instance.client.storage
        .from('employee-avatars')
        .download(path);
    return MemoryImage(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diameter = radius * 2;
    final fallback = ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: Text(
          _initial,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.onPrimaryContainer,
            fontSize: radius * .72,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    final url = photoUrl?.trim();
    final cacheWidth =
        (diameter * MediaQuery.devicePixelRatioOf(context)).round();

    return Semantics(
      image: true,
      label: announceName ? 'الصورة الشخصية: $name' : null,
      excludeSemantics: true,
      child: ClipOval(
        child: SizedBox.square(
          dimension: diameter,
          child: url == null || url.isEmpty
              ? fallback
              : FutureBuilder<ImageProvider<Object>>(
                  future: _loadPrivateImage(url),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return fallback;
                    if (!snapshot.hasData) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          fallback,
                          Center(
                            child: SizedBox.square(
                              dimension: radius * .7,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Image(
                      image: ResizeImage.resizeIfNeeded(
                        cacheWidth,
                        null,
                        snapshot.data!,
                      ),
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => fallback,
                    );
                  },
                ),
        ),
      ),
    );
  }
}
