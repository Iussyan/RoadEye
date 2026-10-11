import 'package:flutter/material.dart';

/// Represents a detected road damage region.
class Recognition {
  const Recognition({
    required this.id,
    required this.label,
    required this.title,
    required this.score,
    required this.location,
  });

  /// Unique detection identifier within a frame.
  final int id;

  /// Damage class code (e.g. D00, D10, D20, D40).
  final String label;

  /// Human-readable label (e.g. Longitudinal Crack, Pothole).
  final String title;

  /// Confidence score between 0.0 and 1.0.
  final double score;

  /// Normalized bounding box in range [0.0, 1.0] representing [left, top, width, height].
  final Rect location;

  /// Color coding for road damage visualization.
  Color get color {
    switch (label) {
      case 'D00':
        return const Color(0xFF3B82F6); // Blue: Longitudinal Crack
      case 'D10':
        return const Color(0xFF10B981); // Green: Transverse Crack
      case 'D20':
        return const Color(0xFFF59E0B); // Amber: Alligator Crack
      case 'D40':
        return const Color(0xFFEF4444); // Red: Pothole
      default:
        return const Color(0xFF8B5CF6);
    }
  }

  static const Map<String, String> damageClassTitles = {
    'D00': 'Longitudinal Crack',
    'D10': 'Transverse Crack',
    'D20': 'Alligator Crack',
    'D40': 'Pothole',
  };

  static String titleForLabel(String label) {
    return damageClassTitles[label] ?? label;
  }
}
