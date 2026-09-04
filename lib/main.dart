// main.dart
//
// Tela de inicialização do Talksnap. Fluxo de dados, ponta a ponta:
//
//   toxcore (C)  --tox_iterate()-->  Isolate de rede (tox_isolate_manager)
//        |                                 |
//        |                    SendPort.send(ToxNetworkEvent)
//        v                                 v
//   memória nativa           StreamProvider (toxNetworkEventsProvider)
//                                          |
//                    Notifiers (contacts/pendingRequests/selfStatus)
//                                          |
//                              ref.watch() -> widgets redesenhados
//
// A partir da Fase 3, a UI não guarda mais estado de rede/contatos em
// StatefulWidget: cada Notifier (lib/providers/) escuta a stream de eventos
// e persiste o que precisa persistir (ver contacts_provider.dart). A UI só
// observa esses providers e manda comandos de volta pelo ToxIsolateManager.

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'identity_backup.dart';
import 'local_auth_screen.dart';
import 'onboarding_screen.dart';
import 'profile_screen.dart';
import 'providers/contacts_provider.dart';
import 'providers/database_provider.dart';
import 'providers/file_transfers_provider.dart';
import 'providers/group_messages_provider.dart';
import 'providers/groups_provider.dart';
import 'providers/local_auth_provider.dart';
import 'providers/messages_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/pending_group_invites_provider.dart';
import 'providers/pending_requests_provider.dart';
import 'providers/self_profile_provider.dart';
import 'providers/self_status_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'providers/tox_events_provider.dart';
import 'providers/tox_manager_provider.dart';
import 'tox_bindings.dart';
import 'tox_events.dart';
import 'welcome_choice_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Notificação nativa do Windows exige um atalho com AppUserModelID válido
  // — o próprio plugin cria esse atalho no menu iniciar se ainda não existir.
  await localNotifier.setup(appName: 'Talksnap');
  runApp(const ProviderScope(child: TalksnapApp()));
}

class TalksnapApp extends ConsumerWidget {
  const TalksnapApp({super.key});

  static const _seedColor = Color(0xFF2F6FED); // azul nostálgico, estilo MSN

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Talksnap',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode.flutterThemeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seedColor,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seedColor,
        brightness: Brightness.dark,
      ),
      home: const AppRoot(),
    );
  }
}

/// Decide qual tela mostrar assim que o app abre:
///   - splash, enquanto ainda não sabemos se já existe um savedata no disco;
///   - WelcomeChoiceScreen, se NENHUM savedata existe ainda — a única janela
///     de oportunidade para importar um backup em vez de deixar o toxcore
///     gerar uma identidade nova sozinho (ver welcome_choice_screen.dart);
///   - splash de novo, enquanto o perfil já existente está sendo lido;
///   - OnboardingScreen, se o nome ainda está vazio (identidade nova, sem
///     backup importado);
///   - HomeScreen, no dia a dia normal.
///
/// Também é aqui que os Notifiers "globais" (mensagens, arquivos, perfil)
/// são ativados pela primeira vez — mas só depois de decidido que é seguro
/// deixar o isolate de rede subir (ver [_startNetworking]).
class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Trava local de usuário/senha: portão mais externo de todos — não tem
    // relação com a identidade Tox, só protege o app neste dispositivo.
    final localAuth = ref.watch(localAuthProvider);
    if (localAuth.checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final activeAccount = localAuth.activeAccount;
    if (!localAuth.unlocked || activeAccount == null) {
      return const LocalAuthScreen();
    }

    // Cada conta local tem sua própria identidade Talksnap (savedata,
    // banco, isolate de rede) — trocar a `key` aqui derruba e recria todo
    // esse ProviderScope (fechando o isolate/banco da conta anterior via
    // os `ref.onDispose` já existentes) sempre que a conta ativa muda, sem
    // precisar reiniciar o processo inteiro.
    return ProviderScope(
      key: ValueKey(activeAccount.slug),
      // `onLogout` é um closure capturado deste `ref` (escopo raiz, fora do
      // ProviderScope aninhado abaixo) — repassado explicitamente em vez de
      // lido de novo lá dentro, porque um ProviderScope aninhado cria seu
      // próprio container: ler localAuthProvider por lá pegaria uma
      // instância separada, e o logout nunca chegaria a este notifier aqui.
      child: _AccountSessionRoot(
        currentUsername: activeAccount.username,
        onLogout: () => ref.read(localAuthProvider.notifier).logout(),
        onChangePassword: (currentPassword, newPassword) => ref
            .read(localAuthProvider.notifier)
            .changePassword(currentPassword, newPassword),
        onRenameAccount: (newUsername) =>
            ref.read(localAuthProvider.notifier).renameAccount(newUsername),
        onDeleteAccountRecord: (password) =>
            ref.read(localAuthProvider.notifier).deleteAccount(password),
      ),
    );
  }
}

