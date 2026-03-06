import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:stridemind/services/firebase_auth_service.dart';
import 'package:stridemind/services/firebase_runtime.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseAuthService _authService = FirebaseAuthService();

  FirebaseFirestore? get _db {
    if (!FirebaseRuntime.isEnabled) return null;
    try {
      return FirebaseFirestore.instance;
    } catch (e) {
      debugPrint("Firestore unavailable: $e");
      return null;
    }
  }

  Future<void> addConversationTurn(
      Map<String, dynamic> turn, int timestamp) async {
    final db = _db;
    if (db == null) return;
    final uid = _authService.uid;
    if (uid == null) {
      debugPrint("FirestoreService Error: User not logged in.");
      return;
    }

    try {
      await db
          .collection('users')
          .doc(uid)
          .collection('conversation_history')
          .add({...turn, 'timestamp': timestamp});
    } catch (e) {
      debugPrint("Error saving conversation to Firestore: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Plan sync
  // ---------------------------------------------------------------------------

  /// Saves a training or nutrition plan to Firestore.
  /// [type] must be "training" or "nutrition".
  Future<void> savePlan(String type, String name, String planJson) async {
    final db = _db;
    if (db == null) return;
    final uid = _authService.uid;
    if (uid == null) {
      debugPrint("FirestoreService: Cannot save plan, user not logged in.");
      return;
    }
    try {
      await db
          .collection('users')
          .doc(uid)
          .collection('plans')
          .doc(type)
          .set({'name': name, 'plan_json': planJson, 'updated_at': DateTime.now().millisecondsSinceEpoch});
    } catch (e) {
      debugPrint("FirestoreService: Error saving $type plan: $e");
    }
  }

  /// Fetches a plan document from Firestore. Returns null if not found.
  /// [type] must be "training" or "nutrition".
  Future<Map<String, dynamic>?> getPlan(String type) async {
    final db = _db;
    if (db == null) return null;
    final uid = _authService.uid;
    if (uid == null) return null;
    try {
      final doc = await db
          .collection('users')
          .doc(uid)
          .collection('plans')
          .doc(type)
          .get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      debugPrint("FirestoreService: Error fetching $type plan: $e");
      return null;
    }
  }

  // ---------------------------------------------------------------------------

  /// Saves the user's Strava ID and other profile info to their user document.
  /// This is crucial for the backend to map a Strava webhook event to a Firebase user.
  Future<void> saveStravaProfile(String uid, Map<String, dynamic> athleteProfile) async {
    final db = _db;
    if (db == null) return;
    if (uid.isEmpty) {
      debugPrint("FirestoreService Error: Cannot save Strava profile, UID is empty.");
      return;
    }
    try {
      final userDocRef = db.collection('users').doc(uid);
      // Use `set` with `merge: true` to create or update the document without overwriting other fields.
      await userDocRef.set({
        'stravaProfile': athleteProfile,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving Strava profile to Firestore: $e");
    }
  }
}