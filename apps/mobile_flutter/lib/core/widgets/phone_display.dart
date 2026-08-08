/// تطبيع وعرض أرقام الهواتف الدولية (E.164) بصيغة صحيحة للعرض العربي.
///
/// المشكلة: عند كتابة رقم دولي (مثل ‎+201099505229) داخل نص عربي بدون عزل
/// اتجاه، قد تُفسد خوارزمية bidi ترتيبه فيظهر كأنه «201099505229+».
/// هذه الدوال تُصلّح الترتيب المعكوس وتوفر عرضاً آمناً داخل [Directionality].
class PhoneDisplay {
  PhoneDisplay._();

  static final _bidiMarkers = RegExp(r'[\u200E\u200F\u202A-\u202E\u061C]');

  /// يصلّح ترتيب رقم دولي انعكس بفعل خوارزمية bidi.
  /// «201099505229+» ← «+201099505229». القيم غير الرقمية تُعاد كما هي.
  static String fixIntlPhoneOrder(String value) {
    final cleaned = value.replaceAll(_bidiMarkers, '').trim();
    final match = RegExp(r'^(\d+)\+(.*)$').firstMatch(cleaned);
    if (match != null) {
      return '+${match.group(1)}${match.group(2)}'.trim();
    }
    return cleaned;
  }

  /// يلف الرقم داخل عنصر [Directionality] باتجاه LTR ليبقى «+20…» صحيحاً
  /// داخل أي نص عربي. يُطبّق [fixIntlPhoneOrder] أولاً.
  static String safePhoneText(String? value) {
    if (value == null || value.trim().isEmpty) return '—';
    return fixIntlPhoneOrder(value);
  }
}

/// امتداد على String لتسهيل الاستخدام: `'+201…'.fixIntlPhoneOrder`.
extension PhoneDisplayStringExt on String {
  String fixIntlPhoneOrder() => PhoneDisplay.fixIntlPhoneOrder(this);
}
