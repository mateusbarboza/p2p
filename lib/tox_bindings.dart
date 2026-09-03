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
  late final _ToxCallbackFriendMessageDart _toxCallbackFriendMessage;
  late final _ToxCallbackFriendReadReceiptDart _toxCallbackFriendReadReceipt;
  late final _ToxFileSendDart _toxFileSend;
  late final _ToxFileSendChunkDart _toxFileSendChunk;
  late final _ToxFileControlDart _toxFileControl;
  late final _ToxCallbackFileRecvDart _toxCallbackFileRecv;
  late final _ToxCallbackFileRecvChunkDart _toxCallbackFileRecvChunk;
  late final _ToxCallbackFileChunkRequestDart _toxCallbackFileChunkRequest;
  late final _ToxCallbackFileRecvControlDart _toxCallbackFileRecvControl;
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
  late final _ToxCallbackFriendNameDart _toxCallbackFriendName;
  late final _ToxCallbackFriendStatusMessageDart
      _toxCallbackFriendStatusMessage;

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
    _toxCallbackFriendName = _lib.lookupFunction<_ToxCallbackFriendNameNative,
        _ToxCallbackFriendNameDart>('tox_callback_friend_name');
    _toxCallbackFriendStatusMessage = _lib.lookupFunction<
            _ToxCallbackFriendStatusMessageNative,
            _ToxCallbackFriendStatusMessageDart>(
        'tox_callback_friend_status_message');
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
  /// Lança [StateError] em caso de erro (`TOX_ERR_FRIEND_SEND_MESSAGE`),
  /// por exemplo se o amigo não estiver online no momento.
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
}
