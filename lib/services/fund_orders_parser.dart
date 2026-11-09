// Reads a list of mutual fund orders from a screenshot, e.g. Groww's
// "All Orders → Mutual Funds" screen:
//
//   06 Nov '26
//   ICICI Prudential Short Term Fund …      ₹50,000.00
//   One-time                                ● In progress
//   09 Oct '26
//   Nippon India Small Cap Fund Dire…        ₹2,000.00
//   SIP Installment                         ● Completed
//
// The phone's text reader may return the screen row by row or the left
// column first and then the right one, so names (left) and amounts /
// statuses (right) are collected separately, in screen order, and paired
// up by position.

import 'sms_parser.dart';

enum OrderStatus { completed, inProgress, failed, unknown }

class FundOrder {
  final String fund;
  final double amount;
  final DateTime? date;

  /// "SIP Installment", "One-time"…
  final String kind;
  final OrderStatus status;

  /// The ₹ sign may have been read as a 7 ("72,000.00" for ₹2,000.00).
  final bool amountGuessed;

  const FundOrder({
    required this.fund,
    required this.amount,
    required this.date,
    required this.kind,
    required this.status,
    this.amountGuessed = false,
  });

  bool get isSip => kind.toLowerCase().contains('sip');

  @override
  String toString() => 'FundOrder($fund $amount $date $kind $status)';
}

class FundOrdersParser {
  static final _kindRe = RegExp(
    r'^(sip install?ments?|sip|one[- ]?time|lump ?sum|additional purchase|'
    r'purchase|new sip|step[- ]?up sip)$',
    caseSensitive: false,
  );
  static final _statusRe = RegExp(
    r'^[•●·o.]?\s*(completed|successful|success|allotted|in progress|'
    r'processing|pending|failed|cancelled|canceled|rejected)$',
    caseSensitive: false,
  );
  static final _dateRe = RegExp(
    r"^(\d{1,2})\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*"
    r"[\s,'’]*(\d{2,4})?$",
    caseSensitive: false,
  );
  static final _amountRe = RegExp(
    r'^(₹|rs\.?|inr|z|%|\*|7)?\s*(\d{1,3}(?:,\d{2,3})*(?:\.\d{2})?|\d+\.\d{2})$',
    caseSensitive: false,
  );
  static const _months = {
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

  /// Screen furniture that is never a fund name.
  static final _noise = RegExp(
    r'^(all orders|orders|stocks|f&o|mutual funds|us stocks|sip|sips|'
    r'filters?|sort|search|dashboard|explore|holdings|watchlist|'
    r'\d{1,2}:\d{2}.*|.*\bkb/s\b.*|\d+%)$',
    caseSensitive: false,
  );

  /// Returns the orders, or an empty list when the text isn't an order
  /// list.
  static List<FundOrder> parse(String text, {DateTime? now}) {
    now ??= DateTime.now();
    final lines = text
        .split('\n')
        .map((l) => l.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((l) => l.isNotEmpty)
        .toList();

    // Left column: (date, name, kind) per order.
    final left = <({DateTime? date, String name, String kind})>[];
    // Right column: amounts and statuses, in screen order.
    final amounts = <(double, bool)>[];
    final statuses = <OrderStatus>[];

    DateTime? date;
    String? name;
    for (final line in lines) {
      final d = _dateRe.firstMatch(line);
      if (d != null) {
        date = _toDate(d, now);
        continue;
      }
      if (_kindRe.hasMatch(line) && line.toLowerCase() != 'sip') {
        if (name != null) {
          left.add((date: date, name: name, kind: line));
          name = null;
        }
        continue;
      }
      final s = _statusRe.firstMatch(line);
      if (s != null) {
        statuses.add(_status(s.group(1)!));
        continue;
      }
      final a = _amountRe.firstMatch(line);
      if (a != null) {
        final amount = _amount(a);
        if (amount != null) amounts.add(amount);
        continue;
      }
      // Two-line names: "Parag Parikh Flexi Cap" + "Fund Direct Growth".
      if (_looksLikeName(line)) {
        name = name != null && !_endsName(name) && _continuesName(line)
            ? '$name $line'
            : line;
      }
    }

    if (left.isEmpty || amounts.isEmpty) return const [];
    final n = left.length < amounts.length ? left.length : amounts.length;
    // Statuses line up with amounts unless some were missed.
    final statusFits = statuses.length == amounts.length;
    return [
      for (var i = 0; i < n; i++)
        FundOrder(
          fund: SmsParser.shortFundName(left[i].name),
          amount: amounts[i].$1,
          amountGuessed: amounts[i].$2,
          date: left[i].date,
          kind: left[i].kind,
          status: statusFits || i < statuses.length
              ? statuses[i]
              : OrderStatus.unknown,
        ),
    ];
  }

  static bool _looksLikeName(String line) {
    if (_noise.hasMatch(line)) return false;
    if (line.length < 4) return false;
    return RegExp(r'[A-Za-z]{3}').hasMatch(line);
  }

  static bool _endsName(String name) => RegExp(
    r'(growth|idcw|plan|option|…|\.\.\.)$',
    caseSensitive: false,
  ).hasMatch(name);

  static bool _continuesName(String line) => RegExp(
    r'^(fund|direct|regular|plan|growth|idcw|option|cap|index)\b',
    caseSensitive: false,
  ).hasMatch(line);

  static DateTime? _toDate(RegExpMatch m, DateTime now) {
    final day = int.parse(m.group(1)!);
    final month = _months[m.group(2)!.toLowerCase().substring(0, 3)]!;
    var year = now.year;
    final y = m.group(3);
    if (y != null) {
      year = int.parse(y);
      if (year < 100) year += 2000;
    }
    final d = DateTime(year, month, day, 12);
    if (d.month != month) return null;
    if (y == null && d.isAfter(now)) return DateTime(year - 1, month, day, 12);
    return d;
  }

  static (double, bool)? _amount(RegExpMatch m) {
    final prefix = (m.group(1) ?? '').toLowerCase();
    var digits = m.group(2)!;
    var guessed = false;
    // A bare "120" is more likely a count or a page number than money.
    if (prefix.isEmpty && !digits.contains(RegExp(r'[,.]'))) return null;
    if (prefix == '7') {
      // "₹2,000.00" read as "72,000.00": the 7 is the rupee sign.
      guessed = true;
    } else if (prefix.isEmpty && digits.startsWith('7')) {
      final rest = digits.substring(1);
      if (RegExp(r'^\d{1,3}(,\d{2,3})*\.\d{2}$').hasMatch(rest) &&
          RegExp(r'^\d{1,3},').hasMatch(digits) &&
          !RegExp(r'^\d{1,2},\d{2},').hasMatch(digits)) {
        // e.g. "72,000.00" → "2,000.00". Only when the comma grouping
        // still works without the 7.
        digits = rest;
        guessed = true;
      }
    } else if (prefix.isNotEmpty &&
        prefix != '₹' &&
        !prefix.startsWith('rs') &&
        prefix != 'inr') {
      guessed = true; // Z / % / * in place of ₹
    }
    final v = double.tryParse(digits.replaceAll(',', ''));
    if (v == null || v <= 0) return null;
    return (v, guessed);
  }

  static OrderStatus _status(String s) => switch (s.toLowerCase()) {
    'completed' ||
    'successful' ||
    'success' ||
    'allotted' => OrderStatus.completed,
    'in progress' || 'processing' || 'pending' => OrderStatus.inProgress,
    _ => OrderStatus.failed,
  };
}
