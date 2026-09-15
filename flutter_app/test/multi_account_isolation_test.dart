import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:paper_graph/core/services/hive_service.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/library/library_state.dart';
import 'package:paper_graph/models/paper_model.dart';
import 'package:paper_graph/providers/favorites_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('multi_account_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.favoritesBoxName);
    await Hive.openBox(HiveService.settingsBoxName);
    await Hive.openBox(HiveService.canonicalPapersBoxName);
    await Hive.openBox(HiveService.cachedGraphsBoxName);
    await Hive.openBox(HiveService.paperNotesBoxName);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Multi-Account Data Isolation Tests', () {
    test('Account A data is strictly invisible to Account B and Guest sessions', () async {
      // 1. Simulate Account A logged in
      await HiveService.saveUser({
        'id': 'user_account_A',
        'name': 'Researcher A',
        'email': 'userA@university.edu',
      });

      final favProvider = FavoritesProvider();
      final libraryCubit = LibraryCubit();

      final paperA = PaperModel(
        id: 'paper-account-A',
        title: 'Deep Learning with Account A',
        authors: ['Author A'],
        abstractText: 'Research paper for account A.',
        category: 'Artificial Intelligence',
        year: 2024,
        citationsCount: 120,
        influentialCitations: 10,
        connectedPaperIds: const [],
        pdfUrl: '',
        journal: 'Nature',
        doi: '10.1038/s41586-024-0001',
        keyTakeaways: const [],
        isFavorite: true,
      );

      await favProvider.toggleFavorite(paperA);
      await libraryCubit.saveNotes('paper-account-A', 'Exclusive notes for account A');

      expect(favProvider.count, equals(1));
      expect(favProvider.isFavorite('paper-account-A'), isTrue);
      expect(libraryCubit.getNotes('paper-account-A'), equals('Exclusive notes for account A'));

      // 2. Account A logs out
      await HiveService.clearUser();
      favProvider.loadFavorites();
      libraryCubit.loadLibrary();

      // Guest session should NOT see Account A's papers or notes
      expect(favProvider.count, equals(0));
      expect(favProvider.isFavorite('paper-account-A'), isFalse);
      final guestState = libraryCubit.state as LibraryLoaded;
      expect(guestState.savedPapers.isEmpty, isTrue);
      expect(guestState.paperNotes.isEmpty, isTrue);

      // 3. Account B logs in
      await HiveService.saveUser({
        'id': 'user_account_B',
        'name': 'Researcher B',
        'email': 'userB@mit.edu',
      });
      favProvider.loadFavorites();
      libraryCubit.loadLibrary();

      // Account B should NOT see Account A's papers
      expect(favProvider.count, equals(0));
      expect(favProvider.isFavorite('paper-account-A'), isFalse);
      final bState = libraryCubit.state as LibraryLoaded;
      expect(bState.savedPapers.isEmpty, isTrue);
      expect(bState.paperNotes.isEmpty, isTrue);

      // Account B saves their own paper
      final paperB = PaperModel(
        id: 'paper-account-B',
        title: 'Quantum Computing with Account B',
        authors: ['Author B'],
        abstractText: 'Research paper for account B.',
        category: 'Quantum Physics',
        year: 2025,
        citationsCount: 45,
        influentialCitations: 5,
        connectedPaperIds: const [],
        pdfUrl: '',
        journal: 'Science',
        doi: '10.1126/science.2025.0002',
        keyTakeaways: const [],
        isFavorite: true,
      );
      await favProvider.toggleFavorite(paperB);

      expect(favProvider.count, equals(1));
      expect(favProvider.isFavorite('paper-account-B'), isTrue);
      expect(favProvider.isFavorite('paper-account-A'), isFalse);

      // 4. Switch back to Account A
      await HiveService.saveUser({
        'id': 'user_account_A',
        'name': 'Researcher A',
        'email': 'userA@university.edu',
      });
      favProvider.loadFavorites();
      libraryCubit.loadLibrary();

      // Account A should see paper A and notes A, but NOT paper B
      expect(favProvider.count, equals(1));
      expect(favProvider.isFavorite('paper-account-A'), isTrue);
      expect(favProvider.isFavorite('paper-account-B'), isFalse);
      expect(libraryCubit.getNotes('paper-account-A'), equals('Exclusive notes for account A'));

      favProvider.dispose();
      await libraryCubit.close();
    });

    test('Legacy migration securely assigns un-prefixed keys to first authenticated user', () async {
      // Simulate legacy un-prefixed data from old version
      final legacyMap = {
        'id': 'legacy-paper-99',
        'title': 'Legacy Unscoped Paper',
        'authors': ['Old Author'],
        'abstractText': 'Legacy content',
        'category': 'Computer Science',
        'year': 2020,
        'citationsCount': 10,
        'influentialCitations': 0,
        'connectedPaperIds': <String>[],
        'pdfUrl': '',
        'journal': '',
        'doi': '',
        'keyTakeaways': <String>[],
        'isFavorite': true,
      };

      await HiveService.favoritesBox.put('legacy-paper-99', legacyMap);
      await HiveService.paperNotesBox.put('legacy-paper-99', 'Old personal note');

      // Guest / anonymous should not access it
      expect(HiveService.getFavoritePapers().isEmpty, isTrue);

      // Account A logs in and runs migration
      await HiveService.saveUser({
        'id': 'user_migrated_A',
        'name': 'Migrated User',
        'email': 'migrated@univ.edu',
      });
      await HiveService.migrateLegacyDataForUser('user_migrated_A');

      // Account A now owns the paper
      expect(HiveService.isPaperFavorite('legacy-paper-99'), isTrue);
      expect(HiveService.getFavoritePapers().length, equals(1));
      expect(HiveService.getPersonalNotes('legacy-paper-99'), equals('Old personal note'));

      // Account B logs in
      await HiveService.saveUser({
        'id': 'user_unrelated_B',
        'name': 'Unrelated User',
        'email': 'other@univ.edu',
      });

      // Account B does NOT see Account A's migrated paper
      expect(HiveService.isPaperFavorite('legacy-paper-99'), isFalse);
      expect(HiveService.getFavoritePapers().isEmpty, isTrue);
      expect(HiveService.getPersonalNotes('legacy-paper-99'), isEmpty);
    });
  });
}
