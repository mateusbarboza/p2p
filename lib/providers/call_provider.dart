// call_provider.dart
//
// Estado de uma chamada de voz 1:1 (ToxAV) + a parte que o Riverpod não
// costuma fazer sozinho aqui: captar o microfone (pacote `record`) e tocar
// o áudio decodificado que chega da rede (pacote `flutter_soloud`). O
// toxcore/toxav só entrega/aceita PCM16 cru — quem grava e quem toca é
// sempre a UI (plugins só funcionam no isolate principal), por isso os
// frames atravessam o isolate de rede como qualquer outro evento/comando
// (ver ToxCallAudioFrameEvent/SendCallAudioFrameCommand em tox_events.dart).
//
// Só uma chamada por vez nesta primeira versão — um segundo
// ToxCallIncomingEvent enquanto já existe uma é ignorado.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

import '../camera_capture_isolate.dart';
import '../data/database.dart' show CallLog;
import '../screen_capture_isolate.dart';
import '../tox_events.dart';
import 'database_provider.dart';
import 'tox_events_provider.dart';
import 'tox_manager_provider.dart';

enum CallStatus { idle, outgoingRinging, incomingRinging, active }

/// De onde vem o vídeo que ESTAMOS mandando — só um por vez, nunca os dois
/// juntos (o ToxAV só tem um canal de vídeo por chamada; câmera e tela de
/// propósito se excluem mutuamente, ver [CallNotifier.toggleVideo]/
/// [CallNotifier.toggleScreenShare]).
enum VideoSource { none, camera, screen }

class CallState {
  const CallState({
    this.status = CallStatus.idle,
    this.contactPublicKeyHex,
    this.muted = false,
    this.outgoing = false,
    this.videoSource = VideoSource.none,
    this.remoteVideoActive = false,
  });

  final CallStatus status;
  final String? contactPublicKeyHex;
  final bool muted;

  /// `true` se fomos nós que ligamos pro contato, `false` se foi ele que
  /// ligou — usado só pra saber como registrar o evento em [CallLogs].
  final bool outgoing;

  /// De onde vem o NOSSO vídeo agora (câmera, tela ou nenhum).
  final VideoSource videoSource;

  /// Nossa própria câmera OU tela está ligada e mandando frames — mantido
  /// como getter (em vez de campo solto) pra não precisar mexer em
  /// chat_screen.dart/main.dart, que só liam isso como bool.
  bool get sendingVideo => videoSource != VideoSource.none;

  /// O CONTATO está mandando vídeo agora (bit SENDING_V do
  /// [ToxCallStateEvent]) — independente de nós estarmos mandando ou não.
  final bool remoteVideoActive;

  CallState copyWith({
    CallStatus? status,
    bool? muted,
    VideoSource? videoSource,
    bool? remoteVideoActive,
  }) {
    return CallState(
      status: status ?? this.status,
      contactPublicKeyHex: contactPublicKeyHex,
      muted: muted ?? this.muted,
      outgoing: outgoing,
      videoSource: videoSource ?? this.videoSource,
      remoteVideoActive: remoteVideoActive ?? this.remoteVideoActive,
    );
  }
}

/// Frame de vídeo mais recente recebido de um contato — bytes BGRA prontos
/// pra `ui.decodeImageFromPixels`. Fica fora do [CallState] (Riverpod) de
/// propósito: um `Notifier` reconstrói a árvore inteira a cada mudança de
/// estado, e frames chegam ~15x/segundo — a UI de vídeo escuta este
/// [ValueNotifier] diretamente em vez de observar o provider.
class RemoteVideoFrame {
  const RemoteVideoFrame({
    required this.width,
    required this.height,
    required this.bgraBytes,
  });
  final int width;
  final int height;
  final Uint8List bgraBytes;
}

