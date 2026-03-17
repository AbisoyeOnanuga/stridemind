import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:stridemind/pages/activity_detail_page.dart';
import 'package:stridemind/pages/coach_page.dart';
import 'package:stridemind/pages/profile_page.dart';
import 'package:stridemind/pages/settings_page.dart';
import 'package:stridemind/models/strava_activity.dart';
import 'package:stridemind/services/firebase_auth_service.dart';
import 'package:stridemind/models/strava_athlete.dart';
import 'package:stridemind/pages/nutrition_plan_page.dart';
import 'package:stridemind/pages/training_plan_page.dart';
import 'package:stridemind/services/activity_refresh_notifier.dart';
import 'package:stridemind/services/database_service.dart';
import 'package:stridemind/services/fcm_service.dart';
import 'package:stridemind/services/strava_api_service.dart';
import 'package:stridemind/services/strava_auth_service.dart';
import 'package:stridemind/widgets/activity_card.dart';
import 'package:stridemind/widgets/weekly_summary_panel.dart';

class HomePage extends StatefulWidget {
  final StravaAuthService authService;
  final void Function(ThemeMode)? onThemeModeChanged;

  const HomePage({
    super.key,
    required this.authService,
    this.onThemeModeChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final List<String> _pageTitles = const [
    'Home',
    'AI Coach',
    'Training Plan',
    'Nutrition Plan',
  ];
  StravaAthlete? _athlete;
  StravaActivity? _coachInitialActivity;

  @override
  void initState() {
    super.initState();
    _loadAthlete();
    // Ensure FCM is initialized when opening Home directly (e.g. app resume without splash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FcmService().initialize(stravaAuthService: widget.authService);
    });
  }

  Future<void> _loadAthlete() async {
    final athlete = await DatabaseService().getCachedAthleteProfile();
    if (mounted) setState(() => _athlete = athlete);
  }

  void _onDiscussWithCoach(StravaActivity activity) {
    // Defer so we don't call setState during build (avoids "cannot be marked as needing to build").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _coachInitialActivity = activity;
        _selectedIndex = 1;
      });
    });
  }

  void _onCoachAppliedInitialActivity() {
    setState(() => _coachInitialActivity = null);
  }

  List<Widget> get _pages => [
        ActivityDashboard(
          authService: widget.authService,
          onAthleteLoaded: (_) {},
          onAthleteProfileLoaded: (athlete) {
            if (mounted) setState(() => _athlete = athlete);
          },
          onDiscussWithCoach: _onDiscussWithCoach,
          onThemeModeChanged: widget.onThemeModeChanged,
        ),
        CoachPage(
          authService: widget.authService,
          initialActivityToSelect: _coachInitialActivity,
          onInitialActivityApplied: _onCoachAppliedInitialActivity,
        ),
        const TrainingPlanPage(),
        const NutritionPlanPage(),
      ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _pageTitles[_selectedIndex];

    // Never pop the root (Home): back on dashboard minimizes app; back on other tabs goes to dashboard.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        } else {
          // On dashboard (root): minimize app like Strava — one back to exit, no going back to login.
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProfilePage(
                  authService: widget.authService,
                  onThemeModeChanged: widget.onThemeModeChanged,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _athlete != null && (_athlete!.profileMedium != null || _athlete!.profile != null)
                  ? CircleAvatar(
                      radius: 18,
                      backgroundImage: NetworkImage(
                        _athlete!.profile ?? _athlete!.profileMedium!,
                      ),
                    )
                  : CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        _athlete?.firstname.isNotEmpty == true
                            ? _athlete!.firstname.substring(0, 1).toUpperCase()
                            : '?',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.model_training),
            label: 'Coach',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_note),
            label: 'Training',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu),
            label: 'Nutrition',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      ),
    );
  }
}

class ActivityDashboard extends StatefulWidget {
  final StravaAuthService authService;
  final Function(String) onAthleteLoaded;
  final void Function(StravaAthlete?)? onAthleteProfileLoaded;
  final void Function(StravaActivity)? onDiscussWithCoach;
  final void Function(ThemeMode)? onThemeModeChanged;

  const ActivityDashboard({
    super.key,
    required this.authService,
    required this.onAthleteLoaded,
    this.onAthleteProfileLoaded,
    this.onDiscussWithCoach,
    this.onThemeModeChanged,
  });

  @override
  State<ActivityDashboard> createState() => _ActivityDashboardState();
}

