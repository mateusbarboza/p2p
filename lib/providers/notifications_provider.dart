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
