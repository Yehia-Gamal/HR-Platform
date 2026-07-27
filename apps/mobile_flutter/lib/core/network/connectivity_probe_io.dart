import 'dart:io';

/// يتحقق من وجود اتصال فعلي بالإنترنت عبر DNS lookup.
/// يحاول عدة خوادم DNS لتجنب الإيجابيات الخاطئة عند فشل خادم واحد مؤقتاً.
Future<bool> hasNetworkConnection() async {
  // نحاول عدة خوادم — نجاح أي واحد يعني أن الإنترنت متصل
  final hosts = ['dns.google', 'one.one.one.one', 'dns.quad9.net'];
  for (final host in hosts) {
    try {
      final result = await InternetAddress.lookup(host).timeout(
        const Duration(seconds: 3),
      );
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {
      // نحاول الخادم التالي
    }
  }
  return false;
}
