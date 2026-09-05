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
import '../tox_bindings.dart' show ToxConnection;
import '../tox_events.dart';
import 'database_provider.dart';
import 'file_transfers_provider.dart';
import 'tox_events_provider.dart';
import 'tox_manager_provider.dart';

class MessagesSyncNotifier extends Notifier<void> {
  /// Contatos com um reenvio de pendentes em andamento — evita disparar o
  /// mesmo lote de novo se `ToxFriendConnectionEvent` chegar mais de uma vez
  /// seguida (reconexões instáveis, por exemplo).
  final Set<String> _retrying = {};

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
        unawaited(_resolveOrInsert(
          repository: repository,
          publicKeyHex: publicKeyHex,
          message: message,
          toxMessageId: toxMessageId!,
          sentAt: sentAt!,
        ));

      // Contato offline no momento do envio: a mensagem já foi salva como
      // pendente por _send() na tela de chat — nada a fazer aqui além de
      // deixar quieto (ver ToxFriendConnectionEvent abaixo para o reenvio).
      case ToxMessageSentEvent(success: false, notConnected: true):
        break;

      case ToxMessageReadReceiptEvent(:final publicKeyHex, :final toxMessageId):
        unawaited(
          repository.markDelivered(
              contactPublicKeyHex: publicKeyHex, toxMessageId: toxMessageId),
        );

      case ToxFriendConnectionEvent(:final publicKeyHex, :final connection)
          when connection != ToxConnection.none:
        unawaited(_retryPending(repository, publicKeyHex));

      case ToxMessageSentEvent():
      case ToxSelfStatusEvent():
      case ToxFriendRequestEvent():
      case ToxFriendConnectionEvent():
      case ToxFriendTypingEvent():
      case ToxCallIncomingEvent():
      case ToxCallStateEvent():
      case ToxCallAudioFrameEvent():
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

  /// Uma mensagem enviada com sucesso pode ser um envio normal (contato já
  /// estava online: insere uma linha nova) ou a confirmação de uma mensagem
  /// que tinha sido salva como pendente (contato estava offline: atualiza a
  /// linha existente em vez de duplicá-la na timeline).
  Future<void> _resolveOrInsert({
    required MessagesRepository repository,
    required String publicKeyHex,
    required String message,
    required int toxMessageId,
    required DateTime sentAt,
  }) async {
    final pending = await repository.pendingForContact(publicKeyHex);
    final matches = pending.where((m) => m.body == message);
    final match = matches.isEmpty ? null : matches.first;
    if (match != null) {
      await repository.resolvePending(id: match.id, toxMessageId: toxMessageId);
    } else {
      await repository.insertOutgoing(
        contactPublicKeyHex: publicKeyHex,
        body: message,
        toxMessageId: toxMessageId,
        timestamp: sentAt,
      );
    }
  }

  /// Reenvia, em ordem, toda mensagem que ficou pendente com esse contato
  /// enquanto ele estava offline — chamado assim que ele conecta de novo.
  Future<void> _retryPending(
      MessagesRepository repository, String publicKeyHex) async {
    if (!_retrying.add(publicKeyHex)) return;
    try {
      final pending = await repository.pendingForContact(publicKeyHex);
      final manager = ref.read(toxIsolateManagerProvider);
      for (final message in pending) {
        manager.sendMessage(publicKeyHex, message.body);
      }
    } finally {
      _retrying.remove(publicKeyHex);
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

/// Quantas mensagens de texto não lidas tem com um contato. Uso interno —
/// [unreadMessagesCountProvider] é quem soma isso com arquivos/áudios não
/// lidos (ver file_transfers_provider.dart) pro badge da lista de contatos.
final _unreadTextMessagesCountProvider =
    StreamProvider.family<int, String>((ref, publicKeyHex) {
  ref.watch(messagesSyncProvider);
  return ref.watch(messagesRepositoryProvider).watchUnreadCount(publicKeyHex);
});

/// Total de itens não lidos (mensagens de texto + arquivos/áudios recebidos)
/// com um contato — mostrado como badge na listagem de contatos. `family`
/// por contato, mesmo raciocínio de [chatMessagesProvider]. Uma mensagem de
/// voz recebida com a conversa fechada só conta aqui depois de completar o
/// download (ver FileTransfersRepository.insert/watchUnreadCount).
final unreadMessagesCountProvider = Provider.family<int, String>((
  ref,
  publicKeyHex,
) {
  final textCount =
      ref.watch(_unreadTextMessagesCountProvider(publicKeyHex)).value ?? 0;
  final fileCount =
      ref.watch(fileTransfersUnreadCountProvider(publicKeyHex)).value ?? 0;
  return textCount + fileCount;
});
