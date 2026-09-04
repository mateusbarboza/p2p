// tox_events.dart
//
// Vocabulario de mensagens trocadas entre o isolate de rede (tox_isolate_manager)
// e a UI. Modelado como duas hierarquias `sealed class` (Dart 3) em vez de um
// unico objeto "status" genérico:
//
//   - ToxNetworkEvent: isolate de rede -> UI (o que aconteceu na rede)
//   - ToxNetworkCommand: UI -> isolate de rede (o que a UI pediu para fazer)
//
// `sealed class` + `switch` exaustivo garante, em tempo de compilacao, que
// novo tipo de evento/comando adicionado em fase futura (mensagens, arquivos,
// chamadas) nao passa despercebido em algum consumidor.

import 'dart:typed_data' show Int16List, Uint8List;

import 'tox_bindings.dart' show ToxConnection;

// ---------------------------------------------------------------------------
// Eventos: isolate de rede -> UI
// ---------------------------------------------------------------------------

sealed class ToxNetworkEvent {
  const ToxNetworkEvent();
}

/// Status da propria instancia: conexao global com a rede e/ou o Talksnap ID
/// (enviado uma unica vez, quando a identidade e criada/restaurada).
class ToxSelfStatusEvent extends ToxNetworkEvent {
  const ToxSelfStatusEvent({required this.connection, this.talksnapId});

  final ToxConnection connection;
  final String? talksnapId;
}

/// Nome e mensagem de status do próprio perfil — enviado no boot (lendo o
/// que já estava salvo no savedata) e de novo sempre que SetProfileCommand
/// é aplicado com sucesso. [userStatus] é o presença escolhido manualmente
/// (Online/Ausente/Ocupado — ver kToxUserStatus* em tox_bindings.dart),
/// diferente da conectividade de rede em [ToxSelfStatusEvent].
class ToxSelfProfileEvent extends ToxNetworkEvent {
  const ToxSelfProfileEvent({
    required this.name,
    required this.statusMessage,
    required this.userStatus,
  });

  final String name;
  final String statusMessage;
  final int userStatus;
}

/// Nome/status de um amigo (o que ELE definiu no perfil dele) — enviado no
/// boot para cada amigo salvo, e de novo quando ele muda algo (ver
/// tox_callback_friend_name/tox_callback_friend_status_message).
class ToxFriendProfileEvent extends ToxNetworkEvent {
  const ToxFriendProfileEvent({
    required this.publicKeyHex,
    required this.name,
    required this.statusMessage,
    required this.userStatus,
  });

  final String publicKeyHex;
  final String name;
  final String statusMessage;

  /// Presença que ELE escolheu (Online/Ausente/Ocupado — kToxUserStatus*),
  /// diferente da conectividade de rede ([ToxFriendConnectionEvent]).
  final int userStatus;
}

/// Confirma que o savedata foi gravado no disco após um
/// [FlushSavedataCommand] — a UI pode então ler o arquivo com segurança.
class ToxSavedataFlushedEvent extends ToxNetworkEvent {
  const ToxSavedataFlushedEvent();
}

/// Alguem enviou um pedido de amizade para o nosso Talksnap ID.
class ToxFriendRequestEvent extends ToxNetworkEvent {
  const ToxFriendRequestEvent(
      {required this.publicKeyHex, required this.message});

  final String publicKeyHex;
  final String message;
}

/// Mudanca de status de conexao de um amigo especifico (ou o estado inicial,
/// enviado logo apos o boot para cada amigo ja salvo no savedata).
class ToxFriendConnectionEvent extends ToxNetworkEvent {
  const ToxFriendConnectionEvent({
    required this.friendNumber,
    required this.publicKeyHex,
    required this.connection,
  });

  final int friendNumber;
  final String publicKeyHex;
  final ToxConnection connection;
}

/// Um amigo começou ou parou de digitar uma mensagem pra nós (`tox_callback_
/// friend_typing`) — só ao vivo, nunca persistido (não faz sentido guardar
/// "estava digitando" no histórico).
class ToxFriendTypingEvent extends ToxNetworkEvent {
  const ToxFriendTypingEvent({
    required this.publicKeyHex,
    required this.isTyping,
  });

  final String publicKeyHex;
  final bool isTyping;
}

