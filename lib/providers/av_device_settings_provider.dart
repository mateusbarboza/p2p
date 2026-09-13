// av_device_settings_provider.dart
//
// Preferência de qual microfone/câmera usar em chamadas de voz/vídeo e
// mensagens de voz, persistida localmente (mesmo padrão de
// spell_check_provider.dart). Antes disso o app sempre usava o microfone
// padrão do Windows e a câmera de índice 0 — hardcoded em call_provider.dart/
// chat_screen.dart (áudio) e camera_capture_isolate.dart (vídeo).
//
// Câmera é só um ÍNDICE (0, 1, 2...), não um dispositivo nomeado: o
// opencv_dart (usado pra captura de vídeo) não expõe enumeração de câmeras
// com nome amigável no Windows, só abre por índice numérico
// (`cv.VideoCapture.fromDevice(index)`) — ver camera_capture_isolate.dart.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kMicIdPrefsKey = 'talksnap.microphoneDeviceId';
const String _kMicLabelPrefsKey = 'talksnap.microphoneDeviceLabel';
const String _kCameraIndexPrefsKey = 'talksnap.cameraIndex';

class AvDeviceSettings {
  const AvDeviceSettings({this.microphone, this.cameraIndex = 0});

  /// `null` = microfone padrão do sistema (comportamento de sempre).
  final InputDevice? microphone;
  final int cameraIndex;

  AvDeviceSettings copyWith({
    InputDevice? Function()? microphone,
    int? cameraIndex,
  }) {
    return AvDeviceSettings(
      microphone: microphone != null ? microphone() : this.microphone,
      cameraIndex: cameraIndex ?? this.cameraIndex,
    );
  }
}

class AvDeviceSettingsNotifier extends Notifier<AvDeviceSettings> {
  @override
  AvDeviceSettings build() {
    _load();
    return const AvDeviceSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final micId = prefs.getString(_kMicIdPrefsKey);
    final micLabel = prefs.getString(_kMicLabelPrefsKey);
    final cameraIndex = prefs.getInt(_kCameraIndexPrefsKey) ?? 0;
    state = AvDeviceSettings(
      microphone: micId != null
          ? InputDevice(id: micId, label: micLabel ?? micId)
          : null,
      cameraIndex: cameraIndex,
    );
  }

  Future<void> setMicrophone(InputDevice? device) async {
    state = state.copyWith(microphone: () => device);
    final prefs = await SharedPreferences.getInstance();
    if (device == null) {
      await prefs.remove(_kMicIdPrefsKey);
      await prefs.remove(_kMicLabelPrefsKey);
    } else {
      await prefs.setString(_kMicIdPrefsKey, device.id);
      await prefs.setString(_kMicLabelPrefsKey, device.label);
    }
  }

  Future<void> setCameraIndex(int index) async {
    state = state.copyWith(cameraIndex: index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCameraIndexPrefsKey, index);
  }
}

final avDeviceSettingsProvider =
    NotifierProvider<AvDeviceSettingsNotifier, AvDeviceSettings>(
  AvDeviceSettingsNotifier.new,
);
