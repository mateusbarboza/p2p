// chat_screen.dart
//
// Conversa 1:1 com um contato. Lê o histórico persistido (mensagens e
// transferências de arquivo, via chatMessagesProvider/fileTransfersProvider
// — ambos Drift, sobrevivem a reinício) e monta uma única timeline
// ordenada por horário, mesclando os dois tipos de "bloco" — sem isso, uma
// transferência de arquivo pareceria fora de ordem em relação às mensagens
// de texto trocadas ao redor dela.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/database.dart' show CallLog, FileTransfer, Message;
import 'date_divider.dart';
import 'providers/call_provider.dart';
import 'providers/contacts_provider.dart';
import 'providers/database_provider.dart';
import 'providers/file_transfers_provider.dart';
import 'providers/messages_provider.dart';
import 'providers/tox_events_provider.dart';
import 'providers/tox_manager_provider.dart';
import 'tox_events.dart';

/// Depois de quanto tempo sem digitar avisamos o contato que paramos —
/// mesmo valor usado por outros clientes Tox (qTox, Toxic).
const _kTypingStopDelay = Duration(seconds: 5);

/// PCM cru (sem cabeçalho), não WAV/AAC — o SoLoud (usado pra tocar de volta
/// em [_FileTransferBubble]) não decodifica de forma confiável o WAV que o
/// `record` produz no Windows nem AAC/M4A, então gravamos e tocamos os bytes
/// crus diretamente via buffer stream, igual à captura de voz ao vivo em
/// call_provider.dart.
const _kVoiceMessageSampleRate = 44100;
const _kVoiceMessageChannels = 1;

sealed class _TimelineItem {
  const _TimelineItem();
  DateTime get timestamp;
}

class _MessageItem extends _TimelineItem {
  const _MessageItem(this.message);
  final Message message;
  @override
  DateTime get timestamp => message.timestamp;
}

class _FileTransferItem extends _TimelineItem {
  const _FileTransferItem(this.transfer);
  final FileTransfer transfer;
  @override
  DateTime get timestamp => transfer.timestamp;
}

class _CallLogItem extends _TimelineItem {
  const _CallLogItem(this.log);
  final CallLog log;
  @override
  DateTime get timestamp => log.timestamp;
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen(
      {super.key,
      required this.contactPublicKeyHex,
      required this.contactLabel});

  final String contactPublicKeyHex;
  final String contactLabel;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();

  /// Só manda `SetTypingCommand(true)` uma vez ao começar a digitar (não a
  /// cada tecla) — [_typingStopTimer] é quem reseta isso depois de um
  /// tempo sem novas teclas, avisando que paramos.
  bool _isTypingNotified = false;
  Timer? _typingStopTimer;

