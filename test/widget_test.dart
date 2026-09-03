// Testes unitários da lógica pura de tox_bindings.dart (conversão hex/bytes).
//
// Não testamos aqui a UI/isolate de rede: subir um ToxIsolateManager de
// verdade num teste automatizado exigiria a lib nativa toxcore.dll carregada
// e uma rede real disponível, o que foge do escopo de um teste unitário
// rápido. Ver native/README.md e o roadmap (Fase 8) para a estratégia de
// testes com duas instâncias locais.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:talksnap/tox_bindings.dart';

void main() {
  group('hexToBytes / bytesToHex', () {
    test('round-trip preserva os bytes originais', () {
      final original = Uint8List.fromList([0x00, 0x0F, 0xA5, 0xFF, 0x7E]);
      final hex = bytesToHex(original);
      final bytesBack = hexToBytes(hex);
      expect(bytesBack, equals(original));
    });

    test('bytesToHex produz sempre maiúsculas e com padding de 2 dígitos', () {
      final hex = bytesToHex(Uint8List.fromList([0x00, 0x0a, 0xff]));
      expect(hex, '000AFF');
    });

    test('hexToBytes aceita hex minúsculo ou maiúsculo', () {
      expect(hexToBytes('0a0AFf'), equals([0x0a, 0x0a, 0xff]));
    });
  });
}
