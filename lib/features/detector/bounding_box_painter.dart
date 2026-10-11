import 'package:flutter/material.dart';
import '../../models/recognition.dart';

/// Paints road damage bounding boxes with iOS-styled frosted badges and rounded outlines.
class BoundingBoxPainter extends CustomPainter {
  BoundingBoxPainter({
    required this.recognitions,
    required this.previewSize,
    required this.screenSize,
  });

  final List<Recognition> recognitions;
  final Size previewSize;
  final Size screenSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (recognitions.isEmpty) return;

    for (final recognition in recognitions) {
      final color = recognition.color;
      final rect = _scaleRect(recognition.location, size);

      // 1. Semi-translucent damage fill
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(rrect, fillPaint);

      // 2. Refined hairline boundary
      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(rrect, boxPaint);

      // 3. Label text layout
      final percentage = (recognition.score * 100).toStringAsFixed(0);
      final textSpan = TextSpan(
        children: [
          TextSpan(
            text: '${recognition.label} ',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          TextSpan(
            text: '• ${recognition.title} ',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: '$percentage%',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      const badgeHeight = 22.0;
      final badgeWidth = textPainter.width + 16.0;

      // Position badge directly above top-left, or clamp inside if hitting screen edge
      final badgeTop = (rect.top - badgeHeight - 4) < 4
          ? (rect.top + 4)
          : (rect.top - badgeHeight - 4);
      final badgeLeft = rect.left.clamp(4.0, size.width - badgeWidth - 4.0);

      final badgeRect = Rect.fromLTWH(
        badgeLeft,
        badgeTop,
        badgeWidth,
        badgeHeight,
      );
      final badgeRRect = RRect.fromRectAndRadius(
        badgeRect,
        const Radius.circular(11),
      );

      // 4. Frosted dark pill background with subtle colored border
      final badgeBgPaint = Paint()
        ..color = const Color(0xE6141416)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(badgeRRect, badgeBgPaint);

      final badgeBorderPaint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(badgeRRect, badgeBorderPaint);

      // 5. Draw text inside badge
      textPainter.paint(canvas, Offset(badgeLeft + 8.0, badgeTop + 3.5));
    }
  }

  Rect _scaleRect(Rect normalized, Size targetSize) {
    return Rect.fromLTWH(
      normalized.left * targetSize.width,
      normalized.top * targetSize.height,
      normalized.width * targetSize.width,
      normalized.height * targetSize.height,
    );
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.recognitions != recognitions;
  }
}
