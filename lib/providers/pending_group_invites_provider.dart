// pending_group_invites_provider.dart
//
// Convites de grupo recebidos e ainda não respondidos. Intencionalmente não
// persistido em banco (mesmo raciocínio de pending_requests_provider.dart):
// é um estado de sessão — se o app fechar antes de responder, quem convidou
// simplesmente convida de novo enquanto estiver no grupo.

import 'dart:typed_data' show Uint8List;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tox_events.dart';
import 'tox_events_provider.dart';

class PendingGroupInvite {
  const PendingGroupInvite({
    required this.fromPublicKeyHex,
    required this.groupName,
    required this.inviteData,
  });

  final String fromPublicKeyHex;
  final String groupName;
  final Uint8List inviteData;
}

class PendingGroupInvitesNotifier extends Notifier<List<PendingGroupInvite>> {
  @override
  List<PendingGroupInvite> build() {
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) {
        if (event is ToxGroupInviteEvent) {
          state = [
            ...state,
            PendingGroupInvite(
              fromPublicKeyHex: event.fromPublicKeyHex,
              groupName: event.groupName,
              inviteData: event.inviteData,
            ),
          ];
        }
      });
    });
    return const [];
  }

  void remove(PendingGroupInvite invite) {
    state = state.where((i) => i != invite).toList();
  }
}

final pendingGroupInvitesProvider =
    NotifierProvider<PendingGroupInvitesNotifier, List<PendingGroupInvite>>(
  PendingGroupInvitesNotifier.new,
);
