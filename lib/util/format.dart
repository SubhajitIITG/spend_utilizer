import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _moneyShort = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

/// ₹1,25,000.50 (Indian grouping). Whole amounts drop the decimals.
String money(double v) =>
    v == v.roundToDouble() ? _moneyShort.format(v) : _money.format(v);

String formatDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

/// "Wed, 5 Nov 2026" or "Wed, 5 Nov 2026 · 6:05 PM" when a time is known.
/// Times of exactly 12:00:00 are our "no time given" placeholder.
String formatTxnDate(DateTime d) {
  final day = DateFormat('EEE, d MMM yyyy').format(d);
  final noTime = d.hour == 12 && d.minute == 0 && d.second == 0;
  return noTime ? day : '$day · ${DateFormat('h:mm a').format(d)}';
}

/// "Today", "Yesterday" or "Wed, 5 Nov 2026" for list headers.
String formatDayHeader(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEE, d MMM yyyy').format(d);
}

String formatDateTime(DateTime d) => DateFormat('d MMM yyyy, h:mm a').format(d);
String formatMonth(DateTime d) => DateFormat('MMMM yyyy').format(d);

/// Parses "1,499.50", "₹ 250", "rs 99" → number.
double? parseAmount(String s) {
  final cleaned = s.replaceAll(
    RegExp(r'rs\.?|inr|₹|,|\s', caseSensitive: false),
    '',
  );
  return double.tryParse(cleaned);
}

const _monthNames = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

DateTime? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  return (dt.month == m && dt.day == d) ? dt : null;
}

/// Parses what people type for a date: "today", "yesterday", "5-11-2026",
/// "5/11/26", "5/11" (this year), "5 Nov", "5 Nov 2026" or "2026-11-05".
DateTime? parseUserDate(String s, {DateTime? now}) {
  now ??= DateTime.now();
  final t = s.trim().toLowerCase();
  final today = DateTime(now.year, now.month, now.day);
  if (t == 'today') return today;
  if (t == 'yesterday') return today.subtract(const Duration(days: 1));

  final dmy = RegExp(r'^(\d{1,2})[-/.](\d{1,2})(?:[-/.](\d{2,4}))?$')
      .firstMatch(t);
  if (dmy != null) {
    var y = int.tryParse(dmy.group(3) ?? '') ?? now.year;
    if (y < 100) y += 2000;
    return _valid(y, int.parse(dmy.group(2)!), int.parse(dmy.group(1)!));
  }
  final named = RegExp(
    r'^(\d{1,2})(?:st|nd|rd|th)?\s*([a-z]{3})[a-z]*'
    r'(?:[\s,-]+(\d{2,4}))?$',
  ).firstMatch(t);
  if (named != null && _monthNames.containsKey(named.group(2))) {
    var y = int.tryParse(named.group(3) ?? '') ?? now.year;
    if (y < 100) y += 2000;
    return _valid(y, _monthNames[named.group(2)]!, int.parse(named.group(1)!));
  }
  return DateTime.tryParse(t);
}
