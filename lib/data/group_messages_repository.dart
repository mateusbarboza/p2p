// group_messages_repository.dart
//
// Acesso a dados sobre a tabela `GroupMessages`. Mensagens de grupo são
// sempre associadas a um grupo pelo Chat ID (estável), nunca pelo
// group_number (efêmero por sessão do toxcore).

import 'package:drift/drift.dart';

import 'database.dart';

class GroupMessagesRepository {
  GroupMessagesRepository(this._db);

  final AppDatabase _db;

  /// Stream reativa do histórico de um grupo, mais antiga primeiro.
  Stream<List<GroupMessage>> watchForGroup(String chatIdHex) {
    final query = _db.select(_db.groupMessages)
      ..where((t) => t.chatIdHex.equals(chatIdHex))
      ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);
    return query.watch();
  }

  Future<void> insertIncoming({
    required String chatIdHex,
    required String senderName,
    required String body,
    required DateTime timestamp,
  }) async {
    await _db.into(_db.groupMessages).insert(
          GroupMessagesCompanion.insert(
            chatIdHex: chatIdHex,
            outgoing: false,
            senderName: senderName,
            body: body,
            timestamp: Value(timestamp),
          ),
        );
  }

  Future<void> insertOutgoing({
    required String chatIdHex,
    required String senderName,
    required String body,
    required DateTime timestamp,
  }) async {
    await _db.into(_db.groupMessages).insert(
          GroupMessagesCompanion.insert(
            chatIdHex: chatIdHex,
            outgoing: true,
            senderName: senderName,
            body: body,
            timestamp: Value(timestamp),
          ),
        );
  }
}