/// Decide qual tela mostrar dentro de uma sessão de conta já destravada:
///   - splash, enquanto ainda não sabemos se já existe um savedata no disco;
///   - WelcomeChoiceScreen, se NENHUM savedata existe ainda — a única janela
///     de oportunidade para importar um backup em vez de deixar o toxcore
///     gerar uma identidade nova sozinho (ver welcome_choice_screen.dart);
///   - splash de novo, enquanto o perfil já existente está sendo lido;
///   - OnboardingScreen, se o nome ainda está vazio (identidade nova, sem
///     backup importado);
///   - HomeScreen, no dia a dia normal.
class _AccountSessionRoot extends ConsumerStatefulWidget {
  const _AccountSessionRoot({
    required this.currentUsername,
    required this.onLogout,
    required this.onChangePassword,
    required this.onRenameAccount,
    required this.onDeleteAccountRecord,
  });

  final String currentUsername;
  final VoidCallback onLogout;
  final Future<bool> Function(String currentPassword, String newPassword)
      onChangePassword;
  final Future<void> Function(String newUsername) onRenameAccount;

  /// Só apaga o REGISTRO local (usuário/senha) — verifica a senha e
  /// retorna `false` se não bater. A limpeza de arquivos e o logout de
  /// fato ficam por conta de [_AccountSessionRootState._deleteAccountAndCleanUp].
  final Future<bool> Function(String password) onDeleteAccountRecord;

  @override
  ConsumerState<_AccountSessionRoot> createState() =>
      _AccountSessionRootState();
}

class _AccountSessionRootState extends ConsumerState<_AccountSessionRoot> {
  bool _checkingIdentity = true;
  bool _networkingStarted = false;

  @override
  void initState() {
    super.initState();
    _checkExistingIdentity();
  }

  Future<void> _checkExistingIdentity() async {
    final file = await resolveSavedataFile();
    final exists = await file.exists();
    if (!mounted) return;
    setState(() => _checkingIdentity = false);
    if (exists) {
      _startNetworking();
    }
  }

