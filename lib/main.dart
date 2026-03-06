import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:app_links/app_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:stridemind/services/strava_auth_service.dart';
import 'package:stridemind/services/strava_api_service.dart';
import 'package:stridemind/services/firebase_auth_service.dart';
import 'package:stridemind/services/firebase_runtime.dart';
import 'package:stridemind/services/firestore_service.dart';
import 'package:stridemind/pages/splash_page.dart';
import 'package:stridemind/pages/home_page.dart';
import 'package:stridemind/pages/login_page.dart';
import 'package:stridemind/services/theme_service.dart';
import 'package:stridemind/strava_config.dart';

// Must be a top-level function (not a class method)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!FirebaseRuntime.enabledByDefine) return;
  await FirebaseRuntime.initializeIfEnabled();
  if (!FirebaseRuntime.isEnabled) return;
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseRuntime.initializeIfEnabled();
  if (FirebaseRuntime.isEnabled) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  runApp(StrideMindApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

class StrideMindApp extends StatefulWidget {
  const StrideMindApp({super.key});

  @override
  State<StrideMindApp> createState() => _StrideMindAppState();
}

class _StrideMindAppState extends State<StrideMindApp> {
  late final AppLinks _appLinks;
  final StravaAuthService _stravaAuthService = StravaAuthService(
      clientId: stravaClientId,
      clientSecret: stravaClientSecret,
      redirectUri: stravaRedirectUri,
      tokenExchangeUrl: stravaTokenExchangeUrl,
      tokenRefreshUrl: stravaTokenRefreshUrl,
      allowInsecureDirectOAuth: allowInsecureDirectStravaOAuth);
  final ThemeService _themeService = ThemeService();
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _themeService.getThemeMode().then((mode) {
      if (mounted) setState(() => _themeMode = mode);
      ThemeService.themeModeNotifier.value = mode;
    });
    ThemeService.themeModeNotifier.addListener(_onThemeNotifierChanged);
    // The logic for handling redirects is different for mobile and web.
    if (kIsWeb) {
      // On the web, the redirect URL is the current page URL.
      handleIncomingUri(Uri.base);
    } else {
      initAppLinks();
    }
  }

  void initAppLinks() async {
    _appLinks = AppLinks();

    try {
      // Handles cold start
      final Uri? initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        handleIncomingUri(initialUri);
      }

      // Handles runtime deep links
      _appLinks.uriLinkStream.listen((Uri uri) {
        handleIncomingUri(uri);
      }, onError: (err) => debugPrint('onLinkError: $err'));
    } catch (e) {
      debugPrint("Error handling deep link: $e");
    }
  }

  void handleIncomingUri(Uri? uri) async {
    if (uri != null && uri.queryParameters.containsKey('code')) {
      final code = uri.queryParameters['code']!;
      debugPrint("Received Strava code: $code");
      final success = await _stravaAuthService.exchangeCodeForToken(code);

      if (success) {
        // Link Strava profile to current Firebase user (e.g. when connecting from Settings).
        try {
          final token = await _stravaAuthService.getValidAccessToken();
          final uid = FirebaseAuthService().uid;
          if (token != null && uid != null) {
            final api = StravaApiService(accessToken: token);
            final profile = await api.getAthleteProfile();
            await FirestoreService().saveStravaProfile(uid, profile);
          }
        } catch (e) {
          debugPrint('Could not link Strava profile after OAuth: $e');
        }
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (context) => HomePage(authService: _stravaAuthService)),
          (route) => false,
        );
      } else {
        // Only show "login failed" if user is still on login page (avoids false message when deep link is processed twice).
        if (LoginPage.isLoginPageVisible) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Login failed. Please try again.')),
            );
          }
        }
      }
    }
  }

  void _onThemeNotifierChanged() {
    final mode = ThemeService.themeModeNotifier.value;
    if (mode != null && mounted) setState(() => _themeMode = mode);
  }

  @override
  void dispose() {
    ThemeService.themeModeNotifier.removeListener(_onThemeNotifierChanged);
    super.dispose();
  }

  void _onThemeModeChanged(ThemeMode mode) {
    _themeService.setThemeMode(mode);
    if (mounted) setState(() => _themeMode = mode);
  }

  ThemeData _resolvedTheme(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final useDark = _themeMode == ThemeMode.dark ||
        (_themeMode == ThemeMode.system && brightness == Brightness.dark);
    return useDark ? _stridemindDarkTheme : _stridemindLightTheme;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _resolvedTheme(context);
    return AnimatedTheme(
      data: theme,
      duration: const Duration(milliseconds: 280),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'StrideMind',
        theme: _stridemindLightTheme,
        darkTheme: _stridemindDarkTheme,
        themeMode: _themeMode,
        home: SplashPage(
          authService: _stravaAuthService,
          onThemeModeChanged: _onThemeModeChanged,
        ),
      ),
    );
  }
}

/// StrideMind brand theme: calm focus + motion (teal/sage), distinct from Strava/NRC/Garmin.
const Color _seedColor = Color(0xFF0D9488);
/// App green used for in-focus/selected in both light and dark.
const Color _appGreen = Color(0xFF14B8A6);
const Color _appGreenLight = Color(0xFF2DD4BF);

final ColorScheme _lightScheme = ColorScheme.fromSeed(
  seedColor: _seedColor,
  brightness: Brightness.light,
  primary: const Color(0xFF0D9488),
  secondary: const Color(0xFF0891B2),
  surface: const Color(0xFFF8FAFC),
);

/// Dark scheme: darker background; primary/selected = app green so selected nav/icons stand out.
final ColorScheme _darkScheme = ColorScheme.dark(
  primary: _appGreen,
  onPrimary: const Color(0xFF0F172A),
  primaryContainer: _appGreen.withValues(alpha: 0.25),
  onPrimaryContainer: _appGreenLight,
  secondary: const Color(0xFF22D3EE),
  onSecondary: const Color(0xFF0F172A),
  surface: const Color(0xFF0F172A),
  onSurface: const Color(0xFFF8FAFC),
  onSurfaceVariant: const Color(0xFFCBD5E1),
  outline: const Color(0xFF94A3B8),
  surfaceContainerLow: const Color(0xFF1E293B),
  surfaceContainerHigh: const Color(0xFF334155),
);

/// Light theme. Cards: darker grey background, outline like activity-card divider; cards with primary border (e.g. current week) keep their own shape.
const Color _lightCardBackground = Color(0xFFE2E8F0); // Darker neutral grey (slate-200)
const Color _lightCardBorder = Color(0xFFCBD5E1); // Border same family as divider (slate-300)
final ThemeData _stridemindLightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: _lightScheme,
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 1,
  ),
  cardTheme: CardThemeData(
    elevation: 2,
    shadowColor: Colors.black38,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: _lightCardBorder, width: 1),
    ),
    color: _lightCardBackground,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
  ),
);

/// Dark theme. Darker background; selected nav/buttons use app green.
final ThemeData _stridemindDarkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: _darkScheme,
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 1,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    color: _darkScheme.surfaceContainerLow,
  ),
  iconTheme: const IconThemeData(color: Color(0xFFF8FAFC)),
  bottomNavigationBarTheme: BottomNavigationBarThemeData(
    backgroundColor: _darkScheme.surface,
    selectedItemColor: _appGreen,
    unselectedItemColor: _darkScheme.onSurfaceVariant,
    type: BottomNavigationBarType.fixed,
  ),
);
