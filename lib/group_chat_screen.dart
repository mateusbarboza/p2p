// group_chat_screen.dart
//
// Conversa em grupo (NGC). Mais simples que chat_screen.dart nesta primeira
// rodada: sem anexos e sem apagar mensagem — cada mensagem recebida mostra
// o nome de quem enviou (necessário aqui, diferente do 1:1, onde já se sabe
// quem é o outro lado). Painel de membros expansível, com "Convidar
// contato" abrindo a lista de contatos já existentes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart' show GroupMessage;
import 'date_divider.dart';
import 'l10n/app_localizations.dart';
import 'providers/contacts_provider.dart' show ContactViewModel;
import 'providers/group_messages_provider.dart';
import 'providers/groups_provider.dart';
import 'providers/spell_check_provider.dart';
import 'providers/tox_events_provider.dart';
import 'providers/tox_manager_provider.dart';
import 'tox_bindings.dart' show ToxConnection;
import 'tox_events.dart';

class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.chatIdHex,
    required this.groupName,
    required this.contacts,
  });

  final String chatIdHex;
  final String groupName;

  /// Contatos disponíveis para convidar — passado pelo HomeScreen, que já
  /// observa contactsProvider.
  final List<ContactViewModel> contacts;

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  bool _showMembers = false;

  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    ref
        .read(toxIsolateManagerProvider)
        .sendGroupMessage(widget.chatIdHex, text);
    _messageController.clear();
  }

  Future<void> _inviteContact() async {
    final knownMemberKeys =
        ref.read(groupKnownMemberKeysProvider(widget.chatIdHex)).value ??
            const <String>{};
    final invitableContacts = widget.contacts
        .where((contact) => !knownMemberKeys.contains(contact.publicKeyHex))
        .toList();

    final l10n = AppLocalizations.of(context)!;
    final selected = await showDialog<ContactViewModel>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.inviteContact),
        children: [
          if (invitableContacts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(l10n.noContactsToInvite),
            ),
          for (final contact in invitableContacts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, contact),
              child: Text(contact.displayName),
            ),
        ],
      ),
    );
    if (selected == null) return;
    ref
        .read(toxIsolateManagerProvider)
        .inviteToGroup(widget.chatIdHex, selected.publicKeyHex);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) {
        if (event is ToxGroupMessageSentEvent &&
            !event.success &&
            event.chatIdHex == widget.chatIdHex) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    l10n.errorSendMessageFailed(event.errorMessage ?? ''))),
          );
        }
      });
    });

    final group = ref
        .watch(groupsProvider)
        .where((g) => g.chatIdHex == widget.chatIdHex)
        .firstOrNull;
    // Garante que o provider de membros conhecidos já está ativo/observado
    // antes de _inviteContact precisar do valor mais recente dele.
    ref.watch(groupKnownMemberKeysProvider(widget.chatIdHex));
    // Roster persistido (sobrevive a reinício) — sem isso, o painel fica
    // vazio até cada peer reconectar e disparar group_peer_join de novo
    // nesta sessão, mesmo que a contagem já mostre o número certo.
    final roster =
        ref.watch(groupRosterProvider(widget.chatIdHex)).value ?? const [];
    final liveByPublicKey = {
      for (final member in group?.members ?? const [])
        if (member.publicKeyHex != null) member.publicKeyHex!: member,
    };
    final messagesAsync =
        ref.watch(groupChatMessagesProvider(widget.chatIdHex));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          IconButton(
            icon: Icon(_showMembers ? Icons.people : Icons.people_outline),
            tooltip: l10n.membersTooltip,
            onPressed: () => setState(() => _showMembers = !_showMembers),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildTimeline(messagesAsync)),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: l10n.messageHint,
                              border: const OutlineInputBorder(),
                            ),
                            spellCheckConfiguration:
                                ref.watch(spellCheckProvider)
                                    ? const SpellCheckConfiguration()
                                    : null,
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                            onPressed: _send, icon: const Icon(Icons.send)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showMembers) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: 220,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  OutlinedButton.icon(
                    onPressed: _inviteContact,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: Text(l10n.inviteContact),
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.membersTooltip,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final rosterEntry in roster)
                    Builder(builder: (context) {
                      final live = liveByPublicKey[rosterEntry.publicKeyHex];
                      final liveName = live?.name;
                      final displayName =
                          (liveName != null && liveName.isNotEmpty)
                              ? liveName
                              : (rosterEntry.name.isNotEmpty
                                  ? rosterEntry.name
                                  : l10n.peerFallbackName);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.circle,
                          size: 10,
                          color: (live?.connection ?? ToxConnection.none) ==
                                  ToxConnection.none
                              ? Colors.grey
                              : Colors.green,
                        ),
                        title: Text(displayName),
                      );
                    }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeline(AsyncValue<List<GroupMessage>> messagesAsync) {
    final l10n = AppLocalizations.of(context)!;
    if (messagesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (messagesAsync.hasError) {
      return Center(
          child:
              Text(l10n.errorLoadingMessages(messagesAsync.error.toString())));
    }

    final messages = messagesAsync.value ?? const [];
    if (messages.isEmpty) {
      return Center(child: Text(l10n.noMessagesYet));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final showDateDivider = index == 0 ||
            !isSameDay(messages[index - 1].timestamp, message.timestamp);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDateDivider) DateDivider(date: message.timestamp),
            _GroupMessageBubble(message: message),
          ],
        );
      },
    );
  }
}

class _GroupMessageBubble extends StatelessWidget {
  const _GroupMessageBubble({required this.message});

  final GroupMessage message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment:
          message.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: message.outgoing
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.outgoing)
              Text(
                message.senderName,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            Text(message.body),
            const SizedBox(height: 2),
            Text(
              '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
