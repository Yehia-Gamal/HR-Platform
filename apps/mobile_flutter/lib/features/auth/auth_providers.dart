import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authSessionProvider = StreamProvider<Session?>((ref) async* {
  final client = ref.watch(supabaseProvider);
  yield client.auth.currentSession;
  await for (final state in client.auth.onAuthStateChange) {
    yield state.session;
  }
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
  final response = await rpcWithTimeout(
    client.rpc<dynamic>('get_my_access_context'),
  );
  return AccessContext.fromJson(
    Map<String, dynamic>.from(response as Map<dynamic, dynamic>),
  );
});

