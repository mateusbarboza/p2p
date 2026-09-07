// toxav_bindings.dart
//
// Camada de mais baixo nível da chamada de voz: mapeia, via dart:ffi, as
// funções da API ToxAV (biblioteca C, embutida na MESMA toxcore.dll — ver
// native/CMakeLists.txt, BUILD_TOXAV=ON) para o mundo Dart.
//
// Segue exatamente o mesmo padrão de tox_bindings.dart (ToxCoreBindings):
// typedef Native/Dart por símbolo, `lookupFunction` em `_bind()`, wrapper
// que aloca o `error` out-param com `pkg_ffi.calloc`, checa o código e
// lança `StateError` se != 0, libera em `finally`. Fica num arquivo
// separado porque a ToxAV é uma API conceitualmente distinta (seu próprio
// tipo opaco `ToxAV*`, não confundir com o `Tox*`), embora resida na mesma
// DLL. Quem usa isso é `tox_isolate_manager.dart`.

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' as pkg_ffi;

// ToxAV *toxav_new(Tox *tox, Toxav_Err_New *error);
typedef _ToxavNewNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxavNewDart = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Void> tox,
  ffi.Pointer<ffi.Int32> error,
);

// void toxav_kill(ToxAV *av);
typedef _ToxavKillNative = ffi.Void Function(ffi.Pointer<ffi.Void> av);
typedef _ToxavKillDart = void Function(ffi.Pointer<ffi.Void> av);

// uint32_t toxav_iteration_interval(const ToxAV *av);
typedef _ToxavIterationIntervalNative = ffi.Uint32 Function(
    ffi.Pointer<ffi.Void> av);
typedef _ToxavIterationIntervalDart = int Function(ffi.Pointer<ffi.Void> av);

// void toxav_iterate(ToxAV *av);
typedef _ToxavIterateNative = ffi.Void Function(ffi.Pointer<ffi.Void> av);
typedef _ToxavIterateDart = void Function(ffi.Pointer<ffi.Void> av);

// bool toxav_call(ToxAV *av, uint32_t friend_number, uint32_t audio_bit_rate, uint32_t video_bit_rate, Toxav_Err_Call *error);
typedef _ToxavCallNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Uint32 audioBitRate,
  ffi.Uint32 videoBitRate,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxavCallDart = int Function(
  ffi.Pointer<ffi.Void> av,
  int friendNumber,
  int audioBitRate,
  int videoBitRate,
  ffi.Pointer<ffi.Int32> error,
);

// bool toxav_answer(ToxAV *av, uint32_t friend_number, uint32_t audio_bit_rate, uint32_t video_bit_rate, Toxav_Err_Answer *error);
typedef _ToxavAnswerNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Uint32 audioBitRate,
  ffi.Uint32 videoBitRate,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxavAnswerDart = int Function(
  ffi.Pointer<ffi.Void> av,
  int friendNumber,
  int audioBitRate,
  int videoBitRate,
  ffi.Pointer<ffi.Int32> error,
);

// bool toxav_call_control(ToxAV *av, uint32_t friend_number, Toxav_Call_Control control, Toxav_Err_Call_Control *error);
typedef _ToxavCallControlNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Int32 control,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxavCallControlDart = int Function(
  ffi.Pointer<ffi.Void> av,
  int friendNumber,
  int control,
  ffi.Pointer<ffi.Int32> error,
);

// bool toxav_audio_send_frame(ToxAV *av, uint32_t friend_number, const int16_t pcm[], size_t sample_count, uint8_t channels, uint32_t sampling_rate, Toxav_Err_Send_Frame *error);
typedef _ToxavAudioSendFrameNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Int16> pcm,
  ffi.Uint64 sampleCount,
  ffi.Uint8 channels,
  ffi.Uint32 samplingRate,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxavAudioSendFrameDart = int Function(
  ffi.Pointer<ffi.Void> av,
  int friendNumber,
  ffi.Pointer<ffi.Int16> pcm,
  int sampleCount,
  int channels,
  int samplingRate,
  ffi.Pointer<ffi.Int32> error,
);

