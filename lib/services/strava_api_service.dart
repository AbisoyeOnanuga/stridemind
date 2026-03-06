import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:stridemind/models/gear.dart';
import 'package:stridemind/models/strava_activity.dart';

class StravaApiService {
  final String _accessToken;
  final String _baseUrl = 'https://www.strava.com/api/v3';

  StravaApiService({required String accessToken}) : _accessToken = accessToken;

  Future<StravaActivity> getActivityDetails(int activityId) async {
    final uri = Uri.parse('$_baseUrl/activities/$activityId');
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
      },
    );

    if (response.statusCode == 200) {
      return StravaActivity.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load activity details: ${response.body}');
    }
  }

  /// Fetches the authenticated user's profile from Strava.
  /// Throws an exception if the request fails.
  Future<Map<String, dynamic>> getAthleteProfile() async {
    final url = Uri.parse('$_baseUrl/athlete');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $_accessToken'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch athlete profile: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<StravaActivity>> getRecentActivities(
      {int page = 1, int perPage = 30, int? after, int? before}) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (after != null) {
      queryParams['after'] = after.toString();
    }
    if (before != null) {
      queryParams['before'] = before.toString();
    }
    final uri = Uri.parse('$_baseUrl/athlete/activities').replace(queryParameters: queryParams);
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_accessToken',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> activitiesJson = jsonDecode(response.body);
      return activitiesJson
          .map((json) => StravaActivity.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to load activities: ${response.body}');
    }
  }

  /// Maps shoes and bikes from Strava athlete profile into [Gear]. Profile from getAthleteProfile().
  /// Athlete response includes id, name, distance; brand_name/model_name come from GET /gear/{id}.
  static List<Gear> mapGearFromAthleteProfile(Map<String, dynamic> profile) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final list = <Gear>[];
    for (final key in ['shoes', 'bikes']) {
      final items = profile[key];
      if (items is! List<dynamic> || items.isEmpty) continue;
      final gearType = key == 'shoes' ? 'shoe' : 'bike';
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        final id = map['id'];
        final name = map['name'] as String? ?? 'Unknown';
        final distanceM = (map['distance'] as num?)?.toDouble() ?? 0.0;
        final distanceKm = distanceM / 1000.0;
        list.add(Gear(
          stravaGearId: id?.toString(),
          name: name,
          brand: map['brand_name'] as String?,
          model: map['model_name'] as String?,
          distanceKm: distanceKm,
          source: 'strava',
          createdAt: now,
          updatedAt: now,
          gearType: gearType,
        ));
      }
    }
    return list;
  }

  /// Fetches gear details from Strava GET /gear/{id} for brand_name, model_name, description.
  /// [gearType] preserves shoe/bike when enriching so UI can show the right icon.
  Future<Gear> getGearDetail(String stravaGearId, {String? gearType}) async {
    final uri = Uri.parse('$_baseUrl/gear/$stravaGearId');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch gear: ${response.statusCode}');
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final distanceM = (map['distance'] as num?)?.toDouble() ?? 0.0;
    return Gear(
      stravaGearId: stravaGearId,
      name: map['name'] as String? ?? 'Unknown',
      brand: map['brand_name'] as String?,
      model: map['model_name'] as String?,
      notes: map['description'] as String?,
      distanceKm: distanceM / 1000.0,
      source: 'strava',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      gearType: gearType,
    );
  }

  /// Enriches gear list with GET /gear/{id} so we get brand_name, model_name (athlete profile only has id, name, distance).
  Future<List<Gear>> enrichGearWithDetails(List<Gear> gearList) async {
    final result = <Gear>[];
    for (final g in gearList) {
      if (g.stravaGearId == null || g.stravaGearId!.isEmpty) {
        result.add(g);
        continue;
      }
      try {
        final detail = await getGearDetail(g.stravaGearId!, gearType: g.gearType);
        result.add(Gear(
          stravaGearId: g.stravaGearId,
          name: detail.name,
          brand: detail.brand,
          model: detail.model,
          nickname: g.nickname,
          notes: g.notes ?? detail.notes,
          distanceKm: detail.distanceKm,
          notifyAtKm: g.notifyAtKm,
          source: 'strava',
          createdAt: g.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          gearType: g.gearType,
        ));
      } catch (_) {
        result.add(g);
      }
    }
    return result;
  }
}