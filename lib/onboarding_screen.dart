// onboarding_screen.dart
//
// Primeiro acesso: aparece automaticamente (ver AppRoot em main.dart)
// quando o nome do perfil ainda está vazio — ou seja, na primeiríssima
// execução do app com essa identidade. Mostra o Talksnap ID recém-gerado
// (o "endereço" que a pessoa vai compartilhar pra ser adicionada) e pede
// nome/foto antes de liberar a tela principal.
//
// Não navega explicitamente para a HomeScreen ao terminar: assim que
// updateNameAndStatus() é chamado, o evento de confirmação do toxcore
// atualiza selfProfileProvider.name, e o AppRoot troca de tela sozinho
// (é só mais um rebuild reagindo ao provider).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/self_profile_provider.dart';
import 'providers/self_status_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _statusController = TextEditingController();
  String? _avatarPath;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    final path = file?.path;
    if (path == null) return;
    setState(() => _avatarPath = path);
    await ref.read(selfProfileProvider.notifier).updateAvatarPath(path);
  }

  void _copyTalksnapId(String talksnapId) {
    Clipboard.setData(ClipboardData(text: talksnapId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Talksnap ID copiado!')),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _submitting = true);
    ref
        .read(selfProfileProvider.notifier)
        .updateNameAndStatus(name, _statusController.text.trim());
    // Não precisa desligar _submitting: assim que o nome deixar de ser
    // vazio, o AppRoot troca esta tela pela HomeScreen.
  }

  @override
  Widget build(BuildContext context) {
    final talksnapId = ref.watch(selfStatusProvider).talksnapId;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bem-vindo(a) ao Talksnap!',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sua identidade P2P já foi criada. Escolha um nome antes de começar.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundImage: _avatarPath != null
                            ? FileImage(File(_avatarPath!))
                            : null,
                        child: _avatarPath == null
                            ? const Icon(Icons.person, size: 44)
                            : null,
                      ),
                      const CircleAvatar(
                          radius: 13, child: Icon(Icons.edit, size: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Seu nome',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _statusController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 100,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting
                      ? 'Entrando...'
                      : 'Começar a usar o Talksnap'),
                ),
                const Divider(height: 40),
                Text('Seu Talksnap ID',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Compartilhe esse código para as pessoas te adicionarem.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: SelectableText(
                        talksnapId ?? 'Gerando identidade P2P...',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copiar ID',
                      onPressed: talksnapId == null
                          ? null
                          : () => _copyTalksnapId(talksnapId),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
