import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// عميل HTTP يعالج «JWT expired» (PGRST303) بتجديد الجلسة وإعادة الطلب مرة واحدة.
///
/// لماذا: مكتبة Supabase تقرّر انتهاء رمز الوصول بساعة الجهاز. إن كانت ساعة
/// الجهاز متأخرة (محاكي استُعيدت حالته، أو هاتف ضُبط وقته يدوياً وخاصةً مع
/// التوقيت الصيفي) يبقى الرمز «صالحاً» محلياً وهو منتهٍ على الخادم؛ فيرجع كل
/// طلب 401 ولا يجدّد التطبيق أبداً — تظهر الشاشات المخزّنة وتفشل البقية
/// (رُصد هذا على لوحة الشرف: 23 طلباً متتالياً 401 من جهاز واحد).
///
/// الحدود:
///  • فقط /rest/v1/ و /functions/v1/ و /storage/v1/ — طلبات /auth/v1/ تمرّ كما هي
///    (التجديد نفسه يمر من هنا ولا يجوز أن يستدعي نفسه).
///  • فقط http.Request (جسم معروف يمكن إعادة إرساله)؛ الرفع المتدفق يمر كما هو.
///  • إعادة واحدة فقط؛ وإن كانت الجلسة جُدّدت فعلاً منذ الطلب الفاشل (طلبات
///    متوازية) نعيد بالرمز الجديد دون تجديد ثانٍ.
class ExpiredJwtRetryClient extends http.BaseClient {
  ExpiredJwtRetryClient({
    required this.refreshAccessToken,
    required this.currentAccessToken,
    http.Client? inner,
  }) : _inner = inner ?? http.Client();

  /// يجدّد الجلسة ويرجع رمز الوصول الجديد (أو null إن تعذّر).
  final Future<String?> Function() refreshAccessToken;

  /// رمز الوصول الحالي في الجلسة (قد يكون جُدّد بطلب موازٍ).
  final String? Function() currentAccessToken;

  final http.Client _inner;

  static const _retryablePrefixes = [
    '/rest/v1/',
    '/functions/v1/',
    '/storage/v1/',
  ];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final retryable =
        request is http.Request &&
        _retryablePrefixes.any(request.url.path.startsWith);
    // نسخة احتياطية قبل الإرسال: الطلب نفسه لا يُرسل مرتين.
    final body = retryable ? request.bodyBytes : null;
    final response = await _inner.send(request);
    if (!retryable || response.statusCode != 401) return response;

    final bytes = await response.stream.toBytes();
    if (!_isExpiredJwt(bytes)) return _rebuild(response, bytes);

    final usedToken = _bearer(request.headers);
    final current = currentAccessToken();
    final token = current != null && current != usedToken
        ? current
        : await refreshAccessToken().catchError((Object _) => null);
    if (token == null || token == usedToken) return _rebuild(response, bytes);

    final retry = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..headers['Authorization'] = 'Bearer $token'
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = body!;
    return _inner.send(retry);
  }

  static bool _isExpiredJwt(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return text.contains('PGRST303') ||
        text.contains('JWT expired') ||
        text.contains('"exp" claim timestamp check failed');
  }

  static String? _bearer(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        final value = entry.value;
        return value.startsWith('Bearer ') ? value.substring(7) : value;
      }
    }
    return null;
  }

  static http.StreamedResponse _rebuild(
    http.StreamedResponse response,
    List<int> bytes,
  ) => http.StreamedResponse(
    Stream.value(bytes),
    response.statusCode,
    contentLength: bytes.length,
    request: response.request,
    headers: response.headers,
    isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection,
    reasonPhrase: response.reasonPhrase,
  );

  @override
  void close() => _inner.close();
}
