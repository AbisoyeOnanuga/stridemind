import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:stridemind/services/firebase_runtime.dart';

class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal();

  FirebaseAuth? get _auth {
    if (!FirebaseRuntime.isEnabled) return null;
    try {
      return FirebaseAuth.instance;
    } catch (e) {
      debugPrint("FirebaseAuth unavailable: $e");
      return null;
    }
  }

  User? get currentUser => _auth?.currentUser;
  String? get uid => _auth?.currentUser?.uid;

  Future<String?> getIdToken() async {
    try {
      return await currentUser?.getIdToken();
    } catch (e) {
      debugPrint("Failed to get ID token: $e");
      return null;
    }
  }

  Future<User?> signInAnonymously() async {
    try {
      final auth = _auth;
      if (auth == null) return null;
      if (currentUser != null) {
        return currentUser;
      }
      final userCredential = await auth.signInAnonymously();
      return userCredential.user;
    } catch (e) {
      debugPrint("Failed to sign in anonymously: $e");
      return null;
    }
  }

  Future<void> signOut() async {
    final auth = _auth;
    if (auth == null) return;
    await auth.signOut();
  }
}