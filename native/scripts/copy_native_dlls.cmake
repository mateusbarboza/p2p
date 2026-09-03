# copy_native_dlls.cmake
#
# Copia as DLLs nativas (toxcore.dll + dependencias como libsodium.dll,
# pthreadVC3(d).dll) de native/output/<Config>/ para a pasta do executavel
# do runner do Flutter Windows, apos cada build.
#
# Chamado via `cmake -P` a partir de windows/runner/CMakeLists.txt, com
# -DSRC_DIR=... e -DDEST_DIR=... Se native/output/<Config> ainda nao existe
# (ex: build nativo daquela configuracao ainda nao foi rodado), avisa em vez
# de falhar o build inteiro do Flutter.

if(NOT DEFINED SRC_DIR OR NOT DEFINED DEST_DIR)
    message(FATAL_ERROR "Uso: cmake -DSRC_DIR=... -DDEST_DIR=... -P copy_native_dlls.cmake")
endif()

if(EXISTS "${SRC_DIR}")
    file(GLOB NATIVE_DLLS "${SRC_DIR}/*.dll")
    if(NATIVE_DLLS)
        file(COPY ${NATIVE_DLLS} DESTINATION "${DEST_DIR}")
        message(STATUS "Talksnap: copiadas DLLs nativas de ${SRC_DIR} para ${DEST_DIR}")
    else()
        message(WARNING "Talksnap: ${SRC_DIR} existe mas nao tem nenhum .dll.")
    endif()
else()
    message(WARNING
        "Talksnap: ${SRC_DIR} nao existe ainda. Rode "
        "native/scripts/build_windows.ps1 (com -Config correspondente) antes "
        "de rodar o app, senao ele vai falhar ao carregar o toxcore.dll.")
endif()
