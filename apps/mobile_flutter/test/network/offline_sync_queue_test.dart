import 'dart:convert';

import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  _FakeGoTrueClient(this._user);
  final User? _user;

  @override
  User? get currentUser => _user;
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  _FakeSupabaseClient(String userId)
      : _auth = _FakeGoTrueClient(
          User(
            id: userId,
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: '2026-11-25T00:00:00Z',
          ),
        );

  final GoTrueClient _auth;

  @override
  GoTrueClient get auth => _auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps concurrent operations and account queues isolated', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final first = OfflineSyncQueue.forUser('queue-test-first');
    final second = OfflineSyncQueue.forUser('queue-test-second');
    await Future.wait([
      first.enqueue('submit_request', {'id': 'one'}),
      first.enqueue('submit_request', {'id': 'two'}),
      second.enqueue('submit_request', {'id': 'three'}),
    ]);

    final firstItems = await first.getAll();
    expect(firstItems.map((item) => item.payload['id']), ['one', 'two']);
    await first.clear();
    expect(await first.count, 0);
    expect((await second.getAll()).single.payload['id'], 'three');
  });

  test(
    'does not associate an ownerless legacy queue with the active account',
    () async {
      const legacyKey = 'offline_sync_queue_v1';
      FlutterSecureStorage.setMockInitialValues({
        legacyKey: '[{"id":"legacy"}]',
      });
      final queue = OfflineSyncQueue.forUser('queue-test-legacy');
      expect(await queue.count, 0);
      expect(
        await const FlutterSecureStorage().read(key: legacyKey),
        isNotNull,
      );
    },
  );

  test(
    'rejects enqueueing punch_attendance offline and drops legacy stored punches',
    () async {
      const userId = 'queue-test-no-punch';
      FlutterSecureStorage.setMockInitialValues({
        'offline_sync_queue_v2_$userId': jsonEncode([
          {
            'id': 'legacy-punch-1',
            'action': 'punch_attendance',
            'payload': {'p_event_type': 'CHECK_IN'},
            'createdAt': '2026-11-25T08:00:00Z',
            'retryCount': 0,
          },
        ]),
      });

      final queue = OfflineSyncQueue.forUser(userId);
      expect(
        () => queue.enqueue('punch_attendance', {'p_event_type': 'CHECK_IN'}),
        throwsUnsupportedError,
      );

      SyncQueueItem? dropped;
      queue.droppedNotifier.addListener(() {
        dropped = queue.droppedNotifier.value;
      });

      final client = _FakeSupabaseClient(userId);
      final processed = await queue.processQueue(client);
      expect(processed, 0);
      expect(await queue.count, 0);
      expect(dropped?.action, 'punch_attendance');
    },
  );
}
