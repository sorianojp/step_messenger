import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:step_messenger/src/data/api.dart';
import 'package:step_messenger/src/data/models.dart';
import 'package:step_messenger/src/data/realtime.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
  stdout.writeln('PASS $label');
}

Future<void> rejects(Future<Object?> request, int status, String label) async {
  try {
    await request;
  } on ApiException catch (error) {
    check(error.status == status, label);
    return;
  }
  throw StateError('Expected rejection: $label');
}

Future<Json> nextEvent(
  RealtimeClient client,
  String event, {
  String? channel,
}) => client.events
    .firstWhere(
      (item) =>
          item['event'] == event &&
          (channel == null || item['channel'] == channel),
    )
    .timeout(const Duration(seconds: 15));

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Run tool/check_backend.py to create an isolated fixture.',
    );
  }
  final fixture =
      jsonDecode(await File(arguments.single).readAsString()) as Json;
  final api = <String, ApiClient>{};
  final sockets = <RealtimeClient>[];
  try {
    for (final name in ['alice', 'bob', 'outsider']) {
      api[name] = ApiClient(baseUrl: fixture['base_url'] as String)
        ..token = (fixture[name] as Json)['token'] as String;
    }
    final alice = api['alice']!;
    final bob = api['bob']!;
    final outsider = api['outsider']!;
    final base = '/api/teams/${fixture['team_slug']}';
    final conversation = '$base/conversations/${fixture['conversation_id']}';
    final session = await alice.request('GET', '/api/mobile/session');
    check(
      (session['user'] as Json)['id'] == (fixture['alice'] as Json)['id'],
      'Bearer session identifies the device user',
    );
    final contacts = await alice.request(
      'GET',
      '$base/contacts?search=Smoke%20Bob',
    );
    check(
      records(contacts['data']).single['id'] == (fixture['bob'] as Json)['id'],
      'School directory search',
    );
    await rejects(
      outsider.request('GET', conversation),
      403,
      'Outsider cannot read the conversation',
    );
    final history = PageData.from(
      await bob.request('GET', '$conversation/messages'),
      ChatMessage.new,
    );
    check(
      history.items.length == 40 && history.next == 2,
      'Message history pagination',
    );
    final older = PageData.from(
      await bob.request('GET', '$conversation/messages?page=2'),
      ChatMessage.new,
    );
    check(
      older.items.length == 5 && older.next == null,
      'Earlier messages are accessible',
    );

    final config = session['realtime'] as Json;
    final a = RealtimeClient(alice, config);
    final b = RealtimeClient(bob, config);
    sockets.addAll([a, b]);
    final privateChannel =
        'private-conversations.${fixture['conversation_id']}';
    final presenceChannel =
        'presence-conversations.${fixture['conversation_id']}';
    final subscriptions = [
      for (final client in sockets) ...[
        nextEvent(client, 'subscribed', channel: privateChannel),
        nextEvent(client, 'subscribed', channel: presenceChannel),
      ],
    ];
    for (final client in sockets) {
      client.subscribe(privateChannel);
      client.subscribe(presenceChannel);
      client.start();
    }
    await Future.wait(subscriptions);
    check(
      true,
      'Both clients authorize real Reverb private and presence channels',
    );
    final typing = nextEvent(b, 'client-typing', channel: presenceChannel);
    final identity = fixture['alice'] as Json;
    a.typing(
      fixture['conversation_id'] as int,
      identity['id'] as int,
      identity['name'] as String,
      true,
    );
    check(
      ((await typing)['data'] as Json)['typing'] == true,
      'Echo-compatible typing reaches the other client',
    );
    final stopped = nextEvent(b, 'client-typing', channel: presenceChannel);
    a.typing(
      fixture['conversation_id'] as int,
      identity['id'] as int,
      identity['name'] as String,
      false,
    );
    check(
      ((await stopped)['data'] as Json)['typing'] == false,
      'Typing stops explicitly',
    );

    final created = nextEvent(b, 'message.created', channel: privateChannel);
    final sent = await alice.request(
      'POST',
      '$conversation/messages',
      body: {'body': 'Mobile integration message'},
    );
    final message = sent['data'] as Json;
    check(
      ((await created)['data'] as Json)['message']['id'] == message['id'],
      'HTTP send delivers a real broadcast to the other client',
    );
    await bob.request('PATCH', '$conversation/read');
    final afterRead = await alice.request('GET', '$conversation/messages');
    check(
      ChatMessage(
        records(afterRead['data']).firstWhere((m) => m['id'] == message['id']),
      ).read,
      'Read receipt reaches the API payload',
    );
    await bob.request(
      'PATCH',
      '$conversation/messages/${message['id']}/reaction',
      body: {'emoji': '👍'},
    );
    final reacted = await bob.request('GET', '$conversation/messages');
    check(
      ChatMessage(
            records(
              reacted['data'],
            ).firstWhere((m) => m['id'] == message['id']),
          ).reactions.single['reacted_by_me'] ==
          true,
      'Reactions are personalized for the viewer',
    );
    await alice.request(
      'PATCH',
      '$conversation/messages/${message['id']}',
      body: {'body': 'Edited integration message'},
    );
    final searched = await bob.request(
      'GET',
      '$conversation/messages?search=Edited%20integration',
    );
    check(
      records(searched['data']).single['id'] == message['id'],
      'Message editing and server search',
    );

    final source = File('${File(arguments.single).parent.path}/attachment.txt');
    await source.writeAsString('Isolated attachment round trip.');
    final upload = await alice.upload(
      '$conversation/messages',
      {'body': 'File integration'},
      [source.path],
    );
    final attachmentMessage = upload['data'] as Json;
    final attachment = records(attachmentMessage['attachments']).single;
    final bytes = await bob.download(
      '$conversation/messages/${attachmentMessage['id']}/attachments/${attachment['id']}',
    );
    check(
      utf8.decode(bytes) == 'Isolated attachment round trip.',
      'Authenticated attachment upload and download',
    );
    await rejects(
      outsider.download(
        '$conversation/messages/${attachmentMessage['id']}/attachments/${attachment['id']}',
      ),
      403,
      'Outsider cannot download attachments',
    );
    final shared =
        (await alice.request('GET', '$conversation/shared'))['data'] as Json;
    check(
      records(shared['files']).any((item) => item['id'] == attachment['id']),
      'Shared files include uploaded attachment',
    );
    final group =
        (await alice.request(
              'POST',
              '$base/conversations',
              body: {
                'type': 'group',
                'title': 'Mobile customization test',
                'participant_ids': [(fixture['bob'] as Json)['id']],
              },
            ))['data']
            as Json;
    final groupPath = '$base/conversations/${group['id']}';
    await alice.request(
      'POST',
      '$groupPath/members',
      body: {
        'user_ids': [(fixture['bob'] as Json)['id']],
      },
    );
    check(true, 'Group member request accepts user_ids');
    final nickname =
        (await alice.request(
              'PATCH',
              '$groupPath/members/${(fixture['bob'] as Json)['id']}/nickname',
              body: {'nickname': 'Study buddy'},
            ))['data']
            as Json;
    check(
      records(
        nickname['participants'],
      ).any((p) => p['nickname'] == 'Study buddy'),
      'Owner can set a group nickname',
    );
    await rejects(
      bob.request(
        'PATCH',
        '$groupPath/members/${(fixture['alice'] as Json)['id']}/nickname',
        body: {'nickname': 'Not allowed'},
      ),
      403,
      'Members cannot customize group nicknames',
    );
    final cleared =
        (await alice.request(
              'PATCH',
              '$groupPath/members/${(fixture['bob'] as Json)['id']}/nickname',
              body: {'nickname': null},
            ))['data']
            as Json;
    check(
      records(cleared['participants']).every((p) => p['nickname'] == null),
      'Owner can clear a nickname',
    );
    final photo = File('${File(arguments.single).parent.path}/group.png');
    await photo.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
      ),
    );
    final photoResult = await alice.upload('$groupPath/photo', {}, [
      photo.path,
    ], field: 'photo');
    check(
      (photoResult['data'] as Json)['photo_url'] != null &&
          (await bob.download('$groupPath/photo')).isNotEmpty,
      'Group photo upload and authenticated display',
    );
    await rejects(
      outsider.download('$groupPath/photo'),
      403,
      'Outsider cannot view group photo',
    );
    await alice.request('DELETE', '$groupPath/photo');
    await rejects(
      bob.download('$groupPath/photo'),
      404,
      'Removing group photo removes access to its bytes',
    );
    final poll =
        (await alice.request(
              'POST',
              '$conversation/polls',
              body: {
                'question': 'Integration poll?',
                'options': ['Yes', 'No'],
              },
            ))['data']
            as Json;
    final option = records((poll['poll'] as Json)['options']).first['id'];
    final vote = await bob.request(
      'PATCH',
      '$conversation/messages/${poll['id']}/poll-vote',
      body: {
        'option_ids': [option],
      },
    );
    check(
      (vote['data'] as Json)['poll']['total_voters'] == 1,
      'Poll creation and voting',
    );
    b.stop();
    final reconnected = nextEvent(b, 'subscribed', channel: presenceChannel);
    b.start();
    await reconnected;
    check(true, 'Reconnection restores channel authorization');
    await bob.request('DELETE', '/api/mobile/session');
    await rejects(
      bob.request('GET', '/api/mobile/session'),
      401,
      'Device logout revokes the real token',
    );
  } finally {
    for (final socket in sockets) {
      socket.dispose();
    }
    for (final client in api.values) {
      client.close();
    }
  }
}