/// Um contato está nos ligando (`toxav_callback_call`) — só áudio nesta
/// fase, então nem carrega `audioEnabled`/`videoEnabled` (sempre tratamos
/// como pedido de chamada de voz).
class ToxCallIncomingEvent extends ToxNetworkEvent {
  const ToxCallIncomingEvent({required this.publicKeyHex});
  final String publicKeyHex;
}

/// Mudança de estado de uma chamada em andamento (`toxav_callback_call_
/// state`) — já traduzido do bitmask `Toxav_Friend_Call_State` pros dois
/// bools que a UI precisa: `active` (chamada realmente conectada, trocando
/// áudio) e `ended` (encerrada, por qualquer motivo — recusada, caiu,
/// desligada pelo outro lado).
class ToxCallStateEvent extends ToxNetworkEvent {
  const ToxCallStateEvent({
    required this.publicKeyHex,
    required this.active,
    required this.ended,
  });

  final String publicKeyHex;
  final bool active;
  final bool ended;
}

/// Um frame de áudio decodificado chegou de um contato em chamada
/// (`toxav_callback_audio_receive_frame`) — pronto pra tocar, o toxav já
/// cuidou do Opus por dentro. Mono, 48kHz (ver call_provider.dart).
class ToxCallAudioFrameEvent extends ToxNetworkEvent {
  const ToxCallAudioFrameEvent({
    required this.publicKeyHex,
    required this.samples,
  });

  final String publicKeyHex;
  final Int16List samples;
}

/// Resultado de um AddFriendCommand/AcceptFriendRequestCommand: sucesso (com
/// o friend_number atribuido) ou falha (com uma mensagem legivel).
class ToxFriendAddResultEvent extends ToxNetworkEvent {
  const ToxFriendAddResultEvent.success(this.friendNumber)
      : success = true,
        errorMessage = null;

  const ToxFriendAddResultEvent.failure(this.errorMessage)
      : success = false,
        friendNumber = null;

  final bool success;
  final int? friendNumber;
  final String? errorMessage;
}

/// Um amigo foi removido com sucesso (resultado de RemoveFriendCommand).
class ToxFriendRemovedEvent extends ToxNetworkEvent {
  const ToxFriendRemovedEvent(
      {required this.friendNumber, required this.publicKeyHex});
  final int friendNumber;
  final String publicKeyHex;
}

/// Uma mensagem de texto foi recebida de um amigo.
class ToxFriendMessageEvent extends ToxNetworkEvent {
  const ToxFriendMessageEvent({
    required this.publicKeyHex,
    required this.message,
    required this.receivedAt,
  });

  final String publicKeyHex;
  final String message;
  final DateTime receivedAt;
}

/// Resultado de um SendMessageCommand: sucesso (com o `message_id` local,
/// usado para casar com [ToxMessageReadReceiptEvent]) ou falha (ex: amigo
/// offline no momento do envio).
class ToxMessageSentEvent extends ToxNetworkEvent {
  const ToxMessageSentEvent.success({
    required this.publicKeyHex,
    required this.message,
    required this.toxMessageId,
    required this.sentAt,
  })  : success = true,
        errorMessage = null,
        notConnected = false;

  const ToxMessageSentEvent.failure({
    required this.publicKeyHex,
    required this.message,
    required this.errorMessage,
    this.notConnected = false,
  })  : success = false,
        toxMessageId = null,
        sentAt = null;

  final bool success;
  final String publicKeyHex;
  final String message;
  final int? toxMessageId;
  final DateTime? sentAt;
  final String? errorMessage;

  /// `true` quando a falha foi especificamente por o contato estar offline
  /// no momento do envio (`TOX_ERR_FRIEND_SEND_MESSAGE_FRIEND_NOT_CONNECTED`)
  /// — nesse caso a mensagem já foi salva como pendente e será reenviada
  /// sozinha quando ele conectar, então a UI não deve tratar como erro real.
  final bool notConnected;
}

/// Uma mensagem enviada por nós foi confirmada como entregue ao amigo.
class ToxMessageReadReceiptEvent extends ToxNetworkEvent {
  const ToxMessageReadReceiptEvent(
      {required this.publicKeyHex, required this.toxMessageId});
  final String publicKeyHex;
  final int toxMessageId;
}

/// Estágio de uma transferência de arquivo. Usado tanto no evento ao vivo
/// quanto como status persistido na tabela `FileTransfers` (ver
/// lib/data/database.dart) — os dois contextos compartilham exatamente o
/// mesmo vocabulário, então reutilizar o enum evita duas fontes de verdade.
enum ToxFileTransferPhase { requested, progress, completed, cancelled, failed }

