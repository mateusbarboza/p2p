// notifications_provider.dart
//
// Notificação nativa do Windows quando chega uma mensagem — 1:1 ou de
// grupo — mesmo padrão dos outros "Sync" Notifiers (só que aqui não
// persiste nada, só dispara a notificação). Precisa ficar ativo desde o
// boot (ver AppRoot._startNetworking em main.dart), pelo mesmo motivo de
// sempre: a stream de eventos é broadcast sem replay.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../tox_events.dart';
import 'contacts_provider.dart';
import 'groups_provider.dart';
import 'tox_events_provider.dart';

/// Mesma lista de extensões usada em chat_screen.dart pra reconhecer uma
/// mensagem de voz — duplicada aqui porque são módulos independentes (um é
/// UI, outro é lógica de notificação) e a lista é pequena o bastante pra não
/// valer a pena uma dependência cruzada só por isso.
const _kAudioExtensions = {
  '.pcm',
  '.m4a',
  '.aac',
  '.mp3',
  '.wav',
  '.ogg',
  '.opus',
};

bool _looksLikeAudio(String? fileName) {
  if (fileName == null) return false;
  final lower = fileName.toLowerCase();
  return _kAudioExtensions.any(lower.endsWith);
}

class NotificationsNotifier extends Notifier<void> {
  @override
  void build() {
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData(_handle);
    });
  }

  void _handle(ToxNetworkEvent event) {
    switch (event) {
      case ToxFriendMessageEvent(:final publicKeyHex, :final message):
        final contact = ref
            .read(contactsProvider)
            .where((c) => c.publicKeyHex == publicKeyHex)
            .firstOrNull;
        LocalNotification(
          title: contact?.displayName ?? 'Novo contato',
          body: message,
          // Explícito (em vez de confiar no padrão) — toca o som padrão de
          // notificação do Windows.
          silent: false,
        ).show();

      case ToxGroupMessageEvent(
          :final chatIdHex,
          :final senderName,
          :final message
        ):
        final group = ref
            .read(groupsProvider)
            .where((g) => g.chatIdHex == chatIdHex)
            .firstOrNull;
        LocalNotification(
          title: group?.name ?? 'Grupo',
          body: '$senderName: $message',
          silent: false,
        ).show();

      // Só a mensagem de voz avisa quando termina de enviar — arquivo
      // comum já mostra o progresso na própria bolha da conversa aberta,
      // sem precisar de notificação nativa também.
      case ToxFileTransferEvent(:final outgoing, :final phase, :final fileName)
          when outgoing &&
              phase == ToxFileTransferPhase.completed &&
              _looksLikeAudio(fileName):
        final contact = ref
            .read(contactsProvider)
            .where((c) => c.publicKeyHex == event.publicKeyHex)
            .firstOrNull;
        LocalNotification(
          title: contact?.displayName ?? 'Contato',
          body: 'Mensagem de voz enviada',
          silent: false,
        ).show();

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
      case ToxMessageSentEvent():
      case ToxMessageReadReceiptEvent():
      case ToxFileTransferEvent():
      case ToxSavedataFlushedEvent():
      case ToxGroupCreatedEvent():
      case ToxGroupSelfJoinedEvent():
      case ToxGroupJoinFailedEvent():
      case ToxGroupInviteEvent():
      case ToxGroupMessageSentEvent():
      case ToxGroupPeerJoinedEvent():
      case ToxGroupPeerLeftEvent():
      case ToxGroupPeerNameEvent():
      case ToxGroupInviteSentEvent():
      case ToxGroupLeftEvent():
        break;
    }
  }
}

final notificationsProvider = NotifierProvider<NotificationsNotifier, void>(
  NotificationsNotifier.new,
);
