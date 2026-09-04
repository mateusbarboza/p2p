// tox_bindings.dart
//
// Camada de mais baixo nível do Talksnap: mapeia, via dart:ffi, as funções
// essenciais da biblioteca nativa `toxcore` (escrita em C) para o mundo Dart.
//
// Esta classe NÃO sabe nada sobre Isolates ou UI — ela apenas expõe as
// funções C como se fossem métodos Dart. Quem usa isso é o
// `tox_isolate_manager.dart`, rodando em background.

import 'dart:convert' show utf8;
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

/// Tamanho em bytes do "Tox ID" (Talksnap ID): 32 bytes de chave pública +
/// 4 bytes de "nospam" + 2 bytes de checksum = 38 bytes -> 76 caracteres hex.
const int kToxAddressSize = 38;

/// Tamanho em bytes de uma chave pública Tox isolada (usada para identificar
/// amigos, diferente do Talksnap ID completo que inclui nospam + checksum).
const int kToxPublicKeySize = 32;

/// Valores do enum `TOX_SAVEDATA_TYPE` da API C.
const int kToxSavedataTypeNone = 0;
const int kToxSavedataTypeToxSave = 1;

/// Converte uma string hexadecimal (maiúscula ou minúscula) para bytes.
Uint8List hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

/// Converte bytes para uma string hexadecimal maiúscula (formato usado pelo
/// toxcore para IDs e chaves públicas).
String bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString().toUpperCase();
}

/// Nó de bootstrap público da rede Tox: sem se conectar a pelo menos um
/// desses, a instância nunca sai do estado `ToxConnection.none`.
class _BootstrapNode {
  const _BootstrapNode(this.host, this.port, this._publicKeyHex);

  final String host;
  final int port;
  final String _publicKeyHex;

  Uint8List get publicKeyBytes => hexToBytes(_publicKeyHex);
}

/// Lista curta de nós públicos conhecidos e estáveis, obtida em
/// https://nodes.tox.chat/json. Não precisa ser exaustiva: basta um nó
/// responder para a instância entrar na DHT e descobrir o resto da rede.
const List<_BootstrapNode> _kBootstrapNodes = [
  _BootstrapNode(
    '3.0.24.15',
    33445,
    'E20ABCF38CDBFFD7D04B29C956B33F7B27A3BB7AF0618101617B036E4AEA402D',
  ),
  _BootstrapNode(
    'tox1.mf-net.eu',
    33445,
    'B3E5FA80DC8EBD1149AD2AB35ED8B85BD546DEDE261CA593234C619249419506',
  ),
  _BootstrapNode(
    'tox2.mf-net.eu',
    33445,
    '70EA214FDE161E7432530605213F18F7427DC773E276B3E317A07531F548545F',
  ),
  _BootstrapNode(
    '139.162.110.188',
    33445,
    'F76A11284547163889DDC89A7738CF271797BF5E5E220643E97AD3C7E7903D55',
  ),
  _BootstrapNode(
    '91.146.66.26',
    33445,
    'B5E7DAC610DBDE55F359C7F8690B294C8E4FCEC4385DE9525DBFA5523EAD9D53',
  ),
  // Nós extras (Fase 6): redes reais com NAT restritivo se beneficiam de
  // mais candidatos — se um estiver fora do ar ou bloqueado pelo firewall
  // local, os outros ainda dão à instância uma chance de entrar na DHT.
  _BootstrapNode(
    'tox.initramfs.io',
    33445,
    '3F0A45A268367C1BEA652F258C85F4A66DA76BCAA667A49E770BCC4917AB6A25',
  ),
  _BootstrapNode(
    '188.214.122.30',
    33445,
    '2A9F7A620581D5D1B09B004624559211C5ED3D1D712E8066ACDB0896A7335705',
  ),
  _BootstrapNode(
    'tox3.mf-net.eu',
    33445,
    'F4FC9398B7167668ED2BCF85634E04D4CDCDD2F95DA5F305BD234888B6E6A771',
  ),
];

/// Estados possíveis de conexão retornados por `tox_self_get_connection_status`.
/// Espelha o enum `TOX_CONNECTION` da API C.
enum ToxConnection {
  none, // 0 - sem conexão com a rede
  tcp, // 1 - conectado via relay TCP (mais lento, fallback)
  udp; // 2 - conectado via UDP (P2P direto, ideal)

  static ToxConnection fromNative(int value) {
    switch (value) {
      case 1:
        return ToxConnection.tcp;
      case 2:
        return ToxConnection.udp;
      default:
        return ToxConnection.none;
    }
  }
}

// ---------------------------------------------------------------------------
// Assinaturas nativas (C) e assinaturas Dart correspondentes.
// O sufixo "Native" descreve os tipos como o C os vê (Int32, Uint8, etc.);
// o sufixo "Dart" descreve como eles chegam no lado Dart (int, double, etc.).
// ---------------------------------------------------------------------------

// Tox *tox_new(const struct Tox_Options *options, TOX_ERR_NEW *error);
typedef _ToxNewNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Void> options,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxNewDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Void> options,
  ffi.Pointer<ffi.Int32> error,
);

// void tox_kill(Tox *tox);
typedef _ToxKillNative = ffi.Void Function(ffi.Pointer<ffi.Void> tox);
typedef _ToxKillDart = void Function(ffi.Pointer<ffi.Void> tox);

// uint32_t tox_iteration_interval(const Tox *tox);
typedef _ToxIterationIntervalNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> tox,
);
typedef _ToxIterationIntervalDart = int Function(ffi.Pointer<ffi.Void> tox);

// void tox_iterate(Tox *tox, void *user_data);
typedef _ToxIterateNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxIterateDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Void> userData,
);

// void tox_self_get_address(const Tox *tox, uint8_t *address);
typedef _ToxSelfGetAddressNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> address,
);
typedef _ToxSelfGetAddressDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> address,
);

// TOX_CONNECTION tox_self_get_connection_status(const Tox *tox);
// (Necessário para reportar "Online"/"Ausente"/"Conectando" para a UI.)
typedef _ToxSelfGetConnectionStatusNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> tox,
);
typedef _ToxSelfGetConnectionStatusDart = int Function(
  ffi.Pointer<ffi.Void> tox,
);

// struct Tox_Options *tox_options_new(TOX_ERR_OPTIONS_NEW *error);
typedef _ToxOptionsNewNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxOptionsNewDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Int32> error,
);

// void tox_options_free(struct Tox_Options *options);
typedef _ToxOptionsFreeNative = ffi.Void Function(
    ffi.Pointer<ffi.Void> options);
typedef _ToxOptionsFreeDart = void Function(ffi.Pointer<ffi.Void> options);

// void tox_options_set_savedata_type(struct Tox_Options *options, TOX_SAVEDATA_TYPE type);
typedef _ToxOptionsSetSavedataTypeNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> options,
  ffi.Int32 type,
);
typedef _ToxOptionsSetSavedataTypeDart = void Function(
  ffi.Pointer<ffi.Void> options,
  int type,
);

// void tox_options_set_savedata_data(struct Tox_Options *options, const uint8_t *data, size_t length);
typedef _ToxOptionsSetSavedataDataNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> options,
  ffi.Pointer<ffi.Uint8> data,
  ffi.Uint64 length,
);
typedef _ToxOptionsSetSavedataDataDart = void Function(
  ffi.Pointer<ffi.Void> options,
  ffi.Pointer<ffi.Uint8> data,
  int length,
);

// size_t tox_get_savedata_size(const Tox *tox);
typedef _ToxGetSavedataSizeNative = ffi.Uint64 Function(
    ffi.Pointer<ffi.Void> tox);
typedef _ToxGetSavedataSizeDart = int Function(ffi.Pointer<ffi.Void> tox);

// void tox_get_savedata(const Tox *tox, uint8_t *savedata);
typedef _ToxGetSavedataNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> savedata,
);
typedef _ToxGetSavedataDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> savedata,
);

// bool tox_bootstrap(Tox *tox, const char *host, uint16_t port, const uint8_t *public_key, TOX_ERR_BOOTSTRAP *error);
typedef _ToxBootstrapNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<pkg_ffi.Utf8> host,
  ffi.Uint16 port,
  ffi.Pointer<ffi.Uint8> publicKey,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxBootstrapDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<pkg_ffi.Utf8> host,
  int port,
  ffi.Pointer<ffi.Uint8> publicKey,
  ffi.Pointer<ffi.Int32> error,
);

// Tox_Friend_Number tox_friend_add(Tox *tox, const Tox_Address address, const uint8_t message[], size_t length, Tox_Err_Friend_Add *error);
typedef _ToxFriendAddNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> address,
  ffi.Pointer<ffi.Uint8> message,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendAddDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> address,
  ffi.Pointer<ffi.Uint8> message,
  int length,
  ffi.Pointer<ffi.Int32> error,
);

// Tox_Friend_Number tox_friend_add_norequest(Tox *tox, const Tox_Public_Key public_key, Tox_Err_Friend_Add *error);
typedef _ToxFriendAddNorequestNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> publicKey,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendAddNorequestDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> publicKey,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_friend_delete(Tox *tox, uint32_t friend_number, Tox_Err_Friend_Delete *error);
typedef _ToxFriendDeleteNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendDeleteDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_friend_get_public_key(const Tox *tox, uint32_t friend_number, Tox_Public_Key public_key, Tox_Err_Friend_Get_Public_Key *error);
typedef _ToxFriendGetPublicKeyNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Uint8> publicKey,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendGetPublicKeyDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  ffi.Pointer<ffi.Uint8> publicKey,
  ffi.Pointer<ffi.Int32> error,
);

// Tox_Connection tox_friend_get_connection_status(const Tox *tox, uint32_t friend_number, Tox_Err_Friend_Query *error);
typedef _ToxFriendGetConnectionStatusNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendGetConnectionStatusDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  ffi.Pointer<ffi.Int32> error,
);

// size_t tox_self_get_friend_list_size(const Tox *tox);
typedef _ToxSelfGetFriendListSizeNative = ffi.Uint64 Function(
    ffi.Pointer<ffi.Void> tox);
typedef _ToxSelfGetFriendListSizeDart = int Function(ffi.Pointer<ffi.Void> tox);

// void tox_self_get_friend_list(const Tox *tox, uint32_t friend_list[]);
typedef _ToxSelfGetFriendListNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint32> friendList,
);
typedef _ToxSelfGetFriendListDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint32> friendList,
);

// typedef void tox_friend_request_cb(Tox *tox, const Tox_Public_Key public_key, const uint8_t message[], size_t length, void *user_data);
// Assinatura nativa pura (para uso com Pointer.fromFunction do lado da UI/isolate) — exposta publicamente porque quem registra o callback (tox_isolate_manager.dart) precisa referenciá-la.
typedef ToxFriendRequestCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> publicKey,
  ffi.Pointer<ffi.Uint8> message,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Void> userData,
);

