import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// خدمة المشاركة المباشرة عبر تطبيق واتساب ومجموعات الجمعية.
class WhatsAppShareService {
  const WhatsAppShareService._();

  /// إرسال نص مباشر إلى تطبيق واتساب.
  static Future<bool> shareText(String text, {String? phone}) async {
    final cleanPhone = phone?.replaceAll(RegExp(r'[^\d]'), '') ?? '';
    final encoded = Uri.encodeComponent(text);

    // 1) رابط wa.me المباشر (يعمل مع التطبيق على Android/iOS)
    final uri = cleanPhone.isNotEmpty
        ? Uri.parse('https://wa.me/$cleanPhone?text=$encoded')
        : Uri.parse('whatsapp://send?text=$encoded');

    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // تجربة الرابط الاحتياطي عبر الويب
    }

    // 2) رابط احتياطي عام
    try {
      final webUri = Uri.parse('https://api.whatsapp.com/send?text=$encoded');
      return await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[WhatsAppShareService] تعذر فتح واتساب: $e');
      return false;
    }
  }

  /// صياغة ومشاركة بطاقة تكريم موظف من لوحة الشرف.
  static Future<bool> shareHonorCard({
    required String employeeName,
    required String period,
    String? category,
    String? rate,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🌟 *تهنئة وتكريم تميز — جمعية أحلى شباب* 🌟');
    buffer.writeln();
    buffer.writeln('يسر إدارة الجمعية تهنئة الزميل/ة:');
    buffer.writeln('👤 *«$employeeName»*');
    buffer.writeln();
    buffer.writeln('🏆 تقديرًا للتميز والانضباط المثالي في الدوام والعمل');
    buffer.writeln('📅 لشهر: $period');
    if (category != null && category.isNotEmpty) {
      buffer.writeln('🎯 الفئة: $category');
    }
    if (rate != null && rate.isNotEmpty) {
      buffer.writeln('📊 نسبة الالتزام: $rate');
    }
    buffer.writeln();
    buffer.writeln('سائلين المولى له/ا دوام التوفيق ومزيدًا من العطاء والإنجاز 👏💚');
    buffer.writeln('— *منظومة جمعية أحلى شباب الإدارية*');
    return shareText(buffer.toString());
  }

  /// صياغة ومشاركة قرار أو تعميم رسمي منشور.
  static Future<bool> shareAnnouncement({
    required String title,
    required String body,
    String? publishedDate,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📢 *قرار / تعميم رسمي — جمعية أحلى شباب*');
    buffer.writeln();
    buffer.writeln('📌 *«$title»*');
    buffer.writeln();
    final cleanBody = body.trim();
    if (cleanBody.length > 250) {
      buffer.writeln('${cleanBody.substring(0, 247)}...');
    } else {
      buffer.writeln(cleanBody);
    }
    buffer.writeln();
    if (publishedDate != null) {
      buffer.writeln('🕒 تاريخ النشر: $publishedDate');
    }
    buffer.writeln('🔗 لمتابعة التفاصيل عبر المنظومة:');
    buffer.writeln('https://ahla-shabab-management-os.vercel.app');
    buffer.writeln();
    buffer.writeln('— *الإدارة التنفيذية لجمعية أحلى شباب*');
    return shareText(buffer.toString());
  }

  /// صياغة ومشاركة طلب للمتابعة أو الاعتماد السريع.
  static Future<bool> shareRequest({
    required int number,
    required String typeLabel,
    required String employeeName,
    required String reason,
    String? stage,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📋 *طلب جديد بالمنظومة — جمعية أحلى شباب*');
    buffer.writeln();
    buffer.writeln('• النوع: *$typeLabel*');
    buffer.writeln('• رقم الطلب: *#$number*');
    buffer.writeln('• صاحب الطلب: *$employeeName*');
    if (reason.trim().isNotEmpty) {
      buffer.writeln('• السبب: ${reason.trim()}');
    }
    if (stage != null && stage.trim().isNotEmpty) {
      buffer.writeln('• المرحلة الحالية: $stage');
    }
    buffer.writeln();
    buffer.writeln('🔗 للبت في الطلب أو متابعته:');
    buffer.writeln('https://ahla-shabab-management-os.vercel.app');
    return shareText(buffer.toString());
  }
}
