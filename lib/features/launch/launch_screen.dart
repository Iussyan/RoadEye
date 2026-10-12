import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/saved_snapshot.dart';
import '../../services/snapshot_storage_service.dart';
import '../detector/detector_screen.dart';
import '../gallery/snapshot_gallery_screen.dart';
import '../photo_inspection/photo_inspection_screen.dart';
import '../settings/settings_sheet.dart';

/// Modern native iOS landing page for RoadEye road inspection.
class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key, this.storageService, this.imagePicker});

  final SnapshotStorageService? storageService;
  final ImagePicker? imagePicker;

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen> {
  late final SnapshotStorageService _storage;
  late final ImagePicker _picker;
  List<SavedSnapshot> _recentSnapshots = [];
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _storage = widget.storageService ?? SnapshotStorageService();
    _picker = widget.imagePicker ?? ImagePicker();
    _loadRecentSnapshots();
  }

  Future<void> _loadRecentSnapshots() async {
    final list = await _storage.getSavedSnapshots();
    if (mounted) {
      setState(() {
        _recentSnapshots = list;
      });
    }
  }

  Future<void> _pickAndTestPhoto() async {
    HapticFeedback.lightImpact();
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null && mounted) {
        Navigator.of(context)
            .push(
              MaterialPageRoute<void>(
                builder: (_) => PhotoInspectionScreen(
                  imageFile: File(picked.path),
                  storageService: _storage,
                ),
              ),
            )
            .then((_) => _loadRecentSnapshots());
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _openSettings() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SettingsSheet(),
    );
  }

  void _openScanner() {
    HapticFeedback.lightImpact();
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DetectorScreen()))
        .then((_) => _loadRecentSnapshots());
  }

  void _openGallery() {
    HapticFeedback.lightImpact();
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => SnapshotGalleryScreen(storageService: _storage),
          ),
        )
        .then((_) => _loadRecentSnapshots());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header: Logo, RoadEye Brand, Settings Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RoadEyeBrandLogo(),
                        const SizedBox(width: 12),
                        const Flexible(
                          child: Text(
                            'RoadEye',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Color(0xFF0F172A),
                      size: 24,
                    ),
                    onPressed: _openSettings,
                    tooltip: 'Settings & About',
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 2. Headline & Subtitle
              const Text(
                'Road inspection',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Capture defects. Keep roads moving.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 24),

              // 3. Hero Inspection Card
              _HeroInspectionCard(onStartScan: _openScanner),
              const SizedBox(height: 16),

              // 4. "Test a photo" Secondary Card
              _TestPhotoCard(onTap: _pickAndTestPhoto),
              const SizedBox(height: 28),

              // 5. "Saved detections" Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Saved detections',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _openGallery,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF0066FF),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View all'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 6. Saved Detections Card / Preview
              if (_recentSnapshots.isEmpty)
                _EmptyDetectionsCard()
              else
                _RecentDetectionsList(
                  snapshots: _recentSnapshots.take(4).toList(),
                  onTap: _openGallery,
                ),
              const SizedBox(height: 28),

              // 7. Offline Indicator
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Detection works offline',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),

      // 8. Bottom Navigation Bar
      bottomNavigationBar: _BottomNavBar(
        currentIndex: _currentTabIndex,
        onTap: (index) {
          setState(() => _currentTabIndex = index);
          if (index == 0) {
            _openScanner();
          } else if (index == 1) {
            _openGallery();
          } else if (index == 2) {
            _openSettings();
          }
        },
      ),
    );
  }
}

/// Brand logo matching RoadEye's blue road sign aesthetic.
class _RoadEyeBrandLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF0066FF),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0066FF).withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CustomPaint(painter: _RoadLogoPainter()),
    );
  }
}

class _RoadLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Left lane boundary
    canvas.drawLine(
      Offset(size.width * 0.28, size.height * 0.76),
      Offset(size.width * 0.38, size.height * 0.24),
      paint,
    );

    // Right lane boundary
    canvas.drawLine(
      Offset(size.width * 0.72, size.height * 0.76),
      Offset(size.width * 0.62, size.height * 0.24),
      paint,
    );

    // Center dashed stripe
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.74),
      Offset(size.width * 0.50, size.height * 0.60),
      dashPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.46),
      Offset(size.width * 0.50, size.height * 0.34),
      dashPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Hero dark card featuring the driver POV road preview and "Start scanning" button.
