import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../data/api.dart';
import 'conversation_avatar.dart';
import 'shared_screen.dart';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'widgets.dart';

class ConversationDetails extends StatefulWidget {
  const ConversationDetails({
    super.key,
    required this.session,
    required this.conversation,
  });
  final SessionController session;
  final Conversation conversation;
  @override
  State<ConversationDetails> createState() => _ConversationDetailsState();
}

class _ConversationDetailsState extends State<ConversationDetails> {
  late Conversation _conversation = widget.conversation;
  late final String _path =
      '${widget.session.teamPath}/conversations/${_conversation.id}';
  bool _busy = false;
  List<ChatMessage> _pinned = [];
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final result = await widget.session.api.request('GET', _path);
      final pinned = await widget.session.api.request(
        'GET',
        '$_path/messages/pinned',
      );
      if (mounted) {
        setState(() {
          _conversation = Conversation(result['data'] as Json);
          _pinned = records(pinned['data']).map(ChatMessage.new).toList();
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _update(String method, String path, [Json? body]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.session.api.request(method, path, body: body);
      await _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo() async {
    if (_busy) return;
    setState(() => _busy = true);
    Directory? temporary;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      );
      if (files.isEmpty) return;
      final picked = files.first;
      if (await picked.length() > 5 * 1024 * 1024) {
        throw const ApiException('Choose an image smaller than 5 MB.');
      }
      final root = await getTemporaryDirectory();
      final parent = await Directory(
        '${root.path}/step_messenger/uploads',
      ).create(recursive: true);
      temporary = await parent.createTemp('photo_');
      final name = picked.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final file = await File(
        '${temporary.path}/$name',
      ).writeAsBytes(await picked.readAsBytes());
      await widget.session.api.upload('$_path/photo', {}, [
        file.path,
      ], field: 'photo');
      await _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMembers() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final contacts = <Person>[];
      int? page = 1;
      do {
        final data = PageData.from(
          await widget.session.api.request(
            'GET',
            '${widget.session.teamPath}/contacts?page=$page',
          ),
          Person.new,
        );
        contacts.addAll(data.items);
        page = data.next;
      } while (page != null);
      final existing = _conversation.participants.map((p) => p.id).toSet();
      final available = contacts
          .where((p) => !existing.contains(p.id))
          .toList();
      if (!mounted) return;
      final selected = <int>{};
      final result = await showModalBottomSheet<List<int>>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              child: Column(
                children: [
                  const ListTile(
                    title: Text(
                      'Add people',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: available.isEmpty
                        ? const EmptyState(
                            icon: Icons.people_outline,
                            title: 'Everyone is here',
                            message:
                                'All workspace members are already in this conversation.',
                          )
                        : ListView(
                            children: [
                              for (final person in available)
                                CheckboxListTile(
                                  title: Text(person.name),
                                  subtitle: Text(person.role),
                                  value: selected.contains(person.id),
                                  onChanged: (value) => update(() {
                                    if (value == true) {
                                      selected.add(person.id);
                                    } else {
                                      selected.remove(person.id);
                                    }
                                  }),
                                ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, selected.toList()),
                      child: const Text('Add to group'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (result != null) {
        await widget.session.api.request(
          'POST',
          '$_path/members',
          body: {'user_ids': result},
        );
        await _refresh();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Conversation details')),
    body: AbsorbPointer(
      absorbing: _busy,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Center(
            child: ConversationAvatar(
              session: widget.session,
              conversation: _conversation,
              size: 88,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _conversation.name,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${_conversation.participants.length} members',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_conversation.managedByStep) ...[
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: Icon(
                  _conversation.locked
                      ? Icons.lock_clock_outlined
                      : Icons.school_outlined,
                ),
                title: const Text('Managed by STEP'),
                subtitle: Text(
                  _conversation.locked
                      ? 'This previous-term classroom is archived and read-only.'
                      : '${_conversation.schoolClass?['school_year'] ?? 'Current term'} · Semester ${_conversation.schoolClass?['semester'] ?? '—'}\nMembership is synchronized from the STEP classroom.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Shared media, files and links'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SharedScreen(
                  session: widget.session,
                  conversationPath: _path,
                ),
              ),
            ),
          ),
          if (_conversation.can('can_customize_group')) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('Change group photo'),
              onTap: _photo,
            ),
            if (_conversation.json['photo_url'] != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hide_image_outlined),
                title: const Text('Remove group photo'),
                onTap: () => _update('DELETE', '$_path/photo'),
              ),
          ],
          if (_conversation.can('can_rename'))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Change group name'),
              onTap: () async {
                final name = await askText(
                  context,
                  title: 'Group name',
                  initial: _conversation.name,
                );
                if (name != null) {
                  await _update('PATCH', _path, {'title': name});
                }
              },
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: Text(switch (_conversation.notifications) {
              'muted' => 'Muted',
              'mentions' => 'Mentions only',
              _ => 'All messages',
            }),
            onTap: () async {
              final preference = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in {
                        'all': 'All messages',
                        'mentions': 'Mentions only',
                        'muted': 'Muted',
                      }.entries)
                        ListTile(
                          title: Text(entry.value),
                          trailing: _conversation.notifications == entry.key
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(context, entry.key),
                        ),
                    ],
                  ),
                ),
              );
              if (preference != null) {
                await _update('PATCH', '$_path/notifications', {
                  'preference': preference,
                });
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.push_pin_outlined),
            title: Text(
              _conversation.pinned ? 'Unpin conversation' : 'Pin conversation',
            ),
            onTap: () => _update('PATCH', '$_path/pin', {
              'pinned': !_conversation.pinned,
            }),
          ),
          if (!_conversation.locked)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.archive_outlined),
              title: Text(
                _conversation.archived
                    ? 'Move to inbox'
                    : 'Archive conversation',
              ),
              onTap: () => _update('PATCH', '$_path/archive', {
                'archived': !_conversation.archived,
              }),
            ),
          if (_pinned.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'PINNED MESSAGES',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final message in _pinned)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.push_pin_outlined, size: 18),
                title: Text(
                  message.preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(message.sender?.name ?? 'School'),
                trailing: _conversation.can('can_pin_messages')
                    ? IconButton(
                        tooltip: 'Unpin message',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _update(
                          'PATCH',
                          '$_path/messages/${message.id}/pin',
                          {'pinned': false},
                        ),
                      )
                    : null,
              ),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'MEMBERS',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_conversation.can('can_add_members'))
                TextButton.icon(
                  onPressed: _addMembers,
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Add'),
                ),
            ],
          ),
          for (final person in _conversation.participants)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PersonAvatar(person.name, size: 38),
              title: Text(
                '${person.name}${person.id == widget.session.user!.id ? ' (you)' : ''}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: !_conversation.can('can_customize_group')
                  ? null
                  : () async {
                      final nickname = await askText(
                        context,
                        title: 'Nickname for ${person.name}',
                        initial: person.json['nickname'] as String? ?? '',
                        hint: 'Leave blank to remove nickname',
                        maxLength: 80,
                        allowEmpty: true,
                      );
                      if (nickname != null) {
                        await _update(
                          'PATCH',
                          '$_path/members/${person.id}/nickname',
                          {'nickname': nickname.isEmpty ? null : nickname},
                        );
                      }
                    },
              subtitle: Text(person.json['nickname'] as String? ?? person.role),
              trailing:
                  _conversation.can('can_remove_members') &&
                      person.id != widget.session.user!.id
                  ? IconButton(
                      tooltip: 'Remove member',
                      icon: const Icon(Icons.person_remove_outlined, size: 20),
                      onPressed: () async {
                        if (await confirmAction(
                          context,
                          'Remove ${person.name}?',
                          'They will no longer have access to this group.',
                          'Remove',
                        )) {
                          await _update(
                            'DELETE',
                            '$_path/members/${person.id}',
                          );
                        }
                      },
                    )
                  : null,
            ),
          if (_conversation.type == 'group' &&
              !_conversation.managedByStep) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                if (!await confirmAction(
                  context,
                  'Leave this group?',
                  'You will need to be added again to access this conversation.',
                  'Leave group',
                )) {
                  return;
                }
                try {
                  await widget.session.api.request(
                    'DELETE',
                    '$_path/members/me',
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              icon: const Icon(Icons.exit_to_app),
              label: const Text('Leave group'),
            ),
          ],
        ],
      ),
    ),
  );
}