// void tox_callback_friend_request(Tox *tox, tox_friend_request_cb *callback);
typedef _ToxCallbackFriendRequestNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendRequestCallbackNative>> callback,
);
typedef _ToxCallbackFriendRequestDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendRequestCallbackNative>> callback,
);

// typedef void tox_friend_connection_status_cb(Tox *tox, uint32_t friend_number, Tox_Connection connection_status, void *user_data);
typedef ToxFriendConnectionStatusCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Int32 connectionStatus,
  ffi.Pointer<ffi.Void> userData,
);

// void tox_callback_friend_connection_status(Tox *tox, tox_friend_connection_status_cb *callback);
typedef _ToxCallbackFriendConnectionStatusNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendConnectionStatusCallbackNative>>
      callback,
);
typedef _ToxCallbackFriendConnectionStatusDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendConnectionStatusCallbackNative>>
      callback,
);

/// Valor do enum `TOX_MESSAGE_TYPE` usado para mensagens de texto comuns
/// (a única variante que o Talksnap envia por enquanto — `ACTION`, o
/// equivalente ao `/me` do IRC, fica para uma fase futura de UI).
const int kToxMessageTypeNormal = 0;

// typedef void tox_friend_typing_cb(Tox *tox, uint32_t friend_number, bool typing, void *user_data);
typedef ToxFriendTypingCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint8 typing,
  ffi.Pointer<ffi.Void> userData,
);

// void tox_callback_friend_typing(Tox *tox, tox_friend_typing_cb *callback);
typedef _ToxCallbackFriendTypingNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendTypingCallbackNative>> callback,
);
typedef _ToxCallbackFriendTypingDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendTypingCallbackNative>> callback,
);

// bool tox_self_set_typing(Tox *tox, uint32_t friend_number, bool typing, Tox_Err_Set_Typing *error);
typedef _ToxSelfSetTypingNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint8 typing,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxSelfSetTypingDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  int typing,
  ffi.Pointer<ffi.Int32> error,
);

// Tox_Friend_Message_Id tox_friend_send_message(Tox *tox, uint32_t friend_number, Tox_Message_Type type, const uint8_t message[], size_t length, Tox_Err_Friend_Send_Message *error);
typedef _ToxFriendSendMessageNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Int32 type,
  ffi.Pointer<ffi.Uint8> message,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendSendMessageDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  int type,
  ffi.Pointer<ffi.Uint8> message,
  int length,
  ffi.Pointer<ffi.Int32> error,
);

// typedef void tox_friend_message_cb(Tox *tox, uint32_t friend_number, Tox_Message_Type type, const uint8_t message[], size_t length, void *user_data);
typedef ToxFriendMessageCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Int32 type,
  ffi.Pointer<ffi.Uint8> message,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Void> userData,
);

// void tox_callback_friend_message(Tox *tox, tox_friend_message_cb *callback);
typedef _ToxCallbackFriendMessageNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendMessageCallbackNative>> callback,
);
typedef _ToxCallbackFriendMessageDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendMessageCallbackNative>> callback,
);

// typedef void tox_friend_read_receipt_cb(Tox *tox, uint32_t friend_number, uint32_t message_id, void *user_data);
typedef ToxFriendReadReceiptCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint32 messageId,
  ffi.Pointer<ffi.Void> userData,
);

// void tox_callback_friend_read_receipt(Tox *tox, tox_friend_read_receipt_cb *callback);
typedef _ToxCallbackFriendReadReceiptNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendReadReceiptCallbackNative>> callback,
);
typedef _ToxCallbackFriendReadReceiptDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendReadReceiptCallbackNative>> callback,
);

/// Valores do enum `TOX_FILE_KIND` — só usamos DATA (arquivos comuns); os
/// outros (avatar, sticker, hash) não fazem parte do escopo do Talksnap.
const int kToxFileKindData = 0;

/// Valores do enum `TOX_FILE_CONTROL`.
const int kToxFileControlResume = 0;
const int kToxFileControlPause = 1;
const int kToxFileControlCancel = 2;

// Tox_File_Number tox_file_send(Tox *tox, uint32_t friend_number, uint32_t kind, uint64_t file_size, const uint8_t *file_id, const uint8_t filename[], size_t filename_length, Tox_Err_File_Send *error);
typedef _ToxFileSendNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint32 kind,
  ffi.Uint64 fileSize,
  ffi.Pointer<ffi.Uint8> fileId,
  ffi.Pointer<ffi.Uint8> filename,
  ffi.Uint64 filenameLength,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFileSendDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  int kind,
  int fileSize,
  ffi.Pointer<ffi.Uint8> fileId,
  ffi.Pointer<ffi.Uint8> filename,
  int filenameLength,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_file_send_chunk(Tox *tox, uint32_t friend_number, uint32_t file_number, uint64_t position, const uint8_t data[], size_t length, Tox_Err_File_Send_Chunk *error);
typedef _ToxFileSendChunkNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint32 fileNumber,
  ffi.Uint64 position,
  ffi.Pointer<ffi.Uint8> data,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFileSendChunkDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  int fileNumber,
  int position,
  ffi.Pointer<ffi.Uint8> data,
  int length,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_file_control(Tox *tox, uint32_t friend_number, uint32_t file_number, Tox_File_Control control, Tox_Err_File_Control *error);
typedef _ToxFileControlNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint32 fileNumber,
  ffi.Int32 control,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFileControlDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  int fileNumber,
  int control,
  ffi.Pointer<ffi.Int32> error,
);

// typedef void tox_file_recv_cb(Tox *tox, uint32_t friend_number, uint32_t file_number, uint32_t kind, uint64_t file_size, const uint8_t filename[], size_t filename_length, void *user_data);
typedef ToxFileRecvCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint32 fileNumber,
  ffi.Uint32 kind,
  ffi.Uint64 fileSize,
  ffi.Pointer<ffi.Uint8> filename,
  ffi.Uint64 filenameLength,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackFileRecvNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFileRecvCallbackNative>> callback,
);
typedef _ToxCallbackFileRecvDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFileRecvCallbackNative>> callback,
);

// typedef void tox_file_recv_chunk_cb(Tox *tox, uint32_t friend_number, uint32_t file_number, uint64_t position, const uint8_t data[], size_t length, void *user_data);
typedef ToxFileRecvChunkCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint32 fileNumber,
  ffi.Uint64 position,
  ffi.Pointer<ffi.Uint8> data,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackFileRecvChunkNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFileRecvChunkCallbackNative>> callback,
);
typedef _ToxCallbackFileRecvChunkDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFileRecvChunkCallbackNative>> callback,
);

// typedef void tox_file_chunk_request_cb(Tox *tox, uint32_t friend_number, uint32_t file_number, uint64_t position, size_t length, void *user_data);
typedef ToxFileChunkRequestCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint32 fileNumber,
  ffi.Uint64 position,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackFileChunkRequestNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFileChunkRequestCallbackNative>> callback,
);
typedef _ToxCallbackFileChunkRequestDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFileChunkRequestCallbackNative>> callback,
);

// typedef void tox_file_recv_control_cb(Tox *tox, uint32_t friend_number, uint32_t file_number, Tox_File_Control control, void *user_data);
typedef ToxFileRecvControlCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Uint32 fileNumber,
  ffi.Int32 control,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackFileRecvControlNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFileRecvControlCallbackNative>> callback,
);
typedef _ToxCallbackFileRecvControlDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFileRecvControlCallbackNative>> callback,
);

/// Valores do enum `TOX_USER_STATUS` — status de presença que o usuário
/// escolhe manualmente (diferente de `ToxConnection`, que é a conectividade
/// de rede). Mostrado como "Online"/"Ausente"/"Ocupado" na UI.
const int kToxUserStatusNone = 0; // "Online" (disponível)
const int kToxUserStatusAway = 1;
const int kToxUserStatusBusy = 2;

/// Valor de `TOX_ERR_FRIEND_SEND_MESSAGE_FRIEND_NOT_CONNECTED` — usado por
/// [ToxBindings.friendSendMessage] para distinguir "amigo offline agora"
/// (mensagem deve ser enfileirada e reenviada depois) de qualquer outro
/// erro real de envio.
const int kToxErrFriendSendMessageFriendNotConnected = 3;

/// Lançada por [ToxBindings.friendSendMessage] quando o amigo não está
/// conectado no momento do envio — não é um erro real, apenas sinaliza que
/// a mensagem deve ser guardada como pendente e reenviada quando ele
/// conectar (ver `SendMessageCommand` em tox_isolate_manager.dart).
class ToxFriendNotConnectedException implements Exception {
  const ToxFriendNotConnectedException();

  @override
  String toString() => 'Contato está offline no momento.';
}

// void tox_self_set_status(Tox *tox, Tox_User_Status status);
typedef _ToxSelfSetStatusNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Int32 status,
);
typedef _ToxSelfSetStatusDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  int status,
);

// Tox_User_Status tox_self_get_status(const Tox *tox);
typedef _ToxSelfGetStatusNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> tox);
typedef _ToxSelfGetStatusDart = int Function(ffi.Pointer<ffi.Void> tox);

// Tox_User_Status tox_friend_get_status(const Tox *tox, uint32_t friend_number, Tox_Err_Friend_Query *error);
typedef _ToxFriendGetUserStatusNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendGetUserStatusDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  ffi.Pointer<ffi.Int32> error,
);

// typedef void tox_friend_status_cb(Tox *tox, uint32_t friend_number, Tox_User_Status status, void *user_data);
typedef ToxFriendUserStatusCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Int32 status,
  ffi.Pointer<ffi.Void> userData,
);

// void tox_callback_friend_status(Tox *tox, tox_friend_status_cb *callback);
typedef _ToxCallbackFriendUserStatusNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendUserStatusCallbackNative>> callback,
);
typedef _ToxCallbackFriendUserStatusDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendUserStatusCallbackNative>> callback,
);

// bool tox_self_set_name(Tox *tox, const uint8_t name[], size_t length, Tox_Err_Set_Info *error);
typedef _ToxSelfSetNameNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxSelfSetNameDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> name,
  int length,
  ffi.Pointer<ffi.Int32> error,
);

// size_t tox_self_get_name_size(const Tox *tox);
typedef _ToxSelfGetNameSizeNative = ffi.Uint64 Function(
    ffi.Pointer<ffi.Void> tox);
typedef _ToxSelfGetNameSizeDart = int Function(ffi.Pointer<ffi.Void> tox);

// void tox_self_get_name(const Tox *tox, uint8_t name[]);
typedef _ToxSelfGetNameNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> name,
);
typedef _ToxSelfGetNameDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> name,
);

// bool tox_self_set_status_message(Tox *tox, const uint8_t status_message[], size_t length, Tox_Err_Set_Info *error);
typedef _ToxSelfSetStatusMessageNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> statusMessage,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxSelfSetStatusMessageDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> statusMessage,
  int length,
  ffi.Pointer<ffi.Int32> error,
);

// size_t tox_self_get_status_message_size(const Tox *tox);
typedef _ToxSelfGetStatusMessageSizeNative = ffi.Uint64 Function(
    ffi.Pointer<ffi.Void> tox);
