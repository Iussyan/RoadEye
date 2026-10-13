# Switch to YOLOv8 Small RDD

Requested source: `YOLOv8_Small_RDD.pt` in the repository root.
The Flutter detector runs TensorFlow Lite and loads `assets/models/best.tflite`.
The PyTorch checkpoint must be exported; renaming `.pt` to `.tflite` does not
convert it. The old asset remains active until the new export is installed.

## Export in Colab

Upload `YOLOv8_Small_RDD.pt` and `tool/export_rdd_model.py` into a fresh Colab
runtime. Run:

```python
%pip install ultralytics==8.3.200
```

```python
!python export_rdd_model.py YOLOv8_Small_RDD.pt
```

The script uses the legacy TFLite exporter with float32 input/output, 640-pixel
input, and no embedded NMS, matching the current Dart decoder. Export tooling
may install additional conversion dependencies. The script validates tensor
shapes and runs CPU smoke inference before producing a ZIP in a new
`roadeye-yolov8-*` folder. Labels come from checkpoint class IDs, not an assumed
RDD class order. `model.json` records source/export hashes and tensor shapes.

Download the ZIP through Colab's Files pane. Extract `best.tflite`, `labels.txt`,
and `model.json` into `assets/models/`, replacing the existing model and labels.
Retain a backup outside the assets folder before replacing them. No runtime path
change is needed; `pubspec.yaml` already bundles `assets/models/`.

## Verify the switch

Run `flutter analyze` and `flutter test`, then rebuild the release app. Confirm
the logged input/output shapes match `model.json`. Inspect a known road-damage
photo and confirm class names and bounding boxes, then test camera inference
and responsiveness on the iPhone X. CPU smoke inference does not prove Metal
delegate compatibility or detection accuracy. Record actual results in the
handoff. YOLOv8 Small performance on the phone has not been measured.

The pinned exporter predates Ultralytics' newer LiteRT export migration. See
[Ultralytics export documentation](https://docs.ultralytics.com/integrations/tflite/)
before changing converter versions or precision.

## Current status

The user exported the checkpoint in Colab and provided the files in
`RoadEye-YOLOv8-Small-RDD/`. All three files have been installed in
`assets/models/`. Source and export SHA-256 hashes match `model.json`.
Input is `[1, 640, 640, 3]`; output is `[1, 8, 8400]`, float32 with no NMS.
Class order: Longitudinal Crack, Transverse Crack, Alligator Crack, Potholes.
Recognition color mappings accept these labels as well as the original codes.
The prior assets are backed up in
`.tooling/model-backup-5c832f5e84da4f768cd1a30b4355e594/`.
Flutter tests and device inference remain unverified in this agent session.