// bool toxav_video_send_frame(ToxAV *av, uint32_t friend_number, uint16_t width, uint16_t height, const uint8_t y[], const uint8_t u[], const uint8_t v[], Toxav_Err_Send_Frame *error);
typedef _ToxavVideoSendFrameNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Uint16 width,
  ffi.Uint16 height,
  ffi.Pointer<ffi.Uint8> y,
  ffi.Pointer<ffi.Uint8> u,
  ffi.Pointer<ffi.Uint8> v,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxavVideoSendFrameDart = int Function(
  ffi.Pointer<ffi.Void> av,
  int friendNumber,
  int width,
  int height,
  ffi.Pointer<ffi.Uint8> y,
  ffi.Pointer<ffi.Uint8> u,
  ffi.Pointer<ffi.Uint8> v,
  ffi.Pointer<ffi.Int32> error,
);

// bool toxav_video_set_bit_rate(ToxAV *av, uint32_t friend_number, uint32_t bit_rate, Toxav_Err_Bit_Rate_Set *error);
typedef _ToxavVideoSetBitRateNative = ffi.Uint8 Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Uint32 bitRate,
  ffi.Pointer<ffi.Int32> error,
);
typedef _ToxavVideoSetBitRateDart = int Function(
  ffi.Pointer<ffi.Void> av,
  int friendNumber,
  int bitRate,
  ffi.Pointer<ffi.Int32> error,
);

// typedef void toxav_call_cb(ToxAV *av, uint32_t friend_number, bool audio_enabled, bool video_enabled, void *user_data);
typedef ToxAvCallCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Uint8 audioEnabled,
  ffi.Uint8 videoEnabled,
  ffi.Pointer<ffi.Void> userData,
);

// void toxav_callback_call(ToxAV *av, toxav_call_cb *callback, void *user_data);
typedef _ToxavCallbackCallNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Pointer<ffi.NativeFunction<ToxAvCallCallbackNative>> callback,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxavCallbackCallDart = void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Pointer<ffi.NativeFunction<ToxAvCallCallbackNative>> callback,
  ffi.Pointer<ffi.Void> userData,
);

// typedef void toxav_call_state_cb(ToxAV *av, uint32_t friend_number, uint32_t state, void *user_data);
typedef ToxAvCallStateCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Uint32 state,
  ffi.Pointer<ffi.Void> userData,
);

// void toxav_callback_call_state(ToxAV *av, toxav_call_state_cb *callback, void *user_data);
typedef _ToxavCallbackCallStateNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Pointer<ffi.NativeFunction<ToxAvCallStateCallbackNative>> callback,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxavCallbackCallStateDart = void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Pointer<ffi.NativeFunction<ToxAvCallStateCallbackNative>> callback,
  ffi.Pointer<ffi.Void> userData,
);

// typedef void toxav_audio_receive_frame_cb(ToxAV *av, uint32_t friend_number, const int16_t pcm[], size_t sample_count, uint8_t channels, uint32_t sampling_rate, void *user_data);
typedef ToxAvAudioReceiveFrameCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Pointer<ffi.Int16> pcm,
  ffi.Uint64 sampleCount,
  ffi.Uint8 channels,
  ffi.Uint32 samplingRate,
  ffi.Pointer<ffi.Void> userData,
);

// void toxav_callback_audio_receive_frame(ToxAV *av, toxav_audio_receive_frame_cb *callback, void *user_data);
typedef _ToxavCallbackAudioReceiveFrameNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Pointer<ffi.NativeFunction<ToxAvAudioReceiveFrameCallbackNative>>
      callback,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxavCallbackAudioReceiveFrameDart = void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Pointer<ffi.NativeFunction<ToxAvAudioReceiveFrameCallbackNative>>
      callback,
  ffi.Pointer<ffi.Void> userData,
);

// typedef void toxav_video_receive_frame_cb(ToxAV *av, uint32_t friend_number,
//     uint16_t width, uint16_t height, const uint8_t y[], const uint8_t u[],
//     const uint8_t v[], int32_t ystride, int32_t ustride, int32_t vstride,
//     void *user_data);
//
// Strides podem vir negativos (imagem de cabeça pra baixo) ou maiores que a
// dimensão da linha (padding) — quem trata isso é tox_isolate_manager.dart,
// nunca assumir que os planos são compactos.
typedef ToxAvVideoReceiveFrameCallbackNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Uint32 friendNumber,
  ffi.Uint16 width,
  ffi.Uint16 height,
  ffi.Pointer<ffi.Uint8> y,
  ffi.Pointer<ffi.Uint8> u,
  ffi.Pointer<ffi.Uint8> v,
  ffi.Int32 yStride,
  ffi.Int32 uStride,
  ffi.Int32 vStride,
  ffi.Pointer<ffi.Void> userData,
);

