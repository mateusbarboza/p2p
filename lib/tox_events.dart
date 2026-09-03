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
/// é aplicado com sucesso.
class ToxSelfProfileEvent extends ToxNetworkEvent {
  const ToxSelfProfileEvent({required this.name, required this.statusMessage});

  final String name;
  final String statusMessage;
}

/// Nome/status de um amigo (o que ELE definiu no perfil dele) — enviado no
/// boot para cada amigo salvo, e de novo quando ele muda algo (ver
/// tox_callback_friend_name/tox_callback_friend_status_message).
class ToxFriendProfileEvent extends ToxNetworkEvent {
  const ToxFriendProfileEvent({
    required this.publicKeyHex,
    required this.name,
    required this.statusMessage,
  });

  final String publicKeyHex;
  final String name;
  final String statusMessage;
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
        errorMessage = null;

  const ToxMessageSentEvent.failure({
    required this.publicKeyHex,
    required this.message,
    required this.errorMessage,
  })  : success = false,
        toxMessageId = null,
        sentAt = null;

  final bool success;
  final String publicKeyHex;
  final String message;
  final int? toxMessageId;
  final DateTime? sentAt;
  final String? errorMessage;
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
