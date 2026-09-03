# Talksnap — build nativo do toxcore

Esta pasta compila a biblioteca C `toxcore` (e sua dependência `libsodium`)
do zero, sem baixar binários pré-compilados de terceiros. O resultado
(`toxcore.dll` no Windows) é o que `lib/tox_bindings.dart` carrega via
`dart:ffi`.

## Estrutura

```
native/
  CMakeLists.txt         # flags do Talksnap para o build do toxcore (sem ToxAV/bootstrap nesta fase)
  scripts/
    build_windows.ps1    # build completo para Windows (vcpkg + CMake)
  third_party/
    toxcore/              # git submodule -> TokTok/c-toxcore, pinado em v0.2.23
    vcpkg/                 # git submodule -> microsoft/vcpkg, pinado em 2026.07.29
                            # (usado só para compilar libsodium a partir do código-fonte)
  build/                  # saída do CMake (gerado, git-ignorado)
  output/<Config>/        # toxcore.dll + sodium.dll prontos para uso (gerado, git-ignorado)
```

## Pré-requisitos (na máquina onde o build roda)

- Visual Studio 2022 com a carga de trabalho **"Desenvolvimento para desktop com C++"**.
- CMake >= 3.21 no PATH.
- Git (para os submodules).

Nada disso é instalado pelo script — ele assume que já estão presentes.

## Primeira vez (clonando o repositório)

```powershell
git submodule update --init --recursive
```

## Compilando

```powershell
pwsh native/scripts/build_windows.ps1            # Debug (padrão)
pwsh native/scripts/build_windows.ps1 -Config Release
```

O script:
1. Faz bootstrap do vcpkg (`third_party/vcpkg`) na primeira execução.
2. Manda o vcpkg compilar `libsodium` a partir do código-fonte (triplet `x64-windows`).
3. Configura e compila `third_party/toxcore` via CMake, usando o toolchain
   do vcpkg para achar a libsodium recém-compilada, com as flags definidas
   em `native/CMakeLists.txt` (sem ToxAV, sem `DHT_bootstrap`/`tox-bootstrapd`
   — esses binários não são usados pelo app).
4. Copia `toxcore.dll` e `sodium.dll` para `native/output/<Config>/`.

## Integrando com o Flutter Windows

Este submódulo nativo é intencionalmente independente do projeto Flutter
(`windows/`), que ainda não existe neste repositório (é criado com
`flutter create .`, na Fase 0 do roadmap, quando o SDK Flutter estiver
disponível na máquina de desenvolvimento). Depois que o `windows/` existir:

1. Copie manualmente `native/output/<Config>/*.dll` para
   `build/windows/x64/runner/<Config>/` antes de rodar `flutter run -d windows`
   — **ou, preferível**, adicione um passo de `add_custom_command(... POST_BUILD ...)`
   em `windows/CMakeLists.txt` que copia os artefatos de `native/output/`
   automaticamente a cada build, para que `flutter run -d windows` sempre
   funcione sem passo manual.
2. Esse passo 1 (integração automática no `windows/CMakeLists.txt`) é o
   próximo item do roadmap depois que o projeto Flutter for criado.

## Atualizando as versões pinadas

As versões de `toxcore` e `vcpkg` são fixadas via submodule (não `main`
flutuante), para builds reprodutíveis:

```powershell
cd native/third_party/toxcore
git fetch --tags
git checkout <nova-tag>
cd ../../..
git add native/third_party/toxcore
git commit -m "chore: atualiza toxcore para <nova-tag>"
```

## Escalando para outras plataformas (fases futuras do roadmap)

- **Android**: `scripts/build_android.sh` (a criar) usando o NDK, gerando
  `libtoxcore.so` por ABI, copiado para `android/app/src/main/jniLibs/<abi>/`.
- **iOS/macOS**: compilar como biblioteca estática e empacotar num
  `.xcframework`, linkado direto no binário do app — `lib/tox_bindings.dart`
  já usa `DynamicLibrary.process()` nessas plataformas, então nenhuma
  mudança de código Dart é necessária.

Em nenhum desses casos `lib/tox_bindings.dart` muda — só a forma como o
binário nativo chega até o processo do app.
