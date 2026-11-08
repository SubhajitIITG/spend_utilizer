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

enum ChatFlow {
  none,
  debit,
  credit,
  lend,
  borrow,
  reminder,

  /// Bot-initiated: "you pay X regularly, what is it?"
  merchant,

  /// Bot-initiated: "is this account / card yours?"
  ownership,
}

enum InputKind { text, amount, date }

extension ChatFlowX on ChatFlow {
  String get label => switch (this) {
    ChatFlow.none => 'Paste SMS',
    ChatFlow.debit => 'Debit',
    ChatFlow.credit => 'Credit',
    ChatFlow.lend => 'Lend',
    ChatFlow.borrow => 'Borrow',
    ChatFlow.reminder => 'Reminder',
    ChatFlow.merchant => 'Regular payment',
    ChatFlow.ownership => 'Account check',
  };
  String get emoji => switch (this) {
    ChatFlow.none => '📋',
    ChatFlow.debit => '➖',
    ChatFlow.credit => '➕',
    ChatFlow.lend => '🤝',
    ChatFlow.borrow => '🙏',
    ChatFlow.reminder => '⏰',
    ChatFlow.merchant => '🔎',
    ChatFlow.ownership => '🏦',
  };
}

enum _Step {
  amount,
  txnDate,
  category,
  account,
  person,
  dueDate,
  note,
  title,
  merchantKind,
  merchantName,
  done,
}

