import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../theme.dart';
import '../data/polling.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'saved_screen.dart';
import 'message_media.dart';
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
  DateTime _lastRefresh = DateTime.now();
  Timer? _debounce;
  StreamSubscription<Json>? _events;
  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint(
        '[ui] HomeScreen mounted (team ${session.team?.slug}, '
        'session #${identityHashCode(session)})',
      );
    }
    if (session.team != null) {
      _load();
      _poll = Timer.periodic(const Duration(seconds: 25), (_) {
        if (!session.foreground) return;
        // Polling also discovers new conversations and sends the presence
        // heartbeat (contacts show as online for 3 minutes after the last one).
        if (PollingPolicy.shouldPoll(
          realtimeLive: session.realtime?.isConnected ?? false,
          lastRefresh: _lastRefresh,
          now: DateTime.now(),
        )) {
          _lastRefresh = DateTime.now();
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
        settings: RouteSettings(name: '/conversations/${conversation.id}'),
        builder: (_) =>
            ChatScreen(session: session, conversation: conversation),
      ),
    );
    if (mounted) await _load(reset: true);
  }

  Future<void> _openSaved() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SavedScreen(
        session: session,
        onOpen: (id) async {
          final data = await session.api.request(
            'GET',
            '${session.teamPath}/conversations/$id',
          );
          if (mounted) await _open(Conversation(data['data'] as Json));
        },
      ),
    ),
  );

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
            if (conversation.archived)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete conversation'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'delete') {
      await _delete(conversation);
      return;
    }
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

  /// Removes an archived conversation from this account, as on the web.
  Future<void> _delete(Conversation conversation) async {
    if (!await confirmAction(
      context,
      'Delete conversation?',
      'This removes ${conversation.name} from your archive. Other members keep their copy.',
      'Delete',
    )) {
      return;
    }
    try {
      await session.api.request(
        'DELETE',
        '${session.teamPath}/conversations/${conversation.id}',
      );
      if (!mounted) return;
      session.drafts.remove(conversation.id);
      setState(() {
        _conversations = _conversations
            .where((c) => c.id != conversation.id)
            .toList();
      });
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
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                          return _ConversationRow(
                            session: session,
                            conversation: c,
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
                        child: SizedBox(height: 24 + bottomInset),
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
        leading: const Icon(Icons.badge_outlined),
        title: const Text('STEP roles'),
        subtitle: Text(
          session.user!.stepRoles.isEmpty
              ? 'No roles synchronized yet'
              : session.user!.stepRoles.join(', '),
        ),
      ),
      if (session.stepAccountUrl != null) ...[
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.manage_accounts_outlined),
          title: const Text('Manage account in STEP'),
          subtitle: const Text(
            'Change your name, email, password, or role. Uhoo! refreshes them on your next sign-in.',
          ),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => openExternalLink(context, session.stepAccountUrl!),
        ),
      ],
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
        leading: const Icon(Icons.bookmark_border),
        title: const Text('Saved messages'),
        subtitle: const Text('Messages you saved to find later'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openSaved,
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
        leading: const Icon(Icons.help_outline),
        title: const Text('Help and support'),
        subtitle: const Text('Contact Uhoo! support'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => openSupportPage(context),
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
    final colors = Theme.of(context).colorScheme;
    final pageTitle = switch (_tab) {
      0 => _filter == 'Archived' ? 'Archived' : 'Chat',
      1 => 'People',
      _ => 'Profile',
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 20,
        backgroundColor: colors.surface,
        shape: const Border(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _chooseTeam,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      session.team!.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              pageTitle,
              // Web: font-heading text-2xl font-bold text-foreground.
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 24,
                color: colors.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          if (_tab == 0 && _filter != 'Archived')
            IconButton.filled(
              tooltip: 'New message',
              onPressed: _compose,
              // Explicit: the app bar's action icon colour would win otherwise.
              style: IconButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                backgroundColor: Theme.of(context).colorScheme.primary,
                fixedSize: const Size(40, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(StepShape.radiusMedium),
                ),
              ),
              icon: Icon(
                Icons.edit_square,
                size: 20,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          const SizedBox(width: 10),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Material(
              color: colors.surfaceContainerLow,
              elevation: 1,
              shadowColor: const Color(0x1a000000),
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: switch (_tab) {
                0 => _inbox(0),
                1 => ContactsScreen(session: session, onOpen: _open),
                _ => _settings(0),
              },
            ),
          ),
        ),
      ),
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

/// Native bottom navigation using the web app's card, border and selected
/// brand-tint treatment.
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
    return Material(
      color: colors.surfaceContainerLow,
      shape: Border(top: BorderSide(color: colors.outlineVariant)),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    for (var i = 0; i < _destinations.length; i++)
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
    final foreground = selected ? brandText(context) : colors.onSurfaceVariant;

    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        child: Center(
          child: Material(
            color: selected ? colors.primaryContainer : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StepShape.radiusMedium),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(StepShape.radiusMedium),
              child: SizedBox(
                width: 64,
                height: 48,
                child: Center(
                  child: Badge(
                    isLabelVisible: badge > 0,
                    label: Text(badge > 99 ? '99+' : '$badge'),
                    backgroundColor: colors.primary,
                    textColor: colors.onPrimary,
                    child: Icon(icon, color: foreground, size: 23),
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

/// A conversation in the inbox, laid out like ConversationRow in the web
/// app's features/messenger/components/conversation-list.tsx.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.session,
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
  });
  final SessionController session;
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final colors = Theme.of(context).colorScheme;
    final me = session.user!.id;
    final other = c.participants.where((p) => p.id != me).firstOrNull;
    final draft = session.drafts[c.id]?.trim() ?? '';
    final preview = draft.isNotEmpty
        ? 'Draft: $draft'
        : '${c.latest?.sender?.id == me && c.latest?.unsent == false ? 'You: ' : ''}${c.latest?.preview ?? 'No messages yet'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(StepShape.radiusMedium),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(StepShape.radiusMedium),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConversationAvatar(
                  session: session,
                  conversation: c,
                  size: 44,
                  online: !c.group && (other?.online ?? false),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          if (c.pinned)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.push_pin_outlined,
                                size: 14,
                                color: brandText(context),
                                semanticLabel: 'Pinned',
                              ),
                            ),
                          if (c.muted)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.notifications_off_outlined,
                                size: 14,
                                color: colors.onSurfaceVariant,
                                semanticLabel: 'Muted',
                              ),
                            ),
                          if (c.unread > 0) ...[
                            const SizedBox(width: 8),
                            _CountBadge(
                              label: c.unread > 99 ? '99+' : '${c.unread}',
                              semantics: '${c.unread} unread',
                            ),
                          ],
                          if (c.unreadMentions > 0) ...[
                            const SizedBox(width: 4),
                            const _CountBadge(
                              label: '@',
                              semantics: 'Unread mention',
                              muted: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        conversationStatus(c, me, DateTime.now()),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
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

/// The 20px round unread (and @mention) badge from the web inbox.
class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.semantics,
    this.muted = false,
  });
  final String label;
  final String semantics;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: muted ? colors.surfaceContainerHigh : colors.primary,
          borderRadius: BorderRadius.circular(10),
          border: muted
              ? Border.all(color: colors.onSurface.withValues(alpha: .15))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: muted ? 11 : 10,
            fontWeight: FontWeight.w700,
            color: muted ? colors.onSurface : colors.onPrimary,
          ),
        ),
      ),
    );
  }
}
