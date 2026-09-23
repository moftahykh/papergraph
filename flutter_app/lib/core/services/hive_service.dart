import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/canonical_paper.dart';
import '../../models/graph_models.dart';
import '../../models/paper_model.dart';

class HiveService {
  /// Give guests enough room to understand the product before asking them
  /// to create an account.
  static const int guestPreviewLimit = 2;
  static const String favoritesBoxName = 'papergraph_favorites';
  static const String settingsBoxName = 'papergraph_settings';
  static const String canonicalPapersBoxName = 'papergraph_canonical_papers';
  static const String cachedGraphsBoxName = 'papergraph_cached_graphs';
  static const String paperNotesBoxName = 'papergraph_paper_notes';

  /// Supported schema version for cached literature graphs.
  static const int currentGraphSchemaVersion = 1;

  /// Automatic history is bounded; explicitly saved graphs are never trimmed.
  static const int maxRecentGraphsPerUser = 30;

  static Future<void> init() async {
    _activeUserOverride = null;
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

  static Box _requireOpenBox(String boxName) {
    if (!Hive.isBoxOpen(boxName)) {
      throw StateError('Required storage box is not open: $boxName');
    }
    return Hive.box(boxName);
  }

  // In-memory session scope. A null value means startup has not resolved the
  // auth session yet, so saved_user is used only as a bootstrap hint.
  static String? _activeUserOverride;

  static void setActiveUserScope(String? userId) {
    final normalized = userId?.trim() ?? '';
    _activeUserOverride = normalized.isEmpty ? 'anonymous' : normalized;
  }

  /// Active User ID to isolate user data (favorites, cached graphs, notes)
  /// between accounts (e.g. Account A vs Account B vs Guest).
  static String get activeUserId {
    if (_activeUserOverride != null) {
      return _activeUserOverride!;
    }
    final saved = getSavedUser();
    if (saved != null &&
        saved['id'] != null &&
        saved['id'].toString().isNotEmpty) {
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
  /// and adopts data created in an anonymous session. Data is moved to only
  /// the first account that signs in, preventing leakage across accounts.
  static Future<void> migrateLegacyDataForUser(String userId) async {
    if (userId.isEmpty || userId == 'anonymous') return;

    String? migratableBaseKey(String key) {
      if (key.startsWith('anonymous::')) {
        return key.substring('anonymous::'.length);
      }
      if (!key.contains('::') && !key.startsWith('alias:')) {
        return key;
      }
      return null;
    }

    Future<void> migrateMapBox(Box box) async {
      final keys = List.from(box.keys);
      for (final key in keys) {
        final keyString = key.toString();
        final baseKey = migratableBaseKey(keyString);
        if (baseKey == null || baseKey.isEmpty) continue;
        final value = box.get(key);
        if (value is! Map) continue;

        final targetKey = '$userId::$baseKey';
        if (!box.containsKey(targetKey)) {
          final migrated = Map<String, dynamic>.from(value);
          migrated['_owner_id'] = userId;
          await box.put(targetKey, migrated);
        }
        await box.delete(key);
      }
    }

    // 1. Favorites Box
    if (Hive.isBoxOpen(favoritesBoxName)) {
      await migrateMapBox(favoritesBox);
    }

    // 2. Canonical Papers Box
    if (Hive.isBoxOpen(canonicalPapersBoxName)) {
      await migrateMapBox(Hive.box(canonicalPapersBoxName));
    }

    // 3. Paper Notes Box
    if (Hive.isBoxOpen(paperNotesBoxName)) {
      final keys = List.from(paperNotesBox.keys);
      for (final key in keys) {
        final keyString = key.toString();
        final baseKey = migratableBaseKey(keyString);
        if (baseKey == null || baseKey.isEmpty) continue;
        final value = paperNotesBox.get(key);
        if (value is! String) continue;
        final targetKey = '$userId::$baseKey';
        if (!paperNotesBox.containsKey(targetKey)) {
          await paperNotesBox.put(targetKey, value);
        }
        await paperNotesBox.delete(key);
      }
    }

    // 4. Cached Graphs Box
    if (Hive.isBoxOpen(cachedGraphsBoxName)) {
      final box = Hive.box(cachedGraphsBoxName);
      await migrateMapBox(box);

      // Repoint anonymous lookup aliases to the newly-owned graph keys.
      final aliasKeys = List.from(box.keys);
      for (final key in aliasKeys) {
        final keyString = key.toString();
        if (!keyString.startsWith('alias:anonymous:')) continue;
        final value = box.get(key);
        if (value is! String) continue;
        final targetAliasKey = keyString.replaceFirst(
          'alias:anonymous:',
          'alias:$userId:',
        );
        final targetGraphKey = value.startsWith('anonymous::')
            ? value.replaceFirst('anonymous::', '$userId::')
            : value;
        if (!box.containsKey(targetAliasKey)) {
          await box.put(targetAliasKey, targetGraphKey);
        }
        await box.delete(key);
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
      connectedPaperIds: cp.citationIds.isNotEmpty
          ? cp.citationIds
          : cp.referenceIds,
      pdfUrl: cp.doi != null && cp.doi!.isNotEmpty
          ? 'https://doi.org/${cp.doi}'
          : '',
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
        } catch (error, stackTrace) {
          debugPrint(
            'Could not read favorite paper "${key.toString()}": '
            '$error\n$stackTrace',
          );
        }
      }
    }

    if (Hive.isBoxOpen(canonicalPapersBoxName)) {
      final cBox = Hive.box(canonicalPapersBoxName);
      for (var key in cBox.keys) {
        final cData = cBox.get(key);
        if (cData != null && cData is Map) {
          if (!_isOwnedByActiveUser(key.toString(), cData)) continue;
          try {
            final cp = CanonicalPaper.fromJson(
              Map<String, dynamic>.from(cData),
            );
            if (!processedIds.contains(cp.canonicalId)) {
              papers.add(canonicalToPaperModel(cp));
              processedIds.add(cp.canonicalId);
            }
          } catch (error, stackTrace) {
            debugPrint(
              'Could not read canonical paper "${key.toString()}": '
              '$error\n$stackTrace',
            );
          }
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
    final favoriteStore = _requireOpenBox(favoritesBoxName);
    final canonicalStore = _requireOpenBox(canonicalPapersBoxName);
    final updatedPaper = paper.copyWith(isFavorite: true);
    final map = updatedPaper.toMap();
    map['_owner_id'] = activeUserId;
    final scopedKey = _userKey(paper.id);

    await favoriteStore.put(scopedKey, map);
    final canonical = paperModelToCanonical(updatedPaper);
    final cJson = canonical.toJson();
    cJson['_owner_id'] = activeUserId;
    await canonicalStore.put(scopedKey, cJson);
  }

  static Future<void> removeFavoritePaper(String paperId) async {
    final favoriteStore = _requireOpenBox(favoritesBoxName);
    final canonicalStore = _requireOpenBox(canonicalPapersBoxName);
    final scopedKey = _userKey(paperId);
    await favoriteStore.deleteAll([scopedKey, paperId]);
    await canonicalStore.deleteAll([scopedKey, paperId]);
  }

  // Personal Notes Management (Scoped to active user account)
  static String getPersonalNotes(String paperId) {
    if (!Hive.isBoxOpen(paperNotesBoxName)) return '';
    final val = paperNotesBox.get(_userKey(paperId));
    if (val is String && val.isNotEmpty) return val;
    return '';
  }

  static Future<void> savePersonalNotes(String paperId, String notes) async {
    final notesStore = _requireOpenBox(paperNotesBoxName);
    await notesStore.put(_userKey(paperId), notes);
    // Keep the legacy paper mirror in sync when possible. The dedicated
    // notes record above is the source of truth and already completed.
    final scopedKey = _userKey(paperId);
    if (Hive.isBoxOpen(favoritesBoxName) &&
        favoritesBox.containsKey(scopedKey)) {
      try {
        final data = favoritesBox.get(scopedKey);
        if (data is Map) {
          final paper = PaperModel.fromMap(data);
          final updatedPaper = paper.copyWith(personalNotes: notes);
          final uMap = updatedPaper.toMap();
          uMap['_owner_id'] = activeUserId;
          await favoritesBox.put(scopedKey, uMap);
        }
      } catch (error, stackTrace) {
        debugPrint('Could not update legacy note mirror: $error\n$stackTrace');
      }
    }
  }

  static Future<void> deletePersonalNotes(String paperId) async {
    final notesStore = _requireOpenBox(paperNotesBoxName);
    await notesStore.deleteAll([_userKey(paperId), paperId]);
  }

  static Map<String, String> getAllPersonalNotes() {
    final notesStore = _requireOpenBox(paperNotesBoxName);
    final Map<String, String> notes = {};
    final prefix = '$activeUserId::';
    for (var key in notesStore.keys) {
      final kStr = key.toString();
      final val = notesStore.get(key);
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
    final box = _requireOpenBox(canonicalPapersBoxName);
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
        } catch (error, stackTrace) {
          debugPrint(
            'Could not read saved paper "${key.toString()}": $error\n$stackTrace',
          );
        }
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
          } catch (error, stackTrace) {
            debugPrint(
              'Could not read legacy paper "${key.toString()}": $error\n$stackTrace',
            );
          }
        }
      }
    }

    return papers;
  }

  static bool isCanonicalPaperSaved(String canonicalId) {
    return isPaperFavorite(canonicalId);
  }

  static Future<void> saveCanonicalPaper(CanonicalPaper paper) async {
    final canonicalStore = _requireOpenBox(canonicalPapersBoxName);
    final scopedKey = _userKey(paper.canonicalId);
    final json = paper.toJson();
    json['_owner_id'] = activeUserId;
    await canonicalStore.put(scopedKey, json);

    // Canonical storage is the source of truth. Keep the legacy favorites
    // representation as a best-effort compatibility mirror.
    if (Hive.isBoxOpen(favoritesBoxName)) {
      try {
        final pm = canonicalToPaperModel(paper);
        final map = pm.toMap();
        map['_owner_id'] = activeUserId;
        await favoritesBox.put(scopedKey, map);
      } catch (error, stackTrace) {
        debugPrint('Could not update legacy paper mirror: $error\n$stackTrace');
      }
    }
  }

  static Future<void> removeCanonicalPaper(String canonicalId) async {
    await removeFavoritePaper(canonicalId);
  }

  // Graph Snapshot Cache Management (Scoped to active user account)
  static List<GraphSnapshot> getCachedGraphs({
    bool includeExpired = true,
    bool savedOnly = false,
  }) {
    final box = _requireOpenBox(cachedGraphsBoxName);
    final List<GraphSnapshot> graphs = [];

    for (var key in box.keys) {
      final kStr = key.toString();
      if (kStr.startsWith('alias:')) continue;
      final data = box.get(key);
      if (data != null && data is Map) {
        if (!_isOwnedByActiveUser(kStr, data)) continue;
        if (savedOnly && !_isGraphExplicitlySaved(data)) continue;
        try {
          final snapshot = GraphSnapshot.fromJson(
            Map<String, dynamic>.from(data),
          );

          // Validate schema version compatibility
          if (!snapshot.isCompatible(currentGraphSchemaVersion)) {
            continue; // Skip incompatible future or obsolete versions safely
          }

          // Expiration filtering
          if (!includeExpired && snapshot.isExpired) {
            continue;
          }

          graphs.add(snapshot);
        } catch (error, stackTrace) {
          debugPrint('Could not read saved graph "$kStr": $error\n$stackTrace');
        }
      }
    }
    graphs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return graphs;
  }

  static GraphSnapshot? getCachedGraph(
    String identifier, {
    bool allowExpired = true,
  }) {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return null;
    final box = Hive.box(cachedGraphsBoxName);
    final clean = identifier.trim().toLowerCase();
    if (clean.isEmpty) return null;

    dynamic candidateData;

    // 1. Direct key match (scoped)
    final direct =
        box.get(_userKey(clean)) ??
        (activeUserId == 'anonymous' ? box.get(clean) : null);
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
          final targetData =
              box.get(targetGraphId) ?? box.get(_userKey(targetGraphId));
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
            final snapshot = GraphSnapshot.fromJson(
              Map<String, dynamic>.from(raw),
            );
            final o = snapshot.origin;
            final origCanonical = o.canonicalId.toLowerCase();
            final origId = o.id.toLowerCase();
            final origDoi = o.doi?.toLowerCase() ?? '';
            final origTitle = o.title.toLowerCase();

            final matches =
                origCanonical == clean ||
                origId == clean ||
                origTitle == clean ||
                (stripped.isNotEmpty && origCanonical.contains(stripped)) ||
                (origDoi.isNotEmpty &&
                    (origDoi == clean || origDoi.contains(stripped))) ||
                snapshot.nodes.any(
                  (n) =>
                      n.isOrigin &&
                      (n.canonicalId.toLowerCase() == clean ||
                          n.id.toLowerCase() == clean ||
                          (stripped.isNotEmpty &&
                              n.canonicalId.toLowerCase().contains(stripped))),
                );

            if (matches) {
              if (!snapshot.isCompatible(currentGraphSchemaVersion)) continue;
              if (!allowExpired && snapshot.isExpired) continue;
              return snapshot;
            }
          } catch (error, stackTrace) {
            debugPrint('Could not inspect graph "$kStr": $error\n$stackTrace');
          }
        }
      }
    }

    if (candidateData != null && candidateData is Map) {
      try {
        final snapshot = GraphSnapshot.fromJson(
          Map<String, dynamic>.from(candidateData),
        );
        if (!snapshot.isCompatible(currentGraphSchemaVersion)) return null;
        if (!allowExpired && snapshot.isExpired) return null;
        return snapshot;
      } catch (error, stackTrace) {
        debugPrint(
          'Could not open saved graph "$identifier": $error\n$stackTrace',
        );
        return null;
      }
    }
    return null;
  }

  static Future<void> saveCachedGraph(
    GraphSnapshot snapshot, {
    bool markAsSaved = true,
  }) async {
    final box = _requireOpenBox(cachedGraphsBoxName);
    final scopedKey = _userKey(snapshot.graphId);
    final existing = box.get(scopedKey);
    final wasAlreadySaved =
        existing is Map && _isGraphExplicitlySaved(existing);

    final map = Map<String, dynamic>.from(snapshot.toJson());
    map['_owner_id'] = activeUserId;
    map['_is_saved'] = markAsSaved || wasAlreadySaved;

    // Save the primary payload before optional lookup aliases.
    await box.put(scopedKey, map);

    // Alias indexes improve lookup speed. The primary record above is the
    // source of truth, so an alias failure must not misreport a successful save.
    final aliases = <String>[];
    final originId = snapshot.origin.id.trim().toLowerCase();
    final canonicalId = snapshot.origin.canonicalId.trim().toLowerCase();
    final title = snapshot.origin.title.trim().toLowerCase();
    if (originId.isNotEmpty) aliases.add('alias:$activeUserId:id:$originId');
    if (canonicalId.isNotEmpty) {
      aliases.add('alias:$activeUserId:canonical:$canonicalId');
    }
    if (title.isNotEmpty) aliases.add('alias:$activeUserId:title:$title');
    final doi = snapshot.origin.doi?.trim().toLowerCase();
    if (doi != null && doi.isNotEmpty) {
      aliases.add('alias:$activeUserId:doi:$doi');
      final cleanDoi = doi
          .replaceAll('doi:', '')
          .replaceAll('https://doi.org/', '')
          .replaceAll('http://dx.doi.org/', '')
          .trim();
      if (cleanDoi.isNotEmpty) {
        aliases.add('alias:$activeUserId:doi:$cleanDoi');
      }
    }
    for (final alias in aliases) {
      try {
        await box.put(alias, scopedKey);
      } catch (error, stackTrace) {
        debugPrint('Could not update graph lookup alias: $error\n$stackTrace');
      }
    }

    if (!markAsSaved) {
      await _trimAutomaticGraphHistory(box);
    }
  }

  static bool _isGraphExplicitlySaved(Map<dynamic, dynamic> data) {
    // Records created before this distinction were visible in Library, so
    // preserve them as saved during the compatibility migration.
    if (!data.containsKey('_is_saved')) return true;
    return data['_is_saved'] == true;
  }

  static Future<void> _trimAutomaticGraphHistory(Box box) async {
    final automatic = <MapEntry<dynamic, Map<dynamic, dynamic>>>[];
    for (final key in box.keys) {
      final keyString = key.toString();
      if (keyString.startsWith('alias:')) continue;
      final data = box.get(key);
      if (data is! Map<dynamic, dynamic>) continue;
      if (!_isOwnedByActiveUser(keyString, data)) continue;
      if (_isGraphExplicitlySaved(data)) continue;
      automatic.add(MapEntry(key, data));
    }
    automatic.sort((a, b) {
      final aDate =
          DateTime.tryParse(a.value['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          DateTime.tryParse(b.value['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    for (final entry in automatic.skip(maxRecentGraphsPerUser)) {
      await _deleteGraphRecordAndAliases(box, entry.key);
    }
  }

  static Future<void> _deleteGraphRecordAndAliases(Box box, dynamic key) async {
    final target = key.toString();
    final aliasPrefix = 'alias:$activeUserId:';
    final aliases = box.keys.where((alias) {
      return alias.toString().startsWith(aliasPrefix) &&
          box.get(alias) == target;
    }).toList();
    await box.delete(key);
    for (final alias in aliases) {
      await box.delete(alias);
    }
  }

  static Future<void> removeCachedGraph(String graphId) async {
    final box = _requireOpenBox(cachedGraphsBoxName);
    final scopedKey = _userKey(graphId);
    final aliasPrefix = 'alias:$activeUserId:';
    final aliasKeys = box.keys.where((key) {
      final keyString = key.toString();
      if (!keyString.startsWith(aliasPrefix)) return false;
      final target = box.get(key);
      return target == scopedKey || target == graphId;
    }).toList();

    await box.delete(scopedKey);
    for (final key in aliasKeys) {
      await box.delete(key);
    }
  }

  /// Safely cleans expired graph snapshots owned by the active user.
  ///
  /// Alias entries are strings, not corrupt graph payloads. Only aliases that
  /// point to a removed graph are deleted.
  static Future<int> cleanExpiredGraphs() async {
    final box = _requireOpenBox(cachedGraphsBoxName);
    final keysToRemove = <dynamic>[];

    for (var key in box.keys) {
      final keyString = key.toString();
      if (keyString.startsWith('alias:')) continue;
      final data = box.get(key);
      if (data != null && data is Map) {
        if (!_isOwnedByActiveUser(keyString, data)) continue;
        if (_isGraphExplicitlySaved(data)) continue;
        try {
          final snapshot = GraphSnapshot.fromJson(
            Map<String, dynamic>.from(data),
          );
          if (snapshot.isExpired) {
            keysToRemove.add(key);
          }
        } catch (error, stackTrace) {
          // Do not classify unreadable user data as expired or delete it here.
          debugPrint(
            'Skipped unreadable graph during expiry cleanup "$keyString": '
            '$error\n$stackTrace',
          );
        }
      }
    }

    for (final k in keysToRemove) {
      final target = k.toString();
      final aliasPrefix = 'alias:$activeUserId:';
      final aliases = box.keys.where((key) {
        if (!key.toString().startsWith(aliasPrefix)) return false;
        return box.get(key) == target;
      }).toList();
      await box.delete(k);
      for (final alias in aliases) {
        await box.delete(alias);
      }
    }
    return keysToRemove.length;
  }

  /// Clears graph snapshots and aliases for the active user only.
  /// Returns the number of graph snapshots removed (aliases are not counted).
  static Future<int> clearCachedGraphsForActiveUser() async {
    final box = _requireOpenBox(cachedGraphsBoxName);
    final aliasPrefix = 'alias:$activeUserId:';
    final graphKeys = <dynamic>[];
    final aliasKeys = <dynamic>[];

    for (final key in box.keys) {
      final keyString = key.toString();
      if (keyString.startsWith(aliasPrefix)) {
        aliasKeys.add(key);
        continue;
      }

      final data = box.get(key);
      if (data is Map && _isOwnedByActiveUser(keyString, data)) {
        graphKeys.add(key);
      }
    }

    for (final key in [...graphKeys, ...aliasKeys]) {
      await box.delete(key);
    }
    return graphKeys.length;
  }

  /// Safely purges corrupted entries that cannot be parsed.
  static Future<int> cleanCorruptedEntries() async {
    if (!Hive.isBoxOpen(cachedGraphsBoxName)) return 0;
    final box = Hive.box(cachedGraphsBoxName);
    final corruptKeys = <dynamic>[];

    for (var key in box.keys) {
      final keyString = key.toString();
      if (keyString.startsWith('alias:')) continue;
      final data = box.get(key);
      if (data is! Map) continue;
      if (!_isOwnedByActiveUser(keyString, data)) continue;
      try {
        GraphSnapshot.fromJson(Map<String, dynamic>.from(data));
      } catch (error, stackTrace) {
        debugPrint(
          'Marked unreadable graph for explicit cleanup "$keyString": '
          '$error\n$stackTrace',
        );
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
    if (!Hive.isBoxOpen(settingsBoxName)) return false;
    return settingsBox.get('biometrics_enabled', defaultValue: false);
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
    setActiveUserScope(userMap['id']?.toString());
    await settingsBox.put('saved_user', userMap);
  }

  static Future<void> clearUser() async {
    setActiveUserScope('anonymous');
    await settingsBox.delete('saved_user');
  }

  // Pending graph job tracking (scoped to the active account).
  static String get _pendingGraphJobKey => 'pending_graph_job::$activeUserId';

  static Map<String, dynamic>? getPendingGraphJob() {
    if (!Hive.isBoxOpen(settingsBoxName)) return null;
    final value = settingsBox.get(_pendingGraphJobKey);
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static Future<void> savePendingGraphJob({
    required String graphId,
    required String originId,
    required DateTime startedAt,
    double progress = 0,
    String? currentStage,
  }) async {
    if (!Hive.isBoxOpen(settingsBoxName)) return;
    await settingsBox.put(_pendingGraphJobKey, {
      'graph_id': graphId,
      'origin_id': originId,
      'started_at': startedAt.toIso8601String(),
      'progress': progress,
      'current_stage': currentStage,
      'owner_id': activeUserId,
    });
  }

  /// Removes a pending job by graph ID across account-scoped keys.
  ///
  /// This matters during logout: AuthProvider clears saved_user before it
  /// notifies GraphCubit, so activeUserId may already be "anonymous".
  static Future<void> clearPendingGraphJob(String graphId) async {
    if (!Hive.isBoxOpen(settingsBoxName)) return;
    final keys = settingsBox.keys
        .where((key) => key.toString().startsWith('pending_graph_job::'))
        .toList();

    for (final key in keys) {
      final value = settingsBox.get(key);
      if (value is Map && value['graph_id']?.toString() == graphId) {
        await settingsBox.delete(key);
      }
    }
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

  // Cached Discovery Topics for offline and Render cold-start resilience
  static const String _cachedDiscoveryTopicsKey = 'cached_discovery_topics';

  static List<Map<String, dynamic>>? getCachedDiscoveryTopics() {
    if (!Hive.isBoxOpen(settingsBoxName)) return null;
    final raw = settingsBox.get(_cachedDiscoveryTopicsKey);
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return null;
  }

  static Future<void> saveCachedDiscoveryTopics(
    List<Map<String, dynamic>> topics,
  ) async {
    if (!Hive.isBoxOpen(settingsBoxName)) return;
    await settingsBox.put(_cachedDiscoveryTopicsKey, topics);
  }
}
