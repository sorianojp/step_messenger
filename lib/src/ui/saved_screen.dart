import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../theme.dart';
import 'widgets.dart';

/// The user's Saved list, like SavedMessagesDialog in the web app. Tapping an
/// item opens its chat through [onOpen].
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key, required this.session, required this.onOpen});
  final SessionController session;
  final Future<void> Function(int conversationId) onOpen;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<Json> _items = [];
  int? _next;
  bool _loading = true;
  bool _opening = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = PageData.from(
        await widget.session.api.request(
          'GET',
          '${widget.session.teamPath}/saved-messages?page=${more ? _next : 1}',
        ),
        (json) => json,
      );
      if (!mounted) return;
      setState(() {
        _items = more ? [..._items, ...page.items] : page.items;
        _next = page.next;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Json item) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onOpen((item['conversation'] as Map)['id'] as int);
      // Unsaved or left chats drop out of the list.
      if (mounted) await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved messages')),
      body: Column(
        children: [
          if (_opening) const LinearProgressIndicator(),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _items.isEmpty
                ? EmptyState(
                    icon: Icons.wifi_off,
                    title: 'Could not load saved messages',
                    message: _error.toString(),
                    action: TextButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  )
                : _items.isEmpty
                ? const EmptyState(
                    icon: Icons.bookmark_border,
                    title: 'No saved messages',
                    message:
                        'Long-press a message and choose Save message to find it here later.',
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      itemCount: _items.length + (_next != null ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _items.length) {
                          return TextButton(
                            onPressed: _loading
                                ? null
                                : () => _load(more: true),
                            child: const Text('Load more'),
                          );
                        }
                        final item = _items[index];
                        final message = ChatMessage(
                          Map<String, dynamic>.from(item['message'] as Map),
                        );
                        final conversation = item['conversation'] as Map;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              StepShape.radiusMedium,
                            ),
                            onTap: () => _open(item),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          conversation['display_name']
                                                  as String? ??
                                              'Conversation',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: brandText(context),
                                          ),
                                        ),
                                      ),
                                      if (message.created != null)
                                        Text(
                                          DateFormat(
                                            'MMM d, h:mm a',
                                          ).format(message.created!),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    message.sender?.name ?? 'Message',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    message.preview,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
