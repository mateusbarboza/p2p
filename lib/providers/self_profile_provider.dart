// self_profile_provider.dart
//
// Perfil do próprio usuário: nome e mensagem de status (sincronizados de
// verdade via toxcore — os contatos veem essa informação automaticamente)
// e o caminho do avatar (só local: o toxcore não tem um mecanismo simples
// de avatar sincronizado por rede, então a foto fica só no seu dispositivo).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tox_events.dart';
import 'tox_events_provider.dart';
import 'tox_manager_provider.dart';

const String _kAvatarPathPrefsKey = 'talksnap.avatarPath';

class SelfProfile {
  const SelfProfile({
    this.name = '',
    this.statusMessage = '',
    this.avatarPath,
    this.loaded = false,
  });

  final String name;
  final String statusMessage;
  final String? avatarPath;

  /// `true` assim que o primeiro [ToxSelfProfileEvent] chega (nome/status
  /// já lidos do savedata, mesmo que vazios). Distingue "ainda carregando"
  /// de "carregou e o nome está mesmo vazio" — sem isso, a tela de boas-
  /// vindas (ver onboarding_screen.dart) apareceria por um instante em
  /// toda abertura do app, antes do nome salvo ser lido.
  final bool loaded;

  SelfProfile copyWith({
    String? name,
    String? statusMessage,
    String? avatarPath,
    bool? loaded,
  }) {
    return SelfProfile(
      name: name ?? this.name,
      statusMessage: statusMessage ?? this.statusMessage,
      avatarPath: avatarPath ?? this.avatarPath,
      loaded: loaded ?? this.loaded,
    );
  }
}

class SelfProfileNotifier extends Notifier<SelfProfile> {
  @override
  SelfProfile build() {
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) {
        if (event is ToxSelfProfileEvent) {
          state = state.copyWith(
            name: event.name,
            statusMessage: event.statusMessage,
            loaded: true,
          );
        }
      });
    });

    _loadAvatarPath();
    return const SelfProfile();
  }

  Future<void> _loadAvatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_kAvatarPathPrefsKey);
    if (path != null) {
      state = state.copyWith(avatarPath: path);
    }
  }

  /// Atualiza nome e status — propagado de verdade para os contatos via
  /// toxcore (ToxIsolateManager.setProfile).
  void updateNameAndStatus(String name, String statusMessage) {
    ref.read(toxIsolateManagerProvider).setProfile(name, statusMessage);
  }

  /// Atualiza o avatar (só local — nunca sai desta máquina).
  Future<void> updateAvatarPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAvatarPathPrefsKey, path);
    state = state.copyWith(avatarPath: path);
  }
}

final selfProfileProvider = NotifierProvider<SelfProfileNotifier, SelfProfile>(
  SelfProfileNotifier.new,
);
