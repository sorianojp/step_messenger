import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/models.dart';
import '../theme.dart';
import 'widgets.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.group,
    required this.onAction,
    required this.onAttachment,
    required this.onVote,
    required this.onRsvp,
    required this.onReact,
  });
  final ChatMessage message;
  final bool mine;
  final bool group;
  final VoidCallback onAction;
  final void Function(Json) onAttachment;
  final void Function(List<String>) onVote;
  final void Function(String?) onRsvp;
  final void Function(String) onReact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Outgoing bubbles are filled with the brand, so everything drawn inside
    // one takes its colour from the bubble rather than from the page.
    final bubble = bubbleColors(context, mine: mine);
    final ink = bubble.onSurface;
    final inkMuted = mine
        ? ink.withValues(alpha: .75)
        : colors.onSurfaceVariant;
    final inkChip = mine
        ? ink.withValues(alpha: .16)
        : colors.surfaceContainerLow;
    if (message.type == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
        child: Text(
          message.body,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine && group) ...[
            PersonAvatar(message.sender?.name ?? 'School', size: 27),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width > 600
                    ? 450
                    : MediaQuery.sizeOf(context).width * .78,
              ),
              child: Column(
                crossAxisAlignment: mine
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!mine && group)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 5),
                      child: Text(
                        message.sender?.name ?? 'School',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  GestureDetector(
                    onLongPress: message.unsent ? null : onAction,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: bubble.surface,
                        border: Border.all(
                          color: mine
                              ? Colors.transparent
                              : colors.outlineVariant,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(mine ? 18 : 5),
                          bottomRight: Radius.circular(mine ? 5 : 18),
                        ),
                      ),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: ink),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.pinned)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.push_pin,
                                      size: 12,
                                      color: inkMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Pinned',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (message.json['metadata'] is Map &&
                                (message.json['metadata']
                                        as Map)['forwarded_from_message_id'] !=
                                    null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  'Forwarded',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: inkMuted,
                                  ),
                                ),
                              ),
                            if (message.reply != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(color: inkMuted, width: 3),
                                  ),
                                  color: inkChip,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (message.reply!['sender']
                                                  as Map?)?['name']
                                              as String? ??
                                          'Message',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      message.reply!['unsent_at'] != null
                                          ? 'Message unsent'
                                          : message.reply!['body'] as String? ??
                                                'Attachment',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (message.unsent)
                              Text(
                                'This message was unsent',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: inkMuted,
                                ),
                              )
                            else if (message.poll != null)
                              _poll(context)
                            else if (message.event != null)
                              _event(context)
                            else if (message.body.isNotEmpty)
                              Text(
                                message.body,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.5,
                                ),
                              ),
                            for (final attachment in message.attachments)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: message.body.isNotEmpty ? 10 : 0,
                                ),
                                child: InkWell(
                                  onTap: () => onAttachment(attachment),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 7,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          (attachment['mime_type'] as String? ??
                                                      '')
                                                  .startsWith('image/')
                                              ? Icons.image_outlined
                                              : Icons
                                                    .insert_drive_file_outlined,
                                          size: 28,
                                        ),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                attachment['name'] as String,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                '${((attachment['size'] as num? ?? 0) / 1024).round()} KB · Tap to open',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: inkMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (message.reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        children: [
                          for (final reaction in message.reactions)
                            InkWell(
                              onTap: () => onReact(reaction['emoji'] as String),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: inkChip,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: reaction['reacted_by_me'] == true
                                        ? ink
                                        : inkMuted.withValues(alpha: .5),
                                  ),
                                ),
                                child: Text(
                                  '${reaction['emoji']} ${reaction['count']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 5, 4, 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${message.edited ? 'Edited · ' : ''}${message.created == null ? '' : DateFormat.jm().format(message.created!)}',
                          style: TextStyle(fontSize: 10, color: inkMuted),
                        ),
                        if (mine) ...[
                          const SizedBox(width: 5),
                          Semantics(
                            label: message.read
                                ? 'Read'
                                : message.delivered
                                ? 'Delivered'
                                : 'Sent',
                            child: Icon(
                              message.read || message.delivered
                                  ? Icons.done_all
                                  : Icons.done,
                              size: 14,
                              color: message.read
                                  ? StepPalette.onlineFor(
                                      Theme.of(context).brightness,
                                    )
                                  : inkMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _poll(BuildContext context) {
    final poll = message.poll!;
    final options = records(poll['options']);
    final selected = options
        .where((o) => o['voted_by_me'] == true)
        .map((o) => o['id'] as String)
        .toSet();
    final closes = date(poll['closes_at']);
    final closed = closes != null && closes.isBefore(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.poll_outlined, size: 16),
            SizedBox(width: 6),
            Text(
              'POLL',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          poll['question'] as String,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 12),
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                side: BorderSide(
                  color: option['voted_by_me'] == true
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              onPressed: closed
                  ? null
                  : () {
                      final id = option['id'] as String;
                      final ids = poll['allow_multiple'] == true
                          ? {...selected}
                          : <String>{};
                      if (selected.contains(id)) {
                        ids.remove(id);
                      } else {
                        ids.add(id);
                      }
                      onVote(ids.toList());
                    },
              child: Row(
                children: [
                  Icon(
                    option['voted_by_me'] == true
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      option['label'] as String,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${option['vote_count']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        Text(
          '${poll['total_voters']} voted · ${closed
              ? 'Closed'
              : poll['allow_multiple'] == true
              ? 'Choose one or more'
              : 'Choose one'}',
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  Widget _event(BuildContext context) {
    final event = message.event!;
    final starts = date(event['starts_at']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_outlined, size: 16),
            SizedBox(width: 6),
            Text(
              'EVENT',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          event['title'] as String,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        if (starts != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              DateFormat('EEE, MMM d · h:mm a').format(starts),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        if (event['location'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              event['location'] as String,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if (event['description'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              event['description'] as String,
              style: const TextStyle(height: 1.5),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 5,
          children: [
            for (final status in ['attending', 'maybe', 'declined'])
              ChoiceChip(
                label: Text(
                  status == 'attending'
                      ? 'Going'
                      : status == 'maybe'
                      ? 'Maybe'
                      : 'Can’t go',
                  style: const TextStyle(fontSize: 11),
                ),
                selected: event['my_response'] == status,
                showCheckmark: false,
                onSelected: (_) =>
                    onRsvp(event['my_response'] == status ? null : status),
              ),
          ],
        ),
        Text(
          '${records((event['responses'] as Map?)?['attending']).length} going',
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}
