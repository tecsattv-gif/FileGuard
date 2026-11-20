import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fs.dart';

/// Ajustes do app (guardados no telefone e no backup).
class Prefs {
  static bool showHidden = false;
  static SortBy sortBy = SortBy.name;
  static bool sortAsc = true;
  static bool foldersFirst = true;
  static bool grid = false;
  static bool useTrash = true;
  static List<String> favorites = [];

  /// Avisa as telas quando algum ajuste muda.
  static final changed = ValueNotifier<int>(0);

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('prefs');
      if (raw != null) fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  static Future<void> save() async {
    changed.value++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('prefs', jsonEncode(toJson()));
    } catch (_) {}
  }

  static Map<String, dynamic> toJson() => {
        'showHidden': showHidden,
        'sortBy': sortBy.name,
        'sortAsc': sortAsc,
        'foldersFirst': foldersFirst,
        'grid': grid,
        'useTrash': useTrash,
        'favorites': favorites,
      };

  static void fromJson(Map<String, dynamic> m) {
    showHidden = m['showHidden'] == true;
    sortBy = SortBy.values.firstWhere((s) => s.name == m['sortBy'],
        orElse: () => SortBy.name);
    sortAsc = m['sortAsc'] != false;
    foldersFirst = m['foldersFirst'] != false;
    grid = m['grid'] == true;
    useTrash = m['useTrash'] != false;
    favorites = ((m['favorites'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  static bool isFavorite(String path) => favorites.contains(path);

  static Future<void> toggleFavorite(String path) async {
    if (favorites.contains(path)) {
      favorites.remove(path);
    } else {
      favorites.add(path);
    }
    await save();
  }
}
