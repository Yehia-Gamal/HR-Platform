import 'dart:io';

import 'package:ahla_shabab_management_os/core/config/app_config.dart';

/// يتحقق من وجود اتصال فعلي بالإنترنت.
///
/// 0471-UX: الفحص القديم كان يطرق نقاط جوجل (gstatic) حصريًا، فعلى شبكات
/// تُبطئ أو تحجب نطاقات جوجل (بعض مشغّلي المحمول/الشبكات المؤسسية) كان
/// يُعلن «لا يوجد اتصال» بينما خادم التطبيق نفسه متاح تمامًا — وهذا هو
/// سبب البانر الأحمر الكاذب المتكرر.
///
/// الترتيب الآن: خادم التطبيق أولًا (أي رد HTTP — حتى 401/404 — يعني أن
/// المسار مفتوح)، ثم نقاط فحص محايدة كاحتياط، ثم DNS كحل أخير.
Future<bool> hasNetworkConnection() async {
  // 1) خادم التطبيق هو الطرف الذي يهمّنا فعليًا.
  final supabaseUrl = AppConfig.supabaseUrl;
  if (supabaseUrl.isNotEmpty) {
    if (await _reachable('$supabaseUrl/auth/v1/health')) return true;
  }

  // 2) نقاط فحص محايدة — لتمييز «الخادم تعطّل» عن «لا إنترنت أصلًا».
  const neutral = <String>[
    'https://connectivitycheck.gstatic.com/generate_204',
    'https://cp.cloudflare.com/generate_204',
  ];
  for (final endpoint in neutral) {
    if (await _reachable(endpoint)) return true;
  }

  // 3) آخر حل: DNS يعمل؟ (شبكات تمنع الفحص النصي لكن تمرر التطبيقات)
  for (final host in const ['dns.google', 'one.one.one.one']) {
    try {
      final result = await InternetAddress.lookup(host).timeout(
        const Duration(seconds: 3),
      );
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) return true;
    } catch (_) {
      // جرّب المضيف التالي.
    }
  }
  return false;
}

/// أي استجابة HTTP (حتى 4xx/5xx) تعني أن المضيف قابل للوصول.
/// لا نطلب مفاتيح ولا نحمّل بيانات — يكفي أن تُغلق الاتصلة بلا خطأ شبكة.
Future<bool> _reachable(String url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);
  try {
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 4));
    final response = await request.close().timeout(const Duration(seconds: 4));
    await response.drain<void>();
    return response.statusCode > 0;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
