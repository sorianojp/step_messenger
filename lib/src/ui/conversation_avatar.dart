import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'widgets.dart';

class ConversationAvatar extends StatefulWidget {
  const ConversationAvatar({
    super.key,
    required this.session,
    required this.conversation,
    this.size = 48,
    this.online = false,
  });
  final SessionController session;
  final Conversation conversation;
  final double size;
  final bool online;
  @override
  State<ConversationAvatar> createState() => _ConversationAvatarState();
}

class _ConversationAvatarState extends State<ConversationAvatar> {
  Future<Uint8List>? _photo;
  String get _key =>
      '${widget.session.api.baseUrl}/${widget.session.teamPath}/${widget.conversation.id}/${widget.conversation.json['photo_url']}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ConversationAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey =
        '${oldWidget.session.api.baseUrl}/${oldWidget.session.teamPath}/${oldWidget.conversation.id}/${oldWidget.conversation.json['photo_url']}';
    if (_key != oldKey) _load();
  }

  void _load() {
    _photo = widget.conversation.json['photo_url'] == null
        ? null
        : widget.session.api.download(
            '${widget.session.teamPath}/conversations/${widget.conversation.id}/photo',
          );
  }

  @override
  Widget build(BuildContext context) {
    final fallback = PersonAvatar(
      widget.conversation.name,
      size: widget.size,
      group: widget.conversation.group,
      online: widget.online,
    );
    if (_photo == null) return fallback;
    return FutureBuilder<Uint8List>(
      future: _photo,
      builder: (context, snapshot) {
        if (!snapshot.hasData ||
            snapshot.connectionState != ConnectionState.done) {
          return fallback;
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.size * .31),
          child: Image.memory(
            snapshot.data!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            cacheWidth: (widget.size * 3).round(),
            errorBuilder: (_, _, _) => fallback,
          ),
        );
      },
    );
  }
}
