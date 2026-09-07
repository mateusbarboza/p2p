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

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dev_profile.dart' show activeAccountSlug, setActiveAccountSlug;
import 'identity_backup.dart' show resolveSavedataFile;
import 'tox_bindings.dart';
import 'tox_events.dart';
import 'toxav_bindings.dart';

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

/// Bit rate de áudio EM KBIT/S (não bits/s! — é assim que toxav_call/
/// toxav_answer esperam, ver toxav.h) usado em toda chamada de voz: 32
/// kbit/s é bom o suficiente pra Opus falado.
const int _kCallAudioBitRate = 32;

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
    required this.activeAccountSlug,
  });

  final SendPort mainSendPort;
  final RootIsolateToken rootIsolateToken;

  /// A conta local ativa (ver dev_profile.dart) precisa ser passada
  /// explicitamente — isolates não compartilham memória com o isolate
  /// principal, então a variável global lá não é vista aqui dentro sem
  /// isso, mesmo que já esteja definida quando o isolate nasce.
  final String? activeAccountSlug;
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

  /// Evita rodar [stop] duas vezes (ex: chamado explicitamente ao trocar de
  /// conta E de novo pelo `ref.onDispose` automático do Riverpod ao
  /// derrubar o ProviderScope aninhado) — sem isso, fechar
  /// [_updatesController] pela segunda vez lançaria `StateError`.
  bool _stopped = false;

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
        activeAccountSlug: activeAccountSlug,
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

  /// Avisa um contato que estamos (ou paramos de) digitar uma mensagem pra
  /// ele — a UI chama isso a cada tecla (com debounce) e ao enviar/limpar o
  /// campo de mensagem.
  void setTyping(String publicKeyHex, bool isTyping) {
    _sendCommand(
        SetTypingCommand(publicKeyHex: publicKeyHex, isTyping: isTyping));
  }

  /// Liga para um contato já conectado — `video: true` negocia vídeo
  /// também. O resultado chega pela stream [updates] como
  /// [ToxCallStateEvent].
  void startCall(String publicKeyHex, {bool video = false}) {
    _sendCommand(StartCallCommand(publicKeyHex: publicKeyHex, video: video));
  }

  /// Atende uma chamada recebida (ver [ToxCallIncomingEvent]).
  void answerCall(String publicKeyHex, {bool video = false}) {
    _sendCommand(AnswerCallCommand(publicKeyHex: publicKeyHex, video: video));
  }

  /// Encerra ou recusa uma chamada (ativa ou ainda tocando).
  void hangUp(String publicKeyHex) {
    _sendCommand(HangUpCallCommand(publicKeyHex: publicKeyHex));
  }

  /// Manda um frame de áudio PCM16 (mono, 48kHz) capturado do microfone —
  /// chamado a cada ~20ms enquanto a chamada está ativa e não está muda.
  void sendCallAudioFrame(String publicKeyHex, Int16List samples) {
    _sendCommand(SendCallAudioFrameCommand(
        publicKeyHex: publicKeyHex, samples: samples));
  }

  /// Manda um frame de vídeo (YUV420 plano, já pronto — ver
  /// call_provider.dart) capturado da webcam.
  void sendCallVideoFrame(
    String publicKeyHex,
    int width,
    int height,
    Uint8List yuvBytes,
  ) {
    _sendCommand(SendCallVideoFrameCommand(
      publicKeyHex: publicKeyHex,
      width: width,
      height: height,
      yuvBytes: yuvBytes,
    ));
  }

  /// Liga (`bitRate > 0`) ou desliga (`0`) o canal de vídeo de uma chamada
  /// já em andamento — ver [SetCallVideoBitRateCommand].
  void setCallVideoBitRate(String publicKeyHex, int bitRate) {
    _sendCommand(SetCallVideoBitRateCommand(
        publicKeyHex: publicKeyHex, bitRate: bitRate));
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

  /// Muda o status de presença (Online/Ausente/Ocupado — ver
  /// kToxUserStatus* em tox_bindings.dart).
  void setUserStatus(int userStatus) {
    _sendCommand(SetUserStatusCommand(userStatus: userStatus));
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
    if (_stopped) return;
    _stopped = true;
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

  /// Mesma justificativa do campo acima — os callbacks nativos da ToxAV só
  /// recebem `ToxAV*` (não o `Tox*` associado), mas resolver a chave
  /// pública de um `friend_number` precisa do `Tox*` (`friendGetPublicKey`
  /// já existe em `ToxCoreBindings`, não faz sentido duplicar). Como só
  /// existe UM `Tox*`/`ToxAV*` por isolate, guardar aqui é seguro.
  static ffi.Pointer<ffi.Void>? _activeTox;

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

  static void _onFriendTypingNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int typing,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final publicKeyHex = bindings.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxFriendTypingEvent(publicKeyHex: publicKeyHex, isTyping: typing != 0),
    );
  }

  /// `av` só identifica a instância ToxAV, não o `Tox*` associado — usamos
  /// [_activeTox] (só existe um por isolate) pra resolver a chave pública.
  static void _onAvCallNative(
    ffi.Pointer<ffi.Void> av,
    int friendNumber,
    int audioEnabled,
    int videoEnabled,
    ffi.Pointer<ffi.Void> userData,
  ) {
    // ignore: avoid_print
    print('[call-debug] _onAvCallNative friendNumber=$friendNumber');
    final tox = _activeTox;
    if (tox == null) return;
    final publicKeyHex =
        ToxCoreBindings.instance.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxCallIncomingEvent(publicKeyHex: publicKeyHex),
    );
  }

  static void _onAvCallStateNative(
    ffi.Pointer<ffi.Void> av,
    int friendNumber,
    int state,
    ffi.Pointer<ffi.Void> userData,
  ) {
    // ignore: avoid_print
    print('[call-debug] _onAvCallStateNative friendNumber=$friendNumber '
        'state=$state');
    final tox = _activeTox;
    if (tox == null) return;
    final publicKeyHex =
        ToxCoreBindings.instance.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxCallStateEvent(
        publicKeyHex: publicKeyHex,
        active: (state & kToxavFriendCallStateAcceptingA) != 0,
        ended: (state &
                (kToxavFriendCallStateFinished | kToxavFriendCallStateError)) !=
            0,
        videoActive: (state & kToxavFriendCallStateSendingV) != 0,
      ),
    );
  }

  static void _onAvAudioReceiveFrameNative(
    ffi.Pointer<ffi.Void> av,
    int friendNumber,
    ffi.Pointer<ffi.Int16> pcm,
    int sampleCount,
    int channels,
    int samplingRate,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final tox = _activeTox;
    if (tox == null) return;
    final publicKeyHex =
        ToxCoreBindings.instance.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    // Cópia pra um Int16List Dart normal — o buffer nativo só é válido
    // durante esta chamada de callback.
    final samples = Int16List.fromList(pcm.asTypedList(sampleCount));
    _networkEventSendPort?.send(
      ToxCallAudioFrameEvent(publicKeyHex: publicKeyHex, samples: samples),
    );
  }

  /// Copia um plano Y/U/V respeitando o stride (pode ter padding — nunca é
  /// garantido que `stride == width`). Não trata corretamente o caso raro
  /// de stride negativo (imagem de cabeça pra baixo) — só usa o valor
  /// absoluto — aceitável nesta primeira versão (ver risco anotado no
  /// plano de chamada de vídeo).
  static Uint8List _copyVideoPlane(
    ffi.Pointer<ffi.Uint8> ptr,
    int width,
    int height,
    int stride,
  ) {
    final rowStride = stride.abs() < width ? width : stride.abs();
    final out = Uint8List(width * height);
    for (var row = 0; row < height; row++) {
      final src = (ptr + row * rowStride).asTypedList(width);
      out.setRange(row * width, row * width + width, src);
    }
    return out;
  }

  static int _videoFrameRecvCount = 0;

  static void _onAvVideoReceiveFrameNative(
    ffi.Pointer<ffi.Void> av,
    int friendNumber,
    int width,
    int height,
    ffi.Pointer<ffi.Uint8> y,
    ffi.Pointer<ffi.Uint8> u,
    ffi.Pointer<ffi.Uint8> v,
    int yStride,
    int uStride,
    int vStride,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final tox = _activeTox;
    if (tox == null) return;
    final publicKeyHex =
        ToxCoreBindings.instance.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;

    _videoFrameRecvCount++;
    if (_videoFrameRecvCount % 15 == 1) {
      // ignore: avoid_print
      print('[call-debug] _onAvVideoReceiveFrameNative #$_videoFrameRecvCount '
          'friendNumber=$friendNumber width=$width height=$height');
    }

    final chromaWidth = (width / 2).ceil();
    final chromaHeight = (height / 2).ceil();
    final yBytes = _copyVideoPlane(y, width, height, yStride);
    final uBytes = _copyVideoPlane(u, chromaWidth, chromaHeight, uStride);
    final vBytes = _copyVideoPlane(v, chromaWidth, chromaHeight, vStride);

    // Buffer I420 plano compacto (Y, depois U, depois V) — layout que o
    // opencv_dart espera pra decodificar com cvtColor(COLOR_YUV2BGRA_I420).
    final totalLength = yBytes.length + uBytes.length + vBytes.length;
    final yuv = Uint8List(totalLength)
      ..setRange(0, yBytes.length, yBytes)
      ..setRange(yBytes.length, yBytes.length + uBytes.length, uBytes)
      ..setRange(yBytes.length + uBytes.length, totalLength, vBytes);

    final yuvMat = cv.Mat.create(
      rows: (height * 1.5).toInt(),
      cols: width,
      type: cv.MatType.CV_8UC1,
    );
    yuvMat.data.setRange(0, yuv.length, yuv);
    final bgraMat = cv.cvtColor(yuvMat, cv.COLOR_YUV2BGRA_I420);
    final bgraBytes = Uint8List.fromList(bgraMat.data);
    yuvMat.dispose();
    bgraMat.dispose();

    _networkEventSendPort?.send(
      ToxCallVideoFrameEvent(
        publicKeyHex: publicKeyHex,
        width: width,
        height: height,
        bgraBytes: bgraBytes,
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
        userStatus: bindings.friendGetUserStatus(tox, friendNumber),
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
        userStatus: bindings.friendGetUserStatus(tox, friendNumber),
      ),
    );
  }

  static void _onFriendUserStatusNative(
    ffi.Pointer<ffi.Void> tox,
    int friendNumber,
    int status,
    ffi.Pointer<ffi.Void> userData,
  ) {
    final bindings = ToxCoreBindings.instance;
    final publicKeyHex = bindings.friendGetPublicKey(tox, friendNumber);
    if (publicKeyHex == null) return;
    _networkEventSendPort?.send(
      ToxFriendProfileEvent(
        publicKeyHex: publicKeyHex,
        name: bindings.friendGetName(tox, friendNumber),
        statusMessage: bindings.friendGetStatusMessage(tox, friendNumber),
        userStatus: status,
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
    // Precisa ser a primeiríssima coisa: resolveSavedataFile() (chamado logo
    // abaixo em networkLoop) depende disso pra apontar pro arquivo da conta
    // certa — sem isso, essa cópia isolada da variável ficaria `null` pra
    // sempre, mesmo com a conta certa já ativa no isolate principal.
    setActiveAccountSlug(args.activeAccountSlug);

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
    ffi.Pointer<ffi.Void>? toxAv;
    File? saveFile;
    final bindings = ToxCoreBindings.instance;
    final avBindings = ToxAvBindings.instance;

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
          // Sempre avisa a UI, mesmo se essa chave já não for mais amigo de
          // verdade no toxcore (ex: contato "fantasma" sobrando no banco
          // local de uma identidade anterior) — sem isso, o contato nunca
          // sai da lista, já que é esse evento que aciona
          // repository.delete() do lado da UI.
          if (friendNumber != null) {
            bindings.friendDelete(currentTox, friendNumber);
            unawaited(persistSavedata());
          }
          mainSendPort.send(
            ToxFriendRemovedEvent(
                friendNumber: friendNumber ?? -1, publicKeyHex: publicKeyHex),
          );

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
                notConnected: e is ToxFriendNotConnectedException,
              ),
            );
          }

        case SetTypingCommand(:final publicKeyHex, :final isTyping):
          final currentTox = tox;
          if (currentTox == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber == null) return;
          bindings.setSelfTyping(currentTox, friendNumber, isTyping);

        case StartCallCommand(:final publicKeyHex, :final video):
          final currentToxAv = toxAv;
          if (currentToxAv == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber == null) return;
          try {
            avBindings.toxavCall(
              currentToxAv,
              friendNumber,
              _kCallAudioBitRate,
              videoBitRate: video ? kCallVideoBitRateKbps : 0,
            );
          } catch (e) {
            // ignore: avoid_print
            print('[call-debug] toxavCall (video=$video) falhou: $e');
          }

        case AnswerCallCommand(:final publicKeyHex, :final video):
          final currentToxAv = toxAv;
          if (currentToxAv == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber == null) return;
          try {
            avBindings.toxavAnswer(
              currentToxAv,
              friendNumber,
              _kCallAudioBitRate,
              videoBitRate: video ? kCallVideoBitRateKbps : 0,
            );
          } catch (e) {
            // ignore: avoid_print
            print('[call-debug] toxavAnswer (video=$video) falhou: $e');
          }

        case HangUpCallCommand(:final publicKeyHex):
          final currentToxAv = toxAv;
          if (currentToxAv == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber == null) return;
          avBindings.toxavCancelCall(currentToxAv, friendNumber);

        case SendCallAudioFrameCommand(:final publicKeyHex, :final samples):
          final currentToxAv = toxAv;
          if (currentToxAv == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber == null) return;
          final pcmPtr = pkg_ffi.calloc<ffi.Int16>(samples.length);
          try {
            pcmPtr.asTypedList(samples.length).setAll(0, samples);
            avBindings.toxavAudioSendFrame(
              currentToxAv,
              friendNumber,
              pcmPtr,
              samples.length,
              1,
              48000,
            );
          } finally {
            pkg_ffi.calloc.free(pcmPtr);
          }

        case SendCallVideoFrameCommand(
            :final publicKeyHex,
            :final width,
            :final height,
            :final yuvBytes
          ):
          final currentToxAv = toxAv;
          if (currentToxAv == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber == null) return;
          final ySize = width * height;
          final chromaSize = ((width / 2).ceil()) * ((height / 2).ceil());
          final planesPtr = pkg_ffi.calloc<ffi.Uint8>(yuvBytes.length);
          try {
            planesPtr.asTypedList(yuvBytes.length).setAll(0, yuvBytes);
            avBindings.toxavVideoSendFrame(
              currentToxAv,
              friendNumber,
              width,
              height,
              planesPtr,
              planesPtr + ySize,
              planesPtr + ySize + chromaSize,
            );
          } finally {
            pkg_ffi.calloc.free(planesPtr);
          }

        case SetCallVideoBitRateCommand(:final publicKeyHex, :final bitRate):
          final currentToxAv = toxAv;
          if (currentToxAv == null) return;
          final friendNumber = findFriendNumberByPublicKey(publicKeyHex);
          if (friendNumber == null) return;
          try {
            avBindings.toxavVideoSetBitRate(
                currentToxAv, friendNumber, bitRate);
            // ignore: avoid_print
            print('[call-debug] toxavVideoSetBitRate friendNumber='
                '$friendNumber bitRate=$bitRate OK');
          } catch (e) {
            // ignore: avoid_print
            print('[call-debug] toxavVideoSetBitRate friendNumber='
                '$friendNumber bitRate=$bitRate FALHOU: $e');
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
              try {
                final directory = await getApplicationSupportDirectory();
                final attachmentsDir = Directory(
                  '${directory.path}${Platform.pathSeparator}attachments',
                );
                await attachmentsDir.create(recursive: true);
                final destPath =
                    '${attachmentsDir.path}${Platform.pathSeparator}${transfer.fileName}';
                transfer.file = await File(destPath).open(mode: FileMode.write);
                transfer.savedPath = destPath;
                bindings.fileControl(currentTox, friendNumber, fileNumber,
                    kToxFileControlResume);
              } catch (e) {
                mainSendPort.send(
                  ToxFileTransferEvent(
                    publicKeyHex: publicKeyHex,
                    fileNumber: fileNumber,
                    phase: ToxFileTransferPhase.failed,
                    outgoing: false,
                    fileName: transfer.fileName,
                    totalBytes: transfer.totalBytes,
                    errorMessage: e.toString(),
                  ),
                );
              }
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
            ToxSelfProfileEvent(
              name: name,
              statusMessage: statusMessage,
              userStatus: bindings.getSelfUserStatus(currentTox),
            ),
          );
          unawaited(persistSavedata());

        case SetUserStatusCommand(:final userStatus):
          final currentTox = tox;
          if (currentTox == null) return;
          bindings.setSelfUserStatus(currentTox, userStatus);
          mainSendPort.send(
            ToxSelfProfileEvent(
              name: bindings.getSelfName(currentTox),
              statusMessage: bindings.getSelfStatusMessage(currentTox),
              userStatus: userStatus,
            ),
          );
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
      _activeTox = currentTox;

      if (savedata == null) {
        // Primeira execução: persiste a identidade recém-criada imediatamente,
        // para que ela já exista em disco mesmo que o app feche logo em seguida.
        await currentSaveFile.writeAsBytes(bindings.getSavedata(currentTox),
            flush: true);
      }

      bindings.bootstrapNetwork(currentTox);

      // ToxAV (chamada de voz) — 1 instância por instância Tox, criada
      // logo depois dele (ver toxav.h: "each ToxAV instance can be bound
      // to only one Tox instance"). Destruída ANTES do tox no shutdown.
      toxAv = avBindings.toxavNew(currentTox);
      final currentToxAv = toxAv!;
      // ignore: avoid_print
      print('[call-debug] toxavNew OK, av=$currentToxAv');
      avBindings.setCallCallback(
        currentToxAv,
        ffi.Pointer.fromFunction<ToxAvCallCallbackNative>(_onAvCallNative),
      );
      avBindings.setCallStateCallback(
        currentToxAv,
        ffi.Pointer.fromFunction<ToxAvCallStateCallbackNative>(
            _onAvCallStateNative),
      );
      avBindings.setAudioReceiveFrameCallback(
        currentToxAv,
        ffi.Pointer.fromFunction<ToxAvAudioReceiveFrameCallbackNative>(
            _onAvAudioReceiveFrameNative),
      );
      avBindings.setVideoReceiveFrameCallback(
        currentToxAv,
        ffi.Pointer.fromFunction<ToxAvVideoReceiveFrameCallbackNative>(
            _onAvVideoReceiveFrameNative),
      );

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
      bindings.setFriendTypingCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFriendTypingCallbackNative>(
            _onFriendTypingNative),
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
      bindings.setFriendUserStatusCallback(
        currentTox,
        ffi.Pointer.fromFunction<ToxFriendUserStatusCallbackNative>(
          _onFriendUserStatusNative,
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
          userStatus: bindings.getSelfUserStatus(currentTox),
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
            userStatus: bindings.friendGetUserStatus(currentTox, friendNumber),
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

        avBindings.toxavIterate(currentToxAv);

        // As duas APIs pedem intervalos de iteração diferentes — usa o
        // menor dos dois pra nenhuma ficar atrasada (ver toxav.h: "It is
        // best called in the separate thread from tox_iterate", mas aqui
        // roda tudo no mesmo loop assíncrono por simplicidade, já que
        // nenhuma das duas bloqueia por muito tempo).
        final intervalMs = [
          bindings.toxIterationInterval(currentTox),
          avBindings.toxavIterationInterval(currentToxAv),
        ].reduce((a, b) => a < b ? a : b);
        await Future<void>.delayed(Duration(milliseconds: intervalMs));
      }

      // Encerramento limpo: persiste o estado final e libera a memória
      // nativa alocada pelo toxcore. A ToxAV precisa morrer ANTES do tox
      // associado (ver toxav.h).
      await persistSavedata();
      avBindings.toxavKill(currentToxAv);
      bindings.toxKill(currentTox);
      _activeTox = null;
      isolateReceivePort.close();
      Isolate.exit();
    }

    networkLoop();
  }
}
