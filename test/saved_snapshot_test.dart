import 'package:flutter_test/flutter_test.dart';
import 'package:roadeye/models/saved_snapshot.dart';

void main() {
  group('SavedSnapshot', () {
    test('serializes and deserializes snapshot lists', () {
      final now = DateTime.now();
      final snapshots = [
        SavedSnapshot(
          id: 'test_1',
          filePath: '/path/to/img1.jpg',
          timestamp: now,
          defectCount: 2,
          defectSummary: {'Pothole': 1, 'Longitudinal Crack': 1},
        ),
      ];

      final encoded = SavedSnapshot.encodeList(snapshots);
      final decoded = SavedSnapshot.decodeList(encoded);

      expect(decoded.length, 1);
      expect(decoded.first.id, 'test_1');
      expect(decoded.first.defectCount, 2);
      expect(decoded.first.defectSummary['Pothole'], 1);
    });

    test('handles empty json string gracefully', () {
      final decoded = SavedSnapshot.decodeList('');
      expect(decoded, isEmpty);
    });
  });
}
