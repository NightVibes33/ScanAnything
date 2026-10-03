# Free self-hosted 3D engine

This is the default development backend for ScanAnything.

It uses the official open-source TripoSR model. TripoSR is MIT licensed and its
README states that a single-image run uses about 6 GB of VRAM, so a consumer
NVIDIA RTX GPU can run it locally without per-generation API fees.

## Windows

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File server\setup-windows.ps1
powershell -ExecutionPolicy Bypass -File server\start-windows.ps1
```

Health check:

```
http://127.0.0.1:8787/health
```

The iPhone app endpoint is:

```
http://<your-PC-IP>:8787/generate
```

For access over Tailscale, use the PC's Tailscale address/hostname. If you expose
the local service with Tailscale HTTPS, use that HTTPS URL instead.

The server loads TripoSR once and keeps it resident. Jobs run one at a time to
avoid consumer-GPU VRAM spikes. Background removal is automatic. The default
marching-cubes resolution is 384 with automatic fallback to 320 or 256 if CUDA
runs out of memory.

No paid inference API or model-provider key is required.
