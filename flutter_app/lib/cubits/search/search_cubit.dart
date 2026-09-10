import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_client.dart';
import 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  final PaperGraphApiClient _apiClient;

  SearchCubit({PaperGraphApiClient? apiClient})
      : _apiClient = apiClient ?? PaperGraphApiClient(),
        super(const SearchInitial());

  Future<void> search(String query, {int limit = 10, int offset = 0}) async {
    final clean = query.trim();
    if (clean.length < 2) {
      emit(const SearchInitial());
      return;
    }

    emit(SearchLoading(clean));

    try {
      final response = await _apiClient.search(clean, limit: limit, offset: offset);
      if (response.items.isEmpty) {
        emit(SearchEmpty(clean));
      } else {
        emit(
          SearchLoaded(
            query: clean,
            items: response.items,
            total: response.total,
            disambiguationNeeded: response.disambiguationNeeded,
            candidates: response.candidates,
          ),
        );
      }
    } on ApiException catch (e) {
      emit(SearchError(clean, e.message));
    } catch (e) {
      emit(SearchError(clean, 'Failed to search literature: $e'));
    }
  }

  void clear() {
    emit(const SearchInitial());
  }
}
