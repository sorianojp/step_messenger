import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'widgets.dart';

Future<void> openAttachment(
  BuildContext context,
  SessionController session,
  String conversationPath,
  int messageId,
  Json attachment,
) async {
  await openDownloadedAttachment(
    context,
    session,
    '$conversationPath/messages/$messageId/attachments/${attachment['id']}',
    '${messageId}_${attachment['id']}',
    attachment,
  );
}

Future<void> openDownloadedAttachment(
  BuildContext context,
  SessionController session,
  String path,
  String storageKey,
  Json attachment,
) async {
  final userId = session.user!.id;
  try {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Opening attachment…'),
        duration: Duration(seconds: 1),
      ),
    );
    final bytes = await session.api.download(path);
    if (!context.mounted) return;
    if ((attachment['mime_type'] as String? ?? '').startsWith('image/')) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text(attachment['name'] as String)),
            body: Center(
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, _, _) =>
                      const Text('This image format cannot be previewed.'),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      final temp = await getTemporaryDirectory();
      final safeName = (attachment['name'] as String).replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final directory = await Directory(
        '${temp.path}/step_messenger/downloads',
      ).create(recursive: true);
      final file = File('${directory.path}/${userId}_${storageKey}_$safeName');
      await file.writeAsBytes(bytes);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw const ApiException('No app could open this file type.');
      }
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
