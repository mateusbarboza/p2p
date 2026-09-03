// self_status_provider.dart
//
// Estado da própria instância (conexão global + Talksnap ID), alimentado
// por ToxSelfStatusEvent. Substitui os campos `_connection`/`_talksnapId`
// que antes viviam soltos em _HomeScreenState.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tox_bindings.dart' show ToxConnection;
import '../tox_events.dart';
import 'tox_events_provider.dart';

class SelfStatus {
  const SelfStatus({this.connection = ToxConnection.none, this.talksnapId});

  final ToxConnection connection;
  final String? talksnapId;

  SelfStatus copyWith({ToxConnection? connection, String? talksnapId}) {
    return SelfStatus(
      connection: connection ?? this.connection,
      talksnapId: talksnapId ?? this.talksnapId,
    );
  }
}

class SelfStatusNotifier extends Notifier<SelfStatus> {
  @override
  SelfStatus build() {
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) {
        if (event is ToxSelfStatusEvent) {
          state = state.copyWith(
              connection: event.connection, talksnapId: event.talksnapId);
        }
      });
    });
    return const SelfStatus();
  }
}

final selfStatusProvider =
    NotifierProvider<SelfStatusNotifier, SelfStatus>(SelfStatusNotifier.new);
