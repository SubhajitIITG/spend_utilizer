import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'sync_types.dart';

enum SyncState { idle, syncing, error }

/// Keeps the local store and the cloud in step:
///  1. upload records changed on this device,
///  2. download records changed on other devices since the last sync.
/// Conflicts are resolved per record: the most recent edit wins.
class SyncService extends ChangeNotifier {
  final AppStore store;
  SyncBackend? _backend;

  SyncService(this.store);

  SyncState state = SyncState.idle;
  String? lastError;
  DateTime? lastSyncedAt;

  Timer? _debounce;
  Timer? _periodic;
  Future<void>? _running;
  bool _again = false;

  bool get enabled => _backend != null;

  /// Starts syncing for a signed-in user.
  void start(SyncBackend backend, String userId) {
    _backend = backend;
    store.attachUser(userId);
    store.onLocalChange = _scheduleSoon;
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
    syncNow();
  }

  void stop() {
    _backend = null;
    store.onLocalChange = null;
    _debounce?.cancel();
    _periodic?.cancel();
    state = SyncState.idle;
    lastError = null;
    notifyListeners();
  }

  void _scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncNow);
  }

  /// Runs a sync. If one is already running, another pass is queued and
  /// the returned future completes after it.
  Future<void> syncNow() {
    _again = true;
    return _running ??= _loop();
  }

  Future<void> _loop() async {
    try {
      while (_again) {
        _again = false;
        await _run();
      }
    } finally {
      _running = null;
    }
  }

  Future<void> _run() async {
    final backend = _backend;
    if (backend == null) return;
    state = SyncState.syncing;
    notifyListeners();
    try {
      final pending = store.pendingRecords();
      for (var i = 0; i < pending.length; i += 500) {
        final chunk = pending.sublist(
          i,
          i + 500 > pending.length ? pending.length : i + 500,
        );
        await backend.upload(chunk);
        store.markUploaded(chunk);
      }
      while (true) {
        final res = await backend.fetchSince(store.syncCursor);
        if (_backend != backend) return; // signed out meanwhile
        store.applyRemote(res.records, res.cursor);
        if (!res.hasMore) break;
      }
      state = SyncState.idle;
      lastError = null;
      lastSyncedAt = DateTime.now();
    } catch (e) {
      state = SyncState.error;
      lastError = e.toString();
      debugPrint('Sync failed: $e');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    super.dispose();
  }
}
