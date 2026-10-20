import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'widgets.dart';

/// Opens http(s) links from messages in the device browser.
Future<void> openExternalLink(BuildContext context, String href) async {
  final uri = Uri.tryParse(href);
  try {
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const ApiException('Unable to open this link.');
    }
  } catch (_) {
    if (context.mounted) {
      showError(context, const ApiException('Unable to open this link.'));
    }
  }
}

Future<Uint8List> _preview(SessionController session, String path) {
  final cache = session.previews;
  final cached = cache.remove(path);
  final future = cached ?? session.api.download(path);
  cache[path] = future;
  if (cache.length > 60) cache.remove(cache.keys.first);
  future.catchError((Object _) {
    if (cache[path] == future) cache.remove(path);
    return Uint8List(0);
  });
  return future;
}

class AttachmentImage extends StatelessWidget {
  const AttachmentImage({
    super.key,
    required this.session,
    required this.path,
    required this.onTap,
  });
  final SessionController session;

  /// The API preview path for the attachment.
  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, minWidth: 120),
          child: FutureBuilder<Uint8List>(
            future: _preview(session, path),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                return Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  semanticLabel: 'Image attachment',
                  errorBuilder: (_, _, _) => _placeholder(colors, true),
                );
              }
              return _placeholder(colors, snapshot.hasError);
            },
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme colors, bool failed) => Container(
    width: 220,
    height: 160,
    color: colors.surfaceContainerHigh,
    alignment: Alignment.center,
    child: failed
        ? Icon(Icons.broken_image_outlined, color: colors.onSurfaceVariant)
        : const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
  );
}

class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    super.key,
    required this.session,
    required this.path,
    required this.cacheKey,
    required this.color,
    required this.mutedColor,
  });
  final SessionController session;
  final String path;
  final String cacheKey;
  final Color color;
  final Color mutedColor;

  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer> {
  /// Only one voice note plays at a time, as on the web.
  static _VoiceNotePlayerState? _active;

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _state;
  bool _loading = false;
  bool _playing = false;

  Future<void> _toggle() async {
    if (_loading) return;
    final player = _player;
    if (player != null) {
      if (_playing) {
        await player.pause();
      } else {
        await _activate(player);
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final temp = await getTemporaryDirectory();
      final directory = await Directory(
        '${temp.path}/step_messenger/downloads',
      ).create(recursive: true);
      final file = File(
        '${directory.path}/${widget.session.user!.id}_voice_${widget.cacheKey}',
      );
      if (!await file.exists()) {
        await file.writeAsBytes(await widget.session.api.download(widget.path));
      }
      final created = AudioPlayer();
      await created.setFilePath(file.path);
      if (!mounted) {
        await created.dispose();
        return;
      }
      _state = created.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          created.pause();
          created.seek(Duration.zero);
        }
        if (mounted) {
          setState(
            () => _playing =
                state.playing &&
                state.processingState != ProcessingState.completed,
          );
        }
      });
      setState(() => _player = created);
      await _activate(created);
    } catch (_) {
      if (mounted) {
        showError(
          context,
          const ApiException('This voice message could not be played.'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate(AudioPlayer player) async {
    if (_active != this) await _active?._player?.pause();
    _active = this;
    unawaited(player.play());
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: _playing ? 'Pause voice message' : 'Play voice message',
            onPressed: _toggle,
            icon: _loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.color,
                    ),
                  )
                : Icon(
                    _playing ? Icons.pause_circle : Icons.play_circle,
                    size: 34,
                    color: widget.color,
                  ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 150,
          child: StreamBuilder<Duration>(
            stream: player?.positionStream,
            builder: (context, position) {
              final total = player?.duration ?? Duration.zero;
              final current = position.data ?? Duration.zero;
              final progress = total.inMilliseconds == 0
                  ? 0.0
                  : (current.inMilliseconds / total.inMilliseconds).clamp(
                      0.0,
                      1.0,
                    );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                    color: widget.color,
                    backgroundColor: widget.mutedColor.withValues(alpha: .3),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    player == null
                        ? 'Voice message'
                        : '${_clock(current)} / ${_clock(total)}',
                    style: TextStyle(fontSize: 11, color: widget.mutedColor),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    _state?.cancel();
    _player?.dispose();
    super.dispose();
  }
}

String _clock(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({
    super.key,
    required this.preview,
    required this.ink,
    required this.inkMuted,
    required this.background,
  });
  final Json preview;
  final Color ink;
  final Color inkMuted;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final image = preview['image_url'] as String?;
    final title = preview['title'] as String?;
    final description = preview['description'] as String?;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openExternalLink(context, preview['url'] as String),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (image != null && image.startsWith('https://'))
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Image.network(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (preview['host'] as String? ?? '').toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: .5,
                        fontWeight: FontWeight.w600,
                        color: inkMuted,
                      ),
                    ),
                    if (title != null && title.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ink,
                          ),
                        ),
                      ),
                    if (description != null && description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: inkMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
