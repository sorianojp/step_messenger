import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/api.dart';
import '../data/session.dart';
import '../theme.dart';

Future<void> openSupportPage(BuildContext context) async {
  try {
    final opened = await launchUrl(
      Uri.parse('${SessionController.officialBaseUrl}/support'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw const ApiException('Unable to open support. Please try again.');
    }
  } catch (_) {
    if (context.mounted) {
      showError(
        context,
        const ApiException('Unable to open support. Please try again.'),
      );
    }
  }
}

String timeLabel(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  if (DateUtils.isSameDay(time, now)) return DateFormat.jm().format(time);
  if (DateUtils.isSameDay(time, now.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  return DateFormat.MMMd().format(time);
}

void showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is ApiException
              ? error.message
              : 'Something went wrong. Please try again.',
        ),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
      ),
    );

/// The green presence dot on avatars (web: size-3, border-2 border-card).
class OnlineDot extends StatelessWidget {
  const OnlineDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: StepPalette.onlineFor(Theme.of(context).brightness),
      shape: BoxShape.circle,
      border: Border.all(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        width: 2,
      ),
    ),
  );
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar(
    this.name, {
    super.key,
    this.size = 48,
    this.group = false,
    this.online = false,
  });
  final String name;
  final double size;
  final bool group;
  final bool online;
  @override
  Widget build(BuildContext context) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first.characters.first +
                  (parts.length > 1 ? parts.last.characters.first : ''))
              .toUpperCase();
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Web Avatar: groups fill with the brand, people sit on muted
          // with a hairline ring.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: group ? colors.primary : colors.surfaceContainerHigh,
              shape: BoxShape.circle,
              border: group ? null : Border.all(color: colors.outlineVariant),
            ),
            alignment: Alignment.center,
            child: group
                ? Icon(
                    Icons.group_outlined,
                    size: size * .45,
                    color: colors.onPrimary,
                  )
                : Text(
                    initials,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: size * .32,
                      color: colors.onSurface,
                    ),
                  ),
          ),
          if (online) const Positioned(right: 0, bottom: 0, child: OnlineDot()),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  int maxLength = 160,
  int lines = 1,
  bool allowEmpty = false,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (allowEmpty || controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // The dialog exit animation may still be using the controller.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}
