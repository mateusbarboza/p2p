// database_provider.dart
//
// Expõe o AppDatabase (Drift) e o ContactsRepository como providers Riverpod
// — singletons por ProviderScope, fechados automaticamente quando o
// provider é descartado.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/contacts_repository.dart';
import '../data/database.dart';
import '../data/file_transfers_repository.dart';
import '../data/group_invited_contacts_repository.dart';
import '../data/group_members_repository.dart';
import '../data/group_messages_repository.dart';
import '../data/groups_repository.dart';
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

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository(ref.watch(appDatabaseProvider));
});

final groupMessagesRepositoryProvider =
    Provider<GroupMessagesRepository>((ref) {
  return GroupMessagesRepository(ref.watch(appDatabaseProvider));
});

final groupMembersRepositoryProvider = Provider<GroupMembersRepository>((ref) {
  return GroupMembersRepository(ref.watch(appDatabaseProvider));
});

final groupInvitedContactsRepositoryProvider =
    Provider<GroupInvitedContactsRepository>((ref) {
  return GroupInvitedContactsRepository(ref.watch(appDatabaseProvider));
});
