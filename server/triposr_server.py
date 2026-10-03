from __future__ import annotations

import base64
import io
import os
import sys
import threading
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import numpy as np
import rembg
import torch
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel
from PIL import Image

ROOT = Path(__file__).resolve().parent
TRIPOSR_ROOT = ROOT / "vendor" / "TripoSR"
OUTPUT_ROOT = ROOT / "outputs"
OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)

if not TRIPOSR_ROOT.exists():
    raise RuntimeError(
        "TripoSR is not installed. Run server/setup-windows.ps1 first."
    )

sys.path.insert(0, str(TRIPOSR_ROOT))

from tsr.system import TSR  # noqa: E402
from tsr.utils import remove_background, resize_foreground  # noqa: E402


class GenerateRequest(BaseModel):
    imageDataURI: str


@dataclass
class Job:
    status: Literal["queued", "running", "completed", "failed"] = "queued"
    error: str | None = None
    glb_path: Path | None = None
    thumbnail_path: Path | None = None


app = FastAPI(title="ScanAnything Free 3D Engine", version="1.0")
jobs: dict[str, Job] = {}
jobs_lock = threading.Lock()
gpu_lock = threading.Lock()

device = "cuda:0" if torch.cuda.is_available() else "cpu"
model = TSR.from_pretrained(
    "stabilityai/TripoSR",
    config_name="config.yaml",
    weight_name="model.ckpt",
)
model.renderer.set_chunk_size(int(os.environ.get("TRIPOSR_CHUNK_SIZE", "4096")))
model.to(device)
rembg_session = rembg.new_session()


def decode_image(data_uri: str) -> Image.Image:
    if "," not in data_uri or not data_uri.startswith("data:image/"):
        raise ValueError("imageDataURI must be a data:image URI.")
    payload = data_uri.split(",", 1)[1]
    data = base64.b64decode(payload, validate=True)
    return Image.open(io.BytesIO(data)).convert("RGBA")


def prepared_image(image: Image.Image) -> Image.Image:
    foreground = remove_background(image, rembg_session)
    foreground = resize_foreground(foreground, 0.88)
    rgba = np.array(foreground).astype(np.float32) / 255.0
    rgb = rgba[:, :, :3] * rgba[:, :, 3:4] + (1 - rgba[:, :, 3:4]) * 0.5
    return Image.fromarray((rgb * 255.0).astype(np.uint8))


def extract_with_quality(scene_codes):
    requested = int(os.environ.get("TRIPOSR_MC_RESOLUTION", "384"))
    candidates = [requested]
    for fallback in (320, 256):
        if fallback not in candidates and fallback < requested:
            candidates.append(fallback)

    last_error: Exception | None = None
    for resolution in candidates:
        try:
            with torch.no_grad():
                return model.extract_mesh(
                    scene_codes,
                    True,
                    resolution=resolution,
                )[0]
        except torch.OutOfMemoryError as error:
            last_error = error
            if torch.cuda.is_available():
                torch.cuda.empty_cache()

    if last_error:
        raise last_error
    raise RuntimeError("Mesh extraction failed.")


def generate_job(job_id: str, data_uri: str) -> None:
    job_dir = OUTPUT_ROOT / job_id
    job_dir.mkdir(parents=True, exist_ok=True)

    with jobs_lock:
        jobs[job_id].status = "running"

    try:
        image = decode_image(data_uri)
        image = prepared_image(image)
        thumbnail_path = job_dir / "preview.png"
        image.save(thumbnail_path)

        # One generation at a time keeps the local GPU deterministic and avoids
        # concurrent CUDA OOMs on consumer cards.
        with gpu_lock:
            with torch.no_grad():
                scene_codes = model([image], device=device)
                mesh = extract_with_quality(scene_codes)

            glb_path = job_dir / "model.glb"
            mesh.export(glb_path)

        with jobs_lock:
            job = jobs[job_id]
            job.status = "completed"
            job.glb_path = glb_path
            job.thumbnail_path = thumbnail_path
    except Exception as error:
        with jobs_lock:
            job = jobs[job_id]
            job.status = "failed"
            job.error = str(error)


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "engine": "TripoSR",
        "device": device,
        "cuda": torch.cuda.is_available(),
        "gpu": (
            torch.cuda.get_device_name(0)
            if torch.cuda.is_available()
            else "CPU"
        ),
    }


@app.post("/generate")
def submit(request: GenerateRequest) -> dict:
    if len(request.imageDataURI) > 5_000_000:
        raise HTTPException(status_code=413, detail="Image payload is too large.")

    job_id = uuid.uuid4().hex
    with jobs_lock:
        jobs[job_id] = Job()

    thread = threading.Thread(
        target=generate_job,
        args=(job_id, request.imageDataURI),
        daemon=True,
    )
    thread.start()
    return {"id": job_id, "status": "queued"}


@app.get("/generate")
def status(id: str, request: Request) -> dict:
    with jobs_lock:
        job = jobs.get(id)
        if job is None:
            raise HTTPException(status_code=404, detail="Unknown generation id.")

        if job.status == "failed":
            return {"status": "failed", "error": job.error}

        if job.status != "completed":
            return {"status": job.status}

    base = str(request.base_url).rstrip("/")
    return {
        "status": "completed",
        "thumbnailURL": f"{base}/files/{id}/preview.png",
        "glbURL": f"{base}/files/{id}/model.glb",
        "usdzURL": None,
    }


@app.get("/files/{job_id}/{filename}")
def files(job_id: str, filename: str):
    if filename not in {"preview.png", "model.glb"}:
        raise HTTPException(status_code=404)
    path = OUTPUT_ROOT / job_id / filename
    if not path.exists():
        raise HTTPException(status_code=404)
    media = "model/gltf-binary" if filename.endswith(".glb") else "image/png"
    return FileResponse(path, media_type=media)


if __name__ == "__main__":
    uvicorn.run(
        app,
        host=os.environ.get("SCANANYTHING_HOST", "0.0.0.0"),
        port=int(os.environ.get("SCANANYTHING_PORT", "8787")),
    )
