import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../theme.dart';
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
  String _mode = 'direct';
  bool get _group => _mode == 'group';

  /// STEP classes this user teaches; the Class tab only shows when non-empty.
  List<SchoolClassSummary> _classes = [];
  Object? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.selecting) _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final data = await widget.session.api.request(
        'GET',
        '${widget.session.teamPath}/school-classes',
      );
      if (mounted) {
        setState(
          () => _classes = records(
            data['data'],
          ).map(SchoolClassSummary.new).toList(),
        );
      }
    } catch (_) {
      /* Classes are optional; people can still be messaged. */
    }
  }

  /// Opens the class chat, starting it first if there is none yet.
  Future<void> _openClass(SchoolClassSummary schoolClass) async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final data = await widget.session.api.request(
        'POST',
        '${widget.session.teamPath}/school-classes/${schoolClass.id}/conversation',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(StepShape.radiusMedium),
              ),
              child: Row(
                children: [
                  for (final mode in [
                    'direct',
                    'group',
                    if (_classes.isNotEmpty) 'class',
                  ])
                    Expanded(
                      child: _ConversationModeButton(
                        label: switch (mode) {
                          'group' => 'Group',
                          'class' => 'Class',
                          _ => 'Direct',
                        },
                        selected: _mode == mode,
                        onTap: _creating
                            ? null
                            : () => setState(() {
                                _mode = mode;
                                _selected.clear();
                              }),
                      ),
                    ),
                ],
              ),
            ),
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
        if (_mode == 'class') ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              'Your STEP classes this semester. Students join the class chat automatically, including those who sign in to Uhoo! later.',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_creating) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              children: [
                for (final schoolClass in _classes)
                  _ClassRow(
                    schoolClass: schoolClass,
                    onOpen: _creating ? null : () => _openClass(schoolClass),
                  ),
              ],
            ),
          ),
        ] else ...[
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
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
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
                        final selected = _selected.containsKey(person.id);
                        return Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            StepShape.radiusMedium,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              StepShape.radiusMedium,
                            ),
                            onTap: _creating
                                ? null
                                : () => _group
                                      ? _toggle(person)
                                      : _create([person]),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  PersonAvatar(
                                    person.name,
                                    size: 44,
                                    online: person.online,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          person.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          person.role,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (_group)
                                    _ContactSelectionMark(selected: selected)
                                  else
                                    Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 20,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
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

class _ConversationModeButton extends StatelessWidget {
  const _ConversationModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? colors.surfaceContainerLow : Colors.transparent,
        borderRadius: BorderRadius.circular(StepShape.radiusSmall),
        boxShadow: selected ? stepShadowSmall : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(StepShape.radiusSmall),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? brandText(context)
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactSelectionMark extends StatelessWidget {
  const _ContactSelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : Colors.transparent,
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 16, color: colors.onPrimary)
          : null,
    );
  }
}

/// A STEP class row in the Class tab, like ClassRow in the web composer.
class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.schoolClass, required this.onOpen});
  final SchoolClassSummary schoolClass;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final started = schoolClass.conversationId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: colors.primary,
            child: Icon(Icons.school_outlined, color: colors.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schoolClass.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  schoolClass.details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${schoolClass.joinedCount} of ${schoolClass.studentsCount} students on Uhoo!',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          started
              ? FilledButton.tonal(
                  onPressed: onOpen,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Open chat'),
                )
              : FilledButton(
                  onPressed: onOpen,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Start chat'),
                ),
        ],
      ),
    );
  }
}
