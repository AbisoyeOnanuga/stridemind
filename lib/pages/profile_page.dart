import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:stridemind/models/gear.dart';
import 'package:stridemind/models/runner_profile.dart';
import 'package:stridemind/models/strava_athlete.dart';
import 'package:stridemind/pages/login_page.dart';
import 'package:stridemind/pages/runner_profile_page.dart';
import 'package:stridemind/pages/settings_page.dart';
import 'package:stridemind/services/database_service.dart';
import 'package:stridemind/services/firebase_auth_service.dart';
import 'package:stridemind/services/shoe_library_service.dart';
import 'package:stridemind/services/strava_auth_service.dart';
import 'package:stridemind/services/strava_api_service.dart';

/// Profile: user info, what the app uses, gear placeholder, entry to Settings, Log out.
class ProfilePage extends StatefulWidget {
  final StravaAuthService authService;
  final void Function(ThemeMode)? onThemeModeChanged;

  const ProfilePage({
    super.key,
    required this.authService,
    this.onThemeModeChanged,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  StravaAthlete? _athlete;
  RunnerProfile? _runnerProfile;
  List<Gear> _gear = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final db = DatabaseService();
    final athlete = await db.getCachedAthleteProfile();
    final runnerProfile = await db.getRunnerProfile();
    // Sync gear from Strava whenever we have a token (merge preserves local nickname/notes/notify).
    try {
      final token = await widget.authService.getValidAccessToken();
      if (token != null) {
        final profileMap = await StravaApiService(accessToken: token).getAthleteProfile();
        var gearList = StravaApiService.mapGearFromAthleteProfile(profileMap);
        if (gearList.isNotEmpty) {
          gearList = await StravaApiService(accessToken: token).enrichGearWithDetails(gearList);
          await db.upsertGear(gearList);
        }
      }
    } catch (e) {
      debugPrint('Profile: Strava gear sync failed: $e');
    }
    final gear = await db.getAllGear();
    if (mounted) {
      setState(() {
        _athlete = athlete;
        _runnerProfile = runnerProfile;
        _gear = gear;
        _loading = false;
      });
    }
  }

  Future<void> _showAddGearDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add shoe'),
        content: const Text(
          'Choose from the shoe library (brand + model) or enter details manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'custom'),
            child: const Text('Enter custom'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'library'),
            child: const Text('From library'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'library') {
      final picked = await _showShoeLibraryPicker();
      if (picked != null && mounted) {
        final result = await showDialog<Gear>(
          context: context,
          builder: (ctx) => _AddGearDialog(prefillBrand: picked.$1, prefillModel: picked.$2),
        );
        if (result != null && mounted) await _loadProfile();
      }
      return;
    }
    final result = await showDialog<Gear>(
      context: context,
      builder: (ctx) => const _AddGearDialog(),
    );
    if (result != null && mounted) await _loadProfile();
  }

  Future<(String brand, String model)?> _showShoeLibraryPicker() async {
    final library = ShoeLibraryService();
    final brands = await library.getBrands();
    if (brands.isEmpty) return null;
    if (!mounted) return null;
    String? selectedBrand;
    List<String> models = [];
    return showDialog<(String, String)?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setState) {
            if (selectedBrand == null) {
              return AlertDialog(
                title: const Text('Select brand'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: brands.length,
                    itemBuilder: (_, i) {
                      final b = brands[i];
                      return ListTile(
                        title: Text(b.name),
                        onTap: () async {
                          final m = await library.getModelsForBrand(b.name);
                          setState(() {
                            selectedBrand = b.name;
                            models = m;
                          });
                        },
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('Cancel'),
                  ),
                ],
              );
            }
            return AlertDialog(
              title: Text('Select model · $selectedBrand'),
              content: SizedBox(
                width: double.maxFinite,
                child: models.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No models in library for this brand. Use “Enter custom” instead.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: models.length,
                        itemBuilder: (_, i) {
                          final model = models[i];
                          return ListTile(
                            title: Text(model),
                            onTap: () => Navigator.pop(ctx, (selectedBrand!, model)),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() {
                    selectedBrand = null;
                    models = [];
                  }),
                  child: const Text('Back'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditGearDialog(Gear gear) async {
    final result = await showDialog<Gear>(
      context: context,
      builder: (ctx) => _AddGearDialog(initial: gear),
    );
    if (result != null && mounted) await _loadProfile();
  }

  Future<void> _confirmDeleteGear(Gear gear) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Remove gear?'),
          content: Text(
            gear.source == 'strava'
                ? 'This will remove "${gear.displayName}" from the app. It will reappear when Strava syncs.'
                : 'This will permanently remove "${gear.displayName}".',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: t.colorScheme.error),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirm == true && gear.id != null && mounted) {
      await DatabaseService().deleteGear(gear.id!);
      await _loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              children: [
                if (_athlete != null) ...[
                  _ProfileHeader(athlete: _athlete!),
                  const SizedBox(height: 24),
                ] else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Connect Strava to see your profile.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                Text(
                  'What the app uses',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your coach uses your activities, training plan, and preferences to personalize feedback. Connect Strava in Settings to sync workouts.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Training profile'),
                  subtitle: Text(_runnerProfile == null || _runnerProfile!.isEmpty
                      ? 'Goals, race times, notes for the coach'
                      : _runnerProfileSummary(_runnerProfile!)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RunnerProfilePage(isOnboarding: false),
                      ),
                    );
                    _loadProfile();
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Gear',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showAddGearDialog,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add gear'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_gear.isEmpty)
                  Text(
                    'Shoes and gear from Strava appear here, or add your own.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ..._gear.map((g) => ListTile(
                        leading: Icon(_iconForGear(g), size: 28),
                        title: Text(g.displayName),
                        subtitle: Text([
                          if (g.brand != null || g.model != null)
                            '${g.brand ?? ''} ${g.model ?? ''}'.trim(),
                          '${g.distanceKm.toStringAsFixed(0)} km',
                          if (g.source == 'strava') 'Strava',
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (g.notifyAtKm != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  'Notify at ${g.notifyAtKm} km',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (value) async {
                                if (value == 'edit') await _showEditGearDialog(g);
                                if (value == 'delete') await _confirmDeleteGear(g);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Remove')),
                              ],
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 32),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Settings'),
                  subtitle: const Text('Connect app, Legal, About, Account'),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsPage(
                          authService: widget.authService,
                          onThemeModeChanged: widget.onThemeModeChanged,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    await FirebaseAuthService().signOut();
                    await widget.authService.logout();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => LoginPage(authService: widget.authService),
                      ),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),
              ],
            ),
    );
  }
}

/// Standard lifespan distances (km) for "notify when reached".
const List<int> _notifyAtKmOptions = [400, 500, 600, 800, 1000, 1200];

IconData _iconForGear(Gear g) {
  final type = g.gearType?.toLowerCase();
  if (type == 'bike') return Icons.directions_bike;
  if (type == 'hiking' || type == 'hike') return Icons.directions_walk;
  if (type == 'shoe' || type == 'run') return MdiIcons.shoeSneaker;
  final name = (g.name).toLowerCase();
  if (name.contains('bike')) return Icons.directions_bike;
  if (name.contains('hike') || name.contains('trail') || name.contains('hiking')) return Icons.directions_walk;
  return MdiIcons.shoeSneaker;
}

String _runnerProfileSummary(RunnerProfile p) {
  final parts = <String>[];
  if (p.targetGoal != null && p.targetGoal!.isNotEmpty) parts.add(p.targetGoal!);
  if (p.raceTime5k != null && p.raceTime5k!.isNotEmpty) parts.add('5K ${p.raceTime5k}');
  if (p.raceTime10k != null && p.raceTime10k!.isNotEmpty) parts.add('10K ${p.raceTime10k}');
  if (p.raceTimeHalfMarathon != null && p.raceTimeHalfMarathon!.isNotEmpty) parts.add('HM ${p.raceTimeHalfMarathon}');
  if (p.raceTimeMarathon != null && p.raceTimeMarathon!.isNotEmpty) parts.add('M ${p.raceTimeMarathon}');
  return parts.isEmpty ? 'Goals, race times, notes for the coach' : parts.join(' · ');
}

class _AddGearDialog extends StatefulWidget {
  final Gear? initial;
  final String? prefillBrand;
  final String? prefillModel;

  const _AddGearDialog({this.initial, this.prefillBrand, this.prefillModel});

  @override
  State<_AddGearDialog> createState() => _AddGearDialogState();
}

class _AddGearDialogState extends State<_AddGearDialog> {
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _distanceController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _scrollController = ScrollController();
  bool _notifyWhenReached = false;
  int? _notifyAtKm;
  bool _isStravaGear = false;

  bool get _fromLibrary => widget.prefillBrand != null && widget.prefillModel != null;

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    if (g != null) {
      _nameController.text = g.name;
      _brandController.text = g.brand ?? '';
      _modelController.text = g.model ?? '';
      _nicknameController.text = g.nickname ?? '';
      _distanceController.text = g.distanceKm.toStringAsFixed(0);
      _notesController.text = g.notes ?? '';
      _notifyWhenReached = g.notifyAtKm != null;
      _notifyAtKm = g.notifyAtKm;
      _isStravaGear = g.source == 'strava';
    } else if (_fromLibrary) {
      final brand = widget.prefillBrand!;
      final model = widget.prefillModel!;
      _nameController.text = '$brand $model';
      _brandController.text = brand;
      _modelController.text = model;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _nicknameController.dispose();
    _distanceController.dispose();
    _notesController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLifespan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    final distance = double.tryParse(_distanceController.text.trim()) ?? 0.0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final existing = widget.initial;
    Gear? result;
    if (existing != null && existing.id != null) {
      result = Gear(
        id: existing.id,
        stravaGearId: existing.stravaGearId,
        name: _isStravaGear ? existing.name : name,
        brand: _isStravaGear ? existing.brand : (_brandController.text.trim().isEmpty ? null : _brandController.text.trim()),
        model: _isStravaGear ? existing.model : (_modelController.text.trim().isEmpty ? null : _modelController.text.trim()),
        nickname: _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        distanceKm: distance,
        notifyAtKm: _notifyWhenReached ? _notifyAtKm : null,
        source: existing.source,
        createdAt: existing.createdAt,
        updatedAt: now,
        gearType: existing.gearType,
      );
      await DatabaseService().updateGear(result);
    } else {
      result = Gear(
        name: name,
        brand: _brandController.text.trim().isEmpty ? null : _brandController.text.trim(),
        model: _modelController.text.trim().isEmpty ? null : _modelController.text.trim(),
        nickname: _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        distanceKm: distance,
        notifyAtKm: _notifyWhenReached ? _notifyAtKm : null,
        source: 'manual',
        createdAt: now,
        updatedAt: now,
        gearType: 'shoe',
      );
      await DatabaseService().upsertGear([result]);
    }
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.initial != null;
    final readOnlyNameBrandModel = _isStravaGear || _fromLibrary;
    return AlertDialog(
      title: Text(isEdit ? 'Edit gear' : 'Add shoe'),
      content: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              readOnly: readOnlyNameBrandModel,
              decoration: InputDecoration(
                labelText: 'Name *',
                hintText: 'e.g. Nike Pegasus 40',
                helperText: _isStravaGear ? 'From Strava' : (_fromLibrary ? 'From library' : null),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _brandController,
              readOnly: readOnlyNameBrandModel,
              decoration: InputDecoration(
                labelText: 'Brand',
                hintText: 'e.g. Nike',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              readOnly: readOnlyNameBrandModel,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'e.g. Pegasus 40',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                hintText: 'e.g. Daily trainers',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _distanceController,
              decoration: const InputDecoration(
                labelText: 'Current distance (km)',
                hintText: '0',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Optional',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _notifyWhenReached,
                  onChanged: (v) {
                    setState(() {
                      _notifyWhenReached = v ?? false;
                      if (_notifyWhenReached && _notifyAtKm == null) {
                        _notifyAtKm = _notifyAtKmOptions.first;
                      }
                    });
                    if (_notifyWhenReached) _scrollToLifespan();
                  },
                ),
                Expanded(
                  child: Text(
                    'Notify when I\'ve reached',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (_notifyWhenReached) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                key: ValueKey('notifyAtKm-${_notifyAtKm ?? _notifyAtKmOptions.first}'),
                initialValue: _notifyAtKm ?? _notifyAtKmOptions.first,
                decoration: const InputDecoration(
                  labelText: 'Lifespan (km)',
                ),
                items: _notifyAtKmOptions
                    .map((km) => DropdownMenuItem(value: km, child: Text('$km km')))
                    .toList(),
                onChanged: (v) => setState(() => _notifyAtKm = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final StravaAthlete athlete;

  const _ProfileHeader({required this.athlete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = '${athlete.firstname} ${athlete.lastname}'.trim();

    return Row(
      children: [
        if (athlete.profileMedium != null || athlete.profile != null)
          CircleAvatar(
            radius: 40,
            backgroundImage: NetworkImage(athlete.profile ?? athlete.profileMedium!),
          )
        else
          CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              athlete.firstname.isNotEmpty
                  ? athlete.firstname.substring(0, 1).toUpperCase()
                  : '?',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isNotEmpty ? name : 'Strava athlete',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (athlete.username != null && athlete.username!.isNotEmpty)
                Text(
                  '@${athlete.username}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
