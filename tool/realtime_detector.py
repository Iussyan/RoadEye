"""Responsive RoadEye webcam/video detection using the existing YOLO checkpoint."""

import argparse
import multiprocessing as mp
from pathlib import Path
from queue import Empty, Full
import sys
import threading
import time


MODEL = Path(__file__).resolve().parents[1] / "YOLOv8_Small_RDD.pt"
COLORS = ((246, 130, 59), (129, 185, 16), (11, 158, 245), (68, 68, 239))


def offer_latest(queue, item):
    """Bound memory; discard a queued frame instead of waiting behind it."""
    try:
        queue.put_nowait(item)
        return
    except Full:
        pass
    try:
        queue.get_nowait()
    except Empty:
        # multiprocessing.Queue's feeder may not have published the item yet.
        return
    try:
        queue.put_nowait(item)
    except Full:
        pass


class LatestFrame:
    def __init__(self):
        self.lock = threading.Lock()
        self.value = None

    def publish(self, value):
        with self.lock:
            self.value = value

    def read(self):
        with self.lock:
            return self.value


def capture_frames(args, latest, stop, errors, finished):
    import cv2

    source = int(args.source) if args.source.isdecimal() else args.source
    capture = cv2.VideoCapture(source)
    try:
        if not capture.isOpened():
            raise RuntimeError(f"Cannot open video source: {args.source}")
        capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        if isinstance(source, int):
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
            capture.set(cv2.CAP_PROP_FPS, args.fps)
        is_file = isinstance(source, str) and Path(source).is_file()
        file_fps = capture.get(cv2.CAP_PROP_FPS)
        period = 1.0 / (file_fps if 0 < file_fps < 1000 else args.fps)
        deadline = time.monotonic()
        sequence = 0
        while not stop.is_set():
            if is_file and stop.wait(max(0, deadline - time.monotonic())):
                break
            ok, frame = capture.read()
            if not ok:
                if not is_file:
                    raise RuntimeError("Video source disconnected or frame read failed.")
                break
            sequence += 1
            latest.publish((sequence, time.monotonic(), frame))
            deadline += period
    except Exception as error:
        errors.append(str(error))
    finally:
        capture.release()
        finished.set()


def inference_worker(args, inputs, outputs, stop):
    """Own the model in a separate process so Python inference cannot block UI."""
    try:
        import torch
        from ultralytics import YOLO

        torch.set_num_threads(args.threads)
        model = YOLO(str(args.model), task="detect")
        outputs.put(("ready", None))
        while not stop.is_set():
            try:
                sequence, captured_at, frame = inputs.get(timeout=0.1)
            except Empty:
                continue
            started = time.monotonic()
            result = model.predict(
                frame, imgsz=args.imgsz, conf=args.conf, iou=args.iou,
                device=args.device, max_det=100, verbose=False,
            )[0]
            boxes = []
            if result.boxes is not None:
                for row in result.boxes.data.cpu().tolist():
                    x1, y1, x2, y2, confidence, class_id = row[:6]
                    class_id = int(class_id)
                    boxes.append((x1, y1, x2, y2, confidence,
                                  class_id, result.names[class_id]))
            offer_latest(outputs, ("result", (
                sequence, captured_at, time.monotonic() - started, boxes,
            )))
    except Exception as error:
        # Error delivery must not be dropped behind an old prediction.
        while not stop.is_set():
            try:
                outputs.put(("error", str(error)), timeout=0.1)
                break
            except Full:
                continue


