# STEP Messenger

The Android and iOS 14+ mobile client for the Laravel app in `../chat-app`.

## Run

Use the Flutter SDK already installed on this machine:

```sh
cd step_messenger
/Users/jpsoriano/Development/flutter/bin/flutter pub get
/Users/jpsoriano/Development/flutter/bin/flutter run
```

If Flutter is on your PATH, use `flutter` directly. The mobile app is
permanently pinned to the official Laravel deployment at
`https://messenger.udd.edu.ph`; the server cannot be changed from the sign-in
screen or with a build flag.

The server must include the mobile changes in `chat-app`. Use an existing STEP
account; the app opens STEP sign-in in the system authentication browser. No
password, OAuth client secret, or STEP access token is stored in the app.

See [the backend mobile runbook](../chat-app/docs/mobile-app.md) for SSO and
Reverb configuration. Existing web authentication remains available.

## Included

- STEP SSO with PKCE-bound, single-use mobile handoff codes; device tokens
  expire after 30 days and are held in platform secure storage.
- Session restoration, workspace switching, and device-specific logout.
- Paginated inbox, unread and group filters, search within loaded
  conversations, pinning, archive/restore, and notification preferences.
- Searchable school directory, direct conversations, and group creation.
- Paginated messages and server-side message search; send, reply, edit,
  unsend, forward, react, and pin messages. Failed sends keep the draft.
- Up to five files per message, 20 MB each; authenticated image viewing and
  opening downloaded files in a device application. Temporary attachment
  copies are removed on sign-out when the OS permits it.
- Poll creation and voting, event creation and RSVPs.
- Group renaming, adding/removing members, and leaving groups, subject to
  Laravel's existing permissions.
- Notice categories and reading; teachers/admins can publish notices.
- Reverb updates for subscribed conversations and notices, automatic
  reconnection, and foreground HTTP refresh as a fallback. Polling also
  discovers newly created conversations. Read receipts, recent activity, and live typing shared with the web app.
- System, light, and dark appearance; loading, empty, and retry states.

## Verify and build

```sh
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator
```

The supplied debug APK targets Android ARM64 phones. To reproduce it with
less build storage, use `flutter build apk --debug --target-platform android-arm64`.
Use the default APK command above when you also need other Android architectures.

For a real HTTP/WebSocket integration check, run:

```sh
python3 tool/check_backend.py
```

This starts temporary Laravel and Reverb servers, uses a disposable SQLite
database with isolated users, and exercises the actual Dart clients. It checks
26 flows including channel membership, typing, messages, pagination, receipts, group photos, nicknames, shared files,
reactions, attachments, polls, notices, reconnection, and token revocation.
The helper removes its servers and temporary data afterward. Use `--php` and
`--dart` to override executable paths if they are not on PATH. It never signs
in to the live STEP service.

`lib/src/data` contains API, authentication, models, and Reverb integration.
`lib/src/ui` contains screens and shared widgets. Tests use an in-memory HTTP
client and secure-storage mock; they do not contact the school server.

## Deployment notes

- This is a native mobile client. The template web/desktop targets are not
  configured for the mobile SSO callback.
- Background push notifications are not configured. Reverb and periodic
  refresh update the app while it is open; operating-system push requires a
  separate FCM/APNs integration and credentials.
- Group owners can change or remove group photos and set or clear member
  nicknames by tapping a member in conversation details. Shared media, files,
  and links are available from conversation details; downloads require membership.
  Typing indicators expire after inactivity and stop when leaving the conversation.
- Offline message history and a background send queue are not implemented.
  Reconnecting reloads data from Laravel.
- Android retains the starter's debug signing configuration for development.
  Set your production application identifiers, app icons, release signing,
  and distribution configuration before store submission.
- Secure storage is constrained to 10.x for the current Flutter/Android SDK.
  The lockfile records the verified package versions.
