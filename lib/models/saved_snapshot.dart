import 'dart:convert';

/// Represents a saved road damage snapshot with metadata.
class SavedSnapshot {
  const SavedSnapshot({
    required this.id,
    required this.filePath,
    required this.timestamp,
    required this.defectCount,
    this.defectSummary = const {},
  });

  final String id;
  final String filePath;
  final DateTime timestamp;
  final int defectCount;
  final Map<String, int> defectSummary;

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'timestamp': timestamp.toIso8601String(),
    'defectCount': defectCount,
    'defectSummary': defectSummary,
  };

  factory SavedSnapshot.fromJson(Map<String, dynamic> json) {
    return SavedSnapshot(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      defectCount: json['defectCount'] as int? ?? 0,
      defectSummary:
          (json['defectSummary'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as int),
          ) ??
          const {},
    );
  }

  static String encodeList(List<SavedSnapshot> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<SavedSnapshot> decodeList(String rawJson) {
    if (rawJson.trim().isEmpty) return [];
    final decoded = jsonDecode(rawJson) as List<dynamic>;
    return decoded
        .map((e) => SavedSnapshot.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
