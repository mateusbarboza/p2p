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
            read: const Value(false),
          ),
        );
  }

  /// Quantas mensagens recebidas deste contato ainda não foram lidas —
  /// usado no badge da lista de contatos.
  Stream<int> watchUnreadCount(String contactPublicKeyHex) {
    final query = _db.select(_db.messages)
      ..where((t) =>
          t.contactPublicKeyHex.equals(contactPublicKeyHex) &
          t.outgoing.equals(false) &
          t.read.equals(false));
    return query.watch().map((rows) => rows.length);
  }

  /// Marca toda a conversa com esse contato como lida — chamado ao abrir a
  /// tela de chat.
  Future<void> markAllRead(String contactPublicKeyHex) async {
    await (_db.update(_db.messages)
          ..where((t) =>
              t.contactPublicKeyHex.equals(contactPublicKeyHex) &
              t.outgoing.equals(false) &
              t.read.equals(false)))
        .write(const MessagesCompanion(read: Value(true)));
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

  /// Salva uma mensagem enviada enquanto o contato estava offline — aparece
  /// na timeline imediatamente (com um indicador de "pendente" na UI), sem
  /// `toxMessageId` ainda. Retorna o `id` da linha, usado por
  /// [resolvePending] quando o reenvio automático for bem-sucedido.
  Future<int> insertPending({
    required String contactPublicKeyHex,
    required String body,
    required DateTime timestamp,
  }) {
    return _db.into(_db.messages).insert(
          MessagesCompanion.insert(
            contactPublicKeyHex: contactPublicKeyHex,
            outgoing: true,
            body: body,
            timestamp: Value(timestamp),
            pending: const Value(true),
          ),
        );
  }

  /// Todas as mensagens ainda pendentes (contato estava offline no envio)
  /// para um contato, mais antiga primeiro — usado para reenviar assim que
  /// ele conectar de novo.
  Future<List<Message>> pendingForContact(String contactPublicKeyHex) {
    final query = _db.select(_db.messages)
      ..where((t) =>
          t.contactPublicKeyHex.equals(contactPublicKeyHex) &
          t.pending.equals(true))
      ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);
    return query.get();
  }

  /// Confirma que uma mensagem pendente (ver [insertPending]) foi enviada
  /// de verdade — preenche o `toxMessageId` e tira o indicador de pendente.
  Future<void> resolvePending({
    required int id,
    required int toxMessageId,
  }) async {
    await (_db.update(_db.messages)..where((t) => t.id.equals(id))).write(
      MessagesCompanion(
        pending: const Value(false),
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
