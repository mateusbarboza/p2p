🇺🇸 [Read in English](README.md)

# Talksnap

Talksnap é um mensageiro P2P descentralizado (Flutter + [toxcore](https://github.com/TokTok/c-toxcore) via `dart:ffi`) — totalmente peer-to-peer e privado, sem servidores centrais.

## Funcionalidades

- **Identidade P2P persistente (Tox)** — sem servidor central, sem "recuperar conta". Sua identidade pode ser exportada (arquivo `.tox`) e importada em outro dispositivo (Perfil > Segurança).
- **Múltiplas contas locais** no mesmo dispositivo, cada uma atrás de seu próprio usuário/senha local, com identidade/banco/contatos totalmente separados.
- **Mensagens de texto 1:1** com confirmação de entrega e fila offline (mensagens são reenviadas automaticamente assim que o contato reconecta).
- **Chat em grupo (NGC)**: crie grupos, convide contatos existentes, roster persistido entre reinícios. Limitação conhecida: um grupo fica inacessível se todos os membros ficarem offline ao mesmo tempo — é uma limitação da biblioteca nativa toxcore, não do app, e já é avisada dentro do próprio app.
- **Transferência de arquivos** com preview de imagem, abrir/baixar, e aceite automático opcional com limite de tamanho configurável.
- **Mensagens de voz** (grave e toque direto no chat).
- **Chamadas de voz e vídeo** (ToxAV), com mudo e liga/desliga de câmera.
- **Compartilhamento de tela** durante a chamada (mutuamente exclusivo com a câmera — só uma fonte de vídeo por vez).
- **Escolha de microfone/câmera** em Configurações.
- **Presença/status** (online/ausente/ocupado) e indicador de "digitando".
- **Notificação nativa** do desktop para mensagens novas.
- **Verificação ortográfica** opcional no campo de mensagem.
- **Tema claro/escuro/sistema**.
- **Localização completa da interface**: inglês, espanhol, português, chinês, japonês, alemão, francês — trocável em tempo real em Perfil > Configurações.
- **Verificação de atualização** dentro do app contra os Releases do GitHub, com botão "Atualizar" que abre a página do release.

## Downloads

Instaladores Windows já compilados são publicados na [página de Releases](https://github.com/mateusbarboza/p2p/releases) (`TalksnapSetup-<versão>.exe`). Só Windows por enquanto — sem build Android/iOS/macOS ainda.

## Rodando a partir do código-fonte

Pré-requisitos: Flutter SDK, Visual Studio 2022 (workload "Desenvolvimento para desktop com C++"), CMake ≥ 3.21.

```powershell
git submodule update --init --recursive
pwsh native/scripts/build_windows.ps1 -Config Release
flutter pub get
flutter run -d windows --release
```

Veja `native/README.md` para detalhes do build nativo (toxcore/libsodium/opus/libvpx via vcpkg) e como ele se integra ao runner do Flutter Windows.

Para testar localmente com duas identidades distintas na mesma máquina (sem precisar de um segundo dispositivo), rode duas cópias do executável com a variável de ambiente `TALKSNAP_PROFILE` diferente em cada uma (ex: `alice` e `bob`) — cada perfil usa seu próprio savedata e banco de dados.
