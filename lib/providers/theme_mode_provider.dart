// theme_mode_provider.dart
//
// Preferência de tema (Claro/Escuro/Sistema), persistida localmente via
// shared_preferences — é só uma preferência de UI, não faz sentido
// sincronizar via toxcore (ao contrário de nome/status do perfil).

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  light,
  dark,
  system;

  ThemeMode get flutterThemeMode {
    switch (this) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }
}

const String _kThemeModePrefsKey = 'talksnap.themeMode';

class ThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    _load();
    return AppThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kThemeModePrefsKey);
    if (stored == null) return;
    state = AppThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => AppThemeMode.system,
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModePrefsKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeMode>(
  ThemeModeNotifier.new,
);
