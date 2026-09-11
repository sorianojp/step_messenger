import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api.dart';
import 'models.dart';

/// Fetch personalized data over HTTP after receiving a Reverb event.
class RealtimeClient {
  RealtimeClient(this.api, this.config);
  final ApiClient api;
  final Json config;
  final _events = StreamController<Json>.broadcast();
  Stream<Json> get events => _events.stream;
  WebSocketChannel? _socket;
  Timer? _retry;
  Timer? _heartbeat;
  Timer? _handshakeTimeout;
  Timer? _authorizationRetry;
  DateTime _lastFrame = DateTime.now();
  String? _socketId;
  final Set<String> _channels = {};
  final Set<String> _subscribed = {};
  final Set<String> _readyChannels = {};
  bool _stopped = true;
  int _attempt = 0;
  int _generation = 0;

  void subscribe(String channel) {
    _channels.add(channel);
    _authorize(channel);
  }

  void unsubscribe(String channel) {
    _channels.remove(channel);
    _subscribed.remove(channel);
    _readyChannels.remove(channel);
    if (_socketId != null) _send('pusher:unsubscribe', {'channel': channel});
  }

  /// Echo's whisper('typing') uses client events on a presence channel.
  void typing(int conversationId, int userId, String name, bool typing) {
    final channel = 'presence-conversations.$conversationId';
    if (!_readyChannels.contains(channel) || _stopped) return;
    _send('client-typing', {
      'id': userId,
      'name': name,
      'typing': typing,
    }, channel: channel);
  }

  void start() {
    if (!_stopped) return;
    _stopped = false;
    _connect();
  }

  Future<void> _connect() async {
    final generation = ++_generation;
    try {
      var host = config['host'] as String? ?? Uri.parse(api.baseUrl).host;
      if (['localhost', '127.0.0.1', '0.0.0.0'].contains(host)) {
        host = Uri.parse(api.baseUrl).host;
      }
      final uri = Uri(
        scheme: config['scheme'] == 'https' ? 'wss' : 'ws',
        host: host,
        port: int.tryParse('${config['port']}'),
        path: '/app/${config['key']}',
        queryParameters: {
          'protocol': '7',
          'client': 'step-flutter',
          'version': '1.0',
          'flash': 'false',
        },
      );
      final socket = WebSocketChannel.connect(uri);
      _socket = socket;
      _handshakeTimeout?.cancel();
      _handshakeTimeout = Timer(
        const Duration(seconds: 15),
        () => _disconnected(generation),
      );
      socket.stream.listen(
        (raw) {
          if (generation != _generation) return;
          try {
            final event = jsonDecode(raw as String) as Json;
            _lastFrame = DateTime.now();
            final data = event['data'] is String
                ? jsonDecode(event['data'] as String)
                : event['data'];
            if (event['event'] == 'pusher:connection_established') {
              _handshakeTimeout?.cancel();
              _socketId = (data as Map)['socket_id'] as String;
              _attempt = 0;
              for (final channel in _channels) {
                _authorize(channel);
              }
              _heartbeat?.cancel();
              _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
                if (DateTime.now().difference(_lastFrame).inSeconds > 60) {
                  _disconnected(generation);
                } else {
                  _send('pusher:ping', {});
                }
              });
              _events.add({'event': 'connected'});
            } else if (event['event'] ==
                'pusher_internal:subscription_succeeded') {
              final channel = event['channel'] as String;
              if (_channels.contains(channel)) {
                _readyChannels.add(channel);
                _events.add({'event': 'subscribed', 'channel': channel});
              }
            } else if (event['event'] == 'pusher:ping') {
              _send('pusher:pong', {});
            } else if (!(event['event'] as String).startsWith('pusher')) {
              _events.add({...event, 'data': data});
            }
          } catch (_) {
            /* Malformed frames are ignored. HTTP remains authoritative. */
          }
        },
        onError: (Object _) => _disconnected(generation),
        onDone: () => _disconnected(generation),
      );
      await socket.ready;
    } catch (_) {
      _disconnected(generation);
    }
  }

  Future<void> _authorize(String channel) async {
    final socketId = _socketId;
    if (socketId == null || _subscribed.contains(channel) || _stopped) return;
    _subscribed.add(channel);
    try {
      final auth = await api.request(
        'POST',
        '/api/mobile/broadcasting/auth',
        body: {'socket_id': socketId, 'channel_name': channel},
      );
      if (_socketId == socketId && !_stopped && _channels.contains(channel)) {
        _send('pusher:subscribe', {'channel': channel, ...auth});
      }
    } catch (_) {
      if (_socketId == socketId && !_stopped) {
        _subscribed.remove(channel);
        _authorizationRetry?.cancel();
        _authorizationRetry = Timer(const Duration(seconds: 5), () {
          for (final pending in _channels) {
            _authorize(pending);
          }
        });
      }
    }
  }

  void _send(String event, Json data, {String? channel}) {
    try {
      _socket?.sink.add(
        jsonEncode({'event': event, 'data': data, 'channel': ?channel}),
      );
    } catch (_) {
      /* Reconnect on close. */
    }
  }

  void _disconnected(int generation) {
    if (generation != _generation || _stopped) return;
    _generation++;
    _socketId = null;
    _subscribed.clear();
    _readyChannels.clear();
    _heartbeat?.cancel();
    _handshakeTimeout?.cancel();
    _authorizationRetry?.cancel();
    _socket?.sink.close();
    _retry?.cancel();
    _retry = Timer(
      Duration(seconds: (2 << _attempt.clamp(0, 4)).clamp(2, 30)),
      _connect,
    );
    _attempt++;
  }

  void stop() {
    _stopped = true;
    _generation++;
    _retry?.cancel();
    _heartbeat?.cancel();
    _handshakeTimeout?.cancel();
    _authorizationRetry?.cancel();
    _socket?.sink.close();
    _socket = null;
    _socketId = null;
    _subscribed.clear();
    _readyChannels.clear();
  }

  void dispose() {
    stop();
    _events.close();
  }
}