  /// Gravação de mensagem de voz — grava via streaming (igual à captura de
  /// voz ao vivo em call_provider.dart: gravar direto pra um arquivo PCM
  /// falha no Windows com `AudioEncoder.pcm16bits`, native error "objeto ou
  /// valor especificado não existe"), acumula os bytes e só grava o arquivo
  /// no disco ao parar, antes de mandar pelo mecanismo de transferência de
  /// arquivo já existente.
  final AudioRecorder _voiceRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _voiceRecordingSubscription;
  final BytesBuilder _voiceRecordingBytes = BytesBuilder(copy: false);
  bool _isRecordingVoice = false;
  Timer? _voiceRecordingTimer;
  Duration _voiceRecordingElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // A tela abriu justamente NESTE contato — marca como lida a conversa
    // inteira (mesmo que a lista de contatos ainda não tenha aberto essa
    // tela nenhuma vez até agora).
    unawaited(
      ref
          .read(messagesRepositoryProvider)
          .markAllRead(widget.contactPublicKeyHex),
    );
    unawaited(
      ref
          .read(fileTransfersRepositoryProvider)
          .markAllRead(widget.contactPublicKeyHex),
    );
    _messageController.addListener(_onMessageTextChanged);
  }

  void _onMessageTextChanged() {
    final hasText = _messageController.text.isNotEmpty;
    _typingStopTimer?.cancel();
    if (!hasText) {
      _stopTyping();
      return;
    }
    if (!_isTypingNotified) {
      _isTypingNotified = true;
      ref.read(toxIsolateManagerProvider).setTyping(
            widget.contactPublicKeyHex,
            true,
          );
    }
    _typingStopTimer = Timer(_kTypingStopDelay, _stopTyping);
  }

  void _stopTyping() {
    _typingStopTimer?.cancel();
    if (!_isTypingNotified) return;
    _isTypingNotified = false;
    ref.read(toxIsolateManagerProvider).setTyping(
          widget.contactPublicKeyHex,
          false,
        );
  }

  /// Insere o emoji na posição do cursor em vez de sempre no fim — assim
  /// funciona também quando a pessoa já digitou algo e move o cursor antes
  /// de abrir o seletor.
  void _insertEmoji(String emoji) {
    final selection = _messageController.selection;
    final text = _messageController.text;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, emoji);
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  Future<void> _showEmojiPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            _insertEmoji(emoji.emoji);
            Navigator.pop(context);
          },
          config: const Config(
            height: 320,
            checkPlatformCompatibility: false,
            emojiViewConfig: EmojiViewConfig(emojiSizeMax: 28),
          ),
        ),
      ),
    );
  }

  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    ref
        .read(toxIsolateManagerProvider)
        .sendMessage(widget.contactPublicKeyHex, text);
    _messageController.clear();
  }

  Future<void> _attachFile() async {
    final file = await FilePicker.pickFile();
    final path = file?.path;
    if (path == null) return;
    ref
        .read(toxIsolateManagerProvider)
        .sendFile(widget.contactPublicKeyHex, path);
  }

  /// Começa a gravar uma mensagem de voz — toca de novo pra parar e enviar
  /// (ver [_stopAndSendVoiceMessage]). Um segundo toque enquanto já grava é
  /// ignorado (o botão vira "parar" assim que [_isRecordingVoice] fica true).
  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice) return;
    final hasPermission = await _voiceRecorder.hasPermission();
    if (!hasPermission) return;
    _voiceRecordingBytes.clear();
    final stream = await _voiceRecorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kVoiceMessageSampleRate,
      numChannels: _kVoiceMessageChannels,
    ));
    _voiceRecordingSubscription = stream.listen(_voiceRecordingBytes.add);
    setState(() {
      _isRecordingVoice = true;
      _voiceRecordingElapsed = Duration.zero;
    });
    _voiceRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _voiceRecordingElapsed += const Duration(seconds: 1);
      });
    });
  }

  Future<void> _stopAndSendVoiceMessage() async {
    if (!_isRecordingVoice) return;
    _voiceRecordingTimer?.cancel();
    _voiceRecordingTimer = null;
    await _voiceRecorder.stop();
    await _voiceRecordingSubscription?.cancel();
    _voiceRecordingSubscription = null;
    setState(() => _isRecordingVoice = false);
    final bytes = _voiceRecordingBytes.takeBytes();
    // Grava curto demais / sem nenhum frame capturado — nada pra enviar.
    if (bytes.isEmpty) return;
    final directory = await getApplicationSupportDirectory();
    final voiceDir = Directory(
      '${directory.path}${Platform.pathSeparator}voice_messages',
    );
    await voiceDir.create(recursive: true);
    final path = '${voiceDir.path}${Platform.pathSeparator}'
        'voice_${DateTime.now().millisecondsSinceEpoch}.pcm';
    await File(path).writeAsBytes(bytes);
    ref
        .read(toxIsolateManagerProvider)
        .sendFile(widget.contactPublicKeyHex, path);
  }

  /// Para e descarta sem enviar — usado quando o usuário desiste no meio da
  /// gravação (ver o botão de cancelar na barra de gravação).
  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceRecordingTimer?.cancel();
    _voiceRecordingTimer = null;
    await _voiceRecorder.stop();
    await _voiceRecordingSubscription?.cancel();
    _voiceRecordingSubscription = null;
    _voiceRecordingBytes.clear();
    setState(() => _isRecordingVoice = false);
  }

  void _respondToTransfer(int fileNumber, ToxFileControlAction action) {
    ref.read(toxIsolateManagerProvider).respondFileControl(
          widget.contactPublicKeyHex,
          fileNumber,
          action,
        );
  }

  /// Apaga só localmente — o toxcore não tem "apagar para todos". Pede
  /// confirmação porque não tem como desfazer.
  Future<void> _confirmDelete(
      String description, Future<void> Function() action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir?'),
        content: Text(
            '$description será removido só do seu histórico. Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed == true) {
      await action();
    }
  }

  void _deleteMessage(Message message) {
    unawaited(
      _confirmDelete(
        'Essa mensagem',
        () => ref.read(messagesRepositoryProvider).deleteById(message.id),
      ),
    );
  }

  void _deleteFileTransfer(FileTransfer transfer) {
    unawaited(
      _confirmDelete(
        'Esse arquivo',
        () => ref.read(fileTransfersRepositoryProvider).deleteById(transfer.id),
      ),
    );
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    if (_isTypingNotified) {
      ref.read(toxIsolateManagerProvider).setTyping(
            widget.contactPublicKeyHex,
            false,
          );
    }
    _voiceRecordingTimer?.cancel();
    unawaited(_voiceRecordingSubscription?.cancel());
    unawaited(_voiceRecorder.dispose());
    _messageController.removeListener(_onMessageTextChanged);
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Falhas de envio (mensagem ou arquivo) não geram uma linha na
    // timeline — sem isso, o usuário só veria o campo limpar / nada
    // acontecer, sem entender por quê.
    ref.listen(toxNetworkEventsProvider, (previous, next) {
      next.whenData((event) {
        // Mensagem chegou com a conversa já aberta: marca como lida na
        // hora, sem esperar o usuário reabrir a tela.
        if (event is ToxFriendMessageEvent &&
            event.publicKeyHex == widget.contactPublicKeyHex) {
          unawaited(
            ref
                .read(messagesRepositoryProvider)
                .markAllRead(widget.contactPublicKeyHex),
          );
        }
        // Mesmo raciocínio acima, mas pra arquivo/áudio recebido (ex:
        // mensagem de voz) chegando com a conversa já aberta.
        if (event is ToxFileTransferEvent &&
            !event.outgoing &&
            event.phase == ToxFileTransferPhase.completed &&
            event.publicKeyHex == widget.contactPublicKeyHex) {
          unawaited(
            ref
                .read(fileTransfersRepositoryProvider)
                .markAllRead(widget.contactPublicKeyHex),
          );
        }
        String? errorMessage;
        if (event is ToxMessageSentEvent &&
            !event.success &&
            event.publicKeyHex == widget.contactPublicKeyHex) {
          // Contato offline no momento: guarda como pendente em vez de
          // mostrar erro — messages_provider.dart reenvia sozinho assim que
          // ele conectar de novo (ToxFriendConnectionEvent).
          if (event.notConnected) {
            unawaited(
              ref.read(messagesRepositoryProvider).insertPending(
                    contactPublicKeyHex: widget.contactPublicKeyHex,
                    body: event.message,
                    timestamp: DateTime.now(),
                  ),
            );
          } else {
            errorMessage = 'Falha ao enviar mensagem: ${event.errorMessage}';
          }
        } else if (event is ToxFileTransferEvent &&
            event.phase == ToxFileTransferPhase.failed &&
            event.publicKeyHex == widget.contactPublicKeyHex) {
          errorMessage = 'Falha na transferência: ${event.errorMessage}';
        }
        if (errorMessage != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(errorMessage)));
        }
      });
    });

    final messagesAsync =
        ref.watch(chatMessagesProvider(widget.contactPublicKeyHex));
    final transfersAsync =
        ref.watch(fileTransfersProvider(widget.contactPublicKeyHex));
    final callLogsAsync =
        ref.watch(callLogsForContactProvider(widget.contactPublicKeyHex));
    final contacts = ref.watch(contactsProvider);
    final isContactTyping = contacts
        .where((c) => c.publicKeyHex == widget.contactPublicKeyHex)
        .any((c) => c.isTyping);

    final callState = ref.watch(callProvider);
    final isThisContactInCall =
        callState.contactPublicKeyHex == widget.contactPublicKeyHex &&
            callState.status != CallStatus.idle;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.contactLabel),
        actions: [_buildCallAction(callState, isThisContactInCall)],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildTimeline(messagesAsync, transfersAsync, callLogsAsync),
          ),
          if (isContactTyping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Digitando...',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _isRecordingVoice
                  ? _buildVoiceRecordingBar()
                  : Row(
                      children: [
                        IconButton(
                            onPressed: _attachFile,
                            icon: const Icon(Icons.attach_file)),
                        IconButton(
                            onPressed: _showEmojiPicker,
                            icon: const Icon(Icons.emoji_emotions_outlined)),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: const InputDecoration(
                              hintText: 'Mensagem...',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        IconButton(
                          onPressed: _startVoiceRecording,
                          tooltip: 'Gravar áudio',
                          icon: const Icon(Icons.mic),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                            onPressed: _send, icon: const Icon(Icons.send)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceRecordingBar() {
    final minutes = _voiceRecordingElapsed.inMinutes.toString().padLeft(2, '0');
    final seconds =
        (_voiceRecordingElapsed.inSeconds % 60).toString().padLeft(2, '0');
    return Row(
      children: [
        IconButton(
          onPressed: _cancelVoiceRecording,
          tooltip: 'Cancelar',
          icon: const Icon(Icons.delete_outline),
        ),
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
        const SizedBox(width: 6),
        Expanded(child: Text('Gravando áudio... $minutes:$seconds')),
        IconButton.filled(
          onPressed: _stopAndSendVoiceMessage,
          tooltip: 'Enviar áudio',
          icon: const Icon(Icons.send),
        ),
      ],
    );
  }

  Widget _buildCallAction(CallState callState, bool isThisContactInCall) {
    if (!isThisContactInCall) {
      return IconButton(
        icon: const Icon(Icons.call),
        tooltip: 'Ligar',
        onPressed: () => ref
            .read(callProvider.notifier)
            .startCall(widget.contactPublicKeyHex),
      );
    }
    if (callState.status == CallStatus.incomingRinging) {
      return IconButton(
        icon: const Icon(Icons.call),
        tooltip: 'Atender',
        onPressed: () => ref.read(callProvider.notifier).answer(),
      );
    }
    return IconButton(
      icon: const Icon(Icons.call_end),
      color: Colors.red,
      tooltip: 'Desligar',
      onPressed: () => ref.read(callProvider.notifier).hangUp(),
    );
  }

  Widget _buildTimeline(
    AsyncValue<List<Message>> messagesAsync,
    AsyncValue<List<FileTransfer>> transfersAsync,
    AsyncValue<List<CallLog>> callLogsAsync,
  ) {
    if (messagesAsync.isLoading || transfersAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (messagesAsync.hasError) {
      return Center(
          child: Text('Erro ao carregar mensagens: ${messagesAsync.error}'));
    }
    if (transfersAsync.hasError) {
      return Center(
          child:
              Text('Erro ao carregar transferências: ${transfersAsync.error}'));
    }

    final items = <_TimelineItem>[
      for (final message in messagesAsync.value ?? const <Message>[])
        _MessageItem(message),
      for (final transfer in transfersAsync.value ?? const <FileTransfer>[])
        _FileTransferItem(transfer),
      for (final log in callLogsAsync.value ?? const <CallLog>[])
        _CallLogItem(log),
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (items.isEmpty) {
      return const Center(child: Text('Nenhuma mensagem ainda. Diga oi!'));
    }

    // `reverse: true` + lista invertida (mais recente primeiro) em vez de
    // pular manualmente pro fim depois de montar a lista — assim a
    // conversa já abre exatamente na mensagem mais recente, sem o "flash"
    // de aparecer no topo por um frame antes de pular.
    final reversedItems = items.reversed.toList();

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: reversedItems.length,
      itemBuilder: (context, index) {
        final item = reversedItems[index];
        final showDateDivider = index == reversedItems.length - 1 ||
            !isSameDay(reversedItems[index + 1].timestamp, item.timestamp);
        final bubble = switch (item) {
          _MessageItem(:final message) => _HoverDeleteWrapper(
              alignRight: message.outgoing,
              onDelete: () => _deleteMessage(message),
              child: _MessageBubble(message: message),
            ),
          _FileTransferItem(:final transfer) => _HoverDeleteWrapper(
              alignRight: transfer.outgoing,
              onDelete: () => _deleteFileTransfer(transfer),
              child: _FileTransferBubble(
                transfer: transfer,
                onAccept: () => _respondToTransfer(
                    transfer.toxFileNumber, ToxFileControlAction.resume),
                onReject: () => _respondToTransfer(
                    transfer.toxFileNumber, ToxFileControlAction.cancel),
              ),
            ),
          _CallLogItem(:final log) => _CallLogBubble(log: log),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDateDivider) DateDivider(date: item.timestamp),
            bubble,
          ],
        );
      },
    );
  }
}

/// Envolve uma bolha (mensagem ou arquivo) com um botão de ações que só
/// aparece ao passar o mouse por cima — padrão comum em apps de desktop
/// (WhatsApp Web, Slack) e bem mais descobrível que um toque
/// longo/clique-direito num app pensado primeiro pra mouse.
class _HoverDeleteWrapper extends StatefulWidget {
  const _HoverDeleteWrapper({
    required this.alignRight,
    required this.onDelete,
    required this.child,
  });

  final bool alignRight;
  final VoidCallback onDelete;
  final Widget child;

  @override
  State<_HoverDeleteWrapper> createState() => _HoverDeleteWrapperState();
}

class _HoverDeleteWrapperState extends State<_HoverDeleteWrapper> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final menuButton = SizedBox(
      width: 28,
      height: 28,
      child: _hovering
          ? PopupMenuButton<void>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_drop_down_circle_outlined, size: 18),
              tooltip: 'Mais opções',
              itemBuilder: (context) => [
                PopupMenuItem<void>(
                  onTap: widget.onDelete,
                  child: const Text('Apagar'),
                ),
              ],
            )
          : null,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            widget.alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: widget.alignRight
            ? [menuButton, Flexible(child: widget.child)]
            : [Flexible(child: widget.child), menuButton],
      ),
    );
  }
}

