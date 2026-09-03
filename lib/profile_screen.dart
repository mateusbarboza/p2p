// profile_screen.dart
//
// Editar o próprio perfil: nome e mensagem de status (sincronizados de
// verdade via toxcore — os contatos passam a ver isso automaticamente,
// tanto os já existentes quanto os que adicionarem você depois) e um
// avatar (só local — ver self_profile_provider.dart para o porquê).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'identity_backup.dart';
import 'providers/self_profile_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'providers/tox_manager_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _statusController;
  bool _initialized = false;
  bool _exportingBackup = false;

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
    await ref.read(selfProfileProvider.notifier).updateAvatarPath(path);
  }

  void _save() {
    ref.read(selfProfileProvider.notifier).updateNameAndStatus(
        _nameController.text.trim(), _statusController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil atualizado!')),
    );
  }

  /// Se a pessoa formatar o PC (ou trocar de máquina) sem esse backup, a
  /// identidade se perde para sempre — o Tox não guarda "conta" em servidor
  /// nenhum, só essas chaves locais. Por isso força um flush antes de ler o
  /// arquivo: sem isso, o backup poderia ficar alguns segundos desatualizado.
  Future<void> _exportBackup() async {
    setState(() => _exportingBackup = true);
    try {
      await ref.read(toxIsolateManagerProvider).flushSavedata();
      final savedataFile = await resolveSavedataFile();
      final bytes = await savedataFile.readAsBytes();
      final savedUri = await FilePicker.saveFile(
        fileName: 'talksnap_backup.tox',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedUri != null ? 'Backup salvo!' : 'Backup cancelado.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao gerar backup: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(selfProfileProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Só inicializa os controllers uma vez com o que já veio do toxcore —
    // depois disso, edição é livre (não sobrescrever o que o usuário está
    // digitando toda vez que um evento de perfil chegar de novo).
    if (!_initialized) {
      _nameController = TextEditingController(text: profile.name);
      _statusController = TextEditingController(text: profile.statusMessage);
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundImage: profile.avatarPath != null
                            ? FileImage(File(profile.avatarPath!))
                            : null,
                        child: profile.avatarPath == null
                            ? const Icon(Icons.person, size: 48)
                            : null,
                      ),
                      const CircleAvatar(
                        radius: 14,
                        child: Icon(Icons.edit, size: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _statusController,
                decoration: const InputDecoration(
                  labelText: 'Descrição (status)',
                  border: OutlineInputBorder(),
                ),
                maxLength: 100,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _save, child: const Text('Salvar')),
              const Divider(height: 40),
              Text('Aparência', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<AppThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text('Claro'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text('Escuro'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.system,
                    label: Text('Sistema'),
                    icon: Icon(Icons.settings_suggest_outlined),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (selection) => ref
                    .read(themeModeProvider.notifier)
                    .setMode(selection.first),
              ),
              const Divider(height: 40),
              Text('Segurança', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Se você formatar o PC sem esse backup, sua identidade e '
                'contatos se perdem para sempre — não existe "recuperar '
                'conta" num sistema P2P sem servidor.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _exportingBackup ? null : _exportBackup,
                icon: const Icon(Icons.backup_outlined),
                label: Text(
                  _exportingBackup
                      ? 'Gerando backup...'
                      : 'Fazer backup da identidade',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
