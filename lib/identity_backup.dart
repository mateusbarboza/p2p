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

import 'dev_profile.dart';

Future<File> resolveSavedataFile() async {
  final directory = await getApplicationSupportDirectory();
  final fileName = '${withDevProfileSuffix('talksnap')}.tox';
  return File('${directory.path}${Platform.pathSeparator}$fileName');
}