/// Mono, 48kHz — taxa que o Opus (usado por dentro do toxav) lida bem, e
/// simplifica não ter que reamostrar nada entre gravação/toxav/reprodução.
const int _kSampleRate = 48000;
const int _kChannels = 1;

/// 20ms de áudio a 48kHz — tamanho de frame convencional pra chamadas de
/// voz (mesmo usado por outros clientes Tox).
const int _kFrameSamples = 960;
const int _kFrameBytes = _kFrameSamples * 2; // PCM16 = 2 bytes/amostra

class CallNotifier extends Notifier<CallState> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSubscription;
  final List<int> _pendingMicBytes = [];
  AudioSource? _playbackSource;

  /// Toque sintetizado (sem precisar de nenhum arquivo de áudio) tocado em
  /// loop enquanto a chamada está chamando/tocando, dos dois lados — imita a
  /// campainha mecânica de telefone antigo: um trinado (alterna rápido entre
  /// duas frequências próximas) que liga e desliga em rajadas curtas, com
  /// uma pausa longa entre elas (ver [_onRingtoneTick]).
  AudioSource? _ringtoneSource;
  SoundHandle? _ringtoneHandle;
  Timer? _ringtoneTimer;
  int _ringtoneElapsedMs = 0;
  bool _ringtoneWarbleHigh = false;

  /// Captura de câmera (opencv_dart), rodando num Isolate dedicado — ver
  /// camera_capture_isolate.dart pro motivo (chamada nativa bloqueante que
  /// pode travar; isolar isso evita congelar o app inteiro). `null` quando
  /// a câmera está desligada/nunca foi ligada.
  CameraCaptureIsolate? _camera;
  StreamSubscription<CameraFrameData>? _cameraFrameSubscription;

  /// Captura de tela (GDI via win32), mesmo raciocínio de isolate acima —
  /// ver screen_capture_isolate.dart. `null` quando não está compartilhando.
  ScreenCaptureIsolate? _screenCapture;
  StreamSubscription<ScreenFrameData>? _screenFrameSubscription;

  /// Frame mais recente recebido do contato — ver [RemoteVideoFrame]. `null`
  /// quando ninguém está mandando vídeo (ou fora de chamada).
  final ValueNotifier<RemoteVideoFrame?> remoteVideoFrame = ValueNotifier(null);

  /// Frame mais recente capturado da NOSSA própria câmera — usado só pro
  /// preview local (canto da tela), mesmo formato de [remoteVideoFrame].
  final ValueNotifier<RemoteVideoFrame?> localPreviewFrame =
      ValueNotifier(null);

  @override
  CallState build() {
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData(_handleEvent);
    });
    ref.onDispose(() {
      unawaited(_stopRingtone());
      unawaited(_stopAudio());
      // Não usa _stopCamera()/_stopScreenShare() aqui: elas fazem
      // `state = ...`, e mexer no state DURANTE o dispose do próprio
      // provider corrompe a lista interna de onDispose do Riverpod
      // ("Concurrent modification during iteration"). Só libera os
      // recursos (isolate/assinatura), sem tocar em state.
      _releaseCameraResources();
      _releaseScreenResources();
      unawaited(_recorder.dispose());
      remoteVideoFrame.dispose();
      localPreviewFrame.dispose();
    });
    return const CallState();
  }

  void _handleEvent(ToxNetworkEvent event) {
    if (event is ToxCallIncomingEvent ||
        event is ToxCallStateEvent ||
        event is ToxCallAudioFrameEvent) {
      // ignore: avoid_print
      print('[call-debug] CallNotifier recebeu $event (status atual '
          '${state.status})');
    }
    if (event is ToxCallIncomingEvent) {
      // Só uma chamada por vez nesta versão — ignora um segundo convite
      // enquanto já existe uma em andamento.
      if (state.status != CallStatus.idle) return;
      state = CallState(
        status: CallStatus.incomingRinging,
        contactPublicKeyHex: event.publicKeyHex,
      );
      unawaited(_startRingtone());
      unawaited(_logCall(event.publicKeyHex, outgoing: false, kind: 'started'));
      return;
    }

    if (event is ToxCallStateEvent) {
      if (state.contactPublicKeyHex != event.publicKeyHex) return;
      if (event.ended) {
        unawaited(_stopRingtone());
        unawaited(_stopAudio());
        _stopCamera();
        _stopScreenShare();
        remoteVideoFrame.value = null;
        unawaited(_logCall(event.publicKeyHex,
            outgoing: state.outgoing, kind: 'ended'));
        state = const CallState();
      } else {
        if (event.active && state.status != CallStatus.active) {
          unawaited(_stopRingtone());
          state = state.copyWith(status: CallStatus.active);
          // _ensureAudioPipeline já deve ter rodado (ver [answer]/[startCall]
          // — o toxav começa a entregar frames de áudio de verdade bem antes
          // desse bit "ativo" aparecer, então não dá pra esperar até aqui).
          unawaited(_ensureAudioPipeline(event.publicKeyHex));
        }
        if (event.videoActive != state.remoteVideoActive) {
          state = state.copyWith(remoteVideoActive: event.videoActive);
          if (!event.videoActive) remoteVideoFrame.value = null;
        }
      }
      return;
    }

    if (event is ToxCallAudioFrameEvent) {
      // Não trava mais em `status == active`: o toxav manda áudio decodificado
      // de verdade assim que a negociação avança, normalmente ANTES do bit
      // ACCEPTING_A (que só chega depois) — travar nisso descartava todo
      // frame real que chegava enquanto ainda mostrávamos "chamando/tocando".
      if (state.contactPublicKeyHex == event.publicKeyHex &&
          state.status != CallStatus.idle) {
        _playReceivedFrame(event.samples);
      }
      return;
    }

    if (event is ToxCallVideoFrameEvent) {
      if (state.contactPublicKeyHex == event.publicKeyHex) {
        remoteVideoFrame.value = RemoteVideoFrame(
          width: event.width,
          height: event.height,
          bgraBytes: event.bgraBytes,
        );
        // O bit SENDING_V do ToxCallStateEvent (usado pra [remoteVideoActive])
        // demora alguns segundos pra ligar depois que o vídeo já está de
        // verdade chegando — visto nos logs: mais de 100 frames reais
        // decodificados antes do toxcore atualizar a flag. Um frame de
        // verdade já É a prova de que o contato está mandando vídeo, então
        // não faz sentido esperar o toxcore confirmar de novo.
        if (!state.remoteVideoActive) {
          state = state.copyWith(remoteVideoActive: true);
        }
      }
    }
  }

  /// Liga pra um contato — `video: true` já liga a própria câmera junto. O
  /// estado só avança pra [CallStatus.active] quando o [ToxCallStateEvent]
  /// correspondente chegar (ele atendeu).
  void startCall(String publicKeyHex, {bool video = false}) {
    if (state.status != CallStatus.idle) return;
    state = CallState(
      status: CallStatus.outgoingRinging,
      contactPublicKeyHex: publicKeyHex,
      outgoing: true,
    );
    unawaited(_startRingtone());
    // O toxav já começa a decodificar/entregar áudio de verdade assim que a
    // chamada é atendida do outro lado, bem antes do nosso bit "ativo" —
    // prepara a reprodução/captura já aqui, não só quando o estado avança.
    unawaited(_ensureAudioPipeline(publicKeyHex));
    unawaited(_logCall(publicKeyHex, outgoing: true, kind: 'started'));
    ref.read(toxIsolateManagerProvider).startCall(publicKeyHex, video: video);
    if (video) unawaited(_startCamera(publicKeyHex));
  }

  /// Atende a chamada que está tocando (ver [CallStatus.incomingRinging]).
  void answer({bool video = false}) {
    final publicKeyHex = state.contactPublicKeyHex;
    if (publicKeyHex == null || state.status != CallStatus.incomingRinging) {
      return;
    }
    unawaited(_ensureAudioPipeline(publicKeyHex));
    ref.read(toxIsolateManagerProvider).answerCall(publicKeyHex, video: video);
    if (video) unawaited(_startCamera(publicKeyHex));
  }

  /// Encerra ou recusa a chamada atual, seja ela tocando ou já ativa.
  void hangUp() {
    final publicKeyHex = state.contactPublicKeyHex;
    if (publicKeyHex == null) return;
    ref.read(toxIsolateManagerProvider).hangUp(publicKeyHex);
    unawaited(_stopRingtone());
    unawaited(_stopAudio());
    _stopCamera();
    _stopScreenShare();
    remoteVideoFrame.value = null;
    unawaited(_logCall(publicKeyHex, outgoing: state.outgoing, kind: 'ended'));
    state = const CallState();
  }

  void toggleMute() {
    // Não trava em `active`: o microfone já é capturado e enviado assim que
    // a chamada começa a tocar (ver [_onMicChunk]), então mudo precisa
    // funcionar desde a mesma hora, pros dois lados da ligação.
    if (state.status == CallStatus.idle) return;
    state = state.copyWith(muted: !state.muted);
  }

  /// Liga/desliga a própria câmera durante uma chamada em andamento — ao
  /// contrário do mudo (que só para de mandar frames, silêncio "de graça"),
  /// desligar a câmera precisa realmente soltar o dispositivo (senão a luz
  /// da webcam fica acesa e outros apps não conseguem usá-la). Se o
  /// compartilhamento de tela estiver ativo, liga a câmera desliga ele
  /// primeiro — só um vídeo de saída por vez (ver [VideoSource]).
  void toggleVideo() {
    final publicKeyHex = state.contactPublicKeyHex;
    if (publicKeyHex == null || state.status == CallStatus.idle) return;
    if (state.videoSource == VideoSource.camera) {
      _stopCamera();
    } else {
      if (state.videoSource == VideoSource.screen) _stopScreenShare();
      unawaited(_startCamera(publicKeyHex));
    }
  }

  /// Liga/desliga o compartilhamento da tela — mesmo raciocínio de
  /// [toggleVideo], mas pra tela em vez da câmera; liga a câmera primeiro
  /// se ela estiver ativa.
  void toggleScreenShare() {
    final publicKeyHex = state.contactPublicKeyHex;
    if (publicKeyHex == null || state.status == CallStatus.idle) return;
    if (state.videoSource == VideoSource.screen) {
      _stopScreenShare();
    } else {
      if (state.videoSource == VideoSource.camera) _stopCamera();
      unawaited(_startScreenShare(publicKeyHex));
    }
  }

  /// Resolução baixa fixa — evita `set()` de propriedades da câmera, que
  /// varia muito entre webcams, e mantém a banda usada previsível.
  static const _kVideoWidth = 320;
  static const _kVideoHeight = 240;
  static const _kVideoCaptureInterval = Duration(milliseconds: 66); // ~15fps

  /// Tela precisa de mais resolução que a câmera (texto tem que dar pra
  /// ler) mas menos fps (conteúdo de tela muda bem menos por segundo que
  /// uma webcam) — mantém a banda usada num patamar parecido.
  static const _kScreenWidth = 960;
  static const _kScreenHeight = 540;
  static const _kScreenCaptureInterval = Duration(milliseconds: 125); // ~8fps

  Future<void> _startCamera(String publicKeyHex) async {
    if (_camera != null) return;
    final camera = await CameraCaptureIsolate.start(
      width: _kVideoWidth,
      height: _kVideoHeight,
      captureInterval: _kVideoCaptureInterval,
    );
    if (camera == null) return;
    // A chamada pode ter sido encerrada ou a câmera desligada de novo
    // enquanto o isolate ainda estava subindo — não deixa um resultado
    // atrasado religar tudo sozinho.
    if (state.status == CallStatus.idle || _camera != null) {
      camera.stop();
      return;
    }
    _camera = camera;
    state = state.copyWith(videoSource: VideoSource.camera);
    // Liga o canal de vídeo no toxav — sem isso, se a chamada começou só
    // de voz (video_bit_rate 0 em toxav_call/toxav_answer),
    // toxav_video_send_frame não tem efeito nenhum e o outro lado nunca
    // vê o bit "vídeo ativo" (ver toxavVideoSetBitRate em
    // toxav_bindings.dart).
    ref
        .read(toxIsolateManagerProvider)
        .setCallVideoBitRate(publicKeyHex, kCallVideoBitRateKbps);
    _cameraFrameSubscription = camera.frames.listen((frame) {
      ref.read(toxIsolateManagerProvider).sendCallVideoFrame(
            publicKeyHex,
            frame.width,
            frame.height,
            frame.yuvBytes,
          );
      localPreviewFrame.value = RemoteVideoFrame(
        width: frame.width,
        height: frame.height,
        bgraBytes: frame.bgraBytes,
      );
    });
  }

  void _releaseCameraResources() {
    unawaited(_cameraFrameSubscription?.cancel());
    _cameraFrameSubscription = null;
    _camera?.stop();
    _camera = null;
  }

  void _stopCamera() {
    _releaseCameraResources();
    if (state.videoSource != VideoSource.camera) return;
    localPreviewFrame.value = null;
    final publicKeyHex = state.contactPublicKeyHex;
    state = state.copyWith(videoSource: VideoSource.none);
    if (publicKeyHex != null) {
      ref.read(toxIsolateManagerProvider).setCallVideoBitRate(publicKeyHex, 0);
    }
  }

  Future<void> _startScreenShare(String publicKeyHex) async {
    if (_screenCapture != null) return;
    final screenCapture = await ScreenCaptureIsolate.start(
      width: _kScreenWidth,
      height: _kScreenHeight,
      captureInterval: _kScreenCaptureInterval,
    );
    if (screenCapture == null) return;
    // Mesmo raciocínio de [_startCamera]: um resultado atrasado não pode
    // religar tudo sozinho se a chamada já acabou/foi cancelada.
    if (state.status == CallStatus.idle || _screenCapture != null) {
      screenCapture.stop();
      return;
    }
    _screenCapture = screenCapture;
    state = state.copyWith(videoSource: VideoSource.screen);
    ref
        .read(toxIsolateManagerProvider)
        .setCallVideoBitRate(publicKeyHex, kCallVideoBitRateKbps);
    _screenFrameSubscription = screenCapture.frames.listen((frame) {
      ref.read(toxIsolateManagerProvider).sendCallVideoFrame(
            publicKeyHex,
            frame.width,
            frame.height,
            frame.yuvBytes,
          );
      localPreviewFrame.value = RemoteVideoFrame(
        width: frame.width,
        height: frame.height,
        bgraBytes: frame.bgraBytes,
      );
    });
  }

  void _releaseScreenResources() {
    unawaited(_screenFrameSubscription?.cancel());
    _screenFrameSubscription = null;
    _screenCapture?.stop();
    _screenCapture = null;
  }

  void _stopScreenShare() {
    _releaseScreenResources();
    if (state.videoSource != VideoSource.screen) return;
    localPreviewFrame.value = null;
    final publicKeyHex = state.contactPublicKeyHex;
    state = state.copyWith(videoSource: VideoSource.none);
    if (publicKeyHex != null) {
      ref.read(toxIsolateManagerProvider).setCallVideoBitRate(publicKeyHex, 0);
    }
  }

  /// Registra "chamando"/"encerrada" na timeline do chat com esse contato
  /// (ver [CallLogs] e o merge na timeline em chat_screen.dart).
  Future<void> _logCall(
    String publicKeyHex, {
    required bool outgoing,
    required String kind,
  }) {
    return ref.read(callLogsRepositoryProvider).insert(
          contactPublicKeyHex: publicKeyHex,
          outgoing: outgoing,
          kind: kind,
          timestamp: DateTime.now(),
        );
  }

  /// Duração de uma rajada de trinado ("brrrim") e da pausa entre rajadas —
  /// mesma cadência clássica de campainha de telefone antigo: toca curto,
  /// silêncio bem mais longo, repete.
  static const _kRingBurstMs = 1200;
  static const _kRingCycleMs = 4200;

  /// Duas frequências próximas alternadas rápido durante a rajada — é essa
  /// alternância (trinado) que dá o timbre de campainha mecânica, em vez de
  /// um tom eletrônico contínuo.
  static const _kRingLowHz = 900.0;
  static const _kRingHighHz = 1200.0;
  static const _kRingWarbleMs = 45;

  /// Toque de chamada sintetizado (sem precisar de nenhum arquivo de áudio)
  /// — toca tanto pra quem está ligando ("chamando...") quanto pra quem está
  /// recebendo ("chamada recebida"), dos dois lados.
  Future<void> _startRingtone() async {
    // ignore: avoid_print
    print('[call-debug] _startRingtone()');
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init();
    }
    final source = await SoLoud.instance.loadWaveform(
      WaveForm.triangle,
      false,
      0,
      0,
    );
    SoLoud.instance.setWaveformFreq(source, _kRingLowHz);
    _ringtoneSource = source;
    _ringtoneHandle = SoLoud.instance.play(source, looping: true);
    _ringtoneElapsedMs = 0;
    _ringtoneWarbleHigh = false;
    _ringtoneTimer = Timer.periodic(
      const Duration(milliseconds: _kRingWarbleMs),
      (_) => _onRingtoneTick(),
    );
  }

  void _onRingtoneTick() {
    final handle = _ringtoneHandle;
    final source = _ringtoneSource;
    if (handle == null || source == null) return;
    _ringtoneElapsedMs = (_ringtoneElapsedMs + _kRingWarbleMs) % _kRingCycleMs;
    final ringing = _ringtoneElapsedMs < _kRingBurstMs;
    SoLoud.instance.setPause(handle, !ringing);
    if (ringing) {
      _ringtoneWarbleHigh = !_ringtoneWarbleHigh;
      SoLoud.instance.setWaveformFreq(
        source,
        _ringtoneWarbleHigh ? _kRingHighHz : _kRingLowHz,
      );
    }
  }

  Future<void> _stopRingtone() async {
    // ignore: avoid_print
    print('[call-debug] _stopRingtone() handle=$_ringtoneHandle '
        'source=$_ringtoneSource');
    _ringtoneTimer?.cancel();
    _ringtoneTimer = null;
    final handle = _ringtoneHandle;
    _ringtoneHandle = null;
    if (handle != null) {
      await SoLoud.instance.stop(handle);
    }
    final source = _ringtoneSource;
    _ringtoneSource = null;
    if (source != null) {
      await SoLoud.instance.disposeSource(source);
    }
  }

  bool _audioPipelineStarting = false;

  /// Idempotente — chamado tanto ao iniciar/atender a chamada quanto (por
  /// segurança) ao ver o bit "ativo", mas só monta a captura/reprodução
  /// uma vez por chamada.
  Future<void> _ensureAudioPipeline(String publicKeyHex) async {
    if (_playbackSource != null || _audioPipelineStarting) return;
    _audioPipelineStarting = true;
    try {
      await _startAudio(publicKeyHex);
    } finally {
      _audioPipelineStarting = false;
    }
  }

  Future<void> _startAudio(String publicKeyHex) async {
    // ignore: avoid_print
    print('[call-debug] _startAudio($publicKeyHex)');
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init();
    }
    _playbackSource = SoLoud.instance.setBufferStream(
      sampleRate: _kSampleRate,
      channels: Channels.mono,
      format: BufferType.s16le,
      bufferingTimeNeeds: 0.05,
    );
    SoLoud.instance.play(_playbackSource!);
    // ignore: avoid_print
    print('[call-debug] playbackSource criado e tocando: $_playbackSource');

    final hasPermission = await _recorder.hasPermission();
    // ignore: avoid_print
    print('[call-debug] _recorder.hasPermission() = $hasPermission');
    if (!hasPermission) return;
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: _kChannels,
    ));
    // ignore: avoid_print
    print('[call-debug] _recorder.startStream() OK, escutando microfone');
    _micSubscription =
        stream.listen((chunk) => _onMicChunk(publicKeyHex, chunk));
  }

  /// Acumula os pedaços que o `record` entrega (tamanho irregular) até ter
  /// um frame exato de [_kFrameSamples] amostras antes de mandar — o
  /// `toxav_audio_send_frame` espera um `sample_count` preciso por chamada.
  int _micChunkCount = 0;
  int _framesSentCount = 0;

  void _onMicChunk(String publicKeyHex, Uint8List chunk) {
    _micChunkCount++;
    if (_micChunkCount % 25 == 1) {
      // ignore: avoid_print
      print('[call-debug] _onMicChunk #$_micChunkCount len=${chunk.length} '
          'muted=${state.muted} status=${state.status}');
    }
    if (state.muted || state.status == CallStatus.idle) return;
    _pendingMicBytes.addAll(chunk);
    final manager = ref.read(toxIsolateManagerProvider);
    while (_pendingMicBytes.length >= _kFrameBytes) {
      final frameBytes =
          Uint8List.fromList(_pendingMicBytes.sublist(0, _kFrameBytes));
      _pendingMicBytes.removeRange(0, _kFrameBytes);
      manager.sendCallAudioFrame(
          publicKeyHex, Int16List.sublistView(frameBytes));
      _framesSentCount++;
      if (_framesSentCount % 25 == 1) {
        // ignore: avoid_print
        print('[call-debug] sendCallAudioFrame #$_framesSentCount');
      }
    }
  }

  int _framesPlayedCount = 0;

  void _playReceivedFrame(Int16List samples) {
    final source = _playbackSource;
    if (source == null) {
      // ignore: avoid_print
      print('[call-debug] _playReceivedFrame: _playbackSource é null!');
      return;
    }
    // Áudio de verdade começou a chegar — o toque sintetizado (que ainda
    // toca enquanto isso, já que o toxav entrega o primeiro frame bem antes
    // do bit "ativo") não faz mais sentido tocar junto.
    if (_ringtoneHandle != null) {
      unawaited(_stopRingtone());
    }
    _framesPlayedCount++;
    if (_framesPlayedCount % 25 == 1) {
      // ignore: avoid_print
      print('[call-debug] _playReceivedFrame #$_framesPlayedCount '
          'samples=${samples.length}');
    }
    SoLoud.instance.addAudioDataStream(source, Uint8List.sublistView(samples));
  }

  Future<void> _stopAudio() async {
    await _micSubscription?.cancel();
    _micSubscription = null;
    _pendingMicBytes.clear();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    final source = _playbackSource;
    if (source != null) {
      SoLoud.instance.setDataIsEnded(source);
      await SoLoud.instance.disposeSource(source);
      _playbackSource = null;
    }
  }
}

final callProvider = NotifierProvider<CallNotifier, CallState>(
  CallNotifier.new,
);

/// Histórico de eventos de chamada ("chamando"/"encerrada") com um contato
/// específico — mesclado na timeline do chat (ver chat_screen.dart).
final callLogsForContactProvider =
    StreamProvider.family<List<CallLog>, String>((ref, publicKeyHex) {
  return ref.watch(callLogsRepositoryProvider).watchForContact(publicKeyHex);
});