  /// Só é seguro chamar isto depois de garantir que, se a intenção era
  /// importar um backup, os bytes já foram copiados para o caminho do
  /// savedata — o isolate de rede lê esse arquivo assim que sobe.
  void _startNetworking() {
    if (_networkingStarted) return;
    _networkingStarted = true;
    // Dispara o boot do isolate de rede uma única vez (FutureProvider já
    // cacheia — chamadas seguintes só reaproveitam o resultado).
    ref.read(toxNetworkStartupProvider);
    // IMPORTANTE: ativa a persistência de mensagens/arquivos/perfil aqui,
    // antes de qualquer tela específica — esses Notifiers escutam a stream
    // de eventos (broadcast, sem replay). Se nada os estiver observando no
    // instante em que um evento chega, ele se perde para sempre, mesmo que
    // o usuário abra a tela relevante logo em seguida.
    ref.read(messagesSyncProvider);
    ref.read(fileTransfersSyncProvider);
    ref.read(selfProfileProvider);
    // Mesmo problema vale para o Talksnap ID: ToxSelfStatusEvent chega logo
    // no boot do isolate, bem antes de qualquer tela (onboarding ou home)
    // ter chance de observar este provider pela primeira vez.
    ref.read(selfStatusProvider);
    // E, por consistência/segurança, os mesmos providers que hoje só a
    // HomeScreen observa — um pedido de amizade ou confirmação de conexão
    // podem chegar antes dela existir (ex: ainda na tela de onboarding).
    ref.read(contactsProvider);
    ref.read(pendingRequestsProvider);
    // Mesmo risco de perda de evento vale para grupos: um convite ou
    // mensagem de grupo pode chegar antes de qualquer tela de grupo existir.
    ref.read(groupsProvider);
    ref.read(groupMessagesSyncProvider);
    ref.read(pendingGroupInvitesProvider);
    // Notificação nativa ao chegar mensagem — mesmo raciocínio de sempre:
    // precisa estar ouvindo desde já, não só quando o chat estiver aberto.
    ref.read(notificationsProvider);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingIdentity) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_networkingStarted) {
      return WelcomeChoiceScreen(onIdentityReady: _startNetworking);
    }

    final selfProfile = ref.watch(selfProfileProvider);
    if (!selfProfile.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (selfProfile.name.isEmpty) {
      return const OnboardingScreen();
    }
    return HomeScreen(
      currentUsername: widget.currentUsername,
      onLogout: _logoutAndStopNetworking,
      onChangePassword: widget.onChangePassword,
      onRenameAccount: widget.onRenameAccount,
      onDeleteAccount: _deleteAccountAndCleanUp,
    );
  }

  /// Para o isolate de rede DESTA conta e reseta TODOS os providers
  /// específicos de conta antes de voltar pra tela de login.
  ///
  /// Dois problemas resolvidos aqui, os dois pela mesma causa: um provider
  /// comum do Riverpod (`Provider`/`NotifierProvider` sem `overrides`)
  /// sempre vive no container RAIZ — trocar a `key` do ProviderScope
  /// aninhado (ver AppRoot) reseta o WIDGET (`_AccountSessionRoot` reinicia
  /// `_checkingIdentity`/`_networkingStarted`), mas NÃO reseta esses
  /// providers, que continuam apontando pra mesma instância antiga (mesma
  /// conexão de banco, mesmo `ToxIsolateManager`) mesmo numa conta nova.
  /// Por isso: (1) sem parar o isolate explicitamente aqui, duas instâncias
  /// do toxcore concorreriam pelos mesmos recursos nativos; (2) sem
  /// invalidar os outros providers, a conta nova reaproveitaria em silêncio
  /// o banco/perfil/contatos da conta anterior, mesmo com savedata vazio.
  void _logoutAndStopNetworking() {
    unawaited(
      ref.read(toxIsolateManagerProvider).stop().then((_) {
        _invalidateAccountScopedProviders();
        widget.onLogout();
      }),
    );
  }

  void _invalidateAccountScopedProviders() {
    ref.invalidate(toxIsolateManagerProvider);
    ref.invalidate(toxNetworkStartupProvider);
    ref.invalidate(toxNetworkEventsProvider);
    ref.invalidate(appDatabaseProvider);
    ref.invalidate(contactsRepositoryProvider);
    ref.invalidate(messagesRepositoryProvider);
    ref.invalidate(fileTransfersRepositoryProvider);
    ref.invalidate(groupsRepositoryProvider);
    ref.invalidate(groupMessagesRepositoryProvider);
    ref.invalidate(groupMembersRepositoryProvider);
    ref.invalidate(groupInvitedContactsRepositoryProvider);
    ref.invalidate(contactsProvider);
    ref.invalidate(messagesSyncProvider);
    ref.invalidate(fileTransfersSyncProvider);
    ref.invalidate(selfProfileProvider);
    ref.invalidate(selfStatusProvider);
    ref.invalidate(pendingRequestsProvider);
    ref.invalidate(groupsProvider);
    ref.invalidate(groupMessagesSyncProvider);
    ref.invalidate(pendingGroupInvitesProvider);
    ref.invalidate(notificationsProvider);
  }

  /// Exclui a conta ativa: confere a senha, apaga os arquivos (savedata,
  /// banco, avatar) ENQUANTO ainda são desta conta, e só então volta pra
  /// tela de login. Retorna uma mensagem de erro (ex: senha incorreta) ou
  /// `null` em caso de sucesso.
  Future<String?> _deleteAccountAndCleanUp(String password) async {
    final removed = await widget.onDeleteAccountRecord(password);
    if (!removed) return 'Senha incorreta.';

    await ref.read(toxIsolateManagerProvider).stop();
    await deleteAccountFiles();
    _invalidateAccountScopedProviders();
    widget.onLogout();
    return null;
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.currentUsername,
    required this.onLogout,
    required this.onChangePassword,
    required this.onRenameAccount,
    required this.onDeleteAccount,
  });

  final String currentUsername;
  final VoidCallback onLogout;
  final Future<bool> Function(String currentPassword, String newPassword)
      onChangePassword;
  final Future<void> Function(String newUsername) onRenameAccount;
  final Future<String?> Function(String password) onDeleteAccount;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _talksnapIdController = TextEditingController();
  final TextEditingController _greetingController =
      TextEditingController(text: 'Vamos conversar no Talksnap!');
  final TextEditingController _contactSearchController =
      TextEditingController();
  bool _sendingFriendRequest = false;
  String _contactSearchQuery = '';

  /// Contato selecionado na coluna da esquerda — a conversa dele aparece
  /// no painel da direita (layout mestre-detalhe, como Skype/Discord),
  /// em vez de navegar para uma tela cheia separada.
  ContactViewModel? _selectedContact;

  /// Grupo selecionado — mutuamente exclusivo com [_selectedContact]: só um
  /// dos dois é mostrado no painel da direita por vez.
  GroupViewModel? _selectedGroup;
  bool _showTalksnapId = false;
  bool _showAddContactForm = false;
  bool _showContactSearch = false;

  void _submitAddFriend() {
    final talksnapId = _talksnapIdController.text.trim().toUpperCase();
    if (talksnapId.length != kToxAddressSize * 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Talksnap ID inválido: deve ter ${kToxAddressSize * 2} caracteres hex.'),
        ),
      );
      return;
    }
    setState(() => _sendingFriendRequest = true);
    ref
        .read(toxIsolateManagerProvider)
        .addFriend(talksnapId, message: _greetingController.text.trim());
  }

  void _acceptRequest(PendingFriendRequest request) {
    ref
        .read(pendingRequestsProvider.notifier)
        .removeByPublicKey(request.publicKeyHex);
    ref
        .read(toxIsolateManagerProvider)
        .acceptFriendRequest(request.publicKeyHex);
  }

  void _acceptGroupInvite(PendingGroupInvite invite) {
    ref.read(pendingGroupInvitesProvider.notifier).remove(invite);
    ref
        .read(toxIsolateManagerProvider)
        .acceptGroupInvite(invite.fromPublicKeyHex, invite.inviteData);
  }

  void _rejectGroupInvite(PendingGroupInvite invite) {
    ref.read(pendingGroupInvitesProvider.notifier).remove(invite);
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final groupName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Criar grupo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome do grupo',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    if (groupName == null || groupName.isEmpty) return;
    ref.read(toxIsolateManagerProvider).createGroup(groupName);
  }

  Future<void> _confirmLeaveGroup(GroupViewModel group) async {
    // Num grupo P2P sem servidor não existe "apagar para todos" — mesmo o
    // fundador só consegue sair do grupo localmente; os demais membros
    // continuam com o grupo deles normalmente. A ação por baixo
    // (LeaveGroupCommand) é a mesma, só o rótulo muda.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(group.isFounder ? 'Excluir grupo?' : 'Sair do grupo?'),
        content: Text(
          group.isFounder
              ? 'Você excluirá "${group.name}" da sua lista e perderá o histórico local dele. Os outros membros continuam com o grupo deles normalmente.'
              : 'Você sairá de "${group.name}" e perderá o histórico local dele.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(group.isFounder ? 'Excluir' : 'Sair'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (_selectedGroup?.chatIdHex == group.chatIdHex) {
        setState(() => _selectedGroup = null);
      }
      ref.read(toxIsolateManagerProvider).leaveGroup(group.chatIdHex);
    }
  }

  void _openGroupChat(GroupViewModel group) {
    setState(() {
      _selectedGroup = group;
      _selectedContact = null;
    });
  }

  @override
  void dispose() {
    _talksnapIdController.dispose();
    _greetingController.dispose();
    _contactSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mostra o resultado de um AddFriendCommand (sucesso/falha) como toast,
    // e limpa o campo de texto e o spinner do botão quando resolve.
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) {
        if (event is! ToxFriendAddResultEvent) return;
        setState(() => _sendingFriendRequest = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              event.success
                  ? 'Pedido de amizade enviado!'
                  : 'Falha ao adicionar contato: ${event.errorMessage}',
            ),
          ),
        );
        if (event.success) _talksnapIdController.clear();
      });
    });

    final selfStatus = ref.watch(selfStatusProvider);
    final selfProfile = ref.watch(selfProfileProvider);
    final pendingRequests = ref.watch(pendingRequestsProvider);
    final contacts = ref.watch(contactsProvider);
    final groups = ref.watch(groupsProvider);
    final pendingGroupInvites = ref.watch(pendingGroupInvitesProvider);
    final bool isOnline = selfStatus.connection != ToxConnection.none;

    final query = _contactSearchQuery.trim().toLowerCase();
    final filteredContacts = query.isEmpty
        ? contacts
        : contacts
            .where((contact) =>
                contact.displayName.toLowerCase().contains(query) ||
                contact.publicKeyHex.toLowerCase().contains(query))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Talksnap'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Meu perfil',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ProfileScreen(
                  currentUsername: widget.currentUsername,
                  onLogout: widget.onLogout,
                  onChangePassword: widget.onChangePassword,
                  onRenameAccount: widget.onRenameAccount,
                  onDeleteAccount: widget.onDeleteAccount,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: selfProfile.avatarPath != null
                          ? FileImage(File(selfProfile.avatarPath!))
                          : null,
                      child: selfProfile.avatarPath == null
                          ? const Icon(Icons.person, size: 32)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            selfProfile.name.isNotEmpty
                                ? selfProfile.name
                                : 'Sem nome',
                            style: Theme.of(context).textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (selfProfile.statusMessage.isNotEmpty)
                            Text(
                              selfProfile.statusMessage,
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<int>(
                      tooltip: 'Mudar status',
                      onSelected: (status) => ref
                          .read(selfProfileProvider.notifier)
                          .updateUserStatus(status),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                            value: kToxUserStatusNone, child: Text('Online')),
                        PopupMenuItem(
                            value: kToxUserStatusAway, child: Text('Ausente')),
                        PopupMenuItem(
                            value: kToxUserStatusBusy, child: Text('Ocupado')),
                      ],
                      child: _StatusBadge(
                        color: !isOnline
                            ? Colors.orange
                            : userStatusColor(selfProfile.userStatus),
                        label: !isOnline
                            ? _connectionLabel(selfStatus.connection)
                            : userStatusLabel(selfProfile.userStatus),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _showTalksnapId = !_showTalksnapId),
                      icon: Icon(
                        _showTalksnapId
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                      ),
                      label: const Text('Meu ID'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => setState(
                          () => _showAddContactForm = !_showAddContactForm),
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('Adicionar'),
                    ),
                  ],
                ),
                if (_showTalksnapId) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          selfStatus.talksnapId ?? 'Gerando identidade P2P...',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Copiar ID',
                        onPressed: selfStatus.talksnapId == null
                            ? null
                            : () => _copyTalksnapId(selfStatus.talksnapId!),
                      ),
                    ],
                  ),
                ],
                if (_showAddContactForm) ...[
                  const Divider(height: 32),
                  Text('Adicionar contato',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _talksnapIdController,
                    decoration: const InputDecoration(
                      labelText: 'Talksnap ID do contato',
                      border: OutlineInputBorder(),
                    ),
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _greetingController,
                    decoration: const InputDecoration(
                      labelText: 'Mensagem de apresentação',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _sendingFriendRequest ? null : _submitAddFriend,
                    icon: const Icon(Icons.person_add),
                    label: Text(_sendingFriendRequest
                        ? 'Enviando...'
                        : 'Enviar pedido de amizade'),
                  ),
                ],
                if (pendingRequests.isNotEmpty) ...[
                  const Divider(height: 40),
                  Text('Pedidos recebidos',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final request in pendingRequests)
                    Card(
                      child: ListTile(
                        title: Text(
                          request.publicKeyHex,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11),
                        ),
                        subtitle: Text(request.message),
                        trailing: FilledButton(
                          onPressed: () => _acceptRequest(request),
                          child: const Text('Aceitar'),
                        ),
                      ),
                    ),
                ],
                const Divider(height: 40),
                Row(
                  children: [
                    Expanded(
                      child: Text('Contatos (${contacts.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    if (contacts.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          _showContactSearch ? Icons.search_off : Icons.search,
                          size: 20,
                        ),
                        tooltip: 'Buscar contato',
                        onPressed: () => setState(() {
                          _showContactSearch = !_showContactSearch;
                          if (!_showContactSearch) {
                            _contactSearchController.clear();
                            _contactSearchQuery = '';
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_showContactSearch && contacts.isNotEmpty) ...[
                  TextField(
                    controller: _contactSearchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Buscar contato',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _contactSearchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _contactSearchController.clear();
                                setState(() => _contactSearchQuery = '');
                              },
                            ),
                    ),
                    onChanged: (value) =>
                        setState(() => _contactSearchQuery = value),
                  ),
                  const SizedBox(height: 8),
                ],
                if (contacts.isEmpty)
                  const Text('Nenhum contato ainda.')
                else if (filteredContacts.isEmpty)
                  const Text('Nenhum contato encontrado.')
                else
                  for (final contact in filteredContacts)
                    _ContactTile(
                      contact: contact,
                      connectionLabel: contact.connection != ToxConnection.none
                          ? userStatusLabel(contact.userStatus)
                          : _connectionLabel(contact.connection),
                      selected: _selectedContact?.publicKeyHex ==
                          contact.publicKeyHex,
                      onTap: () => _openChat(contact),
                      onRemove: () => _confirmRemoveContact(contact),
                    ),
                if (pendingGroupInvites.isNotEmpty) ...[
                  const Divider(height: 40),
                  Text('Convites de grupo',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final invite in pendingGroupInvites)
                    Card(
                      child: ListTile(
                        title: Text(invite.groupName),
                        subtitle: const Text('Convite de um contato'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _rejectGroupInvite(invite),
                              child: const Text('Recusar'),
                            ),
                            FilledButton(
                              onPressed: () => _acceptGroupInvite(invite),
                              child: const Text('Aceitar'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const Divider(height: 40),
                Row(
                  children: [
                    Expanded(
                      child: Text('Grupos (${groups.length})',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.group_add_outlined, size: 20),
                      tooltip: 'Criar grupo',
                      onPressed: _createGroup,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (groups.isEmpty)
                  const Text('Nenhum grupo ainda.')
                else
                  for (final group in groups)
                    _GroupTile(
                      group: group,
                      selected: _selectedGroup?.chatIdHex == group.chatIdHex,
                      onTap: () => _openGroupChat(group),
                      onLeave: () => _confirmLeaveGroup(group),
                    ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedGroup != null
                ? GroupChatScreen(
                    key: ValueKey(_selectedGroup!.chatIdHex),
                    chatIdHex: _selectedGroup!.chatIdHex,
                    groupName: _selectedGroup!.name,
                    contacts: contacts,
                  )
                : _selectedContact == null
                    ? const Center(
                        child: Text('Selecione um contato para conversar'))
                    : ChatScreen(
                        key: ValueKey(_selectedContact!.publicKeyHex),
                        contactPublicKeyHex: _selectedContact!.publicKeyHex,
                        contactLabel: _selectedContact!.displayName,
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveContact(ContactViewModel contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover contato?'),
        content: Text(
          '${contact.displayName} será removido dos seus contatos. Essa ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(toxIsolateManagerProvider).removeFriend(contact.publicKeyHex);
    }
  }

  void _copyTalksnapId(String talksnapId) {
    Clipboard.setData(ClipboardData(text: talksnapId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Talksnap ID copiado!')),
    );
  }

  void _openChat(ContactViewModel contact) {
    setState(() {
      _selectedContact = contact;
      _selectedGroup = null;
    });
  }

  String _connectionLabel(ToxConnection connection) {
    switch (connection) {
      case ToxConnection.udp:
        return 'Online';
      case ToxConnection.tcp:
        return 'Online (via relay)';
      case ToxConnection.none:
        return 'Offline';
    }
  }
}

/// Rótulo do status de presença (Online/Ausente/Ocupado) — função livre
/// porque tanto o cabeçalho do próprio usuário (_HomeScreenState) quanto a
/// listagem de contatos (_ContactTile) precisam dela.
String userStatusLabel(int userStatus) {
  switch (userStatus) {
    case kToxUserStatusAway:
      return 'Ausente';
    case kToxUserStatusBusy:
      return 'Ocupado';
    case kToxUserStatusNone:
    default:
      return 'Online';
  }
}

/// Cor do status de presença (verde/amarelo/vermelho) — mesmo raciocínio de
/// [userStatusLabel].
Color userStatusColor(int userStatus) {
  switch (userStatus) {
    case kToxUserStatusAway:
      return Colors.amber;
    case kToxUserStatusBusy:
      return Colors.red;
    case kToxUserStatusNone:
    default:
      return Colors.green;
  }
}

/// Linha de contato com um botão de ações que só aparece ao passar o
/// mouse por cima — mesmo padrão usado nas bolhas de mensagem/arquivo do
/// chat (ver _HoverDeleteWrapper em chat_screen.dart), pra manter a lista
/// limpa sem um ícone de remover sempre visível ao lado de cada contato.
class _ContactTile extends ConsumerStatefulWidget {
  const _ContactTile({
    required this.contact,
    required this.connectionLabel,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  final ContactViewModel contact;
  final String connectionLabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  ConsumerState<_ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends ConsumerState<_ContactTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final unreadCount =
        ref.watch(unreadMessagesCountProvider(contact.publicKeyHex)).value ?? 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Card(
        color: widget.selected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        child: ListTile(
          onTap: widget.onTap,
          leading: Icon(
            Icons.circle,
            size: 12,
            color: contact.connection != ToxConnection.none
                ? userStatusColor(contact.userStatus)
                : Colors.grey,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  contact.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: contact.displayName == contact.publicKeyHex
                      ? const TextStyle(fontFamily: 'monospace', fontSize: 11)
                      : null,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 6),
                _UnreadBadge(count: unreadCount),
              ],
            ],
          ),
          subtitle: Text(
            contact.statusMessage?.isNotEmpty == true
                ? '${widget.connectionLabel} · ${contact.statusMessage}'
                : widget.connectionLabel,
          ),
          trailing: SizedBox(
            width: 28,
            height: 28,
            child: _hovering
                ? PopupMenuButton<void>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined,
                        size: 18),
                    tooltip: 'Mais opções',
                    itemBuilder: (context) => [
                      PopupMenuItem<void>(
                        onTap: widget.onRemove,
                        child: const Text('Remover contato'),
                      ),
                    ],
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// Círculo vermelho com o número de mensagens não lidas — mesmo padrão
/// visual de badge de notificação usado em apps de mensagem.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: const BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Linha de grupo — mesmo padrão hover+`PopupMenuButton` de `_ContactTile`.
class _GroupTile extends ConsumerStatefulWidget {
  const _GroupTile({
    required this.group,
    required this.selected,
    required this.onTap,
    required this.onLeave,
  });

  final GroupViewModel group;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLeave;

  @override
  ConsumerState<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends ConsumerState<_GroupTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    // Roster persistido (sobrevive a reinício) em vez de group.members.length
    // (só reflete quem já reconectou nesta sessão) — sem isso, a contagem
    // voltaria a "1" toda vez que o app reabre.
    final rosterCount =
        ref.watch(groupRosterProvider(group.chatIdHex)).value?.length ??
            group.members.length;
    final memberCount =
        rosterCount > group.members.length ? rosterCount : group.members.length;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Card(
        color: widget.selected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        child: ListTile(
          onTap: widget.onTap,
          leading: const Icon(Icons.groups_outlined),
          title: Text(group.name),
          subtitle: Text('${memberCount + 1} membro(s)'),
          trailing: SizedBox(
            width: 28,
            height: 28,
            child: _hovering
                ? PopupMenuButton<void>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined,
                        size: 18),
                    tooltip: 'Mais opções',
                    itemBuilder: (context) => [
                      PopupMenuItem<void>(
                        onTap: widget.onLeave,
                        child: Text(group.isFounder
                            ? 'Excluir grupo'
                            : 'Sair do grupo'),
                      ),
                    ],
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
