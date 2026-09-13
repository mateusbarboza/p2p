// local_auth_screen.dart
//
// Portão de entrada do app: escolha ("Criar conta" / "Entrar" / "Importar")
// seguida do formulário correspondente. É só uma trava LOCAL — nada aqui
// viaja pela rede P2P. Cada conta local criada/importada tem sua própria
// identidade Talksnap (savedata, contatos, mensagens, grupos, avatar), como
// se fossem pessoas diferentes usando o mesmo dispositivo (ver
// providers/local_auth_provider.dart e dev_profile.dart).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'identity_backup.dart';
import 'l10n/app_localizations.dart';
import 'providers/local_auth_provider.dart';

enum _Mode { choice, register, login, import }

class LocalAuthScreen extends ConsumerStatefulWidget {
  const LocalAuthScreen({super.key});

  @override
  ConsumerState<LocalAuthScreen> createState() => _LocalAuthScreenState();
}

class _LocalAuthScreenState extends ConsumerState<LocalAuthScreen> {
  _Mode _mode = _Mode.choice;
  LocalAccount? _selectedAccount;
  String? _pickedBackupPath;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _usernameController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    _selectedAccount = null;
    _pickedBackupPath = null;
    _error = null;
  }

  void _goTo(_Mode mode) {
    setState(() {
      _resetForm();
      _mode = mode;
    });
  }

  Future<void> _submitRegister() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    final l10n = AppLocalizations.of(context)!;
    if (username.isEmpty) {
      setState(() => _error = l10n.errorEnterUsername);
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = l10n.errorEnterPassword);
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = l10n.errorPasswordsDontMatch);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    await ref.read(localAuthProvider.notifier).register(username, password);
  }

  Future<void> _pickBackupFile() async {
    final file = await FilePicker.pickFile();
    if (file?.path == null) return;
    setState(() => _pickedBackupPath = file!.path);
  }

  Future<void> _submitImport() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final backupPath = _pickedBackupPath;
    final l10n = AppLocalizations.of(context)!;

    if (backupPath == null) {
      setState(() => _error = l10n.errorChooseBackupFile);
      return;
    }
    if (username.isEmpty) {
      setState(() => _error = l10n.errorEnterUsername);
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = l10n.errorEnterPassword);
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = l10n.errorPasswordsDontMatch);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final backupBytes = await File(backupPath).readAsBytes();
      await ref.read(localAuthProvider.notifier).importAccount(
        username,
        password,
        () async {
          final savedataFile = await resolveSavedataFile();
          await savedataFile.parent.create(recursive: true);
          await savedataFile.writeAsBytes(backupBytes, flush: true);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = l10n.errorImportFailed(e.toString());
      });
    }
  }

  Future<void> _submitLogin() async {
    final account = _selectedAccount;
    if (account == null) return;
    final password = _passwordController.text;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok =
        ref.read(localAuthProvider.notifier).login(account.slug, password);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (!ok) _error = AppLocalizations.of(context)!.errorWrongPassword;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: switch (_mode) {
              _Mode.choice => _buildChoice(context),
              _Mode.register => _buildRegisterForm(context),
              _Mode.login => _buildLoginForm(context),
              _Mode.import => _buildImportForm(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _backButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        onPressed: _submitting ? null : () => _goTo(_Mode.choice),
        icon: const Icon(Icons.arrow_back),
      ),
    );
  }

  Widget _buildChoice(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasAccounts = ref.watch(localAuthProvider).accounts.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_person_outlined, size: 48),
        const SizedBox(height: 16),
        Text(
          l10n.welcomeTitle,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.localPasswordNotice,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _goTo(_Mode.register),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(l10n.createAccount),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hasAccounts ? () => _goTo(_Mode.login) : null,
                icon: const Icon(Icons.login),
                label: Text(l10n.signIn),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _goTo(_Mode.import),
                icon: const Icon(Icons.file_upload_outlined),
                label: Text(l10n.importAction),
              ),
            ),
          ],
        ),
        if (!hasAccounts) ...[
          const SizedBox(height: 8),
          Text(
            l10n.noAccountsYet,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildRegisterForm(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _backButton(),
        Text(l10n.createAccount,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: l10n.usernameLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: l10n.passwordLabel,
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          decoration: InputDecoration(
            labelText: l10n.confirmPasswordLabel,
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
          onSubmitted: (_) => _submitRegister(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _submitRegister,
          child: Text(_submitting ? l10n.pleaseWait : l10n.createAccount),
        ),
      ],
    );
  }

  Widget _buildImportForm(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _backButton(),
        Text(l10n.importIdentityTitle,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          l10n.importIdentityDescription,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _pickBackupFile,
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(
            _pickedBackupPath == null
                ? l10n.chooseToxFile
                : _pickedBackupPath!.split(Platform.pathSeparator).last,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: l10n.usernameLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: l10n.passwordLabel,
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          decoration: InputDecoration(
            labelText: l10n.confirmPasswordLabel,
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
          onSubmitted: (_) => _submitImport(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _submitImport,
          child: Text(_submitting ? l10n.importing : l10n.importAction),
        ),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accounts = ref.watch(localAuthProvider).accounts;
    final selected = _selectedAccount;

    if (selected == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _backButton(),
          Text(l10n.chooseAccount,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          for (final account in accounts)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(account.username),
                onTap: () => setState(() => _selectedAccount = account),
              ),
            ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                      _selectedAccount = null;
                      _error = null;
                      _passwordController.clear();
                    }),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        Text(selected.username,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        TextField(
          controller: _passwordController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.passwordLabel,
            border: const OutlineInputBorder(),
          ),
          obscureText: true,
          onSubmitted: (_) => _submitLogin(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _submitLogin,
          child: Text(_submitting ? l10n.pleaseWait : l10n.signIn),
        ),
      ],
    );
  }
}
