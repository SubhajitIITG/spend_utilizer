// Reads the text of a UPI payment screenshot (Google Pay, PhonePe, Paytm,
// BHIM, bank apps) and runs consistency checks that flag likely fakes.
//
// The text comes from on-device OCR (see ocr_service.dart). OCR text is
// noisy: "₹" is often read as "?", "%", "z" or "Z", lines can be split or
// merged, so every rule here is deliberately forgiving.
//
// A screenshot can never *prove* a payment: a perfect fake is possible.
// The checks catch common mistakes in fakes, and the strongest check is a
// matching bank SMS (see [ScreenshotChecker]).

import '../data/store.dart';
import '../models/models.dart';
import '../util/format.dart';
import 'sms_parser.dart';

enum PaymentApp {
  googlePay,
  phonePe,
  paytm,
  bhim,
  mobiKwik,
  superMoney,
  slice,
  other,
}

enum PaymentStatus { success, pending, failed, unknown }

extension PaymentAppX on PaymentApp {
  String get label => switch (this) {
    PaymentApp.googlePay => 'Google Pay',
    PaymentApp.phonePe => 'PhonePe',
    PaymentApp.paytm => 'Paytm',
    PaymentApp.bhim => 'BHIM',
    PaymentApp.mobiKwik => 'MobiKwik',
    PaymentApp.superMoney => 'super.money',
    PaymentApp.slice => 'slice',
    PaymentApp.other => 'payment app',
  };
}

class ParsedScreenshot {
  final PaymentApp app;
  final PaymentStatus status;

  /// True when the screenshot shows money coming in ("Received from").
  final bool received;
  final double amount;
  final String counterparty;
  final String upiId;
  final String bank;
  final String last4;

  /// Null when the screenshot shows no date.
  final DateTime? date;

  /// Whether [date] includes a time of day.
  final bool hasTime;

  /// 12-digit UPI reference (UTR / RRN), if shown.
  final String utr;

  /// App's own transaction ID (e.g. PhonePe "T2611081042…").
  final String appTxnId;

  /// Phone clock in the status bar at the top of the screenshot ("10:45").
  final (int, int)? statusBarTime;

  /// Amount written in words ("Rupees Fifteen Only", shown by Paytm).
  final double? amountInWords;
  final String rawText;

  const ParsedScreenshot({
    required this.app,
    required this.status,
    required this.received,
    required this.amount,
    required this.counterparty,
    required this.upiId,
    required this.bank,
    required this.last4,
    required this.date,
    required this.hasTime,
    required this.utr,
    required this.appTxnId,
    required this.statusBarTime,
    this.amountInWords,
    required this.rawText,
  });

  /// Name to show for the other party.
  String get who => counterparty.isNotEmpty ? counterparty : upiId;
}

