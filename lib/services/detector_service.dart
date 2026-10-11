import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/recognition.dart';

/// Service that loads the YOLO11 TFLite model and executes road damage detection.
class DetectorService {
  DetectorService({
    this.modelPath = 'assets/models/best.tflite',
    this.labelsPath = 'assets/models/labels.txt',
  });

  final String modelPath;
  final String labelsPath;

  Interpreter? _interpreter;
  List<String> _labels = ['D00', 'D10', 'D20', 'D40'];

  List<int>? _inputShape;
  List<int>? _outputShape;

  bool get isModelLoaded => _interpreter != null;
  List<String> get labels => List.unmodifiable(_labels);

  /// Load labels and initialize TFLite interpreter.
  Future<bool> initialize() async {
    try {
      // Load class labels
      try {
        final labelsData = await rootBundle.loadString(labelsPath);
        final lines = labelsData
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) {
          _labels = lines;
        }
      } catch (e) {
        debugPrint('Using default labels, could not load $labelsPath: $e');
      }

      // Initialize interpreter options
      final options = InterpreterOptions()..threads = 4;

      _interpreter = await Interpreter.fromAsset(modelPath, options: options);

      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;

      debugPrint('RoadEye TFLite Model loaded successfully.');
      debugPrint('Input shape: $_inputShape, Output shape: $_outputShape');
      return true;
    } catch (e) {
      debugPrint('Failed to load TFLite model: $e');
      _interpreter = null;
      return false;
    }
  }

  /// Run inference on a camera image stream.
  List<Recognition> detectOnCameraImage(
    CameraImage cameraImage, {
    double scoreThreshold = 0.25,
    double iouThreshold = 0.45,
  }) {
    if (_interpreter == null || _inputShape == null || _outputShape == null) {
      return const [];
    }

    // Prepare 640x640 input buffer
    final inputTensor = _preprocessCameraImage(cameraImage);

    // Prepare output buffer based on output shape
    // YOLO11 output is either [1, 8, 8400] or [1, 8400, 8]
    final isChannelFirst =
        _outputShape!.length == 3 && _outputShape![1] <= _outputShape![2];
    final numClasses = isChannelFirst
        ? _outputShape![1] - 4
        : _outputShape![2] - 4;
    final numBoxes = isChannelFirst ? _outputShape![2] : _outputShape![1];

    final outputBuffer = List.generate(
      _outputShape![0],
      (_) => List.generate(
        _outputShape![1],
        (_) => List.filled(_outputShape![2], 0.0),
      ),
    );

    _interpreter!.run(inputTensor, outputBuffer);

    // Parse YOLO detections
    final candidates = <Recognition>[];
    int nextId = 0;

    for (int i = 0; i < numBoxes; i++) {
      double cx, cy, w, h;
      int bestClass = -1;
      double maxScore = 0.0;

      if (isChannelFirst) {
        cx = outputBuffer[0][0][i];
        cy = outputBuffer[0][1][i];
        w = outputBuffer[0][2][i];
        h = outputBuffer[0][3][i];

        for (int c = 0; c < numClasses; c++) {
          final score = outputBuffer[0][4 + c][i];
          if (score > maxScore) {
            maxScore = score;
            bestClass = c;
          }
        }
      } else {
        cx = outputBuffer[0][i][0];
        cy = outputBuffer[0][i][1];
        w = outputBuffer[0][i][2];
        h = outputBuffer[0][i][3];

        for (int c = 0; c < numClasses; c++) {
          final score = outputBuffer[0][i][4 + c];
          if (score > maxScore) {
            maxScore = score;
            bestClass = c;
          }
        }
      }

      if (maxScore >= scoreThreshold && bestClass >= 0) {
        // If coordinates are in pixel space (0..640), normalize to [0.0, 1.0]
        final targetW = (_inputShape![1] == 3)
            ? _inputShape![3].toDouble()
            : _inputShape![2].toDouble();
        final targetH = (_inputShape![1] == 3)
            ? _inputShape![2].toDouble()
            : _inputShape![1].toDouble();

        double normCx = cx > 1.0 ? cx / targetW : cx;
        double normCy = cy > 1.0 ? cy / targetH : cy;
        double normW = w > 1.0 ? w / targetW : w;
        double normH = h > 1.0 ? h / targetH : h;

        final left = (normCx - normW / 2).clamp(0.0, 1.0);
        final top = (normCy - normH / 2).clamp(0.0, 1.0);
        final boxW = normW.clamp(0.0, 1.0 - left);
        final boxH = normH.clamp(0.0, 1.0 - top);

        final label = bestClass < _labels.length
            ? _labels[bestClass]
            : 'D$bestClass';
        candidates.add(
          Recognition(
            id: nextId++,
            label: label,
            title: Recognition.titleForLabel(label),
            score: maxScore,
            location: Rect.fromLTWH(left, top, boxW, boxH),
          ),
        );
      }
    }

    return _applyNMS(candidates, iouThreshold);
  }

  /// Converts CameraImage into normalized float tensor [1, 3, 640, 640] or [1, 640, 640, 3].
  dynamic _preprocessCameraImage(CameraImage image) {
    const targetSize = 640;
    final isBCHW = _inputShape!.length == 4 && _inputShape![1] == 3;

    if (isBCHW) {
      final input = List.generate(
        1,
        (_) => List.generate(
          3,
          (_) => List.generate(targetSize, (_) => List.filled(targetSize, 0.0)),
        ),
      );

      _sampleImageToRGB(image, targetSize, (x, y, r, g, b) {
        input[0][0][y][x] = r / 255.0;
        input[0][1][y][x] = g / 255.0;
        input[0][2][y][x] = b / 255.0;
      });
      return input;
    } else {
      final input = List.generate(
        1,
        (_) => List.generate(
          targetSize,
          (_) => List.generate(targetSize, (_) => List.filled(3, 0.0)),
        ),
      );

      _sampleImageToRGB(image, targetSize, (x, y, r, g, b) {
        input[0][y][x][0] = r / 255.0;
        input[0][y][x][1] = g / 255.0;
        input[0][y][x][2] = b / 255.0;
      });
      return input;
    }
  }

  /// Samples camera frame into 640x640 RGB values.
  void _sampleImageToRGB(
    CameraImage image,
    int targetSize,
    void Function(int x, int y, int r, int g, int b) onPixel,
  ) {
    final srcWidth = image.width;
    final srcHeight = image.height;

    final isBGRA = image.format.group == ImageFormatGroup.bgra8888;
    final isYUV = image.format.group == ImageFormatGroup.yuv420;

    for (int y = 0; y < targetSize; y++) {
      final srcY = (y * srcHeight) ~/ targetSize;
      for (int x = 0; x < targetSize; x++) {
        final srcX = (x * srcWidth) ~/ targetSize;

        int r = 0, g = 0, b = 0;

        if (isBGRA) {
          final plane = image.planes[0];
          final bytesPerRow = plane.bytesPerRow;
          final pixelIndex = srcY * bytesPerRow + srcX * 4;
          if (pixelIndex + 3 < plane.bytes.length) {
            b = plane.bytes[pixelIndex];
            g = plane.bytes[pixelIndex + 1];
            r = plane.bytes[pixelIndex + 2];
          }
        } else if (isYUV && image.planes.length >= 3) {
          final yPlane = image.planes[0];
          final uPlane = image.planes[1];
          final vPlane = image.planes[2];

          final yIndex = srcY * yPlane.bytesPerRow + srcX;
          final uvRow = srcY ~/ 2;
          final uvCol = srcX ~/ 2;
          final uIndex =
              uvRow * (uPlane.bytesPerRow) +
              uvCol * (uPlane.bytesPerPixel ?? 1);
          final vIndex =
              uvRow * (vPlane.bytesPerRow) +
              uvCol * (vPlane.bytesPerPixel ?? 1);

          if (yIndex < yPlane.bytes.length &&
              uIndex < uPlane.bytes.length &&
              vIndex < vPlane.bytes.length) {
            final yVal = yPlane.bytes[yIndex];
            final uVal = uPlane.bytes[uIndex] - 128;
            final vVal = vPlane.bytes[vIndex] - 128;

            r = (yVal + (1.370705 * vVal)).round().clamp(0, 255);
            g = (yVal - (0.337633 * uVal) - (0.698001 * vVal)).round().clamp(
              0,
              255,
            );
            b = (yVal + (1.732446 * uVal)).round().clamp(0, 255);
          }
        } else {
          // Fallback grayscale from first plane
          final plane = image.planes[0];
          final index = (srcY * plane.bytesPerRow + srcX).clamp(
            0,
            plane.bytes.length - 1,
          );
          final val = plane.bytes[index];
          r = val;
          g = val;
          b = val;
        }

        onPixel(x, y, r, g, b);
      }
    }
  }

  /// Apply Non-Maximum Suppression (NMS) to eliminate overlapping bounding boxes.
  List<Recognition> _applyNMS(List<Recognition> boxes, double iouThreshold) {
    if (boxes.isEmpty) return [];

    // Sort by confidence score descending
    final sorted = List<Recognition>.from(boxes)
      ..sort((a, b) => b.score.compareTo(a.score));

    final results = <Recognition>[];
    final suppressed = List<bool>.filled(sorted.length, false);

    for (int i = 0; i < sorted.length; i++) {
      if (suppressed[i]) continue;

      final current = sorted[i];
      results.add(current);

      for (int j = i + 1; j < sorted.length; j++) {
        if (suppressed[j]) continue;

        final candidate = sorted[j];
        if (current.label == candidate.label) {
          final iou = _calculateIoU(current.location, candidate.location);
          if (iou > iouThreshold) {
            suppressed[j] = true;
          }
        }
      }
    }

    return results;
  }

  /// Calculates Intersection over Union (IoU) between two rectangles.
  double _calculateIoU(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) {
      return 0.0;
    }

    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        (a.width * a.height) + (b.width * b.height) - intersectionArea;

    return unionArea > 0 ? intersectionArea / unionArea : 0.0;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
