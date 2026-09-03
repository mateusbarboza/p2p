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

import 'providers/self_profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _statusController;
  bool _initialized = false;

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

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(selfProfileProvider);

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
            ],
          ),
        ),
      ),
    );
  }
}