typedef _ToxSelfGetStatusMessageSizeDart = int Function(
    ffi.Pointer<ffi.Void> tox);

// void tox_self_get_status_message(const Tox *tox, uint8_t status_message[]);
typedef _ToxSelfGetStatusMessageNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> statusMessage,
);
typedef _ToxSelfGetStatusMessageDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint8> statusMessage,
);

// size_t tox_friend_get_name_size(const Tox *tox, uint32_t friend_number, Tox_Err_Friend_Query *error);
typedef _ToxFriendGetNameSizeNative = ffi.Uint64 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendGetNameSizeDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_friend_get_name(const Tox *tox, uint32_t friend_number, uint8_t name[], Tox_Err_Friend_Query *error);
typedef _ToxFriendGetNameNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendGetNameDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Pointer<ffi.Int32> error,
);

// size_t tox_friend_get_status_message_size(const Tox *tox, uint32_t friend_number, Tox_Err_Friend_Query *error);
typedef _ToxFriendGetStatusMessageSizeNative = ffi.Uint64 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendGetStatusMessageSizeDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_friend_get_status_message(const Tox *tox, uint32_t friend_number, uint8_t status_message[], Tox_Err_Friend_Query *error);
typedef _ToxFriendGetStatusMessageNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Uint8> statusMessage,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxFriendGetStatusMessageDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  ffi.Pointer<ffi.Uint8> statusMessage,
  ffi.Pointer<ffi.Int32> error,
);

// typedef void tox_friend_name_cb(Tox *tox, uint32_t friend_number, const uint8_t name[], size_t length, void *user_data);
typedef ToxFriendNameCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackFriendNameNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendNameCallbackNative>> callback,
);
typedef _ToxCallbackFriendNameDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendNameCallbackNative>> callback,
);

// typedef void tox_friend_status_message_cb(Tox *tox, uint32_t friend_number, const uint8_t message[], size_t length, void *user_data);
typedef ToxFriendStatusMessageCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Uint8> message,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackFriendStatusMessageNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendStatusMessageCallbackNative>>
      callback,
);
typedef _ToxCallbackFriendStatusMessageDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxFriendStatusMessageCallbackNative>>
      callback,
);

// ---------------------------------------------------------------------------
// Grupos (API "NGC" — tox_group_*). Mesmo padrão dos amigos: group_number é
// efêmero por sessão; a chave estável entre execuções é o Chat ID (32 bytes,
// via tox_group_get_chat_id — o equivalente de uma "chave pública" de grupo).
// O estado dos grupos já é salvo dentro do savedata geral do toxcore, então
// não precisa de nenhuma persistência nativa extra.
// ---------------------------------------------------------------------------

/// Valores do enum `TOX_GROUP_PRIVACY_STATE`. O Talksnap só cria grupos
/// privados — quem entra precisa ser convidado por um amigo já existente,
/// nunca por Chat ID público.
const int kToxGroupPrivacyStatePrivate = 1;

/// Tamanho em bytes do Chat ID de um grupo (`TOX_GROUP_CHAT_ID_SIZE`).
const int kToxGroupChatIdSize = 32;

/// Valor do enum `TOX_GROUP_ROLE` que designa quem criou o grupo — usado
/// para decidir se a UI mostra "Excluir grupo" (fundador) ou "Sair do
/// grupo" (demais membros). Não existe "apagar para todos" num grupo P2P
/// sem servidor — ambas as ações chamam `tox_group_leave` por baixo, só a
/// rotulagem muda.
const int kToxGroupRoleFounder = 0;

// bool tox_group_is_connected(const Tox *tox, Tox_Group_Number group_number, Tox_Err_Group_Is_Connected *error);
typedef _ToxGroupIsConnectedNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupIsConnectedDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  ffi.Pointer<ffi.Int32> error,
);

// Tox_Group_Number tox_group_new(Tox *tox, Tox_Group_Privacy_State privacy_state, const uint8_t group_name[], size_t group_name_length, const uint8_t name[], size_t name_length, Tox_Err_Group_New *error);
typedef _ToxGroupNewNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Int32 privacyState,
  ffi.Pointer<ffi.Uint8> groupName,
  ffi.Uint64 groupNameLength,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Uint64 nameLength,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupNewDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int privacyState,
  ffi.Pointer<ffi.Uint8> groupName,
  int groupNameLength,
  ffi.Pointer<ffi.Uint8> name,
  int nameLength,
  ffi.Pointer<ffi.Int32> error,
);

// Tox_Group_Message_Id tox_group_send_message(const Tox *tox, Tox_Group_Number group_number, Tox_Message_Type message_type, const uint8_t message[], size_t length, Tox_Err_Group_Send_Message *error);
typedef _ToxGroupSendMessageNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Int32 messageType,
  ffi.Pointer<ffi.Uint8> message,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupSendMessageDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  int messageType,
  ffi.Pointer<ffi.Uint8> message,
  int length,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_group_invite_friend(const Tox *tox, Tox_Group_Number group_number, Tox_Friend_Number friend_number, Tox_Err_Group_Invite_Friend *error);
typedef _ToxGroupInviteFriendNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupInviteFriendDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  int friendNumber,
  ffi.Pointer<ffi.Int32> error,
);

// Tox_Group_Number tox_group_invite_accept(Tox *tox, Tox_Friend_Number friend_number, const uint8_t invite_data[], size_t length, const uint8_t name[], size_t name_length, const uint8_t password[], size_t password_length, Tox_Err_Group_Invite_Accept *error);
typedef _ToxGroupInviteAcceptNative = ffi.Uint32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Uint8> inviteData,
  ffi.Uint64 inviteDataLength,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Uint64 nameLength,
  ffi.Pointer<ffi.Uint8> password,
  ffi.Uint64 passwordLength,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupInviteAcceptDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int friendNumber,
  ffi.Pointer<ffi.Uint8> inviteData,
  int inviteDataLength,
  ffi.Pointer<ffi.Uint8> name,
  int nameLength,
  ffi.Pointer<ffi.Uint8> password,
  int passwordLength,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_group_leave(Tox *tox, Tox_Group_Number group_number, const uint8_t part_message[], size_t length, Tox_Err_Group_Leave *error);
typedef _ToxGroupLeaveNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Pointer<ffi.Uint8> partMessage,
  ffi.Uint64 length,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupLeaveDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  ffi.Pointer<ffi.Uint8> partMessage,
  int length,
  ffi.Pointer<ffi.Int32> error,
);

// size_t tox_group_get_name_size(const Tox *tox, Tox_Group_Number group_number, Tox_Err_Group_State_Query *error);
typedef _ToxGroupGetNameSizeNative = ffi.Uint64 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupGetNameSizeDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_group_get_name(const Tox *tox, Tox_Group_Number group_number, uint8_t name[], Tox_Err_Group_State_Query *error);
typedef _ToxGroupGetNameNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupGetNameDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_group_get_chat_id(const Tox *tox, Tox_Group_Number group_number, Tox_Group_Chat_Id chat_id, Tox_Err_Group_State_Query *error);
typedef _ToxGroupGetChatIdNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Pointer<ffi.Uint8> chatId,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupGetChatIdDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  ffi.Pointer<ffi.Uint8> chatId,
  ffi.Pointer<ffi.Int32> error,
);

// Tox_Group_Role tox_group_self_get_role(const Tox *tox, Tox_Group_Number group_number, Tox_Err_Group_Self_Query *error);
typedef _ToxGroupSelfGetRoleNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupSelfGetRoleDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  ffi.Pointer<ffi.Int32> error,
);

// size_t tox_group_peer_get_name_size(const Tox *tox, Tox_Group_Number group_number, Tox_Group_Peer_Number peer_id, Tox_Err_Group_Peer_Query *error);
typedef _ToxGroupPeerGetNameSizeNative = ffi.Uint64 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Uint32 peerId,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupPeerGetNameSizeDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  int peerId,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_group_peer_get_name(const Tox *tox, Tox_Group_Number group_number, Tox_Group_Peer_Number peer_id, uint8_t name[], Tox_Err_Group_Peer_Query *error);
typedef _ToxGroupPeerGetNameNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Uint32 peerId,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupPeerGetNameDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  int peerId,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Pointer<ffi.Int32> error,
);

// bool tox_group_peer_get_public_key(const Tox *tox, Tox_Group_Number group_number, Tox_Group_Peer_Number peer_id, Tox_Public_Key public_key, Tox_Err_Group_Peer_Query *error);
typedef _ToxGroupPeerGetPublicKeyNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Uint32 peerId,
  ffi.Pointer<ffi.Uint8> publicKey,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupPeerGetPublicKeyDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  int peerId,
  ffi.Pointer<ffi.Uint8> publicKey,
  ffi.Pointer<ffi.Int32> error,
);

// Tox_Connection tox_group_peer_get_connection_status(const Tox *tox, Tox_Group_Number group_number, Tox_Group_Peer_Number peer_id, Tox_Err_Group_Peer_Query *error);
typedef _ToxGroupPeerGetConnectionStatusNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Uint32 peerId,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxGroupPeerGetConnectionStatusDart = int Function(
  ffi.Pointer<ffi.Void> tox,
  int groupNumber,
  int peerId,
  ffi.Pointer<ffi.Int32> error,
);

// uint32_t tox_group_get_group_list_size(const Tox *tox);
typedef _ToxGroupGetGroupListSizeNative = ffi.Uint32 Function(
    ffi.Pointer<ffi.Void> tox);
typedef _ToxGroupGetGroupListSizeDart = int Function(ffi.Pointer<ffi.Void> tox);

// void tox_group_get_group_list(const Tox *tox, Tox_Group_Number group_list[]);
typedef _ToxGroupGetGroupListNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint32> groupList,
);
typedef _ToxGroupGetGroupListDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Uint32> groupList,
);

// typedef void tox_group_invite_cb(Tox *tox, Tox_Friend_Number friend_number, const uint8_t invite_data[], size_t invite_data_length, const uint8_t group_name[], size_t group_name_length, void *user_data);
typedef ToxGroupInviteCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Uint8> inviteData,
  ffi.Uint64 inviteDataLength,
  ffi.Pointer<ffi.Uint8> groupName,
  ffi.Uint64 groupNameLength,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackGroupInviteNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupInviteCallbackNative>> callback,
);
typedef _ToxCallbackGroupInviteDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupInviteCallbackNative>> callback,
);

// typedef void tox_group_message_cb(Tox *tox, Tox_Group_Number group_number, Tox_Group_Peer_Number peer_id, Tox_Message_Type message_type, const uint8_t message[], size_t message_length, Tox_Group_Message_Id message_id, void *user_data);
typedef ToxGroupMessageCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Uint32 peerId,
  ffi.Int32 messageType,
  ffi.Pointer<ffi.Uint8> message,
  ffi.Uint64 messageLength,
  ffi.Uint32 messageId,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackGroupMessageNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupMessageCallbackNative>> callback,
);
typedef _ToxCallbackGroupMessageDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupMessageCallbackNative>> callback,
);

