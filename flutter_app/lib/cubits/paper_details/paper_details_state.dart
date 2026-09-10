import 'package:flutter/foundation.dart';
import '../../models/api_schemas.dart';

@immutable
abstract class PaperDetailsState {
  const PaperDetailsState();
}

class PaperDetailsInitial extends PaperDetailsState {
  const PaperDetailsInitial();
}

class PaperDetailsLoading extends PaperDetailsState {
  final String paperId;
  const PaperDetailsLoading(this.paperId);
}

class PaperDetailsLoaded extends PaperDetailsState {
  final PaperDetailsResponse details;
  final bool isSaved;

  const PaperDetailsLoaded(this.details, {this.isSaved = false});
}

class PaperDetailsError extends PaperDetailsState {
  final String paperId;
  final String message;

  const PaperDetailsError(this.paperId, this.message);
}
