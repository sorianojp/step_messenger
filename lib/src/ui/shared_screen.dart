import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'attachment_viewer.dart';
import 'widgets.dart';

class SharedScreen extends StatefulWidget {
  const SharedScreen({
    super.key,
    required this.session,
    required this.conversationPath,
  });
  final SessionController session;
  final String conversationPath;
  @override
  State<SharedScreen> createState() => _SharedScreenState();
}

class _SharedScreenState extends State<SharedScreen> {
  late Future<Json> _data = _fetch();
  Future<Json> _fetch() =>
      widget.session.api.request('GET', '${widget.conversationPath}/shared');
  Future<void> _refresh() async {
    final next = _fetch();
    setState(() => _data = next);
    try {
      await next;
    } catch (_) {
      /* The future builder displays errors. */
    }
  }

  Future<void> _open(Json item, bool link) async {
    if (!link) {
      await openAttachment(
        context,
        widget.session,
        widget.conversationPath,
        item['message_id'] as int,
        item,
      );
      return;
    }
    try {
      final uri = Uri.tryParse(item['url'] as String? ?? '');
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const ApiException('This link cannot be opened.');
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const ApiException('No browser could open this link.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Shared in this conversation'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Media'),
            Tab(text: 'Files'),
            Tab(text: 'Links'),
          ],
        ),
      ),
      body: FutureBuilder<Json>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.cloud_off,
              title: 'Could not load shared items',
              message: snapshot.error.toString(),
              action: FilledButton(
                onPressed: _refresh,
                child: const Text('Retry'),
              ),
            );
          }
          final data = snapshot.data!['data'] as Json;
          return TabBarView(
            children: [
              for (final kind in ['media', 'files', 'links'])
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      if (records(data[kind]).isEmpty)
                        const EmptyState(
                          icon: Icons.folder_open,
                          title: 'Nothing shared yet',
                          message: 'Items shared in messages will appear here.',
                        ),
                      for (final item in records(data[kind]))
                        ListTile(
                          leading: Icon(
                            kind == 'links'
                                ? Icons.link
                                : kind == 'media'
                                ? Icons.perm_media_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(
                            (kind == 'links' ? item['host'] : item['name'])
                                    as String? ??
                                'Shared item',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            kind == 'links'
                                ? item['url'] as String
                                : '${(item['sender'] as Map?)?['name'] ?? 'Member'} · ${timeLabel(date(item['created_at']))}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(item, kind == 'links'),
                        ),
                      if (records(data[kind]).isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Showing recent shared items. Older items remain available in message history.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
