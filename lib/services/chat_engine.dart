// The conversation logic behind the chat screen. Pure Dart (no widgets)
// so it can be unit-tested.
//
// Two ways to add data:
//  * Paste one or more bank messages → parsed automatically.
//  * Pick a quick action (Debit, Credit, Lend, Borrow, Reminder) → the bot
//    asks a few short questions, one at a time.

import '../data/store.dart';
import '../models/models.dart';
import '../util/format.dart';
import 'categories.dart';
import 'sms_parser.dart';

enum ChatFlow { none, debit, credit, lend, borrow, reminder }

enum InputKind { text, amount, date }

extension ChatFlowX on ChatFlow {
  String get label => switch (this) {
        ChatFlow.none => 'Paste SMS',
        ChatFlow.debit => 'Debit',
        ChatFlow.credit => 'Credit',
        ChatFlow.lend => 'Lend',
        ChatFlow.borrow => 'Borrow',
        ChatFlow.reminder => 'Reminder',
      };
  String get emoji => switch (this) {
        ChatFlow.none => '📋',
        ChatFlow.debit => '➖',
        ChatFlow.credit => '➕',
        ChatFlow.lend => '🤝',
        ChatFlow.borrow => '🙏',
        ChatFlow.reminder => '⏰',
      };
}

enum _Step { amount, category, account, person, dueDate, note, title, done }

const cancelOption = 'Cancel';
const skipOption = 'Skip';
const cashOption = 'Cash';

class ChatEngine {
  final AppStore store;
  ChatEngine(this.store);

  ChatFlow flow = ChatFlow.none;
  _Step _step = _Step.done;
  List<_Step> _steps = [];

  // Draft values for the current flow.
  double? _amount;
  String? _category;
  String? _accountId;
  String _person = '';
  String _note = '';
  String _title = '';
  DateTime? _due;

  /// Maps the account option labels shown to the user to account ids.
  final Map<String, String> _accountOptions = {};

  bool get active => flow != ChatFlow.none;

  InputKind get inputKind => switch (_step) {
        _Step.amount => InputKind.amount,
        _Step.dueDate => InputKind.date,
        _ => InputKind.text,
      };

  String get inputHint {
    if (!active) return 'Paste bank message(s) here…';
    return switch (_step) {
      _Step.amount => 'Enter amount, e.g. 450',
      _Step.category => 'Pick a category or type one',
      _Step.account => 'Pick an account',
      _Step.person => 'Enter name',
      _Step.dueDate => 'dd-mm-yyyy or pick an option',
      _Step.note => 'Add a note (optional)',
      _Step.title => 'What should I remind you about?',
      _Step.done => '',
    };
  }

  /// Quick-reply chips for the current step.
  List<String> get options {
    if (!active) return const [];
    final List<String> opts = switch (_step) {
      _Step.category => (flow == ChatFlow.credit
              ? creditCategories
              : debitCategories)
          .map((c) => '${c.emoji} ${c.name}')
          .toList(),
      _Step.account => [..._accountOptions.keys, skipOption],
      _Step.dueDate => flow == ChatFlow.reminder
          ? ['Tomorrow', 'In 1 week', 'In 1 month']
          : ['In 1 week', 'In 1 month', 'No reminder'],
      _Step.note => [skipOption],
      _Step.person => _knownPeople(),
      _ => <String>[],
    };
    return [...opts, cancelOption];
  }

  List<String> _knownPeople() {
    final seen = <String>{};
    final out = <String>[];
    for (final t in store.txns.reversed) {
      if (t.type != TxnType.lend && t.type != TxnType.borrow) continue;
      final n = t.counterparty.trim();
      if (n.isNotEmpty && seen.add(n.toLowerCase())) out.add(n);
      if (out.length >= 6) break;
    }
    return out;
  }

  // ------------------------------------------------------------------ API

  /// Starts a guided flow. Returns the bot's first question.
  List<ChatMessage> start(ChatFlow f) {
    _reset();
    flow = f;
    _steps = switch (f) {
      ChatFlow.debit => [_Step.amount, _Step.category, _Step.account, _Step.note],
      ChatFlow.credit => [_Step.amount, _Step.category, _Step.account, _Step.note],
      ChatFlow.lend => [_Step.person, _Step.amount, _Step.account, _Step.dueDate, _Step.note],
      ChatFlow.borrow => [_Step.person, _Step.amount, _Step.account, _Step.dueDate, _Step.note],
      ChatFlow.reminder => [_Step.title, _Step.amount, _Step.dueDate],
      ChatFlow.none => [],
    };
    if (_steps.isEmpty) return [];
    _step = _steps.first;
    return [_bot(_question())];
  }

