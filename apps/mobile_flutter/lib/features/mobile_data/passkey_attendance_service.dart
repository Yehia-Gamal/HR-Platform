import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final passkeyAttendanceServiceProvider = Provider<PasskeyAttendanceService>((
  ref,
) {
  return PasskeyAttendanceService(
    client: ref.watch(supabaseProvider),
    authenticator: PasskeyAuthenticator(debugMode: kDebugMode),
  );
});

/// Executes server-authored WebAuthn ceremonies for attendance.
///
/// The operating system keeps the private key and biometric material. The app
/// only forwards the public WebAuthn response to the trusted Edge Function.
class PasskeyAttendanceService {
  PasskeyAttendanceService({
    required SupabaseClient client,
    required PasskeyAuthenticator authenticator,
  }) : _client = client,
       _authenticator = authenticator;

  final SupabaseClient _client;
  final PasskeyAuthenticator _authenticator;

  // The package's replacement availability API is platform-specific, while
  // this service intentionally exposes one cross-platform boolean.
  // ignore: deprecated_member_use
  Future<bool> isSupported() => _authenticator.canAuthenticate();

  Future<void> register({String deviceLabel = 'هاتف الموظف'}) async {
    final challengeResponse = await _client.functions.invoke(
      'webauthn-challenge',
      body: const {'type': 'register'},
    );
    _throwOnFunctionError(challengeResponse);

    final request = RegisterRequestType.fromJson(_map(challengeResponse.data));
    final RegisterResponseType credential;
    try {
      credential = await _authenticator.register(request);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('cancel') || msg.contains('dismissed')) {
        throw StateError('تم إلغاء التحقق بالبصمة.');
      }
      throw StateError('تعذر فتح نافذة البصمة على الجهاز: $msg');
    }

