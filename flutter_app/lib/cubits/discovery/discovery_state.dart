import 'package:flutter/foundation.dart';

import '../../models/api_schemas.dart';

@immutable
abstract class DiscoveryState {
  const DiscoveryState();
}

class DiscoveryInitial extends DiscoveryState {
  const DiscoveryInitial();
}

class DiscoveryLoading extends DiscoveryState {
  const DiscoveryLoading();
}

class DiscoveryLoaded extends DiscoveryState {
  final List<DiscoveryTopic> topics;
  final DiscoveryRecommendation? recommendation;

  const DiscoveryLoaded({this.topics = const [], this.recommendation});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveryLoaded &&
          runtimeType == other.runtimeType &&
          listEquals(topics, other.topics) &&
          recommendation == other.recommendation;

  @override
  int get hashCode => Object.hash(Object.hashAll(topics), recommendation);
}

class DiscoveryUnavailable extends DiscoveryState {
  final String message;

  const DiscoveryUnavailable(this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveryUnavailable &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;
}
