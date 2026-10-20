import 'package:flutter_test/flutter_test.dart';
import 'package:step_messenger/src/data/message_text.dart';

void main() {
  test('mention tokens drop whitespace like the web composer', () {
    expect(mentionToken('  Maria  Clara Santos '), 'MariaClaraSantos');
  });

  test('finds the mention being typed at the cursor', () {
    final range = mentionRangeAtCursor('Hi @Mar', 7)!;
    expect([range.start, range.end, range.query], [3, 7, 'Mar']);
    expect(mentionRangeAtCursor('@', 1)!.query, '');
    expect(mentionRangeAtCursor('email@school', 12), isNull);
    expect(mentionRangeAtCursor('Hi @Mar there', 13), isNull);
  });

  test('splits links, trailing punctuation and mentions', () {
    expect(messageTextParts('See www.udd.edu.ph, @everyone!'), const [
      TextPart(TextPartType.text, 'See '),
      TextPart(TextPartType.link, 'www.udd.edu.ph', 'https://www.udd.edu.ph'),
      TextPart(TextPartType.text, ','),
      TextPart(TextPartType.text, ' '),
      TextPart(TextPartType.mention, '@everyone'),
      TextPart(TextPartType.text, '!'),
    ]);
  });

  test('does not treat email addresses as mentions', () {
    expect(messageTextParts('mail a@b.com'), const [
      TextPart(TextPartType.text, 'mail a@b.com'),
    ]);
  });

  test('filters mention options and inserts the chosen token', () {
    final options = mentionOptions(
      participants: [
        (id: 1, name: 'Me Myself', role: 'teacher'),
        (id: 2, name: 'Maria Clara', role: 'student'),
        (id: 3, name: 'Jose Rizal', role: 'student'),
      ],
      currentUserId: 1,
      canMentionEveryone: true,
      query: 'mar',
    );
    expect(options.map((o) => o.token), ['@MariaClara']);
    final everyone = mentionOptions(
      participants: const [],
      currentUserId: 1,
      canMentionEveryone: true,
      query: '',
    );
    expect(everyone.single.token, '@everyone');

    final inserted = insertMention(
      'Hi @Mar!',
      mentionRangeAtCursor('Hi @Mar!', 7)!,
      '@MariaClara',
    );
    expect(inserted.text, 'Hi @MariaClara !');
    expect(inserted.cursor, 15);
  });
}
