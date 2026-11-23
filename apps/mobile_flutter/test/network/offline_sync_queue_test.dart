import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
