// tox_isolate_manager.dart
//
// Ponte entre o mundo nativo (toxcore, via tox_bindings.dart) e a UI do
// Flutter, passando por um Isolate dedicado.
//
// Por que um Isolate? `tox_iterate()` precisa ser chamado continuamente
// (a cada `tox_iteration_interval()` milissegundos) para a rede P2P
// funcionar. Se isso rodasse na thread principal (a mesma que desenha a
// UI), qualquer variação na rede travaria animações e a interface inteira.
// Isolando essa lógica, o Isolate de rede vive numa thread separada com
// sua própria memória, e troca dados com a UI apenas através de
// mensagens (SendPort / ReceivePort) — nunca por memória compartilhada.
//
// Fase 1 (conectividade real + identidade persistente): o isolate lê/escreve
// o "savedata" do toxcore num arquivo local, e chama tox_bootstrap para
// conectar de verdade à rede P2P.
//
// Fase 2 (gestão de amigos): a UI agora pode pedir para adicionar um
// contato pelo Talksnap ID, aceitar pedidos recebidos e remover amigos.
// O vocabulário de mensagens virou uma hierarquia `sealed class`
// (ToxNetworkEvent/ToxNetworkCommand, em tox_events.dart) em vez de um
// único objeto "status" genérico — cada fase futura (mensagens, arquivos,
// chamadas) só precisa acrescentar novos casos, sem inflar um objeto só.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'identity_backup.dart' show resolveSavedataFile;
import 'tox_bindings.dart';
import 'tox_events.dart';

/// Estado de uma transferência de arquivo ativa (em andamento no isolate).
/// Vive só em memória — nada aqui é persistido diretamente; o isolate
/// apenas emite [ToxFileTransferEvent] e é a camada de estado (Riverpod)
/// quem decide gravar no banco (mesma divisão de responsabilidade usada
/// para contatos e mensagens).
class _ActiveFileTransfer {
  _ActiveFileTransfer({
    required this.publicKeyHex,
    required this.fileNumber,
    required this.fileName,
    required this.totalBytes,
    required this.outgoing,
  });

  final String publicKeyHex;
  final int fileNumber;
  final String fileName;
  final int totalBytes;
  final bool outgoing;

  /// Handle de leitura (envio) ou escrita (recebimento) — só existe depois
  /// que a transferência é efetivamente aceita (ver RespondFileControlCommand).
  RandomAccessFile? file;
  String? savedPath;
  int transferredBytes = 0;
}

/// A cada quantas iterações do loop de rede o savedata é persistido de novo
/// (além de sempre salvar no primeiro boot, após mudanças na lista de
/// amigos, e ao encerrar).
const int _kSaveEveryNIterations = 200;

/// Intervalo mínimo entre novas tentativas de bootstrap enquanto a
/// instância ainda não conseguiu entrar na rede (ver Fase 6 — redes reais
/// com NAT restritivo podem precisar de mais de uma tentativa).
const Duration _kBootstrapRetryInterval = Duration(seconds: 15);

/// Payload enviado pelo isolate de rede para o isolate principal assim que
/// ele nasce, contendo o SendPort que a UI deve usar para mandar comandos.
class _IsolateHandshake {
  const _IsolateHandshake(this.commandPort);
  final SendPort commandPort;
}

/// Argumentos passados na criação do isolate de rede. Precisa levar o
/// [RootIsolateToken] porque o isolate usa um plugin (`path_provider`) que
/// fala com o lado nativo via platform channel — algo que só funciona num
/// isolate em background se ele for inicializado com esse token (ver
/// `BackgroundIsolateBinaryMessenger.ensureInitialized`).
class _IsolateBootstrapArgs {
  const _IsolateBootstrapArgs({
    required this.mainSendPort,
    required this.rootIsolateToken,
  });

  final SendPort mainSendPort;
  final RootIsolateToken rootIsolateToken;
}

/// Gerencia o ciclo de vida completo do isolate de rede Tox: criação,
/// escuta de atualizações e encerramento limpo.
class ToxIsolateManager {
  final ReceivePort _mainReceivePort = ReceivePort();
  final StreamController<ToxNetworkEvent> _updatesController =
      StreamController<ToxNetworkEvent>.broadcast();

  Isolate? _isolate;
  SendPort? _commandPortToIsolate;
  StreamSubscription<dynamic>? _subscription;

  /// Stream que a UI escuta para reagir a eventos de rede em tempo real.
  Stream<ToxNetworkEvent> get updates => _updatesController.stream;

  /// Sobe o isolate de rede e conecta as portas de comunicação.
  ///
  /// Precisa ser chamado a partir do isolate principal do Flutter (ex: em
  /// `initState`), pois é de lá que se obtém o [RootIsolateToken].
  Future<void> start() async {
    _subscription = _mainReceivePort.listen(_handleMessageFromIsolate);

    final rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      throw StateError(
        'RootIsolateToken indisponível — ToxIsolateManager.start() precisa '
        'ser chamado a partir do isolate principal do Flutter.',
      );
    }

