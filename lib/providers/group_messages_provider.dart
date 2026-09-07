// group_messages_provider.dart
//
// `groupMessagesSyncProvider` escuta a stream global de eventos de rede e
// persiste mensagens de grupo recebidas/enviadas no banco — precisa ficar
// vivo durante toda a sessão do app, pelo mesmo motivo de
// messages_provider.dart. `groupChatMessagesProvider` é a leitura, por grupo.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart' show GroupMessage;
import '../data/group_messages_repository.dart';
import '../tox_events.dart';
import 'database_provider.dart';
import 'self_profile_provider.dart';
import 'tox_events_provider.dart';

class GroupMessagesSyncNotifier extends Notifier<void> {
  @override
  void build() {
    final repository = ref.watch(groupMessagesRepositoryProvider);
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) => _handle(event, repository));
    });
  }

  void _handle(ToxNetworkEvent event, GroupMessagesRepository repository) {
    switch (event) {
      case ToxGroupMessageEvent(
          :final chatIdHex,
          :final senderName,
          :final message,
          :final receivedAt
        ):
        unawaited(
          repository.insertIncoming(
            chatIdHex: chatIdHex,
            senderName: senderName,
            body: message,
            timestamp: receivedAt,
          ),
        );

      case ToxGroupMessageSentEvent(
          success: true,
          :final chatIdHex,
          :final message,
          :final sentAt,
        ):
        final selfName = ref.read(selfProfileProvider).name;
        unawaited(
          repository.insertOutgoing(
            chatIdHex: chatIdHex,
            senderName: selfName,
            body: message,
            timestamp: sentAt!,
          ),
        );

      case ToxGroupMessageSentEvent():
      case ToxSelfStatusEvent():
      case ToxSelfProfileEvent():
      case ToxFriendProfileEvent():
      case ToxFriendRequestEvent():
      case ToxFriendConnectionEvent():
      case ToxFriendTypingEvent():
      case ToxCallIncomingEvent():
      case ToxCallStateEvent():
      case ToxCallAudioFrameEvent():
      case ToxCallVideoFrameEvent():
      case ToxFriendAddResultEvent():
      case ToxFriendRemovedEvent():
      case ToxFriendMessageEvent():
      case ToxMessageSentEvent():
      case ToxMessageReadReceiptEvent():
      case ToxFileTransferEvent():
      case ToxSavedataFlushedEvent():
      case ToxGroupCreatedEvent():
      case ToxGroupSelfJoinedEvent():
      case ToxGroupJoinFailedEvent():
      case ToxGroupInviteEvent():
      case ToxGroupPeerJoinedEvent():
      case ToxGroupPeerLeftEvent():
      case ToxGroupPeerNameEvent():
      case ToxGroupLeftEvent():
      case ToxGroupInviteSentEvent():
        break;
    }
  }
}

final groupMessagesSyncProvider =
    NotifierProvider<GroupMessagesSyncNotifier, void>(
  GroupMessagesSyncNotifier.new,
);

/// Histórico de mensagens de um grupo específico, ordenado do mais antigo
/// para o mais novo. `family` porque cada tela de grupo observa um grupo
/// diferente.
final groupChatMessagesProvider =
    StreamProvider.family<List<GroupMessage>, String>((ref, chatIdHex) {
  // Garante que a sincronização global está ativa mesmo que nenhuma tela de
  // grupo tenha sido aberta ainda nesta sessão.
  ref.watch(groupMessagesSyncProvider);
  return ref.watch(groupMessagesRepositoryProvider).watchForGroup(chatIdHex);
});
