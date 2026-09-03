# Talksnap

Mensageiro P2P descentralizado (Flutter + [toxcore](https://github.com/TokTok/c-toxcore) via `dart:ffi`), focado em recuperar a experiência nostálgica de mensageiros como o MSN — mas 100% P2P e privado, sem servidores.

## Status

Fases 0–6 do roadmap implementadas e validadas localmente (ver `native/README.md` e `docs/manual_testing.md`):

- Fundação nativa: toxcore compilado do zero (CMake + vcpkg) para Windows.
- Identidade persistente + conectividade real com a rede Tox.
- Gestão de amigos (pedidos, aceitar, remover).
- Persistência estruturada (Drift): contatos, mensagens, transferências de arquivo.
- Mensagens de texto 1:1 com histórico e confirmação de entrega.
- Transferência de arquivos com prévia de imagem, abrir e baixar.
- Perfil (nome, descrição, foto local) sincronizado via toxcore.
- Layout mestre-detalhe (contatos à esquerda, conversa à direita).

Ainda não testado em rede real entre duas máquinas físicas (Fase 6 tem o checklist pronto, falta rodar com um segundo dispositivo).

## Rodando localmente

Pré-requisitos: Flutter SDK, Visual Studio 2022 (workload "Desenvolvimento para desktop com C++"), CMake ≥ 3.21.

```powershell
git submodule update --init --recursive
pwsh native/scripts/build_windows.ps1
flutter pub get
flutter run -d windows
```

Veja `native/README.md` para detalhes do build nativo (toxcore/libsodium via vcpkg) e como ele se integra ao runner do Flutter Windows.

Para testar localmente com duas identidades distintas na mesma máquina (sem precisar de um segundo dispositivo), rode duas cópias do executável com a variável de ambiente `TALKSNAP_PROFILE` diferente em cada uma (ex: `alice` e `bob`) — cada perfil usa seu próprio savedata e banco de dados.

## Próximos passos

Ver o roadmap completo nas fases 7 (Android), 8 (iOS/macOS) e 9 (chamadas de voz/vídeo via ToxAV).
