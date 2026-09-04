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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

import '../data/database.dart' show CallLog;
import '../tox_events.dart';
import 'database_provider.dart';
import 'tox_events_provider.dart';
import 'tox_manager_provider.dart';

enum CallStatus { idle, outgoingRinging, incomingRinging, active }

class CallState {
  const CallState({
    this.status = CallStatus.idle,
    this.contactPublicKeyHex,
    this.muted = false,
    this.outgoing = false,
  });

  final CallStatus status;
  final String? contactPublicKeyHex;
  final bool muted;

  /// `true` se fomos nós que ligamos pro contato, `false` se foi ele que
  /// ligou — usado só pra saber como registrar o evento em [CallLogs].
  final bool outgoing;

  CallState copyWith({CallStatus? status, bool? muted}) {
    return CallState(
      status: status ?? this.status,
      contactPublicKeyHex: contactPublicKeyHex,
      muted: muted ?? this.muted,
      outgoing: outgoing,
    );
  }
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
  /// loop enquanto a chamada está chamando/tocando, dos dois lados.
  AudioSource? _ringtoneSource;
  SoundHandle? _ringtoneHandle;

  @override
  CallState build() {
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData(_handleEvent);
    });
    ref.onDispose(() {
      unawaited(_stopRingtone());
      unawaited(_stopAudio());
      unawaited(_recorder.dispose());
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
        unawaited(_logCall(event.publicKeyHex,
            outgoing: state.outgoing, kind: 'ended'));
        state = const CallState();
      } else if (event.active && state.status != CallStatus.active) {
        unawaited(_stopRingtone());
        state = state.copyWith(status: CallStatus.active);
        // _ensureAudioPipeline já deve ter rodado (ver [answer]/[startCall]
        // — o toxav começa a entregar frames de áudio de verdade bem antes
        // desse bit "ativo" aparecer, então não dá pra esperar até aqui).
        unawaited(_ensureAudioPipeline(event.publicKeyHex));
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
    }
  }

  /// Liga (voz) pra um contato — o estado só avança pra [CallStatus.active]
  /// quando o [ToxCallStateEvent] correspondente chegar (ele atendeu).
  void startCall(String publicKeyHex) {
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
    ref.read(toxIsolateManagerProvider).startCall(publicKeyHex);
  }

  /// Atende a chamada que está tocando (ver [CallStatus.incomingRinging]).
  void answer() {
    final publicKeyHex = state.contactPublicKeyHex;
    if (publicKeyHex == null || state.status != CallStatus.incomingRinging) {
      return;
    }
    unawaited(_ensureAudioPipeline(publicKeyHex));
    ref.read(toxIsolateManagerProvider).answerCall(publicKeyHex);
  }

  /// Encerra ou recusa a chamada atual, seja ela tocando ou já ativa.
  void hangUp() {
    final publicKeyHex = state.contactPublicKeyHex;
    if (publicKeyHex == null) return;
    ref.read(toxIsolateManagerProvider).hangUp(publicKeyHex);
    unawaited(_stopRingtone());
    unawaited(_stopAudio());
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

  /// Toque de chamada sintetizado (tom senoidal em loop) — toca tanto pra
  /// quem está ligando ("chamando...") quanto pra quem está recebendo
  /// ("chamada recebida"), sem precisar embutir nenhum arquivo de áudio.
  Future<void> _startRingtone() async {
    // ignore: avoid_print
    print('[call-debug] _startRingtone()');
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init();
    }
    final source = await SoLoud.instance.loadWaveform(
      WaveForm.sin,
      false,
      0,
      0,
    );
    SoLoud.instance.setWaveformFreq(source, 440);
    _ringtoneSource = source;
    _ringtoneHandle = SoLoud.instance.play(source, looping: true);
  }

  Future<void> _stopRingtone() async {
    // ignore: avoid_print
    print('[call-debug] _stopRingtone() handle=$_ringtoneHandle '
        'source=$_ringtoneSource');
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
