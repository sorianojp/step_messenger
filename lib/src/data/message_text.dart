// Mirrors chat-app/resources/js/features/messenger/lib/text.ts so mentions
// and links are tokenised the same way on web and mobile.

enum TextPartType { text, link, mention }

class TextPart {
  const TextPart(this.type, this.text, [this.href]);
  final TextPartType type;
  final String text;
  final String? href;

  @override
  bool operator ==(Object other) =>
      other is TextPart &&
      other.type == type &&
      other.text == text &&
      other.href == href;

  @override
  int get hashCode => Object.hash(type, text, href);

  @override
  String toString() => '$type($text${href == null ? '' : ' → $href'})';
}

class MentionRange {
  const MentionRange(this.start, this.end, this.query);
  final int start;
  final int end;
  final String query;
}

/// The token Laravel matches against a participant: the name without spaces.
String mentionToken(String name) => name.trim().replaceAll(RegExp(r'\s+'), '');

/// The `@query` being typed immediately before [cursor], if any.
MentionRange? mentionRangeAtCursor(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final match = RegExp(
    r'(^|\s)@([A-Za-z0-9._-]*)$',
  ).firstMatch(text.substring(0, cursor));
  if (match == null) return null;
  return MentionRange(
    match.start + match.group(1)!.length,
    cursor,
    match.group(2) ?? '',
  );
}

final _link = RegExp(
  r'''((?:https?://|www\.)[^\s<>"']+)''',
  caseSensitive: false,
);
final _trailing = RegExp(r'[.,);\]]+$');
final _mention = RegExp(
  r'(^|\s)(@everyone|@[A-Za-z0-9._-]+)',
  caseSensitive: false,
);

/// Splits a message body into plain text, links and @mentions.
List<TextPart> messageTextParts(String text) {
  final parts = <TextPart>[];
  var last = 0;
  for (final match in _link.allMatches(text)) {
    if (match.start > last) {
      parts.addAll(_mentionParts(text.substring(last, match.start)));
    }
    final raw = match.group(0)!;
    final trailing = _trailing.firstMatch(raw)?.group(0) ?? '';
    final clean = raw.substring(0, raw.length - trailing.length);
    parts.add(
      TextPart(
        TextPartType.link,
        clean,
        clean.toLowerCase().startsWith('http') ? clean : 'https://$clean',
      ),
    );
    if (trailing.isNotEmpty) parts.add(TextPart(TextPartType.text, trailing));
    last = match.end;
  }
  if (last < text.length) parts.addAll(_mentionParts(text.substring(last)));
  return parts.isEmpty ? [TextPart(TextPartType.text, text)] : parts;
}

List<TextPart> _mentionParts(String text) {
  final parts = <TextPart>[];
  var last = 0;
  for (final match in _mention.allMatches(text)) {
    final start = match.start + match.group(1)!.length;
    if (start > last) {
      parts.add(TextPart(TextPartType.text, text.substring(last, start)));
    }
    parts.add(TextPart(TextPartType.mention, match.group(2)!));
    last = start + match.group(2)!.length;
  }
  if (last < text.length) {
    parts.add(TextPart(TextPartType.text, text.substring(last)));
  }
  return parts;
}

class MentionOption {
  const MentionOption(this.label, this.token, this.description);
  final String label;
  final String token;
  final String description;
}

/// Participants (and @everyone when allowed) that match [query], as on web.
List<MentionOption> mentionOptions({
  required Iterable<({int id, String name, String role})> participants,
  required int currentUserId,
  required bool canMentionEveryone,
  required String query,
}) {
  final options = [
    if (canMentionEveryone)
      const MentionOption(
        'Everyone',
        '@everyone',
        'Notify everyone in this chat',
      ),
    for (final person in participants)
      if (person.id != currentUserId)
        MentionOption(
          person.name,
          '@${mentionToken(person.name)}',
          person.role,
        ),
  ];
  final needle = query.toLowerCase();
  return options
      .where(
        (option) =>
            '${option.label} ${option.token}'.toLowerCase().contains(needle),
      )
      .toList();
}

/// Replaces the `@query` at [range] with [token] and a trailing space.
({String text, int cursor}) insertMention(
  String text,
  MentionRange range,
  String token,
) {
  final before = text.substring(0, range.start);
  return (
    text: '$before$token ${text.substring(range.end)}',
    cursor: before.length + token.length + 1,
  );
}
