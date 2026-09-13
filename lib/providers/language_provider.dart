// language_provider.dart
//
// Preferência de idioma da interface, persistida localmente (mesmo padrão
// de theme_mode_provider.dart/spell_check_provider.dart). O valor aqui
// alimenta o `locale:` do MaterialApp (ver main.dart/TalksnapApp) — trocar
// o idioma troca a interface inteira via flutter_localizations/.arb
// (lib/l10n/).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kLanguagePrefsKey = 'talksnap.languageCode';

enum AppLanguage {
  english('en', 'English'),
  spanish('es', 'Español'),
  portuguese('pt', 'Português'),
  chinese('zh', '中文'),
  japanese('ja', '日本語'),
  german('de', 'Deutsch'),
  french('fr', 'Français');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (language) => language.code == code,
      orElse: () => AppLanguage.portuguese,
    );
  }
}

class LanguageNotifier extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    _load();
    return AppLanguage.portuguese;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kLanguagePrefsKey);
    if (stored == null) return;
    state = AppLanguage.fromCode(stored);
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguagePrefsKey, language.code);
  }
}

final languageProvider = NotifierProvider<LanguageNotifier, AppLanguage>(
  LanguageNotifier.new,
);
