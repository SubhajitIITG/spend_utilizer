// Core data models for Spend Utilizer.
//
// Everything is stored as plain JSON so the data file stays readable and
// easy to migrate later.

enum TxnType { debit, credit, lend, borrow }

enum AccountType { savings, creditCard, debitCard, wallet, cash }

extension TxnTypeX on TxnType {
  String get label => switch (this) {
        TxnType.debit => 'Debit',
        TxnType.credit => 'Credit',
        TxnType.lend => 'Lent',
        TxnType.borrow => 'Borrowed',
      };

  /// True when this transaction takes money out of the user's pocket.
  bool get isOutflow => this == TxnType.debit || this == TxnType.lend;
}

extension AccountTypeX on AccountType {
  String get label => switch (this) {
        AccountType.savings => 'Bank Account',
        AccountType.creditCard => 'Credit Card',
        AccountType.debitCard => 'Debit Card',
        AccountType.wallet => 'Wallet',
        AccountType.cash => 'Cash',
      };

  bool get isCard =>
      this == AccountType.creditCard || this == AccountType.debitCard;
}

DateTime _parseUpdated(Object? v) =>
    DateTime.tryParse(v as String? ?? '')?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// A bank account, card or wallet. Auto-created from bank messages using
/// (bank, type, last4) as the identity, so three credit cards from the same
/// bank become three separate accounts.
class Account {
  final String id;
  String bank;
  AccountType type;
  String last4;

  /// User-editable display name, e.g. "HDFC Millennia". Empty = auto name.
  String nickname;

  /// Last local change (UTC). Used to merge edits from several devices.
  DateTime updatedAt;

  Account({
    required this.id,
    required this.bank,
    required this.type,
    required this.last4,
    this.nickname = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  String get displayName {
    if (nickname.trim().isNotEmpty) return nickname.trim();
    if (type == AccountType.cash) return 'Cash';
    final suffix = last4.isEmpty ? '' : ' ••$last4';
    return '$bank ${type.label}$suffix';
  }

  /// Identity key used to match a parsed message to an existing account.
  String get matchKey =>
      '${bank.toLowerCase()}|${type.name}|${last4.toLowerCase()}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'bank': bank,
        'type': type.name,
        'last4': last4,
        'nickname': nickname,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        bank: j['bank'] as String? ?? 'Unknown',
        type: _enumByName(AccountType.values, j['type'], AccountType.savings),
        last4: j['last4'] as String? ?? '',
        nickname: j['nickname'] as String? ?? '',
        updatedAt: _parseUpdated(j['updatedAt']),
      );
}

class Txn {
  final String id;
  TxnType type;
  double amount;
  String category;
  String? accountId;

  /// Merchant, payee/payer, or for lend/borrow the person's name.
  String counterparty;
  String note;
  DateTime date;

  /// 'sms' when parsed from a bank message, 'manual' otherwise.
  String source;
  String rawMessage;
  String refNo;

  /// For lend/borrow: whether the money has been returned.
  bool settled;
  DateTime? dueDate;
  DateTime updatedAt;

  Txn({
    required this.id,
    required this.type,
    required this.amount,
    required this.category,
    this.accountId,
    this.counterparty = '',
    this.note = '',
    required this.date,
    this.source = 'manual',
    this.rawMessage = '',
    this.refNo = '',
    this.settled = false,
    this.dueDate,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'amount': amount,
        'category': category,
        'accountId': accountId,
        'counterparty': counterparty,
        'note': note,
        'date': date.toIso8601String(),
        'source': source,
        'rawMessage': rawMessage,
        'refNo': refNo,
        'settled': settled,
        'dueDate': dueDate?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: j['id'] as String,
        type: _enumByName(TxnType.values, j['type'], TxnType.debit),
        amount: (j['amount'] as num).toDouble(),
        category: j['category'] as String? ?? 'Others',
        accountId: j['accountId'] as String?,
        counterparty: j['counterparty'] as String? ?? '',
        note: j['note'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        source: j['source'] as String? ?? 'manual',
        rawMessage: j['rawMessage'] as String? ?? '',
        refNo: j['refNo'] as String? ?? '',
        settled: j['settled'] as bool? ?? false,
        dueDate: DateTime.tryParse(j['dueDate'] as String? ?? ''),
        updatedAt: _parseUpdated(j['updatedAt']),
      );
}

class Reminder {
  final String id;
  String title;
  double? amount;
  DateTime dueDate;
  bool done;

  /// Linked lend/borrow transaction, if any.
  String? txnId;
  DateTime updatedAt;

  Reminder({
    required this.id,
    required this.title,
    this.amount,
    required this.dueDate,
    this.done = false,
    this.txnId,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'dueDate': dueDate.toIso8601String(),
        'done': done,
        'txnId': txnId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        amount: (j['amount'] as num?)?.toDouble(),
        dueDate:
            DateTime.tryParse(j['dueDate'] as String? ?? '') ?? DateTime.now(),
        done: j['done'] as bool? ?? false,
        txnId: j['txnId'] as String?,
        updatedAt: _parseUpdated(j['updatedAt']),
      );
}

/// One bubble in the chat. Bot messages may reference a transaction so the
/// UI can show a summary card with edit/undo actions.
class ChatMessage {
  final String id;
  final bool fromUser;
  final String text;
  final DateTime time;
  final String? txnId;

  ChatMessage({
    required this.id,
    required this.fromUser,
    required this.text,
    required this.time,
    this.txnId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromUser': fromUser,
        'text': text,
        'time': time.toIso8601String(),
        'txnId': txnId,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        fromUser: j['fromUser'] as bool? ?? false,
        text: j['text'] as String? ?? '',
        time: DateTime.tryParse(j['time'] as String? ?? '') ?? DateTime.now(),
        txnId: j['txnId'] as String?,
      );
}
