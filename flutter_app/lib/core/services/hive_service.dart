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

  /// Active User ID to isolate user data (favorites, cached graphs, notes)
  /// between accounts (e.g. Account A vs Account B vs Guest).
  static String get activeUserId {
    final saved = getSavedUser();
    if (saved != null && saved['id'] != null && saved['id'].toString().isNotEmpty) {
      return saved['id'].toString();
    }
    return 'anonymous';
  }

  static String _userKey(String baseKey) => '$activeUserId::$baseKey';

  static bool _isOwnedByActiveUser(String key, Map? data) {
    if (key.startsWith('$activeUserId::')) return true;
    if (data != null && data['_owner_id'] != null) {
      return data['_owner_id'] == activeUserId;
    }
    return false;
  }

  /// Migrates un-prefixed legacy local data to the authenticated user on first login,
  /// preserving the user's saved items while preventing leakage across accounts.
  static Future<void> migrateLegacyDataForUser(String userId) async {
    if (userId.isEmpty || userId == 'anonymous') return;

    // 1. Favorites Box
    if (Hive.isBoxOpen(favoritesBoxName)) {
      final keys = List.from(favoritesBox.keys);
      for (var k in keys) {
        final kStr = k.toString();
        if (!kStr.contains('::')) {
          final val = favoritesBox.get(k);
          if (val is Map) {
            final m = Map<String, dynamic>.from(val);
            m['_owner_id'] = userId;
            await favoritesBox.put('$userId::$kStr', m);
            await favoritesBox.delete(k);
          }
        }
      }
    }

    // 2. Canonical Papers Box
    if (Hive.isBoxOpen(canonicalPapersBoxName)) {
      final box = Hive.box(canonicalPapersBoxName);
      final keys = List.from(box.keys);
      for (var k in keys) {
        final kStr = k.toString();
        if (!kStr.contains('::')) {
          final val = box.get(k);
          if (val is Map) {
            final m = Map<String, dynamic>.from(val);
            m['_owner_id'] = userId;
            await box.put('$userId::$kStr', m);
            await box.delete(k);
          }
        }
      }
    }

    // 3. Paper Notes Box
    if (Hive.isBoxOpen(paperNotesBoxName)) {
      final keys = List.from(paperNotesBox.keys);
      for (var k in keys) {
        final kStr = k.toString();
        if (!kStr.contains('::')) {
          final val = paperNotesBox.get(k);
          if (val is String) {
            await paperNotesBox.put('$userId::$kStr', val);
            await paperNotesBox.delete(k);
          }
        }
      }
    }

    // 4. Cached Graphs Box
    if (Hive.isBoxOpen(cachedGraphsBoxName)) {
      final box = Hive.box(cachedGraphsBoxName);
      final keys = List.from(box.keys);
      for (var k in keys) {
        final kStr = k.toString();
        if (!kStr.contains('::') && !kStr.startsWith('alias:')) {
          final val = box.get(k);
          if (val is Map) {
            final m = Map<String, dynamic>.from(val);
            m['_owner_id'] = userId;
            await box.put('$userId::$kStr', m);
            await box.delete(k);
          }
        }
      }
    }
  }

  // Model Conversion Helpers for Cross-Compatibility
  static CanonicalPaper paperModelToCanonical(PaperModel model) {
    return CanonicalPaper(
      canonicalId: model.id,
      title: model.title,
      normalizedTitle: model.title.toLowerCase(),
      authors: model.authors.map((a) => Author(name: a)).toList(),
      year: model.year > 0 ? model.year : null,
      venue: model.journal.isNotEmpty ? model.journal : null,
      abstractText: model.abstractText.isNotEmpty ? model.abstractText : null,
      citationCount: model.citationsCount,
      referenceCount: 0,
      doi: model.doi.isNotEmpty ? model.doi : null,
      topics: model.category.isNotEmpty ? [model.category] : const [],
      citationIds: model.connectedPaperIds,
    );
  }

  static PaperModel canonicalToPaperModel(CanonicalPaper cp) {
    return PaperModel(
      id: cp.canonicalId,
      title: cp.title,
      authors: cp.authors.map((a) => a.name).toList(),
      abstractText: cp.abstractText ?? '',
      year: cp.year ?? 0,
      citationsCount: cp.citationCount,
      influentialCitations: 0,
      journal: cp.venue ?? '',
      doi: cp.doi ?? '',
      category: cp.topics.isNotEmpty ? cp.topics.first : 'Computer Science',
      connectedPaperIds: cp.citationIds.isNotEmpty ? cp.citationIds : cp.referenceIds,
      pdfUrl: cp.doi != null && cp.doi!.isNotEmpty ? 'https://doi.org/${cp.doi}' : '',
      keyTakeaways: const [],
      isFavorite: true,
      personalNotes: getPersonalNotes(cp.canonicalId),
    );
  }

  // Favorites Management (Scoped to active user account)
  static List<PaperModel> getFavoritePapers() {
    if (!Hive.isBoxOpen(favoritesBoxName)) return [];
    final List<PaperModel> papers = [];
    final Set<String> processedIds = {};

    for (var key in favoritesBox.keys) {
      final data = favoritesBox.get(key);
      if (data != null && data is Map) {
        if (!_isOwnedByActiveUser(key.toString(), data)) continue;
        try {
          final p = PaperModel.fromMap(data);
          papers.add(p);
          processedIds.add(p.id);
        } catch (_) {}
      }
    }

    if (Hive.isBoxOpen(canonicalPapersBoxName)) {
      final cBox = Hive.box(canonicalPapersBoxName);
      for (var key in cBox.keys) {
        final cData = cBox.get(key);
        if (cData != null && cData is Map) {
          if (!_isOwnedByActiveUser(key.toString(), cData)) continue;
          try {
            final cp = CanonicalPaper.fromJson(Map<String, dynamic>.from(cData));
            if (!processedIds.contains(cp.canonicalId)) {
              papers.add(canonicalToPaperModel(cp));
              processedIds.add(cp.canonicalId);
            }
          } catch (_) {}
        }
      }
    }

    return papers;
  }

  static bool isPaperFavorite(String paperId) {
    final scopedKey = _userKey(paperId);
    if (Hive.isBoxOpen(favoritesBoxName)) {
      if (favoritesBox.containsKey(scopedKey)) return true;
    }
    if (Hive.isBoxOpen(canonicalPapersBoxName)) {
      final cBox = Hive.box(canonicalPapersBoxName);
      if (cBox.containsKey(scopedKey)) return true;
    }
    return false;
  }

  static Future<void> saveFavoritePaper(PaperModel paper) async {
    final updatedPaper = paper.copyWith(isFavorite: true);
    final map = updatedPaper.toMap();
    map['_owner_id'] = activeUserId;
    final scopedKey = _userKey(paper.id);

    if (Hive.isBoxOpen(favoritesBoxName)) {
      await favoritesBox.put(scopedKey, map);
    }
    if (Hive.isBoxOpen(canonicalPapersBoxName)) {
      final canonical = paperModelToCanonical(updatedPaper);
      final cJson = canonical.toJson();
      cJson['_owner_id'] = activeUserId;
      await Hive.box(canonicalPapersBoxName).put(scopedKey, cJson);
    }
  }

  static Future<void> removeFavoritePaper(String paperId) async {
    final scopedKey = _userKey(paperId);
    if (Hive.isBoxOpen(favoritesBoxName)) {
      await favoritesBox.delete(scopedKey);
      await favoritesBox.delete(paperId);
    }
    if (Hive.isBoxOpen(canonicalPapersBoxName)) {
      await Hive.box(canonicalPapersBoxName).delete(scopedKey);
      await Hive.box(canonicalPapersBoxName).delete(paperId);
    }
  }

  // Personal Notes Management (Scoped to active user account)
  static String getPersonalNotes(String paperId) {
    if (!Hive.isBoxOpen(paperNotesBoxName)) return '';
    final val = paperNotesBox.get(_userKey(paperId));
    if (val is String && val.isNotEmpty) return val;
    return '';
  }

  static Future<void> savePersonalNotes(String paperId, String notes) async {
    if (Hive.isBoxOpen(paperNotesBoxName)) {
      await paperNotesBox.put(_userKey(paperId), notes);
    }
    // Also sync with favorites box if present
    final scopedKey = _userKey(paperId);
    if (Hive.isBoxOpen(favoritesBoxName) && favoritesBox.containsKey(scopedKey)) {
      final data = favoritesBox.get(scopedKey);
      if (data is Map) {
        final paper = PaperModel.fromMap(data);
        final updatedPaper = paper.copyWith(personalNotes: notes);
        final uMap = updatedPaper.toMap();
        uMap['_owner_id'] = activeUserId;
        await favoritesBox.put(scopedKey, uMap);
      }
    }
  }

  static Future<void> deletePersonalNotes(String paperId) async {
    if (Hive.isBoxOpen(paperNotesBoxName)) {
      await paperNotesBox.delete(_userKey(paperId));
      await paperNotesBox.delete(paperId);
    }
  }

  static Map<String, String> getAllPersonalNotes() {
    if (!Hive.isBoxOpen(paperNotesBoxName)) return {};
    final Map<String, String> notes = {};
    final prefix = '$activeUserId::';
    for (var key in paperNotesBox.keys) {
      final kStr = key.toString();
      final val = paperNotesBox.get(key);
      if (val is String && kStr.startsWith(prefix)) {
        final rawId = kStr.substring(prefix.length);
        notes[rawId] = val;
      }
    }
    return notes;
  }

  static Future<void> updatePersonalNotes(String paperId, String notes) async {
    await savePersonalNotes(paperId, notes);
  }

  // Canonical Papers Management (Scoped to active user account)
  static List<CanonicalPaper> getSavedCanonicalPapers() {
    if (!Hive.isBoxOpen(canonicalPapersBoxName)) return [];
    final box = Hive.box(canonicalPapersBoxName);
    final List<CanonicalPaper> papers = [];
    final Set<String> processedIds = {};

    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null && data is Map) {
        if (!_isOwnedByActiveUser(key.toString(), data)) continue;
        try {
          final cp = CanonicalPaper.fromJson(Map<String, dynamic>.from(data));
          papers.add(cp);
          processedIds.add(cp.canonicalId);
        } catch (_) {}
      }
    }

    if (Hive.isBoxOpen(favoritesBoxName)) {
      for (var key in favoritesBox.keys) {
        final fData = favoritesBox.get(key);
        if (fData != null && fData is Map) {
          if (!_isOwnedByActiveUser(key.toString(), fData)) continue;
          try {
            final pm = PaperModel.fromMap(fData);
            if (!processedIds.contains(pm.id)) {
              papers.add(paperModelToCanonical(pm));
              processedIds.add(pm.id);
            }
          } catch (_) {}
        }
      }
    }

    return papers;
  }

  static bool isCanonicalPaperSaved(String canonicalId) {
    return isPaperFavorite(canonicalId);
  }

  static Future<void> saveCanonicalPaper(CanonicalPaper paper) async {
    final scopedKey = _userKey(paper.canonicalId);
    if (Hive.isBoxOpen(canonicalPapersBoxName)) {
      final box = Hive.box(canonicalPapersBoxName);
      final json = paper.toJson();
      json['_owner_id'] = activeUserId;
      await box.put(scopedKey, json);
    }
    if (Hive.isBoxOpen(favoritesBoxName)) {
      final pm = canonicalToPaperModel(paper);
      final map = pm.toMap();
      map['_owner_id'] = activeUserId;
      await favoritesBox.put(scopedKey, map);
    }
  }

  static Future<void> removeCanonicalPaper(String canonicalId) async {
    await removeFavoritePaper(canonicalId);
  }

  // Graph Snapshot Cache Management (Scoped to active user account)
  static List<GraphSnapshot> getCachedGraphs({bool includeExpired = true}) {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return [];
    final box = Hive.box(cachedGraphsBoxName);
    final List<GraphSnapshot> graphs = [];

    for (var key in box.keys) {
      final kStr = key.toString();
      if (kStr.startsWith('alias:')) continue;
      final data = box.get(key);
      if (data != null && data is Map) {
        if (!_isOwnedByActiveUser(kStr, data)) continue;
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

  static GraphSnapshot? getCachedGraph(String identifier, {bool allowExpired = true}) {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return null;
    final box = Hive.box(cachedGraphsBoxName);
    final clean = identifier.trim().toLowerCase();
    if (clean.isEmpty) return null;

    dynamic candidateData;

    // 1. Direct key match (scoped)
    final direct = box.get(_userKey(clean)) ?? (activeUserId == 'anonymous' ? box.get(clean) : null);
    if (direct != null && direct is Map) {
      candidateData = direct;
    }

    // 2. Lookup through alias keys
    if (candidateData == null) {
      final stripped = clean
          .replaceAll('doi:', '')
          .replaceAll('https://doi.org/', '')
          .replaceAll('http://dx.doi.org/', '')
          .trim();

      final aliasKeys = [
        'alias:$activeUserId:doi:$clean',
        'alias:$activeUserId:doi:$stripped',
        'alias:$activeUserId:canonical:$clean',
        'alias:$activeUserId:id:$clean',
        'alias:$activeUserId:title:$clean',
        if (activeUserId == 'anonymous') ...[
          'alias:doi:$clean',
          'alias:doi:$stripped',
          'alias:canonical:$clean',
          'alias:id:$clean',
          'alias:title:$clean',
        ],
      ];

      for (final aKey in aliasKeys) {
        final targetGraphId = box.get(aKey);
        if (targetGraphId != null && targetGraphId is String) {
          final targetData = box.get(targetGraphId) ?? box.get(_userKey(targetGraphId));
          if (targetData != null && targetData is Map) {
            candidateData = targetData;
            break;
          }
        }
      }
    }

    // 3. Fallback scan across cached snapshots for the active user
    if (candidateData == null) {
      final stripped = clean
          .replaceAll('doi:', '')
          .replaceAll('https://doi.org/', '')
          .replaceAll('http://dx.doi.org/', '')
          .trim();

      for (var key in box.keys) {
        final kStr = key.toString();
        if (kStr.startsWith('alias:')) continue;
        final raw = box.get(key);
        if (raw != null && raw is Map) {
          if (!_isOwnedByActiveUser(kStr, raw)) continue;
          try {
            final snapshot = GraphSnapshot.fromJson(Map<String, dynamic>.from(raw));
            final o = snapshot.origin;
            final origCanonical = o.canonicalId.toLowerCase();
            final origId = o.id.toLowerCase();
            final origDoi = o.doi?.toLowerCase() ?? '';
            final origTitle = o.title.toLowerCase();

            final matches = origCanonical == clean ||
                origId == clean ||
                origTitle == clean ||
                (stripped.isNotEmpty && origCanonical.contains(stripped)) ||
                (origDoi.isNotEmpty && (origDoi == clean || origDoi.contains(stripped))) ||
                snapshot.nodes.any((n) =>
                    n.isOrigin &&
                    (n.canonicalId.toLowerCase() == clean ||
                        n.id.toLowerCase() == clean ||
                        (stripped.isNotEmpty && n.canonicalId.toLowerCase().contains(stripped))));

            if (matches) {
              if (!snapshot.isCompatible(currentGraphSchemaVersion)) continue;
              if (!allowExpired && snapshot.isExpired) continue;
              return snapshot;
            }
          } catch (_) {}
        }
      }
    }

    if (candidateData != null && candidateData is Map) {
      try {
        final snapshot = GraphSnapshot.fromJson(Map<String, dynamic>.from(candidateData));
        if (!snapshot.isCompatible(currentGraphSchemaVersion)) return null;
        if (!allowExpired && snapshot.isExpired) return null;
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

    final map = Map<String, dynamic>.from(snapshot.toJson());
    map['_owner_id'] = activeUserId;
    final scopedKey = _userKey(snapshot.graphId);

    // Save primary graph snapshot payload
    await box.put(scopedKey, map);

    // Index aliases for instantaneous 0-second offline retrieval
    final originId = snapshot.origin.id.trim().toLowerCase();
    final canonicalId = snapshot.origin.canonicalId.trim().toLowerCase();
    final title = snapshot.origin.title.trim().toLowerCase();

    if (originId.isNotEmpty) {
      await box.put('alias:$activeUserId:id:$originId', scopedKey);
    }
    if (canonicalId.isNotEmpty) {
      await box.put('alias:$activeUserId:canonical:$canonicalId', scopedKey);
    }
    if (title.isNotEmpty) {
      await box.put('alias:$activeUserId:title:$title', scopedKey);
    }
    final doi = snapshot.origin.doi?.trim().toLowerCase();
    if (doi != null && doi.isNotEmpty) {
      await box.put('alias:$activeUserId:doi:$doi', scopedKey);
      final cleanDoi = doi
          .replaceAll('doi:', '')
          .replaceAll('https://doi.org/', '')
          .replaceAll('http://dx.doi.org/', '')
          .trim();
      if (cleanDoi.isNotEmpty) {
        await box.put('alias:$activeUserId:doi:$cleanDoi', scopedKey);
      }
    }
  }

  static Future<void> removeCachedGraph(String graphId) async {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return;
    final box = Hive.box(cachedGraphsBoxName);
    await box.delete(_userKey(graphId));
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
