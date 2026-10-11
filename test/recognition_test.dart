import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadeye/models/recognition.dart';

void main() {
  group('Recognition model', () {
    test('instantiates and maps titles and colors correctly', () {
      final recognition = Recognition(
        id: 1,
        label: 'D40',
        title: Recognition.titleForLabel('D40'),
        score: 0.88,
        location: const Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
      );

      expect(recognition.id, 1);
      expect(recognition.label, 'D40');
      expect(recognition.title, 'Pothole');
      expect(recognition.score, 0.88);
      expect(recognition.color, const Color(0xFFEF4444));
    });

    test('maps all RDD2022 classes', () {
      expect(Recognition.titleForLabel('D00'), 'Longitudinal Crack');
      expect(Recognition.titleForLabel('D10'), 'Transverse Crack');
      expect(Recognition.titleForLabel('D20'), 'Alligator Crack');
      expect(Recognition.titleForLabel('D40'), 'Pothole');
      expect(Recognition.titleForLabel('UNKNOWN'), 'UNKNOWN');
    });
  });
}
