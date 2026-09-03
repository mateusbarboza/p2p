// messages_provider.dart
//
// `messagesSyncProvider` escuta a stream global de eventos de rede e
// persiste mensagens recebidas/enviadas/confirmadas no banco — precisa
// ficar vivo durante toda a sessão do app (não só enquanto uma tela de chat
// específica está aberta), para não perder mensagens que chegam em
// segundo plano. `chatMessagesProvider` é a leitura, por contato.
//
// unawaited() é usado deliberadamente aqui: persistir é fire-and-forget do
// ponto de vista do fluxo de eventos — a Stream de mensagens (Drift) já
// notifica a UI quando a escrita terminar, não precisamos bloquear o
// processamento do próximo evento esperando o disco.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart' show Message;
import '../data/messages_repository.dart';
import '../tox_events.dart';
import 'database_provider.dart';
import 'tox_events_provider.dart';

class MessagesSyncNotifier extends Notifier<void> {
  @override
  void build() {
    final repository = ref.watch(messagesRepositoryProvider);
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) => _handle(event, repository));
    });
  }

  void _handle(ToxNetworkEvent event, MessagesRepository repository) {
    switch (event) {
      case ToxFriendMessageEvent(
          :final publicKeyHex,
          :final message,
          :final receivedAt
        ):
        unawaited(
          repository.insertIncoming(
            contactPublicKeyHex: publicKeyHex,
            body: message,
            timestamp: receivedAt,
          ),
        );

      case ToxMessageSentEvent(
          success: true,
          :final publicKeyHex,
          :final message,
          :final toxMessageId,
          :final sentAt,
        ):
        unawaited(
          repository.insertOutgoing(
            contactPublicKeyHex: publicKeyHex,
            body: message,
            toxMessageId: toxMessageId!,
            timestamp: sentAt!,
          ),
        );

      case ToxMessageReadReceiptEvent(:final publicKeyHex, :final toxMessageId):
        unawaited(
          repository.markDelivered(
              contactPublicKeyHex: publicKeyHex, toxMessageId: toxMessageId),
        );

      case ToxMessageSentEvent():
      case ToxSelfStatusEvent():
      case ToxFriendRequestEvent():
      case ToxFriendConnectionEvent():
      case ToxFriendAddResultEvent():
      case ToxFriendRemovedEvent():
      case ToxFileTransferEvent():
      case ToxSelfProfileEvent():
      case ToxFriendProfileEvent():
      case ToxSavedataFlushedEvent():
      case ToxGroupCreatedEvent():
      case ToxGroupSelfJoinedEvent():
      case ToxGroupJoinFailedEvent():
      case ToxGroupInviteEvent():
      case ToxGroupMessageEvent():
      case ToxGroupMessageSentEvent():
      case ToxGroupPeerJoinedEvent():
      case ToxGroupPeerLeftEvent():
      case ToxGroupPeerNameEvent():
      case ToxGroupLeftEvent():
      case ToxGroupInviteSentEvent():
        break;
    }
  }
}

final messagesSyncProvider = NotifierProvider<MessagesSyncNotifier, void>(
  MessagesSyncNotifier.new,
);

/// Histórico de mensagens com um contato específico, ordenado do mais
/// antigo para o mais novo. `family` porque cada tela de chat observa um
/// contato diferente.
final chatMessagesProvider =
    StreamProvider.family<List<Message>, String>((ref, publicKeyHex) {
  // Garante que a sincronização global está ativa mesmo que nenhuma tela de
  // chat tenha sido aberta ainda nesta sessão.
  ref.watch(messagesSyncProvider);
  return ref.watch(messagesRepositoryProvider).watchForContact(publicKeyHex);
});
