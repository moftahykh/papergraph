import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_client.dart';
import '../../core/services/hive_service.dart';
import 'paper_details_state.dart';

class PaperDetailsCubit extends Cubit<PaperDetailsState> {
  final PaperGraphApiClient _apiClient;

  PaperDetailsCubit({PaperGraphApiClient? apiClient})
      : _apiClient = apiClient ?? PaperGraphApiClient(),
        super(const PaperDetailsInitial());

  Future<void> loadDetails(String paperId, {bool? isSaved}) async {
    final clean = paperId.trim();
    emit(PaperDetailsLoading(clean));

    try {
      final details = await _apiClient.getPaperDetails(clean);
      final bool actuallySaved = isSaved ?? HiveService.isPaperFavorite(clean);
      emit(PaperDetailsLoaded(details, isSaved: actuallySaved));
    } on ApiException catch (e) {
      emit(PaperDetailsError(clean, e.message));
    } catch (e) {
      emit(PaperDetailsError(clean, 'Failed to fetch paper details: $e'));
    }
  }

  Future<void> toggleSaved() async {
    if (state is PaperDetailsLoaded) {
      final current = state as PaperDetailsLoaded;
      final newSavedStatus = !current.isSaved;
      emit(PaperDetailsLoaded(current.details, isSaved: newSavedStatus));
      try {
        if (newSavedStatus) {
          await HiveService.saveCanonicalPaper(current.details.paper);
        } else {
          await HiveService.removeCanonicalPaper(current.details.paper.canonicalId);
        }
      } catch (_) {}
    }
  }
}
