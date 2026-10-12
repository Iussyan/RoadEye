import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/recognition.dart';
import '../../services/detector_service.dart';
import '../../services/snapshot_storage_service.dart';
import '../gallery/snapshot_gallery_screen.dart';
import 'bounding_box_painter.dart';

/// Clean RoadEye live scanner screen with unobtrusive HUD and open road view.
class DetectorScreen extends StatefulWidget {
  const DetectorScreen({
    super.key,
    this.detectorService,
    this.cameras,
    this.cameraPreviewOverride,
    this.storageService,
  });

  final DetectorService? detectorService;
  final List<CameraDescription>? cameras;
  final Widget? cameraPreviewOverride;
  final SnapshotStorageService? storageService;

  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen>
    with WidgetsBindingObserver {
  late final DetectorService _detector;
  late final SnapshotStorageService _storage;
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
  DateTime _lastInferenceTime = DateTime.now();
  double _fps = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detector = widget.detectorService ?? DetectorService();
    _storage = widget.storageService ?? SnapshotStorageService();
    _setupDetectorAndCamera();
  }

  Future<void> _setupDetectorAndCamera() async {
    try {
      final modelLoaded = await _detector.initialize();
      if (!modelLoaded && mounted) {
        debugPrint('Model could not be loaded; running in preview mode.');
      }

      if (widget.cameraPreviewOverride != null) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _errorMessage = null;
          });
        }
        return;
      }

      if (widget.cameras != null) {
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

  void _processCameraFrame(CameraImage image) async {
    final now = DateTime.now();
    // Throttle inference: wait at least 100ms between runs so camera preview stays 60 FPS
    if (_isProcessing ||
        _isPaused ||
        !_detector.isModelLoaded ||
        now.difference(_lastInferenceTime).inMilliseconds < 100) {
      return;
    }

    _isProcessing = true;
    _lastInferenceTime = now;

    // Yield to UI event loop so camera preview and touch events stay responsive
    await Future<void>.delayed(Duration.zero);
    if (!mounted || _isPaused) {
      _isProcessing = false;
      return;
    }

    final stopwatch = Stopwatch()..start();

    try {
      final results = _detector.detectOnCameraImage(
        image,
        scoreThreshold: 0.25,
        iouThreshold: 0.45,
      );

      stopwatch.stop();

      final elapsed = stopwatch.elapsedMilliseconds;
      final diff = DateTime.now().difference(_lastFrameTime).inMilliseconds;
      _lastFrameTime = DateTime.now();

      // Haptic pulse when a new damage instance is detected
      if (results.length > _prevDetectionsCount) {
        HapticFeedback.selectionClick();
      }
      _prevDetectionsCount = results.length;

      if (mounted) {
        setState(() {
          _recognitions = results;
          _inferenceTimeMs = elapsed;
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
    if (controller != null && controller.value.isInitialized) {
      try {
        final newMode = _isTorchOn ? FlashMode.off : FlashMode.torch;
        await controller.setFlashMode(newMode);
      } catch (e) {
        debugPrint('Flash not supported: $e');
      }
    }
    HapticFeedback.lightImpact();
    setState(() => _isTorchOn = !_isTorchOn);
  }

  Future<void> _takeSnapshot() async {
    final controller = _cameraController;
    if (widget.cameraPreviewOverride == null &&
        (controller == null || !controller.value.isInitialized)) {
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() => _isFlashing = true);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _isFlashing = false);
    });

    try {
      if (controller != null && controller.value.isInitialized) {
        final picture = await controller.takePicture();
        await _storage.saveSnapshot(
          picture: picture,
          recognitions: List.of(_recognitions),
        );
      }
      _showToast(
        'Saved to Camera Roll & App (${_recognitions.length} defects)',
      );
    } catch (e) {
      debugPrint('Error saving snapshot: $e');
      _showToast('Frame saved (${_recognitions.length} defects)');
    }
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

  void _showInfoPanel() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              decoration: BoxDecoration(
                color: const Color(0xF2121715),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.white38,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title
                  const Text(
                    'Scanner Telemetry & Legend',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Diagnostics Cards Row
                  Row(
                    children: [
                      _TelemetryCard(
                        title: 'Inference',
                        value: '${_inferenceTimeMs}ms',
                        icon: Icons.timer_outlined,
                        color: const Color(0xFFD7EF9A),
                      ),
                      const SizedBox(width: 12),
                      _TelemetryCard(
                        title: 'Frame Rate',
                        value: '${_fps.toStringAsFixed(0)} FPS',
                        icon: Icons.speed_outlined,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      _TelemetryCard(
                        title: 'Status',
                        value: _isPaused ? 'Paused' : 'Active',
                        icon: Icons.lens,
                        color: _isPaused
                            ? Colors.amber
                            : const Color(0xFF10B981),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Defect Types Legend
                  const Text(
                    'ROAD DEFECT CLASSES',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _LegendRow(
                    label: 'D00',
                    title: 'Longitudinal Crack',
                    color: Color(0xFF3B82F6),
                    description: 'Linear cracks parallel to the road direction',
                  ),
                  const Divider(color: Colors.white10, height: 16),
                  const _LegendRow(
                    label: 'D10',
                    title: 'Transverse Crack',
                    color: Color(0xFF10B981),
                    description: 'Linear cracks perpendicular to the lane',
                  ),
                  const Divider(color: Colors.white10, height: 16),
                  const _LegendRow(
                    label: 'D20',
                    title: 'Alligator Crack',
                    color: Color(0xFFF59E0B),
                    description:
                        'Interconnected fatigue cracks resembling skin',
                  ),
                  const Divider(color: Colors.white10, height: 16),
                  const _LegendRow(
                    label: 'D40',
                    title: 'Pothole',
                    color: Color(0xFFEF4444),
                    description: 'Bowl-shaped holes and surface depressions',
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD7EF9A),
                        side: const BorderSide(color: Color(0xFFD7EF9A)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SnapshotGalleryScreen(storageService: _storage),
                          ),
                        );
                      },
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Open Saved Snapshots Gallery'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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

    if (!_isInitialized ||
        (_cameraController == null && widget.cameraPreviewOverride == null)) {
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
    final camera = _cameraController;
    final previewRatio = camera != null
        ? 1 / camera.value.aspectRatio
        : (9.0 / 16.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full-screen Camera preview and synced Bounding Box canvas
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: size.width,
              height: size.width / previewRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.cameraPreviewOverride ??
                      (camera != null
                          ? CameraPreview(camera)
                          : const SizedBox.shrink()),
                  CustomPaint(
                    painter: BoundingBoxPainter(recognitions: _recognitions),
                  ),
                ],
              ),
            ),
          ),

          // 2. Shutter Flash Animation
          if (_isFlashing)
            AnimatedOpacity(
              opacity: _isFlashing ? 0.7 : 0.0,
              duration: const Duration(milliseconds: 100),
              child: Container(color: Colors.white),
            ),

          // 3. Top Anchor: Back button, Status pill, Subtitle, and Info button
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: Back button
                        _CircularGlassButton(
                          icon: Icons.chevron_left,
                          size: 42,
                          iconSize: 26,
                          onPressed: () => Navigator.of(context).pop(),
                        ),

                        // Center: Compact Status Pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xD9101614),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
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
                                      : const Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isPaused ? 'Paused' : 'Scanning',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Right: Info button
                        _CircularGlassButton(
                          icon: Icons.info_outline,
                          size: 42,
                          iconSize: 20,
                          onPressed: _showInfoPanel,
                        ),
                      ],
                    ),

                    // Subtitle: "X defects detected"
                    const SizedBox(height: 6),
                    Text(
                      '${_recognitions.length} defects detected',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. Toast notification banner
          if (_toastMessage != null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE6141D1A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFD7EF9A).withValues(alpha: 0.5),
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

          // 5. Torch / Flashlight Toggle (anchored on right above bottom dock)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 20, bottom: 120),
                child: _CircularGlassButton(
                  icon: _isTorchOn ? Icons.flash_on : Icons.flash_off,
                  size: 44,
                  iconSize: 20,
                  iconColor: _isTorchOn
                      ? const Color(0xFFD7EF9A)
                      : Colors.white70,
                  backgroundColor: _isTorchOn
                      ? const Color(0x66D7EF9A)
                      : const Color(0xCC141816),
                  onPressed: _toggleTorch,
                ),
              ),
            ),
          ),

          // 6. Bottom Anchor: Smaller pause, capture shutter, and camera flip controls
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16, left: 32, right: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Pause / Resume button
                    _CircularGlassButton(
                      icon: _isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 50,
                      iconSize: 26,
                      onPressed: _togglePause,
                    ),

                    // Central Capture Shutter
                    GestureDetector(
                      onTap: _takeSnapshot,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
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
                          const SizedBox(height: 6),
                          const Text(
                            'Save frame',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 4),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Camera Switch button
                    _CircularGlassButton(
                      icon: Icons.flip_camera_ios_outlined,
                      size: 50,
                      iconSize: 22,
                      iconColor: _availableCameras.length > 1
                          ? Colors.white
                          : Colors.white30,
                      onPressed: _availableCameras.length > 1
                          ? _toggleCamera
                          : null,
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

class _CircularGlassButton extends StatelessWidget {
  const _CircularGlassButton({
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 22,
    this.iconColor = Colors.white,
    this.backgroundColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color iconColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? const Color(0xCC181E1C),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.8,
        ),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: iconSize, color: iconColor),
        onPressed: onPressed,
      ),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.label,
    required this.title,
    required this.color,
    required this.description,
  });

  final String label;
  final String title;
  final Color color;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title ($label)',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
