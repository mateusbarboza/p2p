// groups_repository.dart
//
// Camada de acesso a dados sobre a tabela `Groups` do database.dart.
// A UI/estado nunca monta queries Drift diretamente — só fala com este
// repositório, identificando grupos sempre pelo Chat ID (estável),
// nunca pelo group_number (efêmero por sessão do toxcore).

import 'database.dart';

class GroupsRepository {
  GroupsRepository(this._db);

  final AppDatabase _db;

  /// Stream reativa da lista de grupos — emite de novo a cada
  /// insert/update/delete na tabela, para a UI refletir mudanças ao vivo.
  Stream<List<Group>> watchAll() {
    return _db.select(_db.groups).watch();
  }

  /// Garante que existe um grupo para esse Chat ID (idempotente — chamar de
  /// novo para um grupo já existente só atualiza o nome).
  Future<void> ensureExists(String chatIdHex, String name) async {
    await _db.into(_db.groups).insertOnConflictUpdate(
          GroupsCompanion.insert(chatIdHex: chatIdHex, name: name),
        );
  }

  Future<void> delete(String chatIdHex) async {
    await (_db.delete(_db.groups)..where((t) => t.chatIdHex.equals(chatIdHex)))
        .go();
  }
}
