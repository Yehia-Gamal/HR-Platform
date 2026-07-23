import 'dart:io';

Future<bool> hasNetworkConnection() async {
  final result = await InternetAddress.lookup('dns.google');
  return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
}