class _ActivityDashboardState extends State<ActivityDashboard>
    with WidgetsBindingObserver {
  static const String _connectSourcePrompt =
      'Connect Strava in Settings to see activities.';
  final _db = DatabaseService();

  List<StravaActivity> _activities = [];
  bool _isFirstLoad = true;  // true until cache or fresh data is displayed
  bool _isRefreshing = false; // true during a background delta sync
  String? _error;
  bool _connectRecoveryScheduled = false;

  bool _isNetworkError(String text) {
    final lower = text.toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('connection closed');
  }

  String _friendlyDashboardError(String raw) {
    if (_isNetworkError(raw)) {
      return 'No internet connection. Reconnect and pull to refresh.';
    }
    if (raw.toLowerCase().contains('oauth') ||
        raw.toLowerCase().contains('authentication failed')) {
      return 'Strava authentication expired. Reconnect in Settings.';
    }
    return raw;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    ActivityRefreshNotifier.instance.addListener(_onRefreshNotified);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ActivityRefreshNotifier.instance.removeListener(_onRefreshNotified);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
  }

  void _onRefreshNotified() {
    if (!mounted) return;
    _reloadFromCache();
  }

  /// Reload activity list from SQLite (e.g. after FCM delivered a new activity).
  Future<void> _reloadFromCache() async {
    final all = await _db.getCachedActivities(source: 'strava');
    if (mounted) setState(() => _activities = all);
  }

  Future<void> _loadData() async {
    final hasStoredToken = await widget.authService.isLoggedIn();
    final hasValidToken = await widget.authService.getValidAccessToken() != null;
    final stravaConnected = hasStoredToken || hasValidToken;
    // Step 1: serve from SQLite cache for the active source (empty when no source set).
    final cached = await _db.getCachedActivities(source: 'strava');
    final cachedAthlete = await _db.getCachedAthleteProfile();

    if (cached.isNotEmpty && cachedAthlete != null) {
      if (mounted) {
        setState(() {
          _activities = cached;
          _isFirstLoad = false;
        });
        widget.onAthleteLoaded(cachedAthlete.firstname);
        widget.onAthleteProfileLoaded?.call(cachedAthlete);
      }
    }

    // Step 2: background delta sync (Strava only).
    if (stravaConnected) {
      await _syncFromStrava(silent: cached.isNotEmpty);
    } else {
      if (mounted) {
        setState(() {
          _activities = cached;
          _isFirstLoad = false;
          _isRefreshing = false;
          _error = _connectSourcePrompt;
        });
      }
    }
  }

  Future<void> _refreshCurrentSource() async {
    final hasStoredToken = await widget.authService.isLoggedIn();
    final hasValidToken = await widget.authService.getValidAccessToken() != null;
    if (hasStoredToken || hasValidToken) {
      await _syncFromStrava();
      return;
    }
    if (mounted) {
      setState(() {
        _error = _connectSourcePrompt;
      });
    }
  }

  void _scheduleConnectPromptRecovery() {
    if (_connectRecoveryScheduled) return;
    _connectRecoveryScheduled = true;
    Future<void>(() async {
      try {
        final hasStoredToken = await widget.authService.isLoggedIn();
        final hasValidToken = await widget.authService.getValidAccessToken() != null;
        if (hasStoredToken || hasValidToken) {
          await _syncFromStrava(silent: _activities.isNotEmpty);
        }
      } finally {
        _connectRecoveryScheduled = false;
      }
    });
  }

  /// Syncs new activities from Strava.
  /// [silent] — if true, no full-screen spinner is shown (cache is already visible).
  Future<void> _syncFromStrava({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isFirstLoad = true);
    if (silent && mounted) setState(() => _isRefreshing = true);

    try {
      final accessToken = await widget.authService.getValidAccessToken();
      if (accessToken == null) {
        if (mounted) {
          setState(() {
            _error = 'Authentication failed. Please log in again.';
            _isFirstLoad = false;
            _isRefreshing = false;
          });
        }
        return;
      }

      final api = StravaApiService(accessToken: accessToken);

      // Always fetch athlete profile so we get latest gear (bikes/shoes require profile:read_all scope).
      // Update cache only when absent or older than 24 h to avoid unnecessary UI churn.
      final profileMap = await api.getAthleteProfile();
      final gearList = StravaApiService.mapGearFromAthleteProfile(profileMap);
      if (gearList.isNotEmpty) await _db.upsertGear(gearList);

      final cachedAt = await _db.getAthleteProfileCachedAt();
      final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (cachedAt == null || (nowSeconds - cachedAt) > 86400) {
        final athlete = StravaAthlete.fromJson(profileMap);
        await _db.saveAthleteProfile(athlete);
        if (mounted) {
          widget.onAthleteLoaded(athlete.firstname);
          widget.onAthleteProfileLoaded?.call(athlete);
        }
      } else if (mounted) {
        final athlete = await _db.getCachedAthleteProfile();
        if (athlete != null) {
          widget.onAthleteLoaded(athlete.firstname);
          widget.onAthleteProfileLoaded?.call(athlete);
        }
      }

      // Delta fetch: only activities newer than the latest cached one for this source.
      final latestEpoch = await _db.getLatestActivityEpoch(source: 'strava');
      final afterTimestamp = latestEpoch ??
          (DateTime.now()
                  .subtract(const Duration(days: 30))
                  .millisecondsSinceEpoch ~/
              1000);

      final newActivities = await api.getRecentActivities(
        after: afterTimestamp,
        perPage: 100,
      );

      if (newActivities.isNotEmpty) {
        await _db.upsertActivities(newActivities);
      }

      // Reload the full sorted list from SQLite for this source.
      final all = await _db.getCachedActivities(source: 'strava');
      if (mounted) {
        setState(() {
          _activities = all;
          _isFirstLoad = false;
          _isRefreshing = false;
          _error = null;
        });
        // Prefetch full details (splits) in background so detail screen opens instantly.
        _prefetchActivityDetailsInBackground();
      }
    } on SocketException catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyDashboardError(e.toString());
          _isFirstLoad = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyDashboardError(e.toString());
          _isFirstLoad = false;
          _isRefreshing = false;
        });
      }
    }
  }

  /// Fetches full activity details (splits, etc.) in background and upserts into cache.
  /// No UI blocking; when user taps an activity, details are already there for instant open.
  void _prefetchActivityDetailsInBackground() {
    Future<void>(() async {
      try {
        final accessToken = await widget.authService.getValidAccessToken();
        if (accessToken == null) return;
        final api = StravaApiService(accessToken: accessToken);
        const maxPrefetch = 30;
        for (var i = 0; i < _activities.length && i < maxPrefetch; i++) {
          final a = _activities[i];
          if (a.source != null && a.source != 'strava') continue;
          if (a.canonicalSegments.isNotEmpty) continue;
          try {
            final full = await api.getActivityDetails(a.id);
            await _db.upsertActivities([full]);
          } catch (_) {}
          if (!mounted) return;
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isFirstLoad) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _activities.isEmpty) {
      if (_error == _connectSourcePrompt) {
        _scheduleConnectPromptRecovery();
      }
      // Signed in with Google (or other) but no Strava: prompt to connect in Settings.
      final hasFirebaseUser = FirebaseAuthService().currentUser != null;
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_run,
              size: 56,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              _error == _connectSourcePrompt
                  ? _connectSourcePrompt
                  : (_error ?? 'Could not load activities'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (hasFirebaseUser && _error == _connectSourcePrompt) ...[
              const SizedBox(height: 8),
              Text(
                'Go to Settings to connect Strava and sync workouts.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(
                      authService: widget.authService,
                      onThemeModeChanged: widget.onThemeModeChanged,
                    ),
                  ),
                ),
                icon: const Icon(Icons.settings, size: 20),
                label: const Text('Open Settings'),
              ),
            ] else ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _refreshCurrentSource,
                child: Text(_error == _connectSourcePrompt ? 'Retry' : 'Refresh'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isRefreshing)
          const LinearProgressIndicator(minHeight: 2),
        WeeklySummaryPanel(activities: _activities),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Recent activities',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Tap for details',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _activities.isEmpty
              ? const Center(child: Text('No recent activities found.'))
              : RefreshIndicator(
                  onRefresh: _refreshCurrentSource,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _activities.length,
                    itemBuilder: (context, index) {
                      final activity = _activities[index];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            // Use cached full activity (with splits) if prefetched, for instant open.
                            final toShow = await _db.getCachedActivityById(activity.id) ?? activity;
                            if (!context.mounted) return;
                            final result = await Navigator.of(context).push<StravaActivity>(
                              MaterialPageRoute(
                                builder: (_) => ActivityDetailPage(
                                  activity: toShow,
                                  authService: widget.authService,
                                ),
                              ),
                            );
                            if (result != null && mounted && widget.onDiscussWithCoach != null) {
                              widget.onDiscussWithCoach!(result);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                          highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                          child: ActivityCard(activity: activity),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}