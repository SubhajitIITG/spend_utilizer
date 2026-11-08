// Types shared by the store and the sync service.

enum SyncKind { account, txn, reminder, merchant }

String syncKey(SyncKind kind, String id) => '${kind.name}:$id';

(SyncKind?, String) parseSyncKey(String key) {
  final i = key.indexOf(':');
  if (i < 0) return (null, key);
  final name = key.substring(0, i);
  for (final k in SyncKind.values) {
    if (k.name == name) return (k, key.substring(i + 1));
  }
  return (null, key.substring(i + 1));
}

/// One account / transaction / reminder as stored in the cloud.
/// [data] is null for a deletion.
class SyncRecord {
  final SyncKind kind;
  final String id;
  final Map<String, dynamic>? data;
  final DateTime updatedAt;

  const SyncRecord(this.kind, this.id, this.data, this.updatedAt);

  bool get deleted => data == null;
}

class FetchResult {
  final List<SyncRecord> records;

  /// Opaque server position to continue from next time.
  final String? cursor;
  final bool hasMore;
  const FetchResult(this.records, this.cursor, {this.hasMore = false});
}

/// Cloud storage used by the sync service. Implemented with Supabase in
/// supabase_backend.dart, and with an in-memory fake in tests.
abstract class SyncBackend {
  Future<void> upload(List<SyncRecord> records);
  Future<FetchResult> fetchSince(String? cursor);
}
