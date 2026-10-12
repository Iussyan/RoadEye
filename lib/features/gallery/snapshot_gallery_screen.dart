import 'dart:io';
import 'package:flutter/material.dart';

import '../../models/saved_snapshot.dart';
import '../../services/snapshot_storage_service.dart';

/// Screen displaying the user's saved road damage snapshots.
class SnapshotGalleryScreen extends StatefulWidget {
  const SnapshotGalleryScreen({super.key, this.storageService});

  final SnapshotStorageService? storageService;

  @override
  State<SnapshotGalleryScreen> createState() => _SnapshotGalleryScreenState();
}

class _SnapshotGalleryScreenState extends State<SnapshotGalleryScreen> {
  late final SnapshotStorageService _storage;
  List<SavedSnapshot> _snapshots = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _storage = widget.storageService ?? SnapshotStorageService();
    _loadSnapshots();
  }

  Future<void> _loadSnapshots() async {
    final list = await _storage.getSavedSnapshots();
    if (mounted) {
      setState(() {
        _snapshots = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSnapshot(SavedSnapshot snapshot) async {
    await _storage.deleteSnapshot(snapshot.id);
    _loadSnapshots();
  }

  void _openDetail(SavedSnapshot snapshot) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SnapshotDetailView(
          snapshot: snapshot,
          onDelete: () async {
            await _deleteSnapshot(snapshot);
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1413),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text(
          'Saved Snapshots',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD7EF9A)),
            )
          : _snapshots.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.photo_library_outlined,
                      size: 64,
                      color: Colors.white24,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No saved snapshots yet',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap "Save frame" while scanning the road to capture frames to your Camera Roll and this gallery.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: _snapshots.length,
              itemBuilder: (context, index) {
                final snapshot = _snapshots[index];
                return GestureDetector(
                  onTap: () => _openDetail(snapshot),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF19211E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(snapshot.filePath),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.white38,
                                  ),
                                ),
                          ),
                          // Bottom metadata gradient overlay
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [Colors.black87, Colors.transparent],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${snapshot.defectCount} defects',
                                    style: const TextStyle(
                                      color: Color(0xFFD7EF9A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDate(snapshot.timestamp),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
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

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _SnapshotDetailView extends StatelessWidget {
  const _SnapshotDetailView({required this.snapshot, required this.onDelete});

  final SavedSnapshot snapshot;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('${snapshot.defectCount} Defects Recorded'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E2623),
                  title: const Text(
                    'Delete Snapshot?',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: const Text(
                    'This removes the snapshot from the RoadEye app gallery.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        onDelete();
                      },
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Image.file(File(snapshot.filePath), fit: BoxFit.contain),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF121715),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'DETECTED BREAKDOWN',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (snapshot.defectSummary.isEmpty)
                    const Text(
                      'No specific defects tagged in this frame.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: snapshot.defectSummary.entries.map((e) {
                        return Chip(
                          backgroundColor: Colors.white12,
                          label: Text(
                            '${e.key}: ${e.value}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
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
