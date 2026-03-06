import 'package:flutter/material.dart';
import 'package:stridemind/pages/home_page.dart';
import 'package:stridemind/pages/login_page.dart';
import 'package:stridemind/pages/runner_profile_page.dart';
import 'package:stridemind/services/strava_auth_service.dart';
import 'package:stridemind/services/firebase_auth_service.dart';
import 'package:stridemind/services/fcm_service.dart';
import 'package:stridemind/services/strava_api_service.dart';
import 'package:stridemind/services/database_service.dart';
import 'package:stridemind/services/firestore_service.dart';

class SplashPage extends StatefulWidget {
  final StravaAuthService authService;
  final void Function(ThemeMode)? onThemeModeChanged;
  final FirebaseAuthService firebaseAuthService = FirebaseAuthService();
  final FcmService fcmService = FcmService();

  SplashPage({super.key, required this.authService, this.onThemeModeChanged});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  static const Duration _splashDuration = Duration(milliseconds: 2400);
  late AnimationController _controller;
  late Animation<double> _fadeScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeScale = Tween<double>(begin: 0.6, end: 1.0).chain(
      CurveTween(curve: Curves.easeOutCubic),
    ).animate(_controller);
    _controller.forward();
    Future.delayed(_splashDuration, () {
      if (!mounted) return;
      _checkLoginStatus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    if (!mounted) return;

    // 1) Firebase user present (when Firebase is enabled) -> Home or onboarding
    if (widget.firebaseAuthService.currentUser != null) {
      await widget.fcmService.initialize(stravaAuthService: widget.authService);
      if (!mounted) return;
      final runnerProfile = await DatabaseService().getRunnerProfile();
      if (!mounted) return;
      if (runnerProfile == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => RunnerProfilePage(
              isOnboarding: true,
              authService: widget.authService,
              onThemeModeChanged: widget.onThemeModeChanged,
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(
              authService: widget.authService,
              onThemeModeChanged: widget.onThemeModeChanged,
            ),
          ),
        );
      }
      return;
    }

    // 2) Strava token valid -> continue to app.
    // If Firebase is enabled, sign in anonymously and link profile.
    final accessToken = await widget.authService.getValidAccessToken();
    if (accessToken != null) {
      final firebaseUser = await widget.firebaseAuthService.signInAnonymously();
      if (mounted) {
        await widget.fcmService.initialize(stravaAuthService: widget.authService);
      }
      final stravaApiService = StravaApiService(accessToken: accessToken);
      try {
        final athleteProfile = await stravaApiService.getAthleteProfile();
        if (mounted) {
          if (firebaseUser != null) {
            final firestoreService = FirestoreService();
            await firestoreService.saveStravaProfile(firebaseUser.uid, athleteProfile);
          }
          final gearList = StravaApiService.mapGearFromAthleteProfile(athleteProfile);
          if (gearList.isNotEmpty) {
            await DatabaseService().upsertGear(gearList);
          }
        }
      } catch (e) {
        debugPrint("Could not link Strava profile during login: $e");
      }
      if (!mounted) return;
      final runnerProfile = await DatabaseService().getRunnerProfile();
      if (!mounted) return;
      if (runnerProfile == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => RunnerProfilePage(
              isOnboarding: true,
              authService: widget.authService,
              onThemeModeChanged: widget.onThemeModeChanged,
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(
              authService: widget.authService,
              onThemeModeChanged: widget.onThemeModeChanged,
            ),
          ),
        );
      }
      return;
    }

    // 3) Not signed in -> Login
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginPage(authService: widget.authService)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _fadeScale,
            builder: (context, child) {
              return Opacity(
                opacity: _controller.value,
                child: Transform.scale(
                  scale: _fadeScale.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_run,
                        size: 80,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'StrideMind',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your running & training companion',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}