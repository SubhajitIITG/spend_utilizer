import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../services/categories.dart';
import '../services/chat_engine.dart';
import '../services/ocr_service.dart';
import '../services/share_inbox.dart';
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

  ChatEngine get engine =>
      _engine ??= ChatEngine(context.read<AppStore>())..resumePendingQuestion();

  ShareInbox? _inbox;
  bool _draining = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inbox = context.read<ShareInbox>();
    if (!identical(inbox, _inbox)) {
      _inbox?.removeListener(_onShared);
      _inbox = inbox..addListener(_onShared);
      WidgetsBinding.instance.addPostFrameCallback((_) => _drainShares());
    }
  }

  void _onShared() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _drainShares());

  /// Handles items shared from other apps, one at a time. A shared
  /// screenshot waits until the previous one's "Add it?" is answered.
  Future<void> _drainShares() async {
    final inbox = _inbox;
    if (inbox == null || _draining || !mounted) return;
    _draining = true;
    try {
      while (mounted && inbox.hasPending) {
        if (engine.flow == ChatFlow.screenshot) break; // answer first
        final item = inbox.take()!;
        if (item.imagePath != null) {
          await _readScreenshot(item.imagePath!, shared: true);
        } else if (item.text != null) {
          if (engine.active) engine.cancel();
          _send(item.text!);
        }
      }
    } finally {
      _draining = false;
    }
  }

  @override
  void dispose() {
    _inbox?.removeListener(_onShared);
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

  /// Asks before wiping the chat. Transactions, accounts and reminders are
  /// not affected.
  Future<void> _confirmClearChat() async {
    final store = context.read<AppStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text(
          'This removes the messages on this screen only. Your transactions, '
          'accounts, reminders and History stay safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    engine.cancel();
    store.clearChat();
    _controller.clear();
    setState(() {});
  }

  void _send(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    // Typing "clear", "clear chat" or "/clear" also clears the chat.
    if (RegExp(
      r'^/?(clear|clear chat|clear history|clear chat history)$',
      caseSensitive: false,
    ).hasMatch(t)) {
      _confirmClearChat();
      return;
    }
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
    // A shared screenshot may be waiting for this answer.
    if (_inbox?.hasPending ?? false) _drainShares();
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

  /// Android: pick a payment screenshot, read it on the device and let the
  /// chat engine check it.
  Future<void> _pickScreenshot() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || !mounted) return; // cancelled
    final path = file.path;
    if (path == null) {
      _post(engine.screenshotError('the picked image could not be opened'));
      return;
    }
    await _readScreenshot(path);
  }

  /// Reads a payment screenshot on the device and lets the chat engine
  /// check it. [shared]: it came from another app's share sheet.
  Future<void> _readScreenshot(String path, {bool shared = false}) async {
    final store = context.read<AppStore>();
    final messenger = ScaffoldMessenger.of(context);
    if (engine.active) engine.cancel();
    store.addChat(
      ChatMessage(
        id: store.newId(),
        fromUser: true,
        text: shared ? '📷 Shared payment receipt' : '📷 Payment screenshot',
        time: DateTime.now(),
      ),
    );
    setState(() {});
    messenger.showSnackBar(
      const SnackBar(content: Text('Reading the screenshot…')),
    );
    try {
      final text = await OcrService.readText(path);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      _post(engine.handleScreenshot(text));
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      _post(engine.screenshotError(e));
    }
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
              if (v == 'clear') _confirmClearChat();
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
            onClearChat: store.chat.isEmpty ? null : _confirmClearChat,
            onScreenshot: OcrService.isSupported ? _pickScreenshot : null,
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: Royal.gold.withValues(alpha: 0.5)),
              ),
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
                    if (OcrService.isSupported)
                      IconButton(
                        tooltip: 'Add a payment screenshot',
                        icon: Icon(
                          Icons.add_photo_alternate_outlined,
                          color: scheme.primary,
                        ),
                        onPressed: _pickScreenshot,
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

  /// Null hides the "Clear chat" chip (nothing to clear).
  final VoidCallback? onClearChat;

  /// Null hides the "Screenshot" chip (reading needs Android or iOS).
  final VoidCallback? onScreenshot;

  const _OptionsBar({
    required this.engine,
    required this.onFlow,
    required this.onOption,
    required this.onPaste,
    required this.onPickDate,
    required this.onClearChat,
    this.onScreenshot,
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
      if (onScreenshot != null) {
        chips.add(
          ActionChip(
            avatar: const Text('📷'),
            label: const Text('Screenshot'),
            onPressed: onScreenshot,
          ),
        );
      }
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
      if (onClearChat != null) {
        chips.add(
          ActionChip(
            avatar: const Text('🧹'),
            label: const Text('Clear chat'),
            onPressed: onClearChat,
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
        // Solid wine for you, ivory card with a gold rule on the left
        // for the bot. No shadows: flat, like printed paper.
        color: mine ? Royal.purple : scheme.surfaceContainerLow,
        border: mine
            ? null
            : const Border(left: BorderSide(color: Royal.gold, width: 3)),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(mine ? 14 : 2),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(mine ? 14 : 2),
          bottomRight: Radius.circular(mine ? 2 : 14),
        ),
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
                if (c == null || !context.mounted) return;
                final others = store.recategorize(txn, c);
                if (others > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Also moved $others other payment'
                        '${others == 1 ? '' : 's'} to '
                        '"${store.merchantLabel(txn.counterparty)}" into $c. '
                        'Future ones will follow.',
                      ),
                    ),
                  );
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
