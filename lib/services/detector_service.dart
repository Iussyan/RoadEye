import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/recognition.dart';
import 'yolo_frame_processor.dart';

/// One persistent worker owns preprocessing, TFLite, decoding, and NMS.
/// Only one request can be in flight, so live frames never form a backlog.
class DetectorService {
  DetectorService({
    this.modelPath = 'assets/models/best.tflite',
    this.labelsPath = 'assets/models/labels.txt',
  });

  final String modelPath;
  final String labelsPath;
  String? initializationError;
  List<String> _labels = [];
  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _responses;
  ReceivePort? _errors;
  ReceivePort? _exits;
  Completer<bool>? _initializing;
  Completer<List<Recognition>>? _pending;
  bool _disposed = false;

  bool get isModelLoaded => _commands != null && !_disposed;
  bool get isBusy => _pending != null;
  List<String> get labels => List.unmodifiable(_labels);

  Future<bool> initialize() async {
    if (_disposed) return false;
    if (isModelLoaded) return true;
    if (_initializing != null) return _initializing!.future;
    final ready = Completer<bool>();
    _initializing = ready;
    initializationError = null;
    try {
      final labels = await rootBundle.loadString(labelsPath);
      _labels = labels
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (_labels.isEmpty) throw StateError('Model labels are empty.');
      final asset = await rootBundle.load(modelPath);
      if (_disposed) return false;
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final responses = ReceivePort();
      final errors = ReceivePort();
      final exits = ReceivePort();
      _responses = responses;
      _errors = errors;
      _exits = exits;
      responses.listen((dynamic message) {
        if (_disposed) return;
        if (message is SendPort) {
          _commands = message;
          if (!ready.isCompleted) ready.complete(true);
        } else if (message is List<Recognition>) {
          final pending = _pending;
          _pending = null;
          pending?.complete(message);
        } else {
          _fail(StateError('Detection failed: $message'));
        }
      });
      errors.listen(
        (dynamic error) => _fail(StateError('Inference worker: $error')),
      );
      exits.listen((dynamic _) {
        if (!_disposed) {
          _fail(StateError('Inference worker stopped. Retry the scanner.'));
        }
      });
      _isolate = await Isolate.spawn(
        _detectorWorker,
        (responses.sendPort, TransferableTypedData.fromList([bytes]), _labels),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        debugName: 'RoadEye inference',
      );
      if (_disposed) {
        _stopWorker();
        return false;
      }
      return await ready.future.timeout(const Duration(seconds: 60));
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      if (!ready.isCompleted) ready.complete(false);
      _initializing = null;
    }
  }

  void _fail(Object error) {
    initializationError = error.toString();
    _stopWorker();
    final pending = _pending;
    _pending = null;
    pending?.completeError(error);
    if (_initializing case final ready? when !ready.isCompleted) {
      ready.complete(false);
    }
  }

  Future<List<Recognition>> _request(Map<String, Object> request) {
    if (!isModelLoaded) {
      return Future.error(
        StateError(initializationError ?? 'Detection model is not ready.'),
      );
    }
    if (isBusy) {
      return Future.error(
        StateError('Inference is already processing a frame.'),
      );
    }
    final pending = Completer<List<Recognition>>();
    _pending = pending;
    _commands!.send(request);
    return pending.future;
  }

  Future<List<Recognition>> detectOnCameraImage(
    CameraImage cameraImage, {
    double scoreThreshold = 0.25,
    double iouThreshold = 0.45,
    int rotation = 0,
  }) {
    return _request({
      'kind': 'camera',
      'width': cameraImage.width,
      'height': cameraImage.height,
      'format': cameraImage.format.group.name,
      'rotation': rotation,
      'planes': cameraImage.planes
          .map(
            (plane) => <String, Object>{
              'bytes': TransferableTypedData.fromList([plane.bytes]),
              'rowStride': plane.bytesPerRow,
              'pixelStride':
                  plane.bytesPerPixel ??
                  (cameraImage.format.group == ImageFormatGroup.bgra8888
                      ? 4
                      : 1),
            },
          )
          .toList(),
      'confidence': scoreThreshold,
      'iou': iouThreshold,
    });
  }

