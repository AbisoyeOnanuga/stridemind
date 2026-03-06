import 'package:flutter/material.dart';
import 'package:stridemind/models/runner_profile.dart';
import 'package:stridemind/pages/home_page.dart';
import 'package:stridemind/services/database_service.dart';
import 'package:stridemind/services/strava_auth_service.dart';

const List<String> _targetGoalOptions = [
  'General fitness', '5K', '10K', 'Half marathon', 'Marathon', 'Ultra', 'Other',
];
const List<String> _experienceOptions = [
  'Beginner', 'Intermediate', 'Advanced', 'Elite', 'Prefer not to say',
];

/// Parses "H:MM:SS" or "MM:SS" to (hours, minutes, seconds). Returns null if invalid.
(int, int, int)? _parseDuration(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split(':');
  if (parts.length == 2) {
    final m = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    if (m != null && s != null && m >= 0 && m < 60 && s >= 0 && s < 60) return (0, m, s);
    return null;
  }
  if (parts.length == 3) {
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = int.tryParse(parts[2]);
    if (h != null && m != null && s != null && h >= 0 && m >= 0 && m < 60 && s >= 0 && s < 60) return (h, m, s);
    return null;
  }
  return null;
}

/// Formats (h, m, s) as "H:MM:SS" or "MM:SS" when h is 0.
String _formatDuration(int h, int m, int s) {
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Max total minutes per distance for feasible human times (upper bound).
const Map<String, int> _maxMinutesByDistance = {
  '5K': 50,
  '10K': 110,
  'Half marathon': 210,
  'Marathon': 360,
};

/// Onboarding or edit runner profile: goals, target event, race times, notes.
class RunnerProfilePage extends StatefulWidget {
  final bool isOnboarding;
  final StravaAuthService? authService;
  final void Function(ThemeMode)? onThemeModeChanged;

  const RunnerProfilePage({
    super.key,
    this.isOnboarding = false,
    this.authService,
    this.onThemeModeChanged,
  });

  @override
  State<RunnerProfilePage> createState() => _RunnerProfilePageState();
}

class _RunnerProfilePageState extends State<RunnerProfilePage> {
  final _db = DatabaseService();
  RunnerProfile _profile = const RunnerProfile();
  bool _loading = true;
  final _targetEventController = TextEditingController();
  final _notesController = TextEditingController();
  final _targetGoalOtherController = TextEditingController();

  String? _targetGoal;
  String? _targetDate;
  String? _raceTime5k;
  String? _raceTime10k;
  String? _raceTimeHm;
  String? _raceTimeM;
  String? _targetGoalTime;
  String? _experience;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _targetEventController.dispose();
    _notesController.dispose();
    _targetGoalOtherController.dispose();
    super.dispose();
  }

  void _applyProfileToControllers() {
    _targetGoal = _profile.targetGoal;
    if (_targetGoal != null && !_targetGoalOptions.contains(_targetGoal)) {
      _targetGoal = 'Other';
      _targetGoalOtherController.text = _profile.targetGoal!;
    } else if (_targetGoal != null && _targetGoalOptions.contains(_targetGoal)) {
      _targetGoalOtherController.clear();
    }
    _targetEventController.text = _profile.targetEventName ?? '';
    _targetDate = _profile.targetDate?.isNotEmpty == true ? _profile.targetDate : null;
    // Race times: accept "H:MM:SS" or "MM:SS"; legacy band strings are ignored (set null).
    _raceTime5k = _parseDuration(_profile.raceTime5k) != null ? _profile.raceTime5k : null;
    _raceTime10k = _parseDuration(_profile.raceTime10k) != null ? _profile.raceTime10k : null;
    _raceTimeHm = _parseDuration(_profile.raceTimeHalfMarathon) != null ? _profile.raceTimeHalfMarathon : null;
    _raceTimeM = _parseDuration(_profile.raceTimeMarathon) != null ? _profile.raceTimeMarathon : null;
    _targetGoalTime = _parseDuration(_profile.targetGoalTime) != null ? _profile.targetGoalTime : null;
    _experience = _profile.experienceLevel != null && _experienceOptions.contains(_profile.experienceLevel)
        ? _profile.experienceLevel
        : null;
    _notesController.text = _profile.notes ?? '';
  }

  Future<void> _load() async {
    final p = await _db.getRunnerProfile();
    if (mounted) {
      setState(() { _profile = p ?? const RunnerProfile(); _loading = false; });
      _applyProfileToControllers();
    }
  }

  Future<void> _save() async {
    final goal = _targetGoal == 'Other'
        ? (_targetGoalOtherController.text.trim().isEmpty ? null : _targetGoalOtherController.text.trim())
        : _targetGoal;
    _profile = _profile.copyWith(
      targetGoal: goal,
      targetEventName: _targetEventController.text.trim().isEmpty ? null : _targetEventController.text.trim(),
      targetDate: _targetDate,
      raceTime5k: _raceTime5k,
      raceTime10k: _raceTime10k,
      raceTimeHalfMarathon: _raceTimeHm,
      raceTimeMarathon: _raceTimeM,
      targetGoalTime: _targetGoalTime,
      experienceLevel: _experience,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );
    await _db.saveRunnerProfile(_profile);
    if (!widget.isOnboarding && mounted) {
      Navigator.of(context).pop(_profile);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved')),
      );
      return;
    }
    if (widget.isOnboarding && widget.authService != null && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(
            authService: widget.authService!,
            onThemeModeChanged: widget.onThemeModeChanged,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.isOnboarding ? 'Set up your profile' : 'Training profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOnboarding ? 'Set up your profile' : 'Training profile'),
        actions: [
          if (widget.isOnboarding)
            TextButton(
              onPressed: () async {
                await _db.saveRunnerProfile(const RunnerProfile());
                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => HomePage(
                      authService: widget.authService!,
                      onThemeModeChanged: widget.onThemeModeChanged,
                    ),
                  ),
                );
              },
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom + 80,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isOnboarding)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Help your coach give better advice. You can edit this anytime in Profile.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            DropdownButtonFormField<String?>(
              key: ValueKey('targetGoal-$_targetGoal'),
              initialValue: _targetGoal,
              decoration: const InputDecoration(
                labelText: 'Target goal',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Select…')),
                ..._targetGoalOptions.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
              ],
              onChanged: (v) => setState(() => _targetGoal = v),
            ),
            if (_targetGoal == 'Other') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _targetGoalOtherController,
                decoration: const InputDecoration(
                  labelText: 'Other goal',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _targetEventController,
              decoration: const InputDecoration(
                labelText: 'Target event',
                hintText: 'e.g. London Marathon 2026',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            ListTile(
              title: Text(_targetDate ?? 'Pick target date'),
              trailing: const Icon(Icons.calendar_today),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide()),
              onTap: () async {
                final now = DateTime.now();
                final initial = _targetDate != null
                    ? (DateTime.tryParse(_targetDate!) ?? now)
                    : now.add(const Duration(days: 90));
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial.isBefore(now) ? now : initial,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365 * 3)),
                );
                if (picked != null && mounted) {
                  setState(() => _targetDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
                }
              },
            ),
            if (_targetGoal != null && _maxMinutesByDistance.containsKey(_targetGoal!)) ...[
              const SizedBox(height: 12),
              Text('Target time for this goal', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _DurationPicker(
                label: _targetGoal!,
                value: _targetGoalTime,
                maxTotalMinutes: _maxMinutesByDistance[_targetGoal!]!,
                onChanged: (v) => setState(() => _targetGoalTime = v),
              ),
            ],
            const SizedBox(height: 16),
            Text('Race times (best or recent)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _DurationPicker(
              label: '5K',
              value: _raceTime5k,
              maxTotalMinutes: _maxMinutesByDistance['5K']!,
              onChanged: (v) => setState(() => _raceTime5k = v),
            ),
            const SizedBox(height: 8),
            _DurationPicker(
              label: '10K',
              value: _raceTime10k,
              maxTotalMinutes: _maxMinutesByDistance['10K']!,
              onChanged: (v) => setState(() => _raceTime10k = v),
            ),
            const SizedBox(height: 8),
            _DurationPicker(
              label: 'Half marathon',
              value: _raceTimeHm,
              maxTotalMinutes: _maxMinutesByDistance['Half marathon']!,
              onChanged: (v) => setState(() => _raceTimeHm = v),
            ),
            const SizedBox(height: 8),
            _DurationPicker(
              label: 'Marathon',
              value: _raceTimeM,
              maxTotalMinutes: _maxMinutesByDistance['Marathon']!,
              onChanged: (v) => setState(() => _raceTimeM = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('experience-$_experience'),
              initialValue: _experience,
              decoration: const InputDecoration(
                labelText: 'Experience level',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Select…')),
                ..._experienceOptions.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
              ],
              onChanged: (v) => setState(() => _experience = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Injuries, status, or anything else we should know',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: Text(widget.isOnboarding ? 'Done' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Time selector for race times: scroll/select hours, minutes, seconds with feasible max.
class _DurationPicker extends StatefulWidget {
  final String label;
  final String? value;
  final int maxTotalMinutes;
  final void Function(String?) onChanged;

  const _DurationPicker({
    required this.label,
    required this.value,
    required this.maxTotalMinutes,
    required this.onChanged,
  });

  @override
  State<_DurationPicker> createState() => _DurationPickerState();
}

class _DurationPickerState extends State<_DurationPicker> {
  late int _h;
  late int _m;
  late int _s;
  int get _maxHours => widget.maxTotalMinutes ~/ 60;
  int get _maxMinutesAtMaxHour => widget.maxTotalMinutes % 60;

  @override
  void initState() {
    super.initState();
    _applyValue(widget.value);
  }

  @override
  void didUpdateWidget(_DurationPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _applyValue(widget.value);
  }

  void _applyValue(String? value) {
    final parsed = _parseDuration(value);
    if (parsed != null) {
      _h = parsed.$1;
      _m = parsed.$2;
      _s = parsed.$3;
      _clampToMax();
    } else {
      _h = 0;
      _m = 0;
      _s = 0;
    }
  }

  void _clampToMax() {
    final maxH = _maxHours;
    final maxMAtH = _maxMinutesAtMaxHour;
    if (_h == maxH && _m > maxMAtH) _m = maxMAtH;
    final totalSec = _h * 3600 + _m * 60 + _s;
    final maxSec = widget.maxTotalMinutes * 60;
    if (totalSec <= maxSec) return;
    final clamped = maxSec;
    _h = clamped ~/ 3600;
    _m = (clamped % 3600) ~/ 60;
    _s = clamped % 60;
  }

  void _notify() {
    if (_h == 0 && _m == 0 && _s == 0) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(_formatDuration(_h, _m, _s));
  }

  @override
  Widget build(BuildContext context) {
    final maxH = _maxHours;
    final maxMAtH = _maxMinutesAtMaxHour;
    final minChoices = List.generate(60, (i) => i);
    final hourChoices = List.generate(maxH + 1, (i) => i);
    final minuteChoices = _h == maxH
        ? List.generate(maxMAtH + 1, (i) => i)
        : List.generate(60, (i) => i);

    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 72,
            child: DropdownButtonFormField<int>(
              key: ValueKey('duration-h-$_h'),
              initialValue: _h,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              items: hourChoices.map((v) => DropdownMenuItem(value: v, child: Text('${v}h'))).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() { _h = v; _clampToMax(); _notify(); });
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: DropdownButtonFormField<int>(
              key: ValueKey('duration-m-$_m'),
              initialValue: _m.clamp(0, minuteChoices.last),
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              items: minuteChoices.map((v) => DropdownMenuItem(value: v, child: Text('${v}m'))).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() { _m = v; _clampToMax(); _notify(); });
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: DropdownButtonFormField<int>(
              key: ValueKey('duration-s-$_s'),
              initialValue: _s.clamp(0, 59),
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              items: minChoices.map((v) => DropdownMenuItem(value: v, child: Text('${v}s'))).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() { _s = v; _notify(); });
              },
            ),
          ),
        ],
      ),
    );
  }
}
