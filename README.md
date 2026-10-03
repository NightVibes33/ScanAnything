# ScanAnything

ScanAnything is a one-photo 3D collection app.

The old photogrammetry / Gaussian-splat scanner has been removed from the app product. The primary flow is now:

1. Take one photo or choose one photo.
2. Send only that selected image to the configured generation service.
3. Generate a textured 3D asset with Hunyuan 3D v3.1 Pro.
4. Download the GLB (and USDZ when the provider returns it).
5. Register the finished object as a numbered local Dex entry.
6. Browse, rotate, search, rename, export, or open the object in AR when USDZ is available.

## UI

The app is a real collection/Dex interface, not a 3D editor. It uses a red hardware-inspired shell, numbered specimen grid, detail records, local search, and a dedicated one-photo capture screen.

The grid/detail structure is inspired by the open-source PocketDex project by Viktor Gidlöf (MIT). No Pokémon artwork, sprites, names, data, logos, or other franchise assets are bundled.

## 3D backend

The repository includes a Vercel-compatible API under `api/`.

The API uses:

- `fal-ai/hunyuan-3d/v3.1/pro/image-to-3d`
- PBR enabled
- 1,000,000 target faces
- queue submission + polling, so the iOS app does not keep a long HTTP request open

Set this environment variable on the server:

```
FAL_KEY=<your fal server key>
```

Deploy the repository as a Vercel project, then set the iOS app's 3D Engine endpoint to:

```
https://<your-domain>/api/generate
```

For production/App Store builds, set `SCANANYTHING_API_BASE_URL` in the generated Info.plist/build settings instead of asking users to configure it.

The provider credential must stay on the server. Do not embed `FAL_KEY` in the IPA.

## Build

The iOS app targets iOS 18+ and has no third-party Swift package dependency.

```bash
xcodebuild \
  -project ScanAnything.xcodeproj \
  -scheme ScanAnything \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

GitHub Actions also builds and packages an unsigned IPA.
