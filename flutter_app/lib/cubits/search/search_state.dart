import 'package:flutter/foundation.dart';
import '../../models/api_schemas.dart';

@immutable
abstract class SearchState {
  const SearchState();
}

class SearchInitial extends SearchState {
  const SearchInitial();
}

class SearchLoading extends SearchState {
  final String query;
  const SearchLoading(this.query);
}

class SearchLoaded extends SearchState {
  final String query;
  final List<SearchResultItem> items;
  final int total;
  final bool disambiguationNeeded;
  final List<SearchResultItem> candidates;

  const SearchLoaded({
    required this.query,
    required this.items,
    required this.total,
    this.disambiguationNeeded = false,
    this.candidates = const [],
  });
}

class SearchEmpty extends SearchState {
  final String query;
  const SearchEmpty(this.query);
}

class SearchError extends SearchState {
  final String query;
  final String message;
  const SearchError(this.query, this.message);
}