  void cancel() => _reset();

  /// Handles whatever the user typed or tapped.
  List<ChatMessage> handle(String input) {
    final text = input.trim();
    if (text.isEmpty) return [];
    if (!active) return _handleFreeText(text);
    if (text == cancelOption) {
      _reset();
      return [_bot('Cancelled. Paste a bank message or pick an option below.')];
    }
    final error = _accept(text);
    if (error != null) return [_bot(error)];
    final idx = _steps.indexOf(_step);
    if (idx + 1 < _steps.length) {
      _step = _steps[idx + 1];
      return [_bot(_question())];
    }
    return _finish();
  }

  // ------------------------------------------------------------- internals

  void _reset() {
    flow = ChatFlow.none;
    _step = _Step.done;
    _steps = [];
    _amount = null;
    _category = null;
    _accountId = null;
    _person = '';
    _note = '';
    _title = '';
    _due = null;
    _accountOptions.clear();
  }

  ChatMessage _bot(String text, {String? txnId}) => ChatMessage(
        id: store.newId(),
        fromUser: false,
        text: text,
        time: DateTime.now(),
        txnId: txnId,
      );

  String _question() {
    switch (_step) {
      case _Step.amount:
        return switch (flow) {
          ChatFlow.debit => 'How much did you spend? 💸',
          ChatFlow.credit => 'How much did you receive? 💰',
          ChatFlow.lend => 'How much did you lend to $_person?',
          ChatFlow.borrow => 'How much did you borrow from $_person?',
          ChatFlow.reminder => 'Amount involved? (tap Skip if none)',
          ChatFlow.none => '',
        };
      case _Step.category:
        return flow == ChatFlow.credit
            ? 'What kind of money is this?'
            : 'Where did you spend it?';
      case _Step.account:
        _buildAccountOptions();
        return switch (flow) {
          ChatFlow.credit => 'Which account received it?',
          ChatFlow.borrow => 'Which account did the money come into?',
          _ => 'Paid from which account or card?',
        };
      case _Step.person:
        return flow == ChatFlow.lend
            ? 'Who did you lend money to? 🤝'
            : 'Who did you borrow money from? 🙏';
      case _Step.dueDate:
        return flow == ChatFlow.reminder
            ? 'When should I remind you?'
            : flow == ChatFlow.lend
                ? 'When should $_person return it? I\'ll remind you.'
                : 'When do you need to repay $_person? I\'ll remind you.';
      case _Step.note:
        return 'Any note? (optional)';
      case _Step.title:
        return 'What should I remind you about? ⏰';
      case _Step.done:
        return '';
    }
  }

  void _buildAccountOptions() {
    _accountOptions.clear();
    for (final a in store.accounts) {
      if (a.type == AccountType.cash) continue;
      _accountOptions[a.displayName] = a.id;
    }
    _accountOptions[cashOption] = '';
  }

  /// Validates and stores input for the current step. Returns an error
  /// message to show, or null if accepted.
  String? _accept(String text) {
    switch (_step) {
      case _Step.amount:
        if (flow == ChatFlow.reminder && text == skipOption) return null;
        final v = parseAmount(text);
        if (v == null || v <= 0) {
          return 'Please enter a valid amount, like 250 or 1,499.50';
        }
        _amount = v;
        return null;
      case _Step.category:
        // Accept "🛒 Groceries" chips or typed names.
        final all = flow == ChatFlow.credit ? creditCategories : debitCategories;
        for (final c in all) {
          if (text == '${c.emoji} ${c.name}' ||
              text.toLowerCase() == c.name.toLowerCase()) {
            _category = c.name;
            return null;
          }
        }
        _category = text; // custom category
        return null;
      case _Step.account:
        if (text == skipOption) {
          _accountId = null;
        } else if (text == cashOption) {
          _accountId = store.cashAccount().id;
        } else if (_accountOptions.containsKey(text)) {
          _accountId = _accountOptions[text];
        } else {
          return 'Please pick one of the accounts below, or tap Skip.';
        }
        return null;
      case _Step.person:
        _person = text;
        return null;
      case _Step.dueDate:
        if (text == 'No reminder') {
          _due = null;
          return null;
        }
        final now = DateTime.now();
        final d = switch (text) {
          'Tomorrow' => now.add(const Duration(days: 1)),
          'In 1 week' => now.add(const Duration(days: 7)),
          'In 1 month' => DateTime(now.year, now.month + 1, now.day),
          _ => parseUserDate(text),
        };
        if (d == null) {
          return 'I couldn\'t read that date. Use dd-mm-yyyy, e.g. 25-12-2026.';
        }
        _due = DateTime(d.year, d.month, d.day, 9);
        return null;
      case _Step.note:
        _note = text == skipOption ? '' : text;
        return null;
      case _Step.title:
        _title = text;
        return null;
      case _Step.done:
        return null;
    }
  }

