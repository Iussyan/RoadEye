import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../models/recognition.dart';
import '../models/saved_snapshot.dart';

/// Service responsible for saving frames to the device Camera Roll and internal app storage.
class SnapshotStorageService {
  static const String _indexFileName = 'snapshots_index.json';

  Future<Directory> _getSnapshotsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/snapshots');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  File _getIndexFile(Directory snapshotsDir) {
    return File('${snapshotsDir.path}/$_indexFileName');
  }

  /// Saves the captured frame to both internal app storage and the iPhone Camera Roll.
  Future<SavedSnapshot> saveSnapshot({
    required XFile picture,
    required List<Recognition> recognitions,
  }) async {
    final now = DateTime.now();
    final id = 'roadeye_${now.millisecondsSinceEpoch}';
    final snapshotsDir = await _getSnapshotsDirectory();
    final localFilePath = '${snapshotsDir.path}/$id.jpg';

    // 1. Copy image to internal app storage
    final localFile = await File(picture.path).copy(localFilePath);

    // 2. Save to iPhone Camera Roll (Photos App) under "RoadEye" album
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }
      await Gal.putImage(localFile.path, album: 'RoadEye');
      debugPrint('RoadEye: Snapshot saved to Camera Roll album.');
    } catch (e) {
      debugPrint(
        'Could not save to Camera Roll (e.g. simulator/permissions): $e',
      );
    }

    // 3. Compute defect class counts
    final summary = <String, int>{};
    for (final r in recognitions) {
      summary[r.title] = (summary[r.title] ?? 0) + 1;
    }

    final saved = SavedSnapshot(
      id: id,
      filePath: localFile.path,
      timestamp: now,
      defectCount: recognitions.length,
      defectSummary: summary,
    );

    // 4. Update local registry index
    final snapshots = await getSavedSnapshots();
    snapshots.insert(0, saved);
    await _saveIndex(snapshotsDir, snapshots);

    return saved;
  }

  /// Retrieves list of saved snapshots for the in-app gallery.
  Future<List<SavedSnapshot>> getSavedSnapshots() async {
    try {
      final snapshotsDir = await _getSnapshotsDirectory();
      final indexFile = _getIndexFile(snapshotsDir);
      if (!indexFile.existsSync()) {
        return [];
      }
      final content = await indexFile.readAsString();
      final list = SavedSnapshot.decodeList(content);
      // Filter out any entries whose files no longer exist on disk
      return list.where((s) => File(s.filePath).existsSync()).toList();
    } catch (e) {
      debugPrint('Error loading saved snapshots: $e');
      return [];
    }
  }

  /// Deletes a snapshot from internal storage and index.
  Future<void> deleteSnapshot(String id) async {
    try {
      final snapshotsDir = await _getSnapshotsDirectory();
      final snapshots = await getSavedSnapshots();
      final targetIndex = snapshots.indexWhere((s) => s.id == id);
      if (targetIndex >= 0) {
        final target = snapshots[targetIndex];
        final file = File(target.filePath);
        if (file.existsSync()) {
          file.deleteSync();
        }
        snapshots.removeAt(targetIndex);
        await _saveIndex(snapshotsDir, snapshots);
      }
    } catch (e) {
      debugPrint('Error deleting snapshot: $e');
    }
  }

  Future<void> _saveIndex(
    Directory snapshotsDir,
    List<SavedSnapshot> list,
  ) async {
    final indexFile = _getIndexFile(snapshotsDir);
    await indexFile.writeAsString(SavedSnapshot.encodeList(list));
  }
}
