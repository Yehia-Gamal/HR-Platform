import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/theme/app_theme.dart';
import 'package:ahla_shabab_management_os/core/theme/theme_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseThemeMode', () {
    test('يحلل light بشكل صحيح', () {
      expect(parseThemeMode('light'), ThemeMode.light);
    });

    test('يحلل dark بشكل صحيح', () {
      expect(parseThemeMode('dark'), ThemeMode.dark);
    });

    test('يحلل system بشكل صحيح', () {
      expect(parseThemeMode('system'), ThemeMode.system);
    });

    test('يرجع system عند تمرير null', () {
      expect(parseThemeMode(null), ThemeMode.system);
    });

    test('يرجع system لقيمة غير معروفة', () {
      expect(parseThemeMode('auto'), ThemeMode.system);
    });

    test('يرجع system لنص فارغ', () {
      expect(parseThemeMode(''), ThemeMode.system);
    });
  });

  group('serializeThemeMode', () {
    test('يحول light لنص', () {
      expect(serializeThemeMode(ThemeMode.light), 'light');
    });

    test('يحول dark لنص', () {
      expect(serializeThemeMode(ThemeMode.dark), 'dark');
    });

    test('يحول system لنص', () {
      expect(serializeThemeMode(ThemeMode.system), 'system');
    });
  });

  group('دورة كاملة parse ↔ serialize', () {
    test('parse(serialize(light)) == light', () {
      expect(parseThemeMode(serializeThemeMode(ThemeMode.light)),
          ThemeMode.light);
    });

    test('parse(serialize(dark)) == dark', () {
      expect(
          parseThemeMode(serializeThemeMode(ThemeMode.dark)), ThemeMode.dark);
    });

    test('parse(serialize(system)) == system', () {
      expect(parseThemeMode(serializeThemeMode(ThemeMode.system)),
          ThemeMode.system);
    });
  });

  group('AppTheme.light()', () {
    late ThemeData theme;

    setUp(() {
      theme = AppTheme.light();
    });

    test('السطوع فاتح', () {
      expect(theme.brightness, Brightness.light);
    });

    test('يستخدم خط Cairo', () {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Cairo');
    });

    test('يستخدم Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('لون خلفية الصفحة هو lightBackground', () {
      expect(theme.scaffoldBackgroundColor, AppColors.lightBackground);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF3F6FB));
    });

    test('يحتوي على colorScheme', () {
      expect(theme.colorScheme, isNotNull);
      expect(theme.colorScheme.brightness, Brightness.light);
    });
  });

  group('AppTheme.dark()', () {
    late ThemeData theme;

    setUp(() {
      theme = AppTheme.dark();
    });

    test('السطوع داكن', () {
      expect(theme.brightness, Brightness.dark);
    });

    test('يستخدم خط Cairo', () {
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Cairo');
    });

    test('يستخدم Material 3', () {
      expect(theme.useMaterial3, isTrue);
    });

    test('لون خلفية الصفحة هو darkBackground', () {
      expect(theme.scaffoldBackgroundColor, AppColors.darkBackground);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF060B16));
    });

    test('يحتوي على colorScheme داكن', () {
      expect(theme.colorScheme, isNotNull);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });
  });

  group('مقارنة light و dark', () {
    test('ألوان الخلفية مختلفة', () {
      expect(
        AppTheme.light().scaffoldBackgroundColor,
        isNot(equals(AppTheme.dark().scaffoldBackgroundColor)),
      );
    });

    test('كلاهما يستخدم نفس الخط', () {
      expect(
        AppTheme.light().textTheme.bodyMedium?.fontFamily,
        AppTheme.dark().textTheme.bodyMedium?.fontFamily,
      );
    });
  });
}
