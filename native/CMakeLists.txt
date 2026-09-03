# native/CMakeLists.txt
#
# Orquestra a compilação da biblioteca nativa toxcore usada pelo Talksnap
# (consumida via dart:ffi em lib/tox_bindings.dart).
#
# Este projeto NÃO reimplementa nada do toxcore — ele apenas configura as
# flags corretas do CMakeLists.txt oficial (em third_party/toxcore) para
# gerar só o que o Talksnap precisa nesta fase: a libtoxcore compartilhada
# (toxcore.dll no Windows), sem ToxAV e sem os binários de bootstrap node
# (esses recursos entram em fases futuras do roadmap).
#
# libsodium (dependência obrigatória do toxcore) é obtida via vcpkg
# (third_party/vcpkg), que a compila a partir do código-fonte no manifesto
# do próprio vcpkg — nada de binário pré-compilado de terceiros.

cmake_minimum_required(VERSION 3.21)
project(talksnap_native C)

# --- Flags específicas do Talksnap para o build do toxcore -------------------
# (definidas ANTES do add_subdirectory para que o CMakeLists.txt do toxcore
# as leia como cache variables já setadas)

set(BUILD_TOXAV OFF CACHE BOOL "Talksnap fase 0: ToxAV entra só na Fase 9" FORCE)
set(MUST_BUILD_TOXAV OFF CACHE BOOL "" FORCE)
set(DHT_BOOTSTRAP OFF CACHE BOOL "Talksnap não precisa do binário DHT_bootstrap" FORCE)
set(BOOTSTRAP_DAEMON OFF CACHE BOOL "Talksnap não precisa do tox-bootstrapd" FORCE)
set(UNITTEST OFF CACHE BOOL "" FORCE)
set(AUTOTEST OFF CACHE BOOL "" FORCE)

# Queremos a lib compartilhada (toxcore.dll) para o dart:ffi carregar via
# DynamicLibrary.open — a estática não é usada nesta plataforma.
set(ENABLE_SHARED ON CACHE BOOL "" FORCE)
set(ENABLE_STATIC OFF CACHE BOOL "" FORCE)

if(MSVC)
  # No Windows, o vcpkg (triplet padrão x64-windows) gera uma sodium.dll
  # dinâmica; então NÃO linkamos sodium estaticamente aqui.
  set(MSVC_STATIC_SODIUM OFF CACHE BOOL "" FORCE)
endif()

add_subdirectory(third_party/toxcore toxcore_build)

# O MSVC, ao contrario do GCC/Clang no Linux, nao exporta simbolos de uma DLL
# automaticamente, e o toxcore nao usa dllexport/.def para marcar sua API
# publica. Sem isso, tox_new/tox_iterate/etc. ficam invisiveis para o
# dart:ffi (DynamicLibrary.lookupFunction falha com "symbol not found"),
# mesmo com o toxcore.dll carregando normalmente. WINDOWS_EXPORT_ALL_SYMBOLS
# manda o CMake gerar as exportacoes automaticamente para todos os simbolos.
if(MSVC AND TARGET toxcore_shared)
  set_target_properties(toxcore_shared PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
endif()
