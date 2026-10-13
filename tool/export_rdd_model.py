"""Export the requested checkpoint in Colab for RoadEye's existing TFLite loader."""

import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    args = parser.parse_args()
    checkpoint = args.checkpoint.resolve(strict=True)

    from ultralytics import YOLO

    model = YOLO(str(checkpoint))
    if model.task != "detect":
        raise ValueError("RoadEye requires an object-detection checkpoint.")
    names = model.names
    labels = [names[index] for index in range(len(names))]
    if not labels or any(not name.strip() or "\n" in name for name in labels):
        raise ValueError("Checkpoint class names cannot be empty or multiline.")

    exported = Path(model.export(
        format="tflite", imgsz=640, batch=1, half=False,
        int8=False, nms=False, device="cpu",
    ))
    if exported.is_dir():
        candidates = list(exported.glob("*_float32.tflite"))
        if len(candidates) != 1:
            raise ValueError(f"Expected one float32 export, found {candidates}.")
        exported = candidates[0]

    import numpy as np
    import tensorflow as tf

    interpreter = tf.lite.Interpreter(model_path=str(exported))
    interpreter.allocate_tensors()
    inputs = interpreter.get_input_details()
    outputs = interpreter.get_output_details()
    if len(inputs) != 1 or len(outputs) != 1:
        raise ValueError("RoadEye requires one input and one raw detection output.")
    source, result = inputs[0], outputs[0]
    input_shape = source["shape"].tolist()
    output_shape = result["shape"].tolist()
    if input_shape not in ([1, 640, 640, 3], [1, 3, 640, 640]):
        raise ValueError(f"Unsupported input shape: {input_shape}")
    channels = 4 + len(labels)
    if (len(output_shape) != 3 or output_shape[0] != 1
            or channels not in output_shape[1:]
            or max(output_shape[1:]) <= channels):
        raise ValueError(f"Unsupported YOLO output: {output_shape}")
    if source["dtype"] != np.float32 or result["dtype"] != np.float32:
        raise ValueError("RoadEye's buffers require float32 input and output.")
    interpreter.set_tensor(source["index"], np.zeros(input_shape, dtype=np.float32))
    interpreter.invoke()
    if not np.isfinite(interpreter.get_tensor(result["index"])).all():
        raise ValueError("Export produced non-finite values during smoke inference.")

    metadata = {
        "source_checkpoint": checkpoint.name,
        "source_sha256": hashlib.sha256(checkpoint.read_bytes()).hexdigest(),
        "export_sha256": hashlib.sha256(exported.read_bytes()).hexdigest(),
        "input_shape": input_shape,
        "output_shape": output_shape,
        "labels": labels,
        "nms": False,
        "precision": "float32",
    }
    # Always create a new output folder; never overwrite existing model assets.
    destination = Path(tempfile.mkdtemp(prefix="roadeye-yolov8-", dir=Path.cwd()))
    archive = destination / "RoadEye-YOLOv8-Small-RDD.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        bundle.write(exported, "best.tflite")
        bundle.writestr("labels.txt", "\n".join(labels) + "\n")
        bundle.writestr("model.json", json.dumps(metadata, indent=2) + "\n")
    print(f"Validated export: {archive}")
    print("Install all three files into assets/models/, then rebuild RoadEye.")


if __name__ == "__main__":
    main()
