import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:step_messenger/src/app.dart';
import 'package:step_messenger/src/ui/conversation_details.dart';
import 'package:step_messenger/src/data/api.dart';
import 'package:step_messenger/src/data/models.dart';
import 'package:step_messenger/src/data/realtime.dart';
import 'package:step_messenger/src/data/session.dart';

class TestSession extends SessionController {
  TestSession(this.client) {
    user = Person({
      'id': 1,
      'name': 'Alex Student',
      'email': 'alex@school.test',
      'school_role': 'student',
    });
    team = Team({'id': 1, 'name': 'STEP Community', 'slug': 'school'});
    teams = [team!];
    loading = false;
    client.onUnauthorized = expire;
  }
  final ApiClient client;
  @override
  ApiClient get api => client;
  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}

class TestRealtime extends RealtimeClient {
  TestRealtime(ApiClient api) : super(api, {});
  final updates = StreamController<Json>.broadcast();
  final typingUpdates = <bool>[];
  @override
  Stream<Json> get events => updates.stream;
  @override
  void subscribe(String channel) {}
  @override
  void unsubscribe(String channel) {}
  @override
  void typing(int conversationId, int userId, String name, bool typing) {
    typingUpdates.add(typing);
  }

  @override
  void dispose() {
    updates.close();
    super.dispose();
  }
}

Json message(int id, String body, {int sender = 2}) => {
  'id': id,
  'conversation_id': 9,
  'body': body,
  'type': 'text',
  'sender': {
    'id': sender,
    'name': sender == 1 ? 'Alex Student' : 'Jane Teacher',
  },
  'created_at': '2026-09-07T08:00:00Z',
  'attachments': [],
  'reactions': [],
};
Json conversation() => {
  'id': 9,
  'display_name': 'Jane Teacher',
  'type': 'direct',
  'unread_count': 1,
  'participants': [
    {'id': 1, 'name': 'Alex Student'},
    {'id': 2, 'name': 'Jane Teacher'},
  ],
  'latest_message': message(7, 'Welcome to class!'),
  'permissions': {'can_pin_messages': true},
};
Json page(List<Json> items) => {
  'data': items,
  'current_page': 1,
  'next_page_url': null,
};

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'group details add members and clear nicknames with the API contract',
    (tester) async {
      final group = conversation()
        ..['type'] = 'group'
        ..['permissions'] = {
          'can_add_members': true,
          'can_customize_group': true,
        };
      (group['participants'] as List).first['nickname'] = 'Alex';
      final writes = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://school.test',
        client: MockClient((request) async {
          if (request.method != 'GET') {
            writes.add(request);
            return http.Response(jsonEncode({'data': group}), 200);
          }
          if (request.url.path.endsWith('/contacts')) {
            return http.Response(
              jsonEncode(
                page([
                  {'id': 3, 'name': 'New Classmate'},
                ]),
              ),
              200,
            );
          }
          if (request.url.path.endsWith('/pinned')) {
            return http.Response('{"data":[]}', 200);
          }
          return http.Response(jsonEncode({'data': group}), 200);
        }),
      );
      final session = TestSession(client);
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationDetails(
            session: session,
            conversation: Conversation(group),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Add'), 200);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Classmate'));
      await tester.pump();
      await tester.tap(find.text('Add to group'));
      await tester.pumpAndSettle();
      expect(jsonDecode(writes.single.body), {
        'user_ids': [3],
      });
      await tester.scrollUntilVisible(find.text('Alex Student (you)'), 200);
      await tester.tap(find.text('Alex Student (you)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(writes.last.url.path, endsWith('/members/1/nickname'));
      expect(jsonDecode(writes.last.body), {'nickname': null});
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'typing uses member names, expires, and stops when the composer is idle',
    (tester) async {
      final client = ApiClient(
        baseUrl: 'https://school.test',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/conversations')) {
            return http.Response(jsonEncode(page([conversation()])), 200);
          }
          if (request.url.path.endsWith('/messages')) {
            return http.Response(
              jsonEncode(page([message(7, 'Welcome to class!')])),
              200,
            );
          }
          return http.Response('{"data":{}}', 200);
        }),
      );
      final session = TestSession(client);
      final realtime = TestRealtime(client);
      session.realtime = realtime;
      await tester.pumpWidget(UhooApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jane Teacher').first);
      await tester.pumpAndSettle();
      realtime.updates.add({
        'event': 'client-typing',
        'channel': 'presence-conversations.9',
        'user_id': '2',
        'data': {'id': 2, 'name': 'Untrusted name', 'typing': true},
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('Jane Teacher is typing…'), findsOneWidget);
      expect(find.textContaining('Untrusted name'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Jane Teacher is typing…'), findsNothing);
      final composer = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Message…',
      );
      await tester.enterText(composer, 'Hello');
      await tester.pump();
      expect(realtime.typingUpdates.last, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(realtime.typingUpdates.last, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('sign in fits a narrow screen without showing the server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = SessionController();
    await session.restore();
    await tester.pumpWidget(UhooApp(session: session));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/logo.png',
      ),
      findsOneWidget,
    );
    expect(find.text('Welcome to Uhoo!'), findsOneWidget);
    expect(find.text('Stay connected to your school.'), findsOneWidget);
    expect(
      find.textContaining('Messages, class updates'),
      findsNothing,
    );
    expect(find.text('uhoo.udd.edu.ph'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('chat preserves a failed draft and sends a reply on retry', (
    tester,
  ) async {
    var failSend = true;
    final messages = [message(7, 'Welcome to class!')];
    Json? sent;
    final client = ApiClient(
      baseUrl: 'https://school.test',
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/presence') || path.endsWith('/read')) {
          return http.Response('{"data":{}}', 200);
        }
        if (path.endsWith('/conversations')) {
          return http.Response(jsonEncode(page([conversation()])), 200);
        }
        if (path.endsWith('/messages') && request.method == 'GET') {
          return http.Response(jsonEncode(page(messages)), 200);
        }
        if (path.endsWith('/messages') && request.method == 'POST') {
          sent = jsonDecode(request.body) as Json;
          if (failSend) return http.Response('{"message":"Unavailable"}', 503);
          final added = message(8, sent!['body'] as String, sender: 1);
          messages.insert(0, added);
          return http.Response(jsonEncode({'data': added}), 201);
        }
        return http.Response('{"message":"Unexpected request"}', 404);
      }),
    );
    final session = TestSession(client);
    await tester.pumpWidget(UhooApp(session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jane Teacher').first);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Welcome to class!'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    final composer = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Message…',
    );
    await tester.enterText(composer, 'Thank you!');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(
      (tester.widget(composer) as TextField).controller!.text,
      'Thank you!',
    );
    expect(sent?['reply_to_message_id'], 7);
    // Let the error snackbar dismiss before tapping the composer underneath.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    failSend = false;
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect((tester.widget(composer) as TextField).controller!.text, isEmpty);
    expect(find.text('Thank you!'), findsOneWidget);
    expect(find.text('Replying to Jane Teacher'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
