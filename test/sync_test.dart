import 'package:flutter_test/flutter_test.dart';
import 'package:spend_utilizer/data/store.dart';
import 'package:spend_utilizer/models/models.dart';
import 'package:spend_utilizer/services/auth_service.dart';
import 'package:spend_utilizer/services/sync_service.dart';
import 'package:spend_utilizer/services/sync_types.dart';

/// In-memory stand-in for the Supabase `records` table.
class FakeCloud implements SyncBackend {
  final Map<String, (SyncRecord, int)> rows = {};
  int _clock = 0;
  bool offline = false;
  int pageSize = 1000;

  @override
  Future<void> upload(List<SyncRecord> records) async {
    if (offline) throw Exception('SocketException: offline');
    for (final r in records) {
      final key = syncKey(r.kind, r.id);
      // Same rule as the database trigger: stale uploads are ignored.
      final existing = rows[key];
      if (existing != null && r.updatedAt.isBefore(existing.$1.updatedAt)) {
        continue;
      }
      rows[key] = (r, ++_clock);
    }
  }

  @override
  Future<FetchResult> fetchSince(String? cursor) async {
    if (offline) throw Exception('SocketException: offline');
    final after = cursor == null ? 0 : int.parse(cursor);
    final list = rows.values.where((e) => e.$2 > after).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    final page = list.take(pageSize).toList();
    return FetchResult(
      page.map((e) => e.$1).toList(),
      page.isEmpty ? cursor : '${page.last.$2}',
      hasMore: list.length > pageSize,
    );
  }
}

const sms1 =
    'Spent Rs.500 On HDFC Bank Credit Card xx1111 At SWIGGY '
    'On 2026-11-04:10:00:00 Avl Lmt Rs.50,000';
const sms2 =
    'Rs.200.00 debited from A/c XX4567 on 05-11-26 to VPA '
    'blinkit@axisbank (UPI Ref No 512345678901) -SBI';

Future<(AppStore, SyncService)> device(FakeCloud cloud, String user) async {
  final store = AppStore(storage: MemoryStorage());
  await store.load();
  final sync = SyncService(store);
  sync.start(cloud, user);
  await sync.syncNow();
  return (store, sync);
}

Future<void> tick() => Future.delayed(const Duration(milliseconds: 2));

void main() {
  test('changes on one device appear on another', () async {
    final cloud = FakeCloud();
    final (phone, phoneSync) = await device(cloud, 'u1');
    final (laptop, laptopSync) = await device(cloud, 'u1');

    phone.addFromSms(sms1);
    await phoneSync.syncNow();
    await laptopSync.syncNow();
    expect(laptop.txns.single.amount, 500);
    expect(laptop.accounts.single.last4, '1111');

    // Edit on laptop → shows on phone.
    await tick();
    laptop.txns.single.category = 'Groceries';
    laptop.updateTxn(laptop.txns.single);
    laptop.updateAccount(laptop.accounts.single, nickname: 'My HDFC');
    await laptopSync.syncNow();
    await phoneSync.syncNow();
    expect(phone.txns.single.category, 'Groceries');
    expect(phone.accounts.single.displayName, 'My HDFC');

    // Delete on phone → disappears on laptop.
    await tick();
    phone.deleteTxn(phone.txns.single);
    await phoneSync.syncNow();
    await laptopSync.syncNow();
    expect(laptop.txns, isEmpty);
    expect(phone.dirty, isEmpty);
    expect(phone.tombstones, isEmpty);
    phoneSync.stop();
    laptopSync.stop();
  });

  test('newest edit wins in a conflict', () async {
    final cloud = FakeCloud();
    final (a, aSync) = await device(cloud, 'u1');
    final (b, bSync) = await device(cloud, 'u1');
    a.addFromSms(sms2);
    await aSync.syncNow();
    await bSync.syncNow();

    // Both edit offline; B edits later.
    a.txns.single.note = 'from A';
    a.updateTxn(a.txns.single);
    await tick();
    b.txns.single.note = 'from B';
    b.updateTxn(b.txns.single);

    await bSync.syncNow();
    await aSync.syncNow(); // A uploads its older edit, then downloads B's
    await bSync.syncNow();
    expect(a.txns.single.note, 'from B');
    expect(b.txns.single.note, 'from B');
    aSync.stop();
    bSync.stop();
  });

  test('offline edits are kept and uploaded later', () async {
    final cloud = FakeCloud()..offline = true;
    final (a, aSync) = await device(cloud, 'u1');
    a.addFromSms(sms1);
    await aSync.syncNow();
    expect(aSync.state, SyncState.error);
    expect(a.dirty, isNotEmpty);

    cloud.offline = false;
    await aSync.syncNow();
    expect(aSync.state, SyncState.idle);
    expect(a.dirty, isEmpty);
    expect(cloud.rows.length, 2); // account + transaction
    aSync.stop();
  });

  test('data entered before first login is uploaded to the account', () async {
    final cloud = FakeCloud();
    final store = AppStore(storage: MemoryStorage());
    await store.load();
    store.addFromSms(sms1);
    store.dirty.clear(); // as if created long before sync existed
    final sync = SyncService(store);
    sync.start(cloud, 'u1');
    await sync.syncNow();
    expect(cloud.rows.length, 2);
    expect(store.ownerId, 'u1');
    sync.stop();
  });

  test('a different user signing in never sees the old user\'s data', () async {
    final cloud = FakeCloud();
    final store = AppStore(storage: MemoryStorage());
    await store.load();
    final sync = SyncService(store);
    sync.start(cloud, 'u1');
    store.addFromSms(sms1);
    await sync.syncNow();
    sync.stop();
    sync.start(FakeCloud(), 'u2');
    await sync.syncNow();
    expect(store.txns, isEmpty);
    sync.stop();
  });

  test('paged download fetches everything', () async {
    final cloud = FakeCloud()..pageSize = 3;
    final (a, aSync) = await device(cloud, 'u1');
    for (var i = 0; i < 10; i++) {
      a.addTxn(
        Txn(
          id: 't$i',
          type: TxnType.debit,
          amount: i + 1.0,
          category: 'Others',
          date: DateTime(2026, 11, 1),
        ),
      );
    }
    await aSync.syncNow();
    final (b, bSync) = await device(cloud, 'u1');
    expect(b.txns.length, 10);
    aSync.stop();
    bSync.stop();
  });

  test('sync state survives an app restart', () async {
    final storage = MemoryStorage();
    final s = AppStore(storage: storage);
    await s.load();
    s.addFromSms(sms1);
    s.attachUser('u1');
    s.deleteTxn(s.txns.single);
    await s.saveNow();
    final s2 = AppStore(storage: storage);
    await s2.load();
    expect(s2.ownerId, 'u1');
    expect(s2.tombstones.length, 1);
    expect(
      s2.dirty,
      contains(syncKey(SyncKind.account, s2.accounts.single.id)),
    );
  });

  test('phone numbers get the default country code', () {
    expect(AuthService.normalizePhone('98765 43210'), '+919876543210');
    expect(AuthService.normalizePhone('09876543210'), '+919876543210');
    expect(AuthService.normalizePhone('+1 (415) 555-0100'), '+14155550100');
    expect(AuthService.looksLikePhone('12'), isFalse);
    expect(AuthService.looksLikeEmail('a@b.co'), isTrue);
    expect(AuthService.looksLikeEmail('nope'), isFalse);
  });

  test('network errors are shown in plain words', () {
    final msg = AuthService.errorText(
      Exception('ClientException with SocketException: Connection refused'),
    );
    expect(msg, contains('internet connection'));
  });
}
