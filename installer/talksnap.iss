; talksnap.iss
;
; Script do Inno Setup pro instalador do Talksnap (Windows).
;
; Pré-requisito: rodar `flutter build windows --release` ANTES de compilar
; este script — ele empacota o conteúdo já pronto de
; build\windows\x64\runner\Release\ (exe + todas as DLLs nativas + a pasta
; data\ com os assets Flutter), não builda o app sozinho.
;
; Como compilar:
;   "C:\Users\mateu\AppData\Local\Programs\Inno Setup 6\ISCC.exe" installer\talksnap.iss
; O instalador final sai em installer\output\TalksnapSetup-<versão>.exe.
;
; AppId fixo (gerado uma vez, não mudar) — é o que o Windows usa pra saber
; que uma instalação nova é uma ATUALIZAÇÃO da mesma anterior, em vez de um
; programa diferente instalado do lado.
#define AppId "{{E8618B1E-2A3D-4C3A-9FED-C25994B63F9E}"
#define AppName "Talksnap"
#define AppVersion "0.2.0"
#define AppPublisher "Talksnap"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=TalksnapSetup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\talksnap.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Só usuários com permissão de admin (padrão) — evita pedir elevação toda
; hora depois, já que instala em Program Files.
PrivilegesRequired=admin

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar um atalho na Área de Trabalho"; GroupDescription: "Atalhos adicionais:"; Flags: unchecked

[Files]
; Todo o conteúdo do build de Release (exe, DLLs nativas, pasta data\ com
; os assets Flutter) — recursivo, pega tudo sem listar arquivo por arquivo.
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\talksnap.exe"
Name: "{group}\Desinstalar {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\talksnap.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\talksnap.exe"; Description: "Abrir o {#AppName} agora"; Flags: nowait postinstall skipifsilent
