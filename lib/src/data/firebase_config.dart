import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public Firebase client settings for the Uhoo! Android and iOS apps.
///
/// Dart defines can override these defaults for non-production environments.
abstract final class FirebaseConfig {
  static const _apiKeyOverride = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appIdOverride = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderIdOverride = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _projectIdOverride = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const _storageBucketOverride = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  static bool get isConfigured =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static FirebaseOptions get options {
    final defaults = switch (defaultTargetPlatform) {
      TargetPlatform.android => const FirebaseOptions(
        apiKey: 'AIzaSyDpblA3xyeKI2Q2iqmXCObzbpzd3fomgxk',
        appId: '1:923291113689:android:62d4e37fe8d5b20e6e46c8',
        messagingSenderId: '923291113689',
        projectId: 'uhoo-6b5c8',
        storageBucket: 'uhoo-6b5c8.firebasestorage.app',
      ),
      TargetPlatform.iOS => const FirebaseOptions(
        apiKey: 'AIzaSyDVIaGwN4EB-1IwH2nieqJheBAOjCLBtnw',
        appId: '1:923291113689:ios:c581b11593cf59796e46c8',
        messagingSenderId: '923291113689',
        projectId: 'uhoo-6b5c8',
        storageBucket: 'uhoo-6b5c8.firebasestorage.app',
        iosBundleId: 'com.arzatech.uhoo',
      ),
      _ => throw UnsupportedError('Firebase is only configured for mobile.'),
    };

    return defaults.copyWith(
      apiKey: _apiKeyOverride.isEmpty ? null : _apiKeyOverride,
      appId: _appIdOverride.isEmpty ? null : _appIdOverride,
      messagingSenderId: _senderIdOverride.isEmpty ? null : _senderIdOverride,
      projectId: _projectIdOverride.isEmpty ? null : _projectIdOverride,
      storageBucket: _storageBucketOverride.isEmpty
          ? null
          : _storageBucketOverride,
    );
  }
}