class ScreenshotParser {
  /// Returns null when no payment amount can be found.
  static ParsedScreenshot? parse(String text, {DateTime? now}) {
    now ??= DateTime.now();
    final lines = text
        .split('\n')
        .map((l) => l.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    final lower = text.toLowerCase();

    final amount = _amount(lines);
    if (amount == null) return null;

    final received = _isReceived(lines);
    final (counterparty, upiId) = _counterparty(lines, received);
    final (date, hasTime) = _dateTime(lines, now);
    final (bank, last4) = _ownAccount(lines, received);

    return ParsedScreenshot(
      app: _app(lower),
      status: _status(lower),
      received: received,
      amount: amount,
      counterparty: counterparty,
      upiId: upiId,
      bank: bank,
      last4: last4,
      date: date,
      hasTime: hasTime,
      utr: _utr(lines),
      appTxnId: _appTxnId(text),
      statusBarTime: _statusBar(lines),
      amountInWords: _amountInWords(lower),
      rawText: text,
    );
  }

  static final _upiRe = RegExp(r'([\w.\-]+@[a-zA-Z][\w.\-]*)');

  static String _withoutUpiIds(String text) => text.replaceAll(_upiRe, ' ');

  // ------------------------------------------------------------------ app

  static PaymentApp _app(String lower) {
    if (lower.contains('phonepe') || RegExp(r'\bt\d{20,}').hasMatch(lower)) {
      return PaymentApp.phonePe;
    }
    if (lower.contains('google pay') ||
        lower.contains('gpay') ||
        lower.contains('google transaction id')) {
      return PaymentApp.googlePay;
    }
    if (lower.contains('bhim')) return PaymentApp.bhim;
    if (lower.contains('paytm')) return PaymentApp.paytm;
    if (lower.contains('mobikwik') || lower.contains('@ikwik')) {
      return PaymentApp.mobiKwik;
    }
    if (RegExp(r'super\.?\s?money|@superyes').hasMatch(lower)) {
      return PaymentApp.superMoney;
    }
    if (RegExp(r'\bslice\b').hasMatch(lower)) return PaymentApp.slice;
    return PaymentApp.other;
  }

  // --------------------------------------------------------------- status

  static PaymentStatus _status(String lower) {
    if (RegExp(r'\b(failed|failure|declined|unsuccessful|cancelled)\b')
        .hasMatch(lower)) {
      return PaymentStatus.failed;
    }
    if (RegExp(r'\b(pending|processing|in progress|awaiting)\b')
        .hasMatch(lower)) {
      return PaymentStatus.pending;
    }
    if (RegExp(
      r'\b(successful|success|completed|paid|received|money sent|'
      r'payment done)\b',
    ).hasMatch(lower)) {
      return PaymentStatus.success;
    }
    return PaymentStatus.unknown;
  }

  // ------------------------------------------------------------ direction

  // Labels that start the *other party's* section, and the user's own.
  static final _receivedStart = RegExp(
    r'^(received|money received|you received|received from|from\b|'
    r'credited to|credited account)',
    caseSensitive: false,
  );
  static final _paidStart = RegExp(
    r'^(paid\b|paid to|paid for|to\b|sent to|money sent|payment to|'
    r'debited from|debited account|for\b|order successful|transfer to)',
    caseSensitive: false,
  );

  /// The first direction label on the screen decides: Google Pay starts
  /// with "To Name" or "From Name", PhonePe with "Paid to" or "Received
  /// from", BHIM with "Paid" or "Received".
  static bool _isReceived(List<String> lines) {
    for (final l in lines) {
      if (_receivedStart.hasMatch(l)) return true;
      if (_paidStart.hasMatch(l)) return false;
    }
    return false;
  }

  // --------------------------------------------------------------- amount

  /// "₹500", "Rs. 1,250.00", or OCR-mangled "?500" / "Z500" / "%500".
  static final _currencyAmount = RegExp(
    r'(?:₹|rs\.?|inr|^[?%zZ])\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b',
    caseSensitive: false,
  );

  static double? _amount(List<String> lines) {
    for (final l in lines) {
      if (RegExp(
        r'(balance|limit|cashback|reward|offer|earned)',
        caseSensitive: false,
      ).hasMatch(l)) {
        continue;
      }
      final m = _currencyAmount.firstMatch(l);
      if (m != null) {
        final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null && v > 0 && v < 10000000) return v;
      }
    }
    // A big amount on its own line, e.g. "1,250" with the ₹ sign lost.
    for (final l in lines) {
      if (!RegExp(r'^([0-9]{1,3}(?:,[0-9]{2,3})+|[0-9]{1,6})(?:\.[0-9]{1,2})?$')
          .hasMatch(l)) {
        continue;
      }
      final v = double.tryParse(l.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    return null;
  }

  // ---------------------------------------------------------- counterparty

  static final _anyLabel = RegExp(
    r'^(paid|to|from|for|sent to|received|banking name|debited|credited|'
    r'upi|transaction|utr|rrn|order id|date|remarks|google transaction|'
    r'phonepe transaction|transfer details|payment|details|mobikwik)\b',
    caseSensitive: false,
  );

  static (String, String) _counterparty(List<String> lines, bool received) {
    final label = received
        ? RegExp(
            r'^(received from|from|money received from|credited by|'
            r'banking name)\b\s*:?\s*(.*)$',
            caseSensitive: false,
          )
        : RegExp(
            r'^(paid to|to|sent to|payment to|money sent to|transfer to|'
            r'paid for|for|banking name)\b\s*:?\s*(.*)$',
            caseSensitive: false,
          );
    for (var i = 0; i < lines.length; i++) {
      final m = label.firstMatch(lines[i]);
      if (m == null) continue;
      var name = _cleanName(m.group(2)!);
      var upi = '';
      var j = i + 1;
      // The name is on the next line when the label stands alone
      // (skipping avatar initials like "AS").
      while (name.isEmpty && j < lines.length && j <= i + 3) {
        final cand = lines[j];
        if (_upiRe.hasMatch(cand) && !cand.trim().contains(' ')) {
          upi = _upiRe.firstMatch(cand)!.group(1)!;
        } else if (!_skipForName(cand)) {
          name = _cleanName(cand);
        }
        j++;
      }
      // A name wrapped onto the next line: "Paytm" / "Cashback".
      if (name.isNotEmpty && j < lines.length && _isContinuation(lines[j])) {
        name = '$name ${_cleanName(lines[j])}';
        j++;
      }
      if (_upiRe.hasMatch(name)) {
        upi = _upiRe.firstMatch(name)!.group(1)!;
        name = _cleanName(name.replaceAll(_upiRe, ''));
      }
      // The UPI ID usually sits right under the name.
      for (var k = j; upi.isEmpty && k < lines.length && k <= j + 2; k++) {
        final m2 = _upiRe.firstMatch(lines[k]);
        if (m2 != null) upi = m2.group(1)!;
      }
      if (name.isNotEmpty || upi.isNotEmpty) return (name, upi);
    }
    return ('', '');
  }

  /// Removes amounts, separators and stray symbols from a name line.
  static String _cleanName(String s) => s
      .replaceAll(_currencyAmount, '')
      .replaceAll(RegExp(r'[•·|:✓✔]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _skipForName(String l) =>
      RegExp(r'^[A-Z]{1,2}$').hasMatch(l) || // avatar initials
      _currencyAmount.hasMatch(l) && _cleanName(l).isEmpty ||
      RegExp(r'^[+0-9 :,./•*-]+$').hasMatch(l) ||
      RegExp(
        r'(successful|completed|pending|failed|transaction|ref\b)',
        caseSensitive: false,
      ).hasMatch(l);

  static bool _isContinuation(String l) =>
      !_anyLabel.hasMatch(l) &&
      !l.contains(':') &&
      !l.contains('@') &&
      !RegExp(r'\d').hasMatch(l) &&
      !RegExp(r'^[xX*•\s]+$').hasMatch(l) &&
      !RegExp(r'^[A-Z]{1,2}$').hasMatch(l) &&
      l.split(' ').length <= 4 &&
      !RegExp(
        r'(successful|completed|google pay|powered|only)',
        caseSensitive: false,
      ).hasMatch(l);

  // ------------------------------------------------------- own account

  /// The user's own bank and last 4 digits, looked for in the user's part
  /// of the screen ("From" when paying, "To" / "Credited to" when
  /// receiving), so the other party's account and footers like "YES BANK"
  /// are never mistaken for the user's.
  static (String, String) _ownAccount(List<String> lines, bool received) {
    final ownLabel = received
        ? RegExp(
            r'^(to\b|credited to|credited account|credited in)',
            caseSensitive: false,
          )
        : RegExp(
            r'^(from\b|paid from|debited from|debited account)',
            caseSensitive: false,
          );
    final masked = RegExp(r'(?<![a-wyzA-WYZ])[xX*•]+\s?(\d{3,6})\b');
    final bankDigits = RegExp(
      r'bank\s*[-–:•·|]*\s*(\d{4})\b',
      caseSensitive: false,
    );

    for (var i = 0; i < lines.length; i++) {
      if (!ownLabel.hasMatch(lines[i])) continue;
      final section = <String>[lines[i]];
      for (var j = i + 1; j < lines.length && j <= i + 4; j++) {
        if (_receivedStart.hasMatch(lines[j]) ||
            _paidStart.hasMatch(lines[j]) ||
            RegExp(
              r'^(upi (transaction|ref)|utr|order id|google transaction)',
              caseSensitive: false,
            ).hasMatch(lines[j])) {
          break;
        }
        section.add(lines[j]);
      }
      final sectionText = _withoutUpiIds(section.join('\n'));
      final m =
          masked.firstMatch(sectionText) ?? bankDigits.firstMatch(sectionText);
      if (m != null) {
        return (SmsParser.bankIn(sectionText), _tail4(m.group(1)!));
      }
    }
    // Google Pay shows the user's bank as a header: "AU Small Finance Bank
    // 2061" (sometimes wrapped onto two lines).
    final noUpi = _withoutUpiIds(lines.join('\n'));
    for (final m in bankDigits.allMatches(noUpi)) {
      final start = noUpi.lastIndexOf('\n', m.start - 1);
      final lineText = noUpi.substring(start < 0 ? 0 : start, m.end);
      final bank = SmsParser.bankIn(lineText);
      if (bank != 'Unknown Bank') return (bank, m.group(1)!);
    }
    return ('Unknown Bank', '');
  }

  static String _tail4(String d) =>
      d.length > 4 ? d.substring(d.length - 4) : d;

  // ------------------------------------------------------------ reference

  static String _utr(List<String> lines) {
    final label = RegExp(
      r'(upi transaction id|upi ref(?:erence)?\.?\s*(?:no|number|id)?|utr|'
      r'rrn|ref(?:erence)?\.?\s*(?:no|number)|^transaction id)',
      caseSensitive: false,
    );
    for (var i = 0; i < lines.length; i++) {
      if (!label.hasMatch(lines[i])) continue;
      for (var j = i; j < lines.length && j <= i + 2; j++) {
        final m = RegExp(r'(?<![\dA-Za-z])(\d{12})(?!\d)').firstMatch(lines[j]);
        if (m != null) return m.group(1)!;
      }
    }
    for (final l in lines) {
      final m = RegExp(r'^(\d{12})$').firstMatch(l.replaceAll(' ', ''));
      if (m != null) return m.group(1)!;
    }
    return '';
  }

  static String _appTxnId(String text) {
    final m = RegExp(r'\b(T\d{20,})\b').firstMatch(text);
    return m?.group(1) ?? '';
  }

  // ------------------------------------------------------ amount in words

  static const _units = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };
  static const _scales = {
    'hundred': 100,
    'thousand': 1000,
    'lakh': 100000,
    'lakhs': 100000,
    'crore': 10000000,
    'crores': 10000000,
  };

  /// "Rupees Five Hundred Only" → 500. "... and Fifty Paise" adds 0.50.
  static double? _amountInWords(String lower) {
    final m = RegExp(r'rupees ([a-z\s-]+?)(?: and ([a-z\s-]+?) paise)? only')
        .firstMatch(lower);
    if (m == null) return null;
    final rupees = _words(m.group(1)!);
    if (rupees == null) return null;
    final paise = m.group(2) == null ? 0 : (_words(m.group(2)!) ?? 0);
    return rupees + paise / 100;
  }

  static int? _words(String s) {
    var total = 0, current = 0;
    for (final w in s.replaceAll('-', ' ').split(RegExp(r'\s+'))) {
      if (w.isEmpty || w == 'and') continue;
      if (_units.containsKey(w)) {
        current += _units[w]!;
      } else if (w == 'hundred') {
        current = (current == 0 ? 1 : current) * 100;
      } else if (_scales.containsKey(w)) {
        total += (current == 0 ? 1 : current) * _scales[w]!;
        current = 0;
      } else {
        return null;
      }
    }
    return total + current;
  }

  // ------------------------------------------------------------ date/time

  static final _timeRe = RegExp(
    r'(?<!\d)(\d{1,2}):(\d{2})(?::\d{2})?\s*([ap]\.?m\.?)',
    caseSensitive: false,
  );

  static (DateTime?, bool) _dateTime(List<String> lines, DateTime now) {
    // Skip the status bar (first line) when it is just the phone clock.
    final body = _statusBar(lines) != null ? lines.skip(1).toList() : lines;
    final joined = body.join('\n');
    var (d, found) = SmsParser.dateIn(joined, now);
    if (!found) return (null, false);
    // Prefer an am/pm time on the same line as the date ("8 Nov 2026,
    // 10:42 am" or PhonePe's "10:42 pm on 08 Nov 2026"); BHIM wraps the
    // time onto the next line.
    (int, int)? time;
    for (final l in body) {
      final t = _timeRe.firstMatch(l);
      if (t == null) continue;
      final hasDate = _hasDate(l);
      if (hasDate || time == null) {
        time = _to24(t);
        if (hasDate) break;
      }
    }
    // A 24-hour time on the date line, e.g. "07-11-26 21:04:05".
    if (time == null) {
      for (final l in body) {
        if (!_hasDate(l)) continue;
        final t = RegExp(
          r'(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?(?!\d)',
        ).firstMatch(l);
        if (t != null) {
          time = (int.parse(t.group(1)!), int.parse(t.group(2)!));
          break;
        }
      }
    }
    if (time == null) return (DateTime(d.year, d.month, d.day), false);
    return (DateTime(d.year, d.month, d.day, time.$1, time.$2), true);
  }

  static bool _hasDate(String l) => RegExp(
    r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|\d{1,2}[/.-]\d{1,2}[/.-]\d{2})',
    caseSensitive: false,
  ).hasMatch(l);

  static (int, int) _to24(RegExpMatch t) {
    var h = int.parse(t.group(1)!);
    final m = int.parse(t.group(2)!);
    final pm = t.group(3)!.toLowerCase().startsWith('p');
    if (pm && h < 12) h += 12;
    if (!pm && h == 12) h = 0;
    return (h, m);
  }

  static (int, int)? _statusBar(List<String> lines) {
    final m = RegExp(
      r'^(\d{1,2}):(\d{2})(?!\s*[ap]\.?m)\b',
      caseSensitive: false,
    ).firstMatch(lines.first);
    if (m == null) return null;
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return (h, min);
  }
}

// ======================================================================
// Checks
// ======================================================================

enum CheckLevel { ok, warn, bad }

class ScreenshotCheck {
  final CheckLevel level;
  final String text;
  const ScreenshotCheck(this.level, this.text);

  String get icon => switch (level) {
    CheckLevel.ok => '✅',
    CheckLevel.warn => '⚠️',
    CheckLevel.bad => '❌',
  };
}

enum Verdict { verified, consistent, suspicious }

class ScreenshotReport {
  final List<ScreenshotCheck> checks;
  final Verdict verdict;

  /// A transaction already in the app for this payment (same reference or a
  /// matching bank SMS), so the screenshot shouldn't be added again.
  final Txn? alreadyRecorded;
  const ScreenshotReport(this.checks, this.verdict, this.alreadyRecorded);

  String get verdictText => switch (verdict) {
    Verdict.verified => '🟢 Verified: this payment is in your bank messages.',
    Verdict.consistent =>
      '🟡 Looks consistent, but not verified. Check your bank app or SMS '
          'before trusting it.',
    Verdict.suspicious =>
      '🔴 Suspicious: this screenshot may be edited or fake. Check your bank '
          'before trusting it.',
  };
}

class ScreenshotChecker {
  static ScreenshotReport check(
    ParsedScreenshot p,
    AppStore store, {
    DateTime? now,
  }) {
    now ??= DateTime.now();
    final checks = <ScreenshotCheck>[];
    var verified = false;
    Txn? recorded;

    // 1. Status
    switch (p.status) {
      case PaymentStatus.failed:
        checks.add(
          const ScreenshotCheck(
            CheckLevel.bad,
            'The screen says the payment failed.',
          ),
        );
      case PaymentStatus.pending:
        checks.add(
          const ScreenshotCheck(
            CheckLevel.warn,
            'The payment is still pending, so no money has moved yet.',
          ),
        );
      case PaymentStatus.unknown:
        checks.add(
          const ScreenshotCheck(
            CheckLevel.warn,
            'No "Successful" or "Completed" status found on the screen.',
          ),
        );
      case PaymentStatus.success:
        break;
    }

    // 2. Date sanity
    final d = p.date;
    if (d == null) {
      checks.add(
        const ScreenshotCheck(
          CheckLevel.warn,
          'No date found on the screenshot.',
        ),
      );
    } else if (d.isAfter(now.add(const Duration(minutes: 5)))) {
      checks.add(
        ScreenshotCheck(
          CheckLevel.bad,
          'The date (${formatTxnDate(d)}) is in the future.',
        ),
      );
    }

    // 3. UPI reference number. Many banks build it as Y DDD … (last digit
    // of the year, day of the year), but not all: in real screenshots
    // Google Pay, PhonePe, BHIM and Paytm references often don't follow it.
    // So a match is a good sign, and only a number that clearly follows the
    // pattern but points to another day is a warning.
    if (p.utr.isEmpty) {
      checks.add(
        const ScreenshotCheck(
          CheckLevel.warn,
          'No 12-digit UPI reference number found. Most payment screens '
          'show one.',
        ),
      );
    } else if (d != null) {
      final y = int.parse(p.utr[0]);
      final ddd = int.parse(p.utr.substring(1, 4));
      final doy = d.difference(DateTime(d.year)).inDays + 1;
      if (y == d.year % 10 && ddd >= 1 && ddd <= 366) {
        if ((ddd - doy).abs() <= 1) {
          checks.add(
            ScreenshotCheck(
              CheckLevel.ok,
              'The UPI reference ${p.utr} matches the date.',
            ),
          );
        } else {
          final refDate = DateTime(d.year).add(Duration(days: ddd - 1));
          checks.add(
            ScreenshotCheck(
              CheckLevel.warn,
              'The UPI reference ${p.utr} may point to ${formatDate(refDate)}, '
              'but the screenshot says ${formatDate(d)}.',
            ),
          );
        }
      }
    }

    // 3b. Amount in words (Paytm) must match the digits.
    final words = p.amountInWords;
    if (words != null) {
      if ((words - p.amount).abs() < 0.01) {
        checks.add(
          const ScreenshotCheck(
            CheckLevel.ok,
            'The amount in words matches the digits.',
          ),
        );
      } else {
        checks.add(
          ScreenshotCheck(
            CheckLevel.bad,
            'The amount in words says ${money(words)}, but the digits say '
            '${money(p.amount)}.',
          ),
        );
      }
    }

    // 4. PhonePe transaction ID encodes date and time: T YYMMDDHHMM…
    if (p.appTxnId.isNotEmpty && d != null) {
      final m = RegExp(r'^T(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})')
          .firstMatch(p.appTxnId);
      if (m != null) {
        final idTime = DateTime(
          2000 + int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
          int.parse(m.group(4)!),
          int.parse(m.group(5)!),
        );
        final sameDay =
            idTime.year == d.year &&
            idTime.month == d.month &&
            idTime.day == d.day;
        final closeTime =
            !p.hasTime || idTime.difference(d).inMinutes.abs() <= 2;
        if (sameDay && closeTime) {
          checks.add(
            const ScreenshotCheck(
              CheckLevel.ok,
              'The transaction ID matches the date and time.',
            ),
          );
        } else {
          checks.add(
            ScreenshotCheck(
              CheckLevel.bad,
              'The transaction ID says ${formatTxnDate(idTime)}, which '
              'doesn\'t match the time shown.',
            ),
          );
        }
      }
    }

    // 5. Phone clock in the status bar vs. payment time (same day only).
    final sb = p.statusBarTime;
    if (sb != null && d != null && p.hasTime) {
      final today = DateTime(now.year, now.month, now.day);
      if (DateTime(d.year, d.month, d.day) == today) {
        final shot = DateTime(d.year, d.month, d.day, sb.$1, sb.$2);
        if (shot.isBefore(d.subtract(const Duration(minutes: 2)))) {
          checks.add(
            ScreenshotCheck(
              CheckLevel.bad,
              'The phone clock shows ${sb.$1}:${sb.$2.toString().padLeft(2, '0')}, '
              'which is before the payment time. The screenshot can\'t be '
              'taken before the payment.',
            ),
          );
        }
      }
    }

    // 6. Compare with what's already in the app.
    if (p.utr.isNotEmpty) {
      for (final t in store.txns) {
        if (t.refNo != p.utr) continue;
        recorded = t;
        if ((t.amount - p.amount).abs() > 0.009) {
          checks.add(
            ScreenshotCheck(
              CheckLevel.bad,
              'The same reference number is already recorded for '
              '${money(t.amount)}, not ${money(p.amount)}.',
            ),
          );
        } else if (t.source == 'sms') {
          verified = true;
          checks.add(
            ScreenshotCheck(
              CheckLevel.ok,
              'Matches a bank SMS you added (${formatTxnDate(t.date)}).',
            ),
          );
        } else {
          checks.add(
            ScreenshotCheck(
              CheckLevel.warn,
              'This screenshot was already added on ${formatDate(t.date)}.',
            ),
          );
        }
        break;
      }
    }
    if (recorded == null && p.received) {
      final match = _matchingCredit(store, p);
      if (match != null) {
        verified = true;
        recorded = match;
        checks.add(
          ScreenshotCheck(
            CheckLevel.ok,
            'A matching ${money(p.amount)} credit is in your bank messages '
            '(${formatTxnDate(match.date)}).',
          ),
        );
      } else {
        checks.add(
          const ScreenshotCheck(
            CheckLevel.warn,
            'No matching credit in your bank messages yet. Paste the bank '
            'SMS for this payment to verify it.',
          ),
        );
      }
    }

    final anyBad = checks.any((c) => c.level == CheckLevel.bad);
    final verdict = anyBad
        ? Verdict.suspicious
        : verified
        ? Verdict.verified
        : Verdict.consistent;
    return ScreenshotReport(checks, verdict, recorded);
  }

  /// A credit SMS with the same amount within 30 minutes (or the same day
  /// when the screenshot shows no time).
  static Txn? _matchingCredit(AppStore store, ParsedScreenshot p) {
    for (final t in store.txns) {
      if (t.type != TxnType.credit || t.source != 'sms') continue;
      if ((t.amount - p.amount).abs() > 0.009) continue;
      final d = p.date;
      if (d == null) continue;
      final sameDay =
          t.date.year == d.year &&
          t.date.month == d.month &&
          t.date.day == d.day;
      // SMS without a time are stored at 12:00:00; compare the day only.
      final smsHasTime =
          !(t.date.hour == 12 && t.date.minute == 0 && t.date.second == 0);
      final close = p.hasTime && smsHasTime
          ? t.date.difference(d).inMinutes.abs() <= 30
          : sameDay;
      if (close) return t;
    }
    return null;
  }
}
