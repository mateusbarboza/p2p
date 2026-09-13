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
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import 'identity_backup.dart';
import 'l10n/app_localizations.dart';
import 'providers/av_device_settings_provider.dart';
import 'providers/file_receive_settings_provider.dart';
import 'providers/language_provider.dart';
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

  /// `null` enquanto ainda não terminou de carregar (mostra um spinner no
  /// lugar do dropdown); a enumeração em si é assíncrona (`record` consulta
  /// o sistema operacional).
  List<InputDevice>? _inputDevices;

  @override
  void initState() {
    super.initState();
    resolveSavedataFile().then((file) {
      if (mounted) setState(() => _savedataPath = file.path);
    });
    AudioRecorder().listInputDevices().then((devices) {
      if (mounted) setState(() => _inputDevices = devices);
    }).catchError((_) {
      // Enumeração pode falhar em alguns sistemas — sem lista, o usuário
      // só fica sem opção de troca de microfone (continua no padrão).
      if (mounted) setState(() => _inputDevices = const []);
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
      SnackBar(content: Text(AppLocalizations.of(context)!.pathCopied)),
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
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.errorOpeningFolder('$e'))),
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
      SnackBar(content: Text(AppLocalizations.of(context)!.profileUpdated)),
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
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedUri != null ? l10n.backupSaved : l10n.backupCancelled,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.errorBackupFailed('$e'))),
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
    final l10n = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.changePasswordTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentController,
                decoration:
                    InputDecoration(labelText: l10n.currentPasswordLabel),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newController,
                decoration: InputDecoration(labelText: l10n.newPasswordLabel),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                decoration:
                    InputDecoration(labelText: l10n.confirmNewPasswordLabel),
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
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              onPressed: () async {
                if (newController.text.isEmpty) {
                  setDialogState(
                      () => dialogError = l10n.errorEnterNewPassword);
                  return;
                }
                if (newController.text != confirmController.text) {
                  setDialogState(
                      () => dialogError = l10n.errorPasswordsDontMatch);
                  return;
                }
                final ok = await widget.onChangePassword(
                    currentController.text, newController.text);
                if (!context.mounted) return;
                if (!ok) {
                  setDialogState(
                      () => dialogError = l10n.errorWrongCurrentPassword);
                  return;
                }
                Navigator.pop(context);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.passwordChanged)),
                );
              },
              child: Text(l10n.saveAction),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameAccountDialog() async {
    final controller = TextEditingController(text: widget.currentUsername);
    String? dialogError;
    final l10n = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.renameAccountTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.usernameLabel),
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
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              onPressed: () async {
                final newUsername = controller.text.trim();
                if (newUsername.isEmpty) {
                  setDialogState(() => dialogError = l10n.errorEnterUsername);
                  return;
                }
                await widget.onRenameAccount(newUsername);
                if (!context.mounted) return;
                Navigator.pop(context);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.usernameChanged)),
                );
              },
              child: Text(l10n.saveAction),
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
    final l10n = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.deleteAccountTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.deleteAccountWarning),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.passwordLabel),
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
              child: Text(l10n.cancelAction),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: deleting
                  ? null
                  : () async {
                      if (passwordController.text.isEmpty) {
                        setDialogState(
                            () => dialogError = l10n.errorEnterPassword);
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
              child: Text(
                  deleting ? l10n.deletingAction : l10n.deleteAccountAction),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.logoutTitle),
        content: Text(l10n.logoutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.logoutAction),
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
    final l10n = AppLocalizations.of(context)!;
    if (state.status == UpdateCheckStatus.upToDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.upToDateVersion(state.currentVersion)),
        ),
      );
    } else if (state.status == UpdateCheckStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage ?? l10n.unknownError)),
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
    final l10n = AppLocalizations.of(context)!;
    final subtitle = switch (state.status) {
      UpdateCheckStatus.idle => l10n.checkUpdatesTapHint,
      UpdateCheckStatus.checking => l10n.checkingUpdates,
      UpdateCheckStatus.upToDate => l10n.upToDateVersion(state.currentVersion),
      UpdateCheckStatus.available =>
        l10n.updateAvailable(state.latestVersion ?? ''),
      UpdateCheckStatus.error => state.errorMessage ?? l10n.updateCheckError,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.checkUpdatesTitle),
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
                  child: Text(l10n.updateAction),
                )
              : OutlinedButton(
                  onPressed: _checkForUpdates,
                  child: Text(l10n.checkAction),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(selfProfileProvider);
    final themeMode = ref.watch(themeModeProvider);
    final spellCheckEnabled = ref.watch(spellCheckProvider);
    final updateState = ref.watch(updateProvider);
    final fileReceiveSettings = ref.watch(fileReceiveSettingsProvider);
    final currentLanguage = ref.watch(languageProvider);
    final avDeviceSettings = ref.watch(avDeviceSettingsProvider);
    final l10n = AppLocalizations.of(context)!;

    // Só inicializa os controllers uma vez com o que já veio do toxcore —
    // depois disso, edição é livre (não sobrescrever o que o usuário está
    // digitando toda vez que um evento de perfil chegar de novo).
    if (!_initialized) {
      _nameController = TextEditingController(text: profile.name);
      _statusController = TextEditingController(text: profile.statusMessage);
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myProfileTitle)),
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
                decoration: InputDecoration(
                  labelText: l10n.nameLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _statusController,
                decoration: InputDecoration(
                  labelText: l10n.statusDescriptionLabel,
                  border: const OutlineInputBorder(),
                ),
                maxLength: 100,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _save, child: Text(l10n.saveAction)),
              const Divider(height: 40),
              Text(l10n.appearanceTitle,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<AppThemeMode>(
                segments: [
                  ButtonSegment(
                    value: AppThemeMode.light,
                    label: Text(l10n.lightTheme),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    label: Text(l10n.darkTheme),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.system,
                    label: Text(l10n.systemTheme),
                    icon: const Icon(Icons.settings_suggest_outlined),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (selection) => ref
                    .read(themeModeProvider.notifier)
                    .setMode(selection.first),
              ),
              const Divider(height: 40),
              Text(l10n.settingsTitle,
                  style: Theme.of(context).textTheme.titleMedium),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.spellCheckTitle),
                subtitle: Text(l10n.spellCheckSubtitle),
                value: spellCheckEnabled,
                onChanged: (value) =>
                    ref.read(spellCheckProvider.notifier).setEnabled(value),
              ),
              const SizedBox(height: 8),
              _buildUpdateSection(context, updateState),
              const Divider(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.languageTitle),
                subtitle: Text(l10n.languageSubtitle),
                trailing: DropdownButton<AppLanguage>(
                  value: currentLanguage,
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(languageProvider.notifier).setLanguage(value);
                  },
                  items: [
                    for (final language in AppLanguage.values)
                      DropdownMenuItem(
                        value: language,
                        child: Text(language.label),
                      ),
                  ],
                ),
              ),
              const Divider(height: 20),
              Text(l10n.audioVideoTitle,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(l10n.microphoneLabel,
                  style: Theme.of(context).textTheme.bodyLarge),
              Text(l10n.microphoneSubtitle,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              _inputDevices == null
                  ? const LinearProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: avDeviceSettings.microphone?.id,
                        onChanged: (id) {
                          final device = id == null
                              ? null
                              : _inputDevices!
                                  .where((d) => d.id == id)
                                  .firstOrNull;
                          ref
                              .read(avDeviceSettingsProvider.notifier)
                              .setMicrophone(device);
                        },
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(l10n.systemDefaultOption),
                          ),
                          for (final device in _inputDevices!)
                            DropdownMenuItem(
                              value: device.id,
                              child: Text(device.label,
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                      ),
                    ),
              const SizedBox(height: 16),
              Text(l10n.cameraLabel,
                  style: Theme.of(context).textTheme.bodyLarge),
              Text(l10n.cameraSubtitle,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: avDeviceSettings.cameraIndex,
                  onChanged: (index) {
                    if (index == null) return;
                    ref
                        .read(avDeviceSettingsProvider.notifier)
                        .setCameraIndex(index);
                  },
                  items: [
                    for (var i = 0; i < 5; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(l10n.cameraIndexOption(i)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.autoAcceptFilesTitle),
                subtitle: Text(l10n.autoAcceptFilesSubtitle),
                value: fileReceiveSettings.autoAccept,
                onChanged: (value) => ref
                    .read(fileReceiveSettingsProvider.notifier)
                    .setAutoAccept(value),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.maxFileSizeTitle),
                subtitle: Text(l10n.maxFileSizeSubtitle),
                trailing: DropdownButton<int>(
                  value: fileReceiveSettings.maxSizeMb,
                  onChanged: (value) {
                    if (value == null) return;
                    ref
                        .read(fileReceiveSettingsProvider.notifier)
                        .setMaxSizeMb(value);
                  },
                  items: [
                    DropdownMenuItem(value: 0, child: Text(l10n.noLimitOption)),
                    const DropdownMenuItem(value: 10, child: Text('10 MB')),
                    const DropdownMenuItem(value: 25, child: Text('25 MB')),
                    const DropdownMenuItem(value: 50, child: Text('50 MB')),
                    const DropdownMenuItem(value: 100, child: Text('100 MB')),
                    const DropdownMenuItem(value: 250, child: Text('250 MB')),
                    const DropdownMenuItem(value: 500, child: Text('500 MB')),
                    const DropdownMenuItem(value: 1000, child: Text('1 GB')),
                  ],
                ),
              ),
              const Divider(height: 40),
              Text(l10n.securityTitle,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                l10n.backupWarning,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _exportingBackup ? null : _exportBackup,
                icon: const Icon(Icons.backup_outlined),
                label: Text(
                  _exportingBackup
                      ? l10n.generatingBackup
                      : l10n.makeIdentityBackup,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.identityFileLabel,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _savedataPath == null ? null : _openSavedataFolder,
                      child: Text(
                        _savedataPath ?? l10n.loadingAction,
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
                    tooltip: l10n.openFolderTooltip,
                    onPressed:
                        _savedataPath == null ? null : _openSavedataFolder,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: l10n.copyPathTooltip,
                    onPressed: _savedataPath == null ? null : _copySavedataPath,
                  ),
                ],
              ),
              const Divider(height: 40),
              Text(l10n.accountTitle,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(l10n.usernameWithValue(widget.currentUsername),
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showRenameAccountDialog,
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.renameUsernameAction),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.password_outlined),
                label: Text(l10n.changePasswordAction),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout),
                label: Text(l10n.logoutAction),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showDeleteAccountDialog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(l10n.deleteAccountMenuAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
