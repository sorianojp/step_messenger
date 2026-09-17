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
  String get preview => unsent
      ? 'Message unsent'
      : body.isNotEmpty
      ? body
      : attachments.isNotEmpty
      ? 'Sent an attachment'
      : 'Start a conversation';
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
