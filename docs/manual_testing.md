# Talksnap — checklist de teste manual (Fase 6: rede real / NAT-to-NAT)

Tudo que foi construído até a Fase 5 foi validado com duas instâncias do
app **na mesma máquina** (perfis `alice`/`bob` via `TALKSNAP_PROFILE`,
conectando por loopback). Isso prova que a lógica funciona, mas não prova
que o Talksnap atravessa NAT/firewall de verdade — para isso, precisa de
duas máquinas em **redes diferentes**.

## Pré-requisitos

- Duas máquinas Windows, cada uma numa rede diferente (ex: uma no Wi-Fi de
  casa, outra usando o hotspot do celular/4G — o importante é que fiquem
  atrás de roteadores/NATs diferentes, não basta estar em cômodos
  diferentes da mesma rede).
- Cada máquina precisa do ambiente de build completo (Flutter, CMake,
  Visual Studio) ou pelo menos do executável já compilado
  (`build\windows\x64\runner\Debug\talksnap.exe` + as DLLs de
  `native\output\Debug\`) copiado para lá.
- Nenhuma variável `TALKSNAP_PROFILE` setada nas duas (cada máquina já tem
  sua própria identidade naturalmente, por ter seu próprio perfil de
  usuário/diretório de dados).

## Passo a passo

1. **Conectividade básica**
   - Abra o Talksnap nas duas máquinas.
   - Confirme que o badge de status fica verde ("Online (P2P direto)") ou
     laranja/"Online (via relay)" em algum momento nos primeiros ~30s.
   - Se ficar preso em "Conectando..." por mais de 1 minuto: a Fase 6 já
     adicionou nova tentativa de bootstrap a cada 15s enquanto
     desconectado (ver `_kBootstrapRetryInterval` em
     `lib/tox_isolate_manager.dart`) — se mesmo assim não conectar, o
     firewall da rede provavelmente está bloqueando UDP de saída na porta
     usada pelos nós de bootstrap (33445). Tente uma rede diferente (ex:
     hotspot do celular) para isolar o problema.

2. **Pedido de amizade**
   - Copie o Talksnap ID de uma máquina, cole na outra e envie o pedido.
   - Confirme que o pedido aparece na outra máquina e que aceitar funciona.
   - Anote quanto tempo levou — em loopback isso é quase instantâneo; em
     rede real, esperar alguns segundos é normal.

3. **Mensagens**
   - Troque mensagens nos dois sentidos.
   - Feche e reabra o app numa das máquinas — confirme que o histórico
     continua lá.

4. **Transferência de arquivo**
   - Envie um arquivo pequeno (< 1 MB) primeiro. Confirme que a barra de
     progresso avança e termina com "Recebido".
   - Repita com um arquivo maior (ex: 20-50 MB) para observar se a
     conexão aguenta throughput sustentado sem travar a UI (a rede
     continua respondendo, badge de status não deveria oscilar
     estranhamente durante a transferência).
   - Teste "Abrir" e "Baixar" no arquivo recebido.

5. **Fallback para relay (TCP)**
   - Se possível, teste numa rede corporativa/restrita (bloqueia UDP) para
     forçar o badge a mostrar "Online (via relay)" em vez de "P2P
     direto" — confirma que o fallback do toxcore está funcionando, não só
     o caminho feliz de P2P direto.

## O que anotar se algo falhar

- Qual badge de status apareceu (e depois de quanto tempo).
- Se a rede era doméstica, corporativa, ou dado móvel.
- Se havia VPN ativa em alguma das máquinas (VPNs às vezes bloqueiam ou
  redirecionam tráfego UDP de forma que atrapalha o Tox).
- Logs do console (`flutter run -d windows`, se disponível) no momento da
  falha.

Esses dados ajudam a decidir se o ajuste necessário é na lista de nós de
bootstrap (`lib/tox_bindings.dart`), no intervalo de nova tentativa
(`lib/tox_isolate_manager.dart`), ou se é uma limitação de rede fora do
controle do app.

## Limitação conhecida — Grupos não sobrevivem a reiniciar o app

Criar grupo, convidar, aceitar convite, mensagens e lista de membros
funcionam perfeitamente **enquanto o app permanece aberto**. Porém, ao
fechar e reabrir o app (em qualquer um dos lados), o grupo desaparece do
lado do toxcore — mesmo que a linha ainda apareça na lista da UI por um
instante (ela vem do banco local via `Groups`/`GroupMembers`, que não sabe
que o grupo sumiu do lado nativo).

Isolado via teste direto: criar um grupo, aguardar até 18s (inclusive após
um segundo peer entrar de verdade), e recarregar o `savedata` retornado por
`tox_get_savedata()` numa instância `Tox*` de teste na mesma sessão (sem
nem fechar o app) — `tox_group_get_group_list` volta vazio nesse
round-trip. Ou seja, a versão do toxcore atualmente pinada em
`native/third_party/toxcore` não está persistindo o estado de grupos NGC no
savedata, independente de tempo de espera ou de outro peer já ter entrado.
Isso não é um bug do código do Talksnap — é uma limitação/bug da biblioteca
nativa nessa versão.

Decisão registrada (2026-09-03): aceitar a limitação por enquanto. Grupos
continuam existindo apenas durante a sessão atual do app; ao reabrir, é
preciso criar/juntar-se ao grupo de novo. Se algum dia quiser revisitar,
o próximo passo seria tentar atualizar o submódulo `toxcore` para uma
versão mais nova e repetir esse mesmo teste de round-trip antes de investir
mais tempo em qualquer outro lugar.

## Chamada de voz (ToxAV)

Pré-requisito: rebuild nativo depois de puxar essa mudança (`native/scripts/
build_windows.ps1`) — sem isso `toxcore.dll` não tem os símbolos `toxav_*`
e o app falha ao subir a chamada. Confirme `opus.dll` em
`native/output/<Config>/` (o `libvpx` costuma linkar estático, então não
gera um `.dll` próprio — isso é esperado).

Teste com `TALKSNAP_PROFILE=teste1`/`teste2` (duas instâncias já amigas):

1. teste1 abre a conversa com teste2 e clica no ícone de telefone na
   barra superior — teste2 deve receber um diálogo "Chamada de [nome]"
   com Atender/Recusar.
2. teste2 clica em Atender — nos dois lados aparece a barra "Em chamada"
   com o botão de mudo e de desligar.
3. Fala num microfone de um lado e confirma que o áudio sai no
   alto-falante/fone do outro lado (e vice-versa).
4. Clica no ícone de mudo de um lado — confirma que o outro lado para de
   ouvir esse áudio (mas continua ouvindo o próprio, já que o mudo só
   afeta o que VOCÊ manda).
5. Desliga de qualquer um dos lados — a barra de chamada some dos dois
   lados.
6. Repete o passo 1, mas dessa vez teste1 (quem ligou) desliga antes de
   teste2 atender — confirma que o diálogo de "chamada recebida" em
   teste2 fecha sozinho, sem precisar clicar em nada.
