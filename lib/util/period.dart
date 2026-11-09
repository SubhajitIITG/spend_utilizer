import 'package:intl/intl.dart';

/// A date range used by the Dashboard and statement export. Both ends are
/// whole days: [from] at 00:00 and [to] until the end of that day.
class Period {
  final DateTime from;
  final DateTime to;

  /// True when this is exactly one calendar month (the Dashboard's ‹ ›
  /// arrows step month by month).
  final bool isMonth;

  /// Short name for a preset ("Last 3 months"), empty for a custom range.
  final String preset;

  Period._(DateTime from, DateTime to, {this.isMonth = false, this.preset = ''})
    : from = DateTime(from.year, from.month, from.day),
      to = DateTime(to.year, to.month, to.day);

  factory Period.month(DateTime anyDay) {
    final start = DateTime(anyDay.year, anyDay.month);
    final end = DateTime(anyDay.year, anyDay.month + 1, 0);
    return Period._(start, end, isMonth: true);
  }

  factory Period.custom(DateTime from, DateTime to) =>
      from.isAfter(to) ? Period._(to, from) : Period._(from, to);

  /// The last [n] months including the current one.
  factory Period.lastMonths(int n, DateTime now) => Period._(
    DateTime(now.year, now.month - (n - 1)),
    now,
    preset: n == 12 ? 'Last 12 months' : 'Last $n months',
  );

  factory Period.thisYear(DateTime now) =>
      Period._(DateTime(now.year), now, preset: 'This year');

  /// Everything up to today (a very early start).
  factory Period.allTime(DateTime now) =>
      Period._(DateTime(2000), now, preset: 'All time');

  bool contains(DateTime d) =>
      !d.isBefore(from) && d.isBefore(to.add(const Duration(days: 1)));

  Period shiftMonths(int n) =>
      Period.month(DateTime(from.year, from.month + n));

  /// "November 2026", "1 Oct – 15 Nov 2026" or "Last 3 months".
  String get label {
    if (isMonth) return DateFormat('MMMM yyyy').format(from);
    if (preset == 'All time') return preset;
    final sameYear = from.year == to.year;
    final a = DateFormat(sameYear ? 'd MMM' : 'd MMM yyyy').format(from);
    final b = DateFormat('d MMM yyyy').format(to);
    return '$a – $b';
  }

  /// For file names: "2026-10-01_to_2026-11-15".
  String get fileTag {
    final f = DateFormat('yyyy-MM-dd');
    return isMonth
        ? DateFormat('yyyy-MM').format(from)
        : '${f.format(from)}_to_${f.format(to)}';
  }

  @override
  bool operator ==(Object other) =>
      other is Period && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}