    _isolate = await Isolate.spawn<_IsolateBootstrapArgs>(
      _toxNetworkIsolateEntryPoint,
      _IsolateBootstrapArgs(
        mainSendPort: _mainReceivePort.sendPort,
        rootIsolateToken: rootIsolateToken,
      ),
      debugName: 'talksnap-tox-network',
    );
  }

  void _handleMessageFromIsolate(dynamic message) {
    if (message is _IsolateHandshake) {
      // Primeira mensagem: guardamos o SendPort para podermos falar de
      // volta com o isolate (ex: pedir para ele parar).
      _commandPortToIsolate = message.commandPort;
    } else if (message is ToxNetworkEvent) {
      _updatesController.add(message);
    }
  }

  void _sendCommand(ToxNetworkCommand command) {
    _commandPortToIsolate?.send(command);
  }

  /// Envia um pedido de amizade para o Talksnap ID informado (76 caracteres
  /// hex). O resultado chega de volta pela stream [updates] como um
  /// [ToxFriendAddResultEvent].
  void addFriend(String talksnapId,
      {String message = 'Vamos conversar no Talksnap!'}) {
    _sendCommand(AddFriendCommand(talksnapId: talksnapId, message: message));
  }

  /// Aceita um pedido de amizade recebido (ver [ToxFriendRequestEvent]),
  /// identificado pela chave pública de quem pediu.
  void acceptFriendRequest(String publicKeyHex) {
    _sendCommand(AcceptFriendRequestCommand(publicKeyHex: publicKeyHex));
  }

  /// Remove um amigo existente, identificado pela chave pública.
  void removeFriend(String publicKeyHex) {
    _sendCommand(RemoveFriendCommand(publicKeyHex: publicKeyHex));
  }

  /// Envia uma mensagem de texto para um contato. O resultado chega de
  /// volta pela stream [updates] como um [ToxMessageSentEvent].
  void sendMessage(String publicKeyHex, String message) {
    _sendCommand(
        SendMessageCommand(publicKeyHex: publicKeyHex, message: message));
  }

  /// Oferece um arquivo local a um contato. O progresso chega pela stream
  /// [updates] como uma série de [ToxFileTransferEvent].
  void sendFile(String publicKeyHex, String filePath) {
    _sendCommand(
        SendFileCommand(publicKeyHex: publicKeyHex, filePath: filePath));
  }

  /// Aceita, recusa ou cancela uma transferência de arquivo (em qualquer
  /// direção), identificada pelo `fileNumber` recebido num
  /// [ToxFileTransferEvent] anterior.
  void respondFileControl(
      String publicKeyHex, int fileNumber, ToxFileControlAction control) {
    _sendCommand(
      RespondFileControlCommand(
          publicKeyHex: publicKeyHex, fileNumber: fileNumber, control: control),
    );
  }

  /// Atualiza nome e mensagem de status do próprio perfil.
  void setProfile(String name, String statusMessage) {
    _sendCommand(SetProfileCommand(name: name, statusMessage: statusMessage));
  }

  /// Cria um novo grupo privado. O resultado chega como
  /// [ToxGroupCreatedEvent].
  void createGroup(String groupName) {
    _sendCommand(CreateGroupCommand(groupName: groupName));
  }

  /// Convida um contato (chave pública) para um grupo (Chat ID).
  void inviteToGroup(String chatIdHex, String contactPublicKeyHex) {
    _sendCommand(InviteToGroupCommand(
        chatIdHex: chatIdHex, contactPublicKeyHex: contactPublicKeyHex));
  }

  /// Aceita um convite de grupo recebido (ver [ToxGroupInviteEvent]).
  void acceptGroupInvite(String fromPublicKeyHex, Uint8List inviteData) {
    _sendCommand(AcceptGroupInviteCommand(
        fromPublicKeyHex: fromPublicKeyHex, inviteData: inviteData));
  }

  /// Envia uma mensagem de texto para um grupo (Chat ID).
  void sendGroupMessage(String chatIdHex, String message) {
    _sendCommand(
        SendGroupMessageCommand(chatIdHex: chatIdHex, message: message));
  }

  /// Sai de um grupo existente.
  void leaveGroup(String chatIdHex) {
    _sendCommand(LeaveGroupCommand(chatIdHex: chatIdHex));
  }

  /// Força gravar o savedata no disco agora, em vez de esperar o próximo
  /// ciclo periódico. Chamado antes de exportar um backup de identidade —
  /// espera o [ToxSavedataFlushedEvent] de confirmação antes de ler o
  /// arquivo, pra garantir que o backup reflete o estado mais recente.
  Future<void> flushSavedata() {
    final completer = Completer<void>();
    late final StreamSubscription<ToxNetworkEvent> subscription;
    subscription = updates.listen((event) {
      if (event is ToxSavedataFlushedEvent) {
        subscription.cancel();
        completer.complete();
      }
    });
    _sendCommand(const FlushSavedataCommand());
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        subscription.cancel();
        throw TimeoutException(
            'O isolate de rede não respondeu ao pedido de backup.');
      },
    );
  }

  /// Encerra a rede Tox de forma limpa e derruba o isolate.
  Future<void> stop() async {
    _sendCommand(const StopCommand());
    await _subscription?.cancel();
    _mainReceivePort.close();
    await _updatesController.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  // ---------------------------------------------------------------------
  // Código executado DENTRO do isolate de rede (thread separada).
  // Precisa ser uma função top-level ou estática — não pode capturar
  // estado da classe, pois isolates não compartilham memória.
  // ---------------------------------------------------------------------

  /// SendPort da UI, acessível pelos callbacks nativos estáticos abaixo.
  /// Callbacks registrados via `Pointer.fromFunction` não podem ser closures
  /// (não podem capturar variáveis locais), então usamos um campo estático
  /// como ponte — seguro aqui porque os callbacks só disparam de forma
  /// síncrona, dentro de `toxIterate()`, no mesmo isolate que os registrou.
  static SendPort? _networkEventSendPort;

  /// Transferências de arquivo ativas, chaveadas por (friend_number,
  /// file_number) — ambos efêmeros por sessão, mas suficientes: só
  /// precisamos rastrear isso enquanto o isolate (e a transferência) está
  /// vivo. Estático pelo mesmo motivo que [_networkEventSendPort]: os
  /// callbacks de arquivo (`Pointer.fromFunction`) não podem capturar
  /// variáveis locais do isolate.
  static final Map<(int, int), _ActiveFileTransfer> _activeFileTransfers = {};

  static void _onFriendRequestNative(
    ffi.Pointer<ffi.Void> tox,
    ffi.Pointer<ffi.Uint8> publicKey,
    ffi.Pointer<ffi.Uint8> message,
    int length,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    _networkEventSendPort?.send(
      ToxFriendRequestEvent(
        publicKeyHex: bindings.readPublicKeyHex(publicKey),
        message: bindings.readUtf8(message, length),
      ),
    );
  }

  static void _onFriendConnectionStatusNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int connectionStatus,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final publicKeyHex = bindings.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxFriendConnectionEvent(
        friendNumber: friendNumber,
        publicKeyHex: publicKeyHex,
        connection: ToxConnection.fromNative(connectionStatus),
      ),
    );
  }

  static void _onFriendMessageNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int messageType,
    ffi.Pointer<ffi.Uint8> message,
    int length,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final publicKeyHex = bindings.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxFriendMessageEvent(
        publicKeyHex: publicKeyHex,
        message: bindings.readUtf8(message, length),
        receivedAt: DateTime.now(),
      ),
    );
  }

  static void _onFriendReadReceiptNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int messageId,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final publicKeyHex = bindings.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxMessageReadReceiptEvent(
          publicKeyHex: publicKeyHex, toxMessageId: messageId),
    );
  }

  /// Um amigo está nos oferecendo um arquivo. Só guarda o estado e avisa a
  /// UI — o arquivo de destino só é aberto quando a UI decidir aceitar (ver
  /// RespondFileControlCommand), então nada é escrito em disco sem consentimento.
  static void _onFileRecvNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int fileNumber,
    int kind,
    int fileSize,
    ffi.Pointer<ffi.Uint8> filename,
    int filenameLength,
    ffi.Pointer<ffi.Void> userData,
  ) {
    if (kind != kToxFileKindData) return; // ignora avatares/stickers/hashes
    final bindings = ToxCoreBindings.instance;
    final publicKeyHex = bindings.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    final fileName = bindings.readUtf8(filename, filenameLength);

    _activeFileTransfers[(friendNumber, fileNumber)] = _ActiveFileTransfer(
      publicKeyHex: publicKeyHex,
      fileNumber: fileNumber,
      fileName: fileName,
      totalBytes: fileSize,
      outgoing: false,
    );
    _networkEventSendPort?.send(
      ToxFileTransferEvent(
        publicKeyHex: publicKeyHex,
        fileNumber: fileNumber,
        phase: ToxFileTransferPhase.requested,
        outgoing: false,
        fileName: fileName,
        totalBytes: fileSize,
        bytesTransferred: 0,
      ),
    );
  }

  /// O toxcore está pedindo o próximo pedaço de um arquivo que ESTAMOS
  /// enviando. `length == 0` sinaliza fim da transferência (concluída ou
  /// cancelada pelo destinatário).
  static void _onFileChunkRequestNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int fileNumber,
    int position,
    int length,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final key = (friendNumber, fileNumber);
    final transfer = _activeFileTransfers[key];
    if (transfer == null) return;

    if (length == 0) {
      transfer.file?.closeSync();
      _activeFileTransfers.remove(key);
      _networkEventSendPort?.send(
        ToxFileTransferEvent(
          publicKeyHex: transfer.publicKeyHex,
          fileNumber: fileNumber,
          phase: ToxFileTransferPhase.completed,
          outgoing: true,
          fileName: transfer.fileName,
          totalBytes: transfer.totalBytes,
          bytesTransferred: transfer.totalBytes,
        ),
      );
      return;
    }

    final file = transfer.file;
    if (file == null) return;
    file.setPositionSync(position);
    final data = file.readSync(length);
    ToxCoreBindings.instance
        .fileSendChunk(tox, friendNumber, fileNumber, position, data);
    transfer.transferredBytes = position + data.length;
    _networkEventSendPort?.send(
      ToxFileTransferEvent(
        publicKeyHex: transfer.publicKeyHex,
        fileNumber: fileNumber,
        phase: ToxFileTransferPhase.progress,
        outgoing: true,
        fileName: transfer.fileName,
        totalBytes: transfer.totalBytes,
        bytesTransferred: transfer.transferredBytes,
      ),
    );
  }

  /// Chegou um pedaço de um arquivo que ESTAMOS recebendo. `length == 0`
  /// sinaliza fim da transferência.
  static void _onFileRecvChunkNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int fileNumber,
    int position,
    ffi.Pointer<ffi.Uint8> data,
    int length,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final key = (friendNumber, fileNumber);
    final transfer = _activeFileTransfers[key];
    if (transfer == null) return;

    if (length == 0) {
      transfer.file?.closeSync();
      _activeFileTransfers.remove(key);
      _networkEventSendPort?.send(
        ToxFileTransferEvent(
          publicKeyHex: transfer.publicKeyHex,
          fileNumber: fileNumber,
          phase: ToxFileTransferPhase.completed,
          outgoing: false,
          fileName: transfer.fileName,
          totalBytes: transfer.totalBytes,
          bytesTransferred: transfer.totalBytes,
          savedPath: transfer.savedPath,
        ),
      );
      return;
    }

    final file = transfer.file;
    // Ainda preparando o destino em disco (ver RespondFileControlCommand) —
    // não deveria acontecer na prática, já que só mandamos RESUME depois
    // de abrir o arquivo, mas não custa ser defensivo.
    if (file == null) return;
    file.setPositionSync(position);
    file.writeFromSync(data.asTypedList(length));
    transfer.transferredBytes = position + length;
    _networkEventSendPort?.send(
      ToxFileTransferEvent(
        publicKeyHex: transfer.publicKeyHex,
        fileNumber: fileNumber,
        phase: ToxFileTransferPhase.progress,
        outgoing: false,
        fileName: transfer.fileName,
        totalBytes: transfer.totalBytes,
        bytesTransferred: transfer.transferredBytes,
      ),
    );
  }

  /// O outro lado pausou/cancelou uma transferência (em qualquer direção).
  /// RESUME não precisa de tratamento aqui: para quem envia, o próprio
  /// pedido de chunk já confirma que foi aceito; para quem recebe, é a
  /// própria UI que inicia o RESUME.
  static void _onFileRecvControlNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int fileNumber,
    int control,
    ffi.Pointer<ffi.Void> userData,
  ) {
    if (control != kToxFileControlCancel) return;
    final key = (friendNumber, fileNumber);
    final transfer = _activeFileTransfers.remove(key);
    if (transfer == null) return;
    transfer.file?.closeSync();
    _networkEventSendPort?.send(
      ToxFileTransferEvent(
        publicKeyHex: transfer.publicKeyHex,
        fileNumber: fileNumber,
        phase: ToxFileTransferPhase.cancelled,
        outgoing: transfer.outgoing,
        fileName: transfer.fileName,
        totalBytes: transfer.totalBytes,
        bytesTransferred: transfer.transferredBytes,
      ),
    );
  }

  static void _onFriendNameNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    ffi.Pointer<ffi.Uint8> name,
    int length,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final publicKeyHex = bindings.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxFriendProfileEvent(
        publicKeyHex: publicKeyHex,
        name: bindings.readUtf8(name, length),
        statusMessage: bindings.friendGetStatusMessage(tox, friendNumber),
      ),
    );
  }

  static void _onFriendStatusMessageNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    ffi.Pointer<ffi.Uint8> message,
    int length,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final publicKeyHex = bindings.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxFriendProfileEvent(
        publicKeyHex: publicKeyHex,
        name: bindings.friendGetName(tox, friendNumber),
        statusMessage: bindings.readUtf8(message, length),
      ),
    );
  }

  static void _onGroupInviteNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    ffi.Pointer<ffi.Uint8> inviteData,
    int inviteDataLength,
    ffi.Pointer<ffi.Uint8> groupName,
    int groupNameLength,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final publicKeyHex = bindings.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxGroupInviteEvent(
        fromPublicKeyHex: publicKeyHex,
        groupName: bindings.readUtf8(groupName, groupNameLength),
        inviteData:
            Uint8List.fromList(inviteData.asTypedList(inviteDataLength)),
      ),
    );
  }

  static void _onGroupMessageNative(
    ffi.Pointer<ffi.Void> tox,
    int groupNumber,
    int peerId,
    int messageType,
    ffi.Pointer<ffi.Uint8> message,
    int messageLength,
    int messageId,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final chatIdHex = bindings.groupGetChatIdHex(tox, groupNumber);
    if (chatIdHex == null) return;
    _networkEventSendPort?.send(
      ToxGroupMessageEvent(
        chatIdHex: chatIdHex,
        peerId: peerId,
        senderName: bindings.groupPeerGetName(tox, groupNumber, peerId),
        message: bindings.readUtf8(message, messageLength),
        receivedAt: DateTime.now(),
      ),
    );
  }

  static void _onGroupPeerJoinNative(
    ffi.Pointer<ffi.Void> tox,
    int groupNumber,
    int peerId,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final chatIdHex = bindings.groupGetChatIdHex(tox, groupNumber);
    if (chatIdHex == null) return;
    final peerPublicKeyHex =
        bindings.groupPeerGetPublicKey(tox, groupNumber, peerId);
    _networkEventSendPort?.send(
      ToxGroupPeerJoinedEvent(
        chatIdHex: chatIdHex,
        peerId: peerId,
        peerName: bindings.groupPeerGetName(tox, groupNumber, peerId),
        connection:
            bindings.groupPeerGetConnectionStatus(tox, groupNumber, peerId),
        publicKeyHex: peerPublicKeyHex,
      ),
    );
  }

  static void _onGroupPeerExitNative(
    ffi.Pointer<ffi.Void> tox,
    int groupNumber,
    int peerId,
    int exitType,
    ffi.Pointer<ffi.Uint8> name,
    int nameLength,
    ffi.Pointer<ffi.Uint8> partMessage,
    int partMessageLength,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final chatIdHex = bindings.groupGetChatIdHex(tox, groupNumber);
    if (chatIdHex == null) return;
    _networkEventSendPort?.send(
      ToxGroupPeerLeftEvent(
        chatIdHex: chatIdHex,
        peerId: peerId,
        peerName: bindings.readUtf8(name, nameLength),
      ),
    );
  }

  static void _onGroupSelfJoinNative(
    ffi.Pointer<ffi.Void> tox,
    int groupNumber,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final chatIdHex = bindings.groupGetChatIdHex(tox, groupNumber);
    if (chatIdHex == null) return;
    _networkEventSendPort?.send(
      ToxGroupSelfJoinedEvent(
        chatIdHex: chatIdHex,
        name: bindings.groupGetName(tox, groupNumber),
        isFounder:
            bindings.groupSelfGetRole(tox, groupNumber) == kToxGroupRoleFounder,
      ),
    );
  }

  static void _onGroupJoinFailNative(
    ffi.Pointer<ffi.Void> tox,
    int groupNumber,
    int failType,
    ffi.Pointer<ffi.Void> userData,
  ) {
    _networkEventSendPort?.send(
      ToxGroupJoinFailedEvent(reason: 'TOX_GROUP_JOIN_FAIL = $failType'),
    );
  }

  static void _onGroupPeerNameNative(
    ffi.Pointer<ffi.Void> tox,
    int groupNumber,
    int peerId,
    ffi.Pointer<ffi.Uint8> name,
    int nameLength,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final chatIdHex = bindings.groupGetChatIdHex(tox, groupNumber);
    if (chatIdHex == null) return;
    _networkEventSendPort?.send(
      ToxGroupPeerNameEvent(
        chatIdHex: chatIdHex,
        peerId: peerId,
        peerName: bindings.readUtf8(name, nameLength),
      ),
    );
  }

  static void _toxNetworkIsolateEntryPoint(_IsolateBootstrapArgs args) {
    final mainSendPort = args.mainSendPort;
    final isolateReceivePort = ReceivePort();

    // 1º passo: avisa a UI qual porta usar para nos mandar comandos.
    mainSendPort.send(_IsolateHandshake(isolateReceivePort.sendPort));
    _networkEventSendPort = mainSendPort;

    // Habilita o uso de plugins (path_provider) dentro deste isolate em
    // background — sem isso, qualquer platform channel lançaria exceção.
    BackgroundIsolateBinaryMessenger.ensureInitialized(args.rootIsolateToken);

    var running = true;
    ToxConnection lastConnection = ToxConnection.none;

    // Preenchidos assim que a instância Tox existe (ver networkLoop) — os
    // comandos que dependem dela verificam null em vez de travar caso a UI
    // mande algo antes do boot terminar.
    ffi.Pointer<ffi.Void>? tox;
    File? saveFile;
    final bindings = ToxCoreBindings.instance;

    Future<void> persistSavedata() async {
      final currentTox = tox;
      final currentSaveFile = saveFile;
      if (currentTox == null || currentSaveFile == null) return;
      await currentSaveFile.writeAsBytes(bindings.getSavedata(currentTox),
          flush: true);
    }

    // Resolve o friend_number atual (efêmero) a partir da chave pública
    // (estável) — usado para comandos vindos da UI, que só conhecem a
    // chave pública (é o que fica salvo no banco de contatos).
    int? findFriendNumberByPublicKey(String publicKeyHex) {
      final currentTox = tox;
      if (currentTox == null) return null;
      for (final friendNumber in bindings.getFriendList(currentTox)) {
        if (bindings.friendGetPublicKey(currentTox, friendNumber) ==
            publicKeyHex) {
          return friendNumber;
        }
      }
      return null;
    }

    // Resolve o group_number atual (efêmero) a partir do Chat ID (estável)
    // — mesmo raciocínio de findFriendNumberByPublicKey.
    int? findGroupNumberByChatId(String chatIdHex) {
      final currentTox = tox;
      if (currentTox == null) return null;
      for (final groupNumber in bindings.getGroupList(currentTox)) {
        if (bindings.groupGetChatIdHex(currentTox, groupNumber) == chatIdHex) {
          return groupNumber;
        }
      }
      return null;
    }

    // Após adicionar/aceitar um amigo com sucesso, avisa a UI com o mesmo
    // tipo de evento usado para o estado inicial no boot (ToxFriendConnectionEvent)
    // — assim quem está ouvindo a stream sempre associa friend_number a uma
    // chave pública estável pelo mesmo caminho, sem precisar de um segundo
    // tipo de evento só para "amigo novo".
    void notifyFriendAdded(int friendNumber) {
      final currentTox = tox;
      if (currentTox == null) return;
      final publicKeyHex =
          bindings.friendGetPublicKey(currentTox, friendNumber);
      if (publicKeyHex == null) return;
      mainSendPort.send(
        ToxFriendConnectionEvent(
          friendNumber: friendNumber,
          publicKeyHex: publicKeyHex,
          connection:
              bindings.friendGetConnectionStatus(currentTox, friendNumber),
        ),
      );
    }

    isolateReceivePort.listen((dynamic command) {
      if (command is! ToxNetworkCommand) return;

      switch (command) {
        case StopCommand():
          running = false;

        case AddFriendCommand(:final talksnapId, :final message):
          final currentTox = tox;
          if (currentTox == null) return;
          try {
            final friendNumber =
                bindings.friendAdd(currentTox, talksnapId, message);
            mainSendPort.send(ToxFriendAddResultEvent.success(friendNumber));
            notifyFriendAdded(friendNumber);
            unawaited(persistSavedata());
          } catch (e) {
            mainSendPort.send(ToxFriendAddResultEvent.failure(e.toString()));
          }

        case AcceptFriendRequestCommand(:final publicKeyHex):
          final currentTox = tox;
          if (currentTox == null) return;
          try {
            final friendNumber =
                bindings.friendAddNorequest(currentTox, publicKeyHex);
            mainSendPort.send(ToxFriendAddResultEvent.success(friendNumber));
            notifyFriendAdded(friendNumber);
            unawaited(persistSavedata());
          } catch (e) {
            mainSendPort.send(ToxFriendAddResultEvent.failure(e.toString()));
          }

        case RemoveFriendCommand(:final publicKeyHex):
          final currentTox = tox;
          if (currentTox == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber != null &&
              bindings.friendDelete(currentTox, friendNumber)) {
            mainSendPort.send(
              ToxFriendRemovedEvent(
                  friendNumber: friendNumber, publicKeyHex: publicKeyHex),
            );
            unawaited(persistSavedata());
          }

        case SendMessageCommand(:final publicKeyHex, :final message):
          final currentTox = tox;
          if (currentTox == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber == null) {
            mainSendPort.send(
              ToxMessageSentEvent.failure(
                publicKeyHex: publicKeyHex,
                message: message,
                errorMessage: 'Contato não encontrado.',
              ),
            );
            return;
          }
          try {
            final toxMessageId =
                bindings.friendSendMessage(currentTox, friendNumber, message);
            mainSendPort.send(
              ToxMessageSentEvent.success(
                publicKeyHex: publicKeyHex,
                message: message,
                toxMessageId: toxMessageId,
                sentAt: DateTime.now(),
              ),
            );
          } catch (e) {
            mainSendPort.send(
              ToxMessageSentEvent.failure(
                publicKeyHex: publicKeyHex,
                message: message,
                errorMessage: e.toString(),
              ),
            );
          }

        case SendFileCommand(:final publicKeyHex, :final filePath):
          final currentTox = tox;
          if (currentTox == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          final sourceFile = File(filePath);
          if (friendNumber == null || !sourceFile.existsSync()) {
            mainSendPort.send(
              ToxFileTransferEvent(
                publicKeyHex: publicKeyHex,
                fileNumber: null,
                phase: ToxFileTransferPhase.failed,
                outgoing: true,
                errorMessage: friendNumber == null
                    ? 'Contato não encontrado.'
                    : 'Arquivo não encontrado.',
              ),
            );
            return;
          }
          final fileSize = sourceFile.lengthSync();
          final fileName = p.basename(filePath);
          try {
            final fileNumber =
                bindings.fileSend(currentTox, friendNumber, fileSize, fileName);
            _activeFileTransfers[(friendNumber, fileNumber)] =
                _ActiveFileTransfer(
              publicKeyHex: publicKeyHex,
              fileNumber: fileNumber,
              fileName: fileName,
              totalBytes: fileSize,
              outgoing: true,
            )..file = sourceFile.openSync();
            mainSendPort.send(
              ToxFileTransferEvent(
                publicKeyHex: publicKeyHex,
                fileNumber: fileNumber,
                phase: ToxFileTransferPhase.requested,
                outgoing: true,
                fileName: fileName,
                totalBytes: fileSize,
                bytesTransferred: 0,
              ),
            );
          } catch (e) {
            mainSendPort.send(
              ToxFileTransferEvent(
                publicKeyHex: publicKeyHex,
                fileNumber: null,
                phase: ToxFileTransferPhase.failed,
                outgoing: true,
                fileName: fileName,
                totalBytes: fileSize,
                errorMessage: e.toString(),
              ),
            );
          }

        case RespondFileControlCommand(
            :final publicKeyHex,
            :final fileNumber,
            :final control
          ):
          final currentTox = tox;
          if (currentTox == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber == null) return;
          final key = (friendNumber, fileNumber);
          final transfer = _activeFileTransfers[key];

          if (control == ToxFileControlAction.resume &&
              transfer != null &&
              !transfer.outgoing) {
            // Precisa existir um arquivo de destino ANTES de mandar RESUME —
            // senão os primeiros chunks podem chegar sem ter onde ir.
            unawaited(() async {
              final directory = await getApplicationSupportDirectory();
              final attachmentsDir = Directory(
                '${directory.path}${Platform.pathSeparator}attachments',
              );
              await attachmentsDir.create(recursive: true);
              final destPath =
                  '${attachmentsDir.path}${Platform.pathSeparator}${transfer.fileName}';
              transfer.file = await File(destPath).open(mode: FileMode.write);
              transfer.savedPath = destPath;
              bindings.fileControl(
                  currentTox, friendNumber, fileNumber, kToxFileControlResume);
            }());
            return;
          }

          final controlValue = switch (control) {
            ToxFileControlAction.resume => kToxFileControlResume,
            ToxFileControlAction.pause => kToxFileControlPause,
            ToxFileControlAction.cancel => kToxFileControlCancel,
          };
          bindings.fileControl(
              currentTox, friendNumber, fileNumber, controlValue);

          if (control == ToxFileControlAction.cancel) {
            _activeFileTransfers.remove(key);
            transfer?.file?.closeSync();
            mainSendPort.send(
              ToxFileTransferEvent(
                publicKeyHex: publicKeyHex,
                fileNumber: fileNumber,
                phase: ToxFileTransferPhase.cancelled,
                outgoing: transfer?.outgoing ?? false,
                fileName: transfer?.fileName,
                totalBytes: transfer?.totalBytes,
              ),
            );
          }

        case SetProfileCommand(:final name, :final statusMessage):
          final currentTox = tox;
          if (currentTox == null) return;
          bindings.setSelfName(currentTox, name);
          bindings.setSelfStatusMessage(currentTox, statusMessage);
          mainSendPort.send(
              ToxSelfProfileEvent(name: name, statusMessage: statusMessage));
          unawaited(persistSavedata());

        case FlushSavedataCommand():
          unawaited(persistSavedata().then((_) {
            mainSendPort.send(const ToxSavedataFlushedEvent());
          }));

        case CreateGroupCommand(:final groupName):
          final currentTox = tox;
          if (currentTox == null) return;
          try {
            final selfName = bindings.getSelfName(currentTox);
            final groupNumber =
                bindings.groupNew(currentTox, groupName, selfName);
            final chatIdHex =
                bindings.groupGetChatIdHex(currentTox, groupNumber);
            if (chatIdHex != null) {
              mainSendPort.send(
                ToxGroupCreatedEvent(
                  chatIdHex: chatIdHex,
                  name: groupName,
                  isFounder:
                      bindings.groupSelfGetRole(currentTox, groupNumber) ==
                          kToxGroupRoleFounder,
                ),
              );
            }
            unawaited(persistSavedata());
          } catch (e) {
            mainSendPort.send(ToxGroupJoinFailedEvent(reason: e.toString()));
          }

        case InviteToGroupCommand(:final chatIdHex, :final contactPublicKeyHex):
          final currentTox = tox;
          if (currentTox == null) return;
          final groupNumber = findGroupNumberByChatId(chatIdHex);
          final friendNumber = findFriendNumberByPublicKey(contactPublicKeyHex);
          if (groupNumber == null || friendNumber == null) return;
          try {
            bindings.groupInviteFriend(currentTox, groupNumber, friendNumber);
            mainSendPort.send(
              ToxGroupInviteSentEvent(
                chatIdHex: chatIdHex,
                contactPublicKeyHex: contactPublicKeyHex,
              ),
            );
          } catch (_) {
            // Falha de convite não tem uma tela dedicada nesta rodada — o
            // contato simplesmente não recebe o convite.
          }

        case AcceptGroupInviteCommand(
            :final fromPublicKeyHex,
            :final inviteData
          ):
          final currentTox = tox;
          if (currentTox == null) return;
          final friendNumber = findFriendNumberByPublicKey(fromPublicKeyHex);
          if (friendNumber == null) return;
          try {
            final selfName = bindings.getSelfName(currentTox);
            bindings.groupInviteAccept(
                currentTox, friendNumber, inviteData, selfName);
            unawaited(persistSavedata());
          } catch (e) {
            mainSendPort.send(ToxGroupJoinFailedEvent(reason: e.toString()));
          }

        case SendGroupMessageCommand(:final chatIdHex, :final message):
          final currentTox = tox;
          if (currentTox == null) return;
          final groupNumber = findGroupNumberByChatId(chatIdHex);
          if (groupNumber == null) {
            mainSendPort.send(
              ToxGroupMessageSentEvent.failure(
                chatIdHex: chatIdHex,
                message: message,
                errorMessage: 'Grupo não encontrado.',
              ),
            );
            return;
          }
          try {
            bindings.groupSendMessage(currentTox, groupNumber, message);
            mainSendPort.send(
              ToxGroupMessageSentEvent.success(
                chatIdHex: chatIdHex,
                message: message,
                sentAt: DateTime.now(),
              ),
            );
          } catch (e) {
            mainSendPort.send(
              ToxGroupMessageSentEvent.failure(
                chatIdHex: chatIdHex,
                message: message,
                errorMessage: e.toString(),
              ),
            );
          }

        case LeaveGroupCommand(:final chatIdHex):
          final currentTox = tox;
          if (currentTox == null) return;
          final groupNumber = findGroupNumberByChatId(chatIdHex);
          if (groupNumber == null) return;
          bindings.groupLeave(currentTox, groupNumber);
          mainSendPort.send(ToxGroupLeftEvent(chatIdHex: chatIdHex));
          unawaited(persistSavedata());
      }
    });

    // Loop principal de rede: substitui o "while(true)" ingênuo por um loop
    // assíncrono que respeita o intervalo pedido pelo próprio toxcore,
    // liberando a thread do isolate entre uma iteração e outra em vez de
    // ocupar 100% da CPU.
    Future<void> networkLoop() async {
      saveFile = await resolveSavedataFile();
      final currentSaveFile = saveFile!;

      Uint8List? savedata;
      if (await currentSaveFile.exists()) {
        savedata = await currentSaveFile.readAsBytes();
      }

      tox = bindings.createToxInstance(savedata: savedata);
      final currentTox = tox!;

      if (savedata == null) {
        // Primeira execução: persiste a identidade recém-criada imediatamente,
        // para que ela já exista em disco mesmo que o app feche logo em seguida.
        await currentSaveFile.writeAsBytes(bindings.getSavedata(currentTox),
            flush: true);
      }

      bindings.bootstrapNetwork(currentTox);

      bindings.setFriendRequestCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFriendRequestCallbackNative>(
            _onFriendRequestNative),
      );
      bindings.setFriendConnectionStatusCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFriendConnectionStatusCallbackNative>(
          _onFriendConnectionStatusNative,
        ),
      );
      bindings.setFriendMessageCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFriendMessageCallbackNative>(
            _onFriendMessageNative),
      );
      bindings.setFriendReadReceiptCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFriendReadReceiptCallbackNative>(
            _onFriendReadReceiptNative),
      );
      bindings.setFileRecvCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFileRecvCallbackNative>(_onFileRecvNative),
      );
      bindings.setFileChunkRequestCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFileChunkRequestCallbackNative>(
            _onFileChunkRequestNative),
      );
      bindings.setFileRecvChunkCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFileRecvChunkCallbackNative>(
            _onFileRecvChunkNative),
      );
      bindings.setFileRecvControlCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFileRecvControlCallbackNative>(
            _onFileRecvControlNative),
      );
      bindings.setFriendNameCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFriendNameCallbackNative>(
            _onFriendNameNative),
      );
      bindings.setFriendStatusMessageCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFriendStatusMessageCallbackNative>(
          _onFriendStatusMessageNative,
        ),
      );
      bindings.setGroupInviteCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxGroupInviteCallbackNative>(
            _onGroupInviteNative),
      );
      bindings.setGroupMessageCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxGroupMessageCallbackNative>(
            _onGroupMessageNative),
      );
      bindings.setGroupPeerJoinCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxGroupPeerJoinCallbackNative>(
            _onGroupPeerJoinNative),
      );
      bindings.setGroupPeerExitCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxGroupPeerExitCallbackNative>(
            _onGroupPeerExitNative),
      );
      bindings.setGroupSelfJoinCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxGroupSelfJoinCallbackNative>(
            _onGroupSelfJoinNative),
      );
      bindings.setGroupJoinFailCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxGroupJoinFailCallbackNative>(
            _onGroupJoinFailNative),
      );
      bindings.setGroupPeerNameCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxGroupPeerNameCallbackNative>(
            _onGroupPeerNameNative),
      );

      // Envia o Talksnap ID assim que ele é conhecido — a UI só precisa disso
      // uma vez (é o mesmo ID a cada execução, agora que persiste em disco).
      final talksnapId = bindings.readSelfAddress(currentTox);
      mainSendPort.send(
        ToxSelfStatusEvent(
            connection: ToxConnection.none, talksnapId: talksnapId),
      );

      // Nome/status do próprio perfil (já salvos no savedata, se algum dia
      // foram definidos — string vazia na primeiríssima execução).
      mainSendPort.send(
        ToxSelfProfileEvent(
          name: bindings.getSelfName(currentTox),
          statusMessage: bindings.getSelfStatusMessage(currentTox),
        ),
      );

      // Amigos já existentes (restaurados do savedata): informa a UI do
      // estado inicial de cada um, já que eles não disparam o callback de
      // "mudança" de conexão até a primeira mudança de fato.
      for (final friendNumber in bindings.getFriendList(currentTox)) {
        final publicKeyHex =
            bindings.friendGetPublicKey(currentTox, friendNumber);
        if (publicKeyHex == null) continue;
        mainSendPort.send(
          ToxFriendConnectionEvent(
            friendNumber: friendNumber,
            publicKeyHex: publicKeyHex,
            connection:
                bindings.friendGetConnectionStatus(currentTox, friendNumber),
          ),
        );
        mainSendPort.send(
          ToxFriendProfileEvent(
            publicKeyHex: publicKeyHex,
            name: bindings.friendGetName(currentTox, friendNumber),
            statusMessage:
                bindings.friendGetStatusMessage(currentTox, friendNumber),
          ),
        );
      }

      // Grupos já existentes (restaurados do savedata): reusa
      // ToxGroupSelfJoinedEvent, o mesmo evento de "entrei no grupo", já que
      // do ponto de vista da UI o efeito é idêntico — o estado de membros ao
      // vivo é reconstruído conforme os peers reconectam.
      for (final groupNumber in bindings.getGroupList(currentTox)) {
        final chatIdHex = bindings.groupGetChatIdHex(currentTox, groupNumber);
        if (chatIdHex == null) continue;
        mainSendPort.send(
          ToxGroupSelfJoinedEvent(
            chatIdHex: chatIdHex,
            name: bindings.groupGetName(currentTox, groupNumber),
            isFounder: bindings.groupSelfGetRole(currentTox, groupNumber) ==
                kToxGroupRoleFounder,
          ),
        );
      }

      var iterationsSinceLastSave = 0;
      var lastBootstrapAttempt = DateTime.now();
      while (running) {
        bindings.toxIterate(currentTox, ffi.nullptr);

        final currentConnection = ToxConnection.fromNative(
            bindings.toxSelfGetConnectionStatus(currentTox));
        if (currentConnection != lastConnection) {
          lastConnection = currentConnection;
          mainSendPort.send(ToxSelfStatusEvent(connection: currentConnection));
        }

        // Fase 6: em rede real (NAT restritivo, firewall, pacote UDP
        // inicial perdido), a tentativa única de bootstrap no boot pode
        // falhar sem nunca mais se recuperar sozinha. Se ainda estivermos
        // sem conexão global depois de um tempo, tenta de novo.
        if (currentConnection == ToxConnection.none &&
            DateTime.now().difference(lastBootstrapAttempt) >=
                _kBootstrapRetryInterval) {
          lastBootstrapAttempt = DateTime.now();
          bindings.bootstrapNetwork(currentTox);
        }

        if (++iterationsSinceLastSave >= _kSaveEveryNIterations) {
          iterationsSinceLastSave = 0;
          await persistSavedata();
        }

        final intervalMs = bindings.toxIterationInterval(currentTox);
        await Future<void>.delayed(Duration(milliseconds: intervalMs));
      }

      // Encerramento limpo: persiste o estado final e libera a memória
      // nativa alocada pelo toxcore.
      await persistSavedata();
      bindings.toxKill(currentTox);
      isolateReceivePort.close();
      Isolate.exit();
    }

    networkLoop();
  }
}
