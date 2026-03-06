import 'dart:convert';
import 'package:flutter/services.dart';

/// Shoe library: brands and models for "Add shoe" from library.
class ShoeLibraryService {
  static const String _assetPath = 'assets/data/shoe_library.json';

  List<ShoeBrand>? _cache;

  Future<List<ShoeBrand>> getBrands() async {
    if (_cache != null) return _cache!;
    final jsonStr = await rootBundle.loadString(_assetPath);
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = map['brands'] as List<dynamic>? ?? [];
    _cache = list
        .map((e) => ShoeBrand(
              name: e['name'] as String? ?? '',
              models: List<String>.from((e['models'] as List<dynamic>? ?? [])
                  .map((m) => m.toString())),
            ))
        .toList();
    return _cache!;
  }

  Future<List<String>> getModelsForBrand(String brandName) async {
    final brands = await getBrands();
    for (final b in brands) {
      if (b.name == brandName) return b.models;
    }
    return [];
  }
}

class ShoeBrand {
  final String name;
  final List<String> models;

  ShoeBrand({required this.name, required this.models});
}
