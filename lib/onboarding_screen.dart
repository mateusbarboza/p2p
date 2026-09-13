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

import 'l10n/app_localizations.dart';
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
      SnackBar(content: Text(AppLocalizations.of(context)!.talksnapIdCopied)),
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
    final l10n = AppLocalizations.of(context)!;

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
                  l10n.welcomeTitleExclamation,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.onboardingIntro,
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
                  decoration: InputDecoration(
                    labelText: l10n.yourName,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _statusController,
                  decoration: InputDecoration(
                    labelText: l10n.descriptionOptional,
                    border: const OutlineInputBorder(),
                  ),
                  maxLength: 100,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting
                      ? l10n.enteringAction
                      : l10n.startUsingTalksnap),
                ),
                const Divider(height: 40),
                Text(l10n.yourTalksnapId,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  l10n.shareThisCodeNotice,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: SelectableText(
                        talksnapId ?? l10n.generatingIdentity,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: l10n.copyId,
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
