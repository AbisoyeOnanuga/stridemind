import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:stridemind/services/firebase_auth_service.dart';

class NotificationApiService {
  static const String _baseUrl =
      String.fromEnvironment('STRAVA_WEBHOOK_BASE_URL', defaultValue: '');

  final FirebaseAuthService _authService = FirebaseAuthService();

  Future<void> registerDevice(String fcmToken) async {
    if (_baseUrl.isEmpty) {
      debugPrint('NotificationApiService: STRAVA_WEBHOOK_BASE_URL not configured.');
      return;
    }
    final idToken = await _authService.getIdToken();
    if (idToken == null) {
      debugPrint('NotificationApiService: Cannot register device, user not logged in.');
      return;
    }

    final url = Uri.parse('$_baseUrl/api/strava-webhook/register-device');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'token': fcmToken}),
      );

      if (response.statusCode == 200) {
        debugPrint('Device registered successfully with Vercel backend.');
      } else {
        debugPrint('Failed to register device. Status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error registering device with Vercel backend: $e');
    }
  }
}