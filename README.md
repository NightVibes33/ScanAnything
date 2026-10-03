# ScanAnything

ScanAnything is now a **one-photo 3D Dex**.

The old multi-photo scanner, photogrammetry modes, Gaussian splats, room scanner,
LiDAR modes, and editor-style workflow are gone from the product.

## What the app does

1. Open **Capture**.
2. Take one photo or choose one photo.
3. ScanAnything removes the background and sends that one selected image to your
   own 3D engine.
4. A complete 3D object is generated.
5. The result is registered as a numbered Dex entry such as `#0001`.
6. Browse the collection grid, search it, open a specimen, rotate the model,
   rename it, and export the GLB.

The UI is deliberately a collection/Dex interface rather than an AI editor:
red hardware-inspired shell, numbered entries, specimen cards, capture screen,
detail records, and search.

## Open-source Pokédex UI base

The collection/grid/detail direction is based on the MIT-licensed
`brillcp/PocketDex` SwiftUI project by Viktor Gidlöf. ScanAnything does **not**
bundle Pokémon artwork, names, sprites, PokeAPI data, logos, or other franchise
assets. The Pokédex-style interaction model is reused for the user's own scanned
real-world objects.

## Free 3D generation for the developer build

There is **no paid model API** in this branch.

The included server uses the official open-source
`VAST-AI-Research/TripoSR` model locally. TripoSR is MIT licensed, accepts one
image, automatically removes the background, and the upstream project documents
about 6 GB VRAM for one image.

The server keeps the model resident on the GPU and runs jobs one at a time.

### Windows setup

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File server\setup-windows.ps1
powershell -ExecutionPolicy Bypass -File server\start-windows.ps1
```

Then open:

```
http://127.0.0.1:8787/health
```

In ScanAnything Settings set **Your 3D Engine** to:

```
http://<PC-LAN-OR-TAILSCALE-IP>:8787/generate
```

No FAL key, Replicate key, paid inference subscription, or per-generation fee
is required.

## Quality defaults

The local server currently uses:

- automatic foreground/background isolation
- TripoSR single-image reconstruction
- CUDA when an NVIDIA GPU is available
- 384 marching-cubes resolution
- automatic 320/256 fallback if the GPU runs out of memory
- GLB output stored locally in the app's Dex library

## iOS build

```bash
xcodebuild \
  -project ScanAnything.xcodeproj \
  -scheme ScanAnything \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

GitHub Actions builds and packages an unsigned IPA automatically.
