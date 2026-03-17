import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:stridemind/models/strava_activity.dart';
import 'package:stridemind/services/activity_refresh_notifier.dart';
import 'package:stridemind/services/database_service.dart';
import 'package:stridemind/services/notification_api_service.dart';
import 'package:stridemind/services/firebase_runtime.dart';
import 'package:stridemind/services/strava_api_service.dart';
import 'package:stridemind/services/strava_auth_service.dart';

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final NotificationApiService _notificationApiService = NotificationApiService();
  StravaAuthService? _stravaAuthService;

  FirebaseMessaging? get _firebaseMessaging {
    if (!FirebaseRuntime.isEnabled) return null;
    try {
      return FirebaseMessaging.instance;
    } catch (e) {
      debugPrint("FCM unavailable: $e");
      return null;
    }
  }

  /// Call after login so FCM can fetch new activities when webhook delivers activityId.
  void setStravaAuth(StravaAuthService? authService) {
    _stravaAuthService = authService;
  }

  Future<void> initialize({StravaAuthService? stravaAuthService}) async {
    if (stravaAuthService != null) _stravaAuthService = stravaAuthService;
    final firebaseMessaging = _firebaseMessaging;
    if (firebaseMessaging == null) {
      debugPrint('FcmService: Firebase disabled, skipping push setup.');
      return;
    }

    // Request permissions for iOS/web
    NotificationSettings settings = await firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('User granted permission: ${settings.authorizationStatus}');

    // Handle messages while the app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');
      _handleActivityIdData(message.data);

      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification}');
      }
    });

    // When user opens app from a notification (or from background), refresh list
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Message opened app: ${message.data}');
      _handleActivityIdData(message.data);
    });

    // Get the token and save it to Firestore
    await _saveToken();

    // Listen for token refreshes and save the new one
    firebaseMessaging.onTokenRefresh.listen((token) {
      _notificationApiService.registerDevice(token);
    });
  }

  /// If [data] contains activityId, fetch activity from Strava, upsert to DB, notify dashboard.
  Future<void> _handleActivityIdData(Map<String, dynamic> data) async {
    final activityIdStr = data['activityId'];
    if (activityIdStr == null) return;

    final activityId = int.tryParse(activityIdStr.toString());
    if (activityId == null) return;

    final auth = _stravaAuthService;
    if (auth == null) {
      debugPrint('FcmService: No Strava auth, cannot fetch activity $activityId');
      return;
    }

    try {
      final token = await auth.getValidAccessToken();
      if (token == null) return;

      final api = StravaApiService(accessToken: token);
      final StravaActivity activity = await api.getActivityDetails(activityId);
      await DatabaseService().upsertActivities([activity]);
      ActivityRefreshNotifier.trigger();
      debugPrint('FcmService: Fetched and cached activity $activityId');
    } catch (e) {
      debugPrint('FcmService: Failed to fetch activity $activityId: $e');
    }
  }

  Future<void> _saveToken() async {
    final firebaseMessaging = _firebaseMessaging;
    if (firebaseMessaging == null) return;
    String? token = await firebaseMessaging.getToken();
    if (token != null) {
      await _notificationApiService.registerDevice(token);
    }
  }

  /// Manual retry (e.g. Settings) so backend has the FCM token for push.
  /// Returns true if registered, false if failed, null if no token or URL not configured / Firebase disabled.
  Future<bool?> retryDeviceRegistration() async {
    final firebaseMessaging = _firebaseMessaging;
    if (firebaseMessaging == null) return null;
    final token = await firebaseMessaging.getToken();
    if (token == null) return null;

    // Public repo NotificationApiService returns void; treat "attempted" as true.
    await _notificationApiService.registerDevice(token);
    return true;
  }
}