/// Progresso/estado de uma transferência de arquivo, em qualquer direção.
/// `fileNumber` é `null` só no caso raro de falha antes do toxcore atribuir
/// um número (ex: amigo não encontrado) — nesse caso não há nada para
/// persistir, é só feedback efêmero de UI.
class ToxFileTransferEvent extends ToxNetworkEvent {
  const ToxFileTransferEvent({
    required this.publicKeyHex,
    required this.fileNumber,
    required this.phase,
    required this.outgoing,
    this.fileName,
    this.totalBytes,
    this.bytesTransferred,
    this.savedPath,
    this.errorMessage,
  });

  final String publicKeyHex;
  final int? fileNumber;
  final ToxFileTransferPhase phase;
  final bool outgoing;
  final String? fileName;
  final int? totalBytes;
  final int? bytesTransferred;

  /// Caminho local final do arquivo recebido (só preenchido quando
  /// `phase == completed` e `outgoing == false`).
  final String? savedPath;
  final String? errorMessage;
}

// ---------------------------------------------------------------------------
// Grupos (NGC). A chave estável entre execuções é o Chat ID (32 bytes hex,
// via chatIdHex) — group_number é efêmero por sessão, igual friend_number,
// e nunca é usado fora do isolate de rede.
// ---------------------------------------------------------------------------

/// Um grupo foi criado por nós (`tox_group_new`). O toxcore não dispara
/// `group_self_join` para quem cria — este evento cobre esse caso.
class ToxGroupCreatedEvent extends ToxNetworkEvent {
  const ToxGroupCreatedEvent({
    required this.chatIdHex,
    required this.name,
    required this.isFounder,
  });
  final String chatIdHex;
  final String name;

  /// Se somos o fundador do grupo — usado pela UI para mostrar "Excluir
  /// grupo" (fundador) em vez de "Sair do grupo" (demais membros). Não
  /// muda o comportamento por baixo: um grupo P2P sem servidor não tem
  /// "apagar para todos", só "sair" — ambos chamam LeaveGroupCommand.
  final bool isFounder;
}

/// Entramos num grupo com sucesso — seja aceitando um convite, seja (no
/// boot) reconectando a um grupo já salvo no savedata.
class ToxGroupSelfJoinedEvent extends ToxNetworkEvent {
  const ToxGroupSelfJoinedEvent({
    required this.chatIdHex,
    required this.name,
    required this.isFounder,
  });
  final String chatIdHex;
  final String name;
  final bool isFounder;
}

/// Falha ao tentar entrar num grupo (convite ruim, senha errada, grupo
/// cheio, etc.).
class ToxGroupJoinFailedEvent extends ToxNetworkEvent {
  const ToxGroupJoinFailedEvent({required this.reason});
  final String reason;
}

/// Um amigo nos convidou para um grupo. `inviteData` deve ser guardado como
/// veio e reenviado sem modificação em [AcceptGroupInviteCommand].
class ToxGroupInviteEvent extends ToxNetworkEvent {
  const ToxGroupInviteEvent({
    required this.fromPublicKeyHex,
    required this.groupName,
    required this.inviteData,
  });
  final String fromPublicKeyHex;
  final String groupName;
  final Uint8List inviteData;
}

/// Mensagem de texto recebida num grupo.
class ToxGroupMessageEvent extends ToxNetworkEvent {
  const ToxGroupMessageEvent({
    required this.chatIdHex,
    required this.peerId,
    required this.senderName,
    required this.message,
    required this.receivedAt,
  });
  final String chatIdHex;
  final int peerId;
  final String senderName;
  final String message;
  final DateTime receivedAt;
}

/// Resultado de um SendGroupMessageCommand — espelha [ToxMessageSentEvent].
class ToxGroupMessageSentEvent extends ToxNetworkEvent {
  const ToxGroupMessageSentEvent.success({
    required this.chatIdHex,
    required this.message,
    required this.sentAt,
  })  : success = true,
        errorMessage = null;

  const ToxGroupMessageSentEvent.failure({
    required this.chatIdHex,
    required this.message,
    required this.errorMessage,
  })  : success = false,
        sentAt = null;

  final bool success;
  final String chatIdHex;
  final String message;
  final DateTime? sentAt;
  final String? errorMessage;
}

