// camera_capture_isolate.dart
//
// Captura da webcam (opencv_dart) rodando num Isolate dedicado, NUNCA na UI
// — motivo: `VideoCapture.read()`/`release()` são chamadas FFI síncronas e
// bloqueantes; se a câmera estiver disputada por outro processo (ex: dois
// processos do Talksnap testando na mesma máquina com uma webcam só) ou o
// driver travar, essa chamada pode nunca retornar. Isolando isso aqui, um
// travamento desses só prende ESTE isolate (uma thread OS a mais parada) —
// o isolate principal (UI, rede) continua respondendo normalmente, em vez
// do processo inteiro congelar e ficar impossível de fechar (foi isso que
// aconteceu antes desta mudança: dois processos de teste ficaram travados
// até pra `taskkill`/`Stop-Process -Force`, sinal de que a UI thread tinha
// travado dentro de uma chamada nativa).

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Um frame já convertido nos dois formatos que o resto do app precisa:
/// [yuvBytes] (I420 plano, pra `toxav_video_send_frame`) e [bgraBytes]
/// (pronto pra `ui.decodeImageFromPixels`, pro preview local).
class CameraFrameData {
  const CameraFrameData({
    required this.yuvBytes,
    required this.bgraBytes,
    required this.width,
    required this.height,
  });

  final Uint8List yuvBytes;
  final Uint8List bgraBytes;
  final int width;
  final int height;
}

class _CameraIsolateConfig {
  const _CameraIsolateConfig({
    required this.readySendPort,
    required this.width,
    required this.height,
    required this.captureInterval,
  });

  final SendPort readySendPort;
  final int width;
  final int height;
  final Duration captureInterval;
}

class _StopSignal {
  const _StopSignal();
}

/// Handle pro isolate de captura — uma instância por chamada com vídeo
/// ligado. [frames] emite um [CameraFrameData] por frame capturado (real ou
/// sintético, ver `_buildSyntheticFrame`); [stop] derruba o isolate.
class CameraCaptureIsolate {
  CameraCaptureIsolate._(this._isolate, this._commandPort, this._framePort);

  final Isolate _isolate;
  final SendPort _commandPort;
  final ReceivePort _framePort;

  Stream<CameraFrameData> get frames => _framePort.cast<CameraFrameData>();

  static Future<CameraCaptureIsolate?> start({
    required int width,
    required int height,
    required Duration captureInterval,
  }) async {
    final readyPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _cameraIsolateEntry,
      _CameraIsolateConfig(
        readySendPort: readyPort.sendPort,
        width: width,
        height: height,
        captureInterval: captureInterval,
      ),
    );
    final commandPort = await readyPort.first as SendPort;
    final framePort = ReceivePort();
    commandPort.send(framePort.sendPort);
    return CameraCaptureIsolate._(isolate, commandPort, framePort);
  }

  /// Pede pro isolate soltar a câmera e parar de capturar. Não espera a
  /// confirmação — se a chamada nativa de liberar a câmera travar (o
  /// próprio motivo de isolar isso), `kill` derruba o isolate mesmo assim
  /// assim que ele voltar a ser escalonável (não interrompe uma chamada
  /// nativa já em andamento, mas garante que este isolate nunca mais
  /// escalona depois disso, sem afetar o resto do app).
  void stop() {
    _commandPort.send(const _StopSignal());
    _framePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _cameraIsolateEntry(_CameraIsolateConfig config) {
  final commandPort = ReceivePort();
  config.readySendPort.send(commandPort.sendPort);

  cv.VideoCapture? camera;
  Timer? timer;
  int consecutiveFailures = 0;
  int syntheticTick = 0;

  void stopCapture() {
    timer?.cancel();
    timer = null;
    try {
      camera?.release();
      camera?.dispose();
    } catch (_) {
      // Se travar/der erro ao soltar, não tem mais nada a fazer por aqui —
      // o isolate inteiro vai ser derrubado por fora (ver [stop]).
    }
    camera = null;
  }

  commandPort.listen((message) {
    if (message is _StopSignal) {
      stopCapture();
      return;
    }
    if (message is! SendPort) return;
    final framePort = message;

    try {
      final cam = cv.VideoCapture.fromDevice(0);
      if (!cam.isOpened) {
        cam.dispose();
        return;
      }
      camera = cam;
    } catch (_) {
      return;
    }

    timer = Timer.periodic(config.captureInterval, (_) {
      final cam = camera;
      if (cam == null) return;

      cv.Mat resized;
      final (ok, frame) = cam.read();
      if (!ok || frame.isEmpty) {
        frame.dispose();
        consecutiveFailures++;
        // Depois de umas poucas falhas seguidas, a câmera provavelmente
        // está ocupada por outro processo — manda um padrão sintético em
        // vez de simplesmente não mandar nada (ver call_provider.dart).
        if (consecutiveFailures < 5) return;
        resized =
            _buildSyntheticFrame(config.width, config.height, syntheticTick++);
      } else {
        consecutiveFailures = 0;
        resized = frame.rows == config.height && frame.cols == config.width
            ? frame
            : cv.resize(frame, (config.width, config.height));
        if (!identical(resized, frame)) frame.dispose();
      }

      final yuv = cv.cvtColor(resized, cv.COLOR_BGR2YUV_I420);
      final bgra = cv.cvtColor(resized, cv.COLOR_BGR2BGRA);
      framePort.send(CameraFrameData(
        yuvBytes: Uint8List.fromList(yuv.data),
        bgraBytes: Uint8List.fromList(bgra.data),
        width: config.width,
        height: config.height,
      ));
      yuv.dispose();
      bgra.dispose();
      resized.dispose();
    });
  });
}

/// Padrão sintético (fundo cinza + um círculo colorido girando) — usado
/// quando a webcam de verdade não responde depois de várias tentativas.
cv.Mat _buildSyntheticFrame(int width, int height, int tick) {
  final mat = cv.Mat.create(
    rows: height,
    cols: width,
    type: cv.MatType.CV_8UC3,
    r: 60,
    g: 60,
    b: 60,
  );
  final angle = (tick * 0.15) % (2 * math.pi);
  final cx = width / 2 + (width / 3) * math.cos(angle);
  final cy = height / 2 + (height / 3) * math.sin(angle);
  cv.circle(
    mat,
    cv.Point(cx.round(), cy.round()),
    20,
    cv.Scalar(60, 200, 255),
    thickness: -1,
  );
  return mat;
}