// void toxav_callback_video_receive_frame(ToxAV *av, toxav_video_receive_frame_cb *callback, void *user_data);
typedef _ToxavCallbackVideoReceiveFrameNative = ffi.Void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Pointer<ffi.NativeFunction<ToxAvVideoReceiveFrameCallbackNative>>
      callback,
  ffi.Pointer<ffi.Void> userData,
);
typedef _ToxavCallbackVideoReceiveFrameDart = void Function(
  ffi.Pointer<ffi.Void> av,
  ffi.Pointer<ffi.NativeFunction<ToxAvVideoReceiveFrameCallbackNative>>
      callback,
  ffi.Pointer<ffi.Void> userData,
);

/// Valores do enum `Toxav_Call_Control` usados pelo Talksnap (chamada de
/// voz só usa cancelar — silenciar o próprio microfone é feito só pelo
/// app, parando de mandar frames, sem chamar o nativo: `MUTE_AUDIO` no
/// toxcore pede pro CONTATO parar de mandar áudio pra nós, não o
/// contrário).
const int kToxavCallControlCancel = 2;

/// Bits do enum `Toxav_Friend_Call_State` usados pelo Talksnap.
///
/// IMPORTANTE, fácil de confundir: `SENDING_*` = o CONTATO está mandando
/// aquela mídia PRA NÓS; `ACCEPTING_*` = o CONTATO está aceitando RECEBER
/// aquela mídia DE NÓS (ou seja, reflete nosso próprio envio, não o dele).
/// Pra saber se tem vídeo do contato pra mostrar, o bit certo é
/// `SENDING_V`, não `ACCEPTING_V` (ver toxav.h).
const int kToxavFriendCallStateError = 1;
const int kToxavFriendCallStateFinished = 2;
const int kToxavFriendCallStateSendingV = 8;
const int kToxavFriendCallStateAcceptingA = 16;

