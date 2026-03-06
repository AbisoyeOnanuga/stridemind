import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StravaAuthService {
  final String _clientId;
  final String _clientSecret;
  final String _redirectUri;
  final String _tokenExchangeUrl;
  final String _tokenRefreshUrl;
  final bool _allowInsecureDirectOAuth;
  final _secureStorage = const FlutterSecureStorage();

  // Keys for secure storage
  static const _accessTokenKey = 'strava_access_token';
  static const _refreshTokenKey = 'strava_refresh_token';
  static const _expiresAtKey = 'strava_expires_at';

  StravaAuthService(
      {required String clientId,
      required String clientSecret,
      required String redirectUri,
      String tokenExchangeUrl = '',
      String tokenRefreshUrl = '',
      bool allowInsecureDirectOAuth = false})
      : _clientId = clientId,
        _clientSecret = clientSecret,
        _redirectUri = redirectUri,
        _tokenExchangeUrl = tokenExchangeUrl,
        _tokenRefreshUrl = tokenRefreshUrl,
        _allowInsecureDirectOAuth = allowInsecureDirectOAuth;

  Future<void> loginWithStrava() async {
    final authUrl = Uri(
      scheme: 'https',
      host: 'www.strava.com',
      path: '/oauth/mobile/authorize',
      queryParameters: {
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'response_type': 'code',
        'approval_prompt': 'auto',
        'scope': 'read,activity:read_all,profile:read_all',
      },
    );

    // --- IMPORTANT DEBUGGING STEP ---
    // Print the exact URL being launched to the console.
    if (kDebugMode) {
      print('Launching Strava Auth URL: $authUrl');
    }
    // --------------------------------

    if (!await canLaunchUrl(authUrl)) {
      throw 'Could not launch $authUrl';
    }
    await launchUrl(
      authUrl,
      mode: LaunchMode.externalApplication, // Correct mode for OAuth
    );
  }

  Future<bool> exchangeCodeForToken(String code) async {
    try {
      late final http.Response response;
      if (_tokenExchangeUrl.isNotEmpty) {
        response = await http.post(
          Uri.parse(_tokenExchangeUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'code': code,
            'client_id': _clientId,
            'redirect_uri': _redirectUri,
            'grant_type': 'authorization_code',
          }),
        );
      } else if (_allowInsecureDirectOAuth && _clientSecret.isNotEmpty) {
        response = await http.post(
          Uri.parse('https://www.strava.com/oauth/token'),
          body: {
            'client_id': _clientId,
            'client_secret': _clientSecret,
            'code': code,
            'grant_type': 'authorization_code',
          },
        );
      } else {
        if (kDebugMode) {
          print('Token exchange endpoint not configured. Configure backend token exchange.');
        }
        return false;
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String? accessToken = data['access_token'];
        final String? refreshToken = data['refresh_token'];
        final int? expiresAt = data['expires_at']; // Unix timestamp in seconds

        // Require at least access token and expiry; refresh token optional (Strava may omit on re-auth).
        if (accessToken != null && accessToken.isNotEmpty && expiresAt != null) {
          await _storeTokens(
            accessToken: accessToken,
            refreshToken: refreshToken ?? '',
            expiresAt: expiresAt,
          );
          if (kDebugMode) {
            print('Successfully received and stored tokens!');
          }
          return true;
        } else {
          if (kDebugMode) {
            print('Token exchange response did not contain required tokens.');
          }
          return false;
        }
      } else {
        if (kDebugMode) {
          print('Failed to exchange code for token: ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error exchanging code for token: $e');
      }
      return false;
    }
  }

  Future<void> _storeTokens(
      {required String accessToken,
      required String refreshToken,
      required int expiresAt}) async {
    await _secureStorage.write(key: _accessTokenKey, value: accessToken);
    await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    await _secureStorage.write(
        key: _expiresAtKey, value: expiresAt.toString());
  }

  Future<bool> isLoggedIn() async {
    final token = await _secureStorage.read(key: _accessTokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    await _secureStorage.deleteAll();
  }

  /// Clears only Strava tokens (e.g. "Disconnect Strava" in Settings). User stays signed in to Firebase.
  Future<void> clearStravaTokens() async {
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _expiresAtKey);
  }

  /// Gets a valid access token, refreshing it if it's expired.
  Future<String?> getValidAccessToken() async {
    final expiresAtStr = await _secureStorage.read(key: _expiresAtKey);
    if (expiresAtStr == null) {
      if (kDebugMode) {
        print('User not logged in, no expiration time found.');
      }
      return null; // Not logged in
    }

    final expiresAt = int.tryParse(expiresAtStr) ?? 0;
    final nowInSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Check if the token is expired or will expire in the next 5 minutes
    if (nowInSeconds >= expiresAt - 300) {
      if (kDebugMode) {
        print('Access token expired or expiring soon, refreshing...');
      }
      return await _refreshToken();
    }

    if (kDebugMode) {
      print('Access token is valid.');
    }
    return await _secureStorage.read(key: _accessTokenKey);
  }

  Future<String?> _refreshToken() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      if (kDebugMode) {
        print('No refresh token found. Logging out.');
      }
      await logout(); // Can't refresh without a refresh token
      return null;
    }

    late final http.Response response;
    if (_tokenRefreshUrl.isNotEmpty) {
      response = await http.post(
        Uri.parse(_tokenRefreshUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'refresh_token': refreshToken,
          'client_id': _clientId,
          'grant_type': 'refresh_token',
        }),
      );
    } else if (_allowInsecureDirectOAuth && _clientSecret.isNotEmpty) {
      response = await http.post(
        Uri.parse('https://www.strava.com/oauth/token'),
        body: {
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      );
    } else {
      if (kDebugMode) {
        print('Token refresh endpoint not configured. Configure backend token refresh.');
      }
      await logout();
      return null;
    }

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      await _storeTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
          expiresAt: data['expires_at']);
      if (kDebugMode) {
        print('Token refreshed successfully.');
      }
      return data['access_token'];
    } else {
      if (kDebugMode) {
        print('Failed to refresh token: ${response.body}');
      }
      await logout(); // If refresh fails, log the user out.
      return null;
    }
  }
}