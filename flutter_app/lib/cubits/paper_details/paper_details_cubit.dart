import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_client.dart';
import 'paper_details_state.dart';

class PaperDetailsCubit extends Cubit<PaperDetailsState> {
  final PaperGraphApiClient _apiClient;

  PaperDetailsCubit({PaperGraphApiClient? apiClient})
      : _apiClient = apiClient ?? PaperGraphApiClient(),
        super(const PaperDetailsInitial());

  Future<void> loadDetails(String paperId, {bool isSaved = false}) async {
    final clean = paperId.trim();
    emit(PaperDetailsLoading(clean));

    try {
      final details = await _apiClient.getPaperDetails(clean);
      emit(PaperDetailsLoaded(details, isSaved: isSaved));
    } on ApiException catch (e) {
      emit(PaperDetailsError(clean, e.message));
    } catch (e) {
      emit(PaperDetailsError(clean, 'Failed to fetch paper details: $e'));
    }
  }

  void toggleSaved() {
    if (state is PaperDetailsLoaded) {
      final current = state as PaperDetailsLoaded;
      emit(PaperDetailsLoaded(current.details, isSaved: !current.isSaved));
    }
  }
}
