import 'dart:async';
import 'dart:io';

import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('humanizeError — أنواع الأخطاء', () {
    test('SocketException يرجع رسالة عدم اتصال', () {
      final msg = humanizeError(
        const SocketException('Failed host lookup'),
      );
      expect(msg, 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة وأعد المحاولة.');
    });

    test('TimeoutException يرجع رسالة انتهاء وقت', () {
      final msg = humanizeError(TimeoutException('request timed out'));
      expect(
          msg, 'استغرق الطلب وقتًا طويلًا. تحقق من الاتصال وأعد المحاولة.');
    });

    test('PostgrestException 42501 يرجع رسالة صلاحية', () {
      final msg = humanizeError(
        PostgrestException(message: 'permission denied', code: '42501'),
      );
      expect(msg, 'ليس لديك صلاحية لهذه العملية.');
    });

    test('PostgrestException 23505 يرجع رسالة تكرار', () {
      final msg = humanizeError(
        PostgrestException(message: 'unique violation', code: '23505'),
      );
      expect(msg, 'هذا العنصر موجود بالفعل. لا يمكن تكراره.');
    });

    test('PostgrestException 23503 يرجع رسالة مرجعية', () {
      final msg = humanizeError(
        PostgrestException(message: 'FK constraint', code: '23503'),
      );
      expect(
          msg, 'لا يمكن حذف هذا العنصر لأن بيانات أخرى تعتمد عليه.');
    });

    test('PostgrestException PGRST116 يرجع رسالة غير موجود', () {
      final msg = humanizeError(
        PostgrestException(message: 'not found', code: 'PGRST116'),
      );
      expect(msg, 'العنصر المطلوب غير موجود.');
    });

    test('PostgrestException 42703 يرجع رسالة تحميل بيانات', () {
      final msg = humanizeError(
        PostgrestException(message: 'column not found', code: '42703'),
      );
      expect(msg, 'تعذر تحميل البيانات. تواصل مع مسؤول النظام.');
    });
  });

  group('humanizeError — رسائل خاصة', () {
    test('خطأ device_not_active يرجع رسالة جهاز غير معتمد', () {
      final msg = humanizeError(Exception('device_not_active'));
      expect(msg, contains('هذا الجهاز غير معتمد'));
    });

    test('خطأ duplicate_attendance_event يرجع رسالة تسجيل مكرر', () {
      final msg = humanizeError(Exception('duplicate_attendance_event'));
      expect(msg, 'تم تسجيل هذه العملية بالفعل.');
    });

    test('خطأ Invalid API key يرجع رسالة مفتاح غير صالح', () {
      final msg = humanizeError(Exception('Invalid API key'));
      expect(msg, contains('مفتاح الاتصال غير صالح'));
    });
  });

  group('humanizeError — StateError', () {
    test('StateError بنص عربي يرجع النص كما هو', () {
      final msg = humanizeError(StateError('صلاحية الموقع مرفوضة'));
      // _isArabic check in StateError branch returns the Arabic message
      expect(msg, 'صلاحية الموقع مرفوضة');
    });

    test('StateError بنص إنجليزي يرجع رسالة عامة', () {
      final msg = humanizeError(StateError('bad state'));
      expect(msg, 'تعذر إكمال العملية. أعد المحاولة.');
    });
  });

  group('humanizeError — أخطاء عامة', () {
    test('خطأ غير معروف يرجع رسالة عامة', () {
      final msg = humanizeError(Exception('something unexpected'));
      expect(
          msg, 'حدث خطأ غير متوقع. أعد المحاولة أو تواصل مع المسؤول.');
    });

    test('خطأ يحتوي AuthRetryableFetchException يرجع رسالة خادم', () {
      final msg =
          humanizeError(Exception('AuthRetryableFetchException: network'));
      expect(msg,
          'تعذر الاتصال بالخادم. تحقق من الإنترنت وأعد المحاولة.');
    });

    test('خطأ يحتوي نص عربي في Exception يرجع النص', () {
      final msg = humanizeError(Exception('دقة الموقع منخفضة جدًا'));
      // The message contains Arabic, so it returns the cleaned text.
      expect(msg, contains('دقة الموقع'));
    });
  });

  group('retryWithBackoff', () {
    test('يرجع القيمة مباشرة عند النجاح من أول محاولة', () async {
      final result = await retryWithBackoff(
        () async => 42,
        initialDelay: const Duration(milliseconds: 1),
      );
      expect(result, 42);
    });

    test('يعيد المحاولة عند SocketException ثم ينجح', () async {
      var attempts = 0;
      final result = await retryWithBackoff(
        () async {
          attempts++;
          if (attempts < 3) {
            throw const SocketException('no connection');
          }
          return 'نجاح';
        },
        maxRetries: 3,
        initialDelay: const Duration(milliseconds: 1),
      );
      expect(result, 'نجاح');
      expect(attempts, 3);
    });

    test('يعيد المحاولة عند TimeoutException ثم ينجح', () async {
      var attempts = 0;
      final result = await retryWithBackoff(
        () async {
          attempts++;
          if (attempts < 2) {
            throw TimeoutException('timed out');
          }
          return 'تم';
        },
        maxRetries: 3,
        initialDelay: const Duration(milliseconds: 1),
      );
      expect(result, 'تم');
      expect(attempts, 2);
    });

    test('لا يعيد المحاولة عند StateError (غير قابل للإعادة)', () async {
      var attempts = 0;
      expect(
        () => retryWithBackoff(
          () async {
            attempts++;
            throw StateError('not retryable');
          },
          maxRetries: 3,
          initialDelay: const Duration(milliseconds: 1),
        ),
        throwsStateError,
      );
      // StateError يُرمى فورًا من المحاولة الأولى
      expect(attempts, 1);
    });

    test('يرمي الخطأ بعد استنفاد المحاولات', () async {
      var attempts = 0;
      expect(
        () => retryWithBackoff(
          () async {
            attempts++;
            throw const SocketException('no connection');
          },
          maxRetries: 3,
          initialDelay: const Duration(milliseconds: 1),
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
