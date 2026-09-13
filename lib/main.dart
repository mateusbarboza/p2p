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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'identity_backup.dart';
import 'l10n/app_localizations.dart';
import 'local_auth_screen.dart';
import 'onboarding_screen.dart';
import 'profile_screen.dart';
import 'providers/call_provider.dart';
import 'providers/contacts_provider.dart';
import 'providers/database_provider.dart';
import 'providers/file_transfers_provider.dart';
import 'providers/group_messages_provider.dart';
import 'providers/groups_provider.dart';
import 'providers/language_provider.dart';
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
    final language = ref.watch(languageProvider);

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
      locale: Locale(language.code),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
    // Uma chamada pode chegar (ToxCallIncomingEvent) com qualquer tela
    // aberta, ou nenhuma — mesmo raciocínio de sempre.
    ref.read(callProvider);
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
        // Mesmo que invalidar algum provider falhe, o retorno à tela de
        // login (widget.onLogout()) não pode ficar refém disso.
        try {
          _invalidateAccountScopedProviders();
        } finally {
          widget.onLogout();
        }
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
    ref.invalidate(callLogsRepositoryProvider);
    ref.invalidate(callProvider);
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
    final wrongPasswordMessage =
        AppLocalizations.of(context)!.errorWrongPassword;
    final removed = await widget.onDeleteAccountRecord(password);
    if (!removed) return wrongPasswordMessage;

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

  /// `true` enquanto o diálogo de "chamada recebida" está na tela — usado
  /// só pra fechá-lo sozinho se a chamada for encerrada por outro motivo
  /// (ex: quem ligou desistiu antes de atendermos).
  bool _incomingCallDialogShown = false;

  void _submitAddFriend() {
    final talksnapId = _talksnapIdController.text.trim().toUpperCase();
    if (talksnapId.length != kToxAddressSize * 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!
              .invalidTalksnapId(kToxAddressSize * 2)),
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
    final l10n = AppLocalizations.of(context)!;
    final groupName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.createGroupTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.groupNameLabel,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.pop(context, value.trim()),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.groupOfflineWarning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.createAction),
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
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            group.isFounder ? l10n.deleteGroupTitle : l10n.leaveGroupTitle),
        content: Text(
          group.isFounder
              ? l10n.deleteGroupBody(group.name)
              : l10n.leaveGroupBody(group.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(group.isFounder
                ? l10n.deleteGroupAction
                : l10n.leaveGroupAction),
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
    final l10n = AppLocalizations.of(context)!;
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
                  ? l10n.friendRequestSentToast
                  : l10n.friendRequestFailedToast(event.errorMessage ?? ''),
            ),
          ),
        );
        if (event.success) _talksnapIdController.clear();
      });
    });

    // Uma chamada recebida pode chegar com qualquer tela aberta —
    // HomeScreen fica montada o tempo todo enquanto logado, então é o
    // lugar certo pra pegar isso e mostrar o diálogo de atender/recusar.
    ref.listen(callProvider, (previous, next) {
      if (previous?.status != CallStatus.incomingRinging &&
          next.status == CallStatus.incomingRinging) {
        final publicKeyHex = next.contactPublicKeyHex;
        final callerName = ref
            .read(contactsProvider)
            .where((c) => c.publicKeyHex == publicKeyHex)
            .map((c) => c.displayName)
            .firstOrNull;
        _incomingCallDialogShown = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title:
                Text(l10n.incomingCallTitle(callerName ?? l10n.unknownContact)),
            content: Text(l10n.incomingCallBody),
            actions: [
              TextButton(
                onPressed: () {
                  ref.read(callProvider.notifier).hangUp();
                  Navigator.pop(context);
                },
                child: Text(l10n.rejectAction),
              ),
              TextButton.icon(
                onPressed: () {
                  ref.read(callProvider.notifier).answer(video: true);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.videocam),
                label: Text(l10n.answerWithVideoAction),
              ),
              FilledButton(
                onPressed: () {
                  ref.read(callProvider.notifier).answer();
                  Navigator.pop(context);
                },
                child: Text(l10n.answerAction),
              ),
            ],
          ),
        ).then((_) => _incomingCallDialogShown = false);
      } else if (previous?.status == CallStatus.incomingRinging &&
          next.status != CallStatus.incomingRinging &&
          _incomingCallDialogShown) {
        // Quem ligou desistiu (ou a chamada falhou) antes de respondermos
        // — fecha o diálogo sozinho em vez de deixá-lo preso na tela.
        _incomingCallDialogShown = false;
        Navigator.of(context).pop();
      }
    });

    final callState = ref.watch(callProvider);
    final contacts = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Talksnap'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: l10n.myProfileTooltip,
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
      body: Column(
        children: [
          if (callState.status != CallStatus.idle)
            _buildGlobalCallBar(callState, contacts),
          Expanded(
            child: _buildMainRowChildren(),
          ),
        ],
      ),
    );
  }

  /// Barra de chamada visível em QUALQUER tela (não só na conversa do
  /// contato) — sem isso, quem atende só teria acesso ao botão de mudo se
  /// tivesse aberto a conversa específica com quem ligou.
  Widget _buildGlobalCallBar(
      CallState callState, List<ContactViewModel> contacts) {
    final l10n = AppLocalizations.of(context)!;
    final contactName = contacts
            .where((c) => c.publicKeyHex == callState.contactPublicKeyHex)
            .map((c) => c.displayName)
            .firstOrNull ??
        l10n.unknownContact;
    final label = switch (callState.status) {
      CallStatus.outgoingRinging => l10n.callingContact(contactName),
      CallStatus.incomingRinging => l10n.incomingCallLabel(contactName),
      CallStatus.active => l10n.inCallWith(contactName),
      CallStatus.idle => '',
    };
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.call, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            if (callState.status != CallStatus.idle)
              IconButton(
                icon: Icon(callState.muted ? Icons.mic_off : Icons.mic),
                tooltip:
                    callState.muted ? l10n.unmuteTooltip : l10n.muteTooltip,
                onPressed: () => ref.read(callProvider.notifier).toggleMute(),
              ),
            if (callState.status != CallStatus.idle)
              IconButton(
                icon: Icon(
                  callState.videoSource == VideoSource.camera
                      ? Icons.videocam
                      : Icons.videocam_off,
                ),
                tooltip: callState.videoSource == VideoSource.camera
                    ? l10n.turnOffCameraTooltip
                    : l10n.turnOnCameraTooltip,
                onPressed: () => ref.read(callProvider.notifier).toggleVideo(),
              ),
            if (callState.status != CallStatus.idle)
              IconButton(
                icon: Icon(
                  callState.videoSource == VideoSource.screen
                      ? Icons.stop_screen_share
                      : Icons.screen_share,
                ),
                tooltip: callState.videoSource == VideoSource.screen
                    ? l10n.stopScreenShareTooltip
                    : l10n.startScreenShareTooltip,
                onPressed: () =>
                    ref.read(callProvider.notifier).toggleScreenShare(),
              ),
            IconButton(
              icon: const Icon(Icons.call_end),
              color: Colors.red,
              tooltip: l10n.hangUpTooltip,
              onPressed: () => ref.read(callProvider.notifier).hangUp(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainRowChildren() {
    final l10n = AppLocalizations.of(context)!;
    final selfProfile = ref.watch(selfProfileProvider);
    final selfStatus = ref.watch(selfStatusProvider);
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

    return Row(
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
                              : l10n.noNameFallback,
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
                    tooltip: l10n.changeStatusTooltip,
                    onSelected: (status) => ref
                        .read(selfProfileProvider.notifier)
                        .updateUserStatus(status),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                          value: kToxUserStatusNone,
                          child: Text(l10n.statusOnline)),
                      PopupMenuItem(
                          value: kToxUserStatusAway,
                          child: Text(l10n.statusAway)),
                      PopupMenuItem(
                          value: kToxUserStatusBusy,
                          child: Text(l10n.statusBusy)),
                    ],
                    child: _StatusBadge(
                      color: !isOnline
                          ? Colors.orange
                          : userStatusColor(selfProfile.userStatus),
                      label: !isOnline
                          ? _connectionLabel(l10n, selfStatus.connection)
                          : userStatusLabel(l10n, selfProfile.userStatus),
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
                      _showTalksnapId ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    label: Text(l10n.myIdAction),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(
                        () => _showAddContactForm = !_showAddContactForm),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: Text(l10n.addAction),
                  ),
                ],
              ),
              if (_showTalksnapId) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        selfStatus.talksnapId ?? l10n.generatingIdentity,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: l10n.copyId,
                      onPressed: selfStatus.talksnapId == null
                          ? null
                          : () => _copyTalksnapId(selfStatus.talksnapId!),
                    ),
                  ],
                ),
              ],
              if (_showAddContactForm) ...[
                const Divider(height: 32),
                Text(l10n.addContactTitle,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _talksnapIdController,
                  decoration: InputDecoration(
                    labelText: l10n.contactIdLabel,
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _greetingController,
                  decoration: InputDecoration(
                    labelText: l10n.greetingMessageLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _sendingFriendRequest ? null : _submitAddFriend,
                  icon: const Icon(Icons.person_add),
                  label: Text(_sendingFriendRequest
                      ? l10n.sendingAction
                      : l10n.sendFriendRequestAction),
                ),
              ],
              if (pendingRequests.isNotEmpty) ...[
                const Divider(height: 40),
                Text(l10n.receivedRequestsTitle,
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
                        child: Text(l10n.acceptAction),
                      ),
                    ),
                  ),
              ],
              const Divider(height: 40),
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.contactsCountTitle(contacts.length),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (contacts.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        _showContactSearch ? Icons.search_off : Icons.search,
                        size: 20,
                      ),
                      tooltip: l10n.searchContactTooltip,
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
                    hintText: l10n.searchContactTooltip,
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
                Text(l10n.noContactsYetHome)
              else if (filteredContacts.isEmpty)
                Text(l10n.noContactsFound)
              else
                for (final contact in filteredContacts)
                  _ContactTile(
                    contact: contact,
                    connectionLabel: contact.connection != ToxConnection.none
                        ? userStatusLabel(l10n, contact.userStatus)
                        : _connectionLabel(l10n, contact.connection),
                    selected:
                        _selectedContact?.publicKeyHex == contact.publicKeyHex,
                    onTap: () => _openChat(contact),
                    onRemove: () => _confirmRemoveContact(contact),
                  ),
              if (pendingGroupInvites.isNotEmpty) ...[
                const Divider(height: 40),
                Text(l10n.groupInvitesTitle,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final invite in pendingGroupInvites)
                  Card(
                    child: ListTile(
                      title: Text(invite.groupName),
                      subtitle: Text(l10n.inviteFromContact),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _rejectGroupInvite(invite),
                            child: Text(l10n.rejectAction),
                          ),
                          FilledButton(
                            onPressed: () => _acceptGroupInvite(invite),
                            child: Text(l10n.acceptAction),
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
                    child: Text(l10n.groupsCountTitle(groups.length),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.group_add_outlined, size: 20),
                    tooltip: l10n.createGroupTooltip,
                    onPressed: _createGroup,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (groups.isEmpty)
                Text(l10n.noGroupsYet)
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
                  ? Center(child: Text(l10n.selectContactPrompt))
                  : ChatScreen(
                      key: ValueKey(_selectedContact!.publicKeyHex),
                      contactPublicKeyHex: _selectedContact!.publicKeyHex,
                      contactLabel: _selectedContact!.displayName,
                    ),
        ),
      ],
    );
  }

  Future<void> _confirmRemoveContact(ContactViewModel contact) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeContactTitle),
        content: Text(l10n.removeContactBody(contact.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.removeAction),
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
      SnackBar(content: Text(AppLocalizations.of(context)!.talksnapIdCopied)),
    );
  }

  void _openChat(ContactViewModel contact) {
    setState(() {
      _selectedContact = contact;
      _selectedGroup = null;
    });
  }

  String _connectionLabel(AppLocalizations l10n, ToxConnection connection) {
    switch (connection) {
      case ToxConnection.udp:
        return l10n.onlineStatus;
      case ToxConnection.tcp:
        return l10n.onlineViaRelay;
      case ToxConnection.none:
        return l10n.offlineStatus;
    }
  }
}

