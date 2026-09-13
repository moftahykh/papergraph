import 'package:hive_flutter/hive_flutter.dart';
import '../../models/canonical_paper.dart';
import '../../models/graph_models.dart';
import '../../models/paper_model.dart';

class HiveService {
  static const String favoritesBoxName = 'papergraph_favorites';
  static const String settingsBoxName = 'papergraph_settings';
  static const String canonicalPapersBoxName = 'papergraph_canonical_papers';
  static const String cachedGraphsBoxName = 'papergraph_cached_graphs';
  static const String paperNotesBoxName = 'papergraph_paper_notes';

  /// Supported schema version for cached literature graphs.
  static const int currentGraphSchemaVersion = 1;

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(favoritesBoxName);
    await Hive.openBox(settingsBoxName);
    await Hive.openBox(canonicalPapersBoxName);
    await Hive.openBox(cachedGraphsBoxName);
    await Hive.openBox(paperNotesBoxName);
  }

  static Box get favoritesBox => Hive.box(favoritesBoxName);
  static Box get settingsBox => Hive.box(settingsBoxName);
  static Box get paperNotesBox => Hive.box(paperNotesBoxName);

  // Favorites Management (Legacy PaperModel)
  static List<PaperModel> getFavoritePapers() {
    if (!Hive.isBoxOpen(favoritesBoxName)) return [];
    final List<PaperModel> papers = [];
    for (var key in favoritesBox.keys) {
      final data = favoritesBox.get(key);
      if (data != null && data is Map) {
        papers.add(PaperModel.fromMap(data));
      }
    }
    return papers;
  }

  static bool isPaperFavorite(String paperId) {
    if (!Hive.isBoxOpen(favoritesBoxName)) return false;
    return favoritesBox.containsKey(paperId);
  }

  static Future<void> saveFavoritePaper(PaperModel paper) async {
    if (!Hive.isBoxOpen(favoritesBoxName)) return;
    final updatedPaper = paper.copyWith(isFavorite: true);
    await favoritesBox.put(paper.id, updatedPaper.toMap());
  }

  static Future<void> removeFavoritePaper(String paperId) async {
    if (!Hive.isBoxOpen(favoritesBoxName)) return;
    await favoritesBox.delete(paperId);
  }

  // Personal Notes Management
  static String getPersonalNotes(String paperId) {
    if (!Hive.isBoxOpen(paperNotesBoxName)) return '';
    return paperNotesBox.get(paperId, defaultValue: '') as String;
  }

  static Future<void> savePersonalNotes(String paperId, String notes) async {
    if (Hive.isBoxOpen(paperNotesBoxName)) {
      await paperNotesBox.put(paperId, notes);
    }
    // Also sync with legacy favorites box if present
    if (Hive.isBoxOpen(favoritesBoxName) && favoritesBox.containsKey(paperId)) {
      final data = favoritesBox.get(paperId);
      if (data is Map) {
        final paper = PaperModel.fromMap(data);
        final updatedPaper = paper.copyWith(personalNotes: notes);
        await favoritesBox.put(paperId, updatedPaper.toMap());
      }
    }
  }

  static Future<void> deletePersonalNotes(String paperId) async {
    if (Hive.isBoxOpen(paperNotesBoxName)) {
      await paperNotesBox.delete(paperId);
    }
  }

  static Map<String, String> getAllPersonalNotes() {
    if (!Hive.isBoxOpen(paperNotesBoxName)) return {};
    final Map<String, String> notes = {};
    for (var key in paperNotesBox.keys) {
      final val = paperNotesBox.get(key);
      if (val is String) {
        notes[key.toString()] = val;
      }
    }
    return notes;
  }

  static Future<void> updatePersonalNotes(String paperId, String notes) async {
    await savePersonalNotes(paperId, notes);
  }

  // Canonical Papers Management
  static List<CanonicalPaper> getSavedCanonicalPapers() {
    if (!Hive.isBoxOpen(canonicalPapersBoxName)) return [];
    final box = Hive.box(canonicalPapersBoxName);
    final List<CanonicalPaper> papers = [];
    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null && data is Map) {
        try {
          papers.add(CanonicalPaper.fromJson(Map<String, dynamic>.from(data)));
        } catch (_) {}
      }
    }
    return papers;
  }

  static bool isCanonicalPaperSaved(String canonicalId) {
    if (!Hive.isBoxOpen(canonicalPapersBoxName)) return false;
    return Hive.box(canonicalPapersBoxName).containsKey(canonicalId);
  }

  static Future<void> saveCanonicalPaper(CanonicalPaper paper) async {
    if (!Hive.isBoxOpen(canonicalPapersBoxName)) return;
    final box = Hive.box(canonicalPapersBoxName);
    await box.put(paper.canonicalId, paper.toJson());
  }

  static Future<void> removeCanonicalPaper(String canonicalId) async {
    if (!Hive.isBoxOpen(canonicalPapersBoxName)) return;
    final box = Hive.box(canonicalPapersBoxName);
    await box.delete(canonicalId);
  }

  // Graph Snapshot Cache Management (Resilient, Versioned & Expiration-aware)
  static List<GraphSnapshot> getCachedGraphs({bool includeExpired = true}) {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return [];
    final box = Hive.box(cachedGraphsBoxName);
    final List<GraphSnapshot> graphs = [];

    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null && data is Map) {
        try {
          final snapshot = GraphSnapshot.fromJson(Map<String, dynamic>.from(data));

          // Validate schema version compatibility
          if (!snapshot.isCompatible(currentGraphSchemaVersion)) {
            continue; // Skip incompatible future or obsolete versions safely
          }

          // Expiration filtering
          if (!includeExpired && snapshot.isExpired) {
            continue;
          }

          graphs.add(snapshot);
        } catch (_) {
          // Gracefully skip corrupted entries without crashing
        }
      }
    }
    return graphs;
  }

  static GraphSnapshot? getCachedGraph(String graphId, {bool allowExpired = true}) {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return null;
    final box = Hive.box(cachedGraphsBoxName);
    final data = box.get(graphId);
    if (data != null && data is Map) {
      try {
        final snapshot = GraphSnapshot.fromJson(Map<String, dynamic>.from(data));
        if (!snapshot.isCompatible(currentGraphSchemaVersion)) {
          return null;
        }
        if (!allowExpired && snapshot.isExpired) {
          return null;
        }
        return snapshot;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static Future<void> saveCachedGraph(GraphSnapshot snapshot) async {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return;
    final box = Hive.box(cachedGraphsBoxName);
    await box.put(snapshot.graphId, snapshot.toJson());
  }

  static Future<void> removeCachedGraph(String graphId) async {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return;
    final box = Hive.box(cachedGraphsBoxName);
    await box.delete(graphId);
  }

  /// Safely cleans all expired graph snapshots from the cache.
  static Future<int> cleanExpiredGraphs() async {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return 0;
    final box = Hive.box(cachedGraphsBoxName);
    final keysToRemove = <dynamic>[];

    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null && data is Map) {
        try {
          final snapshot = GraphSnapshot.fromJson(Map<String, dynamic>.from(data));
          if (snapshot.isExpired) {
            keysToRemove.add(key);
          }
        } catch (_) {
          keysToRemove.add(key); // Also clean corrupted entries
        }
      } else {
        keysToRemove.add(key);
      }
    }

    for (final k in keysToRemove) {
      await box.delete(k);
    }
    return keysToRemove.length;
  }

  /// Safely purges corrupted entries that cannot be parsed.
  static Future<int> cleanCorruptedEntries() async {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return 0;
    final box = Hive.box(cachedGraphsBoxName);
    final corruptKeys = <dynamic>[];

    for (var key in box.keys) {
      final data = box.get(key);
      if (data == null || data is! Map) {
        corruptKeys.add(key);
        continue;
      }
      try {
        GraphSnapshot.fromJson(Map<String, dynamic>.from(data));
      } catch (_) {
        corruptKeys.add(key);
      }
    }

    for (final k in corruptKeys) {
      await box.delete(k);
    }
    return corruptKeys.length;
  }

  // Theme & Onboarding Settings
  static bool isDarkMode() {
    if (!Hive.isBoxOpen(settingsBoxName)) return true;
    return settingsBox.get('is_dark_mode', defaultValue: true);
  }

  static Future<void> setDarkMode(bool isDark) async {
    if (!Hive.isBoxOpen(settingsBoxName)) return;
    await settingsBox.put('is_dark_mode', isDark);
  }

  static bool isOnboardingCompleted() {
    if (!Hive.isBoxOpen(settingsBoxName)) return false;
    return settingsBox.get('onboarding_completed', defaultValue: false);
  }

  static Future<void> setOnboardingCompleted(bool completed) async {
    if (!Hive.isBoxOpen(settingsBoxName)) return;
    await settingsBox.put('onboarding_completed', completed);
  }

  // Auth & Biometrics preference
  static bool isBiometricsEnabled() {
    if (!Hive.isBoxOpen(settingsBoxName)) return true;
    return settingsBox.get('biometrics_enabled', defaultValue: true);
  }

  static Future<void> setBiometricsEnabled(bool enabled) async {
    if (!Hive.isBoxOpen(settingsBoxName)) return;
    await settingsBox.put('biometrics_enabled', enabled);
  }

  static Map<dynamic, dynamic>? getSavedUser() {
    if (!Hive.isBoxOpen(settingsBoxName)) return null;
    return settingsBox.get('saved_user');
  }

  static Future<void> saveUser(Map<String, dynamic> userMap) async {
    await settingsBox.put('saved_user', userMap);
  }

  static Future<void> clearUser() async {
    await settingsBox.delete('saved_user');
  }

  // Guest search limit tracking (1 free search for unauthenticated guests)
  static int getGuestSearchCount() {
    if (!Hive.isBoxOpen(settingsBoxName)) return 0;
    return settingsBox.get('guest_search_count', defaultValue: 0) as int;
  }

  static Future<void> incrementGuestSearchCount() async {
    if (!Hive.isBoxOpen(settingsBoxName)) return;
    final current = getGuestSearchCount();
    await settingsBox.put('guest_search_count', current + 1);
  }

  static Future<void> resetGuestSearchCount() async {
    if (!Hive.isBoxOpen(settingsBoxName)) return;
    await settingsBox.put('guest_search_count', 0);
  }
}
