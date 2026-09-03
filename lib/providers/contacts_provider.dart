// contacts_provider.dart
//
// Combina três fontes numa única lista de contatos "ao vivo":
//   - o banco de dados local (Contacts, via ContactsRepository) — a fonte
//     de verdade de QUEM é contato e o apelido que VOCÊ deu a ele, sobrevive
//     a reinícios;
//   - os eventos de rede de conexão (ToxFriendConnectionEvent) — o status
//     em tempo real, nunca persistido;
//   - os eventos de rede de perfil (ToxFriendProfileEvent) — o nome/status
//     que O CONTATO definiu no perfil dele, também nunca persistido aqui
//     (é sempre reobtido do toxcore no boot, já que é dado dele, não seu).
//
// O isolate de rede não sabe que este banco existe — é este provider quem
// decide persistir (ensureExists) ou apagar (delete) um contato, reagindo
// aos eventos.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart' show Contact;
import '../tox_bindings.dart' show ToxConnection;
import '../tox_events.dart';
import 'database_provider.dart';
import 'tox_events_provider.dart';

class ContactViewModel {
  const ContactViewModel({
    required this.publicKeyHex,
    required this.nickname,
    required this.toxName,
    required this.statusMessage,
    required this.connection,
  });

  final String publicKeyHex;

  /// Apelido definido por VOCÊ (editável futuramente) — tem prioridade
  /// sobre o nome que o contato definiu no perfil dele.
  final String? nickname;

  /// Nome que o CONTATO definiu no perfil dele (via toxcore).
  final String? toxName;
  final String? statusMessage;
  final ToxConnection connection;

  /// O que mostrar na UI: apelido local > nome do contato > chave pública.
  String get displayName {
    if (nickname != null && nickname!.isNotEmpty) return nickname!;
    if (toxName != null && toxName!.isNotEmpty) return toxName!;
    return publicKeyHex;
  }
}

class ContactsNotifier extends Notifier<List<ContactViewModel>> {
  final Map<String, ToxConnection> _connectionByPublicKey = {};
  final Map<String, String> _nameByPublicKey = {};
  final Map<String, String> _statusMessageByPublicKey = {};
  List<Contact> _dbContacts = const [];
  StreamSubscription<List<Contact>>? _dbSubscription;

  @override
  List<ContactViewModel> build() {
    final repository = ref.watch(contactsRepositoryProvider);

    _dbSubscription = repository.watchAll().listen((contacts) {
      _dbContacts = contacts;
      state = _merge();
    });
    ref.onDispose(() => _dbSubscription?.cancel());

    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData(_handleEvent);
    });

    return const [];
  }

  void _handleEvent(ToxNetworkEvent event) {
    final repository = ref.read(contactsRepositoryProvider);
    switch (event) {
      case ToxFriendConnectionEvent(:final publicKeyHex, :final connection):
        _connectionByPublicKey[publicKeyHex] = connection;
        unawaited(repository.ensureExists(publicKeyHex));
        state = _merge();

      case ToxFriendProfileEvent(
          :final publicKeyHex,
          :final name,
          :final statusMessage
        ):
        _nameByPublicKey[publicKeyHex] = name;
        _statusMessageByPublicKey[publicKeyHex] = statusMessage;
        state = _merge();

      case ToxFriendRemovedEvent(:final publicKeyHex):
        _connectionByPublicKey.remove(publicKeyHex);
        _nameByPublicKey.remove(publicKeyHex);
        _statusMessageByPublicKey.remove(publicKeyHex);
        unawaited(repository.delete(publicKeyHex));

      case ToxSelfStatusEvent():
      case ToxSelfProfileEvent():
      case ToxFriendRequestEvent():
      case ToxFriendAddResultEvent():
      case ToxFriendMessageEvent():
      case ToxMessageSentEvent():
      case ToxMessageReadReceiptEvent():
      case ToxFileTransferEvent():
        break;
    }
  }

  List<ContactViewModel> _merge() {
    return [
      for (final contact in _dbContacts)
        ContactViewModel(
          publicKeyHex: contact.publicKeyHex,
          nickname: contact.nickname,
          toxName: _nameByPublicKey[contact.publicKeyHex],
          statusMessage: _statusMessageByPublicKey[contact.publicKeyHex],
          connection: _connectionByPublicKey[contact.publicKeyHex] ??
              ToxConnection.none,
        ),
    ];
  }
}

final contactsProvider =
    NotifierProvider<ContactsNotifier, List<ContactViewModel>>(
  ContactsNotifier.new,
);
