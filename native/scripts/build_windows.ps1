# build_windows.ps1
#
# Compila a toolchain nativa do Talksnap para Windows, do zero:
#   1) vcpkg (submodule) compila libsodium, pthreads, opus e libvpx a
#      partir do codigo-fonte (opus/libvpx sao as dependencias do ToxAV,
#      usado para chamada de voz).
#   2) CMake configura e compila o toxcore (submodule) como toxcore.dll
#      (com ToxAV embutido), linkado contra essas libs, usando as flags
#      definidas em native/CMakeLists.txt (sem bootstrap daemon).
#   3) Os artefatos (toxcore.dll + sodium.dll + opus.dll + vpx.dll) sao
#      copiados para native/output/<Config>/ prontos para serem usados
#      pelo runner do Flutter Windows.
#
# Pre-requisitos na maquina de quem roda este script (nao instalados por
# ele): Visual Studio 2022 com a carga de trabalho "Desenvolvimento para
# desktop com C++", e CMake >= 3.21 no PATH.
#
# Uso:
#   powershell native/scripts/build_windows.ps1
#   powershell native/scripts/build_windows.ps1 -Config Release
#
# Nota: os comentarios deste arquivo evitam acentos/caracteres especiais de
# proposito. O Windows PowerShell 5.1 le .ps1 sem BOM usando a codepage
# ANSI do sistema, e caracteres UTF-8 multibyte (acentos, travessao "-")
# podem ser mal interpretados e quebrar o parser (erro de string sem
# terminador). Mantenha este arquivo em ASCII puro.

[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Config = "Debug"
)

$ErrorActionPreference = "Stop"

$NativeDir = Split-Path -Parent $PSScriptRoot
$VcpkgDir = Join-Path $NativeDir "third_party\vcpkg"
$ToxcoreDir = Join-Path $NativeDir "third_party\toxcore"
$BuildDir = Join-Path $NativeDir "build"
$OutputDir = Join-Path $NativeDir "output\$Config"
$Triplet = "x64-windows"

function Assert-Tool($Name, $Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "'$Name' nao encontrado no PATH. $Hint"
    }
}

Write-Host "==> Verificando pre-requisitos..." -ForegroundColor Cyan
Assert-Tool "cmake" "Instale o CMake (https://cmake.org/download) e adicione ao PATH."
Assert-Tool "git" "Necessario para os submodules (toxcore/vcpkg)."

if (-not (Test-Path (Join-Path $ToxcoreDir "CMakeLists.txt"))) {
    throw "Submodule toxcore vazio. Rode: git submodule update --init --recursive"
}
if (-not (Test-Path (Join-Path $VcpkgDir "bootstrap-vcpkg.bat"))) {
    throw "Submodule vcpkg vazio. Rode: git submodule update --init --recursive"
}

# --- 1) Bootstrap do vcpkg + libsodium -------------------------------------
$VcpkgExe = Join-Path $VcpkgDir "vcpkg.exe"
if (-not (Test-Path $VcpkgExe)) {
    Write-Host "==> Fazendo bootstrap do vcpkg (primeira vez)..." -ForegroundColor Cyan
    & (Join-Path $VcpkgDir "bootstrap-vcpkg.bat") -disableMetrics
    if ($LASTEXITCODE -ne 0) { throw "Falha ao inicializar o vcpkg." }
}

Write-Host "==> Compilando libsodium, pthreads, opus e libvpx via vcpkg (triplet $Triplet)..." -ForegroundColor Cyan
# pthreads: o toxcore usa a API POSIX de threads (pthread.h) mesmo no
# Windows/MSVC, entao precisa dessa implementacao (pthreads4w) para compilar.
# opus/libvpx: dependencias do ToxAV (chamada de voz) -- o CMakeLists.txt do
# toxcore exige as duas para habilitar BUILD_TOXAV, mesmo so usando audio.
& $VcpkgExe install "libsodium:$Triplet" "pthreads:$Triplet" "opus:$Triplet" "libvpx:$Triplet"
if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar libsodium/pthreads/opus/libvpx via vcpkg." }

# --- 2) Configura e compila o toxcore com CMake ----------------------------
$ToolchainFile = Join-Path $VcpkgDir "scripts\buildsystems\vcpkg.cmake"

Write-Host "==> Configurando CMake ($Config)..." -ForegroundColor Cyan
cmake -S $NativeDir -B $BuildDir `
    -A x64 `
    "-DCMAKE_TOOLCHAIN_FILE=$ToolchainFile" `
    "-DVCPKG_TARGET_TRIPLET=$Triplet"
if ($LASTEXITCODE -ne 0) { throw "Falha ao configurar o CMake do toxcore." }

Write-Host "==> Compilando toxcore ($Config)..." -ForegroundColor Cyan
cmake --build $BuildDir --config $Config --target toxcore_shared
if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar o toxcore." }

# --- 3) Coleta os artefatos -------------------------------------------------
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$ToxcoreDll = Get-ChildItem -Path $BuildDir -Recurse -Filter "toxcore.dll" |
    Where-Object { $_.FullName -match [regex]::Escape($Config) } |
    Select-Object -First 1
if (-not $ToxcoreDll) {
    $ToxcoreDll = Get-ChildItem -Path $BuildDir -Recurse -Filter "toxcore.dll" | Select-Object -First 1
}
if (-not $ToxcoreDll) { throw "toxcore.dll nao foi encontrado apos o build. Verifique o log acima." }

# O MSBuild/vcpkg ja copia automaticamente (deploy "applocal") as DLLs de
# dependencia (libsodium.dll, pthreadVC3(d).dll, opus.dll, vpx.dll) para a
# mesma pasta do toxcore.dll. Copiamos a pasta inteira em vez de
# caçar nomes de arquivo especificos, para não quebrar quando novas
# dependencias nativas forem adicionadas (ex: ToxAV na Fase 9).
Copy-Item "$($ToxcoreDll.DirectoryName)\*.dll" -Destination $OutputDir -Force

Write-Host ""
Write-Host "==> Build concluido. Artefatos em:" -ForegroundColor Green
Write-Host "    $OutputDir"
Get-ChildItem $OutputDir | ForEach-Object { Write-Host "    - $($_.Name)" }
Write-Host ""
Write-Host "Proximo passo: copiar esses arquivos para perto do executavel do" -ForegroundColor Yellow
Write-Host "Flutter Windows (ex: build\windows\x64\runner\$Config\) ou rodar" -ForegroundColor Yellow
Write-Host "'flutter create .' na raiz do projeto e integrar uma copia automatica" -ForegroundColor Yellow
Write-Host "no windows\CMakeLists.txt do runner (ver native\README.md)." -ForegroundColor Yellow
