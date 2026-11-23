import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/offline_aware_provider.dart';
import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authSessionProvider = StreamProvider<Session?>((ref) async* {
  final client = ref.watch(supabaseProvider);
  final session = client.auth.currentSession;
  if (session != null && session.isExpired) {
    try {
      await client.auth.refreshSession();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthSession] Background refresh failed, retaining session: $e');
      }
    }
  }
  yield client.auth.currentSession;

  // منع أخطاء الشبكة أثناء التحديث التلقائي في الخلفية من إسقاط المزود
  final safeStream = client.auth.onAuthStateChange.handleError((error, stackTrace) {
    if (kDebugMode) {
      debugPrint('[AuthSession] onAuthStateChange error suppressed: $error');
    }
  });

  try {
    await for (final state in safeStream) {
      if (state.session != null) {
        yield state.session;
      } else if (state.event == AuthChangeEvent.signedOut) {
        yield null;
      } else {
        // عند تعثر تجديد الرمز بسبب الشبكة لا نسقط جلسة المستخدم
        yield client.auth.currentSession;
      }
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[AuthSession] Stream error, falling back to currentSession: $e');
    }
    if (client.auth.currentSession != null) {
      yield client.auth.currentSession;
    } else {
      rethrow;
    }
  }
});

final authUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authSessionProvider.select((state) => state.value?.user.id));
});

/// Streams true while a PASSWORD_RECOVERY deep-link session is active (invite /
/// reset email opened the app). Resets to false once the user saves their
/// password (userUpdated) or signs out.
final passwordRecoveryActiveProvider = StreamProvider<bool>((ref) async* {
  final client = ref.watch(supabaseProvider);
  yield false;
  await for (final state in client.auth.onAuthStateChange) {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      yield true;
    } else if (state.event == AuthChangeEvent.userUpdated ||
        state.event == AuthChangeEvent.signedOut) {
      yield false;
    }
  }
});

final accessContextProvider = FutureProvider<AccessContext?>((ref) async {
  final session = ref.watch(authSessionProvider).value;
  if (session == null) return null;
  final client = ref.watch(supabaseProvider);
  if (client.auth.currentUser?.id != session.user.id) return null;

  return offlineAwareRpc(
    client: client,
    rpcCall: () => retryWithBackoff(
      () => rpcWithTimeout(
        client.rpc<dynamic>('get_my_access_context'),
      ),
      maxRetries: 2,
    ),
    cacheKey: OfflineCache.accessContext,
    timeout: const Duration(seconds: 65),
    parser: (data) => AccessContext.fromJson(Map<String, dynamic>.from(data as Map)),
  );
});

