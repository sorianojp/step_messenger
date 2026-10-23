typedef Json = Map<String, dynamic>;

List<Json> records(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
DateTime? date(dynamic value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

class Person {
  Person(this.json);
  final Json json;
  int get id => json['id'] as int;
  String get name => json['name'] as String? ?? 'STEP member';
  String get email => json['email'] as String? ?? '';
  String get role => json['school_role'] as String? ?? 'member';
  Department? get department => json['department'] is Map
      ? Department(Map<String, dynamic>.from(json['department']))
      : null;
  List<String> get stepRoles =>
      (json['step_roles'] as List? ?? []).whereType<String>().toList();
  String? get nickname => json['nickname'] as String?;
  DateTime? get lastSeen => date(json['last_seen_at']);
  bool get online =>
      lastSeen != null && DateTime.now().difference(lastSeen!).inMinutes < 3;
}

class Department {
  Department(this.json);
  final Json json;
  String get id => json['id']?.toString() ?? '';
  String get code => json['code'] as String? ?? '';
  String get name => json['name'] as String? ?? '';
  // STEP stores the code and the name identically for some colleges.
  String get label => code.isEmpty || code == name ? name : '$name ($code)';
}

class Team {
  Team(this.json);
  final Json json;
  int get id => json['id'] as int;
  String get name => json['name'] as String;
  String get slug => json['slug'] as String;
}

class Conversation {
  Conversation(this.json);
  final Json json;
  int get id => json['id'] as int;
  String get name =>
      json['display_name'] as String? ??
      json['title'] as String? ??
      'Conversation';
  String get type => json['type'] as String? ?? 'direct';
  bool get group => type != 'direct';
  List<Person> get participants =>
      records(json['participants']).map(Person.new).toList();
  ChatMessage? get latest => json['latest_message'] is Map
      ? ChatMessage(Map<String, dynamic>.from(json['latest_message']))
      : null;
  ChatMessage? get pinnedMessage => json['pinned_message'] is Map
      ? ChatMessage(Map<String, dynamic>.from(json['pinned_message']))
      : null;
  int get unread => json['unread_count'] as int? ?? 0;
  int get unreadMentions => json['unread_mentions_count'] as int? ?? 0;
  bool get pinned => json['pinned_at'] != null;
  bool get archived => json['archived_at'] != null;
  bool get muted => json['notification_preference'] == 'muted';
  String get notifications =>
      json['notification_preference'] as String? ?? 'all';
  bool can(String permission) =>
      (json['permissions'] as Map?)?[permission] == true;
  DateTime? get updated => date(json['last_message_at']) ?? latest?.created;
}

class ChatMessage {
  ChatMessage(this.json);
  final Json json;
  int get id => json['id'] as int;
  Person? get sender => json['sender'] is Map
      ? Person(Map<String, dynamic>.from(json['sender']))
      : null;
  String get body => json['body'] as String? ?? '';
  String get type => json['type'] as String? ?? 'text';
  bool get unsent => json['unsent_at'] != null;
  bool get edited => json['edited_at'] != null;
  bool get pinned => json['pinned_at'] != null;
  DateTime? get created => date(json['created_at']);
  List<Json> get attachments => records(json['attachments']);
  List<Json> get reactions => records(json['reactions']);
  Json? get reply => json['reply_to'] as Json?;
  Json? get poll => json['poll'] as Json?;
  Json? get event => json['event'] as Json?;
  bool get read => records(json['read_by']).any((r) => r['id'] != sender?.id);
  bool get delivered =>
      records(json['delivered_to']).any((r) => r['id'] != sender?.id);
  bool get voice => type == 'voice';
  bool get mentionsMe => json['mentions_me'] == true;
  List<Json> get linkPreviews =>
      records((json['metadata'] as Map?)?['link_previews']);

  /// Same wording as messagePreview() in the web app's lib/messages.ts.
  String get preview {
    if (unsent) {
      return sender == null
          ? 'Message unsent'
          : '${sender!.name} unsent a message';
    }
    if (poll != null) return 'Poll: ${poll!['question']}';
    if (event != null) return 'Event: ${event!['title']}';
    if (voice) return 'Voice message';
    if (body.isNotEmpty) return body;
    if (attachments.length == 1) {
      return 'Attachment: ${attachments.first['name']}';
    }
    if (attachments.length > 1) return '${attachments.length} attachments';
    return 'No messages yet';
  }
}

bool isAudioAttachment(Json attachment, {bool voice = false}) {
  final mime = attachment['mime_type'] as String? ?? '';
  return attachment['preview_url'] != null &&
      (mime.startsWith('audio/') || voice && mime.startsWith('video/'));
}

bool isImageAttachment(Json attachment) =>
    attachment['preview_url'] != null &&
    (attachment['mime_type'] as String? ?? '').startsWith('image/');

/// A STEP class the signed-in user teaches (GET /school-classes).
class SchoolClassSummary {
  SchoolClassSummary(this.json);
  final Json json;
  int get id => json['id'] as int;
  String get name => json['name'] as String? ?? 'Class';
  String get details => [
    json['section'],
    json['subject'],
  ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
  int get studentsCount => json['students_count'] as int? ?? 0;
  int get joinedCount => json['joined_count'] as int? ?? 0;
  int? get conversationId => json['conversation_id'] as int?;
}

class PageData<T> {
  PageData(this.items, this.next);
  final List<T> items;
  final int? next;
  factory PageData.from(Json json, T Function(Json) parse) => PageData(
    records(json['data']).map(parse).toList(),
    json['next_page_url'] != null ? (json['current_page'] as int) + 1 : null,
  );
}

/// formatSeenAt() from the web app's lib/format.ts.
String seenLabel(DateTime readAt, DateTime now) {
  final seconds = now.difference(readAt).inSeconds.clamp(0, 1 << 31);
  String unit(int value, String name) =>
      '$value ${value == 1 ? name : '${name}s'}';
  if (seconds < 60) return 'Seen Just Now';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return 'Seen ${unit(minutes, 'Minute')} Ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return 'Seen ${unit(hours, 'Hour')} Ago';
  return 'Seen ${unit(hours ~/ 24, 'Day')} Ago';
}

/// The receipt line shown under own messages, keyed by message id, following
/// messageDeliveryStatus() in the web app: "Seen …" under the latest message
/// someone read, "Delivered" under the latest one delivered, and "Sent" under
/// the latest one otherwise. [messages] is newest first.
Map<int, String> deliveryStatuses(
  List<ChatMessage> messages,
  int currentUserId,
  DateTime now,
) {
  final own = messages
      .where((m) => m.sender?.id == currentUserId && !m.unsent)
      .toList();
  final seen = own.where((m) => m.read).firstOrNull;
  final delivered = own.where((m) => m.delivered).firstOrNull;
  final latest = own.firstOrNull;
  final statuses = <int, String>{};
  if (latest != null) statuses[latest.id] = 'Sent';
  if (delivered != null) statuses[delivered.id] = 'Delivered';
  if (seen != null) {
    final readAt =
        records(seen.json['read_by'])
            .where((r) => r['id'] != currentUserId)
            .map((r) => date(r['read_at']))
            .nonNulls
            .toList()
          ..sort((a, b) => b.compareTo(a));
    if (readAt.isNotEmpty) {
      statuses[seen.id] = seenLabel(readAt.first, now);
    } else {
      statuses.remove(seen.id);
    }
  }
  return statuses;
}

/// formatRelativeLastSeen() from the web app's lib/format.ts.
String relativeLastSeen(DateTime lastSeen, DateTime now) {
  final minutes = now.difference(lastSeen).inMinutes;
  if (minutes < 1) return 'just now';
  if (minutes < 60) return '$minutes min ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  final days = hours ~/ 24;
  return '$days ${days == 1 ? 'day' : 'days'} ago';
}

/// conversationStatusLabel() from the web app's lib/conversations.ts.
String conversationStatus(Conversation c, int currentUserId, DateTime now) {
  final others = c.participants.where((p) => p.id != currentUserId).toList();
  final online = others.where((p) => p.online).length;
  if (!c.group) {
    if (online > 0) return 'Active now';
    final lastSeen = others.firstOrNull?.lastSeen;
    return lastSeen == null
        ? 'Offline'
        : 'Offline · ${relativeLastSeen(lastSeen, now)}';
  }
  return online == 0
      ? '${c.participants.length} members'
      : '$online active now';
}
