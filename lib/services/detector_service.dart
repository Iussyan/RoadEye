import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img_pkg;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/recognition.dart';

/// High-performance YOLO11 TFLite detector with Metal GPU acceleration and zero-copy buffers.
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

  Float32List? _inputBuffer;
  Float32List? _outputBuffer;
  int _inputSize = 640;
  bool _isBCHW = true;

  int _cachedSrcW = 0;
  int _cachedSrcH = 0;
  Int32List? _xTable;
  Int32List? _yTable;

  bool get isModelLoaded => _interpreter != null;
  List<String> get labels => List.unmodifiable(_labels);

  /// Load labels and initialize TFLite interpreter with hardware acceleration.
  Future<bool> initialize() async {
    try {
      // 1. Load labels
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

      // 2. Hardware-accelerated Interpreter initialization
      Interpreter? interpreter;

      if (Platform.isIOS) {
        try {
          final gpuOptions = InterpreterOptions()
            ..threads = 2
            ..addDelegate(
              GpuDelegate(
                options: GpuDelegateOptions(allowPrecisionLoss: true),
              ),
            );
          interpreter = await Interpreter.fromAsset(
            modelPath,
            options: gpuOptions,
          );
          debugPrint('RoadEye: iOS Metal GPU Delegate enabled.');
        } catch (e) {
          debugPrint('RoadEye: Metal GPU fallback to CPU: $e');
        }
      }

      if (interpreter == null) {
        final cpuOptions = InterpreterOptions()..threads = 4;
        try {
          cpuOptions.addDelegate(
            XNNPackDelegate(options: XNNPackDelegateOptions(numThreads: 4)),
          );
        } catch (_) {}
        interpreter = await Interpreter.fromAsset(
          modelPath,
          options: cpuOptions,
        );
        debugPrint('RoadEye: CPU / XNNPack inference active.');
      }

      _interpreter = interpreter;
      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;

      _isBCHW = _inputShape!.length == 4 && _inputShape![1] == 3;
      _inputSize = _isBCHW ? _inputShape![2] : _inputShape![1];

      final inputTotal = _inputShape!.reduce((a, b) => a * b);
      final outputTotal = _outputShape!.reduce((a, b) => a * b);

      _inputBuffer = Float32List(inputTotal);
      _outputBuffer = Float32List(outputTotal);

      debugPrint(
        'RoadEye TFLite ready: input=$_inputShape, output=$_outputShape',
      );
      return true;
    } catch (e) {
      debugPrint('Failed to load TFLite model: $e');
      _interpreter = null;
      return false;
    }
  }

  /// Run real-time inference on a camera frame.
  List<Recognition> detectOnCameraImage(
    CameraImage cameraImage, {
    double scoreThreshold = 0.25,
    double iouThreshold = 0.45,
  }) {
    if (_interpreter == null || _inputBuffer == null || _outputBuffer == null) {
      return const [];
    }

    // 1. Fast zero-copy frame preprocessing directly into _inputBuffer
    _preprocessCameraImageFast(cameraImage);

    // 2. Run inference via direct native memory buffers
    _interpreter!.run(_inputBuffer!.buffer, _outputBuffer!.buffer);

    // 3. Fast detection decoding directly from _outputBuffer
    return _parseOutputFast(scoreThreshold, iouThreshold);
  }

  /// Run inference on a still photo File.
  Future<List<Recognition>> detectOnImageFile(
    File imageFile, {
    double scoreThreshold = 0.25,
    double iouThreshold = 0.45,
  }) async {
    if (_interpreter == null || _inputBuffer == null || _outputBuffer == null) {
      final success = await initialize();
      if (!success) return [];
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img_pkg.decodeImage(bytes);
      if (decoded == null) return [];

      final resized = img_pkg.copyResize(
        decoded,
        width: _inputSize,
        height: _inputSize,
      );

      const inv255 = 1.0 / 255.0;
      final input = _inputBuffer!;
      final channelStride = _inputSize * _inputSize;
      final gOffset = channelStride;
      final bOffset = channelStride * 2;

      for (int y = 0; y < _inputSize; y++) {
        for (int x = 0; x < _inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          final r = pixel.r;
          final g = pixel.g;
          final b = pixel.b;

          final idx = y * _inputSize + x;
          if (_isBCHW) {
            input[idx] = r * inv255;
            input[gOffset + idx] = g * inv255;
            input[bOffset + idx] = b * inv255;
          } else {
            final bhwcIdx = idx * 3;
            input[bhwcIdx] = r * inv255;
            input[bhwcIdx + 1] = g * inv255;
            input[bhwcIdx + 2] = b * inv255;
          }
        }
      }

      _interpreter!.run(_inputBuffer!.buffer, _outputBuffer!.buffer);
      return _parseOutputFast(scoreThreshold, iouThreshold);
    } catch (e) {
      debugPrint('Error detecting on still photo: $e');
      return [];
    }
  }

  void _ensureLookupTables(int srcW, int srcH) {
    if (_cachedSrcW == srcW && _cachedSrcH == srcH && _xTable != null) return;
    _cachedSrcW = srcW;
    _cachedSrcH = srcH;

    final xTable = Int32List(_inputSize);
    for (int x = 0; x < _inputSize; x++) {
      xTable[x] = (x * srcW) ~/ _inputSize;
    }
    final yTable = Int32List(_inputSize);
    for (int y = 0; y < _inputSize; y++) {
      yTable[y] = (y * srcH) ~/ _inputSize;
    }

    _xTable = xTable;
    _yTable = yTable;
  }

  void _preprocessCameraImageFast(CameraImage image) {
    _ensureLookupTables(image.width, image.height);

    final input = _inputBuffer!;
    final xTable = _xTable!;
    final yTable = _yTable!;
    const inv255 = 1.0 / 255.0;

    final isBGRA = image.format.group == ImageFormatGroup.bgra8888;
    final isYUV = image.format.group == ImageFormatGroup.yuv420;

    if (isBGRA) {
      final plane = image.planes[0];
      final bytes = plane.bytes;
      final bytesPerRow = plane.bytesPerRow;

      if (_isBCHW) {
        final channelStride = _inputSize * _inputSize;
        final gOffset = channelStride;
        final bOffset = channelStride * 2;

        for (int y = 0; y < _inputSize; y++) {
          final srcRowOffset = yTable[y] * bytesPerRow;
          final destRowOffset = y * _inputSize;

          for (int x = 0; x < _inputSize; x++) {
            final pixelIndex = srcRowOffset + (xTable[x] << 2);
            if (pixelIndex + 2 < bytes.length) {
              final b = bytes[pixelIndex];
              final g = bytes[pixelIndex + 1];
              final r = bytes[pixelIndex + 2];

              final destIdx = destRowOffset + x;
              input[destIdx] = r * inv255;
              input[gOffset + destIdx] = g * inv255;
              input[bOffset + destIdx] = b * inv255;
            }
          }
        }
      } else {
        // BHWC
        for (int y = 0; y < _inputSize; y++) {
          final srcRowOffset = yTable[y] * bytesPerRow;
          final destRowOffset = (y * _inputSize) * 3;

          for (int x = 0; x < _inputSize; x++) {
            final pixelIndex = srcRowOffset + (xTable[x] << 2);
            if (pixelIndex + 2 < bytes.length) {
              final b = bytes[pixelIndex];
              final g = bytes[pixelIndex + 1];
              final r = bytes[pixelIndex + 2];

              final destIdx = destRowOffset + x * 3;
              input[destIdx] = r * inv255;
              input[destIdx + 1] = g * inv255;
              input[destIdx + 2] = b * inv255;
            }
          }
        }
      }
    } else if (isYUV && image.planes.length >= 3) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      final yRowStride = yPlane.bytesPerRow;
      final uRowStride = uPlane.bytesPerRow;
      final vRowStride = vPlane.bytesPerRow;
      final uPixelStride = uPlane.bytesPerPixel ?? 1;
      final vPixelStride = vPlane.bytesPerPixel ?? 1;

      final channelStride = _inputSize * _inputSize;
      final gOffset = channelStride;
      final bOffset = channelStride * 2;

      for (int y = 0; y < _inputSize; y++) {
        final srcY = yTable[y];
        final yRowOffset = srcY * yRowStride;
        final uvRow = srcY >> 1;
        final uRowOffset = uvRow * uRowStride;
        final vRowOffset = uvRow * vRowStride;
        final destRowOffset = y * _inputSize;

        for (int x = 0; x < _inputSize; x++) {
          final srcX = xTable[x];
          final uvCol = srcX >> 1;

          final yIndex = yRowOffset + srcX;
          final uIndex = uRowOffset + uvCol * uPixelStride;
          final vIndex = vRowOffset + uvCol * vPixelStride;

          if (yIndex < yBytes.length &&
              uIndex < uBytes.length &&
              vIndex < vBytes.length) {
            final yVal = yBytes[yIndex];
            final uVal = uBytes[uIndex] - 128;
            final vVal = vBytes[vIndex] - 128;

            final r = (yVal + 1.370705 * vVal).clamp(0, 255);
            final g = (yVal - 0.337633 * uVal - 0.698001 * vVal).clamp(0, 255);
            final b = (yVal + 1.732446 * uVal).clamp(0, 255);

            final destIdx = destRowOffset + x;
            input[destIdx] = r * inv255;
            input[gOffset + destIdx] = g * inv255;
            input[bOffset + destIdx] = b * inv255;
          }
        }
      }
    }
  }

  List<Recognition> _parseOutputFast(
    double scoreThreshold,
    double iouThreshold,
  ) {
    final output = _outputBuffer!;
    final isChannelFirst =
        _outputShape!.length == 3 && _outputShape![1] <= _outputShape![2];
    final numClasses = isChannelFirst
        ? _outputShape![1] - 4
        : _outputShape![2] - 4;
    final numBoxes = isChannelFirst ? _outputShape![2] : _outputShape![1];

    final candidates = <Recognition>[];
    int nextId = 0;

    final targetW = _inputSize.toDouble();
    final targetH = _inputSize.toDouble();

    if (isChannelFirst) {
      // Shape [1, 8, 8400]:
      // Row 0: cx, Row 1: cy, Row 2: w, Row 3: h, Rows 4..7: class scores
      final stride = numBoxes;
      final cyOffset = stride;
      final wOffset = stride * 2;
      final hOffset = stride * 3;
      final classOffsetBase = stride * 4;

      for (int i = 0; i < numBoxes; i++) {
        double maxScore = 0.0;
        int bestClass = -1;

        for (int c = 0; c < numClasses; c++) {
          final score = output[classOffsetBase + c * stride + i];
          if (score > maxScore) {
            maxScore = score;
            bestClass = c;
          }
        }

        if (maxScore >= scoreThreshold && bestClass >= 0) {
          final cx = output[i];
          final cy = output[cyOffset + i];
          final w = output[wOffset + i];
          final h = output[hOffset + i];

          final normCx = cx > 1.0 ? cx / targetW : cx;
          final normCy = cy > 1.0 ? cy / targetH : cy;
          final normW = w > 1.0 ? w / targetW : w;
          final normH = h > 1.0 ? h / targetH : h;

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
    } else {
      // Shape [1, 8400, 8]
      final rowStride = numClasses + 4;
      for (int i = 0; i < numBoxes; i++) {
        final rowOffset = i * rowStride;
        double maxScore = 0.0;
        int bestClass = -1;

        for (int c = 0; c < numClasses; c++) {
          final score = output[rowOffset + 4 + c];
          if (score > maxScore) {
            maxScore = score;
            bestClass = c;
          }
        }

        if (maxScore >= scoreThreshold && bestClass >= 0) {
          final cx = output[rowOffset];
          final cy = output[rowOffset + 1];
          final w = output[rowOffset + 2];
          final h = output[rowOffset + 3];

          final normCx = cx > 1.0 ? cx / targetW : cx;
          final normCy = cy > 1.0 ? cy / targetH : cy;
          final normW = w > 1.0 ? w / targetW : w;
          final normH = h > 1.0 ? h / targetH : h;

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
    }

    return _applyNMS(candidates, iouThreshold);
  }

  List<Recognition> _applyNMS(List<Recognition> boxes, double iouThreshold) {
    if (boxes.isEmpty) return [];

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
    _inputBuffer = null;
    _outputBuffer = null;
  }
}
