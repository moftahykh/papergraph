import 'package:flutter/material.dart';
import '../models/paper_model.dart';
import '../core/services/hive_service.dart';
import 'auth_provider.dart';

class PapersProvider extends ChangeNotifier {
  List<PaperModel> _allPapers = [];
  String _searchQuery = '';
  String _selectedCategory = 'All';

  final List<String> categories = [
    'All',
    'Artificial Intelligence',
    'Computer Vision',
    'Generative AI',
    'Cybersecurity',
    'Software Engineering',
    'Optimization & Algorithms',
  ];

  PapersProvider() {
    _initPapers();
    AuthProvider.addAuthListener(reloadPapers);
  }

  @override
  void dispose() {
    AuthProvider.removeAuthListener(reloadPapers);
    super.dispose();
  }

  void reloadPapers() {
    _initPapers();
  }

  void _initPapers() {
    final Set<String> ids = {};
    final List<PaperModel> loaded = [];

    // 1. Load saved/favorite papers from Hive
    for (var paper in HiveService.getFavoritePapers()) {
      if (!ids.contains(paper.id)) {
        ids.add(paper.id);
        loaded.add(paper);
      }
    }

    // 2. Extract synthesized nodes from all cached graphs in Hive
    for (var snapshot in HiveService.getCachedGraphs(includeExpired: true)) {
      for (var node in snapshot.nodes) {
        if (!ids.contains(node.canonicalId)) {
          ids.add(node.canonicalId);
          loaded.add(PaperModel(
            id: node.canonicalId,
            title: node.title,
            authors: node.authors,
            abstractText: '',
            category: 'Computer Science',
            year: node.year ?? 0,
            citationsCount: node.citationCount,
            influentialCitations: 0,
            connectedPaperIds: const [],
            pdfUrl: '',
            journal: node.venue ?? '',
            doi: '',
            keyTakeaways: const [],
            isFavorite: HiveService.isPaperFavorite(node.canonicalId),
          ));
        }
      }
    }

    _allPapers = loaded;
    notifyListeners();
  }

  String get searchQuery => _searchQuery;
  String get selectedCategory => _selectedCategory;

  List<PaperModel> get papers {
    return _allPapers.where((paper) {
      final matchesCategory =
          _selectedCategory == 'All' || paper.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          paper.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          paper.authors.any((a) => a.toLowerCase().contains(_searchQuery.toLowerCase())) ||
          paper.abstractText.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  List<PaperModel> get trendingPapers {
    final list = List<PaperModel>.from(_allPapers);
    list.sort((a, b) => b.citationsCount.compareTo(a.citationsCount));
    return list.take(5).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  PaperModel? getPaperById(String id) {
    try {
      return _allPapers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  List<PaperModel> getConnectedPapers(PaperModel paper) {
    // 1. Direct match by IDs
    final direct = _allPapers
        .where((p) =>
            p.id != paper.id &&
            (paper.connectedPaperIds.contains(p.id) ||
                p.connectedPaperIds.contains(paper.id)))
        .toList();
    if (direct.isNotEmpty) return direct;

    // 2. Match from cached graph edges
    final cached = HiveService.getCachedGraphs(includeExpired: true);
    final Set<String> connectedNodeIds = {};
    for (var g in cached) {
      final allEdges = [...g.citationEdges, ...g.similarityEdges];
      for (var edge in allEdges) {
        if (edge.source == paper.id) connectedNodeIds.add(edge.target);
        if (edge.target == paper.id) connectedNodeIds.add(edge.source);
      }
    }
    final graphConnected = _allPapers
        .where((p) => p.id != paper.id && connectedNodeIds.contains(p.id))
        .toList();
    if (graphConnected.isNotEmpty) return graphConnected;

    // 3. Fallback: match by category/field of study
    return _allPapers
        .where((p) => p.id != paper.id && p.category == paper.category)
        .take(4)
        .toList();
  }

  void updatePaperFavoriteFlag(String paperId, bool isFavorite) {
    final index = _allPapers.indexWhere((p) => p.id == paperId);
    if (index != -1) {
      _allPapers[index].isFavorite = isFavorite;
      notifyListeners();
    }
  }
}
