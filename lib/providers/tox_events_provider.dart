// tox_events_provider.dart
//
// Encapa a Stream<ToxNetworkEvent> do ToxIsolateManager como StreamProvider,
// para outros providers (contatos, pedidos pendentes, status) reagirem via
// `ref.listen`/`ref.watch` sem precisar conhecer o ToxIsolateManager
// diretamente.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tox_events.dart';
import 'tox_manager_provider.dart';

final toxNetworkEventsProvider = StreamProvider<ToxNetworkEvent>((ref) {
  final manager = ref.watch(toxIsolateManagerProvider);
  return manager.updates;
});
