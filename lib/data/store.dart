import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../services/categories.dart';
import '../services/sms_parser.dart';
import '../services/sync_types.dart';
import '../util/period.dart';

/// Where the JSON data lives. Swappable so tests can use memory.
abstract class Storage {
  Future<String?> read();
  Future<void> write(String data);
}

class FileStorage implements Storage {
  File? _file;

  Future<File> _getFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return _file = File(
      '${dir.path}${Platform.pathSeparator}'
      'spend_utilizer_data.json',
    );
  }

  @override
  Future<String?> read() async {
    final f = await _getFile();
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String data) async {
    final f = await _getFile();
    // Write to a temp file then rename, so a crash never corrupts data.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }
}

class MemoryStorage implements Storage {
  String? data;
  MemoryStorage([this.data]);
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String d) async => data = d;
}

enum SmsStatus { added, duplicate, notTransaction }

class SmsResult {
  final SmsStatus status;
  final Txn? txn;
  final Account? account;
  final bool newAccount;

  /// False when the SMS had no date and today was used.
  final bool dateFound;
  const SmsResult(
    this.status, {
    this.txn,
    this.account,
    this.newAccount = false,
    this.dateFound = true,
  });
}

class CategoryTotal {
  final String category;
  final double amount;
  const CategoryTotal(this.category, this.amount);
}

class PersonBalance {
  final String person;

  /// Positive: they owe you. Negative: you owe them.
  final double amount;
  const PersonBalance(this.person, this.amount);
}

/// A merchant the user pays regularly that we could not categorise.
class MerchantSuggestion {
  final String key;

  /// The counterparty as it appears on the latest payment.
  final String label;
  final int count;
  final double total;
  final double minAmount;
  final double maxAmount;
  final int days;
  const MerchantSuggestion({
    required this.key,
    required this.label,
    required this.count,
    required this.total,
    required this.minAmount,
    required this.maxAmount,
    required this.days,
  });
}

class AppStore extends ChangeNotifier {
  /// "Regular": at least this many payments to one merchant…
  static const regularMinCount = 3;

  /// …within this many days…
  static const regularWindowDays = 30;

  /// …each no bigger than this (small everyday payments).
  static const regularMaxAmount = 2000.0;

  final Storage storage;
  AppStore({Storage? storage}) : storage = storage ?? FileStorage();

  final List<Account> accounts = [];
  final List<Txn> txns = [];
  final List<Reminder> reminders = [];
  final List<ChatMessage> chat = [];

  /// What the user told us about merchants, keyed by [merchantKey].
  final Map<String, MerchantRule> merchants = {};
  bool loaded = false;

  // ---- Sync bookkeeping (see services/sync_service.dart)

  /// Records changed locally and not yet uploaded: "kind:id".
  final Set<String> dirty = {};

  /// Deleted records not yet uploaded: "kind:id" → time of deletion.
  final Map<String, DateTime> tombstones = {};

  /// Server cursor: we have downloaded everything synced before this.
  String? syncCursor;

  /// The signed-in user this local data belongs to (null = never synced).
  String? ownerId;

  /// Called after every local edit (not after applying downloaded data),
  /// so the sync service can upload soon.
  VoidCallback? onLocalChange;

