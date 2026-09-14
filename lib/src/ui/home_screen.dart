import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'widgets.dart';
import 'conversation_avatar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final SessionController session;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  List<Conversation> _conversations = [];
  int _tab = 0;
  String _filter = 'All';
  int? _next;
  bool _loading = true;
  bool _fetching = false;
  Future<void>? _inflight;
  Object? _error;
  Timer? _poll;
  Timer? _debounce;
  StreamSubscription<Json>? _events;
  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    if (session.team != null) {
      _load();
      _poll = Timer.periodic(const Duration(seconds: 25), (_) {
        if (session.foreground) {
          _load();
          _presence();
        }
      });
      _presence();
      _events = session.realtime?.events.listen((event) {
        if (event['event'] == 'client-typing' ||
            event['event'] == 'subscribed') {
          return;
        }
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 450), () => _load());
      });
    } else {
      _loading = false;
    }
  }

  Future<void> _presence() async {
    try {
      await session.api.request('POST', '${session.teamPath}/presence');
    } catch (_) {
      /* Inbox reports connection errors. */
    }
  }

  Future<void> _load({bool more = false, bool reset = false}) async {
    if (session.team == null) return;
    final inflight = _inflight;
    if (inflight != null) {
      // A background poll must not swallow a refresh the user just triggered:
      // skip a duplicate poll, but queue anything that has to be seen.
      if (!reset && !more) return;
      await inflight;
      if (!mounted) return;
    }
    final request = _fetch(more: more, reset: reset);
    _inflight = request;
    try {
      await request;
    } finally {
      _inflight = null;
    }
  }

  Future<void> _fetch({required bool more, required bool reset}) async {
    _fetching = true;
    final page = more ? _next : 1;
    final archived = _filter == 'Archived';
    try {
      final data = PageData.from(
        await session.api.request(
          'GET',
          '${session.teamPath}/conversations?page=$page&archived=${archived ? 1 : 0}',
        ),
        Conversation.new,
      );
      if (!mounted) return;
      setState(() {
        if (reset || (page == 1 && _next == 2)) {
          _conversations = data.items;
        } else if (more) {
          final items = {
            for (final c in _conversations) c.id: c,
            for (final c in data.items) c.id: c,
          };
          _conversations = items.values.toList();
        } else {
          // The first page is authoritative about what belongs in this list, so
          // anything it no longer returns (archived elsewhere, or left) is
          // dropped rather than kept forever by the merge.
          final incoming = data.items.map((c) => c.id).toSet();
          final firstPage = data.items.length;
          _conversations = [
            ...data.items,
            ..._conversations
                .skip(firstPage)
                .where((c) => !incoming.contains(c.id)),
          ];
        }
        if (more || reset || _conversations.length <= 25) _next = data.next;
        _error = null;
      });
      for (final conversation in data.items) {
        session.realtime?.subscribe('private-conversations.${conversation.id}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Conversation conversation) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ChatScreen(session: session, conversation: conversation),
      ),
    );
    if (mounted) await _load(reset: true);
  }

  Future<void> _compose() async {
    final result = await Navigator.push<Conversation>(
      context,
      MaterialPageRoute(
        builder: (_) => ContactsScreen(session: session, selecting: true),
      ),
    );
    if (result != null && mounted) await _open(result);
  }

  Future<void> _conversationMenu(Conversation conversation) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                conversation.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(
                conversation.pinned ? 'Unpin conversation' : 'Pin conversation',
              ),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: Text(
                conversation.muted
                    ? 'Unmute conversation'
                    : 'Mute conversation',
              ),
              onTap: () => Navigator.pop(context, 'mute'),
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(
                conversation.archived
                    ? 'Move to inbox'
                    : 'Archive conversation',
              ),
              onTap: () => Navigator.pop(context, 'archive'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    final fields = {
      'pin': {'pinned': !conversation.pinned},
      'mute': {'muted': !conversation.muted},
      'archive': {'archived': !conversation.archived},
    };
    try {
      final response = await session.api.request(
        'PATCH',
        '${session.teamPath}/conversations/${conversation.id}/$action',
        body: fields[action],
      );
      if (!mounted) return;
      setState(() {
        // The server returns the new pivot timestamps; apply them so the row
        // updates on the spot instead of waiting for the next poll.
        final data = response['data'];
        if (data is Map) {
          conversation.json.addAll(Map<String, dynamic>.from(data));
        }
        if (action == 'archive') {
          // The inbox and the archive are mutually exclusive, so the
          // conversation leaves whichever list is on screen.
          _conversations = _conversations
              .where((c) => c.id != conversation.id)
              .toList();
        } else if (action == 'pin') {
          _sort();
        }
      });
      await _load(reset: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Mirrors the server ordering: pinned first, then most recent.
  void _sort() {
    _conversations.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final left = a.updated;
      final right = b.updated;
      if (left == null || right == null) return 0;
      return right.compareTo(left);
    });
  }

  Widget _inbox(double bottomInset) {
    final query = _search.text.toLowerCase();
    final conversations = _conversations
        .where(
          (c) =>
              c.name.toLowerCase().contains(query) &&
              (_filter != 'Unread' || c.unread > 0) &&
              (_filter != 'Groups' || c.group),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search conversations',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            children: [
              for (final filter in ['All', 'Unread', 'Groups', 'Archived'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    showCheckmark: false,
                    onSelected: _fetching
                        ? null
                        : (_) {
                            final changed =
                                (_filter == 'Archived') !=
                                (filter == 'Archived');
                            setState(() {
                              _filter = filter;
                              if (changed) {
                                _conversations = [];
                                _loading = true;
                              }
                            });
                            if (changed) _load(reset: true);
                          },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null && _conversations.isNotEmpty)
          MaterialBanner(
            content: const Text(
              'Could not refresh messages. Pull down to retry.',
            ),
            actions: [
              TextButton(onPressed: () => _load(), child: const Text('Retry')),
            ],
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _conversations.isEmpty
              ? EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Unable to load messages',
                  message: _error.toString(),
                  action: FilledButton(
                    onPressed: () => _load(reset: true),
                    child: const Text('Try again'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (conversations.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: query.isNotEmpty
                                ? 'No matching conversations'
                                : _filter == 'Unread'
                                ? 'You’re all caught up'
                                : _filter == 'Archived'
                                ? 'No archived conversations'
                                : 'Start a conversation',
                            message: query.isNotEmpty
                                ? 'Try a different name or load more conversations.'
                                : 'Keep in touch with your school community.',
                            action: _filter == 'All' && query.isEmpty
                                ? FilledButton.icon(
                                    onPressed: _compose,
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('New message'),
                                  )
                                : null,
                          ),
                        ),
                      SliverList.builder(
                        itemCount: conversations.length,
                        itemBuilder: (context, index) {
                          final c = conversations[index];
                          final other = c.participants
                              .where((p) => p.id != session.user!.id)
                              .firstOrNull;
                          final colors = Theme.of(context).colorScheme;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            leading: ConversationAvatar(
                              session: session,
                              conversation: c,
                              size: 54,
                              online: !c.group && (other?.online ?? false),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: c.unread > 0
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (c.pinned)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.push_pin_rounded,
                                      size: 13,
                                    ),
                                  ),
                                if (c.muted)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.notifications_off_outlined,
                                      size: 13,
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${c.latest?.sender?.id == session.user!.id ? 'You: ' : ''}${c.latest?.preview ?? 'Say hello 👋'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.unread > 0
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant,
                                  fontWeight: c.unread > 0
                                      ? FontWeight.w500
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  timeLabel(c.updated),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                if (c.unread > 0)
                                  Badge(
                                    backgroundColor: colors.primary,
                                    textColor: colors.onPrimary,
                                    label: Text(
                                      c.unread > 99 ? '99+' : '${c.unread}',
                                    ),
                                  )
                                else
                                  const SizedBox(height: 16),
                              ],
                            ),
                            onTap: () => _open(c),
                            onLongPress: () => _conversationMenu(c),
                          );
                        },
                      ),
                      if (_next != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: TextButton(
                              onPressed: _fetching
                                  ? null
                                  : () => _load(more: true),
                              child: const Text('Load more conversations'),
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(height: 90 + bottomInset),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _settings(double bottomInset) => ListView(
    padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
    children: [
      Center(child: PersonAvatar(session.user!.name, size: 84)),
      const SizedBox(height: 16),
      Text(
        session.user!.name,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Text(session.user!.email, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(
        session.user!.role.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 32),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.apartment_outlined),
        title: const Text('Department'),
        subtitle: Text(
          session.user!.department?.label ?? 'Not assigned in STEP',
        ),
      ),
      const Divider(),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.school_outlined),
        title: const Text('School workspace'),
        subtitle: Text(session.team?.name ?? 'No workspace'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _chooseTeam,
      ),
      const Divider(),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.contrast_rounded),
        title: const Text('Appearance'),
        subtitle: Text(session.themeMode.name),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final mode = await showModalBottomSheet<ThemeMode>(
            context: context,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in ThemeMode.values)
                    ListTile(
                      title: Text(
                        mode == ThemeMode.system
                            ? 'Use device settings'
                            : mode == ThemeMode.light
                            ? 'Light'
                            : 'Dark',
                      ),
                      trailing: session.themeMode == mode
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, mode),
                    ),
                ],
              ),
            ),
          );
          if (mode != null) await session.setTheme(mode);
        },
      ),
      const Divider(),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline),
        title: const Text('About Uhoo!'),
        subtitle: const Text('Version 1.0.0'),
        onTap: () => showAboutDialog(
          context: context,
          applicationName: 'Uhoo!',
          applicationVersion: '1.0.0',
          applicationIcon: const Icon(Icons.school_rounded, size: 40),
          children: [
            const Text('A place for your school community to stay connected.'),
          ],
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () async {
          if (!await confirmAction(
            context,
            'Sign out?',
            'You can sign in again with your STEP account.',
            'Sign out',
          )) {
            return;
          }
          try {
            await session.signOut();
          } catch (e) {
            if (mounted) showError(context, e);
          }
        },
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ],
  );

  Future<void> _chooseTeam() async {
    final selected = await showModalBottomSheet<Team>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Your workspaces',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final team in session.teams)
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text(team.name),
                trailing: team.id == session.team?.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, team),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await session.selectTeam(selected);
  }

  @override
  Widget build(BuildContext context) {
    if (session.team == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Uhoo!')),
        body: EmptyState(
          icon: Icons.school_outlined,
          title: 'Your school is not connected yet',
          message: 'Ask your school to add your STEP account to a workspace.',
          action: TextButton(
            onPressed: session.signOut,
            child: const Text('Sign out'),
          ),
        ),
      );
    }
    final unread = _conversations.fold<int>(0, (total, c) => total + c.unread);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ['Messages', 'People', 'Your profile'][_tab],
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -.7,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _chooseTeam,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      session.team!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 16),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: 'New message',
              onPressed: _compose,
              color: Theme.of(context).colorScheme.primary,
              icon: const Icon(Icons.edit_square),
            ),
          const SizedBox(width: 10),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          // The bar floats over the body; the Scaffold reports its height as
          // bottom padding here, which the outer context does not see.
          child: Builder(
            builder: (context) {
              final bottomInset = MediaQuery.paddingOf(context).bottom;
              return switch (_tab) {
                0 => _inbox(bottomInset),
                1 => ContactsScreen(session: session, onOpen: _open),
                _ => _settings(bottomInset),
              };
            },
          ),
        ),
      ),
      extendBody: true,
      bottomNavigationBar: _HomeNavigationBar(
        selectedIndex: _tab,
        unread: unread,
        onDestinationSelected: (tab) => setState(() => _tab = tab),
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _events?.cancel();
    _search.dispose();
    super.dispose();
  }
}

