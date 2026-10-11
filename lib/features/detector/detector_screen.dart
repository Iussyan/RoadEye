import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/recognition.dart';
import '../../services/detector_service.dart';
import 'bounding_box_painter.dart';

/// Real-time road damage detection screen with native iOS styling and tactile feedback.
class DetectorScreen extends StatefulWidget {
  const DetectorScreen({super.key, this.detectorService, this.cameras});

  final DetectorService? detectorService;
  final List<CameraDescription>? cameras;

  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final DetectorService _detector;
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isPaused = false;
  bool _isTorchOn = false;
  bool _isFlashing = false;
  String? _errorMessage;
  String? _toastMessage;
  Timer? _toastTimer;

  List<Recognition> _recognitions = [];
  int _prevDetectionsCount = 0;
  int _inferenceTimeMs = 0;
  DateTime _lastFrameTime = DateTime.now();
  double _fps = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = widget.detectorService ?? DetectorService();
    _setupDetectorAndCamera();
  }

  Future<void> _setupDetectorAndCamera() async {
    try {
      final modelLoaded = await _detector.initialize();
      if (!modelLoaded && mounted) {
        debugPrint('Model could not be loaded; running in preview mode.');
      }

      if (widget.cameras != null && widget.cameras!.isNotEmpty) {
        _availableCameras = widget.cameras!;
      } else {
        _availableCameras = await availableCameras();
      }

      if (_availableCameras.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = 'No camera available on this device.';
          });
        }
        return;
      }

      final rearIndex = _availableCameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _selectedCameraIndex = rearIndex >= 0 ? rearIndex : 0;

      await _initCamera(_availableCameras[_selectedCameraIndex]);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize camera or model: $e';
        });
      }
    }
  }

  Future<void> _initCamera(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );

    _cameraController = controller;

    try {
      await controller.initialize();
      if (!mounted) return;

      await controller.startImageStream(_processCameraFrame);

      setState(() {
        _isInitialized = true;
        _errorMessage = null;
        _isTorchOn = false;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Camera error: ${e.description}';
        });
      }
    }
  }

  void _processCameraFrame(CameraImage image) {
    if (_isProcessing || _isPaused || !_detector.isModelLoaded) return;

    _isProcessing = true;
    final stopwatch = Stopwatch()..start();

    try {
      final results = _detector.detectOnCameraImage(
        image,
        scoreThreshold: 0.25,
        iouThreshold: 0.45,
      );

      stopwatch.stop();

      final now = DateTime.now();
      final diff = now.difference(_lastFrameTime).inMilliseconds;
      _lastFrameTime = now;

      // Haptic pulse when a new damage instance is detected
      if (results.length > _prevDetectionsCount) {
        HapticFeedback.selectionClick();
      }
      _prevDetectionsCount = results.length;

      if (mounted) {
        setState(() {
          _recognitions = results;
          _inferenceTimeMs = stopwatch.elapsedMilliseconds;
          if (diff > 0) {
            _fps = (1000.0 / diff);
          }
        });
      }
    } catch (e) {
      debugPrint('Error processing camera frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final newMode = _isTorchOn ? FlashMode.off : FlashMode.torch;
      await controller.setFlashMode(newMode);
      HapticFeedback.lightImpact();
      setState(() => _isTorchOn = !_isTorchOn);
    } catch (e) {
      debugPrint('Flash not supported: $e');
    }
  }

  Future<void> _takeSnapshot() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    HapticFeedback.mediumImpact();

    // Trigger visual camera shutter flash
    setState(() => _isFlashing = true);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _isFlashing = false);
    });

    _showToast('Snapshot captured (${_recognitions.length} damages)');
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  Future<void> _toggleCamera() async {
    if (_availableCameras.length <= 1) return;

    HapticFeedback.lightImpact();
    setState(() => _isInitialized = false);
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();

    _selectedCameraIndex =
        (_selectedCameraIndex + 1) % _availableCameras.length;
    await _initCamera(_availableCameras[_selectedCameraIndex]);
  }

  void _togglePause() {
    HapticFeedback.lightImpact();
    setState(() {
      _isPaused = !_isPaused;
      if (_isPaused) {
        _recognitions = [];
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(_availableCameras[_selectedCameraIndex]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _toastTimer?.cancel();
    _cameraController?.dispose();
    if (widget.detectorService == null) {
      _detector.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F1715),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: const Text('RoadEye Scanner'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.videocam_off_outlined,
                  size: 56,
                  color: Colors.amber,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: _setupDetectorAndCamera,
                  child: const Text('Retry connection'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isInitialized || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Color(0xFFD7EF9A),
                strokeWidth: 2.5,
              ),
              SizedBox(height: 20),
              Text(
                'Starting RoadEye camera and model...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final camera = _cameraController!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera preview
          Center(
            child: AspectRatio(
              aspectRatio: 1 / camera.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(camera),
                  // 2. Damage bounding boxes overlay
                  CustomPaint(
                    painter: BoundingBoxPainter(
                      recognitions: _recognitions,
                      previewSize: camera.value.previewSize ?? size,
                      screenSize: size,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Shutter Flash Overlay
          if (_isFlashing)
            AnimatedOpacity(
              opacity: _isFlashing ? 0.8 : 0.0,
              duration: const Duration(milliseconds: 100),
              child: Container(color: Colors.white),
            ),

          // 4. Top Bar: Back button & Frosted Telemetry HUD
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button with frosted circular pill
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 0.8,
                          ),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.arrow_back_ios_new,
                            size: 18,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ),

                  // Center Telemetry HUD
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isPaused
                                    ? Colors.amber
                                    : (_detector.isModelLoaded
                                          ? const Color(0xFF10B981)
                                          : Colors.red),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isPaused ? 'PAUSED' : 'LIVE',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${_recognitions.length} damages',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${_inferenceTimeMs}ms',
                              style: const TextStyle(
                                color: Color(0xFFD7EF9A),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${_fps.toStringAsFixed(0)} FPS',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Torch toggle
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _isTorchOn
                              ? const Color(0xFFD7EF9A).withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isTorchOn
                                ? const Color(0xFFD7EF9A)
                                : Colors.white.withValues(alpha: 0.15),
                            width: 0.8,
                          ),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            _isTorchOn ? Icons.flash_on : Icons.flash_off,
                            size: 20,
                            color: _isTorchOn
                                ? const Color(0xFFD7EF9A)
                                : Colors.white70,
                          ),
                          onPressed: _toggleTorch,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5. Toast notification banner (floating below top bar)
          if (_toastMessage != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 64),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF163D35).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFFD7EF9A,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: Color(0xFFD7EF9A),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _toastMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 6. Bottom Controls Dock & Damage Legend
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Frosted Legend Chips
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 0.8,
                            ),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            alignment: WrapAlignment.center,
                            children: const [
                              _LegendChip(
                                label: 'D00',
                                title: 'Longitudinal',
                                color: Color(0xFF3B82F6),
                              ),
                              _LegendChip(
                                label: 'D10',
                                title: 'Transverse',
                                color: Color(0xFF10B981),
                              ),
                              _LegendChip(
                                label: 'D20',
                                title: 'Alligator',
                                color: Color(0xFFF59E0B),
                              ),
                              _LegendChip(
                                label: 'D40',
                                title: 'Pothole',
                                color: Color(0xFFEF4444),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Frosted Controls Dock
                    ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(36),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Pause / Play toggle
                              IconButton(
                                iconSize: 28,
                                color: Colors.white,
                                icon: Icon(
                                  _isPaused
                                      ? Icons.play_arrow_rounded
                                      : Icons.pause_rounded,
                                ),
                                onPressed: _togglePause,
                                tooltip: _isPaused
                                    ? 'Resume scanner'
                                    : 'Pause scanner',
                              ),
                              const SizedBox(width: 24),

                              // Central Shutter Button
                              GestureDetector(
                                onTap: _takeSnapshot,
                                child: Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4,
                                    ),
                                    color: Colors.transparent,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),

                              // Flip Camera button
                              IconButton(
                                iconSize: 26,
                                color: _availableCameras.length > 1
                                    ? Colors.white
                                    : Colors.white30,
                                icon: const Icon(Icons.flip_camera_ios_rounded),
                                onPressed: _availableCameras.length > 1
                                    ? _toggleCamera
                                    : null,
                                tooltip: 'Flip camera',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.title,
    required this.color,
  });

  final String label;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Text(
        '$label $title',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
