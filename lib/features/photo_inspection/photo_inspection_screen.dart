import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../models/recognition.dart';
import '../../services/detector_service.dart';
import '../../services/snapshot_storage_service.dart';
import '../detector/bounding_box_painter.dart';

/// Screen that runs road damage detection on an imported still image.
class PhotoInspectionScreen extends StatefulWidget {
  const PhotoInspectionScreen({
    super.key,
    required this.imageFile,
    this.detectorService,
    this.storageService,
  });

  final File imageFile;
  final DetectorService? detectorService;
  final SnapshotStorageService? storageService;

  @override
  State<PhotoInspectionScreen> createState() => _PhotoInspectionScreenState();
}

class _PhotoInspectionScreenState extends State<PhotoInspectionScreen> {
  late final DetectorService _detector;
  late final SnapshotStorageService _storage;

  bool _isAnalyzing = true;
  List<Recognition> _recognitions = [];
  bool _isSaved = false;
  String? _analysisError;

  @override
  void initState() {
    super.initState();
    _detector = widget.detectorService ?? DetectorService();
    _storage = widget.storageService ?? SnapshotStorageService();
    _analyzePhoto();
  }

  Future<void> _analyzePhoto() async {
    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
    });
    try {
      final results = await _detector.detectOnImageFile(widget.imageFile);
      if (mounted) {
        setState(() => _recognitions = results);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _analysisError = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  @override
  void dispose() {
    if (widget.detectorService == null) _detector.dispose();
    super.dispose();
  }

  Future<void> _saveResult() async {
    try {
      await _storage.saveSnapshot(
        picture: XFile(widget.imageFile.path),
        recognitions: _recognitions,
      );
      if (mounted) {
        setState(() => _isSaved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to Photos & RoadEye Gallery!'),
            backgroundColor: Color(0xFF163D35),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving photo test result: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Photo Inspection'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.file(
                    widget.imageFile,
                    fit: BoxFit.contain,
                    errorBuilder: (_, error, stackTrace) => const Text(
                      'Photo preview unavailable',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  if (!_isAnalyzing &&
                      _analysisError == null &&
                      _recognitions.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: BoundingBoxPainter(
                          recognitions: _recognitions,
                        ),
                      ),
                    ),
                  if (_isAnalyzing)
                    Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.all(24),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFD7EF9A)),
                          SizedBox(height: 16),
                          Text(
                            'Analyzing road photo...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom Results Sheet
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF141917),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isAnalyzing
                            ? 'Scanning...'
                            : _analysisError != null
                            ? 'Photo analysis failed'
                            : '${_recognitions.length} Defects Found',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!_isAnalyzing &&
                          _analysisError == null &&
                          _recognitions.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFD7EF9A,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Damage detected',
                            style: TextStyle(
                              color: Color(0xFFD7EF9A),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_isAnalyzing && _analysisError != null) ...[
                    Text(
                      _analysisError!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    TextButton(
                      onPressed: _analyzePhoto,
                      child: const Text('Retry analysis'),
                    ),
                  ] else if (!_isAnalyzing && _recognitions.isEmpty)
                    const Text(
                      'No cracks or potholes detected in this photo.',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    )
                  else if (!_isAnalyzing)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _recognitions.map((r) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: r.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: r.color.withValues(alpha: 0.7),
                            ),
                          ),
                          child: Text(
                            '${r.title} (${(r.score * 100).toStringAsFixed(0)}%)',
                            style: TextStyle(
                              color: r.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0066FF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed:
                          _isSaved || _isAnalyzing || _analysisError != null
                          ? null
                          : _saveResult,
                      icon: Icon(_isSaved ? Icons.check : Icons.download),
                      label: Text(
                        _isSaved ? 'Saved to Gallery' : 'Save Result',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
