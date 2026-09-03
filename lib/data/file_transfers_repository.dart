// file_transfers_repository.dart
//
// Acesso a dados sobre a tabela `FileTransfers`.
//
// IMPORTANTE: `toxFileNumber` NÃO é uma chave estável entre transferências
// — o toxcore o reaproveita a cada nova transferência com o mesmo amigo
// (ex: a segunda transferência pode receber o mesmo número da primeira,
// já concluída). Por isso este repositório nunca "procura uma linha
// existente por toxFileNumber" — cada [insert] sempre cria uma linha nova,
// e quem chama guarda o id retornado para as atualizações seguintes
// ([updateById]) enquanto aquela transferência especificamente estiver
// ativa (ver FileTransfersSyncNotifier).

import 'dart:io';

import 'package:drift/drift.dart';

import '../tox_events.dart' show ToxFileTransferPhase;
import 'database.dart';

class FileTransfersRepository {
  FileTransfersRepository(this._db);

  final AppDatabase _db;

  /// Stream reativa das transferências com um contato, mais antiga primeiro.
  Stream<List<FileTransfer>> watchForContact(String contactPublicKeyHex) {
    final query = _db.select(_db.fileTransfers)
      ..where((t) => t.contactPublicKeyHex.equals(contactPublicKeyHex))
      ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);
    return query.watch();
  }

  /// Cria uma nova linha para uma transferência recém-oferecida. Retorna o
  /// id gerado, a ser usado em [updateById] para o restante do ciclo de
  /// vida dessa transferência específica.
  Future<int> insert({
    required String contactPublicKeyHex,
    required int toxFileNumber,
    required String fileName,
    required int totalBytes,
    required bool outgoing,
    required ToxFileTransferPhase status,
  }) {
    return _db.into(_db.fileTransfers).insert(
          FileTransfersCompanion.insert(
            contactPublicKeyHex: contactPublicKeyHex,
            toxFileNumber: toxFileNumber,
            fileName: fileName,
            totalBytes: totalBytes,
            outgoing: outgoing,
            status: status,
          ),
        );
  }

  Future<void> updateById({
    required int id,
    required int bytesTransferred,
    required ToxFileTransferPhase status,
    String? savedPath,
  }) async {
    await (_db.update(_db.fileTransfers)..where((t) => t.id.equals(id))).write(
      FileTransfersCompanion(
        bytesTransferred: Value(bytesTransferred),
        status: Value(status),
        savedPath: savedPath == null ? const Value.absent() : Value(savedPath),
      ),
    );
  }

  /// Apaga o registro localmente. Se o arquivo recebido ainda existir em
  /// disco (`attachments/`), apaga também — senão ficaria um órfão lá,
  /// já que essa linha era a única referência a ele. O toxcore não tem
  /// "apagar para todos"; isso só afeta o nosso lado.
  Future<void> deleteById(int id) async {
    final row = await (_db.select(_db.fileTransfers)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    await (_db.delete(_db.fileTransfers)..where((t) => t.id.equals(id))).go();

    final savedPath = row?.savedPath;
    if (savedPath != null) {
      final file = File(savedPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
