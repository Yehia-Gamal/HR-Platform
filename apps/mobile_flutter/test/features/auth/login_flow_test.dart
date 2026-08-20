import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Login Flow Tests', () {
    test('identifier validation - email format', () {
      // تنسيق البريد الإلكتروني
      expect(isValidEmail('test@example.com'), isTrue);
      expect(isValidEmail('invalid-email'), isFalse);
      expect(isValidEmail(''), isFalse);
    });

    test('identifier validation - phone format', () {
      // تنسيق رقم الهاتف (يبدأ بـ 05 أو +9665)
      expect(isValidPhone('0501234567'), isTrue);
      expect(isValidPhone('+966501234567'), isTrue);
      expect(isValidPhone('1234567'), isFalse);
      expect(isValidPhone(''), isFalse);
    });

    test('identifier validation - employee code format', () {
      // كود الموظف (أرقام فقط، 3-8 أحرف)
      expect(isValidEmployeeCode('12345'), isTrue);
      expect(isValidEmployeeCode('123'), isTrue);
      expect(isValidEmployeeCode('12345678'), isTrue);
      expect(isValidEmployeeCode('12'), isFalse); // أقل من 3
      expect(isValidEmployeeCode('123456789'), isFalse); // أكثر من 8
      expect(isValidEmployeeCode('abc123'), isFalse); // يحتوي على حروف
    });

    test('password validation - minimum length', () {
      expect(isValidPassword('12345678'), isTrue); // 8 أحرف
      expect(isValidPassword('1234567'), isFalse); // 7 أحرف
      expect(isValidPassword(''), isFalse);
    });

    test('password validation - maximum length', () {
      final longPassword = 'a' * 72;
      final tooLongPassword = 'a' * 73;
      expect(isValidPassword(longPassword), isTrue);
      expect(isValidPassword(tooLongPassword), isFalse);
    });

    test('identifier type detection', () {
      expect(detectIdentifierType('test@example.com'), IdentifierType.email);
      expect(detectIdentifierType('0501234567'), IdentifierType.phone);
      expect(detectIdentifierType('+966501234567'), IdentifierType.phone);
      expect(detectIdentifierType('12345'), IdentifierType.employeeCode);
      expect(detectIdentifierType(''), IdentifierType.unknown);
      expect(detectIdentifierType('invalid'), IdentifierType.unknown);
    });
  });

  group('Password Setup Flow Tests', () {
    test('password confirmation matching', () {
      expect(passwordsMatch('password123', 'password123'), isTrue);
      expect(passwordsMatch('password123', 'password456'), isFalse);
      expect(passwordsMatch('', ''), isTrue);
    });

    test('password strength - weak', () {
      expect(calculatePasswordStrength('12345678'), PasswordStrength.weak);
      expect(calculatePasswordStrength('abcdefgh'), PasswordStrength.weak);
    });

    test('password strength - medium', () {
      expect(calculatePasswordStrength('abc12345'), PasswordStrength.medium);
      expect(calculatePasswordStrength('Abcdefgh'), PasswordStrength.medium);
    });

    test('password strength - strong', () {
      expect(calculatePasswordStrength('Abc123!@'), PasswordStrength.strong);
      expect(calculatePasswordStrength('MyP@ss123'), PasswordStrength.strong);
    });
  });
}

// Helper functions للاختبار
enum IdentifierType { email, phone, employeeCode, unknown }

enum PasswordStrength { weak, medium, strong }

bool isValidEmail(String email) {
  if (email.isEmpty) return false;
  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
  return emailRegex.hasMatch(email);
}

bool isValidPhone(String phone) {
  if (phone.isEmpty) return false;
  final phoneRegex = RegExp(r'^(05\d{8}|\+9665\d{8})$');
  return phoneRegex.hasMatch(phone);
}

bool isValidEmployeeCode(String code) {
  if (code.isEmpty) return false;
  final codeRegex = RegExp(r'^\d{3,8}$');
  return codeRegex.hasMatch(code);
}

bool isValidPassword(String password) {
  return password.length >= 8 && password.length <= 72;
}

IdentifierType detectIdentifierType(String identifier) {
  if (isValidEmail(identifier)) return IdentifierType.email;
  if (isValidPhone(identifier)) return IdentifierType.phone;
  if (isValidEmployeeCode(identifier)) return IdentifierType.employeeCode;
  return IdentifierType.unknown;
}

bool passwordsMatch(String password, String confirmation) {
  return password == confirmation;
}

PasswordStrength calculatePasswordStrength(String password) {
  if (password.length < 8) return PasswordStrength.weak;

  var strength = 0;
  if (RegExp(r'[a-z]').hasMatch(password)) strength++;
  if (RegExp(r'[A-Z]').hasMatch(password)) strength++;
  if (RegExp(r'[0-9]').hasMatch(password)) strength++;
  if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;

  if (strength <= 1) return PasswordStrength.weak;
  if (strength == 2) return PasswordStrength.medium;
  return PasswordStrength.strong;
}