  List<ChatMessage> _finish() {
    final f = flow;
    final out = <ChatMessage>[];
    if (f == ChatFlow.reminder) {
      final due = _due ?? DateTime.now().add(const Duration(days: 1));
      store.addReminder(Reminder(
        id: store.newId(),
        title: _title,
        amount: _amount,
        dueDate: due,
      ));
      out.add(_bot('⏰ Reminder set: "$_title"'
          '${_amount != null ? ' (${money(_amount!)})' : ''} on '
          '${formatDate(due)}.'));
      _reset();
      return out;
    }

    final type = switch (f) {
      ChatFlow.credit => TxnType.credit,
      ChatFlow.lend => TxnType.lend,
      ChatFlow.borrow => TxnType.borrow,
      _ => TxnType.debit,
    };
    final t = Txn(
      id: store.newId(),
      type: type,
      amount: _amount!,
      category: switch (type) {
        TxnType.lend => lendCategory,
        TxnType.borrow => borrowCategory,
        _ => _category ?? 'Others',
      },
      accountId: _accountId,
      counterparty: _person,
      note: _note,
      date: DateTime.now(),
      dueDate: _due,
    );
    store.addTxn(t);

    if (_due != null && (type == TxnType.lend || type == TxnType.borrow)) {
      store.addReminder(Reminder(
        id: store.newId(),
        title: type == TxnType.lend
            ? 'Collect ${money(t.amount)} from $_person'
            : 'Repay ${money(t.amount)} to $_person',
        amount: t.amount,
        dueDate: _due!,
        txnId: t.id,
      ));
    }
    out.add(_bot(describeTxn(store, t), txnId: t.id));
    _reset();
    return out;
  }

  List<ChatMessage> _handleFreeText(String text) {
    final parts = SmsParser.splitMessages(text);
    final out = <ChatMessage>[];
    var added = 0, dup = 0, failed = 0;
    for (final part in parts) {
      final r = store.addFromSms(part);
      switch (r.status) {
        case SmsStatus.added:
          added++;
          var msg = describeTxn(store, r.txn!);
          if (r.newAccount) {
            msg += '\n🆕 New ${r.account!.type.label.toLowerCase()} found: '
                '${r.account!.displayName}. You can rename it in Accounts.';
          }
          out.add(_bot(msg, txnId: r.txn!.id));
        case SmsStatus.duplicate:
          dup++;
        case SmsStatus.notTransaction:
          failed++;
      }
    }
    if (parts.length > 1 || added == 0) {
      final bits = <String>[
        if (added > 0) '✅ $added added',
        if (dup > 0) '♻️ $dup already recorded',
        if (failed > 0) '❓ $failed not understood',
      ];
      if (added == 0 && dup == 0) {
        out.add(_bot('I couldn\'t find a transaction in that message. 🤔\n'
            'Paste a bank/UPI SMS like:\n'
            '"Rs.250 debited from A/c XX1234 to VPA swiggy@axis…"\n'
            'or use the buttons below to add an entry manually.'));
      } else {
        out.add(_bot(bits.join(' · ')));
      }
    }
    return out;
  }
}

/// One-line human summary used in chat bubbles.
String describeTxn(AppStore store, Txn t) {
  final acc = store.accountById(t.accountId);
  final accText = acc == null ? '' : ' · ${acc.displayName}';
  final who = t.counterparty.isEmpty ? '' : t.counterparty;
  return switch (t.type) {
    TxnType.debit => '➖ Spent ${money(t.amount)}'
        '${who.isEmpty ? '' : ' at $who'}\n'
        '${emojiFor(t.category)} ${t.category}$accText · ${formatDate(t.date)}',
    TxnType.credit => '➕ Received ${money(t.amount)}'
        '${who.isEmpty ? '' : ' from $who'}\n'
        '${emojiFor(t.category)} ${t.category}$accText · ${formatDate(t.date)}',
    TxnType.lend => '🤝 Lent ${money(t.amount)} to $who$accText'
        '${t.dueDate != null ? '\n⏰ Reminder on ${formatDate(t.dueDate!)}' : ''}',
    TxnType.borrow => '🙏 Borrowed ${money(t.amount)} from $who$accText'
        '${t.dueDate != null ? '\n⏰ Repay by ${formatDate(t.dueDate!)}' : ''}',
  };
}
