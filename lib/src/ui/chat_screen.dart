import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'attachment_viewer.dart';
import 'conversation_avatar.dart';
import 'package:path_provider/path_provider.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'conversation_details.dart';
import 'interactive_composer.dart';
import 'message_bubble.dart';
import 'widgets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.session,
    required this.conversation,
  });
  final SessionController session;
  final Conversation conversation;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late Conversation _conversation = widget.conversation;
  final _body = TextEditingController();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = [];
  List<_PendingFile> _files = [];
  ChatMessage? _reply;
  ChatMessage? _editing;
  int? _next;
  int? _readId;
  int _generation = 0;
  bool _loading = true;
  bool _moreLoading = false;
  bool _sending = false;
  bool _searching = false;
  bool _refreshing = false;
  Object? _error;
  Timer? _poll;
  Timer? _debounce;
  Timer? _typingStop;
  DateTime? _lastTypingSent;
  final Map<int, String> _typingPeople = {};
  final Map<int, Timer> _typingExpiry = {};
  StreamSubscription<Json>? _events;
  SessionController get session => widget.session;
  late final String _path =
      '${session.teamPath}/conversations/${_conversation.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    session.realtime?.subscribe('private-conversations.${_conversation.id}');
    session.realtime?.subscribe('presence-conversations.${_conversation.id}');
    _events = session.realtime?.events.listen((event) {
      if (event['event'] == 'client-typing' &&
          event['channel'] == 'presence-conversations.${_conversation.id}') {
        _receiveTyping(event);
        return;
      }
      if (event['event'] == 'connected' ||
          event['channel'] == 'private-conversations.${_conversation.id}') {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), _load);
      }
    });
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (session.foreground) _load();
    });
  }

  void _receiveTyping(Json event) {
    final data = event['data'];
    if (data is! Map || data['id'] is! int) return;
    final id = data['id'] as int;
    if (id == session.user?.id ||
        (event['user_id'] != null && '${event['user_id']}' != '$id')) {
      return;
    }
    final participant = _conversation.participants
        .where((p) => p.id == id)
        .firstOrNull;
    if (participant == null) return;
    _typingExpiry.remove(id)?.cancel();
    setState(() {
      if (data['typing'] == true) {
        _typingPeople[id] = participant.name;
      } else {
        _typingPeople.remove(id);
      }
    });
    if (data['typing'] == true) {
      _typingExpiry[id] = Timer(const Duration(seconds: 4), () {
        _typingExpiry.remove(id);
        if (mounted) setState(() => _typingPeople.remove(id));
      });
    }
  }

  void _composerChanged() {
    setState(() {});
    if (_body.text.trim().isEmpty || _editing != null) {
      _stopTyping();
      return;
    }
    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!).inMilliseconds >= 1000) {
      final user = session.user;
      if (user != null) {
        session.realtime?.typing(_conversation.id, user.id, user.name, true);
      }
      _lastTypingSent = now;
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    _typingStop?.cancel();
    if (_lastTypingSent != null) {
      final user = session.user;
      if (user != null) {
        session.realtime?.typing(_conversation.id, user.id, user.name, false);
      }
      _lastTypingSent = null;
    }
  }

  String get _typingLabel => _typingPeople.length == 1
      ? '${_typingPeople.values.first} is typing…'
      : 'Several people are typing…';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopTyping();
      for (final timer in _typingExpiry.values) {
        timer.cancel();
      }
      _typingExpiry.clear();
      setState(_typingPeople.clear);
    }
  }

  Future<void> _load({bool more = false, bool reset = false}) async {
    if (more && _moreLoading || !more && _refreshing && !reset) return;
    if (more) {
      setState(() => _moreLoading = true);
    } else {
      _refreshing = true;
    }
    final generation = reset ? ++_generation : _generation;
    final query = _searching ? _search.text.trim() : '';
    try {
      final result = await session.api.request(
        'GET',
        '$_path/messages?page=${more ? _next : 1}&search=${Uri.encodeQueryComponent(query)}',
      );
      final page = PageData.from(result, ChatMessage.new);
      if (!mounted || generation != _generation) return;
      setState(() {
        final merged = {
          if (!reset)
            for (final m in _messages) m.id: m,
          for (final m in page.items) m.id: m,
        };
        _messages = merged.values.toList()
          ..sort((a, b) => b.id.compareTo(a.id));
        if (more || reset || _messages.length <= 40) _next = page.next;
        _error = null;
      });
      if (!more &&
          !_searching &&
          session.foreground &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        final latest = page.items.firstOrNull?.id;
        if (latest != null && _readId != latest) {
          await session.api.request('PATCH', '$_path/read');
          _readId = latest;
        }
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (more) {
        if (mounted) setState(() => _moreLoading = false);
      } else {
        _refreshing = false;
      }
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _send() async {
    final text = _body.text.trim();
    if (_sending || (text.isEmpty && _files.isEmpty)) return;
    if (text.length > 5000) {
      showError(
        context,
        const ApiException('Messages can contain up to 5,000 characters.'),
      );
      return;
    }
    setState(() => _sending = true);
    _stopTyping();
    try {
      Json result;
      if (_editing != null) {
        result = await session.api.request(
          'PATCH',
          '$_path/messages/${_editing!.id}',
          body: {'body': text},
        );
      } else if (_files.isNotEmpty) {
        result = await session.api.upload('$_path/messages', {
          'body': text,
          if (_reply != null) 'reply_to_message_id': '${_reply!.id}',
        }, _files.map((f) => f.path).toList());
      } else {
        result = await session.api.request(
          'POST',
          '$_path/messages',
          body: {
            'body': text,
            if (_reply != null) 'reply_to_message_id': _reply!.id,
          },
        );
      }
      if (!mounted) return;
      final message = ChatMessage(result['data'] as Json);
      setState(() {
        _messages = {
          for (final m in _messages) m.id: m,
          message.id: message,
        }.values.toList()..sort((a, b) => b.id.compareTo(a.id));
        _body.clear();
        _files = [];
        _reply = null;
        _editing = null;
        _readId = message.id;
      });
      // Reset search so the newly sent message is visible in its conversation.
      if (_searching) {
        setState(() {
          _searching = false;
          _search.clear();
        });
        await _load(reset: true);
      }
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.pickFiles();
      if (!mounted) return;
      final sizes = await Future.wait(result.map((file) => file.length()));
      if (_files.length + result.length > 5 ||
          sizes.any((size) => size > 20 * 1024 * 1024)) {
        throw const ApiException(
          'Choose up to 5 files, each no larger than 20 MB.',
        );
      }
      final temp = await getTemporaryDirectory();
      final directory = await Directory(
        '${temp.path}/step_messenger/uploads/${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
      final files = <_PendingFile>[..._files];
      for (var index = 0; index < result.length; index++) {
        final picked = result[index];
        final safeName = picked.name.replaceAll(
          RegExp(r'[^a-zA-Z0-9._-]'),
          '_',
        );
        final file = File('${directory.path}/${index}_$safeName');
        await file.writeAsBytes(await picked.readAsBytes());
        files.add(_PendingFile(picked.name, file.path));
      }
      if (!mounted) return;
      setState(() => _files = files);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _attachment(ChatMessage message, Json attachment) =>
      openAttachment(context, session, _path, message.id, attachment);

  Future<void> _mutate(String method, String path, [Json? body]) async {
    try {
      await session.api.request(method, path, body: body);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _react(ChatMessage message, String emoji) async {
    final selected = message.reactions.any(
      (r) => r['emoji'] == emoji && r['reacted_by_me'] == true,
    );
    await _mutate(
      selected ? 'DELETE' : 'PATCH',
      '$_path/messages/${message.id}/reaction',
      selected ? null : {'emoji': emoji},
    );
  }

  Future<void> _actions(ChatMessage message) async {
    final mine = message.sender?.id == session.user!.id;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: Wrap(
                  spacing: 5,
                  children: [
                    for (final emoji in ['👍', '❤️', '😂', '😮', '🙏', '✅'])
                      TextButton(
                        onPressed: () => Navigator.pop(context, emoji),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 25),
                        ),
                      ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () => Navigator.pop(context, 'reply'),
              ),
              if (message.body.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copy text'),
                  onTap: () => Navigator.pop(context, 'copy'),
                ),
              ListTile(
                leading: const Icon(Icons.forward_outlined),
                title: const Text('Forward'),
                onTap: () => Navigator.pop(context, 'forward'),
              ),
              if (_conversation.can('can_pin_messages'))
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(message.pinned ? 'Unpin message' : 'Pin message'),
                  onTap: () => Navigator.pop(context, 'pin'),
                ),
              if (mine && ['text', 'attachment'].contains(message.type))
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit message'),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Unsend for everyone'),
                  onTap: () => Navigator.pop(context, 'unsend'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'reply':
        setState(() {
          _reply = message;
          _editing = null;
        });
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
      case 'edit':
        setState(() {
          _editing = message;
          _reply = null;
          _files = [];
          _body.text = message.body;
        });
      case 'pin':
        await _mutate('PATCH', '$_path/messages/${message.id}/pin', {
          'pinned': !message.pinned,
        });
      case 'unsend':
        if (await confirmAction(
          context,
          'Unsend message?',
          'This message will be removed for everyone in the conversation.',
          'Unsend',
        )) {
          await _mutate('DELETE', '$_path/messages/${message.id}');
        }
      case 'forward':
        await _forward(message);
      default:
        await _react(message, action);
    }
  }

  Future<void> _forward(ChatMessage message) async {
    try {
      final conversations = <Conversation>[];
      int? page = 1;
      do {
        final result = PageData.from(
          await session.api.request(
            'GET',
            '${session.teamPath}/conversations?page=$page',
          ),
          Conversation.new,
        );
        conversations.addAll(result.items);
        page = result.next;
      } while (page != null);
      if (!mounted) return;
      final target = await showModalBottomSheet<Conversation>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Forward to',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final c in conversations)
                ListTile(
                  leading: ConversationAvatar(
                    session: session,
                    conversation: c,
                    size: 36,
                  ),
                  title: Text(c.name),
                  onTap: () => Navigator.pop(context, c),
                ),
            ],
          ),
        ),
      );
      if (target != null) {
        await session.api.request(
          'POST',
          '$_path/messages/${message.id}/forward',
          body: {
            'conversation_ids': [target.id],
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Forwarded to ${target.name}')),
          );
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _add() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Photos and files'),
              onTap: () => Navigator.pop(context, 'files'),
            ),
            ListTile(
              leading: const Icon(Icons.poll_outlined),
              title: const Text('Create a poll'),
              onTap: () => Navigator.pop(context, 'polls'),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Create an event'),
              onTap: () => Navigator.pop(context, 'events'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'files') {
      await _pickFiles();
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => InteractiveComposer(
            session: session,
            path: '$_path/$action',
            poll: action == 'polls',
          ),
        ),
      );
      await _load();
    }
  }

  Future<void> _details() async {
    _stopTyping();
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ConversationDetails(session: session, conversation: _conversation),
      ),
    );
    if (!mounted) return;
    try {
      final data = await session.api.request('GET', _path);
      if (mounted) {
        setState(() => _conversation = Conversation(data['data'] as Json));
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted && [403, 404].contains(e.status)) {
        Navigator.pop(context);
      } else if (mounted) {
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final other = _conversation.participants
        .where((p) => p.id != session.user?.id)
        .firstOrNull;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _details,
          child: Row(
            children: [
              ConversationAvatar(
                session: session,
                conversation: _conversation,
                size: 39,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _conversation.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _conversation.group
                          ? '${_conversation.participants.length} members'
                          : other?.online == true
                          ? 'Active recently'
                          : 'Uhoo!',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search messages',
            onPressed: () {
              setState(() {
                _searching = !_searching;
                _search.clear();
              });
              _load(reset: true);
            },
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
          IconButton(
            tooltip: 'Conversation details',
            onPressed: _details,
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            children: [
              const Divider(),
              if (_searching)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search messages and files',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 400),
                        () => _load(reset: true),
                      );
                    },
                  ),
                ),
              if (_error != null && _messages.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  color: colors.surfaceContainerLow,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Could not refresh messages.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null && _messages.isEmpty
                    ? EmptyState(
                        icon: Icons.wifi_off,
                        title: 'Unable to load conversation',
                        message: _error.toString(),
                        action: TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      )
                    : _messages.isEmpty
                    ? EmptyState(
                        icon: Icons.waving_hand_outlined,
                        title: _searching ? 'No messages found' : 'Say hello',
                        message: _searching
                            ? 'Try a different search.'
                            : 'This is the beginning of your conversation with ${_conversation.name}.',
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        itemCount: _messages.length + (_next != null ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return Center(
                              child: _moreLoading
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(),
                                    )
                                  : TextButton(
                                      onPressed: () => _load(more: true),
                                      child: const Text(
                                        'Load earlier messages',
                                      ),
                                    ),
                            );
                          }
                          final message = _messages[index];
                          final older = index + 1 < _messages.length
                              ? _messages[index + 1]
                              : null;
                          final day = message.created;
                          final showDay =
                              day != null &&
                              (older == null ||
                                  !DateUtils.isSameDay(day, older.created));
                          return Column(
                            key: ValueKey(message.id),
                            children: [
                              if (showDay)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    DateUtils.isSameDay(day, DateTime.now())
                                        ? 'Today'
                                        : DateFormat.yMMMd().format(day),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              MessageBubble(
                                message: message,
                                mine: message.sender?.id == session.user!.id,
                                group: _conversation.group,
                                onAction: () => _actions(message),
                                onAttachment: (a) => _attachment(message, a),
                                onReact: (emoji) => _react(message, emoji),
                                onVote: (ids) => _mutate(
                                  'PATCH',
                                  '$_path/messages/${message.id}/poll-vote',
                                  {'option_ids': ids},
                                ),
                                onRsvp: (status) => _mutate(
                                  'PATCH',
                                  '$_path/messages/${message.id}/rsvp',
                                  {'status': status},
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              if (_typingPeople.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _typingLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              const Divider(),
              if (_conversation.locked)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_clock_outlined,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'This previous-term classroom chat is archived and read-only.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_conversation.locked && (_reply != null || _editing != null))
                ListTile(
                  dense: true,
                  leading: Icon(_editing != null ? Icons.edit : Icons.reply),
                  title: Text(
                    _editing != null
                        ? 'Editing message'
                        : 'Replying to ${_reply!.sender?.name ?? 'message'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    (_editing ?? _reply)!.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Cancel',
                    onPressed: _sending
                        ? null
                        : () => setState(() {
                            if (_editing != null) _body.clear();
                            _editing = null;
                            _reply = null;
                          }),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              if (!_conversation.locked && _files.isNotEmpty)
                SizedBox(
                  height: 54,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final file in _files)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            label: SizedBox(
                              width: 135,
                              child: Text(
                                file.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            avatar: const Icon(Icons.attach_file, size: 16),
                            onDeleted: _sending
                                ? null
                                : () => setState(() => _files.remove(file)),
                          ),
                        ),
                    ],
                  ),
                ),
              if (!_conversation.locked)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Add attachment, poll, or event',
                          onPressed: _sending || _editing != null ? null : _add,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _body,
                            enabled: !_sending,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Message…',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 12,
                              ),
                            ),
                            onChanged: (_) => _composerChanged(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton.filled(
                            tooltip: _editing != null
                                ? 'Save edit'
                                : 'Send message',
                            onPressed:
                                _sending ||
                                    (_body.text.trim().isEmpty &&
                                        _files.isEmpty)
                                ? null
                                : _send,
                            icon: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _editing != null
                                        ? Icons.check
                                        : Icons.arrow_upward_rounded,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTyping();
    for (final timer in _typingExpiry.values) {
      timer.cancel();
    }
    session.realtime?.unsubscribe('presence-conversations.${_conversation.id}');
    _body.dispose();
    _search.dispose();
    _scroll.dispose();
    _poll?.cancel();
    _debounce?.cancel();
    _events?.cancel();
    super.dispose();
  }
}

class _PendingFile {
  const _PendingFile(this.name, this.path);
  final String name;
  final String path;
}
