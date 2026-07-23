import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _themeModeKey = 'ahla_theme_mode';
const _themeStorage = FlutterSecureStorage();

ThemeMode parseThemeMode(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

String serializeThemeMode(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
  ThemeMode.system => 'system',
};

Future<ThemeMode> loadSavedThemeMode() async {
  try {
    return parseThemeMode(await _themeStorage.read(key: _themeModeKey));
  } catch (_) {
    return ThemeMode.system;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  ThemeModeController({this.initialMode = ThemeMode.system});

  final ThemeMode initialMode;

  @override
  ThemeMode build() => initialMode;

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      await _themeStorage.write(
        key: _themeModeKey,
        value: serializeThemeMode(mode),
      );
    } catch (_) {
      // The in-memory preference remains active when device storage is unavailable.
    }
  }
}
