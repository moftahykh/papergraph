import 'package:flutter/foundation.dart';
import '../../models/graph_models.dart';
import '../../models/graph_job_status.dart';

@immutable
abstract class GraphState {
  const GraphState();
}

class GraphInitial extends GraphState {
  const GraphInitial();
}

class GraphCreating extends GraphState {
  final String originId;
  const GraphCreating(this.originId);
}

class GraphPolling extends GraphState {
  final String graphId;
  final String originId;
  final GraphJobStatus status;
  final double progress;
  final GraphJobStatus currentStage;
  final List<GraphWarning> warnings;
  final DataCompleteness? dataCompleteness;

  const GraphPolling({
    required this.graphId,
    this.originId = '',
    required this.status,
    required this.progress,
    required this.currentStage,
    this.warnings = const [],
    this.dataCompleteness,
  });
}

class GraphLoaded extends GraphState {
  final GraphSnapshot snapshot;
  final bool isPartial;
  final List<GraphWarning> warnings;
  final DataCompleteness dataCompleteness;
  final bool fromOfflineCache;
  final bool isNewlyGenerated;
  final bool isPersisted;
  final String? persistenceWarning;

  const GraphLoaded({
    required this.snapshot,
    this.isPartial = false,
    this.warnings = const [],
    this.dataCompleteness = const DataCompleteness(),
    this.fromOfflineCache = false,
    this.isNewlyGenerated = false,
    this.isPersisted = true,
    this.persistenceWarning,
  });
}

class GraphError extends GraphState {
  final String message;
  final bool canRetry;
  final String? graphId;

  const GraphError(this.message, {this.canRetry = true, this.graphId});
}
