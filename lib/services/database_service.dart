import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:stridemind/models/nutrition_plan.dart';
import 'package:stridemind/models/runner_profile.dart';
import 'package:stridemind/models/gear.dart';
import 'package:stridemind/models/strava_activity.dart';
import 'package:stridemind/models/strava_athlete.dart';
import 'package:stridemind/models/training_plan.dart';
import 'package:stridemind/services/firestore_service.dart';
import 'package:stridemind/utils/training_plan_storage_config.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;
  final FirestoreService _firestoreService = FirestoreService();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'stridemind.db');

    return await openDatabase(
      path,
      version: 9,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE conversation_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        log TEXT NOT NULL,
        feedback TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE training_plan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        plan_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE nutrition_plan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        plan_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE strava_activities (
        id INTEGER PRIMARY KEY,
        data_json TEXT NOT NULL,
        start_date_epoch INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT 'strava'
      )
    ''');
    await db.execute('''
      CREATE TABLE athlete_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        data_json TEXT NOT NULL,
        cached_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE gear (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        strava_gear_id TEXT UNIQUE,
        name TEXT NOT NULL,
        brand TEXT,
        model TEXT,
        nickname TEXT,
        notes TEXT,
        distance_km REAL NOT NULL,
        notify_at_km INTEGER,
        source TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE runner_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        data_json TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE training_plan (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          plan_json TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE nutrition_plan (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          plan_json TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE strava_activities (
          id INTEGER PRIMARY KEY,
          data_json TEXT NOT NULL,
          start_date_epoch INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE athlete_profile (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          data_json TEXT NOT NULL,
          cached_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE gear (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          strava_gear_id TEXT UNIQUE,
          name TEXT NOT NULL,
          brand TEXT,
          model TEXT,
          nickname TEXT,
          notes TEXT,
          distance_km REAL NOT NULL,
          notify_at_km INTEGER,
          source TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 6) {
      try {
        await db.execute(
          "ALTER TABLE strava_activities ADD COLUMN source TEXT NOT NULL DEFAULT 'strava'",
        );
      } catch (_) {
        // Column may already exist in some dev setups
      }
    }
    if (oldVersion < 7) {
      try {
        await db.execute('ALTER TABLE gear ADD COLUMN gear_type TEXT');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS runner_profile (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          data_json TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 9) {
      try {
        await db.execute(
          'ALTER TABLE training_plan ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }
  }

  Future<void> addConversationTurn(Map<String, dynamic> turn) async {
    final db = await database;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      'conversation_history',
      {
        'log': turn['log'],
        'feedback': jsonEncode(turn['feedback']), // Encode the whole feedback object
        'timestamp': timestamp,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _trimHistory();

    // Sync to Firestore for cloud backup
    await _firestoreService.addConversationTurn(turn, timestamp);
  }

  Future<List<Map<String, dynamic>>> getConversationHistory() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'conversation_history',
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return {
        'id': maps[i]['id'],
        'log': maps[i]['log'],
        'feedback': jsonDecode(maps[i]['feedback']), // Decode it back
        'timestamp': maps[i]['timestamp'],
      };
    });
  }

  // ---------------------------------------------------------------------------
  // Training plan storage
  // ---------------------------------------------------------------------------

  /// Returns count of plans. [includeArchived] false = only non-archived (default).
  /// Treats NULL archived as non-archived so plans show after migration.
  Future<int> getTrainingPlanCount({bool includeArchived = false}) async {
    final db = await database;
    final where = includeArchived ? null : 'COALESCE(archived, 0) = 0';
    final result = await db.query(
      'training_plan',
      where: where,
      columns: ['id'],
    );
    return result.length;
  }

  /// Returns all plans with row id, isActive, archived. Newest first.
  /// When [includeArchived] false, returns only non-archived (COALESCE(archived,0)=0).
  Future<List<Map<String, dynamic>>> getAllTrainingPlanRows({
    bool includeArchived = false,
  }) async {
    final db = await database;
    final where = includeArchived ? null : 'COALESCE(archived, 0) = 0';
    final rows = await db.query(
      'training_plan',
      where: where,
      orderBy: 'created_at DESC',
    );
    return rows;
  }

  Future<void> saveTrainingPlan(TrainingPlan plan) async {
    final db = await database;
    final count = await getTrainingPlanCount(includeArchived: false);
    if (count >= TrainingPlanStorageConfig.maxPlansLocal) {
      final oldest = await db.query(
        'training_plan',
        where: 'COALESCE(archived, 0) = 0',
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (oldest.isNotEmpty) {
        await db.update(
          'training_plan',
          {'archived': 1},
          where: 'id = ?',
          whereArgs: [oldest.first['id']],
        );
      }
    }
    await db.update('training_plan', {'is_active': 0});
    await db.insert('training_plan', {
      'name': plan.name,
      'plan_json': plan.toJsonString(),
      'created_at': plan.createdAt,
      'is_active': 1,
      'archived': 0,
    });
    _firestoreService.savePlan('training', plan.name, plan.toJsonString());
  }

  /// Updates the currently active plan row with new JSON (for in-place edits: mark complete, edit details, etc.).
  /// Returns true if a row was updated, false if there was no active row (caller may then save as new).
  Future<bool> updateActiveTrainingPlan(TrainingPlan plan) async {
    final db = await database;
    final rows = await db.query(
      'training_plan',
      where: 'is_active = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    await db.update(
      'training_plan',
      {'plan_json': plan.toJsonString()},
      where: 'id = ?',
      whereArgs: [rows.first['id']],
    );
    return true;
  }

  Future<TrainingPlan?> getActiveTrainingPlan() async {
    final db = await database;
    final rows = await db.query(
      'training_plan',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      try {
        final planMap = jsonDecode(rows.first['plan_json'] as String)
            as Map<String, dynamic>;
        return TrainingPlan.fromJson(planMap);
      } catch (_) {
        return null;
      }
    }
    // SQLite empty — attempt a one-time restore from Firestore (new device / reinstall).
    try {
      final remote = await _firestoreService.getPlan('training');
      if (remote != null && remote['plan_json'] != null) {
        final plan = TrainingPlan.fromJson(
            jsonDecode(remote['plan_json'] as String) as Map<String, dynamic>);
        await saveTrainingPlan(plan);
        return plan;
      }
    } catch (_) {}
    return null;
  }

  Future<void> deleteActiveTrainingPlan() async {
    final db = await database;
    final rows = await db.query(
      'training_plan',
      where: 'is_active = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final id = rows.first['id'] as int;
    await deleteTrainingPlanById(id);
  }

  Future<void> updateTrainingPlanArchived(int id, bool archived) async {
    final db = await database;
    if (archived) {
      final row = await db.query(
        'training_plan',
        where: 'id = ?',
        whereArgs: [id],
        columns: ['is_active'],
      );
      final wasActive = row.isNotEmpty && (row.first['is_active'] as int) == 1;
      await db.update(
        'training_plan',
        {'archived': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (wasActive) {
        final next = await db.query(
          'training_plan',
          where: 'id != ? AND archived = 0',
          whereArgs: [id],
          orderBy: 'created_at DESC',
          limit: 1,
        );
        if (next.isNotEmpty) {
          await db.update('training_plan', {'is_active': 0});
          await db.update(
            'training_plan',
            {'is_active': 1},
            where: 'id = ?',
            whereArgs: [next.first['id']],
          );
        } else {
          await db.update('training_plan', {'is_active': 0});
        }
      }
    } else {
      await db.update(
        'training_plan',
        {'archived': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deleteTrainingPlanById(int id) async {
    final db = await database;
    final wasActive = await db.query(
      'training_plan',
      where: 'id = ?',
      whereArgs: [id],
      columns: ['is_active'],
    );
    final isActive = wasActive.isNotEmpty && (wasActive.first['is_active'] as int) == 1;
    await db.delete('training_plan', where: 'id = ?', whereArgs: [id]);
    if (isActive) {
      final next = await db.query(
        'training_plan',
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (next.isNotEmpty) {
        await db.update(
          'training_plan',
          {'is_active': 1},
          where: 'id = ?',
          whereArgs: [next.first['id']],
        );
      }
    }
  }

  Future<void> setActiveTrainingPlan(int id) async {
    final db = await database;
    await db.update('training_plan', {'is_active': 0});
    await db.update(
      'training_plan',
      {'is_active': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearActiveTrainingPlan() async {
    final db = await database;
    await db.update('training_plan', {'is_active': 0});
  }

  // ---------------------------------------------------------------------------
  // Nutrition plan storage
  // ---------------------------------------------------------------------------

  Future<void> saveNutritionPlan(NutritionPlan plan) async {
    final db = await database;
    await db.update('nutrition_plan', {'is_active': 0});
    await db.insert('nutrition_plan', {
      'name': plan.name,
      'plan_json': plan.toJsonString(),
      'created_at': plan.createdAt,
      'is_active': 1,
    });
    // Cloud backup — fire and forget (non-critical path)
    _firestoreService.savePlan('nutrition', plan.name, plan.toJsonString());
  }

  Future<NutritionPlan?> getActiveNutritionPlan() async {
    final db = await database;
    final rows = await db.query(
      'nutrition_plan',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      try {
        final planMap = jsonDecode(rows.first['plan_json'] as String)
            as Map<String, dynamic>;
        return NutritionPlan.fromJson(planMap);
      } catch (_) {
        return null;
      }
    }
    // SQLite empty — attempt a one-time restore from Firestore (new device / reinstall).
    try {
      final remote = await _firestoreService.getPlan('nutrition');
      if (remote != null && remote['plan_json'] != null) {
        final plan = NutritionPlan.fromJson(
            jsonDecode(remote['plan_json'] as String) as Map<String, dynamic>);
        await saveNutritionPlan(plan);
        return plan;
      }
    } catch (_) {}
    return null;
  }

  Future<void> deleteActiveNutritionPlan() async {
    final db = await database;
    await db.delete('nutrition_plan', where: 'is_active = ?', whereArgs: [1]);
  }

  // ---------------------------------------------------------------------------
  // Strava activity cache
  // ---------------------------------------------------------------------------

  Future<void> upsertActivities(List<StravaActivity> activities) async {
    final db = await database;
    final batch = db.batch();
    for (final activity in activities) {
      final source = activity.source ?? 'strava';
      batch.insert(
        'strava_activities',
        {
          'id': activity.id,
          'data_json': jsonEncode(activity.toJson()),
          'start_date_epoch':
              activity.startDateLocal.millisecondsSinceEpoch ~/ 1000,
          'source': source,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// [source] if non-null returns only activities for that source ('strava' | 'samsung_health').
  Future<List<StravaActivity>> getCachedActivities({String? source}) async {
    final db = await database;
    final rows = await db.query(
      'strava_activities',
      where: source != null ? 'source = ?' : null,
      whereArgs: source != null ? [source] : null,
      orderBy: 'start_date_epoch DESC',
    );
    return rows.map((r) {
      final data = jsonDecode(r['data_json'] as String) as Map<String, dynamic>;
      final rowSource = r['source'] as String?;
      if (rowSource != null) data['source'] = rowSource;
      return StravaActivity.fromJson(data);
    }).toList();
  }

  /// Returns a single cached activity by id (e.g. full details with splits if prefetched).
  Future<StravaActivity?> getCachedActivityById(int id) async {
    final db = await database;
    final rows =
        await db.query('strava_activities', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return StravaActivity.fromJson(
        jsonDecode(rows.first['data_json'] as String));
  }

  /// Returns the Unix epoch (seconds) of the most recently cached activity for [source], or null if empty.
  Future<int?> getLatestActivityEpoch({String? source}) async {
    final db = await database;
    final result = source != null
        ? await db.rawQuery(
            'SELECT MAX(start_date_epoch) AS latest FROM strava_activities WHERE source = ?',
            [source],
          )
        : await db.rawQuery(
            'SELECT MAX(start_date_epoch) AS latest FROM strava_activities',
          );
    return result.first['latest'] as int?;
  }

  // ---------------------------------------------------------------------------
  // Athlete profile cache
  // ---------------------------------------------------------------------------

  Future<void> saveAthleteProfile(StravaAthlete athlete) async {
    final db = await database;
    await db.insert(
      'athlete_profile',
      {
        'id': 1,
        'data_json': jsonEncode(athlete.toJson()),
        'cached_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<StravaAthlete?> getCachedAthleteProfile() async {
    final db = await database;
    final rows = await db.query('athlete_profile', where: 'id = 1');
    if (rows.isEmpty) return null;
    return StravaAthlete.fromJson(
        jsonDecode(rows.first['data_json'] as String));
  }

  Future<int?> getAthleteProfileCachedAt() async {
    final db = await database;
    final rows = await db.query('athlete_profile',
        columns: ['cached_at'], where: 'id = 1');
    if (rows.isEmpty) return null;
    return rows.first['cached_at'] as int?;
  }

  // ---------------------------------------------------------------------------
  // Runner profile (goals, race times, bio for coach)
  // ---------------------------------------------------------------------------

  Future<RunnerProfile?> getRunnerProfile() async {
    final db = await database;
    final rows = await db.query('runner_profile', where: 'id = 1');
    if (rows.isEmpty) return null;
    final data = rows.first['data_json'] as String?;
    if (data == null || data.isEmpty) return null;
    try {
      return RunnerProfile.fromJson(jsonDecode(data) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRunnerProfile(RunnerProfile profile) async {
    final db = await database;
    await db.insert(
      'runner_profile',
      {'id': 1, 'data_json': jsonEncode(profile.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // Gear (shoes, bikes from Strava or manual)
  // ---------------------------------------------------------------------------

  Future<void> upsertGear(List<Gear> items) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final g in items) {
      final created = g.createdAt;
      final updated = g.updatedAt;
      final row = {
        'name': g.name,
        'brand': g.brand,
        'model': g.model,
        'nickname': g.nickname,
        'notes': g.notes,
        'distance_km': g.distanceKm,
        'notify_at_km': g.notifyAtKm,
        'source': g.source,
        'created_at': created,
        'updated_at': updated,
        'gear_type': g.gearType,
      };
      if (g.stravaGearId != null && g.stravaGearId!.isNotEmpty) {
        final existingRows = await db.query(
          'gear',
          where: 'strava_gear_id = ?',
          whereArgs: [g.stravaGearId],
        );
        if (existingRows.isNotEmpty) {
          final existing = _gearFromRow(existingRows.first);
          await db.update(
            'gear',
            {
              ...row,
              'nickname': existing.nickname ?? g.nickname,
              'notes': existing.notes ?? g.notes,
              'notify_at_km': existing.notifyAtKm ?? g.notifyAtKm,
              'updated_at': now,
            },
            where: 'strava_gear_id = ?',
            whereArgs: [g.stravaGearId],
          );
        } else {
          await db.insert('gear', {
            ...row,
            'strava_gear_id': g.stravaGearId,
            'created_at': now,
            'updated_at': now,
          });
        }
      } else {
        await db.insert('gear', {
          ...row,
          'strava_gear_id': null,
          'created_at': g.createdAt > 0 ? created : now,
          'updated_at': g.updatedAt > 0 ? updated : now,
        });
      }
    }
  }

  Future<List<Gear>> getAllGear() async {
    final db = await database;
    final rows = await db.query('gear', orderBy: 'updated_at DESC');
    return rows.map((r) => _gearFromRow(r)).toList();
  }

  Future<Gear?> getGearById(int id) async {
    final db = await database;
    final rows = await db.query('gear', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _gearFromRow(rows.first);
  }

  /// Returns gear matching the given Strava gear id (e.g. for activity gear_id).
  Future<Gear?> getGearByStravaId(String? stravaGearId) async {
    if (stravaGearId == null || stravaGearId.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'gear',
      where: 'strava_gear_id = ?',
      whereArgs: [stravaGearId],
    );
    if (rows.isEmpty) return null;
    return _gearFromRow(rows.first);
  }

  Future<void> updateGear(Gear gear) async {
    if (gear.id == null) return;
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.update(
      'gear',
      {
        'name': gear.name,
        'brand': gear.brand,
        'model': gear.model,
        'nickname': gear.nickname,
        'notes': gear.notes,
        'distance_km': gear.distanceKm,
        'notify_at_km': gear.notifyAtKm,
        'gear_type': gear.gearType,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [gear.id],
    );
  }

  Future<void> deleteGear(int id) async {
    final db = await database;
    await db.delete('gear', where: 'id = ?', whereArgs: [id]);
  }

  Gear _gearFromRow(Map<String, dynamic> r) {
    return Gear(
      id: r['id'] as int?,
      stravaGearId: r['strava_gear_id'] as String?,
      name: r['name'] as String,
      brand: r['brand'] as String?,
      model: r['model'] as String?,
      nickname: r['nickname'] as String?,
      notes: r['notes'] as String?,
      distanceKm: (r['distance_km'] as num).toDouble(),
      notifyAtKm: r['notify_at_km'] as int?,
      source: r['source'] as String,
      createdAt: r['created_at'] as int,
      updatedAt: r['updated_at'] as int,
      gearType: r['gear_type'] as String?,
    );
  }

  // ---------------------------------------------------------------------------

  Future<void> _trimHistory({int maxHistoryLength = 10}) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM conversation_history'));
    if (count != null && count > maxHistoryLength) {
      final toDeleteCount = count - maxHistoryLength;
      final oldestEntries = await db.query(
        'conversation_history',
        columns: ['id'],
        orderBy: 'timestamp ASC',
        limit: toDeleteCount,
      );
      final idsToDelete = oldestEntries.map((e) => e['id']).toList();
      if (idsToDelete.isNotEmpty) {
        await db.delete(
          'conversation_history',
          where: 'id IN (${idsToDelete.join(', ')})',
        );
      }
    }
  }
}