  Future<List<Recognition>> detectOnImageFile(
    File imageFile, {
    double scoreThreshold = 0.25,
    double iouThreshold = 0.45,
  }) async {
    if (!isModelLoaded && !await initialize()) {
      throw StateError(
        'Could not load the detection model: $initializationError',
      );
    }
    final bytes = await imageFile.readAsBytes();
    return _request({
      'kind': 'photo',
      'bytes': TransferableTypedData.fromList([bytes]),
      'confidence': scoreThreshold,
      'iou': iouThreshold,
    });
  }

  void _stopWorker() {
    _commands?.send(<String, Object>{'kind': 'close'});
    _commands = null;
    final isolate = _isolate;
    if (isolate != null) {
      Timer(
        const Duration(seconds: 3),
        () => isolate.kill(priority: Isolate.immediate),
      );
    }
    _isolate = null;
    _responses?.close();
    _errors?.close();
    _exits?.close();
    _responses = null;
    _errors = null;
    _exits = null;
  }

  void dispose() {
    _disposed = true;
    _stopWorker();
    final pending = _pending;
    _pending = null;
    pending?.completeError(StateError('Detector disposed.'));
    if (_initializing case final ready? when !ready.isCompleted) {
      ready.complete(false);
    }
  }
}

void _detectorWorker(
  (SendPort, TransferableTypedData, List<String>) startup,
) async {
  final (responses, model, labels) = startup;
  Interpreter? interpreter;
  final commands = ReceivePort();
  try {
    final options = InterpreterOptions()..threads = 2;
    try {
      // Creation, execution, and disposal all occur on this isolate.
      interpreter = Interpreter.fromBuffer(
        model.materialize().asUint8List(),
        options: options,
      );
    } finally {
      options.delete();
    }
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputShape = inputTensor.shape;
    final outputShape = outputTensor.shape;
    final channelFirst = inputShape.length == 4 && inputShape[1] == 3;
    if (inputTensor.type != TensorType.float32 ||
        outputTensor.type != TensorType.float32 ||
        inputShape.length != 4 ||
        inputShape[0] != 1 ||
        (channelFirst
            ? inputShape[2] != inputShape[3]
            : inputShape[1] != inputShape[2] || inputShape[3] != 3) ||
        outputShape.length != 3 ||
        outputShape[0] != 1 ||
        (outputShape[1] != labels.length + 4 &&
            outputShape[2] != labels.length + 4)) {
      throw StateError(
        'Unsupported model contract: float32 square RGB input and raw '
        'normalized YOLO output required. Found $inputShape / $outputShape.',
      );
    }
    final size = inputShape[channelFirst ? 2 : 1];
    final input = Float32List(inputShape.reduce((a, b) => a * b));
    final output = Float32List(outputShape.reduce((a, b) => a * b));
    final processor = YoloFrameProcessor(
      size: size,
      channelFirst: channelFirst,
    );
    responses.send(commands.sendPort);
    await for (final dynamic raw in commands) {
      final request = raw as Map<String, Object>;
      if (request['kind'] == 'close') break;
      try {
        final Letterbox transform;
        if (request['kind'] == 'camera') {
          final planes = (request['planes'] as List<Map<String, Object>>)
              .map(
                (plane) => FramePlane(
                  (plane['bytes'] as TransferableTypedData)
                      .materialize()
                      .asUint8List(),
                  plane['rowStride'] as int,
                  plane['pixelStride'] as int,
                ),
              )
              .toList();
          transform = processor.prepareCamera(
            input: input,
            width: request['width'] as int,
            height: request['height'] as int,
            format: request['format'] as String,
            planes: planes,
            rotation: request['rotation'] as int,
          );
        } else {
          transform = processor.preparePhoto(
            input,
            (request['bytes'] as TransferableTypedData)
                .materialize()
                .asUint8List(),
          );
        }
        interpreter.run(input.buffer, output.buffer);
        responses.send(
          decodeYoloOutput(
            output: output,
            shape: outputShape,
            labels: labels,
            transform: transform,
            scoreThreshold: request['confidence'] as double,
            iouThreshold: request['iou'] as double,
          ),
        );
      } catch (error) {
        responses.send(error.toString());
      }
    }
  } catch (error) {
    responses.send(error.toString());
  } finally {
    interpreter?.close();
    commands.close();
  }
}
