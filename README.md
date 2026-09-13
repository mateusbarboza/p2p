🇧🇷 [Ler em português](README.pt-BR.md)

# Talksnap

Talksnap is a decentralized P2P messenger (Flutter + [toxcore](https://github.com/TokTok/c-toxcore) via `dart:ffi`) — fully peer-to-peer and private, with no central servers.

## Features

- **Persistent P2P identity (Tox)** — no central server, no "recover account". Your identity can be backed up/exported (`.tox` file) and imported on another device (Profile > Security).
- **Multiple local accounts** on the same device, each behind its own local username/password lock, with fully separate identity/database/contacts.
- **1:1 text messaging** with delivery confirmation and offline queueing (messages are automatically resent once the contact reconnects).
- **Group chats (NGC)**: create groups, invite existing contacts, roster persisted across restarts. Known limitation: a group becomes unreachable if every member goes offline at the same time — this is a native toxcore limitation, not app-level, and is already surfaced in-app.
- **File transfer** with image preview, open/download, and an optional auto-accept setting with a configurable max size.
- **Voice messages** (record and play back directly in the chat).
- **Voice and video calls** (ToxAV), with mute and camera toggle.
- **Screen sharing** during a call (mutually exclusive with the camera — only one video source at a time).
- **Selectable microphone/camera** device in Settings.
- **Presence/status** (online/away/busy) and typing indicator.
- **Native desktop notifications** for new messages.
- **Spell check** toggle for the message input.
- **Light/Dark/System theme**.
- **Full UI localization**: English, Spanish, Portuguese, Chinese, Japanese, German, French — switchable live from Profile > Settings.
- **In-app update checker** against GitHub Releases, with an "Update" button that opens the release page.

## Downloads

Prebuilt Windows installers are published on the [Releases page](https://github.com/mateusbarboza/p2p/releases) (`TalksnapSetup-<version>.exe`). Windows only for now — no Android/iOS/macOS build yet.

## Running from source

Prerequisites: Flutter SDK, Visual Studio 2022 (workload "Desktop development with C++"), CMake ≥ 3.21.

```powershell
git submodule update --init --recursive
pwsh native/scripts/build_windows.ps1 -Config Release
flutter pub get
flutter run -d windows --release
```

See `native/README.md` for native build details (toxcore/libsodium/opus/libvpx via vcpkg) and how it integrates with the Flutter Windows runner.

To test locally with two distinct identities on the same machine (without needing a second device), run two copies of the executable with a different `TALKSNAP_PROFILE` environment variable in each (e.g. `alice` and `bob`) — each profile uses its own savedata and database.
