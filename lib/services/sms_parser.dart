// Parses Indian bank / UPI transaction messages (SMS or e-mail alerts)
// into structured data: amount, debit/credit, bank, account type, last
// digits of the account/card, merchant/payee, reference number and date.
//
// It is rule-based (regular expressions), works fully offline, and is
// covered by tests in test/sms_parser_test.dart. When a new bank format
// is not understood, add a sample to the tests and extend the rules here.

import '../models/models.dart';
import 'categories.dart';

class ParsedSms {
  final TxnType type; // debit or credit
  final double amount;
  final String bank;
  final AccountType accountType;
  final String last4;
  final String counterparty;
  final String refNo;
  final DateTime date;
  final bool isRefund;
  final String category;

  const ParsedSms({
    required this.type,
    required this.amount,
    required this.bank,
    required this.accountType,
    required this.last4,
    required this.counterparty,
    required this.refNo,
    required this.date,
    required this.isRefund,
    required this.category,
  });

  @override
  String toString() => 'ParsedSms(${type.name} $amount $bank '
      '${accountType.name} $last4 "$counterparty" ref=$refNo $date $category)';
}

class SmsParser {
  /// Splits a paste that may contain several messages (separated by blank
  /// lines) into individual messages.
  static List<String> splitMessages(String text) {
    return text
        .split(RegExp(r'\n\s*\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Returns null when the text does not look like a transaction alert.
  static ParsedSms? parse(String raw, {DateTime? now}) {
    now ??= DateTime.now();
    final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    final amount = _amount(text);
    if (amount == null || amount <= 0) return null;

    final type = _type(lower);
    if (type == null) return null;

    // Ignore OTP / "will be debited" style messages that are not real
    // transactions yet.
    if (RegExp(r'\b(otp|one time password)\b').hasMatch(lower) &&
        !RegExp(r'\b(debited|credited|spent|sent)\b').hasMatch(lower)) {
      return null;
    }

    final isRefund = RegExp(r'\b(refund(ed)?|reversal|reversed)\b')
        .hasMatch(lower);
    final bank = _bank(lower);
    final accountType = _accountType(lower);
    final last4 = _last4(text);
    final counterparty = _counterparty(text);
    final refNo = _refNo(text);
    final date = _date(text, now);

    final category = isRefund
        ? 'Refund'
        : guessCategory(
            isCredit: type == TxnType.credit,
            merchant: counterparty,
            message: text,
          );

    return ParsedSms(
      type: isRefund ? TxnType.credit : type,
      amount: amount,
      bank: bank,
      accountType: accountType,
      last4: last4,
      counterparty: counterparty,
      refNo: refNo,
      date: date,
      isRefund: isRefund,
      category: category,
    );
  }

  // ---------------------------------------------------------------- amount

  static final _amountRe = RegExp(
    r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final _bareAmountRe = RegExp(
    r'\b(?:debited|credited|spent|sent|paid|received)\s+(?:by|for|with|of)'
    r'\s+([0-9][0-9,]*(?:\.[0-9]{1,2})?)\b',
    caseSensitive: false,
  );

  static double? _amount(String text) {
    for (final m in _amountRe.allMatches(text)) {
      // Skip "Avl Bal Rs 12,000" / "Avl Lmt INR 50,000" style amounts.
      final start = m.start;
      final before = text
          .substring(start - 25 < 0 ? 0 : start - 25, start)
          .toLowerCase();
      if (RegExp(r'(bal|balance|lmt|limit)[^a-z]*$|avl\.?\s*$')
          .hasMatch(before)) {
        continue;
      }
      final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    // Some banks (e.g. SBI UPI) omit the currency: "debited by 250.0".
    final bare = _bareAmountRe.firstMatch(text);
    if (bare != null) {
      return double.tryParse(bare.group(1)!.replaceAll(',', ''));
    }
    return null;
  }

  // ------------------------------------------------------------------ type

  static final _debitRe = RegExp(
    r'\b(debited|debit(?!\s*card)|spent|sent|paid|withdrawn|withdrawal|'
    r'purchase|deducted|txn of|transferred|payment of rs|dr\.?\s)',
  );
  static final _creditRe = RegExp(
    r'\b(credited|received|deposited|refund(ed)?|reversed|reversal|'
    r'credit of|added to|cr\.?\s)',
  );

  /// Whichever keyword appears first wins: "debited from A/c ...; AMAZON
  /// credited" is a debit.
  static TxnType? _type(String lower) {
    final d = _debitRe.firstMatch(lower);
    final c = _creditRe.firstMatch(lower);
    if (d == null && c == null) return null;
    if (d == null) return TxnType.credit;
    if (c == null) return TxnType.debit;
    // A refund mention anywhere means money came back.
    if (RegExp(r'\brefund(ed)?\b').hasMatch(lower) &&
        !RegExp(r'\bdebited\b').hasMatch(lower)) {
      return TxnType.credit;
    }
    // "Payment of Rs X received towards your credit card" is a card
    // repayment, i.e. a credit to the card.
    if (lower.contains('received towards') ||
        lower.contains('payment received')) {
      return TxnType.credit;
    }
    return d.start <= c.start ? TxnType.debit : TxnType.credit;
  }

  // ------------------------------------------------------------------ bank

  // Order matters: "State Bank of India" contains "Bank of India" and
  // "Indian Overseas Bank" contains "Indian ... Bank".
  static const _banks = <String, List<String>>{
    'SBI': ['state bank of india', 'sbi', 'sbiinb', 'sbipsg', 'sbicrd'],
    'HDFC': ['hdfc', 'hdfcbk'],
    'ICICI': ['icici'],
    'Axis': ['axis bank', 'axisbk', 'axis'],
    'Kotak': ['kotak'],
    'PNB': ['punjab national', 'pnb'],
    'Bank of Baroda': ['bank of baroda', 'bob ', 'bobcard', 'bobtxn'],
    'Canara': ['canara'],
    'Union Bank': ['union bank', 'unionb'],
    'IDFC First': ['idfc'],
    'Yes Bank': ['yes bank', 'yesbnk', 'yesbank'],
    'IndusInd': ['indusind', 'indus'],
    'AU Bank': ['au small finance', 'au bank', 'aubank'],
    'Federal Bank': ['federal bank', 'fedbnk', 'federal'],
    'RBL': ['rbl'],
    'Standard Chartered': ['standard chartered', 'stanchart', 'scbank'],
    'HSBC': ['hsbc'],
    'Citi': ['citibank', 'citi'],
    'Amex': ['american express', 'amex'],
    'IDBI': ['idbi'],
    'Indian Overseas Bank': ['indian overseas', 'iob '],
    'Indian Bank': ['indian bank', 'indbnk'],
    'Bank of India': ['bank of india', 'boi '],
    'Central Bank': ['central bank'],
    'UCO Bank': ['uco bank', 'ucobnk'],
    'Bank of Maharashtra': ['bank of maharashtra', 'mahabk'],
    'Paytm Payments Bank': ['paytm payments bank', 'paytm bank', 'paytm'],
    'Airtel Payments Bank': ['airtel payments bank'],
    'Jupiter': ['jupiter'],
    'Fi': ['fi money', 'federal bank fi'],
    'OneCard': ['onecard'],
    'Slice': ['slice'],
    'DBS': ['dbs'],
    'Equitas': ['equitas'],
    'Ujjivan': ['ujjivan'],
    'South Indian Bank': ['south indian bank', 'sib '],
    'Karnataka Bank': ['karnataka bank'],
  };

  static String _bank(String lower) {
    // Remove UPI IDs first: "abc@hdfcbank" is the payee's bank, not ours.
    final cleaned =
        ' ${lower.replaceAll(RegExp(r'[\w.\-]+@[\w.\-]+'), ' ')} ';
    for (final entry in _banks.entries) {
      for (final alias in entry.value) {
        final re = RegExp('(?<![a-z])${RegExp.escape(alias)}');
        if (re.hasMatch(cleaned)) return entry.key;
      }
    }
    return 'Unknown Bank';
  }

  // ---------------------------------------------------------- account type

  static AccountType _accountType(String lower) {
    if (RegExp(r'credit\s*card|\bcc\b').hasMatch(lower)) {
      return AccountType.creditCard;
    }
    if (RegExp(r'debit\s*card|\bdc\b|atm\s*card').hasMatch(lower)) {
      return AccountType.debitCard;
    }
    if (RegExp(r'\bwallet\b').hasMatch(lower)) return AccountType.wallet;
    if (RegExp(r'\bcard\b').hasMatch(lower)) {
      // A bare "card" with an available *limit* is a credit card.
      if (RegExp(r'\b(avl\.?\s*lmt|available limit|limit)\b')
          .hasMatch(lower)) {
        return AccountType.creditCard;
      }
      if (RegExp(r'\b(a/?c|acct|account)\b').hasMatch(lower) &&
          !RegExp(r'card\s*(no\.?\s*)?(ending|xx|x\d|\*)').hasMatch(lower)) {
        return AccountType.savings;
      }
      return AccountType.creditCard;
    }
    return AccountType.savings;
  }

  // ----------------------------------------------------------------- last4

  static String _last4(String text) {
    // Masked numbers: XX1234, x4321, *1234, XXXXXXXX5678, ••1234
    final masked =
        RegExp(r'(?<![a-wyzA-WYZ])[xX*•]+\s?(\d{3,6})\b').firstMatch(text);
    if (masked != null) return _tail(masked.group(1)!);

    final ending = RegExp(r'ending\s*(?:with|in)?\s*(\d{3,6})\b',
            caseSensitive: false)
        .firstMatch(text);
    if (ending != null) return _tail(ending.group(1)!);

    final near = RegExp(
      r'\b(?:a/?c|acct|account|card)\b\s*(?:no\.?|number)?\s*[:#]?\s*(\d{3,6})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (near != null) return _tail(near.group(1)!);
    return '';
  }

  static String _tail(String digits) =>
      digits.length > 4 ? digits.substring(digits.length - 4) : digits;

  // ---------------------------------------------------------- counterparty

  static final _vpa = r'([\w.\-]+@[\w.\-]+)';
  static final _stop = r'(?=\s+(?:on|via|ref\w*|utr|rrn|txn|call|if|for|using|from|thru|through|'
      r'avl|upi|dated|at|with|is|has|not)\b|[.,;(]|\s-|$)';

  static String _counterparty(String text) {
    final patterns = <RegExp>[
      RegExp('\\bto\\s+vpa\\s+$_vpa', caseSensitive: false),
      RegExp('\\b(?:from|by)\\s+vpa\\s+$_vpa', caseSensitive: false),
      RegExp('\\bvpa\\s+$_vpa', caseSensitive: false),
      RegExp('\\b(?:to|from|by)\\s+$_vpa', caseSensitive: false),
      RegExp(r';\s*([A-Za-z0-9][A-Za-z0-9 .&_-]{1,40}?)\s+credited',
          caseSensitive: false),
      RegExp(r'UPI/(?:P2M|P2A|DR|CR)/\d+/([^/\s]+)', caseSensitive: false),
      RegExp(
        '\\b(?:at|towards|to|info:?)\\s+'
        "([A-Za-z0-9][A-Za-z0-9 .&*'_@-]{1,40}?)$_stop",
        caseSensitive: false,
      ),
      RegExp(
        '\\b(?:from|by)\\s+'
        "([A-Za-z][A-Za-z0-9 .&'_@-]{1,40}?)$_stop",
        caseSensitive: false,
      ),
    ];
    for (final re in patterns) {
      for (final m in re.allMatches(text)) {
        final c = _cleanCounterparty(m.group(1)!);
        if (c.isNotEmpty) return c;
      }
    }
    return '';
  }

  static String _cleanCounterparty(String s) {
    var c = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    c = c.replaceAll(RegExp(r'[.\-*]+$'), '').trim();
    final l = c.toLowerCase();
    // Reject phrases that describe the user's own account, not a payee.
    if (c.length < 2 ||
        RegExp(r'^\d+$').hasMatch(c) ||
        RegExp(r'\b(your|ur|a/?c|acct|account|card|bank|self|linked)\b')
            .hasMatch(l) ||
        RegExp(r'^(rs|inr|the|a|an|you|your)$').hasMatch(l) ||
        RegExp(r'^[xX*]+\d+').hasMatch(c)) {
      return '';
    }
    return c;
  }

  // ---------------------------------------------------------------- ref no

  static String _refNo(String text) {
    final res = <RegExp>[
      RegExp(
        r'(?:upi\s*ref(?:erence)?|ref(?:erence)?|utr|rrn|txn\s*id|'
        r'transaction\s*id)\.?\s*(?:no|num|number|id)?\.?\s*[:#-]?\s*'
        r'([A-Za-z0-9]*\d[A-Za-z0-9]{5,})',
        caseSensitive: false,
      ),
      RegExp(r'\bupi[:/\s]+(\d{9,})', caseSensitive: false),
      RegExp(r'UPI/(?:P2M|P2A|DR|CR)/(\d{6,})', caseSensitive: false),
    ];
    for (final re in res) {
      final m = re.firstMatch(text);
      if (m != null) return m.group(1)!;
    }
    return '';
  }

  // ------------------------------------------------------------------ date

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime _date(String text, DateTime now) {
    DateTime? candidate;

    final iso = RegExp(r'\b(20\d{2})-(\d{1,2})-(\d{1,2})').firstMatch(text);
    if (iso != null) {
      candidate = _safeDate(int.parse(iso.group(1)!),
          int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    }

    if (candidate == null) {
      final named = RegExp(
        r'\b(\d{1,2})[-\s]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)'
        r'[a-z]*[-\s,]*(\d{4}|\d{2})?\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (named != null) {
        final y = named.group(3) == null
            ? now.year
            : _year(int.parse(named.group(3)!));
        candidate = _safeDate(y, _months[named.group(2)!.toLowerCase()]!,
            int.parse(named.group(1)!));
      }
    }

    if (candidate == null) {
      final dmy = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b')
          .firstMatch(text);
      if (dmy != null) {
        candidate = _safeDate(_year(int.parse(dmy.group(3)!)),
            int.parse(dmy.group(2)!), int.parse(dmy.group(1)!));
      }
    }

    if (candidate == null) return now;
    // Bank messages arrive soon after the transaction, so a date far in
    // the future means we misread it.
    if (candidate.isAfter(now.add(const Duration(days: 1)))) return now;
    // Keep the time of day from "now" so ordering within a day is natural.
    if (candidate.year == now.year &&
        candidate.month == now.month &&
        candidate.day == now.day) {
      return now;
    }
    return DateTime(candidate.year, candidate.month, candidate.day, 12);
  }

  static int _year(int y) => y < 100 ? 2000 + y : y;

  static DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) {
      return null;
    }
    final dt = DateTime(y, m, d);
    if (dt.month != m) return null; // e.g. 31 Feb
    return dt;
  }
}
