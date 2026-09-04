// database.dart
//
// Persistência local estruturada do Talksnap (Fase 3), separada do
// "savedata" opaco do próprio toxcore (que só guarda chaves e a lista de
// friend_numbers). Aqui guardamos o que o toxcore não sabe: apelidos e,
// nas fases seguintes, histórico de mensagens e transferências de arquivo.
//
// O isolate de rede (tox_isolate_manager.dart) NÃO conhece este banco —
// ele só emite ToxNetworkEvent. Quem persiste esses eventos aqui é a
// camada de estado (lib/providers/), mantendo o isolate de rede fino e
// focado só em FFI/rede.

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../dev_profile.dart';
import '../tox_events.dart' show ToxFileTransferPhase;

part 'database.g.dart';

/// Um contato (amigo Tox) conhecido localmente. A chave estável é
/// [publicKeyHex] — o friend_number que o toxcore usa em tempo de execução
/// é efêmero por sessão, então nunca é persistido aqui.
class Contacts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get publicKeyHex => text().unique()();
  TextColumn get nickname => text().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Histórico de mensagens de texto 1:1 com um contato, identificado sempre
/// por [contactPublicKeyHex] (nunca por friend_number).
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get contactPublicKeyHex => text()();
  BoolColumn get outgoing => boolean()();
  TextColumn get body => text()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();

  /// `message_id` local do toxcore (só preenchido para mensagens enviadas
  /// por nós) — usado para casar com o read receipt e marcar [delivered].
  IntColumn get toxMessageId => integer().nullable()();
  BoolColumn get delivered => boolean().withDefault(const Constant(false))();

  /// Mensagem enviada por nós enquanto o contato estava offline: já salva
  /// na timeline, mas ainda sem `toxMessageId` — [MessagesSyncNotifier]
  /// reenvia sozinho assim que o contato conectar de novo.
  BoolColumn get pending => boolean().withDefault(const Constant(false))();

  /// Só faz sentido para mensagens recebidas (`outgoing: false`) — `true`
  /// assim que a conversa é aberta. Mensagens enviadas por nós nascem já
  /// `true` (não existe "não lida" para o que a própria pessoa escreveu).
  BoolColumn get read => boolean().withDefault(const Constant(true))();
}

/// Transferências de arquivo com um contato. `toxFileNumber` é efêmero
/// (escopado por amigo+sessão do toxcore) — só serve para casar eventos de
/// progresso ao vivo com a linha certa enquanto a transferência está
/// ativa; não é uma chave estável entre execuções do app.
class FileTransfers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get contactPublicKeyHex => text()();
  IntColumn get toxFileNumber => integer()();
  TextColumn get fileName => text()();
  IntColumn get totalBytes => integer()();
  IntColumn get bytesTransferred => integer().withDefault(const Constant(0))();
  BoolColumn get outgoing => boolean()();
  TextColumn get status => textEnum<ToxFileTransferPhase>()();
  TextColumn get savedPath => text().nullable()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

/// Um grupo (chat NGC). A chave estável é [chatIdHex] (32 bytes, hex) —
/// equivalente a uma "chave pública" de grupo; o `group_number` que o
/// toxcore usa em tempo de execução é efêmero por sessão e nunca é
/// persistido aqui.
class Groups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get chatIdHex => text().unique()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Histórico de mensagens de um grupo, identificado sempre por
/// [chatIdHex] (nunca por `group_number`). Diferente de [Messages] (1:1),
/// guarda também o nome de quem enviou — necessário para atribuir cada
/// mensagem a um peer numa conversa com mais de duas pessoas.
class GroupMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get chatIdHex => text()();
  BoolColumn get outgoing => boolean()();
  TextColumn get senderName => text()();
  TextColumn get body => text()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

/// Roster de quem já apareceu como peer num grupo, por chave — persiste
/// mesmo que o peer esteja offline agora, diferente do estado "ao vivo" de
/// conexão (nunca persistido, ver groups_provider.dart). Sem isso, a
/// contagem de membros voltaria a "1" toda vez que o app reabre, até cada
/// peer reconectar e disparar `group_peer_join` de novo.
///
/// IMPORTANTE: [publicKeyHex] aqui é a chave que o toxcore usa para
/// identificar o peer DENTRO do grupo (`tox_group_peer_get_public_key`) —
/// estável entre reconexões, mas **diferente** da chave pública Tox do
/// amigo (por design de privacidade do NGC). Não dá pra cruzar isto com
/// [Contacts.publicKeyHex]; para "esse contato já foi convidado" ver
/// [GroupInvitedContacts] em vez disso.
class GroupMembers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get chatIdHex => text()();
  TextColumn get publicKeyHex => text()();
  TextColumn get name => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {chatIdHex, publicKeyHex}
      ];
}

/// Contatos (chave pública do AMIGO, não do peer dentro do grupo — ver
/// [GroupMembers]) que já foram convidados para um grupo — usado só para
/// não oferecer convidar de novo o mesmo contato na lista de "convidar
/// contato".
class GroupInvitedContacts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get chatIdHex => text()();
  TextColumn get contactPublicKeyHex => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {chatIdHex, contactPublicKeyHex}
      ];
}

@DriftDatabase(tables: [
  Contacts,
  Messages,
  FileTransfers,
  Groups,
  GroupMessages,
  GroupMembers,
  GroupInvitedContacts,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(messages);
          }
          if (from < 3) {
            await m.createTable(fileTransfers);
          }
          if (from < 4) {
            await m.createTable(groups);
            await m.createTable(groupMessages);
          }
          if (from < 5) {
            await m.createTable(groupMembers);
          }
          if (from < 6) {
            await m.createTable(groupInvitedContacts);
          }
          if (from < 7) {
            await m.addColumn(messages, messages.pending);
          }
          if (from < 8) {
            await m.addColumn(messages, messages.read);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: withDevProfileSuffix('talksnap'),
      native:
          DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
    );
  }
}
