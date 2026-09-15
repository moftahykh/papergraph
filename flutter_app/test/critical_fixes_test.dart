import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:paper_graph/core/services/hive_service.dart';
import 'package:paper_graph/models/canonical_paper.dart';
import 'package:paper_graph/models/paper_model.dart';
import 'package:paper_graph/providers/papers_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('critical_fixes_test_');
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

  group('Critical Fix 1 & 2: HiveService Bidirectional Sync Tests', () {
    test('Saving a PaperModel automatically syncs to CanonicalPaper box', () async {
      final paperModel = PaperModel(
        id: 'sync-paper-1',
        title: 'Attention Is All You Need',
        authors: ['Ashish Vaswani', 'Noam Shazeer'],
        abstractText: 'We propose the Transformer.',
        category: 'Artificial Intelligence',
        year: 2017,
        citationsCount: 95000,
        influentialCitations: 5000,
        connectedPaperIds: const ['ref-1', 'ref-2'],
        pdfUrl: 'https://arxiv.org/pdf/1706.03762',
        journal: 'NeurIPS',
        doi: '10.5555/3295222.3295349',
        keyTakeaways: const ['Transformer architecture'],
        isFavorite: true,
      );

      await HiveService.saveFavoritePaper(paperModel);

      // Verify in legacy favorites box
      expect(HiveService.isPaperFavorite('sync-paper-1'), isTrue);
      expect(HiveService.isCanonicalPaperSaved('sync-paper-1'), isTrue);

      // Verify retrieved from getSavedCanonicalPapers
      final canonicalList = HiveService.getSavedCanonicalPapers();
      expect(canonicalList.any((p) => p.canonicalId == 'sync-paper-1'), isTrue);
      final retrievedCanonical =
          canonicalList.firstWhere((p) => p.canonicalId == 'sync-paper-1');
      expect(retrievedCanonical.title, 'Attention Is All You Need');
      expect(retrievedCanonical.authors.length, 2);
    });

    test('Saving a CanonicalPaper automatically syncs to Favorites box', () async {
      const canonical = CanonicalPaper(
        canonicalId: 'sync-canonical-2',
        title: 'Deep Residual Learning for Image Recognition',
        normalizedTitle: 'deep residual learning for image recognition',
        authors: [Author(name: 'Kaiming He'), Author(name: 'Xiangyu Zhang')],
        year: 2016,
        venue: 'CVPR',
        abstractText: 'Residual learning framework for deep networks.',
        citationCount: 180000,
        topics: ['Computer Vision'],
      );

      await HiveService.saveCanonicalPaper(canonical);

      // Verify both check functions report true
      expect(HiveService.isCanonicalPaperSaved('sync-canonical-2'), isTrue);
      expect(HiveService.isPaperFavorite('sync-canonical-2'), isTrue);

      // Verify in legacy getFavoritePapers
      final favList = HiveService.getFavoritePapers();
      expect(favList.any((p) => p.id == 'sync-canonical-2'), isTrue);
      final retrievedModel =
          favList.firstWhere((p) => p.id == 'sync-canonical-2');
      expect(retrievedModel.title, 'Deep Residual Learning for Image Recognition');
      expect(retrievedModel.isFavorite, isTrue);
    });

    test('Removing from either box removes it from both boxes', () async {
      const canonical = CanonicalPaper(
        canonicalId: 'to-delete-1',
        title: 'Paper to be deleted',
        normalizedTitle: 'paper to be deleted',
        authors: [Author(name: 'Author A')],
      );

      await HiveService.saveCanonicalPaper(canonical);
      expect(HiveService.isPaperFavorite('to-delete-1'), isTrue);

      // Remove via removeFavoritePaper
      await HiveService.removeFavoritePaper('to-delete-1');
      expect(HiveService.isPaperFavorite('to-delete-1'), isFalse);
      expect(HiveService.isCanonicalPaperSaved('to-delete-1'), isFalse);
    });
  });

  group('Critical Fix 3: PapersProvider Active Data Population', () {
    test('PapersProvider initializes with saved papers from Hive', () async {
      final paperModel = PaperModel(
        id: 'provider-test-1',
        title: 'Foundational Paper on Graph Neural Networks',
        authors: ['Thomas Kipf'],
        abstractText: 'GCNs for semi-supervised classification.',
        category: 'Computer Science',
        year: 2017,
        citationsCount: 30000,
        influentialCitations: 1500,
        connectedPaperIds: const ['provider-test-2'],
        pdfUrl: '',
        journal: 'ICLR',
        doi: '',
        keyTakeaways: const [],
        isFavorite: true,
      );
      final paperModel2 = PaperModel(
        id: 'provider-test-2',
        title: 'Inductive Representation Learning on Large Graphs',
        authors: ['William L. Hamilton'],
        abstractText: 'GraphSAGE algorithm.',
        category: 'Computer Science',
        year: 2017,
        citationsCount: 20000,
        influentialCitations: 1000,
        connectedPaperIds: const ['provider-test-1'],
        pdfUrl: '',
        journal: 'NeurIPS',
        doi: '',
        keyTakeaways: const [],
        isFavorite: true,
      );

      await HiveService.saveFavoritePaper(paperModel);
      await HiveService.saveFavoritePaper(paperModel2);

      final provider = PapersProvider();
      expect(provider.papers.length, 2);
      expect(provider.trendingPapers.length, 2);

      final connected = provider.getConnectedPapers(paperModel);
      expect(connected.length, 1);
      expect(connected.first.id, 'provider-test-2');
    });
  });
}
