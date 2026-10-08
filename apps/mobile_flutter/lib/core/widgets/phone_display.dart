/// تطبيع وعرض أرقام الهواتف الدولية (E.164) بصيغة صحيحة للعرض العربي.
///
/// المشكلة: عند كتابة رقم دولي (مثل ‎+201099505229) داخل نص عربي بدون عزل
/// اتجاه، قد تُفسد خوارزمية bidi ترتيبه فيظهر كأنه «201099505229+».
/// هذه الدوال تُصلّح الترتيب المعكوس وتوفر عرضاً آمناً داخل [Directionality].
class PhoneDisplay {
  PhoneDisplay._();

  static final _bidiMarkers = RegExp(r'[\u200E\u200F\u202A-\u202E\u061C]');

  /// يصلّح ترتيب رقم دولي انعكس بفعل خوارزمية bidi ويجرد رمز الدولة (+20) للمصرية.
  /// «201099505229+» أو «+201099505229» ← «01099505229».
  static String fixIntlPhoneOrder(String value) {
    return stripCountryCode(value);
  }

  /// يزيل رمز الدولة (+20 أو 0020) ويعيد الرقم المصري بالصيغة المحلية (01xxxxxxxxx).
  /// الأرقام الدولية الأخرى غير المصرية يُعاد ترتيبها بالصيغة الصحيحة (مثل +966...).
  static String stripCountryCode(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    var cleaned = value.replaceAll(_bidiMarkers, '').trim();

    // تصليح اتجاه الرقم المعكوس بفعل bidi (مثل 201099505229+)
    final bidiMatch = RegExp(r'^(\d+)\+(.*)$').firstMatch(cleaned);
    if (bidiMatch != null) {
      cleaned = '+${bidiMatch.group(1)}${bidiMatch.group(2)}'.trim();
    }

    // إزالة الفراغات والواصلات بين الأرقام
    final compact = cleaned.replaceAll(RegExp(r'[\s\-]'), '');

    // إزالة رمز الدولة +20
    if (compact.startsWith('+20')) {
      final rest = compact.substring(3).trim();
      return rest.startsWith('0') ? rest : '0$rest';
    }

    // إزالة رمز الدولة 0020
    if (compact.startsWith('0020')) {
      final rest = compact.substring(4).trim();
      return rest.startsWith('0') ? rest : '0$rest';
    }

    // رقم مصري مكون من 12 خانة يبدأ بـ 20 (مثل 201099505229)
    if (RegExp(r'^201[0125]\d{8}$').hasMatch(compact)) {
      return '0${compact.substring(2)}';
    }

    // إذا بدأ بـ + دولي آخر غير مصري
    if (cleaned.startsWith('+')) {
      return cleaned;
    }

    return cleaned;
  }

  /// يلف الرقم داخل صيغة محلية آمنة للعرض، بدون +20، مع استبدال الفارغ بشرطة '—'.
  static String safePhoneText(String? value) {
    if (value == null || value.trim().isEmpty) return '—';
    final result = stripCountryCode(value);
    return result.isEmpty ? '—' : result;
  }
}

/// امتداد على String لتسهيل الاستخدام
extension PhoneDisplayStringExt on String {
  String fixIntlPhoneOrder() => PhoneDisplay.fixIntlPhoneOrder(this);
  String stripCountryCode() => PhoneDisplay.stripCountryCode(this);
  String safePhone() => PhoneDisplay.safePhoneText(this);
}

