// welcome_choice_screen.dart
//
// Só aparece quando NENHUM arquivo de savedata existe ainda no disco (ver
// AppRoot em main.dart) — ou seja, antes até do isolate de rede subir e
// gerar uma identidade nova sozinho. É a única janela de oportunidade para
// importar uma identidade de backup: depois que o isolate inicia, se não
// houver savedata, o toxcore já cria uma identidade nova e grava no disco
// imediatamente — tarde demais para "restaurar" nesse ponto.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'identity_backup.dart';

class WelcomeChoiceScreen extends StatefulWidget {
  const WelcomeChoiceScreen({super.key, required this.onIdentityReady});

  /// Chamado quando o usuário decidiu (criar nova ou importou um backup) —
  /// a partir daí é seguro deixar o isolate de rede subir normalmente.
  final VoidCallback onIdentityReady;

  @override
  State<WelcomeChoiceScreen> createState() => _WelcomeChoiceScreenState();
}

class _WelcomeChoiceScreenState extends State<WelcomeChoiceScreen> {
  bool _importing = false;
  String? _error;

  Future<void> _importBackup() async {
    final file = await FilePicker.pickFile();
    final path = file?.path;
    if (path == null) return;

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      final backupBytes = await File(path).readAsBytes();
      final savedataFile = await resolveSavedataFile();
      await savedataFile.parent.create(recursive: true);
      await savedataFile.writeAsBytes(backupBytes, flush: true);
      widget.onIdentityReady();
    } catch (e) {
      setState(() {
        _importing = false;
        _error = 'Não foi possível importar esse arquivo: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bem-vindo(a) ao Talksnap!',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Você já tem uma identidade Talksnap de um backup, ou quer criar uma nova?',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _importing ? null : widget.onIdentityReady,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Criar nova identidade'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _importing ? null : _importBackup,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(_importing
                      ? 'Importando...'
                      : 'Importar identidade (.tox)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
