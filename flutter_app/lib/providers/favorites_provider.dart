import 'package:flutter/material.dart';
import '../core/services/hive_service.dart';
import '../models/paper_model.dart';
import 'auth_provider.dart';
import 'papers_provider.dart';

class FavoritesProvider extends ChangeNotifier {
  List<PaperModel> _favoritePapers = [];

  FavoritesProvider() {
    loadFavorites();
    AuthProvider.addAuthListener(loadFavorites);
  }

  @override
  void dispose() {
    AuthProvider.removeAuthListener(loadFavorites);
    super.dispose();
  }

  List<PaperModel> get favoritePapers => _favoritePapers;
  int get count => _favoritePapers.length;

  void loadFavorites() {
    _favoritePapers = HiveService.getFavoritePapers();
    notifyListeners();
  }

  bool isFavorite(String paperId) {
    return _favoritePapers.any((p) => p.id == paperId);
  }

  Future<void> toggleFavorite(
    PaperModel paper, [
    PapersProvider? papersProvider,
  ]) async {
    final exists = isFavorite(paper.id);

    if (exists) {
      await HiveService.removeFavoritePaper(paper.id);
      _favoritePapers.removeWhere((p) => p.id == paper.id);
      papersProvider?.updatePaperFavoriteFlag(paper.id, false);
    } else {
      final savedPaper = paper.copyWith(isFavorite: true);
      await HiveService.saveFavoritePaper(savedPaper);
      _favoritePapers.insert(0, savedPaper);
      papersProvider?.updatePaperFavoriteFlag(paper.id, true);
    }

    notifyListeners();
  }

  Future<void> updateNotes(String paperId, String notes) async {
    await HiveService.updatePersonalNotes(paperId, notes);
    final index = _favoritePapers.indexWhere((p) => p.id == paperId);
    if (index != -1) {
      _favoritePapers[index].personalNotes = notes;
      notifyListeners();
    }
  }
}
