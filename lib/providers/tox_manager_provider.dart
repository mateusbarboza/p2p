// tox_manager_provider.dart
//
// Expõe o ToxIsolateManager (fundação de FFI/Isolate das Fases 0-2) como
// provider Riverpod. `toxNetworkStartupProvider` dispara `start()` uma
// única vez — a UI só precisa ler esse provider (ex: no initState da tela
// inicial) para o isolate de rede subir.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tox_isolate_manager.dart';

final toxIsolateManagerProvider = Provider<ToxIsolateManager>((ref) {
  final manager = ToxIsolateManager();
  ref.onDispose(manager.stop);
  return manager;
});

final toxNetworkStartupProvider = FutureProvider<void>((ref) async {
  final manager = ref.watch(toxIsolateManagerProvider);
  await manager.start();
});
