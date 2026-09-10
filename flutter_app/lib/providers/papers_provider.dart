import 'package:flutter/material.dart';
import '../data/sample_papers_data.dart';
import '../models/paper_model.dart';
import '../core/services/hive_service.dart';

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
  }

  void _initPapers() {
    _allPapers = SamplePapersData.getInitialPapers();
    // Sync favorite flags from Hive
    for (var paper in _allPapers) {
      paper.isFavorite = HiveService.isPaperFavorite(paper.id);
    }
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
    return _allPapers
        .where((p) => paper.connectedPaperIds.contains(p.id))
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
