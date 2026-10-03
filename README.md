# ScanAnything

ScanAnything is a **one-photo, fully on-device 3D Dex for iPhone**.

The previous multi-photo scanner, photogrammetry modes, Gaussian splats, room
scanner, LiDAR workflow, PC backend, and hosted inference API are not part of
the product anymore.

## Product flow

1. Open **Capture**.
2. Take one photo or choose one photo.
3. Apple Vision isolates the subject locally.
4. TripoSR runs through Core ML on the iPhone.
5. The neural field is queried locally and converted to a mesh with marching
   cubes.
6. SceneKit exports the finished mesh to USDZ locally.
7. The result is registered as a numbered Dex entry such as `#0001`.

No photo is sent to a generation server.

## On-device model

The app bundles the MIT-licensed Core ML conversion of TripoSR from
`mickeyvanolst/triposr-coreml`.

The conversion contains:

- `ImageToTriplane.mlpackage` — fp16 Core ML MLProgram, about 839 MB
- `NeRFQuery.mlpackage` — Core ML neural-field query model
- 512×512 RGB input
- triplane output `[1,3,40,64,64]`
- fixed query chunks of 262,144 xyz samples

The encoder is allowed to use the Apple Neural Engine/GPU/CPU. The published
conversion identifies CPU as the fastest execution target for the tiny NeRF
query model, so ScanAnything keeps that stage on CPU while the encoder uses all
available Core ML compute units.

## Device quality

Mesh-field resolution is selected from physical memory:

- 8 GB-class and newer devices: 256³
- 6 GB-class devices: 224³
- lower-memory supported devices: 192³

The target product range is modern iPhones, including iPhone 14-class hardware
and newer. The app remains one-photo-first on every supported device.

## Model bootstrap

The ~839 MB model is not committed to Git. Build machines fetch the pinned Core
ML model before compiling:

```bash
bash scripts/bootstrap-triposr-coreml.sh
```

The GitHub Actions workflow caches the model between builds and Xcode compiles
the model packages into the IPA. The shipped app therefore has no inference
server dependency.

## Dex UI

The collection/grid/detail direction is based on the MIT-licensed
`brillcp/PocketDex` SwiftUI project by Viktor Gidlöf. ScanAnything uses the Dex
interaction model for the user's own real-world 3D entries and does not bundle
Pokémon artwork, sprites, names, PokeAPI data, or franchise logos.

## Build

```bash
bash scripts/bootstrap-triposr-coreml.sh

xcodebuild \
  -project ScanAnything.xcodeproj \
  -scheme ScanAnything \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

GitHub Actions builds and packages the self-contained unsigned IPA.
