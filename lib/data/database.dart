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

@DriftDatabase(tables: [Contacts, Messages, FileTransfers])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

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
