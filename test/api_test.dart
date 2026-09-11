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

  test('mobile sessions are pinned to the official Messenger server', () {
    expect(SessionController.officialBaseUrl, 'https://messenger.udd.edu.ph');
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
}
