import 'package:ahla_shabab_management_os/core/security/secure_session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'sb-test-auth-token';
  const secure = FlutterSecureStorage();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'migrates the previous session and removes the plaintext copy',
    () async {
      SharedPreferences.setMockInitialValues({key: 'existing session'});
      final storage = SecureSessionStorage(persistSessionKey: key);
      await storage.initialize();

      expect(await storage.accessToken(), 'existing session');
      expect(await secure.read(key: key), 'existing session');
      expect((await SharedPreferences.getInstance()).containsKey(key), isFalse);
    },
  );

  test(
    'an overlapping session write cannot restore a removed session',
    () async {
      final storage = SecureSessionStorage(persistSessionKey: key);
      await storage.initialize();
      await Future.wait([
        storage.persistSession('new session'),
        storage.removePersistedSession(),
      ]);

      final restarted = SecureSessionStorage(persistSessionKey: key);
      await restarted.initialize();
      expect(await restarted.hasAccessToken(), isFalse);
      expect(await secure.read(key: key), isNull);
      expect((await SharedPreferences.getInstance()).containsKey(key), isFalse);
    },
  );

  test(
    'migrates an in-progress PKCE flow and persists new verifiers securely',
    () async {
      SharedPreferences.setMockInitialValues({'verifier': 'existing verifier'});
      final storage = SecurePkceStorage();
      expect(await storage.getItem(key: 'verifier'), 'existing verifier');
      await storage.setItem(key: 'verifier', value: 'new verifier');
      expect(await secure.read(key: 'pkce_verifier'), 'new verifier');
      expect(
        (await SharedPreferences.getInstance()).containsKey('verifier'),
        isFalse,
      );
      await storage.removeItem(key: 'verifier');
      expect(await storage.getItem(key: 'verifier'), isNull);
    },
  );
}