/// Rótulo do status de presença (Online/Ausente/Ocupado) — função livre
/// porque tanto o cabeçalho do próprio usuário (_HomeScreenState) quanto a
/// listagem de contatos (_ContactTile) precisam dela.
String userStatusLabel(AppLocalizations l10n, int userStatus) {
  switch (userStatus) {
    case kToxUserStatusAway:
      return l10n.statusAway;
    case kToxUserStatusBusy:
      return l10n.statusBusy;
    case kToxUserStatusNone:
    default:
      return l10n.statusOnline;
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
    final l10n = AppLocalizations.of(context)!;
    final contact = widget.contact;
    final unreadCount =
        ref.watch(unreadMessagesCountProvider(contact.publicKeyHex));
    final callState = ref.watch(callProvider);
    final inCallWithContact = callState.status != CallStatus.idle &&
        callState.contactPublicKeyHex == contact.publicKeyHex;
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
          subtitle: inCallWithContact
              ? Text(l10n.inCallLabel,
                  style: const TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold))
              : contact.isTyping
                  ? Text(l10n.typingIndicator,
                      style: const TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold))
                  : contact.statusMessage?.isNotEmpty == true
                      ? Text(contact.statusMessage!)
                      : null,
          trailing: SizedBox(
            width: 28,
            height: 28,
            child: _hovering
                ? PopupMenuButton<void>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined,
                        size: 18),
                    tooltip: l10n.moreOptionsTooltip,
                    itemBuilder: (context) => [
                      PopupMenuItem<void>(
                        onTap: widget.onRemove,
                        child: Text(l10n.removeContactMenuAction),
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
    final l10n = AppLocalizations.of(context)!;
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
          subtitle: Text(l10n.membersCountLabel(memberCount + 1)),
          trailing: SizedBox(
            width: 28,
            height: 28,
            child: _hovering
                ? PopupMenuButton<void>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined,
                        size: 18),
                    tooltip: l10n.moreOptionsTooltip,
                    itemBuilder: (context) => [
                      PopupMenuItem<void>(
                        onTap: widget.onLeave,
                        child: Text(group.isFounder
                            ? l10n.deleteGroupMenuAction
                            : l10n.leaveGroupMenuAction),
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
