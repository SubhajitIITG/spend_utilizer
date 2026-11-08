import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _moneyShort =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// ₹1,25,000.50 (Indian grouping). Whole amounts drop the decimals.
String money(double v) =>
    v == v.roundToDouble() ? _moneyShort.format(v) : _money.format(v);

String formatDate(DateTime d) => DateFormat('d MMM yyyy').format(d);
String formatDateTime(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);
String formatMonth(DateTime d) => DateFormat('MMMM yyyy').format(d);

/// Parses "1,499.50", "₹ 250", "rs 99" → number.
double? parseAmount(String s) {
  final cleaned =
      s.replaceAll(RegExp(r'rs\.?|inr|₹|,|\s', caseSensitive: false), '');
  return double.tryParse(cleaned);
}

/// Parses dd-mm-yyyy, dd/mm/yy or yyyy-mm-dd.
DateTime? parseUserDate(String s) {
  final t = s.trim();
  final dmy = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$').firstMatch(t);
  if (dmy != null) {
    var y = int.parse(dmy.group(3)!);
    if (y < 100) y += 2000;
    final m = int.parse(dmy.group(2)!), d = int.parse(dmy.group(1)!);
    final dt = DateTime(y, m, d);
    return (dt.month == m && dt.day == d) ? dt : null;
  }
  return DateTime.tryParse(t);
}
