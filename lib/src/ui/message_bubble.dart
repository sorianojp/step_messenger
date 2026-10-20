import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/message_text.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../theme.dart';
import 'message_media.dart';

/// A message, laid out like MessageBubble in the web app's
/// features/messenger/components/message-bubble.tsx.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.session,
    required this.conversationPath,
    required this.message,
    required this.mine,
    required this.group,
    required this.onAction,
    required this.onAttachment,
    required this.onVote,
    required this.onRsvp,
    required this.onReact,
    this.senderName,
    this.status,
  });
  final SessionController session;
  final String conversationPath;
  final ChatMessage message;
  final bool mine;
  final bool group;

  /// The sender's name as this conversation shows it (nickname first).
  final String? senderName;

  /// "Sent", "Delivered" or "Seen …" under the latest own message.
  final String? status;
  final VoidCallback onAction;
  final void Function(Json) onAttachment;
  final void Function(List<String>) onVote;
  final void Function(String) onRsvp;
  final void Function(String) onReact;

  bool get _interactive => message.poll != null || message.event != null;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brand = brandText(context);
    if (message.type == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh.withValues(alpha: .8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              message.body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    // Polls and events sit on the incoming colour so their controls stay
    // readable; unsent messages are muted.
    final outgoing = mine && !message.unsent && !_interactive;
    final surface = mine && message.unsent
        ? colors.surfaceContainerHigh
        : bubbleColors(context, mine: outgoing).surface;
    final ink = mine && message.unsent
        ? colors.onSurfaceVariant
        : bubbleColors(context, mine: outgoing).onSurface;
    final inkMuted = outgoing
        ? ink.withValues(alpha: .7)
        : colors.onSurfaceVariant;
    final accent = outgoing ? ink : brand;
    const tail = Radius.circular(StepShape.radiusBubbleTail);
    const round = Radius.circular(StepShape.radiusLarge);
    final width = MediaQuery.sizeOf(context).width;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        message.reactions.isEmpty || message.unsent ? 8 : 20,
      ),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (width * .82).clamp(0, 544).toDouble(),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onLongPress: message.unsent ? null : onAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: surface,
                      boxShadow: stepShadowSmall,
                      border: mine && _interactive && !message.unsent
                          ? Border.all(color: brand.withValues(alpha: .25))
                          : null,
                      borderRadius: BorderRadius.only(
                        topLeft: round,
                        topRight: round,
                        bottomLeft: mine ? round : tail,
                        bottomRight: mine ? tail : round,
                      ),
                    ),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: ink),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!mine && group && message.sender != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                senderName ?? message.sender!.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: brand,
                                ),
                              ),
                            ),
                          if (message.pinned || _forwarded)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                [
                                  if (message.pinned) 'Pinned',
                                  if (_forwarded) 'Forwarded',
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: inkMuted,
                                ),
                              ),
                            ),
                          if (message.reply != null)
                            _ReplyPreview(
                              reply: message.reply!,
                              currentUserId: session.user?.id,
                              outgoing: outgoing,
                              ink: ink,
                              brand: brand,
                            ),
                          if (message.unsent)
                            Text(
                              mine
                                  ? 'You unsent a message.'
                                  : 'This message was unsent.',
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: colors.onSurfaceVariant,
                              ),
                            )
                          else if (message.poll != null)
                            _poll(context, brand)
                          else if (message.event != null)
                            _event(context, brand)
                          else if (message.body.isNotEmpty)
                            _MessageText(
                              text: message.body,
                              color: ink,
                              accent: accent,
                            ),
                          if (!message.unsent &&
                              message.linkPreviews.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final preview in message.linkPreviews)
                                    LinkPreviewCard(
                                      preview: preview,
                                      ink: colors.onSurface,
                                      inkMuted: colors.onSurfaceVariant,
                                      background: dark
                                          ? StepPalette.cardDark
                                          : StepPalette.card,
                                    ),
                                ],
                              ),
                            ),
                          if (!message.unsent)
                            for (final (index, attachment)
                                in message.attachments.indexed)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: index > 0 || message.body.isNotEmpty
                                      ? 8
                                      : 0,
                                ),
                                child: _attachment(
                                  context,
                                  attachment,
                                  outgoing: outgoing,
                                  ink: ink,
                                  inkMuted: inkMuted,
                                  brand: brand,
                                ),
                              ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              [
                                if (message.edited && !message.unsent) 'Edited',
                                if (message.created != null)
                                  DateFormat(
                                    'MMM d, h:mm a',
                                  ).format(message.created!),
                              ].join(' '),
                              style: TextStyle(fontSize: 11, color: inkMuted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (message.reactions.isNotEmpty && !message.unsent)
                  Positioned(
                    right: 8,
                    bottom: -14,
                    child: Wrap(
                      spacing: 4,
                      children: [
                        for (final reaction in message.reactions)
                          _ReactionChip(
                            reaction: reaction,
                            onTap: () => onReact(reaction['emoji'] as String),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (status != null)
            Padding(
              padding: EdgeInsets.only(
                top: message.reactions.isEmpty ? 0 : 4,
                right: 2,
              ),
              child: Text(
                status!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool get _forwarded =>
      (message.json['metadata'] as Map?)?['forwarded_from_message_id'] != null;

  String _previewPath(Json attachment) =>
      '$conversationPath/messages/${message.id}/attachments/${attachment['id']}/preview';

  Widget _attachment(
    BuildContext context,
    Json attachment, {
    required bool outgoing,
    required Color ink,
    required Color inkMuted,
    required Color brand,
  }) {
    final colors = Theme.of(context).colorScheme;
    // Inside an outgoing bubble, shells tint with the bubble's own ink
    // (like the reply preview) so their text stays readable.
    final shell = BoxDecoration(
      color: outgoing
          ? ink.withValues(alpha: .1)
          : colors.surfaceContainerHigh.withValues(alpha: .4),
      borderRadius: BorderRadius.circular(StepShape.radiusMedium),
      border: Border.all(
        color: outgoing ? ink.withValues(alpha: .25) : colors.outlineVariant,
      ),
    );
    if (isAudioAttachment(attachment, voice: message.voice)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: shell,
        child: VoiceNotePlayer(
          session: session,
          path: _previewPath(attachment),
          cacheKey: '${message.id}_${attachment['id']}',
          color: outgoing ? ink : brand,
          mutedColor: inkMuted,
        ),
      );
    }
    if (isImageAttachment(attachment)) {
      return AttachmentImage(
        session: session,
        path: _previewPath(attachment),
        onTap: () => onAttachment(attachment),
      );
    }
    final size = (attachment['size'] as num? ?? 0).toDouble();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onAttachment(attachment),
        borderRadius: BorderRadius.circular(StepShape.radiusMedium),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: shell,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? StepPalette.cardDark
                      : StepPalette.card,
                  borderRadius: BorderRadius.circular(StepShape.radiusSmall),
                ),
                child: Icon(Icons.description_outlined, size: 16, color: brand),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment['name'] as String? ?? 'Attachment',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Material resets the inherited text colour.
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: ink,
                      ),
                    ),
                    Text(
                      fileSizeLabel(size),
                      style: TextStyle(fontSize: 12, color: inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poll(BuildContext context, Color brand) {
    final colors = Theme.of(context).colorScheme;
    final poll = message.poll!;
    final options = records(poll['options']);
    final selected = options
        .where((o) => o['voted_by_me'] == true)
        .map((o) => o['id'] as String)
        .toSet();
    final totalVotes = options.fold<num>(
      0,
      (total, o) => total + (o['vote_count'] as num? ?? 0),
    );
    final closes = date(poll['closes_at']);
    final closed = closes != null && !closes.isAfter(DateTime.now());
    final voters = poll['total_voters'] as num? ?? 0;
    return SizedBox(
      width: 288,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.checklist_rounded,
            brand: brand,
            title: poll['question'] as String,
            subtitle: Text(
              poll['allow_multiple'] == true
                  ? 'Choose one or more'
                  : 'Choose one',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PollOption(
                option: option,
                percent: totalVotes == 0
                    ? 0
                    : ((option['vote_count'] as num? ?? 0) / totalVotes * 100)
                          .round(),
                brand: brand,
                onTap: closed
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
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '$voters ${voters == 1 ? 'person voted' : 'people voted'}${closed
                ? ' · Poll closed'
                : closes != null
                ? ' · Closes ${eventDateLabel(closes)}'
                : ''}',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _event(BuildContext context, Color brand) {
    final colors = Theme.of(context).colorScheme;
    final event = message.event!;
    final starts = date(event['starts_at']);
    final responses = event['responses'] as Map? ?? {};
    return SizedBox(
      width: 288,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.calendar_today_outlined,
            brand: brand,
            square: true,
            title: event['title'] as String,
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (starts != null)
                  Text(
                    eventDateLabel(starts),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: brand,
                    ),
                  ),
                if (event['location'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            event['location'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (event['description'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                event['description'] as String,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final (index, (status, label)) in const [
                ('attending', 'Going'),
                ('maybe', 'Maybe'),
                ('declined', 'Can’t go'),
              ].indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: _RsvpButton(
                    label: '$label · ${records(responses[status]).length}',
                    selected: event['my_response'] == status,
                    brand: brand,
                    onTap: () => onRsvp(status),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

String fileSizeLabel(double bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String eventDateLabel(DateTime value) =>
    DateFormat('MMM d, y, h:mm a').format(value);

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.brand,
    required this.title,
    required this.subtitle,
    this.square = false,
  });
  final IconData icon;
  final Color brand;
  final String title;
  final Widget subtitle;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final size = square ? 44.0 : 36.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: brand.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(
              square ? StepShape.radiusMedium : size / 2,
            ),
          ),
          child: Icon(icon, size: square ? 20 : 16, color: brand),
        ),
        SizedBox(width: square ? 12 : 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle,
            ],
          ),
        ),
      ],
    );
  }
}

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.option,
    required this.percent,
    required this.brand,
    required this.onTap,
  });
  final Json option;
  final int percent;
  final Color brand;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final voted = option['voted_by_me'] == true;
    final radius = BorderRadius.circular(StepShape.radiusMedium);
    return Semantics(
      button: true,
      selected: voted,
      child: Material(
        color: voted
            ? brand.withValues(alpha: .1)
            : colors.surfaceContainerLow.withValues(alpha: .7),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: voted ? brand : colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: percent / 100,
                  child: ColoredBox(color: brand.withValues(alpha: .1)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${voted ? '✓ ' : ''}${option['label']}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${option['vote_count']} · $percent%',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RsvpButton extends StatelessWidget {
  const _RsvpButton({
    required this.label,
    required this.selected,
    required this.brand,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color brand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? brand.withValues(alpha: .15)
            : colors.surfaceContainerLow.withValues(alpha: .7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StepShape.radiusSmall),
          side: BorderSide(color: selected ? brand : colors.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(StepShape.radiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? brand : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({
    required this.reply,
    required this.currentUserId,
    required this.outgoing,
    required this.ink,
    required this.brand,
  });
  final Json reply;
  final int? currentUserId;
  final bool outgoing;
  final Color ink;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sender = reply['sender'] as Map?;
    final attachments = reply['attachment_count'] as num? ?? 0;
    // Same wording as replyMessagePreview() in the web app.
    final preview = reply['unsent_at'] != null
        ? 'Message unsent'
        : (reply['body'] as String? ?? '').isNotEmpty
        ? reply['body'] as String
        : attachments == 1
        ? 'Attachment'
        : attachments > 1
        ? '$attachments attachments'
        : 'Message';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: outgoing
            ? ink.withValues(alpha: .12)
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(StepShape.radiusSmall),
        border: Border(
          left: BorderSide(
            color: outgoing ? ink.withValues(alpha: .5) : brand,
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sender?['id'] == currentUserId
                ? 'You'
                : sender?['name'] as String? ?? 'Message',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: outgoing ? ink : brand,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: outgoing
                  ? ink.withValues(alpha: .75)
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction, required this.onTap});
  final Json reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brand = brandText(context);
    final mine = reaction['reacted_by_me'] == true;
    final names = records(reaction['users']).map((u) => u['name']).join(', ');
    return Tooltip(
      message: names,
      child: Material(
        color: mine
            ? Color.alphaBlend(
                brand.withValues(alpha: .15),
                colors.surfaceContainerLow,
              )
            : colors.surfaceContainerLow,
        shape: StadiumBorder(
          side: BorderSide(
            color: mine ? brand.withValues(alpha: .4) : colors.outlineVariant,
          ),
        ),
        elevation: 0.5,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              '${reaction['emoji']} ${reaction['count']}',
              style: TextStyle(
                fontSize: 12,
                color: mine ? brand : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Message body with tappable links and highlighted @mentions.
class _MessageText extends StatefulWidget {
  const _MessageText({
    required this.text,
    required this.color,
    required this.accent,
  });
  final String text;
  final Color color;

  /// Links and mentions: brand on light bubbles, bubble ink on outgoing ones.
  final Color accent;

  @override
  State<_MessageText> createState() => _MessageTextState();
}

class _MessageTextState extends State<_MessageText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _clear() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(String href) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => openExternalLink(context, href);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 14, height: 1.7, color: widget.color),
        children: [
          for (final part in messageTextParts(widget.text))
            switch (part.type) {
              TextPartType.link => TextSpan(
                text: part.text,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: widget.accent,
                  decoration: TextDecoration.underline,
                  decorationColor: widget.accent.withValues(alpha: .3),
                ),
                recognizer: _tap(part.href!),
              ),
              TextPartType.mention => TextSpan(
                text: part.text,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: widget.accent,
                ),
              ),
              TextPartType.text => TextSpan(text: part.text),
            },
        ],
      ),
    );
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }
}
