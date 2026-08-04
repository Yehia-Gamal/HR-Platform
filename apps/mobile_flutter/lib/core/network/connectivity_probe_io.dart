import 'dart:io';

/// يتحقق من وجود اتصال فعلي بالإنترنت عبر DNS lookup ثم طلب HTTP حقيقي.
/// يجمع بين الفحصين لتجنب الإيجابيات الخاطئة (شبكات captive portal
/// أو بيئات تُجيب على DNS دون فتح طريق بيانات فعلي).
Future<bool> hasNetworkConnection() async {
  final hosts = ['dns.google', 'one.one.one.one', 'dns.quad9.net'];
  for (final host in hosts) {
    try {
      final result = await InternetAddress.lookup(host).timeout(
        const Duration(seconds: 3),
      );
      if (result.isEmpty || result.first.rawAddress.isEmpty) {
        continue;
      }
    } catch (_) {
      continue;
    }
    // DNS نجح — تأكد من مسار HTTP حقيقي قبل الإعلان عن الاتصال.
    return await _httpProbe();
  }
  return false;
}

/// طلب 204 إلى نقطة فحص موثوقة — لا يُحمّل بيانات ولا يتطلب مفاتيح.
Future<bool> _httpProbe() async {
  const endpoints = [
    'https://connectivitycheck.gstatic.com/generate_204',
    'https://www.gstatic.com/generate_204',
  ];
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3);
  try {
    for (final endpoint in endpoints) {
      try {
        final request = await client
            .getUrl(Uri.parse(endpoint))
            .timeout(const Duration(seconds: 3));
        final response = await request.close().timeout(
              const Duration(seconds: 3),
            );
        await response.drain<void>();
        if (response.statusCode == 204 || response.statusCode == 200) {
          return true;
        }
      } catch (_) {
        // جرّب نقطة الفحص التالية.
      }
    }
    return false;
  } finally {
    client.close(force: true);
  }
}
