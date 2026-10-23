import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:step_messenger/src/data/api.dart';
import 'package:step_messenger/src/data/models.dart';
import 'package:step_messenger/src/data/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('API sends bearer tokens only to the configured server', () async {
    final api = ApiClient(
      baseUrl: 'https://school.test',
      client: MockClient((request) async {
        expect(request.url.origin, 'https://school.test');
        expect(request.headers['Authorization'], 'Bearer private-token');
        expect(request.followRedirects, isFalse);
        return http.Response('{"data":[]}', 200);
      }),
    )..token = 'private-token';
    await api.request('GET', '/api/teams/school/conversations');
    expect(
      () => api.uri('https://other.test/file'),
      throwsA(isA<ApiException>()),
    );
    expect(() => api.uri('//other.test/file'), throwsA(isA<ApiException>()));
    api.close();
  });

  test(
    'unauthorized responses expire a session and validation errors remain readable',
    () async {
      var expired = false;
      var status = 401;
      final api =
          ApiClient(
              baseUrl: 'https://school.test',
              client: MockClient(
                (_) async => http.Response(
                  status == 401
                      ? '{"message":"Unauthenticated"}'
                      : '{"errors":{"body":["A message is required."]}}',
                  status,
                ),
              ),
            )
            ..token = 'expired-token'
            ..onUnauthorized = () => expired = true;
      await expectLater(
        api.request('GET', '/api/mobile/session'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(expired, isTrue);
      status = 422;
      await expectLater(
        api.request('POST', '/api/messages'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'A message is required.',
          ),
        ),
      );
      api.close();
    },
  );

  test(
    'pagination is derived from server metadata and unsent content stays hidden',
    () {
      final page = PageData.from({
        'data': [
          {'id': 7, 'body': '', 'unsent_at': '2026-09-07T00:00:00Z'},
        ],
        'current_page': 2,
        'next_page_url': 'https://school.test/messages?page=3',
      }, ChatMessage.new);
      expect(page.next, 3);
      expect(page.items.single.preview, 'Message unsent');
      expect(page.items.single.sender, isNull);
    },
  );

  test('mobile sessions are pinned to the official Uhoo! server', () {
    expect(SessionController.officialBaseUrl, 'https://uhoo.udd.edu.ph');
  });

  test('sessions saved for another server are discarded', () async {
    FlutterSecureStorage.setMockInitialValues({
      'step.session': jsonEncode({
        'server': 'https://old-messenger.test',
        'token': 'old-server-token',
      }),
    });
    const storage = FlutterSecureStorage();
    final session = SessionController(storage: storage);

    await session.restore();

    expect(session.hasSavedSession, isFalse);
    expect(await storage.read(key: 'step.session'), isNull);
    session.dispose();
  });

  test('status and receipt labels use the web app wording', () {
    final now = DateTime(2026, 10, 20, 12);
    expect(
      relativeLastSeen(now.subtract(const Duration(seconds: 20)), now),
      'just now',
    );
    expect(
      relativeLastSeen(now.subtract(const Duration(minutes: 5)), now),
      '5 min ago',
    );
    expect(
      relativeLastSeen(now.subtract(const Duration(hours: 1)), now),
      '1 hour ago',
    );
    expect(
      seenLabel(now.subtract(const Duration(minutes: 1)), now),
      'Seen 1 Minute Ago',
    );
    expect(
      seenLabel(now.subtract(const Duration(days: 3)), now),
      'Seen 3 Days Ago',
    );

    final group = Conversation({
      'type': 'group',
      'participants': [
        {'id': 1, 'name': 'Me'},
        {'id': 2, 'name': 'Ana'},
        {'id': 3, 'name': 'Ben'},
      ],
    });
    expect(conversationStatus(group, 1, DateTime.now()), '3 members');
    final direct = Conversation({
      'type': 'direct',
      'participants': [
        {'id': 1, 'name': 'Me'},
        {
          'id': 2,
          'name': 'Ana',
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    });
    expect(conversationStatus(direct, 1, DateTime.now()), 'Active now');

    Json own(
      int id, {
      List<Json> read = const [],
      List<Json> delivered = const [],
    }) => {
      'id': id,
      'sender': {'id': 1, 'name': 'Me'},
      'read_by': read,
      'delivered_to': delivered,
    };
    final statuses = deliveryStatuses(
      [
        ChatMessage(own(9)),
        ChatMessage(
          own(
            8,
            delivered: [
              {'id': 2},
            ],
          ),
        ),
        ChatMessage(
          own(
            7,
            read: [
              {
                'id': 2,
                'read_at': now
                    .subtract(const Duration(minutes: 2))
                    .toIso8601String(),
              },
            ],
          ),
        ),
      ],
      1,
      now,
    );
    expect(statuses, {9: 'Sent', 8: 'Delivered', 7: 'Seen 2 Minutes Ago'});
  });

  test('message receipts group seen, delivered and pending like the web', () {
    final chat = Conversation({
      'type': 'group',
      'participants': [
        {'id': 1, 'name': 'Me'},
        {'id': 2, 'name': 'Ana', 'nickname': 'Annie'},
        {'id': 3, 'name': 'Ben'},
        {'id': 4, 'name': 'Cara'},
      ],
    });
    final message = ChatMessage({
      'id': 7,
      'sender': {'id': 1, 'name': 'Me'},
      'read_by': [
        {'id': 2, 'name': 'Ana', 'read_at': '2026-10-23T03:00:00Z'},
      ],
      'delivered_to': [
        {'id': 2, 'name': 'Ana', 'delivered_at': '2026-10-23T02:59:00Z'},
        {'id': 3, 'name': 'Ben', 'delivered_at': '2026-10-23T02:58:00Z'},
      ],
    });
    final receipts = messageReceipts(message, chat);
    expect(receipts.seen.map((r) => r.name), ['Annie']);
    expect(receipts.delivered.map((r) => r.name), ['Ben']);
    expect(receipts.pending.map((r) => r.name), ['Cara']);
  });
}
