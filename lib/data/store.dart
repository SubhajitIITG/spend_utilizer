import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../services/sms_parser.dart';

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
    return _file = File('${dir.path}${Platform.pathSeparator}'
        'spend_utilizer_data.json');
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
  const SmsResult(this.status, {this.txn, this.account, this.newAccount = false});
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

class AppStore extends ChangeNotifier {
  final Storage storage;
  AppStore({Storage? storage}) : storage = storage ?? FileStorage();

  final List<Account> accounts = [];
  final List<Txn> txns = [];
  final List<Reminder> reminders = [];
  final List<ChatMessage> chat = [];
  bool loaded = false;

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
        accounts.addAll((j['accounts'] as List? ?? [])
            .map((e) => Account.fromJson(e as Map<String, dynamic>)));
        txns.addAll((j['txns'] as List? ?? [])
            .map((e) => Txn.fromJson(e as Map<String, dynamic>)));
        reminders.addAll((j['reminders'] as List? ?? [])
            .map((e) => Reminder.fromJson(e as Map<String, dynamic>)));
        chat.addAll((j['chat'] as List? ?? [])
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('Failed to load data: $e');
    }
    loaded = true;
    notifyListeners();
  }

  Timer? _saveTimer;

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), saveNow);
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

  List<String> get banks {
    final set = <String>{};
    for (final a in accounts) {
      if (a.type != AccountType.cash) set.add(a.bank);
    }
    return set.toList()..sort();
  }

  int get cardCount => accounts.where((a) => a.type.isCard).length;
  int get bankAccountCount =>
      accounts.where((a) => a.type == AccountType.savings).length;

  // -------------------------------------------------------------- accounts

  /// Finds the account matching (bank, type, last4), creating it if new.
  (Account, bool) findOrCreateAccount(
      String bank, AccountType type, String last4) {
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
    final created =
        Account(id: newId(), bank: bank, type: type, last4: last4);
    accounts.add(created);
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

  void addAccount(Account a) {
    accounts.add(a);
    _changed();
  }

  void updateAccount(Account a,
      {String? bank, String? nickname, AccountType? type, String? last4}) {
    if (bank != null) a.bank = bank.trim();
    if (nickname != null) a.nickname = nickname.trim();
    if (type != null) a.type = type;
    if (last4 != null) a.last4 = last4.trim();
    _changed();
  }

  /// Renames a bank across all its accounts, e.g. "Unknown Bank" → "Jana".
  void renameBank(String oldName, String newName) {
    for (final a in accounts) {
      if (a.bank == oldName) a.bank = newName.trim();
    }
    _changed();
  }

  void deleteAccount(Account a) {
    accounts.remove(a);
    for (final t in txns) {
      if (t.accountId == a.id) t.accountId = null;
    }
    _changed();
  }

  // ---------------------------------------------------------- transactions

  bool _isDuplicate(ParsedSms p, String raw) {
    final norm = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final t in txns) {
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
    final (account, isNew) =
        findOrCreateAccount(p.bank, p.accountType, p.last4);
    final t = Txn(
      id: newId(),
      type: p.type,
      amount: p.amount,
      category: p.category,
      accountId: account.id,
      counterparty: p.counterparty,
      date: p.date,
      source: 'sms',
      rawMessage: raw.trim(),
      refNo: p.refNo,
    );
    txns.add(t);
    _changed();
    return SmsResult(SmsStatus.added,
        txn: t, account: account, newAccount: isNew);
  }

  void addTxn(Txn t) {
    txns.add(t);
    _changed();
  }

  void updateTxn(Txn t) => _changed();

  void deleteTxn(Txn t) {
    txns.remove(t);
    reminders.removeWhere((r) => r.txnId == t.id);
    _changed();
  }

  void setSettled(Txn t, bool settled) {
    t.settled = settled;
    for (final r in reminders) {
      if (r.txnId == t.id) r.done = settled;
    }
    _changed();
  }

  // ------------------------------------------------------------- reminders

  void addReminder(Reminder r) {
    reminders.add(r);
    _changed();
  }

  void toggleReminder(Reminder r) {
    r.done = !r.done;
    _changed();
  }

  void deleteReminder(Reminder r) {
    reminders.remove(r);
    _changed();
  }

  List<Reminder> get pendingReminders =>
      reminders.where((r) => !r.done).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  // ------------------------------------------------------------------ chat

  void addChat(ChatMessage m) {
    chat.add(m);
    _changed();
  }

  void clearChat() {
    chat.clear();
    _changed();
  }

  // ----------------------------------------------------------------- stats

  bool _inMonth(DateTime d, DateTime month) =>
      d.year == month.year && d.month == month.month;

  Iterable<Txn> txnsInMonth(DateTime month) =>
      txns.where((t) => _inMonth(t.date, month));

  double spentIn(DateTime month) => txnsInMonth(month)
      .where((t) => t.type == TxnType.debit)
      .fold(0.0, (s, t) => s + t.amount);

  double receivedIn(DateTime month) => txnsInMonth(month)
      .where((t) => t.type == TxnType.credit)
      .fold(0.0, (s, t) => s + t.amount);

  List<CategoryTotal> categoryTotals(DateTime month, TxnType type) {
    final map = <String, double>{};
    for (final t in txnsInMonth(month).where((t) => t.type == type)) {
      map[t.category] = (map[t.category] ?? 0) + t.amount;
    }
    final list =
        map.entries.map((e) => CategoryTotal(e.key, e.value)).toList();
    list.sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  double accountSpentIn(Account a, DateTime month) => txnsInMonth(month)
      .where((t) => t.accountId == a.id && t.type == TxnType.debit)
      .fold(0.0, (s, t) => s + t.amount);

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
