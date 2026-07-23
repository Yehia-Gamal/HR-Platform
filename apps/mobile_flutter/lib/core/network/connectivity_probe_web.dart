import 'package:web/web.dart' as web;

Future<bool> hasNetworkConnection() async => web.window.navigator.onLine;
