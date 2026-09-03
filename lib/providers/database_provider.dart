// database_provider.dart
//
// Expõe o AppDatabase (Drift) e o ContactsRepository como providers Riverpod
// — singletons por ProviderScope, fechados automaticamente quando o
// provider é descartado.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/contacts_repository.dart';
import '../data/database.dart';
import '../data/file_transfers_repository.dart';
import '../data/messages_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final contactsRepositoryProvider = Provider<ContactsRepository>((ref) {
  return ContactsRepository(ref.watch(appDatabaseProvider));
});

final messagesRepositoryProvider = Provider<MessagesRepository>((ref) {
  return MessagesRepository(ref.watch(appDatabaseProvider));
});

final fileTransfersRepositoryProvider =
    Provider<FileTransfersRepository>((ref) {
  return FileTransfersRepository(ref.watch(appDatabaseProvider));
});
