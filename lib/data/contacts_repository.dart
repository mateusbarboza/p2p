// contacts_repository.dart
//
// Camada de acesso a dados sobre a tabela `Contacts` do database.dart.
// A UI/estado nunca monta queries Drift diretamente — só fala com este
// repositório, identificando contatos sempre pela chave pública (estável),
// nunca pelo friend_number (efêmero por sessão do toxcore).

import 'package:drift/drift.dart';

import 'database.dart';

class ContactsRepository {
  ContactsRepository(this._db);

  final AppDatabase _db;

  /// Stream reativa da lista de contatos — emite de novo a cada
  /// insert/update/delete na tabela, para a UI refletir mudanças ao vivo.
  Stream<List<Contact>> watchAll() {
    return _db.select(_db.contacts).watch();
  }

  /// Garante que existe um contato para essa chave pública (idempotente —
  /// chamar de novo para um contato já existente não faz nada).
  Future<void> ensureExists(String publicKeyHex) async {
    await _db.into(_db.contacts).insert(
          ContactsCompanion.insert(publicKeyHex: publicKeyHex),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> setNickname(String publicKeyHex, String? nickname) async {
    await (_db.update(_db.contacts)
          ..where((t) => t.publicKeyHex.equals(publicKeyHex)))
        .write(
      ContactsCompanion(nickname: Value(nickname)),
    );
  }

  Future<void> delete(String publicKeyHex) async {
    await (_db.delete(_db.contacts)
          ..where((t) => t.publicKeyHex.equals(publicKeyHex)))
        .go();
  }
}
