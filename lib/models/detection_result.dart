// ============================================================
// FILE: lib/models/detection_result.dart
// ============================================================
import 'package:flutter/material.dart';
class DetectionResult {
  final String label;
  final double confidence;
  final List<double> boundingBox; // [x1, y1, x2, y2]
  final String status; // "genuine", "counterfeit", "uncertain"
  final int featureCount;
  final List<String> features;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.status,
    this.featureCount = 0,
    this.features = const [],
  });

  bool get isGenuine => status == "genuine";
  bool get isCounterfeit => status == "counterfeit";
  bool get isUncertain => status == "uncertain";
  bool get isCoin => label.toLowerCase().contains('coin');

  Color get statusColor {
    if (isCounterfeit) return Colors.red;
    if (isGenuine) return Colors.green;
    return Colors.yellow;
  }

  String get statusText {
    if (isCounterfeit) return "COUNTERFEIT";
    if (isGenuine) return "GENUINE ($featureCount features)";
    return "UNCERTAIN ($featureCount feature)";
  }
}