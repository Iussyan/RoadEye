# Python real-time road-damage detection

This standalone desktop tool uses the existing root `YOLOv8_Small_RDD.pt`
checkpoint. It detects the checkpoint's road-damage classes, not arbitrary
objects. It does not change the Flutter app or require exporting the model.

Use Python 3.10-3.12. From the repository root in PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-realtime.txt
.\.venv\Scripts\python.exe tool/realtime_detector.py
```

The default source is webcam 0. Press **Q**, **Esc**, or close the window to quit.
Labels and confidence scores appear beside colored bounding boxes. Only one
application should use the camera at a time.

```powershell
# Different webcam
.\.venv\Scripts\python.exe tool/realtime_detector.py --source 1
# Play a local recording at its original frame rate
.\.venv\Scripts\python.exe tool/realtime_detector.py --source "C:\videos\road.mp4"
# Lower inference resolution on a slower CPU
.\.venv\Scripts\python.exe tool/realtime_detector.py --imgsz 320 --threads 2
# Higher resolution / confidence threshold
.\.venv\Scripts\python.exe tool/realtime_detector.py --imgsz 640 --conf 0.40
# NVIDIA GPU, if a CUDA-enabled PyTorch installation is available
.\.venv\Scripts\python.exe tool/realtime_detector.py --device 0
```

Capture runs on a background thread; inference owns the model in a separate
process; the main thread displays the newest captured frame. Bounded queues
drop pending frames rather than building up a video backlog. CPU inference
defaults to two threads to leave capacity for capture and display.

The feed FPS and inference duration are separate measurements. A slow model
updates boxes less frequently while the video keeps advancing. Boxes use the
latest completed prediction and can lag moving objects; this is not tracking.
Predictions older than 1.5 seconds are hidden. Adjust `--max-box-age` if needed;
inference slower than that limit may require a lower `--imgsz` or a faster device.
Actual feed smoothness depends on camera, decoding, CPU/GPU load, and hardware;
30 FPS is a camera request, not a guaranteed result. Lower resolution trades
small-crack sensitivity for speed.

If the model cannot load or inference fails, the program prints the error and
exits instead of presenting the failure as zero detections. A camera read
failure is reported; local-video EOF exits normally. Network-stream buffering
also depends on the capture backend. No images or recordings are saved.

Validation still required on the target machine: open the webcam, inspect a
known road-damage scene, compare box alignment, observe feed FPS while inference
is active, test disconnect and exit, and tune inference resolution. Dependency
installation and actual camera/model inference have not been verified here.

Run the dependency-free frame-handoff regression tests with:

```powershell
python -m unittest discover -s tool -p test_realtime_detector.py
```

API reference: [Ultralytics prediction](https://docs.ultralytics.com/modes/predict/).
