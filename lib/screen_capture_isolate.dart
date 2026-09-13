// screen_capture_isolate.dart
//
// Captura de tela (GDI clássico via `win32`) rodando num Isolate dedicado —
// mesmo motivo de `camera_capture_isolate.dart`: `BitBlt`/`GetDIBits` são
// chamadas FFI síncronas e potencialmente bloqueantes; isolar isso evita que
// um travamento congele o app inteiro.
//
// Compartilhamento de tela é, do ponto de vista do ToxAV, só OUTRA FONTE de
// frame de vídeo — `toxav_video_send_frame` não sabe se o frame veio da
// webcam ou da tela. Por isso este arquivo produz o mesmo formato de saída
// que `camera_capture_isolate.dart` (YUV420 pra enviar, BGRA pro preview
// local), só a captura em si é diferente.
//
// Caminho clássico de captura de tela no Windows: BitBlt copia o conteúdo
// da tela pra um bitmap compatível em memória, GetDIBits extrai os pixels
// crus desse bitmap pra um buffer. Pede DIB de 32 bits por pixel (BGRA) em
// vez de 24 — assim cada pixel já fica alinhado em 4 bytes, sem padding de
// linha pra tratar (só compartilha o monitor primário nesta versão).

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:win32/win32.dart';

/// Mesmo shape de `CameraFrameData` (ver camera_capture_isolate.dart) —
/// classe própria, não reaproveitada, pra não confundir "frame de câmera"
/// com "frame de tela" ao ler o código.
class ScreenFrameData {
  const ScreenFrameData({
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

class _ScreenIsolateConfig {
  const _ScreenIsolateConfig({
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

/// Handle pro isolate de captura de tela — mesma API pública de
/// `CameraCaptureIsolate`: `start()` estático, `frames` stream, `stop()`.
class ScreenCaptureIsolate {
  ScreenCaptureIsolate._(this._isolate, this._commandPort, this._framePort);

  final Isolate _isolate;
  final SendPort _commandPort;
  final ReceivePort _framePort;

  Stream<ScreenFrameData> get frames => _framePort.cast<ScreenFrameData>();

  static Future<ScreenCaptureIsolate?> start({
    required int width,
    required int height,
    required Duration captureInterval,
  }) async {
    final readyPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _screenIsolateEntry,
      _ScreenIsolateConfig(
        readySendPort: readyPort.sendPort,
        width: width,
        height: height,
        captureInterval: captureInterval,
      ),
    );
    final commandPort = await readyPort.first as SendPort;
    final framePort = ReceivePort();
    commandPort.send(framePort.sendPort);
    return ScreenCaptureIsolate._(isolate, commandPort, framePort);
  }

  /// Mesmo raciocínio de `CameraCaptureIsolate.stop()`: não espera a
  /// confirmação (soltar os handles GDI pode travar), `kill` garante que
  /// o isolate nunca mais escalona depois disso de qualquer forma.
  void stop() {
    _commandPort.send(const _StopSignal());
    _framePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _screenIsolateEntry(_ScreenIsolateConfig config) {
  final commandPort = ReceivePort();
  config.readySendPort.send(commandPort.sendPort);

  Timer? timer;
  int screenWidth = 0;
  int screenHeight = 0;
  HDC? hdcScreen;
  HDC? hdcMem;
  HBITMAP? hBitmap;
  ffi.Pointer<BITMAPINFO>? bmi;
  ffi.Pointer<ffi.Uint8>? pixelBuffer;
  int pixelBufferSize = 0;

  void stopCapture() {
    timer?.cancel();
    timer = null;
    try {
      if (hBitmap != null) DeleteObject(HGDIOBJ(hBitmap!));
      if (hdcMem != null) DeleteDC(hdcMem!);
      if (hdcScreen != null) ReleaseDC(null, hdcScreen!);
      if (pixelBuffer != null) pkg_ffi.calloc.free(pixelBuffer!);
      if (bmi != null) pkg_ffi.calloc.free(bmi!);
    } catch (_) {
      // Se travar/der erro ao soltar, não tem mais nada a fazer por aqui —
      // o isolate inteiro vai ser derrubado por fora (ver [ScreenCaptureIsolate.stop]).
    }
    hdcScreen = null;
    hdcMem = null;
    hBitmap = null;
    bmi = null;
    pixelBuffer = null;
  }

  commandPort.listen((message) {
    if (message is _StopSignal) {
      stopCapture();
      return;
    }
    if (message is! SendPort) return;
    final framePort = message;

    try {
      screenWidth = GetSystemMetrics(SM_CXSCREEN);
      screenHeight = GetSystemMetrics(SM_CYSCREEN);
      final screen = GetDC(null);
      final mem = CreateCompatibleDC(screen);
      final bitmap = CreateCompatibleBitmap(screen, screenWidth, screenHeight);
      SelectObject(mem, HGDIOBJ(bitmap));
      hdcScreen = screen;
      hdcMem = mem;
      hBitmap = bitmap;

      // 32bpp (BGRA) — cada pixel já alinhado em 4 bytes, sem padding de
      // linha pra tratar. `biHeight` negativo pede um DIB "top-down" (sem
      // precisar inverter as linhas manualmente depois).
      final info = pkg_ffi.calloc<BITMAPINFO>();
      info.ref.bmiHeader
        ..biSize = ffi.sizeOf<BITMAPINFOHEADER>()
        ..biWidth = screenWidth
        ..biHeight = -screenHeight
        ..biPlanes = 1
        ..biBitCount = 32
        ..biCompression = BI_RGB;
      bmi = info;

      pixelBufferSize = screenWidth * screenHeight * 4;
      pixelBuffer = pkg_ffi.calloc<ffi.Uint8>(pixelBufferSize);
    } catch (_) {
      stopCapture();
      return;
    }

    timer = Timer.periodic(config.captureInterval, (_) {
      final screen = hdcScreen;
      final mem = hdcMem;
      final bitmap = hBitmap;
      final info = bmi;
      final buffer = pixelBuffer;
      if (screen == null || mem == null || bitmap == null) return;
      if (info == null || buffer == null) return;

      BitBlt(mem, 0, 0, screenWidth, screenHeight, screen, 0, 0, SRCCOPY);
      GetDIBits(
        mem,
        bitmap,
        0,
        screenHeight,
        buffer.cast(),
        info,
        DIB_RGB_COLORS,
      );

      final rawMat = cv.Mat.create(
        rows: screenHeight,
        cols: screenWidth,
        type: cv.MatType.CV_8UC4,
      );
      rawMat.data
          .setRange(0, pixelBufferSize, buffer.asTypedList(pixelBufferSize));
      final bgrMat = cv.cvtColor(rawMat, cv.COLOR_BGRA2BGR);
      rawMat.dispose();

      final resized =
          bgrMat.rows == config.height && bgrMat.cols == config.width
              ? bgrMat
              : cv.resize(bgrMat, (config.width, config.height));
      if (!identical(resized, bgrMat)) bgrMat.dispose();

      final yuv = cv.cvtColor(resized, cv.COLOR_BGR2YUV_I420);
      final bgra = cv.cvtColor(resized, cv.COLOR_BGR2BGRA);
      framePort.send(ScreenFrameData(
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