    final finishResponse = await _client.functions.invoke(
      'passkey-register',
      body: {
        'deviceLabel': deviceLabel,
        'response': {
          'id': credential.id,
          'rawId': credential.rawId,
          'type': 'public-key',
          'response': {
            'clientDataJSON': credential.clientDataJSON,
            'attestationObject': credential.attestationObject,
            'transports': credential.transports.whereType<String>().toList(
              growable: false,
            ),
          },
          'clientExtensionResults': <String, dynamic>{},
        },
      },
    );
    _throwOnFunctionError(finishResponse);
  }

  Future<Map<String, dynamic>> punch(String eventType) async {
    final position = await LocationService.current();
    final operationId = const Uuid().v4();
    final challengeResponse = await _client.functions.invoke(
      'webauthn-challenge',
      body: const {'type': 'auth'},
    );
    _throwOnFunctionError(challengeResponse);

    final challengeData = _map(challengeResponse.data);
    final challengeId = challengeData['challengeId']?.toString();
    if (challengeId == null || challengeId.isEmpty) {
      throw StateError('تعذر بدء جلسة التحقق بأمان. أعد المحاولة.');
    }
    final request = AuthenticateRequestType.fromJson(challengeData);
    final AuthenticateResponseType assertion;
    try {
      assertion = await _authenticator.authenticate(request);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('cancel') || msg.contains('dismissed')) {
        throw StateError('تم إلغاء التحقق بالبصمة.');
      }
      throw StateError('تعذر فتح نافذة البصمة على الجهاز: $msg');
    }

    final verifyResponse = await _client.functions.invoke(
      'verify-attendance-punch',
      body: {
        'operationId': operationId,
        'correlationId': operationId,
        'challengeId': challengeId,
        'eventType': eventType,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMeters': position.accuracy,
        'isMock': position.isMocked,
        'response': {
          'id': assertion.id,
          'rawId': assertion.rawId,
          'type': 'public-key',
          'response': {
            'clientDataJSON': assertion.clientDataJSON,
            'authenticatorData': assertion.authenticatorData,
            'signature': assertion.signature,
            'userHandle': assertion.userHandle,
          },
          'clientExtensionResults': <String, dynamic>{},
        },
      },
    );
    _throwOnFunctionError(verifyResponse);
    return _map(verifyResponse.data);
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw StateError('استجابة الخادم غير صالحة.');
  }

  void _throwOnFunctionError(FunctionResponse response) {
    if (response.status >= 200 && response.status < 300) return;
    var message = 'تعذر إكمال عملية البصمة. (خطأ ${response.status})';
    final data = response.data;
    if (data is Map && data['error'] != null) {
      message = _humanize(data['error'].toString());
    } else if (data != null) {
      message =
          'تعذر إكمال عملية البصمة: ${data.toString().length > 200 ? data.toString().substring(0, 200) : data}';
    }
    throw StateError(message);
  }

  String _humanize(String code) => switch (code) {
    'credential_already_registered' => 'هذه البصمة مسجلة بالفعل.',
    'challenge_invalid_or_used' ||
    'challenge_already_used' => 'انتهت جلسة التحقق. أعد المحاولة.',
    'assertion_verification_failed' ||
    'assertion_not_verified' => 'تعذر التحقق من بصمة الجهاز.',
    'registration_verification_failed' ||
    'registration_not_verified' => 'تعذر تسجيل بصمة الجهاز بأمان.',
    'employee_inactive' => 'حساب الموظف غير نشط.',
    'record_failed' => 'تعذر تسجيل الحضور على الخادم. أعد المحاولة.',
    'attendance_outside_complex' => 'لا يمكن تسجيل البصمة من خارج نطاق المجمع.',
    'attendance_mock_location_rejected' =>
      'تم رفض البصمة لأن الجهاز أبلغ عن موقع غير حقيقي.',
    'attendance_location_accuracy_too_low' =>
      'دقة الموقع غير كافية. انتظر ثبات إشارة GPS ثم أعد المحاولة داخل المجمع.',
    'attendance_geofence_not_configured' =>
      'لم يتم ربط حسابك بنطاق المجمع. تواصل مع مسؤول النظام.',
    'attendance_location_required' =>
      'تعذر قراءة موقعك الحالي. فعّل الموقع الدقيق ثم أعد المحاولة.',
    'attendance_passkey_not_trusted' =>
      'بصمة هذا الجهاز غير موثقة. أعد تسجيل بصمة الجهاز.',
    'device_not_active' =>
      'جهازك غير موثق على الخادم. جاري تسجيل الجهاز تلقائيًا... أعد المحاولة بعد لحظات.',
    'duplicate_attendance_event' => 'تم تسجيل هذه العملية بالفعل منذ لحظات.',
    'attendance_period_finalized' => 'تم إغلاق فترة الحضور ولا يمكن إضافة بصمة جديدة.',
    'attendance_check_in_required' => 'يجب تسجيل الحضور قبل تسجيل الانصراف.',
    'attendance_check_out_required' => 'لديك حضور مفتوح بالفعل. سجّل الانصراف أولاً.',
    'server_not_configured' => 'إعدادات البصمة على الخادم غير مكتملة.',
    'origin_not_allowed' => 'هذا الإصدار غير مرتبط بنطاق البصمة المعتمد.',
    'authenticator_counter_replay' =>
      'رُصد استخدام بصمة قديمة. أعد تسجيل بصمة الجهاز.',
    'attendance_trusted_server_required' =>
      'إعدادات الخادم غير مكتملة. تواصل مع مسؤول النظام.',
    'attendance_idempotency_conflict' =>
      'محاولة تسجيل مكررة. أعد المحاولة بعد لحظات.',
    'operation_conflict' =>
      'حدث تعارض في المعاملة. أعد المحاولة بعد لحظات.',
    'operation_lookup_failed' =>
      'تعذر التحقق من حالة العملية. أعد المحاولة.',
    'invalid_operation_context' =>
      'إعدادات الجلسة غير صالحة. أعد المحاولة.',
    'invalid_latitude' || 'invalid_longitude' || 'invalid_accuracy' =>
      'قراءة الموقع غير صالحة. حرّك الجهاز وأعد المحاولة.',
    'credential_not_found' =>
      'لم يتم العثور على بصمة موثقة لهذا الحساب. سجّل بصمة الجهاز أولاً.',
    'credential_disabled' =>
      'بصمة الجهاز موقوفة. تواصل مع مسؤول النظام لإعادة تفعيلها.',
    'no_employee_linked' => 'حسابك غير مربوط بملف موظف.',
    'invalid_session' || 'unauthorized' =>
      'انتهت جلسة الدخول. سجّل الدخول من جديد.',
    _ => 'تعذر إكمال العملية بأمان. أعد المحاولة أو تواصل مع المسؤول.',
  };
}
