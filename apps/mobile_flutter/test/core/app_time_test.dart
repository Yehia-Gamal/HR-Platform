import 'package:ahla_shabab_management_os/core/time/app_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    AppTime.initialize();
  });

  test('converts UTC winter timestamp accurately to Africa/Cairo (UTC+2)', () {
    final utcWinter = DateTime.utc(2026, 11, 25, 8, 15);
    final cairo = AppTime.toCairo(utcWinter);
    expect(cairo.hour, 10);
    expect(cairo.minute, 15);
    expect(AppTime.dayKey(utcWinter), '2026-11-25');
  });

  test('converts UTC summer DST timestamp accurately to Africa/Cairo (UTC+3)', () {
    final utcSummer = DateTime.utc(2026, 7, 15, 22, 30);
    final cairo = AppTime.toCairo(utcSummer);
    expect(cairo.day, 16);
    expect(cairo.hour, 1);
    expect(cairo.minute, 30);
    expect(AppTime.dayKey(utcSummer), '2026-07-16');
  });

  test('handles nullable dates and invalid strings cleanly', () {
    expect(AppTime.tryToCairo(null), isNull);
    expect(AppTime.tryParse(null), isNull);
    expect(AppTime.tryParse('not-a-timestamp'), isNull);
    expect(AppTime.tryParse('2026-11-25T06:00:00Z')?.hour, 8);
  });
}