  int _idCounter = 0;
  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(_idCounter++).toRadixString(36)}';

  // ------------------------------------------------------------ persistence

  Future<void> load() async {
    try {
      final raw = await storage.read();
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        accounts.addAll(
          (j['accounts'] as List? ?? []).map(
            (e) => Account.fromJson(e as Map<String, dynamic>),
          ),
        );
        txns.addAll(
          (j['txns'] as List? ?? []).map(
            (e) => Txn.fromJson(e as Map<String, dynamic>),
          ),
        );
        reminders.addAll(
          (j['reminders'] as List? ?? []).map(
            (e) => Reminder.fromJson(e as Map<String, dynamic>),
          ),
        );
        chat.addAll(
          (j['chat'] as List? ?? []).map(
            (e) => ChatMessage.fromJson(e as Map<String, dynamic>),
          ),
        );
        for (final e in (j['merchants'] as List? ?? [])) {
          final m = MerchantRule.fromJson(e as Map<String, dynamic>);
          merchants[m.key] = m;
        }
        _migrate();
        final sync = j['sync'] as Map<String, dynamic>? ?? {};
        dirty.addAll((sync['dirty'] as List? ?? []).cast<String>());
        (sync['tombstones'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
          final d = DateTime.tryParse(v as String);
          if (d != null) tombstones[k] = d.toUtc();
        });
        syncCursor = sync['cursor'] as String?;
        ownerId = sync['ownerId'] as String?;
      }
    } catch (e) {
      debugPrint('Failed to load data: $e');
    }
    loaded = true;
    notifyListeners();
  }

  Timer? _saveTimer;

  /// [local]: the user changed something, so it should be uploaded.
  void _changed({bool local = true}) {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), saveNow);
    if (local) onLocalChange?.call();
  }

  void _touchAccount(Account a) {
    a.updatedAt = DateTime.now().toUtc();
    dirty.add(syncKey(SyncKind.account, a.id));
  }

  void _touchTxn(Txn t) {
    t.updatedAt = DateTime.now().toUtc();
    dirty.add(syncKey(SyncKind.txn, t.id));
  }

  void _touchReminder(Reminder r) {
    r.updatedAt = DateTime.now().toUtc();
    dirty.add(syncKey(SyncKind.reminder, r.id));
  }

  void _touchMerchant(MerchantRule m) {
    m.updatedAt = DateTime.now().toUtc();
    dirty.add(syncKey(SyncKind.merchant, m.key));
  }

  void _bury(SyncKind kind, String id) {
    final k = syncKey(kind, id);
    dirty.remove(k);
    tombstones[k] = DateTime.now().toUtc();
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    // Keep the chat log from growing forever.
    if (chat.length > 500) chat.removeRange(0, chat.length - 500);
    final data = jsonEncode({
      'version': 1,
      'accounts': accounts.map((a) => a.toJson()).toList(),
      'txns': txns.map((t) => t.toJson()).toList(),
      'reminders': reminders.map((r) => r.toJson()).toList(),
      'chat': chat.map((c) => c.toJson()).toList(),
      'merchants': merchants.values.map((m) => m.toJson()).toList(),
      'sync': {
        'dirty': dirty.toList(),
        'tombstones': tombstones.map(
          (k, v) => MapEntry(k, v.toIso8601String()),
        ),
        'cursor': syncCursor,
        'ownerId': ownerId,
      },
    });
    await storage.write(data);
  }

  // --------------------------------------------------------------- lookups

  Account? accountById(String? id) {
    if (id == null) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Txn? txnById(String? id) {
    if (id == null) return null;
    for (final t in txns) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The user's own accounts and cards (confirmed as theirs).
  Iterable<Account> get myAccounts => accounts.where((a) => a.isMine);

  /// Found in bank messages, waiting for "is this yours?".
  List<Account> get pendingAccounts =>
      accounts.where((a) => a.ownership == Ownership.pending).toList();

  /// Accounts the user said belong to someone else (hidden from Accounts).
  List<Account> get notMineAccounts =>
      accounts.where((a) => a.ownership == Ownership.notMine).toList();

  /// Accounts that can be picked when entering a payment.
  Iterable<Account> get selectableAccounts =>
      accounts.where((a) => a.ownership != Ownership.notMine);

  List<String> get banks {
    final set = <String>{};
    for (final a in myAccounts) {
      if (a.type != AccountType.cash) set.add(a.bank);
    }
    return set.toList()..sort();
  }

  int get cardCount => myAccounts.where((a) => a.type.isCard).length;
  int get bankAccountCount =>
      myAccounts.where((a) => a.type == AccountType.savings).length;

  // -------------------------------------------------------------- accounts

  /// Finds the account matching (bank, type, last4), creating it if new.
  (Account, bool) findOrCreateAccount(
    String bank,
    AccountType type,
    String last4,
  ) {
    final probe = Account(id: '', bank: bank, type: type, last4: last4);
    for (final a in accounts) {
      if (a.matchKey == probe.matchKey) return (a, false);
    }
    // Same bank + last digits but a different guessed type (e.g. a message
    // that just said "card"): reuse the existing account.
    if (last4.isNotEmpty) {
      for (final a in accounts) {
        if (a.bank.toLowerCase() == bank.toLowerCase() && a.last4 == last4) {
          return (a, false);
        }
      }
    }
    final created = Account(
      id: newId(),
      bank: bank,
      type: type,
      last4: last4,
      // Found in a message: ask the user before treating it as theirs.
      ownership: type == AccountType.cash ? Ownership.mine : Ownership.pending,
    );
    accounts.add(created);
    _touchAccount(created);
    _changed();
    return (created, true);
  }

  Account cashAccount() {
    for (final a in accounts) {
      if (a.type == AccountType.cash) return a;
    }
    final (a, _) = findOrCreateAccount('Cash', AccountType.cash, '');
    return a;
  }

  /// Upgrades data saved by older versions of the app.
  void _migrate() {
    // Money sent out used to be filed as "Transfer"; it is now "Payees".
    for (final t in txns) {
      if (t.type == TxnType.debit && t.category == 'Transfer') {
        t.category = payeesCategory;
      }
    }
    for (final m in merchants.values) {
      if (m.category == 'Transfer') m.category = payeesCategory;
    }
    // Cash is always the user's own.
    for (final a in accounts) {
      if (a.type == AccountType.cash) a.ownership = Ownership.mine;
    }
  }

  /// The user confirmed whether [a] is theirs. Someone else's account is
  /// kept (so we remember the answer) but its payments are detached from
  /// it and the account becomes the payee.
  void setOwnership(Account a, Ownership ownership) {
    a.ownership = ownership;
    _touchAccount(a);
    if (ownership == Ownership.notMine) {
      for (final t in txns) {
        if (t.accountId != a.id) continue;
        t.accountId = null;
        if (t.counterparty.trim().isEmpty) {
          t.counterparty = 'A/c ••${a.last4}';
        }
        if (t.type == TxnType.debit &&
            !t.userCategorized &&
            unclearCategories.contains(t.category)) {
          t.category = payeesCategory;
        }
        _touchTxn(t);
      }
    }
    _changed();
  }

  void addAccount(Account a) {
    accounts.add(a);
    _touchAccount(a);
    _changed();
  }

  void updateAccount(
    Account a, {
    String? bank,
    String? nickname,
    AccountType? type,
    String? last4,
  }) {
    if (bank != null) a.bank = bank.trim();
    if (nickname != null) a.nickname = nickname.trim();
    if (type != null) a.type = type;
    if (last4 != null) a.last4 = last4.trim();
    _touchAccount(a);
    _changed();
  }

  /// Renames a bank across all its accounts, e.g. "Unknown Bank" → "Jana".
  void renameBank(String oldName, String newName) {
    for (final a in accounts) {
      if (a.bank == oldName) {
        a.bank = newName.trim();
        _touchAccount(a);
      }
    }
    _changed();
  }

  void deleteAccount(Account a) {
    accounts.remove(a);
    _bury(SyncKind.account, a.id);
    for (final t in txns) {
      if (t.accountId == a.id) {
        t.accountId = null;
        _touchTxn(t);
      }
    }
    _changed();
  }

  // ---------------------------------------------------------- transactions

  bool _isDuplicate(ParsedSms p, String raw) {
    final norm = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final t in txns) {
      // Same payment already added from a screenshot.
      if (t.source == 'screenshot' &&
          p.refNo.isNotEmpty &&
          t.refNo == p.refNo &&
          t.amount == p.amount) {
        return true;
      }
      if (t.source != 'sms') continue;
      if (p.refNo.isNotEmpty && t.refNo == p.refNo && t.amount == p.amount) {
        return true;
      }
      if (t.rawMessage.replaceAll(RegExp(r'\s+'), ' ').trim() == norm) {
        return true;
      }
    }
    return false;
  }

  SmsResult addFromSms(String raw) {
    final p = SmsParser.parse(raw);
    if (p == null) return const SmsResult(SmsStatus.notTransaction);
    if (_isDuplicate(p, raw)) return const SmsResult(SmsStatus.duplicate);
    final (found, isNew) = findOrCreateAccount(p.bank, p.accountType, p.last4);
    // The user said this account isn't theirs: don't attach payments to it.
    final account = found.ownership == Ownership.notMine ? null : found;
    // A category the user taught us for this merchant beats the guess.
    final rule = merchants[merchantKey(p.counterparty)];
    final category = p.type == TxnType.debit && (rule?.decided ?? false)
        ? rule!.category
        : p.category;
    final t = Txn(
      id: newId(),
      type: p.type,
      amount: p.amount,
      category: category,
      accountId: account?.id,
      counterparty: p.counterparty.isEmpty && account == null
          ? 'A/c ••${found.last4}'
          : p.counterparty,
      date: p.date,
      source: 'sms',
      rawMessage: raw.trim(),
      refNo: p.refNo,
    );
    txns.add(t);
    _touchTxn(t);
    _changed();
    return SmsResult(
      SmsStatus.added,
      txn: t,
      account: found,
      newAccount: isNew,
      dateFound: p.dateFound,
    );
  }

  /// Records a payment read from a screenshot (see screenshot_parser).
  Txn addFromScreenshot({
    required bool received,
    required double amount,
    required String counterparty,
    required DateTime date,
    required String refNo,
    required String bank,
    required String last4,
    AccountType accountType = AccountType.savings,
    required String category,
    required String rawText,
  }) {
    Account? account;
    if (last4.isNotEmpty && bank != 'Unknown Bank') {
      final (found, _) = findOrCreateAccount(bank, accountType, last4);
      account = found.ownership == Ownership.notMine ? null : found;
    } else if (last4.isNotEmpty) {
      // Bank not shown (e.g. only a logo): use the user's account with
      // these last digits, if there's exactly one.
      final matches = selectableAccounts.where((a) => a.last4 == last4);
      if (matches.length == 1) account = matches.first;
    }
    final rule = merchants[merchantKey(counterparty)];
    final t = Txn(
      id: newId(),
      type: received ? TxnType.credit : TxnType.debit,
      amount: amount,
      category: !received && (rule?.decided ?? false)
          ? rule!.category
          : category,
      accountId: account?.id,
      counterparty: counterparty,
      date: date,
      source: 'screenshot',
      rawMessage: rawText,
      refNo: refNo,
    );
    txns.add(t);
    _touchTxn(t);
    _changed();
    return t;
  }

  // -------------------------------------------------------------- merchants

  MerchantRule? merchantRule(String counterparty) =>
      merchants[merchantKey(counterparty)];

  /// Display name for a merchant: the user's alias if they gave one.
  String merchantLabel(String counterparty) {
    final alias = merchantRule(counterparty)?.alias ?? '';
    return alias.isNotEmpty ? alias : counterparty;
  }

  /// Merchants paid regularly in small amounts whose category we couldn't
  /// work out, and the user hasn't told us about yet. Most frequent first.
  List<MerchantSuggestion> merchantsToReview({DateTime? now}) {
    now ??= DateTime.now();
    final since = now.subtract(const Duration(days: regularWindowDays));
    final groups = <String, List<Txn>>{};
    for (final t in txns) {
      if (t.type != TxnType.debit || t.counterparty.trim().isEmpty) continue;
      if (t.date.isBefore(since) || t.amount > regularMaxAmount) continue;
      groups.putIfAbsent(merchantKey(t.counterparty), () => []).add(t);
    }
    final out = <MerchantSuggestion>[];
    groups.forEach((key, list) {
      if (list.length < regularMinCount) return;
      final rule = merchants[key];
      if (rule != null) {
        if (rule.decided || rule.neverAsk) return;
        if (rule.askAfter != null && now!.isBefore(rule.askAfter!)) return;
      }
      // Only ask when we're unsure: most payments landed in a vague
      // category and the user hasn't categorised them themselves.
      final unclear = list.where(
        (t) => !t.userCategorized && unclearCategories.contains(t.category),
      );
      if (unclear.length * 2 < list.length) return;
      list.sort((a, b) => a.date.compareTo(b.date));
      final amounts = list.map((t) => t.amount);
      out.add(
        MerchantSuggestion(
          key: key,
          label: list.last.counterparty.trim(),
          count: list.length,
          total: amounts.fold(0.0, (a, b) => a + b),
          minAmount: amounts.reduce((a, b) => a < b ? a : b),
          maxAmount: amounts.reduce((a, b) => a > b ? a : b),
          days: list.last.date.difference(list.first.date).inDays + 1,
        ),
      );
    });
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  /// Saves what a merchant is and recategorises its payments that the user
  /// hasn't categorised by hand. Returns how many payments changed.
  int setMerchantCategory(
    String counterparty,
    String category, {
    String? alias,
    bool? isPerson,
  }) {
    final key = merchantKey(counterparty);
    final rule = merchants.putIfAbsent(key, () => MerchantRule(key: key));
    rule.category = category;
    if (alias != null) rule.alias = alias.trim();
    if (isPerson != null) rule.isPerson = isPerson;
    rule.askAfter = null;
    _touchMerchant(rule);
    var changed = 0;
    for (final t in txns) {
      if (t.type != TxnType.debit || t.userCategorized) continue;
      if (merchantKey(t.counterparty) != key || t.category == category) {
        continue;
      }
      t.category = category;
      _touchTxn(t);
      changed++;
    }
    _changed();
    return changed;
  }

  void setMerchantAlias(String counterparty, String alias) {
    final key = merchantKey(counterparty);
    final rule = merchants.putIfAbsent(key, () => MerchantRule(key: key));
    rule.alias = alias.trim();
    _touchMerchant(rule);
    _changed();
  }

  void snoozeMerchant(String counterparty, {Duration? forHow}) {
    final key = merchantKey(counterparty);
    final rule = merchants.putIfAbsent(key, () => MerchantRule(key: key));
    rule.askAfter = DateTime.now().add(forHow ?? const Duration(days: 7));
    _touchMerchant(rule);
    _changed();
  }

  void neverAskMerchant(String counterparty) {
    final key = merchantKey(counterparty);
    final rule = merchants.putIfAbsent(key, () => MerchantRule(key: key));
    rule.neverAsk = true;
    _touchMerchant(rule);
    _changed();
  }

  /// The user picked a category for one payment by hand: remember it for
  /// that merchant and apply it to the merchant's other auto-categorised
  /// payments. Returns how many other payments changed.
  int recategorize(Txn t, String category) {
    t.category = category;
    t.userCategorized = true;
    _touchTxn(t);
    if (t.type == TxnType.debit && t.counterparty.trim().isNotEmpty) {
      return setMerchantCategory(t.counterparty, category);
    }
    _changed();
    return 0;
  }

  void addTxn(Txn t) {
    txns.add(t);
    _touchTxn(t);
    _changed();
  }

  /// Call after changing fields of [t] directly.
  void updateTxn(Txn t) {
    _touchTxn(t);
    _changed();
  }

  void deleteTxn(Txn t) {
    txns.remove(t);
    _bury(SyncKind.txn, t.id);
    for (final r in reminders.where((r) => r.txnId == t.id).toList()) {
      reminders.remove(r);
      _bury(SyncKind.reminder, r.id);
    }
    _changed();
  }

  void setSettled(Txn t, bool settled) {
    t.settled = settled;
    _touchTxn(t);
    for (final r in reminders) {
      if (r.txnId == t.id) {
        r.done = settled;
        _touchReminder(r);
      }
    }
    _changed();
  }

  // ------------------------------------------------------------- reminders

  void addReminder(Reminder r) {
    reminders.add(r);
    _touchReminder(r);
    _changed();
  }

  void toggleReminder(Reminder r) {
    r.done = !r.done;
    _touchReminder(r);
    _changed();
  }

  void deleteReminder(Reminder r) {
    reminders.remove(r);
    _bury(SyncKind.reminder, r.id);
    _changed();
  }

  List<Reminder> get pendingReminders =>
      reminders.where((r) => !r.done).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  // ------------------------------------------------------------------ chat

  // Chat history stays on this device (it is not synced).
  void addChat(ChatMessage m) {
    chat.add(m);
    _changed(local: false);
  }

  void clearChat() {
    chat.clear();
    _changed(local: false);
  }

  // ------------------------------------------------------------------ sync

  /// Records waiting to be uploaded.
  List<SyncRecord> pendingRecords() {
    final out = <SyncRecord>[];
    for (final a in accounts) {
      if (dirty.contains(syncKey(SyncKind.account, a.id))) {
        out.add(SyncRecord(SyncKind.account, a.id, a.toJson(), a.updatedAt));
      }
    }
    for (final t in txns) {
      if (dirty.contains(syncKey(SyncKind.txn, t.id))) {
        out.add(SyncRecord(SyncKind.txn, t.id, t.toJson(), t.updatedAt));
      }
    }
    for (final r in reminders) {
      if (dirty.contains(syncKey(SyncKind.reminder, r.id))) {
        out.add(SyncRecord(SyncKind.reminder, r.id, r.toJson(), r.updatedAt));
      }
    }
    for (final m in merchants.values) {
      if (dirty.contains(syncKey(SyncKind.merchant, m.key))) {
        out.add(SyncRecord(SyncKind.merchant, m.key, m.toJson(), m.updatedAt));
      }
    }
    tombstones.forEach((key, when) {
      final (kind, id) = parseSyncKey(key);
      if (kind != null) out.add(SyncRecord(kind, id, null, when));
    });
    return out;
  }

  /// Marks records as uploaded, unless they changed again meanwhile.
  void markUploaded(List<SyncRecord> sent) {
    for (final r in sent) {
      final key = syncKey(r.kind, r.id);
      if (r.deleted) {
        if (tombstones[key] == r.updatedAt) tombstones.remove(key);
      } else if (_localUpdatedAt(r.kind, r.id) == r.updatedAt) {
        dirty.remove(key);
      }
    }
    _changed(local: false);
  }

  DateTime? _localUpdatedAt(SyncKind kind, String id) => switch (kind) {
    SyncKind.account => accountById(id)?.updatedAt,
    SyncKind.txn => txnById(id)?.updatedAt,
    SyncKind.reminder => _reminderById(id)?.updatedAt,
    SyncKind.merchant => merchants[id]?.updatedAt,
  };

  Reminder? _reminderById(String id) {
    for (final r in reminders) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Applies downloaded records. The newest edit wins.
  void applyRemote(List<SyncRecord> records, String? newCursor) {
    for (final r in records) {
      final key = syncKey(r.kind, r.id);
      final local = _localUpdatedAt(r.kind, r.id);
      final buried = tombstones[key];
      // Ignore anything older than what we have (or deleted) locally.
      if (local != null && !r.updatedAt.isAfter(local)) continue;
      if (buried != null && !r.updatedAt.isAfter(buried)) continue;
      tombstones.remove(key);
      dirty.remove(key);
      _removeLocal(r.kind, r.id);
      if (r.deleted || r.data == null) continue;
      try {
        switch (r.kind) {
          case SyncKind.account:
            accounts.add(Account.fromJson(r.data!)..updatedAt = r.updatedAt);
          case SyncKind.txn:
            txns.add(Txn.fromJson(r.data!)..updatedAt = r.updatedAt);
          case SyncKind.reminder:
            reminders.add(Reminder.fromJson(r.data!)..updatedAt = r.updatedAt);
          case SyncKind.merchant:
            final m = MerchantRule.fromJson(r.data!)..updatedAt = r.updatedAt;
            merchants[m.key] = m;
        }
      } catch (e) {
        debugPrint('Skipping bad record $key: $e');
      }
    }
    if (newCursor != null) syncCursor = newCursor;
    _changed(local: false);
  }

  void _removeLocal(SyncKind kind, String id) {
    switch (kind) {
      case SyncKind.account:
        accounts.removeWhere((a) => a.id == id);
      case SyncKind.txn:
        txns.removeWhere((t) => t.id == id);
      case SyncKind.reminder:
        reminders.removeWhere((r) => r.id == id);
      case SyncKind.merchant:
        merchants.remove(id);
    }
  }

  /// Links local data to a signed-in user. Data created before signing in
  /// is uploaded to the new account; data from a different user is wiped.
  void attachUser(String userId) {
    if (ownerId == userId) return;
    if (ownerId != null) {
      clearAll();
    } else {
      for (final a in accounts) {
        dirty.add(syncKey(SyncKind.account, a.id));
      }
      for (final t in txns) {
        dirty.add(syncKey(SyncKind.txn, t.id));
      }
      for (final r in reminders) {
        dirty.add(syncKey(SyncKind.reminder, r.id));
      }
      for (final m in merchants.values) {
        dirty.add(syncKey(SyncKind.merchant, m.key));
      }
    }
    ownerId = userId;
    syncCursor = null;
    _changed(local: false);
  }

  /// Removes everything from this device (used on sign-out).
  void clearAll() {
    accounts.clear();
    txns.clear();
    reminders.clear();
    chat.clear();
    merchants.clear();
    dirty.clear();
    tombstones.clear();
    syncCursor = null;
    ownerId = null;
    _changed(local: false);
  }

  // ----------------------------------------------------------------- stats

  // Totals work on any [Period]; the month versions are shortcuts.

  Iterable<Txn> txnsIn(Period p) => txns.where((t) => p.contains(t.date));

  Iterable<Txn> txnsInMonth(DateTime month) => txnsIn(Period.month(month));

  /// Whether a debit counts as spending. Card-bill payments don't (the
  /// purchases were counted on the card) and neither do SIPs/investments
  /// (that money is saved; see [investedDuring]).
  static bool isSpending(Txn t) =>
      t.type == TxnType.debit &&
      t.category != cardBillCategory &&
      !investmentCategories.contains(t.category);

  static bool isInvestment(Txn t) =>
      t.type == TxnType.debit && investmentCategories.contains(t.category);

  static double _sum(Iterable<Txn> ts) => ts.fold(0.0, (s, t) => s + t.amount);

  double spentDuring(Period p) => _sum(txnsIn(p).where(isSpending));
  double receivedDuring(Period p) =>
      _sum(txnsIn(p).where((t) => t.type == TxnType.credit));
  double investedDuring(Period p) => _sum(txnsIn(p).where(isInvestment));

  double spentIn(DateTime month) => spentDuring(Period.month(month));
  double receivedIn(DateTime month) => receivedDuring(Period.month(month));
  double investedIn(DateTime month) => investedDuring(Period.month(month));

  /// Investments (SIP, FD, RD, stocks, bonds, other) in [p], newest first.
  List<Txn> investmentsDuring(Period p) =>
      txnsIn(p).where(isInvestment).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  List<Txn> investmentsInYear(int year) =>
      investmentsDuring(Period.custom(DateTime(year), DateTime(year, 12, 31)));

  /// SIP payments in [year], newest first.
  List<Txn> sipsInYear(int year) =>
      investmentsInYear(year).where((t) => t.category == sipCategory).toList();

  List<CategoryTotal> categoryTotalsDuring(Period p, TxnType type) {
    final map = <String, double>{};
    for (final t in txnsIn(p).where((t) => t.type == type)) {
      // Card bills and investments aren't spending.
      if (type == TxnType.debit && !isSpending(t)) continue;
      map[t.category] = (map[t.category] ?? 0) + t.amount;
    }
    final list = map.entries.map((e) => CategoryTotal(e.key, e.value)).toList();
    list.sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  List<CategoryTotal> categoryTotals(DateTime month, TxnType type) =>
      categoryTotalsDuring(Period.month(month), type);

  double accountSpentDuring(Account a, Period p) =>
      _sum(txnsIn(p).where((t) => t.accountId == a.id && isSpending(t)));

  double accountSpentIn(Account a, DateTime month) =>
      accountSpentDuring(a, Period.month(month));

  static const _fundNames = {
    'parag parikh': 'Parag Parikh MF',
    'ppfas': 'Parag Parikh MF',
    'zerodha coin': 'Zerodha Coin',
    'coin by zerodha': 'Zerodha Coin',
    'iccl': 'Zerodha Coin',
    'bse star': 'BSE StAR MF',
    'bsestarmf': 'BSE StAR MF',
    'bse limited': 'BSE StAR MF',
    'bse ltd': 'BSE StAR MF',
    'groww': 'Groww',
    'kuvera': 'Kuvera',
    'paytm money': 'Paytm Money',
    'et money': 'ET Money',
    'etmoney': 'ET Money',
    'scripbox': 'Scripbox',
    'sbi mf': 'SBI MF',
    'sbi mutual': 'SBI MF',
    'hdfc mf': 'HDFC MF',
    'hdfc mutual': 'HDFC MF',
    'icici pru': 'ICICI Prudential MF',
    'axis mf': 'Axis MF',
    'axis mutual': 'Axis MF',
    'nippon': 'Nippon India MF',
    'mirae': 'Mirae Asset MF',
    'kotak mf': 'Kotak MF',
    'kotak mutual': 'Kotak MF',
    'uti mf': 'UTI MF',
    'uti mutual': 'UTI MF',
    'quant mf': 'Quant MF',
    'aditya birla sun life': 'Aditya Birla Sun Life MF',
    'dsp mf': 'DSP MF',
    'tata mf': 'Tata MF',
    'franklin templeton': 'Franklin Templeton MF',
    'motilal oswal': 'Motilal Oswal MF',
    'edelweiss': 'Edelweiss MF',
    'canara robeco': 'Canara Robeco MF',
    'sundaram': 'Sundaram MF',
    'invesco': 'Invesco MF',
    'bandhan': 'Bandhan MF',
    'cams': 'CAMS',
    'kfin': 'KFintech',
  };

  /// A readable name for a SIP's fund or platform, for grouping.
  String sipFundName(Txn t) {
    final alias = merchantRule(t.counterparty)?.alias ?? '';
    if (alias.isNotEmpty) return alias;
    final text = '${t.counterparty} ${t.rawMessage} ${t.note}'.toLowerCase();
    for (final e in _fundNames.entries) {
      if (text.contains(e.key)) return e.value;
    }
    return t.counterparty.trim().isEmpty ? 'Other SIPs' : t.counterparty;
  }

  /// Outstanding lend/borrow per person (case-insensitive names).
  List<PersonBalance> personBalances() {
    final map = <String, double>{};
    final display = <String, String>{};
    for (final t in txns) {
      if (t.settled) continue;
      if (t.type != TxnType.lend && t.type != TxnType.borrow) continue;
      final key = t.counterparty.trim().toLowerCase();
      display.putIfAbsent(key, () => t.counterparty.trim());
      final sign = t.type == TxnType.lend ? 1 : -1;
      map[key] = (map[key] ?? 0) + sign * t.amount;
    }
    final list = map.entries
        .where((e) => e.value.abs() > 0.001)
        .map((e) => PersonBalance(display[e.key]!, e.value))
        .toList();
    list.sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
    return list;
  }

  double get totalToReceive => personBalances()
      .where((p) => p.amount > 0)
      .fold(0.0, (s, p) => s + p.amount);

  double get totalToPay => personBalances()
      .where((p) => p.amount < 0)
      .fold(0.0, (s, p) => s - p.amount);
}
