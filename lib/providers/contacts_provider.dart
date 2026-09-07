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
import '../tox_bindings.dart' show ToxConnection, kToxUserStatusNone;
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
    required this.userStatus,
    required this.isTyping,
  });

  final String publicKeyHex;

  /// Apelido definido por VOCÊ (editável futuramente) — tem prioridade
  /// sobre o nome que o contato definiu no perfil dele.
  final String? nickname;

  /// Nome que o CONTATO definiu no perfil dele (via toxcore).
  final String? toxName;
  final String? statusMessage;
  final ToxConnection connection;

  /// Presença que ELE escolheu (Online/Ausente/Ocupado — kToxUserStatus*),
  /// só faz sentido considerar quando [connection] != none.
  final int userStatus;

  /// `true` enquanto ele está digitando uma mensagem pra nós — nunca
  /// persistido, só ao vivo (ver [ToxFriendTypingEvent]).
  final bool isTyping;

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
  final Map<String, int> _userStatusByPublicKey = {};
  final Map<String, bool> _isTypingByPublicKey = {};
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
          :final statusMessage,
          :final userStatus
        ):
        _nameByPublicKey[publicKeyHex] = name;
        _statusMessageByPublicKey[publicKeyHex] = statusMessage;
        _userStatusByPublicKey[publicKeyHex] = userStatus;
        state = _merge();

      case ToxFriendTypingEvent(:final publicKeyHex, :final isTyping):
        _isTypingByPublicKey[publicKeyHex] = isTyping;
        state = _merge();

      case ToxFriendRemovedEvent(:final publicKeyHex):
        _connectionByPublicKey.remove(publicKeyHex);
        _nameByPublicKey.remove(publicKeyHex);
        _statusMessageByPublicKey.remove(publicKeyHex);
        _userStatusByPublicKey.remove(publicKeyHex);
        _isTypingByPublicKey.remove(publicKeyHex);
        unawaited(repository.delete(publicKeyHex));

      case ToxSelfStatusEvent():
      case ToxSelfProfileEvent():
      case ToxFriendRequestEvent():
      case ToxFriendAddResultEvent():
      case ToxFriendMessageEvent():
      case ToxMessageSentEvent():
      case ToxMessageReadReceiptEvent():
      case ToxFileTransferEvent():
      case ToxSavedataFlushedEvent():
      case ToxGroupCreatedEvent():
      case ToxGroupSelfJoinedEvent():
      case ToxGroupJoinFailedEvent():
      case ToxGroupInviteEvent():
      case ToxGroupMessageEvent():
      case ToxGroupMessageSentEvent():
      case ToxGroupPeerJoinedEvent():
      case ToxGroupPeerLeftEvent():
      case ToxGroupPeerNameEvent():
      case ToxGroupLeftEvent():
      case ToxGroupInviteSentEvent():
      case ToxCallIncomingEvent():
      case ToxCallStateEvent():
      case ToxCallAudioFrameEvent():
      case ToxCallVideoFrameEvent():
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
          userStatus: _userStatusByPublicKey[contact.publicKeyHex] ??
              kToxUserStatusNone,
          isTyping: _isTypingByPublicKey[contact.publicKeyHex] ?? false,
        ),
    ];
  }
}

final contactsProvider =
    NotifierProvider<ContactsNotifier, List<ContactViewModel>>(
  ContactsNotifier.new,
);
