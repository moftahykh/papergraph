import 'package:flutter/foundation.dart';

enum ResearchSessionStatus {
  idle,
  searching,
  results,
  building,
  ready,
  error,
}

@immutable
class ResearchSessionState {
  final ResearchSessionStatus status;
  final String query;
  final String? graphId;
  final String? title;
  final int? paperCount;
  final double progress;
  final String? message;

  const ResearchSessionState({
    this.status = ResearchSessionStatus.idle,
    this.query = '',
    this.graphId,
    this.title,
    this.paperCount,
    this.progress = 0,
    this.message,
  });

  bool get hasSession => status != ResearchSessionStatus.idle;

  bool get canOpenGraph =>
      status == ResearchSessionStatus.building ||
      status == ResearchSessionStatus.ready;

  ResearchSessionState copyWith({
    ResearchSessionStatus? status,
    String? query,
    String? graphId,
    String? title,
    int? paperCount,
    double? progress,
    String? message,
    bool clearGraph = false,
    bool clearTitle = false,
    bool clearMessage = false,
  }) {
    return ResearchSessionState(
      status: status ?? this.status,
      query: query ?? this.query,
      graphId: clearGraph ? null : (graphId ?? this.graphId),
      title: clearTitle ? null : (title ?? this.title),
      paperCount: paperCount ?? this.paperCount,
      progress: progress ?? this.progress,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}