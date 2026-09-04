// call_logs_repository.dart
//
// Acesso a dados sobre a tabela `CallLogs` — eventos de chamada de voz
// (iniciada/encerrada) mostrados na timeline do chat, junto com mensagens
// e transferências de arquivo (ver chat_screen.dart).

import 'package:drift/drift.dart';

import 'database.dart';

class CallLogsRepository {
  CallLogsRepository(this._db);

  final AppDatabase _db;

  /// Stream reativa dos eventos de chamada com um contato, mais antigo
  /// primeiro — mesma ordem usada pra mensagens de texto.
  Stream<List<CallLog>> watchForContact(String contactPublicKeyHex) {
    final query = _db.select(_db.callLogs)
      ..where((t) => t.contactPublicKeyHex.equals(contactPublicKeyHex))
      ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);
    return query.watch();
  }

  Future<void> insert({
    required String contactPublicKeyHex,
    required bool outgoing,
    required String kind,
    required DateTime timestamp,
  }) async {
    await _db.into(_db.callLogs).insert(
          CallLogsCompanion.insert(
            contactPublicKeyHex: contactPublicKeyHex,
            outgoing: outgoing,
            kind: kind,
            timestamp: Value(timestamp),
          ),
        );
  }
}