/// Um peer (que não somos nós) entrou no grupo.
class ToxGroupPeerJoinedEvent extends ToxNetworkEvent {
  const ToxGroupPeerJoinedEvent({
    required this.chatIdHex,
    required this.peerId,
    required this.peerName,
    required this.connection,
    required this.publicKeyHex,
  });
  final String chatIdHex;
  final int peerId;
  final String peerName;
  final ToxConnection connection;

  /// Chave pública estável do peer — usada para casar com um contato já
  /// existente (ex: para não oferecer convidar de novo quem já é membro).
  /// `null` se o toxcore não conseguiu fornecê-la.
  final String? publicKeyHex;
}

/// Um peer saiu/foi desconectado do grupo.
class ToxGroupPeerLeftEvent extends ToxNetworkEvent {
  const ToxGroupPeerLeftEvent({
    required this.chatIdHex,
    required this.peerId,
    required this.peerName,
  });
  final String chatIdHex;
  final int peerId;
  final String peerName;
}

/// Um convite de grupo foi enviado com sucesso a um contato (resultado de
/// [InviteToGroupCommand]) — usado para não oferecer convidar de novo o
/// mesmo contato. Não dá pra confirmar de fato a entrada dele comparando
/// chaves: o toxcore identifica peers DENTRO de um grupo com uma chave
/// própria daquele grupo (por design de privacidade do NGC), diferente da
/// chave pública do amigo — então "convite enviado" é o sinal prático mais
/// próximo disponível do lado de quem convida.
class ToxGroupInviteSentEvent extends ToxNetworkEvent {
  const ToxGroupInviteSentEvent({
    required this.chatIdHex,
    required this.contactPublicKeyHex,
  });
  final String chatIdHex;
  final String contactPublicKeyHex;
}

/// Saímos de um grupo com sucesso (resultado de [LeaveGroupCommand]) —
/// usado para remover a linha correspondente da lista local (ver
/// GroupsRepository.delete).
class ToxGroupLeftEvent extends ToxNetworkEvent {
  const ToxGroupLeftEvent({required this.chatIdHex});
  final String chatIdHex;
}

/// Um peer mudou o próprio apelido dentro do grupo.
class ToxGroupPeerNameEvent extends ToxNetworkEvent {
  const ToxGroupPeerNameEvent({
    required this.chatIdHex,
    required this.peerId,
    required this.peerName,
  });
  final String chatIdHex;
  final int peerId;
  final String peerName;
}

// ---------------------------------------------------------------------------
// Comandos: UI -> isolate de rede
// ---------------------------------------------------------------------------

sealed class ToxNetworkCommand {
  const ToxNetworkCommand();
}

/// Encerra o loop de rede e libera a instancia Tox.
class StopCommand extends ToxNetworkCommand {
  const StopCommand();
}

/// Envia um pedido de amizade para o Talksnap ID informado.
class AddFriendCommand extends ToxNetworkCommand {
  const AddFriendCommand({required this.talksnapId, required this.message});

  final String talksnapId;
  final String message;
}

/// Aceita um pedido de amizade recebido (identificado pela chave publica de
/// quem pediu), adicionando-o de volta sem exigir novo convite.
class AcceptFriendRequestCommand extends ToxNetworkCommand {
  const AcceptFriendRequestCommand({required this.publicKeyHex});

  final String publicKeyHex;
}

/// Remove um amigo existente, identificado pela chave pública (estável) —
/// não pelo friend_number (efêmero por sessão), que a UI/banco de dados
/// nunca precisam conhecer.
class RemoveFriendCommand extends ToxNetworkCommand {
  const RemoveFriendCommand({required this.publicKeyHex});

  final String publicKeyHex;
}

/// Envia uma mensagem de texto para um contato (identificado pela chave
/// pública). O isolate resolve o friend_number efêmero internamente.
class SendMessageCommand extends ToxNetworkCommand {
  const SendMessageCommand({required this.publicKeyHex, required this.message});

  final String publicKeyHex;
  final String message;
}

/// Avisa um contato que estamos (ou paramos de) digitar uma mensagem pra
/// ele — chamado a cada tecla digitada no campo de mensagem (com debounce
/// na UI) e ao limpar o campo/enviar.
class SetTypingCommand extends ToxNetworkCommand {
  const SetTypingCommand({required this.publicKeyHex, required this.isTyping});

  final String publicKeyHex;
  final bool isTyping;
}

