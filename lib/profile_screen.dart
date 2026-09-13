// profile_screen.dart
//
// Editar o próprio perfil: nome e mensagem de status (sincronizados de
// verdade via toxcore — os contatos passam a ver isso automaticamente,
// tanto os já existentes quanto os que adicionarem você depois) e um
// avatar (só local — ver self_profile_provider.dart para o porquê).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'identity_backup.dart';
import 'providers/self_profile_provider.dart';
import 'providers/spell_check_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'providers/tox_manager_provider.dart';
import 'providers/update_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    required this.currentUsername,
    required this.onLogout,
    required this.onChangePassword,
    required this.onRenameAccount,
    required this.onDeleteAccount,
  });

  /// Usuário de LOGIN local (diferente do nome de perfil Talksnap, que é
  /// sincronizado via toxcore e editado mais abaixo nesta mesma tela).
  final String currentUsername;

  /// Vêm de fora do ProviderScope aninhado por conta (ver main.dart) — não
  /// lemos localAuthProvider diretamente aqui porque essa tela vive DENTRO
  /// do escopo por conta, e leria uma instância separada do notifier.
  final VoidCallback onLogout;
  final Future<bool> Function(String currentPassword, String newPassword)
      onChangePassword;
  final Future<void> Function(String newUsername) onRenameAccount;

  /// Confere a senha e, se bater, apaga a conta inteira (registro local +
  /// savedata + banco + avatar) e volta pro login. Retorna uma mensagem de
  /// erro (ex: senha incorreta) ou `null` em caso de sucesso.
  final Future<String?> Function(String password) onDeleteAccount;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _statusController;
  bool _initialized = false;
  bool _exportingBackup = false;
  String? _savedataPath;

  @override
  void initState() {
    super.initState();
    resolveSavedataFile().then((file) {
      if (mounted) setState(() => _savedataPath = file.path);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _copySavedataPath() {
    final path = _savedataPath;
    if (path == null) return;
    Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Caminho copiado!')),
    );
  }

  /// Abre o Explorer já na pasta do arquivo, com ele selecionado — só
  /// funciona no Windows (`/select,` é uma flag do `explorer.exe`).
  Future<void> _openSavedataFolder() async {
    final path = _savedataPath;
    if (path == null) return;
    try {
      await Process.run('explorer.exe', ['/select,$path']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir a pasta: $e')),
      );
    }
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

  Future<void> _showChangePasswordDialog() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Alterar senha'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentController,
                decoration: const InputDecoration(labelText: 'Senha atual'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newController,
                decoration: const InputDecoration(labelText: 'Nova senha'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                decoration:
                    const InputDecoration(labelText: 'Confirmar nova senha'),
                obscureText: true,
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(
                  dialogError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (newController.text.isEmpty) {
                  setDialogState(() => dialogError = 'Informe a nova senha.');
                  return;
                }
                if (newController.text != confirmController.text) {
                  setDialogState(
                      () => dialogError = 'As senhas não coincidem.');
                  return;
                }
                final ok = await widget.onChangePassword(
                    currentController.text, newController.text);
                if (!context.mounted) return;
                if (!ok) {
                  setDialogState(() => dialogError = 'Senha atual incorreta.');
                  return;
                }
                Navigator.pop(context);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Senha alterada!')),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameAccountDialog() async {
    final controller = TextEditingController(text: widget.currentUsername);
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Renomear usuário'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Usuário'),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(
                  dialogError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final newUsername = controller.text.trim();
                if (newUsername.isEmpty) {
                  setDialogState(() => dialogError = 'Informe um usuário.');
                  return;
                }
                await widget.onRenameAccount(newUsername);
                if (!context.mounted) return;
                Navigator.pop(context);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Usuário renomeado!')),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final passwordController = TextEditingController();
    String? dialogError;
    bool deleting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Excluir conta?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Isso apaga essa identidade, contatos, mensagens e grupos '
                'deste dispositivo PARA SEMPRE — sem backup, não tem como '
                'recuperar depois. Digite sua senha para confirmar.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(
                  dialogError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: deleting
                  ? null
                  : () async {
                      if (passwordController.text.isEmpty) {
                        setDialogState(() => dialogError = 'Informe a senha.');
                        return;
                      }
                      setDialogState(() {
                        deleting = true;
                        dialogError = null;
                      });
                      final error =
                          await widget.onDeleteAccount(passwordController.text);
                      if (!context.mounted) return;
                      if (error != null) {
                        setDialogState(() {
                          deleting = false;
                          dialogError = error;
                        });
                        return;
                      }
                      Navigator.pop(context);
                    },
              child: Text(deleting ? 'Excluindo...' : 'Excluir'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair?'),
        content: const Text(
          'Você volta pra tela de login. Seu usuário e senha continuam salvos '
          'neste dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onLogout();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _checkForUpdates() async {
    await ref.read(updateProvider.notifier).checkNow();
    if (!mounted) return;
    final state = ref.read(updateProvider);
    if (state.status == UpdateCheckStatus.upToDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Você já está na versão mais recente (${state.currentVersion}).',
          ),
        ),
      );
    } else if (state.status == UpdateCheckStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage ?? 'Erro desconhecido.')),
      );
    }
  }

  Future<void> _openReleasePage(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildUpdateSection(BuildContext context, UpdateCheckState state) {
    final subtitle = switch (state.status) {
      UpdateCheckStatus.idle =>
        'Toque para checar se há uma versão mais nova do Talksnap.',
      UpdateCheckStatus.checking => 'Verificando...',
      UpdateCheckStatus.upToDate =>
        'Você está na versão mais recente (${state.currentVersion}).',
      UpdateCheckStatus.available =>
        'Nova versão disponível: ${state.latestVersion}.',
      UpdateCheckStatus.error =>
        state.errorMessage ?? 'Não foi possível verificar atualizações.',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Verificar atualizações'),
      subtitle: Text(subtitle),
      trailing: state.status == UpdateCheckStatus.checking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : state.status == UpdateCheckStatus.available
              ? FilledButton(
                  onPressed: () => _openReleasePage(state.releaseUrl),
                  child: const Text('Atualizar'),
                )
              : OutlinedButton(
                  onPressed: _checkForUpdates,
                  child: const Text('Verificar'),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(selfProfileProvider);
    final themeMode = ref.watch(themeModeProvider);
    final spellCheckEnabled = ref.watch(spellCheckProvider);
    final updateState = ref.watch(updateProvider);

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
              Text('Configurações',
                  style: Theme.of(context).textTheme.titleMedium),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Verificar ortografia'),
                subtitle: const Text(
                  'Sublinha palavras que o corretor do sistema não reconhece '
                  'ao digitar mensagens.',
                ),
                value: spellCheckEnabled,
                onChanged: (value) =>
                    ref.read(spellCheckProvider.notifier).setEnabled(value),
              ),
              const SizedBox(height: 8),
              _buildUpdateSection(context, updateState),
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
              const SizedBox(height: 12),
              Text(
                'Arquivo de identidade (.tox) desta conta',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _savedataPath == null ? null : _openSavedataFolder,
                      child: Text(
                        _savedataPath ?? 'Carregando...',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: _savedataPath == null
                              ? null
                              : Theme.of(context).colorScheme.primary,
                          decoration: _savedataPath == null
                              ? null
                              : TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    tooltip: 'Abrir pasta',
                    onPressed:
                        _savedataPath == null ? null : _openSavedataFolder,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copiar caminho',
                    onPressed: _savedataPath == null ? null : _copySavedataPath,
                  ),
                ],
              ),
              const Divider(height: 40),
              Text('Conta', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Usuário: ${widget.currentUsername}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showRenameAccountDialog,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Renomear usuário'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.password_outlined),
                label: const Text('Alterar senha'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout),
                label: const Text('Sair'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showDeleteAccountDialog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Excluir conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
