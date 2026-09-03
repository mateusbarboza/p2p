// group_invited_contacts_repository.dart
//
// Quem já foi convidado (pela chave pública do AMIGO) para cada grupo — só
// para não oferecer convidar de novo o mesmo contato. Não confundir com
// GroupMembers, que guarda o roster real do grupo por uma chave diferente
// (a chave do peer DENTRO do grupo, ver database.dart).

import 'database.dart';

class GroupInvitedContactsRepository {
  GroupInvitedContactsRepository(this._db);

  final AppDatabase _db;

  Stream<List<GroupInvitedContact>> watchForGroup(String chatIdHex) {
    return (_db.select(_db.groupInvitedContacts)
          ..where((t) => t.chatIdHex.equals(chatIdHex)))
        .watch();
  }

  Future<void> ensureExists(
      String chatIdHex, String contactPublicKeyHex) async {
    await _db.into(_db.groupInvitedContacts).insertOnConflictUpdate(
          GroupInvitedContactsCompanion.insert(
            chatIdHex: chatIdHex,
            contactPublicKeyHex: contactPublicKeyHex,
          ),
        );
  }

  Future<void> deleteForGroup(String chatIdHex) async {
    await (_db.delete(_db.groupInvitedContacts)
          ..where((t) => t.chatIdHex.equals(chatIdHex)))
        .go();
  }
}
