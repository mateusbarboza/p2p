// spell_check_provider.dart
//
// Preferência de verificação ortográfica nos campos de mensagem, persistida
// localmente via shared_preferences — mesma lógica de theme_mode_provider.dart
// (é só uma preferência de UI local, não sincroniza via toxcore).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kSpellCheckPrefsKey = 'talksnap.spellCheckEnabled';

class SpellCheckNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_kSpellCheckPrefsKey);
    if (stored == null) return;
    state = stored;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSpellCheckPrefsKey, enabled);
  }
}

final spellCheckProvider = NotifierProvider<SpellCheckNotifier, bool>(
  SpellCheckNotifier.new,
);
