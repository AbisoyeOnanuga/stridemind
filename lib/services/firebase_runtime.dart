import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:stridemind/firebase_options.dart';

/// Centralized Firebase bootstrap so public builds can run without Firebase.
class FirebaseRuntime {
  static const bool enabledByDefine =
      bool.fromEnvironment('ENABLE_FIREBASE', defaultValue: false);

  static bool _initialized = false;

  static bool get isEnabled => enabledByDefine && _initialized;

  static Future<void> initializeIfEnabled() async {
    if (!enabledByDefine) {
      debugPrint('Firebase disabled (ENABLE_FIREBASE=false). Running local-only mode.');
      _initialized = false;
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _initialized = true;
    } catch (e) {
      _initialized = false;
      debugPrint('Firebase initialization failed. Continuing without Firebase: $e');
    }
  }
}
