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

    if (username.isEmpty) {
      setState(() => _error = 'Informe um usuário.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Informe uma senha.');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = 'As senhas não coincidem.');
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

    if (backupPath == null) {
      setState(() => _error = 'Escolha o arquivo de backup (.tox).');
      return;
    }
    if (username.isEmpty) {
      setState(() => _error = 'Informe um usuário.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Informe uma senha.');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = 'As senhas não coincidem.');
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
        _error = 'Não foi possível importar esse arquivo: $e';
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
      if (!ok) _error = 'Senha incorreta.';
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
    final hasAccounts = ref.watch(localAuthProvider).accounts.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_person_outlined, size: 48),
        const SizedBox(height: 16),
        Text(
          'Bem-vindo(a) ao Talksnap',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Essa senha só protege o app neste dispositivo, não tem relação '
          'com sua identidade P2P nem viaja pela rede.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _goTo(_Mode.register),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Criar conta'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: hasAccounts ? () => _goTo(_Mode.login) : null,
                icon: const Icon(Icons.login),
                label: const Text('Entrar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _goTo(_Mode.import),
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Importar'),
              ),
            ),
          ],
        ),
        if (!hasAccounts) ...[
          const SizedBox(height: 8),
          Text(
            'Nenhuma conta cadastrada ainda neste dispositivo.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildRegisterForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _backButton(),
        Text('Criar conta', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Usuário',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'Senha',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          decoration: const InputDecoration(
            labelText: 'Confirmar senha',
            border: OutlineInputBorder(),
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
          child: Text(_submitting ? 'Aguarde...' : 'Criar conta'),
        ),
      ],
    );
  }

  Widget _buildImportForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _backButton(),
        Text('Importar identidade',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Escolha o arquivo de backup (.tox) trazido de outro dispositivo e '
          'defina um usuário/senha locais para proteger o acesso a ele aqui.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _pickBackupFile,
          icon: const Icon(Icons.folder_open_outlined),
          label: Text(
            _pickedBackupPath == null
                ? 'Escolher arquivo .tox'
                : _pickedBackupPath!.split(Platform.pathSeparator).last,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Usuário',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'Senha',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          decoration: const InputDecoration(
            labelText: 'Confirmar senha',
            border: OutlineInputBorder(),
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
          child: Text(_submitting ? 'Importando...' : 'Importar'),
        ),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    final accounts = ref.watch(localAuthProvider).accounts;
    final selected = _selectedAccount;

    if (selected == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _backButton(),
          Text('Escolha uma conta',
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
          decoration: const InputDecoration(
            labelText: 'Senha',
            border: OutlineInputBorder(),
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
          child: Text(_submitting ? 'Aguarde...' : 'Entrar'),
        ),
      ],
    );
  }
}
