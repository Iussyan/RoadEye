import 'package:flutter/material.dart';
import '../../models/recognition.dart';

/// Paints thin, clean bounding boxes with plain damage names attached.
class BoundingBoxPainter extends CustomPainter {
  BoundingBoxPainter({required this.recognitions, this.mirror = false});

  final List<Recognition> recognitions;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    if (recognitions.isEmpty) return;

    for (final recognition in recognitions) {
      final color = recognition.color;
      final rect = _scaleRect(recognition.location, size);

      // 1. Subtle damage area tint
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, fillPaint);

      // 2. Clean thin outline
      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawRRect(rrect, boxPaint);

      // 3. Plain name and confidence text (e.g. "Pothole 92%")
      final percentage = (recognition.score * 100).toStringAsFixed(0);
      final textSpan = TextSpan(
        children: [
          TextSpan(
            text: '${recognition.title} ',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: '$percentage%',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      const badgeHeight = 20.0;
      final badgeWidth = textPainter.width + 12.0;

      // Position badge directly above top-left, or inside if near screen edge
      final badgeTop = (rect.top - badgeHeight - 2) < 2
          ? (rect.top + 2)
          : (rect.top - badgeHeight - 2);
      final badgeLeft = rect.left.clamp(2.0, size.width - badgeWidth - 2.0);

      final badgeRect = Rect.fromLTWH(
        badgeLeft,
        badgeTop,
        badgeWidth,
        badgeHeight,
      );
      final badgeRRect = RRect.fromRectAndRadius(
        badgeRect,
        const Radius.circular(5),
      );

      // 4. Compact frosted badge background
      final badgeBgPaint = Paint()
        ..color = const Color(0xDD121214)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(badgeRRect, badgeBgPaint);

      final badgeBorderPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawRRect(badgeRRect, badgeBorderPaint);

      textPainter.paint(canvas, Offset(badgeLeft + 6.0, badgeTop + 2.5));
    }
  }

  Rect _scaleRect(Rect normalized, Size targetSize) {
    return Rect.fromLTWH(
      (mirror ? 1 - normalized.right : normalized.left) * targetSize.width,
      normalized.top * targetSize.height,
      normalized.width * targetSize.width,
      normalized.height * targetSize.height,
    );
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.recognitions != recognitions ||
        oldDelegate.mirror != mirror;
  }
}
