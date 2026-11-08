import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Something another app shared to Spend Utilizer via the share sheet.
class SharedItem {
  /// A payment screenshot / receipt image file on the device.
  final String? imagePath;

  /// Shared text, e.g. a bank SMS from the Messages app.
  final String? text;

  const SharedItem.image(String path) : imagePath = path, text = null;
  const SharedItem.text(String value) : text = value, imagePath = null;
}

/// Holds items shared into the app until the chat is ready to handle them
/// (after the app has started and the user is signed in).
class ShareInbox extends ChangeNotifier {
  final List<SharedItem> _pending = [];
  StreamSubscription<List<SharedMediaFile>>? _sub;

  List<SharedItem> get pending => List.unmodifiable(_pending);
  bool get hasPending => _pending.isNotEmpty;

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Starts receiving shares: the one that opened the app, and any shared
  /// while it's running.
  Future<void> start() async {
    if (!isSupported) return;
    try {
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
        _addAll,
        onError: (Object e) => debugPrint('Share stream error: $e'),
      );
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      _addAll(initial);
      // Don't receive the same launch share again next time.
      await ReceiveSharingIntent.instance.reset();
    } catch (e) {
      debugPrint('Sharing not available: $e');
    }
  }

  void _addAll(List<SharedMediaFile> files) {
    var added = false;
    for (final f in files) {
      if (f.type == SharedMediaType.image && f.path.isNotEmpty) {
        _pending.add(SharedItem.image(f.path));
        added = true;
      } else if ((f.type == SharedMediaType.text ||
              f.type == SharedMediaType.url) &&
          f.path.trim().isNotEmpty) {
        // For text shares the plugin puts the text itself in `path`.
        _pending.add(SharedItem.text(f.path));
        added = true;
      }
    }
    if (added) notifyListeners();
  }

  /// Adds an item directly (used by tests).
  void add(SharedItem item) {
    _pending.add(item);
    notifyListeners();
  }

  /// Removes and returns the oldest pending item.
  SharedItem? take() {
    if (_pending.isEmpty) return null;
    final item = _pending.removeAt(0);
    notifyListeners();
    return item;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
