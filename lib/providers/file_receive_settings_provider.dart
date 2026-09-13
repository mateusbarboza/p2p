// file_receive_settings_provider.dart
//
// Preferências de recebimento de arquivo, persistidas localmente (mesmo
// padrão de spell_check_provider.dart): se aceita transferências recebidas
// automaticamente (sem precisar clicar em "Aceitar" no chat) e um limite de
// tamanho opcional que governa esse auto-aceite — ver uso em
// file_transfers_provider.dart, no handler do evento `requested`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kAutoAcceptPrefsKey = 'talksnap.autoAcceptFiles';
const String _kMaxFileSizeMbPrefsKey = 'talksnap.maxAutoAcceptFileSizeMb';

class FileReceiveSettings {
  const FileReceiveSettings({
    this.autoAccept = false,
    // 0 = sem limite.
    this.maxSizeMb = 0,
  });

  final bool autoAccept;
  final int maxSizeMb;

  int? get maxSizeBytes => maxSizeMb > 0 ? maxSizeMb * 1024 * 1024 : null;

  FileReceiveSettings copyWith({bool? autoAccept, int? maxSizeMb}) {
    return FileReceiveSettings(
      autoAccept: autoAccept ?? this.autoAccept,
      maxSizeMb: maxSizeMb ?? this.maxSizeMb,
    );
  }
}

class FileReceiveSettingsNotifier extends Notifier<FileReceiveSettings> {
  @override
  FileReceiveSettings build() {
    _load();
    return const FileReceiveSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = FileReceiveSettings(
      autoAccept: prefs.getBool(_kAutoAcceptPrefsKey) ?? false,
      maxSizeMb: prefs.getInt(_kMaxFileSizeMbPrefsKey) ?? 0,
    );
  }

  Future<void> setAutoAccept(bool value) async {
    state = state.copyWith(autoAccept: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoAcceptPrefsKey, value);
  }

  Future<void> setMaxSizeMb(int value) async {
    state = state.copyWith(maxSizeMb: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMaxFileSizeMbPrefsKey, value);
  }
}

final fileReceiveSettingsProvider =
    NotifierProvider<FileReceiveSettingsNotifier, FileReceiveSettings>(
  FileReceiveSettingsNotifier.new,
);