/// Liga (voz, sem vídeo) para um contato já conectado.
class StartCallCommand extends ToxNetworkCommand {
  const StartCallCommand({required this.publicKeyHex});
  final String publicKeyHex;
}

/// Atende uma chamada recebida (voz, sem vídeo).
class AnswerCallCommand extends ToxNetworkCommand {
  const AnswerCallCommand({required this.publicKeyHex});
  final String publicKeyHex;
}

/// Encerra ou recusa uma chamada (ativa ou ainda tocando) com um contato.
class HangUpCallCommand extends ToxNetworkCommand {
  const HangUpCallCommand({required this.publicKeyHex});
  final String publicKeyHex;
}

/// Manda um frame de áudio PCM16 capturado do microfone (mono, 48kHz) pro
/// contato em chamada — chamado a cada ~20ms enquanto o microfone não
/// está mudo (ver call_provider.dart).
class SendCallAudioFrameCommand extends ToxNetworkCommand {
  const SendCallAudioFrameCommand({
    required this.publicKeyHex,
    required this.samples,
  });

  final String publicKeyHex;
  final Int16List samples;
}

/// Oferece um arquivo local a um contato.
class SendFileCommand extends ToxNetworkCommand {
  const SendFileCommand({required this.publicKeyHex, required this.filePath});

  final String publicKeyHex;
  final String filePath;
}

/// Ação que a UI pode tomar sobre uma transferência de arquivo — espelha
/// `TOX_FILE_CONTROL`, mas com nomes que fazem sentido do lado da UI
/// (aceitar/recusar um pedido recebido, ou cancelar uma transferência em
/// andamento em qualquer direção).
enum ToxFileControlAction { resume, pause, cancel }

class RespondFileControlCommand extends ToxNetworkCommand {
  const RespondFileControlCommand({
    required this.publicKeyHex,
    required this.fileNumber,
    required this.control,
  });

  final String publicKeyHex;
  final int fileNumber;
  final ToxFileControlAction control;
}

/// Atualiza nome e mensagem de status do próprio perfil. Ambos ficam
/// salvos no savedata do toxcore (não precisa de tabela própria no banco).
class SetProfileCommand extends ToxNetworkCommand {
  const SetProfileCommand({required this.name, required this.statusMessage});

  final String name;
  final String statusMessage;
}

/// Muda o status de presença (Online/Ausente/Ocupado — ver kToxUserStatus*
/// em tox_bindings.dart), separado do nome/descrição de [SetProfileCommand].
class SetUserStatusCommand extends ToxNetworkCommand {
  const SetUserStatusCommand({required this.userStatus});
  final int userStatus;
}

/// Pede para o isolate gravar o savedata no disco imediatamente, em vez de
/// esperar o próximo ciclo periódico. Usado antes de exportar um backup de
/// identidade (ver identity_backup.dart) — sem isso, o arquivo no disco
/// pode estar alguns segundos desatualizado em relação ao estado em memória.
class FlushSavedataCommand extends ToxNetworkCommand {
  const FlushSavedataCommand();
}

/// Cria um novo grupo privado com o nome informado.
class CreateGroupCommand extends ToxNetworkCommand {
  const CreateGroupCommand({required this.groupName});
  final String groupName;
}

/// Convida um contato existente (chave pública) para um grupo (Chat ID).
class InviteToGroupCommand extends ToxNetworkCommand {
  const InviteToGroupCommand(
      {required this.chatIdHex, required this.contactPublicKeyHex});
  final String chatIdHex;
  final String contactPublicKeyHex;
}

/// Aceita um convite de grupo recebido (ver [ToxGroupInviteEvent]) — os
/// dados devem ser exatamente os recebidos naquele evento.
class AcceptGroupInviteCommand extends ToxNetworkCommand {
  const AcceptGroupInviteCommand({
    required this.fromPublicKeyHex,
    required this.inviteData,
  });
  final String fromPublicKeyHex;
  final Uint8List inviteData;
}

/// Envia uma mensagem de texto para um grupo (identificado pelo Chat ID).
class SendGroupMessageCommand extends ToxNetworkCommand {
  const SendGroupMessageCommand(
      {required this.chatIdHex, required this.message});
  final String chatIdHex;
  final String message;
}

/// Sai de um grupo existente.
class LeaveGroupCommand extends ToxNetworkCommand {
  const LeaveGroupCommand({required this.chatIdHex});
  final String chatIdHex;
}