def draw(frame, result, args, display_fps, status):
    import cv2

    canvas = frame.copy()
    age = time.monotonic() - result[1] if result else float("inf")
    inference_ms = result[2] * 1000 if result else 0
    if result and age <= args.max_box_age:
        height, width = canvas.shape[:2]
        for x1, y1, x2, y2, confidence, class_id, name in result[3]:
            x1, x2 = [max(0, min(width - 1, int(x))) for x in (x1, x2)]
            y1, y2 = [max(0, min(height - 1, int(y))) for y in (y1, y2)]
            color = COLORS[class_id % len(COLORS)]
            cv2.rectangle(canvas, (x1, y1), (x2, y2), color, 2)
            cv2.putText(canvas, f"{name} {confidence:.0%}",
                        (x1, max(48, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX,
                        0.5, color, 2, cv2.LINE_AA)
    if result:
        status = f"Inference {inference_ms:.0f} ms | result age {age:.1f}s"
        if age > args.max_box_age:
            status += " | boxes expired"
    cv2.rectangle(canvas, (0, 0), (canvas.shape[1], 40), (20, 25, 23), -1)
    cv2.putText(canvas, f"Feed {display_fps:.0f} FPS | {status}", (8, 25),
                cv2.FONT_HERSHEY_SIMPLEX, 0.48, (215, 239, 154), 1, cv2.LINE_AA)
    return canvas


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, default=MODEL)
    parser.add_argument("--source", default="0", help="Camera index, video path, or stream URL")
    parser.add_argument("--device", default="cpu", help="cpu, CUDA index (0), or mps")
    parser.add_argument("--imgsz", type=int, default=416)
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--iou", type=float, default=0.45)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--threads", type=int, default=2, help="CPU inference threads")
    parser.add_argument("--max-box-age", type=float, default=1.5,
                        help="Hide predictions older than this many seconds")
    args = parser.parse_args()
    if not args.model.is_file():
        parser.error(f"Model not found: {args.model}")
    if not 0 < args.conf <= 1 or not 0 < args.iou <= 1:
        parser.error("--conf and --iou must be in (0, 1]")
    if min(args.imgsz, args.width, args.height, args.fps, args.threads, args.max_box_age) <= 0:
        parser.error("Image dimensions, FPS, threads, and box age must be positive")
    return args


def main():
    args = parse_args()
    try:
        import cv2
    except ImportError:
        print("Install dependencies: python -m pip install -r requirements-realtime.txt",
              file=sys.stderr)
        return 1
    cv2.setNumThreads(1)
    context = mp.get_context("spawn")
    inputs, outputs = context.Queue(maxsize=1), context.Queue(maxsize=2)
    stop = context.Event()
    finished = threading.Event()
    latest, errors = LatestFrame(), []
    worker = context.Process(target=inference_worker,
                             args=(args, inputs, outputs, stop), daemon=True)
    camera = threading.Thread(target=capture_frames,
                              args=(args, latest, stop, errors, finished), daemon=True)
    worker.start()
    camera.start()
    window = "RoadEye - Q or Esc to quit"
    last_sequence, last_display, display_fps = -1, time.monotonic(), 0.0
    result, ready = None, False
    exit_code = 0
    try:
        cv2.namedWindow(window, cv2.WINDOW_NORMAL)
        while True:
            while True:
                try:
                    kind, value = outputs.get_nowait()
                except Empty:
                    break
                if kind == "error":
                    raise RuntimeError(f"Model inference failed: {value}")
                if kind == "ready":
                    ready = True
                elif kind == "result":
                    result = value
            if errors:
                raise RuntimeError(errors[0])
            if not worker.is_alive():
                raise RuntimeError("Inference process exited unexpectedly.")
            packet = latest.read()
            if packet is not None and packet[0] != last_sequence:
                sequence, _, frame = packet
                last_sequence = sequence
                if ready:
                    offer_latest(inputs, packet)
                now = time.monotonic()
                display_fps = 0.9 * display_fps + 0.1 / max(now - last_display, 1e-6)
                last_display = now
                cv2.imshow(window, draw(frame, result, args, display_fps,
                                        "Waiting for prediction" if ready else "Loading model..."))
            if cv2.waitKey(1) & 0xFF in (27, ord("q")):
                break
            if cv2.getWindowProperty(window, cv2.WND_PROP_VISIBLE) < 1:
                break
            if finished.is_set() and (packet is None or packet[0] == last_sequence):
                break
            time.sleep(0.001)
    except KeyboardInterrupt:
        pass
    except Exception as error:
        print(f"RoadEye: {error}", file=sys.stderr)
        exit_code = 1
    finally:
        stop.set()
        worker.join(timeout=3)
        if worker.is_alive():
            worker.terminate()
            worker.join(timeout=2)
        camera.join(timeout=2)
        cv2.destroyAllWindows()
        for queue in (inputs, outputs):
            queue.cancel_join_thread()
            queue.close()
    return exit_code


if __name__ == "__main__":
    mp.freeze_support()
    sys.exit(main())
