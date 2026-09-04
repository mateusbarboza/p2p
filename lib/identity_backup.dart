// identity_backup.dart
//
// Resolve o caminho do arquivo de savedata (identidade Tox) a partir de
// QUALQUER isolate — tanto o isolate de rede (tox_isolate_manager.dart)
// quanto a UI (para checar se já existe identidade antes de decidir mostrar
// WelcomeChoiceScreen, e para ler os bytes na hora de exportar um backup).
// Os dois lados precisam calcular exatamente o mesmo caminho, por isso essa
// lógica mora num só lugar em vez de duplicada.

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dev_profile.dart';

Future<File> resolveSavedataFile() async {
  final directory = await getApplicationSupportDirectory();
  final fileName = '${withDevProfileSuffix('talksnap')}.tox';
  return File('${directory.path}${Platform.pathSeparator}$fileName');
}

/// Apaga TUDO que pertence só a esta conta: savedata Tox, banco de dados
/// local (mensagens/contatos/grupos) e a preferência de caminho do avatar —
/// usado ao excluir a conta. Chamar só DEPOIS que o isolate de rede e o
/// banco já foram parados/fechados (arquivo em uso não pode ser apagado no
/// Windows).
Future<void> deleteAccountFiles() async {
  final savedataFile = await resolveSavedataFile();
  if (await savedataFile.exists()) {
    await savedataFile.delete();
  }

  final directory = await getApplicationSupportDirectory();
  final dbBaseName = withDevProfileSuffix('talksnap');
  for (final suffix in [
    '.sqlite',
    '.sqlite-wal',
    '.sqlite-shm',
    '.sqlite-journal'
  ]) {
    final file =
        File('${directory.path}${Platform.pathSeparator}$dbBaseName$suffix');
    if (await file.exists()) {
      await file.delete();
    }
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(withDevProfileSuffix('talksnap.avatarPath'));
}
