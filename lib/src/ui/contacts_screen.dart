import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'widgets.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.session,
    this.selecting = false,
    this.onOpen,
  });
  final SessionController session;
  final bool selecting;
  final Future<void> Function(Conversation)? onOpen;
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _search = TextEditingController();
  final _title = TextEditingController();
  final Map<int, Person> _selected = {};
  List<Person> _people = [];
  int? _next;
  int _generation = 0;
  bool _loading = true;
  bool _creating = false;
  bool _group = false;
  Object? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    try {
      final data = PageData.from(
        await widget.session.api.request(
          'GET',
          '${widget.session.teamPath}/contacts?page=${more ? _next : 1}&search=${Uri.encodeQueryComponent(_search.text.trim())}',
        ),
        Person.new,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _people = more ? [..._people, ...data.items] : data.items;
          _next = data.next;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _create(List<Person> people) async {
    if (_creating) return;
    if (_group && _title.text.trim().isEmpty) {
      showError(context, const FormatException());
      return;
    }
    setState(() => _creating = true);
    try {
      final data = await widget.session.api.request(
        'POST',
        '${widget.session.teamPath}/conversations',
        body: {
          'type': _group ? 'group' : 'direct',
          if (_group) 'title': _title.text.trim(),
          'participant_ids': people.map((p) => p.id).toList(),
        },
      );
      if (!mounted) return;
      final conversation = Conversation(data['data'] as Json);
      if (widget.selecting) {
        Navigator.pop(context, conversation);
      } else {
        await widget.onOpen?.call(conversation);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        if (widget.selecting)
          SwitchListTile(
            title: const Text('Create a group'),
            subtitle: const Text('Bring your community together'),
            value: _group,
            onChanged: _creating
                ? null
                : (value) => setState(() {
                    _group = value;
                    _selected.clear();
                  }),
          ),
        if (_group)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              controller: _title,
              maxLength: 160,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Group name'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search people',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
        ),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_selected.length} people selected',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        if (_creating) const LinearProgressIndicator(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? EmptyState(
                  icon: Icons.wifi_off,
                  title: 'Unable to load people',
                  message: _error.toString(),
                  action: TextButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                )
              : _people.isEmpty
              ? const EmptyState(
                  icon: Icons.people_outline,
                  title: 'No people found',
                  message:
                      'Try another name, or check back when more people join your workspace.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _people.length + (_next != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _people.length) {
                        return TextButton(
                          onPressed: () => _load(more: true),
                          child: const Text('Load more people'),
                        );
                      }
                      final person = _people[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 5,
                        ),
                        leading: PersonAvatar(
                          person.name,
                          online: person.online,
                        ),
                        title: Text(
                          person.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(person.role),
                        trailing: _group
                            ? Checkbox(
                                value: _selected.containsKey(person.id),
                                onChanged: _creating
                                    ? null
                                    : (_) => _toggle(person),
                              )
                            : const Icon(Icons.chat_bubble_outline, size: 20),
                        onTap: _creating
                            ? null
                            : () =>
                                  _group ? _toggle(person) : _create([person]),
                      );
                    },
                  ),
                ),
        ),
        if (_group)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _selected.isEmpty ||
                          _creating ||
                          _title.text.trim().isEmpty
                      ? null
                      : () => _create(_selected.values.toList()),
                  child: const Text('Create group'),
                ),
              ),
            ),
          ),
      ],
    );
    return widget.selecting
        ? Scaffold(
            appBar: AppBar(title: const Text('New message')),
            body: body,
          )
        : body;
  }

  void _toggle(Person person) => setState(() {
    if (_selected.containsKey(person.id)) {
      _selected.remove(person.id);
    } else {
      _selected[person.id] = person;
    }
  });
  @override
  void dispose() {
    _search.dispose();
    _title.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
