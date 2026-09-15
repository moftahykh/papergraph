import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_client.dart';
import '../../providers/auth_provider.dart';
import 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  final PaperGraphApiClient _apiClient;
  Timer? _debounceTimer;
  CancelToken? _activeCancelToken;

  /// Coalesces rapid typing into a single request (matches the API
  /// contract's promise of query debouncing).
  static const Duration debounceDuration = Duration(milliseconds: 350);

  SearchCubit({PaperGraphApiClient? apiClient})
      : _apiClient = apiClient ?? PaperGraphApiClient(),
        super(const SearchInitial()) {
    AuthProvider.addAuthListener(clear);
  }

  /// Debounced search entry point used by the UI.
  /// Pass [immediate] = true (e.g. on submit) to skip the debounce delay.
  Future<void> search(
    String query, {
    int limit = 10,
    int offset = 0,
    bool immediate = false,
  }) async {
    final clean = query.trim();
    _debounceTimer?.cancel();

    if (clean.length < 2) {
      _cancelInFlight();
      emit(const SearchInitial());
      return;
    }

    if (immediate) {
      await _executeSearch(clean, limit: limit, offset: offset);
      return;
    }

    _debounceTimer = Timer(debounceDuration, () {
      _executeSearch(clean, limit: limit, offset: offset);
    });
  }

  Future<void> _executeSearch(
    String clean, {
    int limit = 10,
    int offset = 0,
  }) async {
    // A newer query always supersedes any in-flight older request,
    // preventing stale responses from overwriting fresh results.
    _cancelInFlight();
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    emit(SearchLoading(clean));

    try {
      final response = await _apiClient.search(
        clean,
        limit: limit,
        offset: offset,
        cancelToken: cancelToken,
      );
      if (isClosed) return;
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
      if (e.message.contains('cancelled')) return; // superseded — stay silent
      if (!isClosed) emit(SearchError(clean, e.message));
    } catch (e) {
      if (!isClosed) emit(SearchError(clean, 'Failed to search literature: $e'));
    }
  }

  void _cancelInFlight() {
    _activeCancelToken?.cancel('Superseded by a newer query.');
    _activeCancelToken = null;
  }

  void clear() {
    _debounceTimer?.cancel();
    _cancelInFlight();
    emit(const SearchInitial());
  }

  @override
  Future<void> close() {
    AuthProvider.removeAuthListener(clear);
    _debounceTimer?.cancel();
    _cancelInFlight();
    return super.close();
  }
}
