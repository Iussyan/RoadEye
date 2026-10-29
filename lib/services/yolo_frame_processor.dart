import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../models/recognition.dart';

/// Exact resize/padding transform, shared by preprocessing and box decoding.
class Letterbox {
  Letterbox(this.width, this.height, this.size) {
    final scale = math.min(size / width, size / height);
    resizedWidth = (width * scale).round().clamp(1, size);
    resizedHeight = (height * scale).round().clamp(1, size);
    left = ((size - resizedWidth) / 2 - 0.1).round();
    top = ((size - resizedHeight) / 2 - 0.1).round();
  }

  final int width;
  final int height;
  final int size;
  late final int resizedWidth;
  late final int resizedHeight;
  late final int left;
  late final int top;

  Rect undo(double cx, double cy, double w, double h) {
    final x1 = ((cx - w / 2) * size - left) / resizedWidth;
    final y1 = ((cy - h / 2) * size - top) / resizedHeight;
    final x2 = ((cx + w / 2) * size - left) / resizedWidth;
    final y2 = ((cy + h / 2) * size - top) / resizedHeight;
    return Rect.fromLTRB(
      x1.clamp(0, 1).toDouble(),
      y1.clamp(0, 1).toDouble(),
      x2.clamp(0, 1).toDouble(),
      y2.clamp(0, 1).toDouble(),
    );
  }
}

class FramePlane {
  const FramePlane(this.bytes, this.rowStride, this.pixelStride);
  final Uint8List bytes;
  final int rowStride;
  final int pixelStride;
}

/// CPU-only transforms; invoked inside the inference isolate, never by build().
class YoloFrameProcessor {
  YoloFrameProcessor({required this.size, required this.channelFirst});
  final int size;
  final bool channelFirst;

  void _put(Float32List input, int index, num r, num g, num b) {
    if (channelFirst) {
      final stride = size * size;
      input[index] = r / 255;
      input[stride + index] = g / 255;
      input[2 * stride + index] = b / 255;
    } else {
      input[index * 3] = r / 255;
      input[index * 3 + 1] = g / 255;
      input[index * 3 + 2] = b / 255;
    }
  }

  Letterbox prepareCamera({
    required Float32List input,
    required int width,
    required int height,
    required String format,
    required List<FramePlane> planes,
    int rotation = 0,
  }) {
    if (rotation % 90 != 0 || ![0, 90, 180, 270].contains(rotation)) {
      throw ArgumentError('Camera rotation must be 0, 90, 180, or 270.');
    }
    if ((format != 'bgra8888' || planes.length != 1) &&
        (format != 'yuv420' || planes.length != 3)) {
      throw FormatException('Unsupported camera format: $format');
    }
    final swapped = rotation == 90 || rotation == 270;
    final transform = Letterbox(
      swapped ? height : width,
      swapped ? width : height,
      size,
    );
    input.fillRange(0, input.length, 114 / 255);
    for (var y = 0; y < transform.resizedHeight; y++) {
      final oy = y * transform.height ~/ transform.resizedHeight;
      for (var x = 0; x < transform.resizedWidth; x++) {
        final ox = x * transform.width ~/ transform.resizedWidth;
        final (sx, sy) = switch (rotation) {
          90 => (oy, height - 1 - ox),
          180 => (width - 1 - ox, height - 1 - oy),
          270 => (width - 1 - oy, ox),
          _ => (ox, oy),
        };
        final index = (y + transform.top) * size + x + transform.left;
        if (format == 'bgra8888') {
          final plane = planes.first;
          final offset = sy * plane.rowStride + sx * plane.pixelStride;
          _put(
            input,
            index,
            plane.bytes[offset + 2],
            plane.bytes[offset + 1],
            plane.bytes[offset],
          );
        } else {
          final yp = planes[0];
          final up = planes[1];
          final vp = planes[2];
          final yy = planes[0].bytes[sy * yp.rowStride + sx * yp.pixelStride];
          final u =
              up.bytes[(sy ~/ 2) * up.rowStride + (sx ~/ 2) * up.pixelStride] -
              128;
          final v =
              vp.bytes[(sy ~/ 2) * vp.rowStride + (sx ~/ 2) * vp.pixelStride] -
              128;
          // Android YUV_420_888 uses video-range BT.601 samples.
          final luminance = 1.164 * (yy - 16);
          _put(
            input,
            index,
            (luminance + 1.596 * v).clamp(0, 255),
            (luminance - 0.392 * u - 0.813 * v).clamp(0, 255),
            (luminance + 2.017 * u).clamp(0, 255),
          );
        }
      }
    }
    return transform;
  }

  Letterbox preparePhoto(Float32List input, Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Could not decode photo. Try JPEG or PNG.');
    }
    final oriented = img.bakeOrientation(decoded);
    final transform = Letterbox(oriented.width, oriented.height, size);
    final resized = img.copyResize(
      oriented,
      width: transform.resizedWidth,
      height: transform.resizedHeight,
      interpolation: img.Interpolation.linear,
    );
    input.fillRange(0, input.length, 114 / 255);
    for (var y = 0; y < resized.height; y++) {
      for (var x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        _put(
          input,
          (y + transform.top) * size + x + transform.left,
          pixel.r,
          pixel.g,
          pixel.b,
        );
      }
    }
    return transform;
  }
}

/// Raw Ultralytics TFLite exports emit normalized xywh, without objectness/NMS.
List<Recognition> decodeYoloOutput({
  required Float32List output,
  required List<int> shape,
  required List<String> labels,
  required Letterbox transform,
  double scoreThreshold = 0.25,
  double iouThreshold = 0.45,
  int maxDetections = 100,
}) {
  final channelFirst = shape[1] == labels.length + 4;
  final count = channelFirst ? shape[2] : shape[1];
  double at(int box, int channel) =>
      output[channelFirst
          ? channel * count + box
          : box * (labels.length + 4) + channel];
  final candidates = <Recognition>[];
  for (var box = 0; box < count; box++) {
    var bestClass = -1;
    var score = 0.0;
    for (var c = 0; c < labels.length; c++) {
      final value = at(box, c + 4);
      if (value.isFinite && value > score) {
        score = value;
        bestClass = c;
      }
    }
    if (bestClass < 0 || score < scoreThreshold) continue;
    final coords = List<double>.generate(4, (c) => at(box, c));
    if (coords.any((v) => !v.isFinite) || coords[2] <= 0 || coords[3] <= 0) {
      continue;
    }
    final rect = transform.undo(coords[0], coords[1], coords[2], coords[3]);
    if (rect.isEmpty) continue;
    final label = labels[bestClass];
    candidates.add(
      Recognition(
        id: box,
        label: label,
        title: Recognition.titleForLabel(label),
        score: score,
        location: rect,
      ),
    );
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  // Bound worst-case quadratic NMS work as Ultralytics does before suppression.
  final sorted = candidates.take(3000);
  final kept = <Recognition>[];
  for (final candidate in sorted) {
    final suppressed = kept.any((previous) {
      if (previous.label != candidate.label) return false;
      final intersection = previous.location.intersect(candidate.location);
      if (intersection.isEmpty) return false;
      final area = intersection.width * intersection.height;
      final union =
          previous.location.width * previous.location.height +
          candidate.location.width * candidate.location.height -
          area;
      return union > 0 && area / union > iouThreshold;
    });
    if (!suppressed) kept.add(candidate);
    if (kept.length == maxDetections) break;
  }
  return kept;
}
