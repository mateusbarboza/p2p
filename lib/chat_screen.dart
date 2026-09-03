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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/database.dart' show FileTransfer, Message;
import 'providers/database_provider.dart';
import 'providers/file_transfers_provider.dart';
import 'providers/messages_provider.dart';
import 'providers/tox_events_provider.dart';
import 'providers/tox_manager_provider.dart';
import 'tox_events.dart';

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
        String? errorMessage;
        if (event is ToxMessageSentEvent &&
            !event.success &&
            event.publicKeyHex == widget.contactPublicKeyHex) {
          errorMessage = 'Falha ao enviar mensagem: ${event.errorMessage}';
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

    return Scaffold(
      appBar: AppBar(title: Text(widget.contactLabel)),
      body: Column(
        children: [
          Expanded(
            child: _buildTimeline(messagesAsync, transfersAsync),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                      onPressed: _attachFile,
                      icon: const Icon(Icons.attach_file)),
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

  Widget _buildTimeline(
    AsyncValue<List<Message>> messagesAsync,
    AsyncValue<List<FileTransfer>> transfersAsync,
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
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (items.isEmpty) {
      return const Center(child: Text('Nenhuma mensagem ainda. Diga oi!'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return switch (item) {
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
        };
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
                  message.delivered ? Icons.done_all : Icons.done,
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

class _FileTransferBubble extends StatelessWidget {
  const _FileTransferBubble({
    required this.transfer,
    required this.onAccept,
    required this.onReject,
  });

  final FileTransfer transfer;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.webp'
  };

  bool get _isReceivedAndComplete =>
      !transfer.outgoing &&
      transfer.status == ToxFileTransferPhase.completed &&
      transfer.savedPath != null;

  bool get _isImage {
    final lowerName = transfer.fileName.toLowerCase();
    return _imageExtensions.any(lowerName.endsWith);
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
              const Icon(Icons.insert_drive_file_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(transfer.fileName, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
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
