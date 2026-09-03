// dev_profile.dart
//
// Suporte a múltiplas identidades Talksnap na mesma máquina — usado só para
// testes locais (ex: rodar duas cópias do app, "alice" e "bob", cada uma com
// seu próprio savedata Tox e banco de contatos, sem precisar de dois
// dispositivos físicos). Em produção (um usuário, um dispositivo) isso é
// sempre `null` e cada arquivo/banco usa seu nome padrão.

import 'dart:io' show Platform;

/// Nome do perfil de desenvolvimento ativo (via variável de ambiente
/// `TALKSNAP_PROFILE`), ou `null` se não definido.
String? get devProfileSuffix {
  final profile = Platform.environment['TALKSNAP_PROFILE'];
  return (profile == null || profile.isEmpty) ? null : profile;
}

/// Aplica o sufixo de perfil de desenvolvimento (se houver) a um nome base
/// de arquivo/banco de dados.
String withDevProfileSuffix(String baseName) {
  final suffix = devProfileSuffix;
  return suffix == null ? baseName : '${baseName}_$suffix';
}