/// Lançada por qualquer wrapper da ToxAV quando o código de erro nativo
/// vem diferente de zero (`*_OK`).
class ToxAvException implements Exception {
  const ToxAvException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Wrapper único e cacheado sobre a `DynamicLibrary` do toxcore (a ToxAV
/// mora na mesma DLL — ver native/CMakeLists.txt).
///
/// Uso: `ToxAvBindings.instance.toxavNew(...)`.
class ToxAvBindings {
  ToxAvBindings._internal(this._lib) {
    _bind();
  }

  static ToxAvBindings? _cachedInstance;

  static ToxAvBindings get instance {
    return _cachedInstance ??= ToxAvBindings._internal(_loadLibrary());
  }

  final ffi.DynamicLibrary _lib;

  late final _ToxavNewDart _toxavNew;
  late final _ToxavKillDart _toxavKill;
  late final _ToxavIterationIntervalDart _toxavIterationInterval;
  late final _ToxavIterateDart _toxavIterate;
  late final _ToxavCallDart _toxavCall;
  late final _ToxavAnswerDart _toxavAnswer;
  late final _ToxavCallControlDart _toxavCallControl;
  late final _ToxavAudioSendFrameDart _toxavAudioSendFrame;
  late final _ToxavVideoSendFrameDart _toxavVideoSendFrame;
  late final _ToxavVideoSetBitRateDart _toxavVideoSetBitRate;
  late final _ToxavCallbackCallDart _toxavCallbackCall;
  late final _ToxavCallbackCallStateDart _toxavCallbackCallState;
  late final _ToxavCallbackAudioReceiveFrameDart
      _toxavCallbackAudioReceiveFrame;
  late final _ToxavCallbackVideoReceiveFrameDart
      _toxavCallbackVideoReceiveFrame;

  /// Mesma DLL que `ToxCoreBindings` já carrega — abrir de novo pelo nome
  /// só pega outro handle pro módulo já residente no processo (o Windows
  /// não recarrega), então não duplica nada na memória.
  static ffi.DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('toxcore.dll');
    } else if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libtoxcore.so');
    } else if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libtoxcore.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      return ffi.DynamicLibrary.process();
    }
    throw UnsupportedError(
      'Plataforma não suportada pelo Talksnap: ${Platform.operatingSystem}',
    );
  }

  void _bind() {
    _toxavNew =
        _lib.lookupFunction<_ToxavNewNative, _ToxavNewDart>('toxav_new');
    _toxavKill =
        _lib.lookupFunction<_ToxavKillNative, _ToxavKillDart>('toxav_kill');
    _toxavIterationInterval = _lib.lookupFunction<_ToxavIterationIntervalNative,
        _ToxavIterationIntervalDart>('toxav_iteration_interval');
    _toxavIterate = _lib.lookupFunction<_ToxavIterateNative, _ToxavIterateDart>(
        'toxav_iterate');
    _toxavCall =
        _lib.lookupFunction<_ToxavCallNative, _ToxavCallDart>('toxav_call');
    _toxavAnswer = _lib
        .lookupFunction<_ToxavAnswerNative, _ToxavAnswerDart>('toxav_answer');
    _toxavCallControl =
        _lib.lookupFunction<_ToxavCallControlNative, _ToxavCallControlDart>(
            'toxav_call_control');
    _toxavAudioSendFrame = _lib.lookupFunction<_ToxavAudioSendFrameNative,
        _ToxavAudioSendFrameDart>('toxav_audio_send_frame');
    _toxavVideoSendFrame = _lib.lookupFunction<_ToxavVideoSendFrameNative,
        _ToxavVideoSendFrameDart>('toxav_video_send_frame');
    _toxavVideoSetBitRate = _lib.lookupFunction<_ToxavVideoSetBitRateNative,
        _ToxavVideoSetBitRateDart>('toxav_video_set_bit_rate');
    _toxavCallbackCall =
        _lib.lookupFunction<_ToxavCallbackCallNative, _ToxavCallbackCallDart>(
            'toxav_callback_call');
    _toxavCallbackCallState = _lib.lookupFunction<_ToxavCallbackCallStateNative,
        _ToxavCallbackCallStateDart>('toxav_callback_call_state');
    _toxavCallbackAudioReceiveFrame = _lib.lookupFunction<
            _ToxavCallbackAudioReceiveFrameNative,
            _ToxavCallbackAudioReceiveFrameDart>(
        'toxav_callback_audio_receive_frame');
    _toxavCallbackVideoReceiveFrame = _lib.lookupFunction<
            _ToxavCallbackVideoReceiveFrameNative,
            _ToxavCallbackVideoReceiveFrameDart>(
        'toxav_callback_video_receive_frame');
  }

  /// Cria a instância ToxAV associada a este `tox` — 1 por instância Tox,
  /// criada logo depois dele e destruída (ver [toxavKill]) antes dele.
  ffi.Pointer<ffi.Void> toxavNew(ffi.Pointer<ffi.Void> tox) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final av = _toxavNew(tox, errorPtr);
      final errorCode = errorPtr.value;
      if (errorCode != 0) {
        throw ToxAvException('toxav_new falhou com Toxav_Err_New = $errorCode');
      }
      return av;
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  void toxavKill(ffi.Pointer<ffi.Void> av) => _toxavKill(av);

  int toxavIterationInterval(ffi.Pointer<ffi.Void> av) =>
      _toxavIterationInterval(av);

  void toxavIterate(ffi.Pointer<ffi.Void> av) => _toxavIterate(av);

  /// Inicia uma chamada com um amigo já conectado — `videoBitRate` em 0
  /// (padrão) faz uma chamada só de voz, > 0 negocia vídeo também. Erros
  /// (ex: já existe uma chamada com ele) só lançam — quem chama decide o
  /// que fazer.
  void toxavCall(
    ffi.Pointer<ffi.Void> av,
    int friendNumber,
    int audioBitRate, {
    int videoBitRate = 0,
  }) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final ok =
          _toxavCall(av, friendNumber, audioBitRate, videoBitRate, errorPtr);
      final errorCode = errorPtr.value;
      if (ok == 0 || errorCode != 0) {
        throw ToxAvException(
            'toxav_call falhou com Toxav_Err_Call = $errorCode');
      }
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Atende uma chamada recebida — mesmo raciocínio de [toxavCall] pro
  /// `videoBitRate`.
  void toxavAnswer(
    ffi.Pointer<ffi.Void> av,
    int friendNumber,
    int audioBitRate, {
    int videoBitRate = 0,
  }) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final ok =
          _toxavAnswer(av, friendNumber, audioBitRate, videoBitRate, errorPtr);
      final errorCode = errorPtr.value;
      if (ok == 0 || errorCode != 0) {
        throw ToxAvException(
            'toxav_answer falhou com Toxav_Err_Answer = $errorCode');
      }
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Encerra/recusa uma chamada (`TOXAV_CALL_CONTROL_CANCEL`). Silencioso
  /// se a chamada já não existir mais — desligar duas vezes não é erro.
  void toxavCancelCall(ffi.Pointer<ffi.Void> av, int friendNumber) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      _toxavCallControl(av, friendNumber, kToxavCallControlCancel, errorPtr);
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Manda um frame de áudio PCM16 capturado do microfone (mono, 48kHz —
  /// ver call_provider.dart). Ignora erro (frame atrasado após a chamada
  /// já ter acabado é normal, não é uma condição excepcional).
  void toxavAudioSendFrame(
    ffi.Pointer<ffi.Void> av,
    int friendNumber,
    ffi.Pointer<ffi.Int16> pcm,
    int sampleCount,
    int channels,
    int samplingRate,
  ) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      _toxavAudioSendFrame(
          av, friendNumber, pcm, sampleCount, channels, samplingRate, errorPtr);
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Manda um frame de vídeo YUV420 planar (Y, depois U, depois V — ver
  /// call_provider.dart, que já entrega os 3 planos prontos vindo da
  /// conversão BGR->I420 do opencv_dart). Ignora erro pelo mesmo motivo de
  /// [toxavAudioSendFrame].
  void toxavVideoSendFrame(
    ffi.Pointer<ffi.Void> av,
    int friendNumber,
    int width,
    int height,
    ffi.Pointer<ffi.Uint8> y,
    ffi.Pointer<ffi.Uint8> u,
    ffi.Pointer<ffi.Uint8> v,
  ) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      _toxavVideoSendFrame(av, friendNumber, width, height, y, u, v, errorPtr);
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  /// Liga/desliga o canal de vídeo de uma chamada JÁ em andamento —
  /// necessário quando a chamada começou só de voz (`video_bit_rate = 0`
  /// em toxav_call/toxav_answer) e o vídeo é ligado depois, no meio dela
  /// (ver [CallNotifier.toggleVideo] em call_provider.dart): sem isso,
  /// `toxav_video_send_frame` não tem efeito — o toxav só transmite vídeo
  /// pra uma chamada que já negociou um bit rate de vídeo > 0. `bitRate =
  /// 0` desliga de novo.
  void toxavVideoSetBitRate(
      ffi.Pointer<ffi.Void> av, int friendNumber, int bitRate) {
    final errorPtr = pkg_ffi.calloc<ffi.Int32>();
    try {
      final ok = _toxavVideoSetBitRate(av, friendNumber, bitRate, errorPtr);
      final errorCode = errorPtr.value;
      if (ok == 0 || errorCode != 0) {
        throw ToxAvException(
            'toxav_video_set_bit_rate falhou com Toxav_Err_Bit_Rate_Set = '
            '$errorCode');
      }
    } finally {
      pkg_ffi.calloc.free(errorPtr);
    }
  }

  void setCallCallback(
    ffi.Pointer<ffi.Void> av,
    ffi.Pointer<ffi.NativeFunction<ToxAvCallCallbackNative>> callback,
  ) {
    _toxavCallbackCall(av, callback, ffi.nullptr);
  }

  void setCallStateCallback(
    ffi.Pointer<ffi.Void> av,
    ffi.Pointer<ffi.NativeFunction<ToxAvCallStateCallbackNative>> callback,
  ) {
    _toxavCallbackCallState(av, callback, ffi.nullptr);
  }

  void setAudioReceiveFrameCallback(
    ffi.Pointer<ffi.Void> av,
    ffi.Pointer<ffi.NativeFunction<ToxAvAudioReceiveFrameCallbackNative>>
        callback,
  ) {
    _toxavCallbackAudioReceiveFrame(av, callback, ffi.nullptr);
  }

  void setVideoReceiveFrameCallback(
    ffi.Pointer<ffi.Void> av,
    ffi.Pointer<ffi.NativeFunction<ToxAvVideoReceiveFrameCallbackNative>>
        callback,
  ) {
    _toxavCallbackVideoReceiveFrame(av, callback, ffi.nullptr);
  }
}
