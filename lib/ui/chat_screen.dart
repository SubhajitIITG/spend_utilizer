import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../services/categories.dart';
import '../services/chat_engine.dart';
import '../util/format.dart';
import 'profile_screen.dart';
import 'theme.dart';
import 'txn_editor.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  ChatEngine? _engine;

  ChatEngine get engine => _engine ??= ChatEngine(context.read<AppStore>());

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _post(List<ChatMessage> replies) {
    final store = context.read<AppStore>();
    for (final r in replies) {
      store.addChat(r);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final store = context.read<AppStore>();
    store.addChat(
      ChatMessage(
        id: store.newId(),
        fromUser: true,
        text: t,
        time: DateTime.now(),
      ),
    );
    _controller.clear();
    _post(engine.handle(t));
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard is empty. Copy a bank SMS first.'),
        ),
      );
      return;
    }
    if (engine.active) engine.cancel();
    _send(text);
  }

  void _startFlow(ChatFlow f) {
    final store = context.read<AppStore>();
    store.addChat(
      ChatMessage(
        id: store.newId(),
        fromUser: true,
        text: '${f.emoji} ${f.label}',
        time: DateTime.now(),
      ),
    );
    _post(engine.start(f));
    _focus.requestFocus();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final past = engine.askingPastDate;
    final d = await showDatePicker(
      context: context,
      initialDate: past ? now : now.add(const Duration(days: 7)),
      firstDate: past ? DateTime(2000) : now.subtract(const Duration(days: 1)),
      lastDate: past ? now : DateTime(now.year + 10),
    );
    if (d != null) _send('${d.day}-${d.month}-${d.year}');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final scheme = Theme.of(context).colorScheme;
    final messages = store.chat.reversed.toList();

    return Scaffold(
      appBar: royalAppBar(
        'Spend Utilizer',
        actions: [
          const SyncStatusButton(),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'clear') store.clearChat();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear chat history')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _Welcome(onPaste: _pasteFromClipboard)
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _Bubble(message: messages[i]),
                  ),
          ),
          _OptionsBar(
            engine: engine,
            onFlow: _startFlow,
            onOption: _send,
            onPaste: _pasteFromClipboard,
            onPickDate: _pickDate,
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: Royal.gold.withValues(alpha: 0.5)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Royal.deep.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Paste bank SMS from clipboard',
                      icon: Icon(
                        Icons.content_paste_rounded,
                        color: scheme.primary,
                      ),
                      onPressed: _pasteFromClipboard,
                    ),
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          // Enter sends on desktop; Shift+Enter adds a new line.
                          const SingleActivator(LogicalKeyboardKey.enter): () =>
                              _send(_controller.text),
                        },
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          keyboardType: engine.inputKind == InputKind.amount
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : TextInputType.multiline,
                          decoration: InputDecoration(
                            hintText: engine.inputHint,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(26),
                              borderSide: BorderSide(
                                color: Royal.gold.withValues(alpha: 0.45),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(26),
                              borderSide: BorderSide(
                                color: Royal.gold.withValues(alpha: 0.45),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(26),
                              borderSide: const BorderSide(
                                color: Royal.gold,
                                width: 1.6,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Send',
                      // Own Material so the gradient isn't hidden behind
                      // the input bar's background.
                      child: Material(
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: Ink(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            gradient: Royal.gradient,
                          ),
                          child: InkWell(
                            onTap: () => _send(_controller.text),
                            child: const Icon(
                              Icons.send_rounded,
                              color: Royal.goldLight,
                              semanticLabel: 'Send',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  final VoidCallback onPaste;
  const _Welcome({required this.onPaste});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const RoyalEmblem(size: 84),
              const SizedBox(height: 20),
              Text(
                'Track every rupee by chatting',
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(width: 60, height: 2, color: Royal.gold),
              const SizedBox(height: 12),
              Text(
                'Copy a bank or UPI SMS and paste it here. I\'ll find the '
                'amount, bank, card or account, merchant and category '
                'automatically. You can paste many messages at once '
                '(separate them with a blank line).\n\n'
                'Or use the buttons below to add a debit, credit, lend, '
                'borrow or reminder yourself.',
                style: t.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Paste SMS from clipboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionsBar extends StatelessWidget {
  final ChatEngine engine;
  final void Function(ChatFlow) onFlow;
  final void Function(String) onOption;
  final VoidCallback onPaste;
  final VoidCallback onPickDate;

  const _OptionsBar({
    required this.engine,
    required this.onFlow,
    required this.onOption,
    required this.onPaste,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (!engine.active) {
      chips.add(
        ActionChip(
          avatar: const Text('📋'),
          label: const Text('Paste SMS'),
          onPressed: onPaste,
        ),
      );
      for (final f in [
        ChatFlow.debit,
        ChatFlow.credit,
        ChatFlow.lend,
        ChatFlow.borrow,
        ChatFlow.reminder,
      ]) {
        chips.add(
          ActionChip(
            avatar: Text(f.emoji),
            label: Text(f.label),
            onPressed: () => onFlow(f),
          ),
        );
      }
    } else {
      if (engine.inputKind == InputKind.date) {
        chips.add(
          ActionChip(
            avatar: const Icon(Icons.calendar_month, size: 18),
            label: const Text('Pick date'),
            onPressed: onPickDate,
          ),
        );
      }
      for (final o in engine.options) {
        chips.add(
          o == cancelOption
              ? ActionChip(
                  avatar: const Icon(Icons.close, size: 18),
                  label: Text(o),
                  onPressed: () => onOption(o),
                )
              : ActionChip(label: Text(o), onPressed: () => onOption(o)),
        );
      }
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 140),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: SingleChildScrollView(
        child: Wrap(spacing: 6, runSpacing: 4, children: chips),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = context.watch<AppStore>();
    final mine = message.fromUser;
    final txn = store.txnById(message.txnId);
    final removed = message.txnId != null && txn == null;

    // Show the live transaction (reflects later edits) plus extra notes
    // like "New credit card found". The "no date" note disappears once the
    // entry has been edited.
    final edited =
        txn != null &&
        txn.updatedAt.isAfter(
          message.time.toUtc().add(const Duration(seconds: 2)),
        );
    final text = txn != null
        ? [
            describeTxn(store, txn),
            ...message.text
                .split('\n')
                .where(
                  (l) =>
                      l.startsWith('🆕') ||
                      (!edited && l.startsWith('📅 No date')),
                ),
          ].join('\n')
        : message.text;
    final lines = text.split('\n');
    final fg = mine ? Colors.white : scheme.onSurface;

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        gradient: mine ? Royal.gradient : null,
        color: mine ? null : scheme.surfaceContainerLow,
        border: mine
            ? null
            : Border.all(color: Royal.gold.withValues(alpha: 0.45), width: 0.8),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(mine ? 20 : 6),
          bottomRight: Radius.circular(mine ? 6 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: Royal.deep.withValues(alpha: mine ? 0.25 : 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (txn != null) ...[
            Text(
              lines.first,
              style: TextStyle(
                color: txn.type.isOutflow
                    ? Royal.spend(context)
                    : Royal.income(context),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              lines.skip(1).join('\n'),
              style: TextStyle(color: fg, height: 1.55),
            ),
          ] else
            Text(
              text,
              style: TextStyle(
                color: fg,
                height: 1.4,
                decoration: removed ? TextDecoration.lineThrough : null,
              ),
            ),
          if (removed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Removed',
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          if (txn != null) _TxnActions(txn: txn),
          const SizedBox(height: 2),
          Text(
            formatDateTime(message.time),
            style: TextStyle(
              fontSize: 10,
              color: (mine ? Royal.goldLight : scheme.onSurface).withValues(
                alpha: 0.7,
              ),
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }
}

class _TxnActions extends StatelessWidget {
  final Txn txn;
  const _TxnActions({required this.txn});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final canChangeCategory =
        txn.type == TxnType.debit || txn.type == TxnType.credit;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        children: [
          if (canChangeCategory)
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.category_outlined, size: 16),
              label: const Text('Category'),
              onPressed: () async {
                final c = await pickCategory(context, txn.type, txn.category);
                if (c != null) {
                  txn.category = c;
                  store.updateTxn(txn);
                }
              },
            ),
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.event_outlined, size: 16),
            label: const Text('Date'),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: txn.date.isAfter(now) ? now : txn.date,
                firstDate: DateTime(2000),
                lastDate: now,
              );
              if (d == null) return;
              final sameDay =
                  d.year == txn.date.year &&
                  d.month == txn.date.month &&
                  d.day == txn.date.day;
              if (sameDay) return;
              txn.date = DateTime(d.year, d.month, d.day, 12);
              store.updateTxn(txn);
            },
          ),
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
            onPressed: () => showTxnEditor(context, txn),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Undo'),
            onPressed: () => store.deleteTxn(txn),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet listing categories for the transaction type.
Future<String?> pickCategory(
  BuildContext context,
  TxnType type,
  String current,
) {
  final cats = type == TxnType.credit ? creditCategories : debitCategories;
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in cats)
              ChoiceChip(
                label: Text('${c.emoji} ${c.name}'),
                selected: c.name == current,
                onSelected: (_) => Navigator.pop(ctx, c.name),
              ),
          ],
        ),
      ),
    ),
  );
}
