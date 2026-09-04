// local_auth_provider.dart
//
// Bloqueio LOCAL do app (usuário + senha) — não tem nenhuma relação com a
// identidade Tox nem viaja pela rede (o Talksnap é P2P puro, sem servidor
// de autenticação). Suporta VÁRIAS contas no mesmo dispositivo, cada uma
// com sua própria identidade Talksnap (savedata, contatos, mensagens,
// grupos, avatar) — como se fossem pessoas diferentes usando o mesmo PC.
// A lista de contas (usuário + hash salgado da senha) fica no
// SharedPreferences do DISPOSITIVO (ver dev_profile.dart); qual conta está
// ativa no momento é o que decide, via [setActiveAccountSlug], quais
// arquivos/banco cada conta enxerga.

import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:math' show Random;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dev_profile.dart';

final String _kAccountsKey = withDeviceSuffix('talksnap.localAccounts');

String _generateSlug() {
  final random = Random.secure();
  return List<int>.generate(8, (_) => random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

String _generateSalt() {
  final random = Random.secure();
  return List<int>.generate(16, (_) => random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

String _hashPassword(String password, String salt) {
  return sha256.convert(utf8.encode('$salt:$password')).toString();
}

/// Uma conta local — só a parte visível pra UI (nunca expõe hash/salt).
class LocalAccount {
  const LocalAccount({required this.slug, required this.username});
  final String slug;
  final String username;
}

class _StoredAccount {
  const _StoredAccount({
    required this.slug,
    required this.username,
    required this.passwordHash,
    required this.passwordSalt,
  });
  final String slug;
  final String username;
  final String passwordHash;
  final String passwordSalt;

  Map<String, String> toJson() => {
        'slug': slug,
        'username': username,
        'passwordHash': passwordHash,
        'passwordSalt': passwordSalt,
      };

  static _StoredAccount fromJson(Map<String, dynamic> json) => _StoredAccount(
        slug: json['slug'] as String,
        username: json['username'] as String,
        passwordHash: json['passwordHash'] as String,
        passwordSalt: json['passwordSalt'] as String,
      );
}

class LocalAuthState {
  const LocalAuthState({
    this.checking = true,
    this.accounts = const [],
    this.unlocked = false,
    this.activeAccount,
  });

  /// `true` enquanto ainda estamos lendo o SharedPreferences pela primeira
  /// vez — evita mostrar a lista de contas vazia por engano.
  final bool checking;

  final List<LocalAccount> accounts;

  /// Se alguma conta já foi destravada nesta execução do app.
  final bool unlocked;

  final LocalAccount? activeAccount;

  LocalAuthState copyWith({
    bool? checking,
    List<LocalAccount>? accounts,
    bool? unlocked,
    LocalAccount? activeAccount,
  }) {
    return LocalAuthState(
      checking: checking ?? this.checking,
      accounts: accounts ?? this.accounts,
      unlocked: unlocked ?? this.unlocked,
      activeAccount: activeAccount ?? this.activeAccount,
    );
  }
}

class LocalAuthNotifier extends Notifier<LocalAuthState> {
  List<_StoredAccount> _storedAccounts = const [];

  @override
  LocalAuthState build() {
    _load();
    return const LocalAuthState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccountsKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      _storedAccounts = decoded
          .map((e) => _StoredAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    state = state.copyWith(
      checking: false,
      accounts: _storedAccounts
          .map((a) => LocalAccount(slug: a.slug, username: a.username))
          .toList(),
    );
  }

  Future<void> _persistAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kAccountsKey,
      jsonEncode(_storedAccounts.map((a) => a.toJson()).toList()),
    );
  }

  /// Cria uma conta nova (identidade Talksnap própria) e já entra nela.
  Future<void> register(String username, String password) async {
    final slug = _generateSlug();
    final salt = _generateSalt();
    _storedAccounts = [
      ..._storedAccounts,
      _StoredAccount(
        slug: slug,
        username: username,
        passwordHash: _hashPassword(password, salt),
        passwordSalt: salt,
      ),
    ];
    await _persistAccounts();
    setActiveAccountSlug(slug);
    state = state.copyWith(
      accounts: [
        ...state.accounts,
        LocalAccount(slug: slug, username: username),
      ],
      unlocked: true,
      activeAccount: LocalAccount(slug: slug, username: username),
    );
  }

  /// Cria uma conta nova a partir de um backup de identidade (.tox)
  /// importado — [writeSavedata] é chamado depois que a conta já está
  /// ativa (para resolveSavedataFile() apontar pro lugar certo), antes de
  /// destravar de fato.
  Future<void> importAccount(
    String username,
    String password,
    Future<void> Function() writeSavedata,
  ) async {
    final slug = _generateSlug();
    final salt = _generateSalt();
    setActiveAccountSlug(slug);
    await writeSavedata();
    _storedAccounts = [
      ..._storedAccounts,
      _StoredAccount(
        slug: slug,
        username: username,
        passwordHash: _hashPassword(password, salt),
        passwordSalt: salt,
      ),
    ];
    await _persistAccounts();
    state = state.copyWith(
      accounts: [
        ...state.accounts,
        LocalAccount(slug: slug, username: username),
      ],
      unlocked: true,
      activeAccount: LocalAccount(slug: slug, username: username),
    );
  }

  /// Entra numa conta existente (identificada pelo slug — a UI mostra a
  /// lista de contas, não pede pra digitar usuário). Retorna `true` e
  /// destrava se a senha bater, `false` caso contrário.
  bool login(String slug, String password) {
    final account = _storedAccounts.where((a) => a.slug == slug).firstOrNull;
    if (account == null) return false;
    final matches =
        _hashPassword(password, account.passwordSalt) == account.passwordHash;
    if (matches) {
      setActiveAccountSlug(slug);
      state = state.copyWith(
        unlocked: true,
        activeAccount:
            LocalAccount(slug: account.slug, username: account.username),
      );
    }
    return matches;
  }

  /// Troca a senha da conta ATIVA no momento. Confere a senha atual antes
  /// de aceitar a nova — retorna `false` sem alterar nada se não bater.
  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    final activeSlug = state.activeAccount?.slug;
    if (activeSlug == null) return false;
    final index = _storedAccounts.indexWhere((a) => a.slug == activeSlug);
    if (index == -1) return false;

    final account = _storedAccounts[index];
    final currentMatches =
        _hashPassword(currentPassword, account.passwordSalt) ==
            account.passwordHash;
    if (!currentMatches) return false;

    final newSalt = _generateSalt();
    _storedAccounts = [
      ..._storedAccounts.sublist(0, index),
      _StoredAccount(
        slug: account.slug,
        username: account.username,
        passwordHash: _hashPassword(newPassword, newSalt),
        passwordSalt: newSalt,
      ),
      ..._storedAccounts.sublist(index + 1),
    ];
    await _persistAccounts();
    return true;
  }

  /// Renomeia a conta ATIVA no momento (só o usuário local de login — não
  /// mexe no nome do perfil Talksnap, que é outro campo, sincronizado com
  /// os contatos via toxcore).
  Future<void> renameAccount(String newUsername) async {
    final activeSlug = state.activeAccount?.slug;
    if (activeSlug == null) return;
    final index = _storedAccounts.indexWhere((a) => a.slug == activeSlug);
    if (index == -1) return;

    final account = _storedAccounts[index];
    _storedAccounts = [
      ..._storedAccounts.sublist(0, index),
      _StoredAccount(
        slug: account.slug,
        username: newUsername,
        passwordHash: account.passwordHash,
        passwordSalt: account.passwordSalt,
      ),
      ..._storedAccounts.sublist(index + 1),
    ];
    await _persistAccounts();
    state = state.copyWith(
      accounts: [
        for (final a in state.accounts)
          if (a.slug == activeSlug)
            LocalAccount(slug: activeSlug, username: newUsername)
          else
            a,
      ],
      activeAccount: LocalAccount(slug: activeSlug, username: newUsername),
    );
  }

  /// Apaga o REGISTRO local (usuário/senha) da conta ATIVA — confere a
  /// senha antes. Não mexe em savedata/banco/arquivos: isso é
  /// responsabilidade de quem chama (ver `_deleteAccountAndCleanUp` em
  /// main.dart), que precisa fazer isso ENQUANTO a conta ainda está ativa
  /// (pra `resolveSavedataFile()` continuar apontando pro lugar certo) e
  /// ANTES de efetivamente sair — por isso `unlocked`/`activeAccount` só
  /// são limpos depois, por [logout].
  Future<bool> deleteAccount(String password) async {
    final activeSlug = state.activeAccount?.slug;
    if (activeSlug == null) return false;
    final index = _storedAccounts.indexWhere((a) => a.slug == activeSlug);
    if (index == -1) return false;

    final account = _storedAccounts[index];
    final matches =
        _hashPassword(password, account.passwordSalt) == account.passwordHash;
    if (!matches) return false;

    _storedAccounts = [..._storedAccounts]..removeAt(index);
    await _persistAccounts();
    state = state.copyWith(
      accounts: state.accounts.where((a) => a.slug != activeSlug).toList(),
    );
    return true;
  }

  /// Trava o app de novo — volta pra tela de escolha de conta. As contas
  /// continuam salvas, só a sessão atual é encerrada.
  void logout() {
    setActiveAccountSlug(null);
    // copyWith não consegue "limpar" activeAccount (null significa "manter
    // o atual" lá) — reconstrói o estado direto pra garantir que some.
    state = LocalAuthState(
      checking: false,
      accounts: state.accounts,
    );
  }
}

final localAuthProvider = NotifierProvider<LocalAuthNotifier, LocalAuthState>(
  LocalAuthNotifier.new,
);
