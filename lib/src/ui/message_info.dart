import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/models.dart';
import 'widgets.dart';

/// "Seen by": who has read, received, or not yet received your message.
/// Same groups as MessageInfoDialog in the web app.
Future<void> showMessageInfo(
  BuildContext context,
  ChatMessage message,
  Conversation conversation,
) {
  final receipts = messageReceipts(message, conversation);
  final sections = [
    ('Seen by', receipts.seen),
    ('Delivered to', receipts.delivered),
    ('Not delivered yet', receipts.pending),
  ].where((section) => section.$2.isNotEmpty);
  final colors = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .5,
      maxChildSize: .9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              'Message info',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              message.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
            ),
          ),
          for (final (title, people) in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(
                '$title · ${people.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            for (final person in people)
              ListTile(
                leading: PersonAvatar(person.name, size: 40, brand: true),
                title: Text(person.name),
                trailing: person.at == null
                    ? null
                    : Text(
                        DateFormat('MMM d, h:mm a').format(person.at!),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
              ),
          ],
        ],
      ),
    ),
  );
}
