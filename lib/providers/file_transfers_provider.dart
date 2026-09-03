// file_transfers_provider.dart
//
// Mesmo padrão de messages_provider.dart: `fileTransfersSyncProvider`
// escuta a stream global de eventos e persiste (fica vivo durante toda a
// sessão do app — ativado a partir de main.dart, não só quando uma tela de
// chat é aberta); `fileTransfersProvider` é a leitura reativa por contato.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart' show FileTransfer;
import '../data/file_transfers_repository.dart';
import '../tox_events.dart';
import 'database_provider.dart';
import 'tox_events_provider.dart';

class FileTransfersSyncNotifier extends Notifier<void> {
  /// Id da linha (Drift) de cada transferência ativa, chaveado por
  /// (publicKeyHex, fileNumber) — só vale enquanto a transferência está em
  /// andamento; removido ao chegar a um status terminal. Necessário porque
  /// o toxcore reaproveita `fileNumber` entre transferências distintas com
  /// o mesmo amigo, então esse par sozinho não identifica uma transferência
  /// de forma estável entre execuções nem entre transferências sucessivas.
  final Map<(String, int), int> _activeRowIds = {};

  @override
  void build() {
    final repository = ref.watch(fileTransfersRepositoryProvider);
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) => _handle(event, repository));
    });
  }

  void _handle(ToxNetworkEvent event, FileTransfersRepository repository) {
    if (event is! ToxFileTransferEvent) return;
    final fileNumber = event.fileNumber;
    // Sem fileNumber (falha antes do toxcore atribuir um) não há o que
    // persistir — é feedback efêmero, tratado direto na tela de chat.
    if (fileNumber == null) return;

    final key = (event.publicKeyHex, fileNumber);

    if (event.phase == ToxFileTransferPhase.requested) {
      unawaited(() async {
        final id = await repository.insert(
          contactPublicKeyHex: event.publicKeyHex,
          toxFileNumber: fileNumber,
          fileName: event.fileName ?? '(sem nome)',
          totalBytes: event.totalBytes ?? 0,
          outgoing: event.outgoing,
          status: event.phase,
        );
        _activeRowIds[key] = id;
      }());
      return;
    }

    final rowId = _activeRowIds[key];
    if (rowId == null) return; // evento sem uma linha ativa correspondente

    unawaited(
      repository.updateById(
        id: rowId,
        bytesTransferred: event.bytesTransferred ?? 0,
        status: event.phase,
        savedPath: event.savedPath,
      ),
    );

    const terminalPhases = {
      ToxFileTransferPhase.completed,
      ToxFileTransferPhase.cancelled,
      ToxFileTransferPhase.failed,
    };
    if (terminalPhases.contains(event.phase)) {
      _activeRowIds.remove(key);
    }
  }
}

final fileTransfersSyncProvider =
    NotifierProvider<FileTransfersSyncNotifier, void>(
  FileTransfersSyncNotifier.new,
);

/// Transferências de arquivo com um contato específico, mais antiga primeiro.
final fileTransfersProvider =
    StreamProvider.family<List<FileTransfer>, String>((
  ref,
  publicKeyHex,
) {
  ref.watch(fileTransfersSyncProvider);
  return ref
      .watch(fileTransfersRepositoryProvider)
      .watchForContact(publicKeyHex);
});
