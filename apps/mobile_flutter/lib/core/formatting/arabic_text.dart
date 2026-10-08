/// صياغة عربية سليمة للأعداد والأرقام في الواجهات.
library;

/// العدد مع المعدود بقاعدة العربية:
/// 1 «طلب واحد»، 2 «طلبان»، 3–10 «3 طلبات»، 11–99 «11 طلبًا»، 0 و100+ «100 طلب».
String arCount(
  int n, {
  required String one,
  required String two,
  required String few,
  required String many,
  required String base,
}) {
  if (n == 1) return one;
  if (n == 2) return two;
  final mod100 = n % 100;
  if (n > 2 && mod100 >= 3 && mod100 <= 10) return '$n $few';
  if (mod100 >= 11 && mod100 <= 99) return '$n $many';
  return '$n $base';
}

String arRequests(int n) => arCount(
  n,
  one: 'طلب واحد',
  two: 'طلبان',
  few: 'طلبات',
  many: 'طلبًا',
  base: 'طلب',
);

String arMembers(int n) => arCount(
  n,
  one: 'عضو واحد',
  two: 'عضوان',
  few: 'أعضاء',
  many: 'عضوًا',
  base: 'عضو',
);

String arEmployees(int n) => arCount(
  n,
  one: 'موظف واحد',
  two: 'موظفان',
  few: 'موظفين',
  many: 'موظفًا',
  base: 'موظف',
);

String arDays(int n) => arCount(
  n,
  one: 'يوم واحد',
  two: 'يومان',
  few: 'أيام',
  many: 'يومًا',
  base: 'يوم',
);

/// رصيد أو كمية: عدد صحيح بلا كسر عشري («3» لا «3.0»)، وإلا منزلة واحدة.
String fmtUnits(num value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
