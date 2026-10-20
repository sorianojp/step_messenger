import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../data/api.dart';
import 'widgets.dart';

/// Same limit as MAX_VOICE_NOTE_SECONDS in the web recorder.
const maxVoiceNote = Duration(minutes: 5);

/// Replaces the composer while a voice note is recorded. Calls [onDone] with
/// the recorded file, or null when the recording is discarded.
class VoiceRecorderBar extends StatefulWidget {
  const VoiceRecorderBar({super.key, required this.onDone});
  final Future<void> Function(File?) onDone;

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  final _recorder = AudioRecorder();
  final _started = Stopwatch();
  Timer? _tick;
  bool _recording = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        throw const ApiException(
          'Allow microphone access in Settings to record voice messages.',
        );
      }
      final temp = await getTemporaryDirectory();
      final directory = await Directory(
        '${temp.path}/step_messenger/uploads',
      ).create(recursive: true);
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          numChannels: 1,
        ),
        path:
            '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      if (!mounted) return;
      _started.start();
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_started.elapsed >= maxVoiceNote) _finish(send: true);
        if (mounted) setState(() {});
      });
      setState(() => _recording = true);
    } catch (e) {
      if (!mounted) return;
      showError(
        context,
        e is ApiException
            ? e
            : const ApiException('Voice recording could not start.'),
      );
      await widget.onDone(null);
    }
  }

  Future<void> _finish({required bool send}) async {
    if (_finishing) return;
    _finishing = true;
    _tick?.cancel();
    _started.stop();
    File? file;
    try {
      if (send) {
        final path = await _recorder.stop();
        if (path != null && _started.elapsed >= const Duration(seconds: 1)) {
          file = File(path);
        }
      } else {
        await _recorder.cancel();
      }
    } catch (_) {
      /* Treat a failed stop as a discarded recording. */
    }
    if (mounted) setState(() => _recording = false);
    await widget.onDone(file);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final elapsed = _started.elapsed;
    return Row(
      children: [
        IconButton(
          tooltip: 'Discard voice message',
          onPressed: _finishing ? null : () => _finish(send: false),
          icon: const Icon(Icons.delete_outline),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: _recording ? 'Recording voice message' : 'Starting recorder',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.fiber_manual_record,
                    size: 14,
                    color: _recording ? colors.error : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _recording
                        ? '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}'
                        : 'Starting…',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Max 5:00',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton.filled(
            tooltip: 'Send voice message',
            onPressed: _recording && !_finishing
                ? () => _finish(send: true)
                : null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (!_finishing) _recorder.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
