// dev_profile.dart
//
// Duas camadas de "sufixo de perfil":
//
//   - deviceSuffix: só a variável de ambiente `TALKSNAP_PROFILE`, usada
//     para simular várias MÁQUINAS na mesma máquina física durante testes
//     locais (ex: "alice"/"bob"/"teste1"/"teste2" rodando em janelas
//     separadas). Em produção isso é sempre `null`.
//   - activeAccountSlug: a conta local escolhida pelo usuário na tela de
//     login (ver providers/local_auth_provider.dart) — cada conta tem sua
//     própria identidade Talksnap (savedata, banco de contatos/mensagens,
//     avatar), como se fossem pessoas diferentes usando o mesmo
//     dispositivo. É `null` até o usuário entrar/criar/importar uma conta.
//
// `devProfileSuffix` combina as duas: recursos por CONTA (savedata, banco,
// avatar) usam essa combinação. Recursos por DISPOSITIVO (a lista de
// contas em si, e a preferência de tema) usam só `deviceSuffix`.

import 'dart:io' show Platform;

String? _activeAccountSlug;

/// Define a conta ativa (chamado pelo LocalAuthNotifier ao entrar/criar/
/// importar uma conta, e voltado a `null` no logout).
void setActiveAccountSlug(String? slug) {
  _activeAccountSlug = slug;
}

String? get activeAccountSlug => _activeAccountSlug;

String? get _rawDeviceProfile {
  final profile = Platform.environment['TALKSNAP_PROFILE'];
  return (profile == null || profile.isEmpty) ? null : profile;
}

/// Sufixo para recursos compartilhados por todas as contas deste
/// dispositivo (ex: a lista de contas locais, preferência de tema).
String? get deviceSuffix => _rawDeviceProfile;

/// Sufixo para recursos exclusivos da conta ativa no momento (savedata,
/// banco de dados, avatar).
String? get devProfileSuffix {
  final parts = [
    if (_rawDeviceProfile != null) _rawDeviceProfile!,
    if (_activeAccountSlug != null) _activeAccountSlug!,
  ];
  return parts.isEmpty ? null : parts.join('_');
}

/// Aplica o sufixo de CONTA (dispositivo de teste + conta ativa) a um nome
/// base de arquivo/banco de dados.
String withDevProfileSuffix(String baseName) {
  final suffix = devProfileSuffix;
  return suffix == null ? baseName : '${baseName}_$suffix';
}

/// Aplica só o sufixo de DISPOSITIVO (sem a conta ativa) a um nome base —
/// para recursos que precisam existir mesmo antes de qualquer conta ser
/// escolhida, como a lista de contas locais.
String withDeviceSuffix(String baseName) {
  final suffix = deviceSuffix;
  return suffix == null ? baseName : '${baseName}_$suffix';
}
