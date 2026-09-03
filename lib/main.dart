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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_screen.dart';
import 'profile_screen.dart';
import 'providers/contacts_provider.dart';
import 'providers/file_transfers_provider.dart';
import 'providers/messages_provider.dart';
import 'providers/pending_requests_provider.dart';
import 'providers/self_profile_provider.dart';
import 'providers/self_status_provider.dart';
import 'providers/tox_events_provider.dart';
import 'providers/tox_manager_provider.dart';
import 'tox_bindings.dart';
import 'tox_events.dart';

void main() {
  runApp(const ProviderScope(child: TalksnapApp()));
}

class TalksnapApp extends StatelessWidget {
  const TalksnapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Talksnap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2F6FED), // azul nostálgico, estilo MSN
        brightness: Brightness.light,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _talksnapIdController = TextEditingController();
  final TextEditingController _greetingController =
      TextEditingController(text: 'Vamos conversar no Talksnap!');
  bool _sendingFriendRequest = false;

  /// Contato selecionado na coluna da esquerda — a conversa dele aparece
  /// no painel da direita (layout mestre-detalhe, como Skype/Discord),
  /// em vez de navegar para uma tela cheia separada.
  ContactViewModel? _selectedContact;
  bool _showTalksnapId = false;
  bool _showAddContactForm = false;

  @override
  void initState() {
    super.initState();
    // Dispara o boot do isolate de rede uma única vez (FutureProvider já
    // cacheia — chamadas seguintes só reaproveitam o resultado).
    ref.read(toxNetworkStartupProvider);
    // IMPORTANTE: ativa a persistência de mensagens/arquivos aqui, na tela
    // inicial, e não só quando uma tela de chat é aberta. Esses Notifiers
    // escutam a stream de eventos (broadcast, sem replay) — se nada os
    // estiver observando no instante em que uma mensagem/arquivo chega, o
    // evento se perde para sempre, mesmo que o usuário abra a conversa
    // logo em seguida.
    ref.read(messagesSyncProvider);
    ref.read(fileTransfersSyncProvider);
    // Mesmo motivo: se nada observar o perfil próprio antes do evento de
    // boot chegar, o nome/status salvos anteriormente nunca aparecem na UI.
    ref.read(selfProfileProvider);
  }

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

  @override
  void dispose() {
    _talksnapIdController.dispose();
    _greetingController.dispose();
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
    final bool isOnline = selfStatus.connection != ToxConnection.none;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Talksnap'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Meu perfil',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
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
                    _StatusBadge(
                      isOnline: isOnline,
                      label: _connectionLabel(selfStatus.connection),
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
                Text('Contatos (${contacts.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (contacts.isEmpty)
                  const Text('Nenhum contato ainda.')
                else
                  for (final contact in contacts)
                    _ContactTile(
                      contact: contact,
                      connectionLabel: _connectionLabel(contact.connection),
                      selected: _selectedContact?.publicKeyHex ==
                          contact.publicKeyHex,
                      onTap: () => _openChat(contact),
                      onRemove: () => _confirmRemoveContact(contact),
                    ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedContact == null
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
    setState(() => _selectedContact = contact);
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

/// Linha de contato com um botão de ações que só aparece ao passar o
/// mouse por cima — mesmo padrão usado nas bolhas de mensagem/arquivo do
/// chat (ver _HoverDeleteWrapper em chat_screen.dart), pra manter a lista
/// limpa sem um ícone de remover sempre visível ao lado de cada contato.
class _ContactTile extends StatefulWidget {
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
  State<_ContactTile> createState() => _ContactTileState();
}

class _ContactTileState extends State<_ContactTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
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
                ? Colors.green
                : Colors.grey,
          ),
          title: Text(
            contact.displayName,
            style: contact.displayName == contact.publicKeyHex
                ? const TextStyle(fontFamily: 'monospace', fontSize: 11)
                : null,
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isOnline, required this.label});

  final bool isOnline;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color:
            (isOnline ? Colors.green : Colors.orange).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.orange,
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
