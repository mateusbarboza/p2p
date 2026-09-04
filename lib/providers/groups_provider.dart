// groups_provider.dart
//
// Combina duas fontes numa única lista de grupos "ao vivo": o banco de
// dados local (Groups, via GroupsRepository) — a fonte de verdade de QUAL é
// o grupo e o nome dele, sobrevive a reinícios — e os eventos de rede de
// membros (ToxGroupPeerJoined/Left/Name) — o estado em tempo real, nunca
// persistido (mesmo raciocínio de contacts_provider.dart para conexão).
//
// O isolate de rede não sabe que este banco existe — é este provider quem
// decide persistir (ensureExists) reagindo a ToxGroupCreatedEvent/
// ToxGroupSelfJoinedEvent.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart' show Group, GroupMember;
import '../tox_bindings.dart' show ToxConnection;
import '../tox_events.dart';
import 'database_provider.dart';
import 'tox_events_provider.dart';

class GroupMemberViewModel {
  const GroupMemberViewModel({
    required this.peerId,
    required this.name,
    required this.connection,
    required this.publicKeyHex,
  });

  final int peerId;
  final String name;
  final ToxConnection connection;

  /// Chave pública estável do peer — usada para não oferecer convidar de
  /// novo quem já é membro do grupo. `null` se não disponível.
  final String? publicKeyHex;
}

class GroupViewModel {
  const GroupViewModel({
    required this.chatIdHex,
    required this.name,
    required this.members,
    required this.isFounder,
  });

  final String chatIdHex;
  final String name;
  final List<GroupMemberViewModel> members;

  /// Se somos o fundador do grupo — a UI mostra "Excluir grupo" em vez de
  /// "Sair do grupo" nesse caso (ver [ToxGroupCreatedEvent]).
  final bool isFounder;
}

class GroupsNotifier extends Notifier<List<GroupViewModel>> {
  final Map<String, Map<int, GroupMemberViewModel>> _membersByChatId = {};
  final Map<String, bool> _isFounderByChatId = {};
  List<Group> _dbGroups = const [];
  StreamSubscription<List<Group>>? _dbSubscription;

  @override
  List<GroupViewModel> build() {
    final repository = ref.watch(groupsRepositoryProvider);

    _dbSubscription = repository.watchAll().listen((groups) {
      _dbGroups = groups;
      state = _merge();
    });
    ref.onDispose(() => _dbSubscription?.cancel());

    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData(_handleEvent);
    });

    return const [];
  }

  void _handleEvent(ToxNetworkEvent event) {
    final repository = ref.read(groupsRepositoryProvider);
    switch (event) {
      case ToxGroupCreatedEvent(
          :final chatIdHex,
          :final name,
          :final isFounder
        ):
      case ToxGroupSelfJoinedEvent(
          :final chatIdHex,
          :final name,
          :final isFounder
        ):
        _isFounderByChatId[chatIdHex] = isFounder;
        unawaited(repository.ensureExists(chatIdHex, name));
        state = _merge();

      case ToxGroupPeerJoinedEvent(
          :final chatIdHex,
          :final peerId,
          :final peerName,
          :final connection,
          :final publicKeyHex
        ):
        final members = _membersByChatId.putIfAbsent(chatIdHex, () => {});
        members[peerId] = GroupMemberViewModel(
          peerId: peerId,
          name: peerName,
          connection: connection,
          publicKeyHex: publicKeyHex,
        );
        if (publicKeyHex != null) {
          unawaited(ref
              .read(groupMembersRepositoryProvider)
              .ensureExists(chatIdHex, publicKeyHex, peerName));
        }
        state = _merge();

      case ToxGroupInviteSentEvent(
          :final chatIdHex,
          :final contactPublicKeyHex
        ):
        unawaited(ref
            .read(groupInvitedContactsRepositoryProvider)
            .ensureExists(chatIdHex, contactPublicKeyHex));

      case ToxGroupPeerLeftEvent(:final chatIdHex, :final peerId):
        _membersByChatId[chatIdHex]?.remove(peerId);
        state = _merge();

      case ToxGroupLeftEvent(:final chatIdHex):
        _membersByChatId.remove(chatIdHex);
        _isFounderByChatId.remove(chatIdHex);
        unawaited(repository.delete(chatIdHex));
        unawaited(
            ref.read(groupMembersRepositoryProvider).deleteForGroup(chatIdHex));
        unawaited(ref
            .read(groupInvitedContactsRepositoryProvider)
            .deleteForGroup(chatIdHex));

      case ToxGroupPeerNameEvent(
          :final chatIdHex,
          :final peerId,
          :final peerName
        ):
        final members = _membersByChatId[chatIdHex];
        final existing = members?[peerId];
        if (members != null && existing != null) {
          members[peerId] = GroupMemberViewModel(
            peerId: peerId,
            name: peerName,
            connection: existing.connection,
            publicKeyHex: existing.publicKeyHex,
          );
          final publicKeyHex = existing.publicKeyHex;
          if (publicKeyHex != null) {
            unawaited(ref
                .read(groupMembersRepositoryProvider)
                .ensureExists(chatIdHex, publicKeyHex, peerName));
          }
          state = _merge();
        }

      case ToxSelfStatusEvent():
      case ToxSelfProfileEvent():
      case ToxFriendProfileEvent():
      case ToxFriendRequestEvent():
      case ToxFriendConnectionEvent():
      case ToxFriendTypingEvent():
      case ToxCallIncomingEvent():
      case ToxCallStateEvent():
      case ToxCallAudioFrameEvent():
      case ToxFriendAddResultEvent():
      case ToxFriendRemovedEvent():
      case ToxFriendMessageEvent():
      case ToxMessageSentEvent():
      case ToxMessageReadReceiptEvent():
      case ToxFileTransferEvent():
      case ToxSavedataFlushedEvent():
      case ToxGroupJoinFailedEvent():
      case ToxGroupInviteEvent():
      case ToxGroupMessageEvent():
      case ToxGroupMessageSentEvent():
        break;
    }
  }

  List<GroupViewModel> _merge() {
    return [
      for (final group in _dbGroups)
        GroupViewModel(
          chatIdHex: group.chatIdHex,
          name: group.name,
          members:
              (_membersByChatId[group.chatIdHex]?.values ?? const []).toList(),
          isFounder: _isFounderByChatId[group.chatIdHex] ?? false,
        ),
    ];
  }
}

final groupsProvider = NotifierProvider<GroupsNotifier, List<GroupViewModel>>(
  GroupsNotifier.new,
);

/// Chaves públicas de contatos já convidados para um grupo — usado para não
/// oferecer convidar de novo o mesmo contato na lista de "convidar contato".
final groupKnownMemberKeysProvider =
    StreamProvider.family<Set<String>, String>((ref, chatIdHex) {
  return ref
      .watch(groupInvitedContactsRepositoryProvider)
      .watchForGroup(chatIdHex)
      .map((rows) => rows.map((row) => row.contactPublicKeyHex).toSet());
});

/// Roster persistido de um grupo (todo peer que já apareceu nele, com o
/// último nome conhecido) — ao contrário de `GroupViewModel.members`, não
/// zera a cada reinício do app; usado tanto para a contagem quanto para a
/// lista "Membros" continuar mostrando quem já esteve lá, mesmo antes do
/// `group_peer_join` disparar de novo nesta sessão.
final groupRosterProvider =
    StreamProvider.family<List<GroupMember>, String>((ref, chatIdHex) {
  return ref.watch(groupMembersRepositoryProvider).watchForGroup(chatIdHex);
});
