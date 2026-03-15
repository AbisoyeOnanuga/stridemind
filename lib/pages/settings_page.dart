import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:stridemind/pages/profile_page.dart';
import 'package:stridemind/services/firebase_auth_service.dart';
import 'package:stridemind/services/strava_auth_service.dart';
import 'package:stridemind/services/theme_service.dart';
import 'package:stridemind/services/activity_source_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// App URLs for Settings.
const String aboutUrl = 'https://abisoyeonanuga.github.io/stride-mind/';
const String privacyUrl = 'https://abisoyeonanuga.github.io/stride-mind/privacy.html';

/// Settings: Connect app (Strava), Theme, Gear, Legal, About, Account.
class SettingsPage extends StatefulWidget {
  final StravaAuthService authService;
  final void Function(ThemeMode)? onThemeModeChanged;

  const SettingsPage({
    super.key,
    required this.authService,
    this.onThemeModeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _stravaConnected = false;
  String? _activeSource;
  String? _accountEmail;
  final ThemeService _themeService = ThemeService();
  final ActivitySourceService _sourceService = ActivitySourceService();
  final FirebaseAuthService _firebaseAuth = FirebaseAuthService();

  @override
  void initState() {
    super.initState();
    _checkStravaConnection();
    _loadActiveSource();
    _loadAccountEmail();
  }

  Future<void> _loadAccountEmail() async {
    final user = _firebaseAuth.currentUser;
    final email = user?.email;
    if (mounted) {
      setState(() {
        _accountEmail = email;
      });
    }
  }

  Future<void> _loadActiveSource() async {
    final source = await _sourceService.getActiveSource();
    if (mounted) setState(() => _activeSource = source);
  }

  Future<void> _showThemePicker(BuildContext context, ThemeData theme) async {
    final current =
        ThemeService.themeModeNotifier.value ?? await _themeService.getThemeMode();
    if (!context.mounted) return;
    final chosen = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => _ThemePickerDialog(current: current),
    );
    if (chosen != null) {
      // Persist/apply once via app-level callback when available.
      // Fallback to direct service call for contexts without callback.
      if (widget.onThemeModeChanged != null) {
        widget.onThemeModeChanged!(chosen);
      } else {
        _themeService.setThemeMode(chosen);
      }
    }
  }

  Future<void> _checkStravaConnection() async {
    final token = await widget.authService.getValidAccessToken();
    if (mounted) {
      setState(() => _stravaConnected = token != null);
      if (token != null && _activeSource == null) {
        await _sourceService.setActiveSource(ActivitySourceService.valueStrava);
        setState(() => _activeSource = ActivitySourceService.valueStrava);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Appearance',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: const Text('Light, dark, or follow system'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemePicker(context, theme),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Connect app',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.directions_run),
            title: const Text('Strava'),
            subtitle: Text(_stravaConnected ? 'Connected' : 'Not connected'),
            onTap: _stravaConnected
                ? null
                : () async {
                    try {
                      await widget.authService.loginWithStrava();
                      // App goes to browser; deep link handler will process return.
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not launch Strava: $e')),
                        );
                      }
                    }
                  },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_stravaConnected)
                  TextButton(
                    onPressed: _activeSource == ActivitySourceService.valueStrava
                        ? null
                        : () async {
                            await _sourceService.setActiveSource(ActivitySourceService.valueStrava);
                            if (mounted) setState(() => _activeSource = ActivitySourceService.valueStrava);
                          },
                    child: Text(
                      _activeSource == ActivitySourceService.valueStrava ? 'In use' : 'Use for activities',
                    ),
                  ),
                if (_stravaConnected)
                  IconButton(
                    icon: const Icon(Icons.link_off),
                    tooltip: 'Disconnect',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Disconnect Strava?'),
                          content: const Text(
                            'You will need to connect again to sync activities.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Disconnect'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        await widget.authService.clearStravaTokens();
                        if (mounted) setState(() => _stravaConnected = false);
                      }
                    },
                  )
                else
                  const Icon(Icons.chevron_right),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: const Text('Samsung Health'),
            subtitle: const Text('Use Health Connect on Android for activities'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: _activeSource == ActivitySourceService.valueSamsungHealth
                      ? null
                      : () async {
                          await _sourceService.setActiveSource(ActivitySourceService.valueSamsungHealth);
                          if (!mounted) return;
                          setState(() => _activeSource = ActivitySourceService.valueSamsungHealth);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Samsung Health / Health Connect sync coming soon. Use Strava for now.',
                              ),
                            ),
                          );
                        },
                  child: Text(
                    _activeSource == ActivitySourceService.valueSamsungHealth ? 'In use' : 'Use for activities',
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Gear',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: Icon(MdiIcons.shoeSneaker),
            title: const Text('Shoes & bikes'),
            subtitle: const Text('View and manage gear from Strava or add your own'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProfilePage(
                    authService: widget.authService,
                    onThemeModeChanged: widget.onThemeModeChanged,
                  ),
                ),
              );
            },
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Legal',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.gavel),
            title: const Text('Terms & Privacy'),
            subtitle: const Text('Legal information'),
            onTap: () async {
              final uri = Uri.parse(privacyUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open privacy link')),
                  );
                }
              }
            },
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'About',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('StrideMind'),
            subtitle: const Text('Your running & training companion'),
            onTap: () async {
              final uri = Uri.parse(aboutUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open about link')),
                  );
                }
              }
            },
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Account',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: Text(
              _accountEmail != null
                  ? _accountEmail!
                  : _stravaConnected
                      ? 'Strava connected; no account email is configured'
                      : 'No account email is configured',
            ),
            onTap: () async {
              await _loadAccountEmail();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _accountEmail != null
                        ? 'Account email loaded'
                        : 'No account email available',
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete my account'),
            subtitle: const Text('Remove account and data'),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete account?'),
                  content: const Text(
                    'This will remove your account and data. This action cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Account removal to be implemented'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ThemePickerDialog extends StatelessWidget {
  final ThemeMode current;

  const _ThemePickerDialog({required this.current});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Theme'),
      content: RadioGroup<ThemeMode>(
        groupValue: current,
        onChanged: (v) {
          if (v != null) Navigator.of(context).pop(v);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
            ),
            RadioListTile<ThemeMode>(
              title: const Text('System'),
              subtitle: const Text('Follow device setting'),
              value: ThemeMode.system,
            ),
          ],
        ),
      ),
    );
  }
}
