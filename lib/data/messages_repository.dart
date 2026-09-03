// messages_repository.dart
//
// Acesso a dados sobre a tabela `Messages`. Mensagens são sempre associadas
// a um contato pela chave pública (estável), nunca pelo friend_number
// (efêmero por sessão do toxcore).

import 'package:drift/drift.dart';

import 'database.dart';

class MessagesRepository {
  MessagesRepository(this._db);

  final AppDatabase _db;

  /// Stream reativa do histórico com um contato, mais antiga primeiro.
  Stream<List<Message>> watchForContact(String contactPublicKeyHex) {
    final query = _db.select(_db.messages)
      ..where((t) => t.contactPublicKeyHex.equals(contactPublicKeyHex))
      ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);
    return query.watch();
  }

  Future<void> insertIncoming({
    required String contactPublicKeyHex,
    required String body,
    required DateTime timestamp,
  }) async {
    await _db.into(_db.messages).insert(
          MessagesCompanion.insert(
            contactPublicKeyHex: contactPublicKeyHex,
            outgoing: false,
            body: body,
            timestamp: Value(timestamp),
          ),
        );
  }

  Future<void> insertOutgoing({
    required String contactPublicKeyHex,
    required String body,
    required int toxMessageId,
    required DateTime timestamp,
  }) async {
    await _db.into(_db.messages).insert(
          MessagesCompanion.insert(
            contactPublicKeyHex: contactPublicKeyHex,
            outgoing: true,
            body: body,
            timestamp: Value(timestamp),
            toxMessageId: Value(toxMessageId),
          ),
        );
  }

  /// Marca como entregue a mensagem enviada por nós que corresponde a esse
  /// `message_id` do toxcore (ver [ToxMessageReadReceiptEvent]).
  Future<void> markDelivered({
    required String contactPublicKeyHex,
    required int toxMessageId,
  }) async {
    await (_db.update(_db.messages)
          ..where(
            (t) =>
                t.contactPublicKeyHex.equals(contactPublicKeyHex) &
                t.toxMessageId.equals(toxMessageId),
          ))
        .write(const MessagesCompanion(delivered: Value(true)));
  }

  /// Apaga uma mensagem localmente. O toxcore não tem "apagar para todos" —
  /// isso só remove do nosso histórico.
  Future<void> deleteById(int id) async {
    await (_db.delete(_db.messages)..where((t) => t.id.equals(id))).go();
  }
}
