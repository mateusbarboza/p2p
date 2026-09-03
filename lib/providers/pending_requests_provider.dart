// pending_requests_provider.dart
//
// Pedidos de amizade recebidos e ainda não respondidos. Intencionalmente
// não persistido em banco: é um estado de sessão (se o app fechar antes de
// responder, quem pediu simplesmente pede de novo — o toxcore não guarda
// pedidos pendentes recebidos entre execuções).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tox_events.dart';
import 'tox_events_provider.dart';

class PendingFriendRequest {
  const PendingFriendRequest(
      {required this.publicKeyHex, required this.message});

  final String publicKeyHex;
  final String message;
}

class PendingRequestsNotifier extends Notifier<List<PendingFriendRequest>> {
  @override
  List<PendingFriendRequest> build() {
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) {
        if (event is ToxFriendRequestEvent) {
          state = [
            ...state,
            PendingFriendRequest(
                publicKeyHex: event.publicKeyHex, message: event.message),
          ];
        }
      });
    });
    return const [];
  }

  void removeByPublicKey(String publicKeyHex) {
    state =
        state.where((request) => request.publicKeyHex != publicKeyHex).toList();
  }
}

final pendingRequestsProvider =
    NotifierProvider<PendingRequestsNotifier, List<PendingFriendRequest>>(
  PendingRequestsNotifier.new,
);