// typedef void tox_group_peer_join_cb(Tox *tox, Tox_Group_Number group_number, Tox_Group_Peer_Number peer_id, void *user_data);
typedef ToxGroupPeerJoinCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Uint32 peerId,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackGroupPeerJoinNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupPeerJoinCallbackNative>> callback,
);
typedef _ToxCallbackGroupPeerJoinDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupPeerJoinCallbackNative>> callback,
);

// typedef void tox_group_peer_exit_cb(Tox *tox, Tox_Group_Number group_number, Tox_Group_Peer_Number peer_id, Tox_Group_Exit_Type exit_type, const uint8_t name[], size_t name_length, const uint8_t part_message[], size_t part_message_length, void *user_data);
typedef ToxGroupPeerExitCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Uint32 peerId,
  ffi.Int32 exitType,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Uint64 nameLength,
  ffi.Pointer<ffi.Uint8> partMessage,
  ffi.Uint64 partMessageLength,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackGroupPeerExitNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupPeerExitCallbackNative>> callback,
);
typedef _ToxCallbackGroupPeerExitDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupPeerExitCallbackNative>> callback,
);

// typedef void tox_group_self_join_cb(Tox *tox, Tox_Group_Number group_number, void *user_data);
typedef ToxGroupSelfJoinCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackGroupSelfJoinNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupSelfJoinCallbackNative>> callback,
);
typedef _ToxCallbackGroupSelfJoinDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupSelfJoinCallbackNative>> callback,
);

// typedef void tox_group_join_fail_cb(Tox *tox, Tox_Group_Number group_number, Tox_Group_Join_Fail fail_type, void *user_data);
typedef ToxGroupJoinFailCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Int32 failType,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackGroupJoinFailNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupJoinFailCallbackNative>> callback,
);
typedef _ToxCallbackGroupJoinFailDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupJoinFailCallbackNative>> callback,
);

// typedef void tox_group_peer_name_cb(Tox *tox, Tox_Group_Number group_number, Tox_Group_Peer_Number peer_id, const uint8_t name[], size_t name_length, void *user_data);
typedef ToxGroupPeerNameCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Uint32 groupNumber,
  ffi.Uint32 peerId,
  ffi.Pointer<ffi.Uint8> name,
  ffi.Uint64 nameLength,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxCallbackGroupPeerNameNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupPeerNameCallbackNative>> callback,
);
typedef _ToxCallbackGroupPeerNameDart = void Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.NativeFunction<ToxGroupPeerNameCallbackNative>> callback,
);

/// Wrapper único e cacheado sobre a `DynamicLibrary` do toxcore.
///
/// Uso: `ToxCoreBindings.instance.toxNew(...)`.
class ToxCoreBindings {
  ToxCoreBindings._internal(this._lib) {
    _bind();
  }

  static ToxCoreBindings? _cachedInstance;

  /// Ponto de acesso único (singleton) — evita reabrir a lib nativa várias vezes.
  static ToxCoreBindings get instance {
    return _cachedInstance ??= ToxCoreBindings._internal(_loadLibrary());
  }

  final ffi.DynamicLibrary _lib;

  late final _ToxNewDart toxNew;
  late final _ToxKillDart toxKill;
  late final _ToxIterationIntervalDart toxIterationInterval;
  late final _ToxIterateDart toxIterate;
  late final _ToxSelfGetAddressDart toxSelfGetAddress;
  late final _ToxSelfGetConnectionStatusDart toxSelfGetConnectionStatus;
  late final _ToxOptionsNewDart _toxOptionsNew;
  late final _ToxOptionsFreeDart _toxOptionsFree;
  late final _ToxOptionsSetSavedataTypeDart _toxOptionsSetSavedataType;
  late final _ToxOptionsSetSavedataDataDart _toxOptionsSetSavedataData;
  late final _ToxGetSavedataSizeDart _toxGetSavedataSize;
  late final _ToxGetSavedataDart _toxGetSavedata;
  late final _ToxBootstrapDart _toxBootstrap;
  late final _ToxFriendAddDart _toxFriendAdd;
  late final _ToxFriendAddNorequestDart _toxFriendAddNorequest;
  late final _ToxFriendDeleteDart _toxFriendDelete;
  late final _ToxFriendGetPublicKeyDart _toxFriendGetPublicKey;
  late final _ToxFriendGetConnectionStatusDart _toxFriendGetConnectionStatus;
  late final _ToxSelfGetFriendListSizeDart _toxSelfGetFriendListSize;
  late final _ToxSelfGetFriendListDart _toxSelfGetFriendList;
  late final _ToxCallbackFriendRequestDart _toxCallbackFriendRequest;
  late final _ToxCallbackFriendConnectionStatusDart
      _toxCallbackFriendConnectionStatus;
  late final _ToxFriendSendMessageDart _toxFriendSendMessage;
  late final _ToxCallbackFriendTypingDart _toxCallbackFriendTyping;
  late final _ToxSelfSetTypingDart _toxSelfSetTyping;
  late final _ToxCallbackFriendMessageDart _toxCallbackFriendMessage;
  late final _ToxCallbackFriendReadReceiptDart _toxCallbackFriendReadReceipt;
  late final _ToxFileSendDart _toxFileSend;
  late final _ToxFileSendChunkDart _toxFileSendChunk;
  late final _ToxFileControlDart _toxFileControl;
  late final _ToxCallbackFileRecvDart _toxCallbackFileRecv;
  late final _ToxCallbackFileRecvChunkDart _toxCallbackFileRecvChunk;
  late final _ToxCallbackFileChunkRequestDart _toxCallbackFileChunkRequest;
  late final _ToxCallbackFileRecvControlDart _toxCallbackFileRecvControl;
  late final _ToxSelfSetStatusDart _toxSelfSetStatus;
  late final _ToxSelfGetStatusDart _toxSelfGetStatus;
  late final _ToxSelfSetNameDart _toxSelfSetName;
  late final _ToxSelfGetNameSizeDart _toxSelfGetNameSize;
  late final _ToxSelfGetNameDart _toxSelfGetName;
  late final _ToxSelfSetStatusMessageDart _toxSelfSetStatusMessage;
  late final _ToxSelfGetStatusMessageSizeDart _toxSelfGetStatusMessageSize;
  late final _ToxSelfGetStatusMessageDart _toxSelfGetStatusMessage;
  late final _ToxFriendGetNameSizeDart _toxFriendGetNameSize;
  late final _ToxFriendGetNameDart _toxFriendGetName;
  late final _ToxFriendGetStatusMessageSizeDart _toxFriendGetStatusMessageSize;
  late final _ToxFriendGetStatusMessageDart _toxFriendGetStatusMessage;
  late final _ToxFriendGetUserStatusDart _toxFriendGetUserStatus;
  late final _ToxCallbackFriendUserStatusDart _toxCallbackFriendUserStatus;
  late final _ToxCallbackFriendNameDart _toxCallbackFriendName;
  late final _ToxCallbackFriendStatusMessageDart
      _toxCallbackFriendStatusMessage;
  late final _ToxGroupIsConnectedDart _toxGroupIsConnected;
  late final _ToxGroupNewDart _toxGroupNew;
  late final _ToxGroupSendMessageDart _toxGroupSendMessage;
  late final _ToxGroupInviteFriendDart _toxGroupInviteFriend;
  late final _ToxGroupInviteAcceptDart _toxGroupInviteAccept;
  late final _ToxGroupLeaveDart _toxGroupLeave;
  late final _ToxGroupSelfGetRoleDart _toxGroupSelfGetRole;
  late final _ToxGroupGetNameSizeDart _toxGroupGetNameSize;
  late final _ToxGroupGetNameDart _toxGroupGetName;
  late final _ToxGroupGetChatIdDart _toxGroupGetChatId;
  late final _ToxGroupPeerGetNameSizeDart _toxGroupPeerGetNameSize;
  late final _ToxGroupPeerGetNameDart _toxGroupPeerGetName;
  late final _ToxGroupPeerGetPublicKeyDart _toxGroupPeerGetPublicKey;
  late final _ToxGroupPeerGetConnectionStatusDart
      _toxGroupPeerGetConnectionStatus;
  late final _ToxGroupGetGroupListSizeDart _toxGroupGetGroupListSize;
  late final _ToxGroupGetGroupListDart _toxGroupGetGroupList;
  late final _ToxCallbackGroupInviteDart _toxCallbackGroupInvite;
  late final _ToxCallbackGroupMessageDart _toxCallbackGroupMessage;
  late final _ToxCallbackGroupPeerJoinDart _toxCallbackGroupPeerJoin;
  late final _ToxCallbackGroupPeerExitDart _toxCallbackGroupPeerExit;
  late final _ToxCallbackGroupSelfJoinDart _toxCallbackGroupSelfJoin;
  late final _ToxCallbackGroupJoinFailDart _toxCallbackGroupJoinFail;
  late final _ToxCallbackGroupPeerNameDart _toxCallbackGroupPeerName;