class _HeroInspectionCard extends StatelessWidget {
  const _HeroInspectionCard({required this.onStartScan});

  final VoidCallback onStartScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1D33),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1D33).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Image with Viewfinder Corner Reticles
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SizedBox(
              height: 190,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/hero_road.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFF1E293B),
                      child: const Center(
                        child: Icon(
                          Icons.drive_eta,
                          color: Colors.white38,
                          size: 56,
                        ),
                      ),
                    ),
                  ),
                  // Reticle corner overlays
                  const Positioned(
                    top: 14,
                    left: 14,
                    child: _CornerBracket(top: true, left: true),
                  ),
                  const Positioned(
                    top: 14,
                    right: 14,
                    child: _CornerBracket(top: true, left: false),
                  ),
                  const Positioned(
                    bottom: 14,
                    left: 14,
                    child: _CornerBracket(top: false, left: true),
                  ),
                  const Positioned(
                    bottom: 14,
                    right: 14,
                    child: _CornerBracket(top: false, left: false),
                  ),
                ],
              ),
            ),
          ),

          // 2. Bottom Card Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "Ready to scan" pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.circle, color: Color(0xFF0066FF), size: 8),
                      SizedBox(width: 6),
                      Text(
                        'Ready to scan',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                const Text(
                  'Start an inspection',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Detect cracks and potholes with your camera.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 20),

                // Primary Start scanning button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0066FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: onStartScan,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.camera_alt_outlined, size: 20),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Start scanning',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Blue viewfinder corner bracket widget.
class _CornerBracket extends StatelessWidget {
  const _CornerBracket({required this.top, required this.left});

  final bool top;
  final bool left;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(26, 26),
      painter: _CornerBracketPainter(top: top, left: left),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  _CornerBracketPainter({required this.top, required this.left});

  final bool top;
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0066FF)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 4);
      path.quadraticBezierTo(0, 0, 4, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(size.width - 4, 0);
      path.quadraticBezierTo(size.width, 0, size.width, 4);
      path.lineTo(size.width, size.height);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height - 4);
      path.quadraticBezierTo(0, size.height, 4, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width - 4, size.height);
      path.quadraticBezierTo(
        size.width,
        size.height,
        size.width,
        size.height - 4,
      );
      path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Secondary action card for photo test.
class _TestPhotoCard extends StatelessWidget {
  const _TestPhotoCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.image_outlined,
                color: Color(0xFF334155),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Test a photo',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Choose an image from your gallery.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 22),
          ],
        ),
      ),
    );
  }
}

/// Empty state when no detections are saved yet.
class _EmptyDetectionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: const [
          Icon(Icons.folder_open_outlined, size: 44, color: Color(0xFF94A3B8)),
          SizedBox(height: 12),
          Text(
            'No saved detections yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Your captured results will appear here.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

/// Horizontal list preview of recent detections.
class _RecentDetectionsList extends StatelessWidget {
  const _RecentDetectionsList({required this.snapshots, required this.onTap});

  final List<SavedSnapshot> snapshots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: snapshots.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final snapshot = snapshots[index];
          return GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 110,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(snapshot.filePath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[300],
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        color: Colors.black54,
                        child: Text(
                          '${snapshot.defectCount} defects',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Native iOS 3-tab bottom navigation bar.
class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: const Color(0xFFE2E8F0), width: 0.8),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: _NavTabItem(
                  icon: Icons.camera_alt,
                  label: 'Scan',
                  isSelected: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
              ),
              Expanded(
                child: _NavTabItem(
                  icon: Icons.folder_outlined,
                  label: 'Saved',
                  isSelected: currentIndex == 1,
                  onTap: () => onTap(1),
                ),
              ),
              Expanded(
                child: _NavTabItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  isSelected: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTabItem extends StatelessWidget {
  const _NavTabItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? const Color(0xFF0066FF)
        : const Color(0xFF64748B);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 3),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFF0066FF),
                  shape: BoxShape.circle,
                ),
              ),
            ] else
              const SizedBox(height: 7),
          ],
        ),
      ),
    );
  }
}
