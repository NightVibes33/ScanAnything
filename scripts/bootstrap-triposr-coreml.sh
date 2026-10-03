#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/ScanAnything/Models/TripoSRCoreML"

if [[ -d "$DEST/ImageToTriplane.mlpackage" && -d "$DEST/NeRFQuery.mlpackage" ]]; then
  echo "TripoSR Core ML models already present."
  exit 0
fi

python3 -m pip install --user --quiet "huggingface_hub>=0.27,<1.0"

python3 - <<'PY'
from pathlib import Path
from huggingface_hub import snapshot_download

dest = Path("ScanAnything/Models/TripoSRCoreML")
dest.mkdir(parents=True, exist_ok=True)

snapshot_download(
    repo_id="mickeyvanolst/triposr-coreml",
    revision="1426b49",
    allow_patterns=[
        "ImageToTriplane.mlpackage/**",
        "NeRFQuery.mlpackage/**",
        "LICENSE",
        "README.md",
    ],
    local_dir=str(dest),
)
PY

test -f "$DEST/ImageToTriplane.mlpackage/Manifest.json"
test -f "$DEST/NeRFQuery.mlpackage/Manifest.json"

echo "TripoSR Core ML models ready in $DEST"