/// A floating, frosted bar in the style of TimeTab: lists scroll under it and
/// the selected tab fills with the brand.
class _HomeNavigationBar extends StatelessWidget {
  const _HomeNavigationBar({
    required this.selectedIndex,
    required this.unread,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final int unread;
  final ValueChanged<int> onDestinationSelected;

  static const _destinations = [
    (
      label: 'Messages',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    (label: 'People', icon: Icons.people_outline, selectedIcon: Icons.people),
    (label: 'Profile', icon: Icons.person_outline, selectedIcon: Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(24);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: .76),
                  border: Border.all(
                    color: colors.onSurface.withValues(alpha: .12),
                  ),
                  borderRadius: radius,
                ),
                child: SizedBox(
                  height: 72,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Row(
                      children: [
                        for (var i = 0; i < _destinations.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: _HomeNavigationItem(
                              label: _destinations[i].label,
                              icon: i == selectedIndex
                                  ? _destinations[i].selectedIcon
                                  : _destinations[i].icon,
                              selected: i == selectedIndex,
                              badge: i == 0 ? unread : 0,
                              onTap: () => onDestinationSelected(i),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeNavigationItem extends StatelessWidget {
  const _HomeNavigationItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onPrimary : colors.onSurface;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primary : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // On the brand fill the badge inverts, or it would vanish.
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text(badge > 99 ? '99+' : '$badge'),
                  backgroundColor: selected ? colors.onPrimary : null,
                  textColor: selected ? colors.primary : null,
                  child: Icon(icon, color: foreground, size: 22),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
