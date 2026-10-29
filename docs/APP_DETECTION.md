# Live detection in the Flutter app

Install a newly built version of RoadEye, open it, and tap **Start scanning**.
Allow camera access. The preview shows the live camera feed with colored boxes,
damage names, and confidence percentages from the bundled YOLOv8 Small RDD
TFLite model. Use pause/resume, camera flip, and the information button as before.
The information panel reports camera-frame delivery FPS separately from the
end-to-end time required for a detection.

The app now uses the same scheduling approach as the Python detector:

- A persistent background isolate owns preprocessing, the interpreter, decoding,
  and class-aware nonmaximum suppression. CPU inference uses two threads.
- Camera preview rendering proceeds independently. Only one inference request
  can be active; frames received while busy are dropped, not queued.
- The newest completed boxes overlay the current preview. They can lag moving
  objects and disappear 1.5 seconds after their source frame. This is detection,
  not object tracking.
- Pause, camera changes, and orientation changes invalidate in-flight results.
  Background/resume serializes camera disposal and reinitialization.
- A model or inference failure displays an error with a retry action instead of
  claiming that scanning succeeded with zero defects.

Preprocessing preserves aspect ratio with 114-gray letterboxing and RGB values
normalized to 0–1. Android YUV planes respect row/pixel strides and the model's
RGB layout; sensor rotation is applied before inference. The pinned iOS plugin
already delivers upright buffers, with front-camera mirroring included. Photo
analysis also uses the background worker and applies EXIF orientation. Saving a
live snapshot analyzes the captured photo before storing its defect summary.

Behavior matches the Python design, but numerical equality and identical FPS
are not promised. The bundled TFLite model has fixed 640×640 input; the Python
tool defaults to 416 pixels and uses PyTorch. Resizing, runtime implementations,
and hardware differ. Both use confidence 0.25, IoU 0.45, and up to 100 detections.
The existing settings slider is not connected to either inference path.

## Build and validate

From a Flutter 3.47.6 terminal at the repository root:

```powershell
flutter pub get
dart run tool/bootstrap.dart
flutter analyze
flutter test
flutter run -d <device-id>
```

iOS release compilation still requires macOS; use the existing **Mobile
release** GitHub Actions workflow and the [iPhone install guide](IPHONE_INSTALL.md).
The change does not update an already installed IPA: rebuild and reinstall it.

On the target iPhone X and an Android device, verify:

1. A known road-damage scene produces boxes aligned with the visible damage.
2. Preview and touch controls remain responsive during slow inference.
3. Rotating the phone, switching cameras, pausing, and backgrounding/resuming
   never restore boxes from an earlier camera/orientation/session.
4. Old boxes disappear when detections stop; a snapshot's class summary matches
   its captured photo. Check both portrait and landscape, front and rear cameras.

Unit/widget tests exercise RGB packing, rotation, letterboxing, decoding/NMS,
frame dropping, expiry, stale-result invalidation, and model-load errors. They
do not establish native runtime compatibility, model accuracy, or device FPS.

References: [TFLite Flutter](https://pub.dev/packages/tflite_flutter) and
[Ultralytics prediction](https://docs.ultralytics.com/modes/predict/).
