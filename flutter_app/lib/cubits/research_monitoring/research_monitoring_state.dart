import 'package:flutter/foundation.dart';

import '../../models/research_monitoring_models.dart';

@immutable
class ResearchMonitoringState {
  final bool isLoading;
  final bool isActing;
  final MonitoredGraphSummary? monitoring;
  final List<ResearchUpdate> updates;
  final String? errorMessage;

  const ResearchMonitoringState({
    this.isLoading = false,
    this.isActing = false,
    this.monitoring,
    this.updates = const [],
    this.errorMessage,
  });

  bool get isNotMonitoring => monitoring == null && !isLoading;
  int get unreadCount => updates.where((update) => !update.isRead).length;

  ResearchMonitoringState copyWith({
    bool? isLoading,
    bool? isActing,
    MonitoredGraphSummary? monitoring,
    bool clearMonitoring = false,
    List<ResearchUpdate>? updates,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ResearchMonitoringState(
      isLoading: isLoading ?? this.isLoading,
      isActing: isActing ?? this.isActing,
      monitoring: clearMonitoring ? null : (monitoring ?? this.monitoring),
      updates: updates ?? this.updates,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
