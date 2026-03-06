import 'package:flutter/material.dart';
import 'package:stridemind/services/strava_auth_service.dart';

class LoginPage extends StatefulWidget {
  final StravaAuthService authService;
  const LoginPage({super.key, required this.authService});

  /// True while the login page is in the tree; deep-link handler uses this to avoid showing "login failed" after navigating to Home.
  static bool isLoginPageVisible = false;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _stravaLoading = false;

  @override
  void initState() {
    super.initState();
    LoginPage.isLoginPageVisible = true;
  }

  @override
  void dispose() {
    LoginPage.isLoginPageVisible = false;
    super.dispose();
  }

  Future<void> _loginWithStrava() async {
    setState(() => _stravaLoading = true);
    try {
      await widget.authService.loginWithStrava();
      // App loses focus; deep link handler in main.dart will take over on return.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching Strava: $e')),
      );
      setState(() => _stravaLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canTap = !_stravaLoading;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.directions_run,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'StrideMind',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to get started',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canTap ? _loginWithStrava : null,
                    icon: _stravaLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.directions_run, size: 22),
                    label: Text(_stravaLoading ? 'Connecting…' : 'Connect with Strava'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Connect Strava to get started and sync activities.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
