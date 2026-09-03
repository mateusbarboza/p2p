// group_members_repository.dart
//
// Quem já é/foi membro de um grupo, por chave pública — persistido mesmo
// que o peer esteja offline agora (diferente do estado "ao vivo" de conexão
// em groups_provider.dart). Usado para filtrar a lista de "convidar
// contato" (não reoferecer quem já está no grupo).

import 'database.dart';

class GroupMembersRepository {
  GroupMembersRepository(this._db);

  final AppDatabase _db;

  Stream<List<GroupMember>> watchForGroup(String chatIdHex) {
    return (_db.select(_db.groupMembers)
          ..where((t) => t.chatIdHex.equals(chatIdHex)))
        .watch();
  }

  Future<void> ensureExists(
      String chatIdHex, String publicKeyHex, String name) async {
    await _db.into(_db.groupMembers).insertOnConflictUpdate(
          GroupMembersCompanion.insert(
            chatIdHex: chatIdHex,
            publicKeyHex: publicKeyHex,
            name: name,
          ),
        );
  }

  Future<void> deleteForGroup(String chatIdHex) async {
    await (_db.delete(_db.groupMembers)
          ..where((t) => t.chatIdHex.equals(chatIdHex)))
        .go();
  }
}