  /// Identifica o sistema operacional em tempo de execução e carrega o
  /// binário nativo correto do toxcore para cada plataforma.
  static ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) {
      // .dll ao lado do executável (ou em PATH) no Windows.
      return ffi.DynamicLibrary.open('toxcore.dll');
    } else if (Platform.isAndroid) {
      // .so embarcada em android/app/src/main/jniLibs/<abi>/.
      return ffi.DynamicLibrary.open('libtoxcore.so');
    } else if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libtoxcore.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      // No iOS/macOS o toxcore normalmente é compilado como biblioteca
      // estática e linkado direto no binário do app (via .framework/xcframework),
      // então acessamos os símbolos já carregados no processo atual —
      // não existe um arquivo .so/.dll separado para abrir.
      return ffi.DynamicLibrary.process();
    }
    throw UnsupportedError(
      'Plataforma não suportada pelo Talksnap: ${Platform.operatingSystem}',
    );
  }

  /// Resolve cada símbolo C uma única vez e guarda a função Dart tipada.
  void _bind() {
    toxNew = _lib.lookupFunction<_ToxNewNative, _ToxNewDart>('tox_new');
    toxKill = _lib.lookupFunction<_ToxKillNative, _ToxKillDart>('tox_kill');
    toxIterationInterval = _lib
        .lookupFunction<_ToxIterationIntervalNative, _ToxIterationIntervalDart>(
      'tox_iteration_interval',
    );
    toxIterate =
        _lib.lookupFunction<_ToxIterateNative, _ToxIterateDart>('tox_iterate');
    toxSelfGetAddress =
        _lib.lookupFunction<_ToxSelfGetAddressNative, _ToxSelfGetAddressDart>(
      'tox_self_get_address',
    );
    toxSelfGetConnectionStatus = _lib.lookupFunction<
        _ToxSelfGetConnectionStatusNative,
        _ToxSelfGetConnectionStatusDart>('tox_self_get_connection_status');
    _toxOptionsNew =
        _lib.lookupFunction<_ToxOptionsNewNative, _ToxOptionsNewDart>(
            'tox_options_new');
    _toxOptionsFree =
        _lib.lookupFunction<_ToxOptionsFreeNative, _ToxOptionsFreeDart>(
      'tox_options_free',
    );
    _toxOptionsSetSavedataType = _lib.lookupFunction<
        _ToxOptionsSetSavedataTypeNative,
        _ToxOptionsSetSavedataTypeDart>('tox_options_set_savedata_type');
    _toxOptionsSetSavedataData = _lib.lookupFunction<
        _ToxOptionsSetSavedataDataNative,
        _ToxOptionsSetSavedataDataDart>('tox_options_set_savedata_data');
    _toxGetSavedataSize =
        _lib.lookupFunction<_ToxGetSavedataSizeNative, _ToxGetSavedataSizeDart>(
      'tox_get_savedata_size',
    );
    _toxGetSavedata =
        _lib.lookupFunction<_ToxGetSavedataNative, _ToxGetSavedataDart>(
      'tox_get_savedata',
    );
    _toxBootstrap = _lib.lookupFunction<_ToxBootstrapNative, _ToxBootstrapDart>(
        'tox_bootstrap');
    _toxFriendAdd = _lib.lookupFunction<_ToxFriendAddNative, _ToxFriendAddDart>(
        'tox_friend_add');
    _toxFriendAddNorequest = _lib.lookupFunction<_ToxFriendAddNorequestNative,
        _ToxFriendAddNorequestDart>('tox_friend_add_norequest');
    _toxFriendDelete =
        _lib.lookupFunction<_ToxFriendDeleteNative, _ToxFriendDeleteDart>(
      'tox_friend_delete',
    );
    _toxFriendGetPublicKey = _lib.lookupFunction<_ToxFriendGetPublicKeyNative,
        _ToxFriendGetPublicKeyDart>('tox_friend_get_public_key');
    _toxFriendGetConnectionStatus = _lib.lookupFunction<
        _ToxFriendGetConnectionStatusNative,
        _ToxFriendGetConnectionStatusDart>('tox_friend_get_connection_status');
    _toxSelfGetFriendListSize = _lib.lookupFunction<
        _ToxSelfGetFriendListSizeNative,
        _ToxSelfGetFriendListSizeDart>('tox_self_get_friend_list_size');
    _toxSelfGetFriendList = _lib
        .lookupFunction<_ToxSelfGetFriendListNative, _ToxSelfGetFriendListDart>(
      'tox_self_get_friend_list',
    );
    _toxCallbackFriendRequest = _lib.lookupFunction<
        _ToxCallbackFriendRequestNative,
        _ToxCallbackFriendRequestDart>('tox_callback_friend_request');
    _toxCallbackFriendConnectionStatus = _lib.lookupFunction<
            _ToxCallbackFriendConnectionStatusNative,
            _ToxCallbackFriendConnectionStatusDart>(
        'tox_callback_friend_connection_status');
    _toxFriendSendMessage = _lib.lookupFunction<_ToxFriendSendMessageNative,
        _ToxFriendSendMessageDart>('tox_friend_send_message');
    _toxCallbackFriendTyping = _lib.lookupFunction<
        _ToxCallbackFriendTypingNative,
        _ToxCallbackFriendTypingDart>('tox_callback_friend_typing');
    _toxSelfSetTyping =
        _lib.lookupFunction<_ToxSelfSetTypingNative, _ToxSelfSetTypingDart>(
            'tox_self_set_typing');
    _toxCallbackFriendMessage = _lib.lookupFunction<
        _ToxCallbackFriendMessageNative,
        _ToxCallbackFriendMessageDart>('tox_callback_friend_message');
    _toxCallbackFriendReadReceipt = _lib.lookupFunction<
        _ToxCallbackFriendReadReceiptNative,
        _ToxCallbackFriendReadReceiptDart>('tox_callback_friend_read_receipt');
    _toxFileSend = _lib
        .lookupFunction<_ToxFileSendNative, _ToxFileSendDart>('tox_file_send');
    _toxFileSendChunk =
        _lib.lookupFunction<_ToxFileSendChunkNative, _ToxFileSendChunkDart>(
            'tox_file_send_chunk');
    _toxFileControl =
        _lib.lookupFunction<_ToxFileControlNative, _ToxFileControlDart>(
            'tox_file_control');
    _toxCallbackFileRecv = _lib
        .lookupFunction<_ToxCallbackFileRecvNative, _ToxCallbackFileRecvDart>(
      'tox_callback_file_recv',
    );
    _toxCallbackFileRecvChunk = _lib.lookupFunction<
        _ToxCallbackFileRecvChunkNative,
        _ToxCallbackFileRecvChunkDart>('tox_callback_file_recv_chunk');
    _toxCallbackFileChunkRequest = _lib.lookupFunction<
        _ToxCallbackFileChunkRequestNative,
        _ToxCallbackFileChunkRequestDart>('tox_callback_file_chunk_request');
    _toxCallbackFileRecvControl = _lib.lookupFunction<
        _ToxCallbackFileRecvControlNative,
        _ToxCallbackFileRecvControlDart>('tox_callback_file_recv_control');
    _toxSelfSetStatus =
        _lib.lookupFunction<_ToxSelfSetStatusNative, _ToxSelfSetStatusDart>(
            'tox_self_set_status');
    _toxSelfGetStatus =
        _lib.lookupFunction<_ToxSelfGetStatusNative, _ToxSelfGetStatusDart>(
            'tox_self_get_status');
    _toxSelfSetName =
        _lib.lookupFunction<_ToxSelfSetNameNative, _ToxSelfSetNameDart>(
            'tox_self_set_name');
    _toxSelfGetNameSize =
        _lib.lookupFunction<_ToxSelfGetNameSizeNative, _ToxSelfGetNameSizeDart>(
            'tox_self_get_name_size');
    _toxSelfGetName =
        _lib.lookupFunction<_ToxSelfGetNameNative, _ToxSelfGetNameDart>(
            'tox_self_get_name');
    _toxSelfSetStatusMessage = _lib.lookupFunction<
        _ToxSelfSetStatusMessageNative,
        _ToxSelfSetStatusMessageDart>('tox_self_set_status_message');
    _toxSelfGetStatusMessageSize = _lib.lookupFunction<
        _ToxSelfGetStatusMessageSizeNative,
        _ToxSelfGetStatusMessageSizeDart>('tox_self_get_status_message_size');
    _toxSelfGetStatusMessage = _lib.lookupFunction<
        _ToxSelfGetStatusMessageNative,
        _ToxSelfGetStatusMessageDart>('tox_self_get_status_message');
    _toxFriendGetNameSize = _lib.lookupFunction<_ToxFriendGetNameSizeNative,
        _ToxFriendGetNameSizeDart>('tox_friend_get_name_size');
    _toxFriendGetName =
        _lib.lookupFunction<_ToxFriendGetNameNative, _ToxFriendGetNameDart>(
            'tox_friend_get_name');
    _toxFriendGetStatusMessageSize = _lib.lookupFunction<
            _ToxFriendGetStatusMessageSizeNative,
            _ToxFriendGetStatusMessageSizeDart>(
        'tox_friend_get_status_message_size');
    _toxFriendGetStatusMessage = _lib.lookupFunction<
        _ToxFriendGetStatusMessageNative,
        _ToxFriendGetStatusMessageDart>('tox_friend_get_status_message');
    _toxFriendGetUserStatus = _lib.lookupFunction<_ToxFriendGetUserStatusNative,
        _ToxFriendGetUserStatusDart>('tox_friend_get_status');
    _toxCallbackFriendUserStatus = _lib.lookupFunction<
        _ToxCallbackFriendUserStatusNative,
        _ToxCallbackFriendUserStatusDart>('tox_callback_friend_status');
    _toxCallbackFriendName = _lib.lookupFunction<_ToxCallbackFriendNameNative,
        _ToxCallbackFriendNameDart>('tox_callback_friend_name');
    _toxCallbackFriendStatusMessage = _lib.lookupFunction<
            _ToxCallbackFriendStatusMessageNative,
            _ToxCallbackFriendStatusMessageDart>(
        'tox_callback_friend_status_message');
    _toxGroupIsConnected = _lib.lookupFunction<_ToxGroupIsConnectedNative,
        _ToxGroupIsConnectedDart>('tox_group_is_connected');
    _toxGroupNew = _lib
        .lookupFunction<_ToxGroupNewNative, _ToxGroupNewDart>('tox_group_new');
    _toxGroupSendMessage = _lib.lookupFunction<_ToxGroupSendMessageNative,
        _ToxGroupSendMessageDart>('tox_group_send_message');
    _toxGroupInviteFriend = _lib.lookupFunction<_ToxGroupInviteFriendNative,
        _ToxGroupInviteFriendDart>('tox_group_invite_friend');
    _toxGroupInviteAccept = _lib.lookupFunction<_ToxGroupInviteAcceptNative,
        _ToxGroupInviteAcceptDart>('tox_group_invite_accept');
    _toxGroupLeave =
        _lib.lookupFunction<_ToxGroupLeaveNative, _ToxGroupLeaveDart>(
            'tox_group_leave');
    _toxGroupSelfGetRole = _lib.lookupFunction<_ToxGroupSelfGetRoleNative,
        _ToxGroupSelfGetRoleDart>('tox_group_self_get_role');
    _toxGroupGetNameSize = _lib.lookupFunction<_ToxGroupGetNameSizeNative,
        _ToxGroupGetNameSizeDart>('tox_group_get_name_size');
    _toxGroupGetName =
        _lib.lookupFunction<_ToxGroupGetNameNative, _ToxGroupGetNameDart>(
            'tox_group_get_name');
    _toxGroupGetChatId =
        _lib.lookupFunction<_ToxGroupGetChatIdNative, _ToxGroupGetChatIdDart>(
      'tox_group_get_chat_id',
    );
    _toxGroupPeerGetNameSize = _lib.lookupFunction<
        _ToxGroupPeerGetNameSizeNative,
        _ToxGroupPeerGetNameSizeDart>('tox_group_peer_get_name_size');
    _toxGroupPeerGetName = _lib.lookupFunction<_ToxGroupPeerGetNameNative,
        _ToxGroupPeerGetNameDart>('tox_group_peer_get_name');
    _toxGroupPeerGetPublicKey = _lib.lookupFunction<
        _ToxGroupPeerGetPublicKeyNative,
        _ToxGroupPeerGetPublicKeyDart>('tox_group_peer_get_public_key');
    _toxGroupPeerGetConnectionStatus = _lib.lookupFunction<
            _ToxGroupPeerGetConnectionStatusNative,
            _ToxGroupPeerGetConnectionStatusDart>(
        'tox_group_peer_get_connection_status');
    _toxGroupGetGroupListSize = _lib.lookupFunction<
        _ToxGroupGetGroupListSizeNative,
        _ToxGroupGetGroupListSizeDart>('tox_group_get_group_list_size');
    _toxGroupGetGroupList = _lib.lookupFunction<_ToxGroupGetGroupListNative,
        _ToxGroupGetGroupListDart>('tox_group_get_group_list');
    _toxCallbackGroupInvite = _lib.lookupFunction<_ToxCallbackGroupInviteNative,
        _ToxCallbackGroupInviteDart>('tox_callback_group_invite');
    _toxCallbackGroupMessage = _lib.lookupFunction<
        _ToxCallbackGroupMessageNative,
        _ToxCallbackGroupMessageDart>('tox_callback_group_message');
    _toxCallbackGroupPeerJoin = _lib.lookupFunction<
        _ToxCallbackGroupPeerJoinNative,
        _ToxCallbackGroupPeerJoinDart>('tox_callback_group_peer_join');
    _toxCallbackGroupPeerExit = _lib.lookupFunction<
        _ToxCallbackGroupPeerExitNative,
        _ToxCallbackGroupPeerExitDart>('tox_callback_group_peer_exit');
    _toxCallbackGroupSelfJoin = _lib.lookupFunction<
        _ToxCallbackGroupSelfJoinNative,
        _ToxCallbackGroupSelfJoinDart>('tox_callback_group_self_join');
    _toxCallbackGroupJoinFail = _lib.lookupFunction<
        _ToxCallbackGroupJoinFailNative,
        _ToxCallbackGroupJoinFailDart>('tox_callback_group_join_fail');
    _toxCallbackGroupPeerName = _lib.lookupFunction<
        _ToxCallbackGroupPeerNameNative,
        _ToxCallbackGroupPeerNameDart>('tox_callback_group_peer_name');
  }

  /// Cria uma nova instância `Tox*`. Se [savedata] for fornecido (bytes lidos
  /// de um arquivo persistido anteriormente via [getSavedata]), a identidade
  /// (chaves, lista de amigos etc.) é restaurada; caso contrário, o toxcore
  /// gera uma identidade nova.
  /// Lança [StateError] caso o toxcore reporte erro em `TOX_ERR_OPTIONS_NEW`
  /// ou `TOX_ERR_NEW`.
  ffi.Pointer<ffi.Void> createToxInstance({Uint8List? savedata}) {
    final optionsErrorPtr = pkg_ffi.calloc<ffi.Int32>();
    final newErrorPtr = pkg_ffi.calloc<ffi.Int32>();
    var options = ffi.nullptr.cast<ffi.Void>();
    var savedataPtr = ffi.nullptr.cast<ffi.Uint8>();
    try {
      options = _toxOptionsNew(optionsErrorPtr);
      if (options.address == 0 || optionsErrorPtr.value != 0) {
        throw StateError(
          'tox_options_new falhou com TOX_ERR_OPTIONS_NEW = ${optionsErrorPtr.value}',
        );
      }

      if (savedata != null && savedata.isNotEmpty) {
        savedataPtr = pkg_ffi.calloc<ffi.Uint8>(savedata.length);
        savedataPtr.asTypedList(savedata.length).setAll(0, savedata);
        _toxOptionsSetSavedataType(options, kToxSavedataTypeToxSave);
        _toxOptionsSetSavedataData(options, savedataPtr, savedata.length);
      }

      final tox = toxNew(options, newErrorPtr);
      final errorCode = newErrorPtr.value;
      if (tox.address == 0 || errorCode != 0) {
        throw StateError('tox_new falhou com TOX_ERR_NEW = $errorCode');
      }
      return tox;
    } finally {
      if (options.address != 0) _toxOptionsFree(options);
      if (savedataPtr.address != 0) pkg_ffi.calloc.free(savedataPtr);
      pkg_ffi.calloc.free(optionsErrorPtr);
      pkg_ffi.calloc.free(newErrorPtr);
    }
  }

  /// Extrai o blob binário opaco de identidade (chaves, amigos, etc.) para
  /// ser persistido em disco e recarregado depois via [createToxInstance].
  Uint8List getSavedata(ffi.Pointer<ffi.Void> tox) {
    final size = _toxGetSavedataSize(tox);
    final buffer = pkg_ffi.calloc<ffi.Uint8>(size);
    try {
      _toxGetSavedata(tox, buffer);
      return Uint8List.fromList(buffer.asTypedList(size));
    } finally {
      pkg_ffi.calloc.free(buffer);
    }
  }

  /// Conecta a instância a alguns nós públicos conhecidos da rede Tox.
  /// Sem isso, `tox_self_get_connection_status` nunca sai de `none`: a
  /// instância existe, mas está isolada da DHT.
  void bootstrapNetwork(ffi.Pointer<ffi.Void> tox) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      for (final node in _kBootstrapNodes) {
        final hostPtr = node.host.toNativeUtf8();
        final keyBytes = node.publicKeyBytes;
        final keyPtr = pkg_ffi.calloc<ffi.Uint8>(keyBytes.length);
        keyPtr.asTypedList(keyBytes.length).setAll(0, keyBytes);
        try {
          _toxBootstrap(tox, hostPtr, node.port, keyPtr, errorPtr);
          // Falha em um nó isolado não é fatal — basta um responder.
        } finally {
          pkg_ffi.calloc.free(hostPtr);
          pkg_ffi.calloc.free(keyPtr);
        }
      }
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Lê o Talksnap ID (Tox ID) da instância e devolve como string hexadecimal
  /// (formato padrão de 76 caracteres usado para adicionar contatos).
  String readSelfAddress(ffi.Pointer<ffi.Void> tox) {
    final addressPtr = pkg_ffi.calloc<ffi.Uint8>(kToxAddressSize);
    try {
      toxSelfGetAddress(tox, addressPtr);
      return bytesToHex(
          Uint8List.fromList(addressPtr.asTypedList(kToxAddressSize)));
    } finally {
      pkg_ffi.calloc.free(addressPtr);
    }
  }

  /// Envia um pedido de amizade para o Talksnap ID (76 caracteres hex)
  /// informado. Retorna o `friend_number` atribuído em caso de sucesso.
  /// Lança [ArgumentError]/[StateError] em caso de ID inválido ou erro do
  /// toxcore (`TOX_ERR_FRIEND_ADD`).
  int friendAdd(ffi.Pointer<ffi.Void> tox, String talksnapId, String message) {
    final addressBytes = hexToBytes(talksnapId);
    if (addressBytes.length != kToxAddressSize) {
      throw ArgumentError(
        'Talksnap ID inválido: esperado $kToxAddressSize bytes, recebeu ${addressBytes.length}.',
      );
    }
    final messageBytes = utf8.encode(message);
    final addressPtr = pkg_ffi.calloc<ffi.Uint8>(kToxAddressSize);
    final messagePtr = pkg_ffi.calloc<ffi.Uint8>(
      messageBytes.isEmpty ? 1 : messageBytes.length,
    );
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      addressPtr.asTypedList(kToxAddressSize).setAll(0, addressBytes);
      if (messageBytes.isNotEmpty) {
        messagePtr.asTypedList(messageBytes.length).setAll(0, messageBytes);
      }
      final friendNumber = _toxFriendAdd(
          tox, addressPtr, messagePtr, messageBytes.length, errorPtr);
      final errorCode = errorPtr.value;
      if (errorCode != 0) {
        throw StateError(
            'tox_friend_add falhou com TOX_ERR_FRIEND_ADD = $errorCode');
      }
      return friendNumber;
    } finally {
      pkg_ffi.calloc.free(addressPtr);
      pkg_ffi.calloc.free(messagePtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Aceita um pedido de amizade recebido, adicionando de volta pela chave
  /// pública (32 bytes hex) de quem pediu — sem exigir novo convite/mensagem.
  int friendAddNorequest(ffi.Pointer<ffi.Void> tox, String publicKeyHex) {
    final keyBytes = hexToBytes(publicKeyHex);
    if (keyBytes.length != kToxPublicKeySize) {
      throw ArgumentError(
        'Chave pública inválida: esperado $kToxPublicKeySize bytes, recebeu ${keyBytes.length}.',
      );
    }
    final keyPtr = pkg_ffi.calloc<ffi.Uint8>(kToxPublicKeySize);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      keyPtr.asTypedList(kToxPublicKeySize).setAll(0, keyBytes);
      final friendNumber = _toxFriendAddNorequest(tox, keyPtr, errorPtr);
      final errorCode = errorPtr.value;
      if (errorCode != 0) {
        throw StateError(
          'tox_friend_add_norequest falhou com TOX_ERR_FRIEND_ADD = $errorCode',
        );
      }
      return friendNumber;
    } finally {
      pkg_ffi.calloc.free(keyPtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Remove um amigo existente. Retorna `false` se o `friendNumber` não
  /// corresponder a nenhum amigo atual.
  bool friendDelete(ffi.Pointer<ffi.Void> tox, int friendNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final ok = _toxFriendDelete(tox, friendNumber, errorPtr);
      return ok != 0 && errorPtr.value == 0;
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Lê a chave pública (hex) de um amigo pelo seu `friend_number`, ou
  /// `null` se esse `friend_number` não existir.
  String? friendGetPublicKey(ffi.Pointer<ffi.Void> tox, int friendNumber) {
    final keyPtr = pkg_ffi.calloc<ffi.Uint8>(kToxPublicKeySize);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final ok = _toxFriendGetPublicKey(tox, friendNumber, keyPtr, errorPtr);
      if (ok == 0 || errorPtr.value != 0) return null;
      return bytesToHex(
          Uint8List.fromList(keyPtr.asTypedList(kToxPublicKeySize)));
    } finally {
      pkg_ffi.calloc.free(keyPtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Status de conexão de um amigo especifico (diferente do status global
  /// da própria instância, exposto por [toxSelfGetConnectionStatus]).
  ToxConnection friendGetConnectionStatus(
      ffi.Pointer<ffi.Void> tox, int friendNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final status = _toxFriendGetConnectionStatus(tox, friendNumber, errorPtr);
      return ToxConnection.fromNative(status);
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Lista os `friend_number`s de todos os amigos salvos na identidade atual
  /// (restaurados automaticamente do savedata ao chamar [createToxInstance]).
  List<int> getFriendList(ffi.Pointer<ffi.Void> tox) {
    final size = _toxSelfGetFriendListSize(tox);
    if (size == 0) return const [];
    final listPtr = pkg_ffi.calloc<ffi.Uint32>(size);
    try {
      _toxSelfGetFriendList(tox, listPtr);
      return List<int>.generate(size, (i) => listPtr[i]);
    } finally {
      pkg_ffi.calloc.free(listPtr);
    }
  }

  /// Registra o callback nativo chamado quando alguém envia um pedido de
  /// amizade para o nosso Talksnap ID. Disparado de dentro de [toxIterate].
  void setFriendRequestCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFriendRequestCallbackNative>> callback,
  ) {
    _toxCallbackFriendRequest(tox, callback);
  }

  /// Registra o callback nativo chamado quando o status de conexão de um
  /// amigo muda. Disparado de dentro de [toxIterate].
  void setFriendConnectionStatusCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFriendConnectionStatusCallbackNative>>
        callback,
  ) {
    _toxCallbackFriendConnectionStatus(tox, callback);
  }

  /// Registra o callback nativo chamado quando um amigo começa ou para de
  /// digitar. Disparado de dentro de [toxIterate].
  void setFriendTypingCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFriendTypingCallbackNative>> callback,
  ) {
    _toxCallbackFriendTyping(tox, callback);
  }

  /// Avisa um amigo que estamos (ou paramos de) digitar uma mensagem pra
  /// ele. Erro silencioso (amigo não encontrado) não é crítico o bastante
  /// pra lançar exceção — só ignora.
  void setSelfTyping(ffi.Pointer<ffi.Void> tox, int friendNumber, bool typing) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      _toxSelfSetTyping(tox, friendNumber, typing ? 1 : 0, errorPtr);
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Decodifica `length` bytes UTF-8 a partir de um ponteiro nativo (usado
  /// para ler a mensagem de um pedido de amizade recebido via callback).
  String readUtf8(ffi.Pointer<ffi.Uint8> ptr, int length) {
    return utf8.decode(ptr.asTypedList(length));
  }

  /// Lê uma chave pública (32 bytes) a partir de um ponteiro nativo (usado
  /// dentro dos callbacks de amizade) e devolve como hex.
  String readPublicKeyHex(ffi.Pointer<ffi.Uint8> ptr) {
    return bytesToHex(Uint8List.fromList(ptr.asTypedList(kToxPublicKeySize)));
  }

  /// Envia uma mensagem de texto normal para um amigo já conectado.
  /// Retorna o `message_id` (local, usado para casar com o read receipt).
  /// Lança [ToxFriendNotConnectedException] se o amigo não estiver online
  /// no momento (`TOX_ERR_FRIEND_SEND_MESSAGE_FRIEND_NOT_CONNECTED`), ou
  /// [StateError] para qualquer outro erro (`TOX_ERR_FRIEND_SEND_MESSAGE`).
  int friendSendMessage(
      ffi.Pointer<ffi.Void> tox, int friendNumber, String message) {
    final messageBytes = utf8.encode(message);
    final messagePtr = pkg_ffi
        .calloc<ffi.Uint8>(messageBytes.isEmpty ? 1 : messageBytes.length);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      if (messageBytes.isNotEmpty) {
        messagePtr.asTypedList(messageBytes.length).setAll(0, messageBytes);
      }
      final messageId = _toxFriendSendMessage(
        tox,
        friendNumber,
        kToxMessageTypeNormal,
        messagePtr,
        messageBytes.length,
        errorPtr,
      );
      final errorCode = errorPtr.value;
      if (errorCode == kToxErrFriendSendMessageFriendNotConnected) {
        throw const ToxFriendNotConnectedException();
      }
      if (errorCode != 0) {
        throw StateError(
          'tox_friend_send_message falhou com TOX_ERR_FRIEND_SEND_MESSAGE = $errorCode',
        );
      }
      return messageId;
    } finally {
      pkg_ffi.calloc.free(messagePtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Registra o callback nativo chamado ao receber uma mensagem de um
  /// amigo. Disparado de dentro de [toxIterate].
  void setFriendMessageCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFriendMessageCallbackNative>> callback,
  ) {
    _toxCallbackFriendMessage(tox, callback);
  }

  /// Registra o callback nativo chamado quando uma mensagem enviada por nós
  /// é confirmada como entregue. Disparado de dentro de [toxIterate].
  void setFriendReadReceiptCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFriendReadReceiptCallbackNative>>
        callback,
  ) {
    _toxCallbackFriendReadReceipt(tox, callback);
  }

  /// Oferece um arquivo a um amigo. Retorna o `file_number` (efêmero,
  /// escopado por amigo+sessão) usado nas chamadas seguintes
  /// (`fileSendChunk`, `fileControl`) e nos callbacks. Lança [StateError]
  /// em caso de erro (`TOX_ERR_FILE_SEND`) — ex: amigo offline.
  int fileSend(ffi.Pointer<ffi.Void> tox, int friendNumber, int fileSize,
      String fileName) {
    final nameBytes = utf8.encode(fileName);
    final namePtr =
        pkg_ffi.calloc<ffi.Uint8>(nameBytes.isEmpty ? 1 : nameBytes.length);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      if (nameBytes.isNotEmpty) {
        namePtr.asTypedList(nameBytes.length).setAll(0, nameBytes);
      }
      // file_id = nullptr: o toxcore gera um identificador aleatório.
      final fileNumber = _toxFileSend(
        tox,
        friendNumber,
        kToxFileKindData,
        fileSize,
        ffi.nullptr,
        namePtr,
        nameBytes.length,
        errorPtr,
      );
      final errorCode = errorPtr.value;
      if (errorCode != 0) {
        throw StateError(
            'tox_file_send falhou com TOX_ERR_FILE_SEND = $errorCode');
      }
      return fileNumber;
    } finally {
      pkg_ffi.calloc.free(namePtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Envia um pedaço de um arquivo sendo transmitido, em resposta a um
  /// `tox_file_chunk_request_cb`. `data` deve ter exatamente o tamanho
  /// pedido pelo callback (ou vazio, para sinalizar fim de arquivo).
  void fileSendChunk(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int fileNumber,
    int position,
    Uint8List data,
  ) {
    final dataPtr = pkg_ffi.calloc<ffi.Uint8>(data.isEmpty ? 1 : data.length);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      if (data.isNotEmpty) {
        dataPtr.asTypedList(data.length).setAll(0, data);
      }
      _toxFileSendChunk(tox, friendNumber, fileNumber, position, dataPtr,
          data.length, errorPtr);
      // Erros aqui (ex: posição incorreta) não são fatais para o Talksnap
      // por ora — o pior caso é a transferência travar, sem derrubar o app.
    } finally {
      pkg_ffi.calloc.free(dataPtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Envia um controle (resume/pause/cancel) para uma transferência de
  /// arquivo — usado tanto para aceitar/rejeitar uma oferta recebida quanto
  /// para cancelar uma transferência em andamento (em qualquer direção).
  void fileControl(ffi.Pointer<ffi.Void> tox, int friendNumber, int fileNumber,
      int control) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      _toxFileControl(tox, friendNumber, fileNumber, control, errorPtr);
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  void setFileRecvCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFileRecvCallbackNative>> callback,
  ) {
    _toxCallbackFileRecv(tox, callback);
  }

  void setFileRecvChunkCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFileRecvChunkCallbackNative>> callback,
  ) {
    _toxCallbackFileRecvChunk(tox, callback);
  }

  void setFileChunkRequestCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFileChunkRequestCallbackNative>> callback,
  ) {
    _toxCallbackFileChunkRequest(tox, callback);
  }

  void setFileRecvControlCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFileRecvControlCallbackNative>> callback,
  ) {
    _toxCallbackFileRecvControl(tox, callback);
  }

  /// Define o status de presença escolhido manualmente pelo usuário
  /// (Online/Ausente/Ocupado — ver kToxUserStatus*) — diferente da
  /// conectividade de rede ([ToxConnection]). Propagado automaticamente
  /// pelo toxcore aos contatos, e persistido no savedata.
  void setSelfUserStatus(ffi.Pointer<ffi.Void> tox, int status) {
    _toxSelfSetStatus(tox, status);
  }

  int getSelfUserStatus(ffi.Pointer<ffi.Void> tox) {
    return _toxSelfGetStatus(tox);
  }

  /// Define o nome exibido para os contatos (propagado automaticamente
  /// pelo toxcore a cada amigo conectado).
  void setSelfName(ffi.Pointer<ffi.Void> tox, String name) {
    final bytes = utf8.encode(name);
    final ptr = pkg_ffi.calloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      if (bytes.isNotEmpty) ptr.asTypedList(bytes.length).setAll(0, bytes);
      _toxSelfSetName(tox, ptr, bytes.length, errorPtr);
    } finally {
      pkg_ffi.calloc.free(ptr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  String getSelfName(ffi.Pointer<ffi.Void> tox) {
    final size = _toxSelfGetNameSize(tox);
    if (size == 0) return '';
    final ptr = pkg_ffi.calloc<ffi.Uint8>(size);
    try {
      _toxSelfGetName(tox, ptr);
      return utf8.decode(ptr.asTypedList(size));
    } finally {
      pkg_ffi.calloc.free(ptr);
    }
  }

  /// Define a mensagem de status ("descrição" curta) exibida para os
  /// contatos.
  void setSelfStatusMessage(ffi.Pointer<ffi.Void> tox, String statusMessage) {
    final bytes = utf8.encode(statusMessage);
    final ptr = pkg_ffi.calloc<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      if (bytes.isNotEmpty) ptr.asTypedList(bytes.length).setAll(0, bytes);
      _toxSelfSetStatusMessage(tox, ptr, bytes.length, errorPtr);
    } finally {
      pkg_ffi.calloc.free(ptr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  String getSelfStatusMessage(ffi.Pointer<ffi.Void> tox) {
    final size = _toxSelfGetStatusMessageSize(tox);
    if (size == 0) return '';
    final ptr = pkg_ffi.calloc<ffi.Uint8>(size);
    try {
      _toxSelfGetStatusMessage(tox, ptr);
      return utf8.decode(ptr.asTypedList(size));
    } finally {
      pkg_ffi.calloc.free(ptr);
    }
  }

  /// Nome atual de um amigo (o que ele mesmo definiu no perfil dele), ou
  /// string vazia se ainda não recebemos essa informação.
  String friendGetName(ffi.Pointer<ffi.Void> tox, int friendNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final size = _toxFriendGetNameSize(tox, friendNumber, errorPtr);
      if (errorPtr.value != 0 || size == 0) return '';
      final ptr = pkg_ffi.calloc<ffi.Uint8>(size);
      try {
        _toxFriendGetName(tox, friendNumber, ptr, errorPtr);
        return utf8.decode(ptr.asTypedList(size));
      } finally {
        pkg_ffi.calloc.free(ptr);
      }
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  String friendGetStatusMessage(ffi.Pointer<ffi.Void> tox, int friendNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final size = _toxFriendGetStatusMessageSize(tox, friendNumber, errorPtr);
      if (errorPtr.value != 0 || size == 0) return '';
      final ptr = pkg_ffi.calloc<ffi.Uint8>(size);
      try {
        _toxFriendGetStatusMessage(tox, friendNumber, ptr, errorPtr);
        return utf8.decode(ptr.asTypedList(size));
      } finally {
        pkg_ffi.calloc.free(ptr);
      }
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Status de presença atual de um amigo (Online/Ausente/Ocupado — ver
  /// kToxUserStatus* — diferente da conectividade de rede).
  int friendGetUserStatus(ffi.Pointer<ffi.Void> tox, int friendNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      return _toxFriendGetUserStatus(tox, friendNumber, errorPtr);
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  void setFriendUserStatusCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFriendUserStatusCallbackNative>> callback,
  ) {
    _toxCallbackFriendUserStatus(tox, callback);
  }

  void setFriendNameCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFriendNameCallbackNative>> callback,
  ) {
    _toxCallbackFriendName(tox, callback);
  }

  void setFriendStatusMessageCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxFriendStatusMessageCallbackNative>>
        callback,
  ) {
    _toxCallbackFriendStatusMessage(tox, callback);
  }

  /// Se a instância está conectada (ou tentando se conectar) a outros
  /// peers do grupo — útil para depurar sincronização lenta após entrar.
  bool groupIsConnected(ffi.Pointer<ffi.Void> tox, int groupNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      return _toxGroupIsConnected(tox, groupNumber, errorPtr) != 0;
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Cria um novo grupo privado (só entra quem for convidado por um amigo).
  /// Retorna o `group_number` (efêmero por sessão) atribuído. Lança
  /// [StateError] em caso de erro (`TOX_ERR_GROUP_NEW`).
  int groupNew(ffi.Pointer<ffi.Void> tox, String groupName, String selfName) {
    final groupNameBytes = utf8.encode(groupName);
    final selfNameBytes = utf8.encode(selfName);
    final groupNamePtr = pkg_ffi.calloc<ffi.Uint8>(groupNameBytes.length);
    final selfNamePtr = pkg_ffi.calloc<ffi.Uint8>(selfNameBytes.length);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      groupNamePtr.asTypedList(groupNameBytes.length).setAll(0, groupNameBytes);
      selfNamePtr.asTypedList(selfNameBytes.length).setAll(0, selfNameBytes);
      final groupNumber = _toxGroupNew(
        tox,
        kToxGroupPrivacyStatePrivate,
        groupNamePtr,
        groupNameBytes.length,
        selfNamePtr,
        selfNameBytes.length,
        errorPtr,
      );
      final errorCode = errorPtr.value;
      if (errorCode != 0) {
        throw StateError(
            'tox_group_new falhou com TOX_ERR_GROUP_NEW = $errorCode');
      }
      return groupNumber;
    } finally {
      pkg_ffi.calloc.free(groupNamePtr);
      pkg_ffi.calloc.free(selfNamePtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Envia uma mensagem de texto normal para o grupo. Retorna o
  /// `message_id` local. Lança [StateError] em caso de erro
  /// (`TOX_ERR_GROUP_SEND_MESSAGE`) — ex: grupo desconectado.
  int groupSendMessage(
      ffi.Pointer<ffi.Void> tox, int groupNumber, String message) {
    final messageBytes = utf8.encode(message);
    final messagePtr = pkg_ffi
        .calloc<ffi.Uint8>(messageBytes.isEmpty ? 1 : messageBytes.length);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      if (messageBytes.isNotEmpty) {
        messagePtr.asTypedList(messageBytes.length).setAll(0, messageBytes);
      }
      final messageId = _toxGroupSendMessage(
        tox,
        groupNumber,
        kToxMessageTypeNormal,
        messagePtr,
        messageBytes.length,
        errorPtr,
      );
      final errorCode = errorPtr.value;
      if (errorCode != 0) {
        throw StateError(
          'tox_group_send_message falhou com TOX_ERR_GROUP_SEND_MESSAGE = $errorCode',
        );
      }
      return messageId;
    } finally {
      pkg_ffi.calloc.free(messagePtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Convida um amigo (já conectado) para um grupo. Lança [StateError] em
  /// caso de erro (`TOX_ERR_GROUP_INVITE_FRIEND`).
  void groupInviteFriend(
      ffi.Pointer<ffi.Void> tox, int groupNumber, int friendNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      _toxGroupInviteFriend(tox, groupNumber, friendNumber, errorPtr);
      final errorCode = errorPtr.value;
      if (errorCode != 0) {
        throw StateError(
          'tox_group_invite_friend falhou com TOX_ERR_GROUP_INVITE_FRIEND = $errorCode',
        );
      }
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Aceita um convite de grupo recebido de um amigo (ver
  /// [ToxGroupInviteCallbackNative]) — `inviteData` deve ser exatamente o
  /// que veio no callback. Retorna o `group_number` atribuído. Lança
  /// [StateError] em caso de erro (`TOX_ERR_GROUP_INVITE_ACCEPT`).
  int groupInviteAccept(ffi.Pointer<ffi.Void> tox, int friendNumber,
      Uint8List inviteData, String selfName) {
    final selfNameBytes = utf8.encode(selfName);
    final inviteDataPtr = pkg_ffi.calloc<ffi.Uint8>(inviteData.length);
    final selfNamePtr = pkg_ffi.calloc<ffi.Uint8>(selfNameBytes.length);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      inviteDataPtr.asTypedList(inviteData.length).setAll(0, inviteData);
      selfNamePtr.asTypedList(selfNameBytes.length).setAll(0, selfNameBytes);
      final groupNumber = _toxGroupInviteAccept(
        tox,
        friendNumber,
        inviteDataPtr,
        inviteData.length,
        selfNamePtr,
        selfNameBytes.length,
        ffi.nullptr,
        0,
        errorPtr,
      );
      final errorCode = errorPtr.value;
      if (errorCode != 0) {
        throw StateError(
          'tox_group_invite_accept falhou com TOX_ERR_GROUP_INVITE_ACCEPT = $errorCode',
        );
      }
      return groupNumber;
    } finally {
      pkg_ffi.calloc.free(inviteDataPtr);
      pkg_ffi.calloc.free(selfNamePtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Sai de um grupo, sem enviar mensagem de despedida.
  bool groupLeave(ffi.Pointer<ffi.Void> tox, int groupNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final ok = _toxGroupLeave(tox, groupNumber, ffi.nullptr, 0, errorPtr);
      return ok != 0 && errorPtr.value == 0;
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Nosso próprio papel no grupo (`TOX_GROUP_ROLE`) — usado para saber se
  /// somos o fundador (ver [kToxGroupRoleFounder]).
  int groupSelfGetRole(ffi.Pointer<ffi.Void> tox, int groupNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      return _toxGroupSelfGetRole(tox, groupNumber, errorPtr);
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Nome do grupo (definido na criação), ou string vazia se o
  /// `group_number` não existir.
  String groupGetName(ffi.Pointer<ffi.Void> tox, int groupNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final size = _toxGroupGetNameSize(tox, groupNumber, errorPtr);
      if (errorPtr.value != 0 || size == 0) return '';
      final ptr = pkg_ffi.calloc<ffi.Uint8>(size);
      try {
        _toxGroupGetName(tox, groupNumber, ptr, errorPtr);
        return utf8.decode(ptr.asTypedList(size));
      } finally {
        pkg_ffi.calloc.free(ptr);
      }
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Chat ID (hex, 32 bytes) do grupo — chave estável entre execuções,
  /// equivalente à chave pública de um amigo. `null` se o `group_number`
  /// não existir.
  String? groupGetChatIdHex(ffi.Pointer<ffi.Void> tox, int groupNumber) {
    final chatIdPtr = pkg_ffi.calloc<ffi.Uint8>(kToxGroupChatIdSize);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final ok = _toxGroupGetChatId(tox, groupNumber, chatIdPtr, errorPtr);
      if (ok == 0 || errorPtr.value != 0) return null;
      return bytesToHex(
          Uint8List.fromList(chatIdPtr.asTypedList(kToxGroupChatIdSize)));
    } finally {
      pkg_ffi.calloc.free(chatIdPtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Nome atual de um peer do grupo, ou string vazia se não disponível.
  String groupPeerGetName(
      ffi.Pointer<ffi.Void> tox, int groupNumber, int peerId) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final size = _toxGroupPeerGetNameSize(tox, groupNumber, peerId, errorPtr);
      if (errorPtr.value != 0 || size == 0) return '';
      final ptr = pkg_ffi.calloc<ffi.Uint8>(size);
      try {
        _toxGroupPeerGetName(tox, groupNumber, peerId, ptr, errorPtr);
        return utf8.decode(ptr.asTypedList(size));
      } finally {
        pkg_ffi.calloc.free(ptr);
      }
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Chave pública (hex) de um peer do grupo — permanece a mesma enquanto
  /// esse peer não sair explicitamente do grupo, mesmo entre reconexões,
  /// então serve para saber se um contato já é membro (ex: filtrar a lista
  /// de "convidar contato"). `null` se não disponível.
  String? groupPeerGetPublicKey(
      ffi.Pointer<ffi.Void> tox, int groupNumber, int peerId) {
    final keyPtr = pkg_ffi.calloc<ffi.Uint8>(kToxPublicKeySize);
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final ok =
          _toxGroupPeerGetPublicKey(tox, groupNumber, peerId, keyPtr, errorPtr);
      if (ok == 0 || errorPtr.value != 0) return null;
      return bytesToHex(
          Uint8List.fromList(keyPtr.asTypedList(kToxPublicKeySize)));
    } finally {
      pkg_ffi.calloc.free(keyPtr);
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Status de conexão de um peer específico do grupo.
  ToxConnection groupPeerGetConnectionStatus(
      ffi.Pointer<ffi.Void> tox, int groupNumber, int peerId) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final status =
          _toxGroupPeerGetConnectionStatus(tox, groupNumber, peerId, errorPtr);
      return ToxConnection.fromNative(status);
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Lista os `group_number`s de todos os grupos salvos na identidade atual
  /// (restaurados automaticamente do savedata ao chamar [createToxInstance]).
  List<int> getGroupList(ffi.Pointer<ffi.Void> tox) {
    final size = _toxGroupGetGroupListSize(tox);
    if (size == 0) return const [];
    final listPtr = pkg_ffi.calloc<ffi.Uint32>(size);
    try {
      _toxGroupGetGroupList(tox, listPtr);
      return List<int>.generate(size, (i) => listPtr[i]);
    } finally {
      pkg_ffi.calloc.free(listPtr);
    }
  }

  void setGroupInviteCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxGroupInviteCallbackNative>> callback,
  ) {
    _toxCallbackGroupInvite(tox, callback);
  }

  void setGroupMessageCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxGroupMessageCallbackNative>> callback,
  ) {
    _toxCallbackGroupMessage(tox, callback);
  }

  void setGroupPeerJoinCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxGroupPeerJoinCallbackNative>> callback,
  ) {
    _toxCallbackGroupPeerJoin(tox, callback);
  }

  void setGroupPeerExitCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxGroupPeerExitCallbackNative>> callback,
  ) {
    _toxCallbackGroupPeerExit(tox, callback);
  }

  void setGroupSelfJoinCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxGroupSelfJoinCallbackNative>> callback,
  ) {
    _toxCallbackGroupSelfJoin(tox, callback);
  }

  void setGroupJoinFailCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxGroupJoinFailCallbackNative>> callback,
  ) {
    _toxCallbackGroupJoinFail(tox, callback);
  }

  void setGroupPeerNameCallback(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.NativeFunction<ToxGroupPeerNameCallbackNative>> callback,
  ) {
    _toxCallbackGroupPeerName(tox, callback);
  }
}
