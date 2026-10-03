$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $Root ".venv\Scripts\python.exe"

if (-not (Test-Path $Python)) {
    throw "Run server/setup-windows.ps1 first."
}

$env:TRIPOSR_MC_RESOLUTION = if ($env:TRIPOSR_MC_RESOLUTION) { $env:TRIPOSR_MC_RESOLUTION } else { "384" }
$env:TRIPOSR_CHUNK_SIZE = if ($env:TRIPOSR_CHUNK_SIZE) { $env:TRIPOSR_CHUNK_SIZE } else { "4096" }
$env:SCANANYTHING_PORT = if ($env:SCANANYTHING_PORT) { $env:SCANANYTHING_PORT } else { "8787" }

& $Python (Join-Path $Root "triposr_server.py")
