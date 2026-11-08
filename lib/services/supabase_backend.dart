import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_types.dart';

/// Stores records in the `records` table (see supabase/schema.sql).
/// Row-level security makes sure each user only sees their own rows.
class SupabaseSyncBackend implements SyncBackend {
  final SupabaseClient client;
  static const _pageSize = 1000;

  SupabaseSyncBackend(this.client);

  String get _userId {
    final id = client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Not signed in');
    return id;
  }

  @override
  Future<void> upload(List<SyncRecord> records) async {
    if (records.isEmpty) return;
    final uid = _userId;
    await client.from('records').upsert([
      for (final r in records)
        {
          'user_id': uid,
          'kind': r.kind.name,
          'id': r.id,
          'data': r.data,
          'deleted': r.deleted,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
        },
    ], onConflict: 'user_id,kind,id');
  }

  @override
  Future<FetchResult> fetchSince(String? cursor) async {
    var query = client
        .from('records')
        .select('kind,id,data,deleted,updated_at,synced_at')
        .eq('user_id', _userId);
    if (cursor != null) query = query.gt('synced_at', cursor);
    final rows = await query.order('synced_at').limit(_pageSize);

    final out = <SyncRecord>[];
    String? last = cursor;
    for (final row in rows) {
      last = row['synced_at'] as String;
      final (kind, _) = parseSyncKey('${row['kind']}:');
      if (kind == null) continue;
      final deleted = row['deleted'] as bool? ?? false;
      out.add(
        SyncRecord(
          kind,
          row['id'] as String,
          deleted ? null : (row['data'] as Map).cast<String, dynamic>(),
          DateTime.parse(row['updated_at'] as String).toUtc(),
        ),
      );
    }
    return FetchResult(out, last, hasMore: rows.length == _pageSize);
  }
}
