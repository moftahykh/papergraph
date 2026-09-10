enum GraphJobStatus {
  queued,
  resolvingOrigin,
  generatingCandidates,
  preRanking,
  enrichingMetadata,
  enrichingReferences,
  computingWbc,
  enrichingCitations,
  computingNcc,
  computingFinalScores,
  extractingPriorWorks,
  extractingDerivativeWorks,
  buildingLayout,
  completed,
  partial,
  failed;

  static GraphJobStatus fromString(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'queued':
        return GraphJobStatus.queued;
      case 'resolving_origin':
        return GraphJobStatus.resolvingOrigin;
      case 'generating_candidates':
        return GraphJobStatus.generatingCandidates;
      case 'pre_ranking':
        return GraphJobStatus.preRanking;
      case 'enriching_metadata':
        return GraphJobStatus.enrichingMetadata;
      case 'enriching_references':
        return GraphJobStatus.enrichingReferences;
      case 'computing_wbc':
        return GraphJobStatus.computingWbc;
      case 'enriching_citations':
        return GraphJobStatus.enrichingCitations;
      case 'computing_ncc':
        return GraphJobStatus.computingNcc;
      case 'computing_final_scores':
        return GraphJobStatus.computingFinalScores;
      case 'extracting_prior_works':
        return GraphJobStatus.extractingPriorWorks;
      case 'extracting_derivative_works':
        return GraphJobStatus.extractingDerivativeWorks;
      case 'building_layout':
        return GraphJobStatus.buildingLayout;
      case 'completed':
        return GraphJobStatus.completed;
      case 'partial':
        return GraphJobStatus.partial;
      case 'failed':
      default:
        return GraphJobStatus.failed;
    }
  }

  String get value {
    switch (this) {
      case GraphJobStatus.queued:
        return 'queued';
      case GraphJobStatus.resolvingOrigin:
        return 'resolving_origin';
      case GraphJobStatus.generatingCandidates:
        return 'generating_candidates';
      case GraphJobStatus.preRanking:
        return 'pre_ranking';
      case GraphJobStatus.enrichingMetadata:
        return 'enriching_metadata';
      case GraphJobStatus.enrichingReferences:
        return 'enriching_references';
      case GraphJobStatus.computingWbc:
        return 'computing_wbc';
      case GraphJobStatus.enrichingCitations:
        return 'enriching_citations';
      case GraphJobStatus.computingNcc:
        return 'computing_ncc';
      case GraphJobStatus.computingFinalScores:
        return 'computing_final_scores';
      case GraphJobStatus.extractingPriorWorks:
        return 'extracting_prior_works';
      case GraphJobStatus.extractingDerivativeWorks:
        return 'extracting_derivative_works';
      case GraphJobStatus.buildingLayout:
        return 'building_layout';
      case GraphJobStatus.completed:
        return 'completed';
      case GraphJobStatus.partial:
        return 'partial';
      case GraphJobStatus.failed:
        return 'failed';
    }
  }

  bool get isDone => this == GraphJobStatus.completed || this == GraphJobStatus.partial;
  bool get isFailed => this == GraphJobStatus.failed;
  bool get isActive => !isDone && !isFailed;
}
