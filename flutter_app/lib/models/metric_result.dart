import 'package:flutter/foundation.dart';

enum MetricAvailability {
  available,
  unavailable,
  providerError,
  notApplicable;

  static MetricAvailability fromString(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'available':
        return MetricAvailability.available;
      case 'provider_error':
        return MetricAvailability.providerError;
      case 'not_applicable':
        return MetricAvailability.notApplicable;
      case 'unavailable':
      default:
        return MetricAvailability.unavailable;
    }
  }

  String get value {
    switch (this) {
      case MetricAvailability.available:
        return 'available';
      case MetricAvailability.providerError:
        return 'provider_error';
      case MetricAvailability.notApplicable:
        return 'not_applicable';
      case MetricAvailability.unavailable:
        return 'unavailable';
    }
  }
}

@immutable
class MetricResult {
  /// Calculated metric value in [0, 1]. Null if signal could not be evaluated.
  /// Null is explicitly distinguishable from 0.0 (zero similarity vs missing data).
  final double? value;
  final MetricAvailability availability;
  final String? reason;

  const MetricResult({
    this.value,
    this.availability = MetricAvailability.unavailable,
    this.reason,
  });

  bool get isAvailable => availability == MetricAvailability.available && value != null;

  factory MetricResult.fromJson(Map<String, dynamic> json) {
    return MetricResult(
      value: (json['value'] as num?)?.toDouble(),
      availability: MetricAvailability.fromString(json['availability'] as String?),
      reason: json['reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'availability': availability.value,
      'reason': reason,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetricResult &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          availability == other.availability &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(value, availability, reason);

  @override
  String toString() => 'MetricResult(value: $value, availability: ${availability.value}, reason: $reason)';
}