/// Linha informativa de chamada de voz na timeline — "Chamada de voz
/// iniciada/recebida" ou "Chamada encerrada", sempre com o horário. Não é
/// uma bolha de mensagem (nem tem "apagar" — ver [_HoverDeleteWrapper]):
/// fica centralizada, como o [DateDivider].
class _CallLogBubble extends StatelessWidget {
  const _CallLogBubble({required this.log});

  final CallLog log;

  @override
  Widget build(BuildContext context) {
    final time = '${log.timestamp.hour.toString().padLeft(2, '0')}:'
        '${log.timestamp.minute.toString().padLeft(2, '0')}';
    final label = switch (log.kind) {
      'started' =>
        log.outgoing ? 'Chamada de voz iniciada' : 'Chamada de voz recebida',
      'ended' => 'Chamada encerrada',
      _ => 'Chamada de voz',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.call, size: 14),
              const SizedBox(width: 6),
              Text('$label — $time',
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Sem Align aqui de propósito: quem posiciona a bolha na tela (esquerda
    // vs. direita) é o _HoverDeleteWrapper que envolve isto — colocar outro
    // Align aqui de novo faria a bolha flutuar dentro do próprio espaço
    // flexível reservado a ela, se afastando do botão de opções ao lado.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: message.outgoing
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message.body),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (message.outgoing) ...[
                const SizedBox(width: 4),
                Icon(
                  message.pending
                      ? Icons.schedule
                      : (message.delivered ? Icons.done_all : Icons.done),
                  size: 14,
                  color: message.delivered ? Colors.blue : null,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FileTransferBubble extends StatefulWidget {
  const _FileTransferBubble({
    required this.transfer,
    required this.onAccept,
    required this.onReject,
  });

  final FileTransfer transfer;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  State<_FileTransferBubble> createState() => _FileTransferBubbleState();
}

class _FileTransferBubbleState extends State<_FileTransferBubble> {
  FileTransfer get transfer => widget.transfer;
  VoidCallback get onAccept => widget.onAccept;
  VoidCallback get onReject => widget.onReject;

  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp'
  };

  static const _audioExtensions = {
    '.pcm',
    '.m4a',
    '.aac',
    '.mp3',
    '.wav',
    '.ogg',
    '.opus',
  };

  AudioSource? _playbackSource;
  SoundHandle? _playbackHandle;
  StreamSubscription<StreamSoundEvent>? _playbackSubscription;
  bool _isPlaying = false;

  bool get _isReceivedAndComplete =>
      !transfer.outgoing &&
      transfer.status == ToxFileTransferPhase.completed &&
      transfer.savedPath != null;

  bool get _isImage {
    final lowerName = transfer.fileName.toLowerCase();
    return _imageExtensions.any(lowerName.endsWith);
  }

  bool get _isAudio {
    final lowerName = transfer.fileName.toLowerCase();
    return _audioExtensions.any(lowerName.endsWith);
  }

  /// Toca/pausa a mensagem de voz recebida. Em vez de pedir pro SoLoud
  /// decodificar o arquivo sozinho (`loadFile` falha tanto pro WAV que o
  /// `record` produz no Windows quanto pro AAC/M4A — `SoLoudFileLoadFailedException`
  /// nos dois casos), lemos os bytes PCM crus e empurramos direto num buffer
  /// stream, igual à reprodução de áudio ao vivo em call_provider.dart.
  Future<void> _togglePlayback() async {
    final path = transfer.savedPath;
    if (path == null) return;
    final handle = _playbackHandle;
    if (_isPlaying && handle != null) {
      await SoLoud.instance.stop(handle);
      setState(() => _isPlaying = false);
      return;
    }
    if (!SoLoud.instance.isInitialized) {
      await SoLoud.instance.init();
    }
    final oldSource = _playbackSource;
    if (oldSource != null) {
      await _playbackSubscription?.cancel();
      await SoLoud.instance.disposeSource(oldSource);
    }
    final source = SoLoud.instance.setBufferStream(
      sampleRate: _kVoiceMessageSampleRate,
      channels: Channels.mono,
      format: BufferType.s16le,
      bufferingTimeNeeds: 0,
    );
    _playbackSource = source;
    _playbackSubscription = source.soundEvents.listen((event) {
      if (event.event == SoundEventType.handleIsNoMoreValid && mounted) {
        setState(() => _isPlaying = false);
      }
    });
    final bytes = await File(path).readAsBytes();
    SoLoud.instance.addAudioDataStream(source, bytes);
    SoLoud.instance.setDataIsEnded(source);
    _playbackHandle = SoLoud.instance.play(source);
    if (mounted) setState(() => _isPlaying = true);
  }

  @override
  void dispose() {
    unawaited(_playbackSubscription?.cancel());
    final source = _playbackSource;
    if (source != null) {
      unawaited(SoLoud.instance.disposeSource(source));
    }
    super.dispose();
  }

  Future<void> _openFile() async {
    final path = transfer.savedPath;
    if (path == null) return;
    await launchUrl(Uri.file(path));
  }

  /// "Abrir" já salva o recebido em attachments/ dentro dos dados do app —
  /// isso aqui é o "Salvar como", deixando o usuário escolher outro lugar
  /// (ex: Downloads, Área de Trabalho), como num navegador comum.
  Future<void> _downloadFile() async {
    final path = transfer.savedPath;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    await FilePicker.saveFile(fileName: transfer.fileName, bytes: bytes);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = transfer.totalBytes == 0
        ? 0.0
        : transfer.bytesTransferred / transfer.totalBytes;
    final isPendingIncoming =
        !transfer.outgoing && transfer.status == ToxFileTransferPhase.requested;

    // Sem Align aqui de propósito — ver o comentário equivalente em
    // _MessageBubble: quem posiciona é o _HoverDeleteWrapper.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: transfer.outgoing
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _isAudio ? Icons.mic : Icons.insert_drive_file_outlined,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isAudio ? 'Mensagem de voz' : transfer.fileName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (_isReceivedAndComplete && _isAudio) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filled(
                  onPressed: _togglePlayback,
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                ),
              ],
            ),
          ],
          if (_isReceivedAndComplete && _isImage) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(transfer.savedPath!),
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (!isPendingIncoming)
            LinearProgressIndicator(value: progress.clamp(0, 1)),
          const SizedBox(height: 4),
          Text(_statusLabel(transfer),
              style: Theme.of(context).textTheme.labelSmall),
          if (isPendingIncoming)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: onReject, child: const Text('Recusar')),
                  const SizedBox(width: 4),
                  FilledButton(
                      onPressed: onAccept, child: const Text('Aceitar')),
                ],
              ),
            ),
          if (_isReceivedAndComplete)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: _downloadFile,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Baixar'),
                  ),
                  TextButton.icon(
                    onPressed: _openFile,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Abrir'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(FileTransfer transfer) {
    final sizeLabel = '${(transfer.totalBytes / 1024).toStringAsFixed(1)} KB';
    switch (transfer.status) {
      case ToxFileTransferPhase.requested:
        return transfer.outgoing
            ? 'Aguardando aceitação... ($sizeLabel)'
            : 'Recebido pedido de envio ($sizeLabel)';
      case ToxFileTransferPhase.progress:
        return '${(transfer.bytesTransferred / 1024).toStringAsFixed(1)} KB / $sizeLabel';
      case ToxFileTransferPhase.completed:
        return transfer.outgoing
            ? 'Enviado ($sizeLabel)'
            : 'Recebido ($sizeLabel)';
      case ToxFileTransferPhase.cancelled:
        return 'Cancelado';
      case ToxFileTransferPhase.failed:
        return 'Falhou';
    }
  }
}