const cancelOption = 'Cancel';
const skipOption = 'Skip';
const cashOption = 'Cash';
const personOption = '👤 A friend / person';
const askLaterOption = 'Ask me later';
const neverAskOption = 'Don\'t ask again';
const mineOption = '✅ Yes, it\'s mine';
const notMineOption = '❌ No, someone else\'s';

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
  DateTime? _when;
  MerchantSuggestion? _merchant;
  Account? _pendingAccount;
  bool _merchantIsPerson = false;

  /// Maps the account option labels shown to the user to account ids.
  final Map<String, String> _accountOptions = {};

  bool get active => flow != ChatFlow.none;

  /// True when asking when a transaction happened (date must be in the
  /// past), false for due dates / reminders (future).
  bool get askingPastDate => _step == _Step.txnDate;

  InputKind get inputKind => switch (_step) {
    _Step.amount => InputKind.amount,
    _Step.dueDate || _Step.txnDate => InputKind.date,
    _ => InputKind.text,
  };

  String get inputHint {
    if (!active) return 'Paste bank message(s) here…';
    if (flow == ChatFlow.ownership) return 'Tap Yes or No below';
    return switch (_step) {
      _Step.amount => 'Enter amount, e.g. 450',
      _Step.category => 'Pick a category or type one',
      _Step.account => 'Pick an account',
      _Step.person => 'Enter name',
      _Step.dueDate => 'dd-mm-yyyy or pick an option',
      _Step.txnDate => 'e.g. 5-11-2026, 5 Nov, yesterday',
      _Step.note => 'Add a note (optional)',
      _Step.title => 'What should I remind you about?',
      _Step.merchantKind => 'Pick what this is, or type a category',
      _Step.merchantName => 'e.g. Raju Tea Stall (optional)',
      _Step.done => '',
    };
  }

  /// Quick-reply chips for the current step.
  List<String> get options {
    if (!active) return const [];
    if (flow == ChatFlow.ownership) {
      return const [mineOption, notMineOption, cancelOption];
    }
    final List<String> opts = switch (_step) {
      _Step.category =>
        (flow == ChatFlow.credit ? creditCategories : debitCategories)
            .map((c) => '${c.emoji} ${c.name}')
            .toList(),
      _Step.account => [..._accountOptions.keys, skipOption],
      _Step.dueDate =>
        flow == ChatFlow.reminder
            ? ['Tomorrow', 'In 1 week', 'In 1 month']
            : ['In 1 week', 'In 1 month', 'No reminder'],
      _Step.txnDate => ['Today', 'Yesterday', '2 days ago'],
      _Step.note => [skipOption],
      _Step.person => _knownPeople(),
      _Step.merchantKind => [
        personOption,
        ...debitCategories
            .where(
              (c) =>
                  c.name != friendsCategory &&
                  !unclearCategories.contains(c.name),
            )
            .map((c) => '${c.emoji} ${c.name}'),
        askLaterOption,
        neverAskOption,
      ],
      _Step.merchantName => [skipOption],
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
      ChatFlow.debit => [
        _Step.amount,
        _Step.txnDate,
        _Step.category,
        _Step.account,
        _Step.note,
      ],
      ChatFlow.credit => [
        _Step.amount,
        _Step.txnDate,
        _Step.category,
        _Step.account,
        _Step.note,
      ],
      ChatFlow.lend => [
        _Step.person,
        _Step.amount,
        _Step.txnDate,
        _Step.account,
        _Step.dueDate,
        _Step.note,
      ],
      ChatFlow.borrow => [
        _Step.person,
        _Step.amount,
        _Step.txnDate,
        _Step.account,
        _Step.dueDate,
        _Step.note,
      ],
      ChatFlow.reminder => [_Step.title, _Step.amount, _Step.dueDate],
      ChatFlow.merchant => [_Step.merchantKind, _Step.merchantName],
      ChatFlow.ownership => [],
      ChatFlow.none => [],
    };
    if (_steps.isEmpty) return [];
    _step = _steps.first;
    return [_bot(_question())];
  }

  void cancel() => _reset();

  /// Starts asking about a regularly-paid merchant.
  List<ChatMessage> reviewMerchant(MerchantSuggestion m) {
    _reset();
    flow = ChatFlow.merchant;
    _merchant = m;
    _steps = [_Step.merchantKind, _Step.merchantName];
    _step = _steps.first;
    return [_bot(_question())];
  }

  /// After an app restart: if the last chat message is an unanswered
  /// question about a merchant, pick that question up again.
  void resumePendingQuestion() {
    if (active || store.chat.isEmpty) return;
    final last = store.chat.last;
    if (last.fromUser) return;
    if (last.text.startsWith('🏦')) {
      for (final a in store.pendingAccounts) {
        if (last.text.contains(a.displayName)) {
          flow = ChatFlow.ownership;
          _pendingAccount = a;
          return;
        }
      }
      return;
    }
    if (!last.text.startsWith('🔎')) return;
    for (final m in store.merchantsToReview()) {
      if (last.text.contains('"${m.label}"')) {
        flow = ChatFlow.merchant;
        _merchant = m;
        _steps = [_Step.merchantKind, _Step.merchantName];
        _step = _steps.first;
        return;
      }
    }
  }

  /// Asks whether a newly found account/card belongs to the user.
  List<ChatMessage> reviewAccount(Account a) {
    _reset();
    flow = ChatFlow.ownership;
    _pendingAccount = a;
    final what = a.type.label.toLowerCase();
    return [
      _bot(
        '🏦 This message mentions a $what I haven\'t seen before: '
        '${a.displayName}.\n\nIs this your own $what? I keep only your '
        'accounts and cards in Accounts. If it belongs to someone else, I\'ll '
        'treat it as a payee (it stays in History).',
      ),
    ];
  }

  /// Asks the next open question, if any: first unconfirmed accounts,
  /// then regularly-paid merchants we can't categorise.
  List<ChatMessage> _maybeAskNext() {
    if (active) return const [];
    final pending = store.pendingAccounts;
    if (pending.isNotEmpty) return reviewAccount(pending.first);
    final list = store.merchantsToReview();
    return list.isEmpty ? const [] : reviewMerchant(list.first);
  }

  /// Handles whatever the user typed or tapped.
  List<ChatMessage> handle(String input) {
    final text = input.trim();
    if (text.isEmpty) return [];
    if (!active) return _handleFreeText(text);
    // A pasted bank SMS is always a new transaction, even mid-question:
    // drop the open question (it will be asked again if still relevant).
    if (text.length > 30 && SmsParser.parse(text) != null) {
      _reset();
      return _handleFreeText(text);
    }
    if (text == cancelOption) {
      // Don't re-ask about the same merchant on the very next paste.
      if (flow == ChatFlow.merchant) {
        store.snoozeMerchant(_merchant!.label, forHow: const Duration(days: 1));
      }
      _reset();
      return [_bot('Cancelled. Paste a bank message or pick an option below.')];
    }
    if (flow == ChatFlow.ownership) {
      final a = _pendingAccount!;
      final yes =
          text == mineOption ||
          RegExp(r'^(y|yes|mine)\b', caseSensitive: false).hasMatch(text);
      final no =
          text == notMineOption ||
          RegExp(r'^(n|no|not)\b', caseSensitive: false).hasMatch(text);
      if (yes == no) {
        return [_bot('Please tap "Yes, it\'s mine" or "No, someone else\'s".')];
      }
      store.setOwnership(a, yes ? Ownership.mine : Ownership.notMine);
      _reset();
      return [
        _bot(
          yes
              ? '👍 Added ${a.displayName} to your accounts. You can rename '
                    'it in Accounts.'
              : '👌 Got it, A/c ••${a.last4} isn\'t yours. Payments to it '
                    'stay in History under Payees, but it won\'t appear in '
                    'your accounts.',
        ),
        ..._maybeAskNext(),
      ];
    }
    if (flow == ChatFlow.merchant &&
        (text == askLaterOption || text == neverAskOption)) {
      final label = _merchant!.label;
      if (text == askLaterOption) {
        store.snoozeMerchant(label);
      } else {
        store.neverAskMerchant(label);
      }
      _reset();
      return [
        _bot(
          text == askLaterOption
              ? 'Sure, I\'ll ask about "$label" again in a week. 👍'
              : 'Okay, I won\'t ask about "$label" again. You can still '
                    'change categories from History.',
        ),
      ];
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
    _when = null;
    _merchant = null;
    _pendingAccount = null;
    _merchantIsPerson = false;
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
          ChatFlow.merchant || ChatFlow.ownership || ChatFlow.none => '',
        };
      case _Step.txnDate:
        return switch (flow) {
          ChatFlow.credit => 'When did you receive it? 📅',
          ChatFlow.lend => 'When did you lend it? 📅',
          ChatFlow.borrow => 'When did you borrow it? 📅',
          _ => 'When did you spend it? 📅',
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
      case _Step.merchantKind:
        final m = _merchant!;
        final range = m.minAmount == m.maxAmount
            ? '${money(m.minAmount)} each'
            : '${money(m.minAmount)}–${money(m.maxAmount)} each';
        return '🔎 I noticed you paid "${m.label}" ${m.count} times '
            'in the last ${m.days} day${m.days == 1 ? '' : 's'} '
            '($range, ${money(m.total)} in total), but I can\'t tell what '
            'it is.\n\nIs it a friend, or a shop / stall? Tell me once and '
            'I\'ll categorise these payments automatically from now on.';
      case _Step.merchantName:
        return _merchantIsPerson
            ? 'What\'s their name? (so it shows instead of '
                  '"${_merchant!.label}")'
            : 'Want to give it a name? e.g. "Raju Tea Stall" '
                  '(shows instead of "${_merchant!.label}")';
      case _Step.done:
        return '';
    }
  }

  void _buildAccountOptions() {
    _accountOptions.clear();
    for (final a in store.selectableAccounts) {
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
        final all = flow == ChatFlow.credit
            ? creditCategories
            : debitCategories;
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
      case _Step.txnDate:
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final d = text == '2 days ago'
            ? today.subtract(const Duration(days: 2))
            : parseUserDate(text);
        if (d == null) {
          return 'I couldn\'t read that date. Try 5-11-2026, 5 Nov or '
              'yesterday, or tap Pick date.';
        }
        if (d.isAfter(today)) {
          return 'That date is in the future. When did it actually happen?';
        }
        // Today keeps the current time; earlier days get no specific time.
        _when = d == today ? now : DateTime(d.year, d.month, d.day, 12);
        return null;
      case _Step.note:
        _note = text == skipOption ? '' : text;
        return null;
      case _Step.title:
        _title = text;
        return null;
      case _Step.merchantKind:
        if (text == personOption) {
          _merchantIsPerson = true;
          _category = friendsCategory;
          return null;
        }
        for (final c in debitCategories) {
          if (text == '${c.emoji} ${c.name}' ||
              text.toLowerCase() == c.name.toLowerCase()) {
            _category = c.name;
            return null;
          }
        }
        _category = text; // custom category
        return null;
      case _Step.merchantName:
        _title = text == skipOption ? '' : text;
        return null;
      case _Step.done:
        return null;
    }
  }

  List<ChatMessage> _finish() {
    final f = flow;
    final out = <ChatMessage>[];
    if (f == ChatFlow.merchant) {
      final m = _merchant!;
      final category = _category ?? 'Others';
      final changed = store.setMerchantCategory(
        m.label,
        category,
        alias: _title.isEmpty ? null : _title,
        isPerson: _merchantIsPerson,
      );
      final name = _title.isEmpty ? m.label : _title;
      out.add(
        _bot(
          '✅ Got it! "$name" is ${emojiFor(category)} $category. '
          'I updated $changed payment${changed == 1 ? '' : 's'}, and future '
          'payments to it will be categorised automatically.',
        ),
      );
      _reset();
      out.addAll(_maybeAskNext());
      return out;
    }
    if (f == ChatFlow.reminder) {
      final due = _due ?? DateTime.now().add(const Duration(days: 1));
      store.addReminder(
        Reminder(
          id: store.newId(),
          title: _title,
          amount: _amount,
          dueDate: due,
        ),
      );
      out.add(
        _bot(
          '⏰ Reminder set: "$_title"'
          '${_amount != null ? ' (${money(_amount!)})' : ''} on '
          '${formatDate(due)}.',
        ),
      );
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
      date: _when ?? DateTime.now(),
      dueDate: _due,
    );
    store.addTxn(t);

    if (_due != null && (type == TxnType.lend || type == TxnType.borrow)) {
      store.addReminder(
        Reminder(
          id: store.newId(),
          title: type == TxnType.lend
              ? 'Collect ${money(t.amount)} from $_person'
              : 'Repay ${money(t.amount)} to $_person',
          amount: t.amount,
          dueDate: _due!,
          txnId: t.id,
        ),
      );
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
          if (!r.dateFound) {
            msg +=
                '\n📅 No date in the message, so I used today. Tap '
                'Date to change it.';
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
        out.add(
          _bot(
            'I couldn\'t find a transaction in that message. 🤔\n'
            'Paste a bank/UPI SMS like:\n'
            '"Rs.250 debited from A/c XX1234 to VPA swiggy@axis…"\n'
            'or use the buttons below to add an entry manually.',
          ),
        );
      } else {
        out.add(_bot(bits.join(' · ')));
      }
    }
    if (added > 0) out.addAll(_maybeAskNext());
    return out;
  }
}

/// Human summary used in chat bubbles.
String describeTxn(AppStore store, Txn t) {
  final acc = store.accountById(t.accountId);
  final accLine = acc == null ? '' : '\n💳 ${acc.displayName}';
  final who = store.merchantLabel(t.counterparty);
  final when = '\n📅 ${formatTxnDate(t.date)}';
  return switch (t.type) {
    TxnType.debit =>
      '➖ Spent ${money(t.amount)}'
          '${who.isEmpty ? '' : ' at $who'}\n'
          '${emojiFor(t.category)} ${t.category}$accLine$when',
    TxnType.credit =>
      '➕ Received ${money(t.amount)}'
          '${who.isEmpty ? '' : ' from $who'}\n'
          '${emojiFor(t.category)} ${t.category}$accLine$when',
    TxnType.lend =>
      '🤝 Lent ${money(t.amount)} to $who$accLine$when'
          '${t.dueDate != null ? '\n⏰ Reminder on ${formatDate(t.dueDate!)}' : ''}',
    TxnType.borrow =>
      '🙏 Borrowed ${money(t.amount)} from $who$accLine$when'
          '${t.dueDate != null ? '\n⏰ Repay by ${formatDate(t.dueDate!)}' : ''}',
  };
}
