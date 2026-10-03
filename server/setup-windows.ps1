$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Venv = Join-Path $Root ".venv"
$Vendor = Join-Path $Root "vendor"
$Tripo = Join-Path $Vendor "TripoSR"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is required."
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw "Python 3 is required."
}

New-Item -ItemType Directory -Force -Path $Vendor | Out-Null

if (-not (Test-Path $Tripo)) {
    git clone --depth 1 https://github.com/VAST-AI-Research/TripoSR.git $Tripo
}

if (-not (Test-Path $Venv)) {
    py -3.10 -m venv $Venv
}

$Python = Join-Path $Venv "Scripts\python.exe"
$Pip = Join-Path $Venv "Scripts\pip.exe"

& $Python -m pip install --upgrade pip setuptools wheel

# CUDA 12.4 PyTorch wheels. This keeps inference on the NVIDIA GPU.
& $Pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
& $Pip install -r (Join-Path $Tripo "requirements.txt")
& $Pip install -r (Join-Path $Root "requirements-server.txt")

# torchmcubes occasionally installs without CUDA support on Windows.
# TripoSR can still use CPU marching cubes, but try the CUDA-capable source.
try {
    & $Pip uninstall -y torchmcubes
    & $Pip install "git+https://github.com/tatsy/torchmcubes.git"
} catch {
    Write-Warning "torchmcubes CUDA build failed; TripoSR may fall back to CPU marching cubes."
}

Write-Host ""
Write-Host "ScanAnything free 3D engine installed."
Write-Host "Run: powershell -ExecutionPolicy Bypass -File server\start-windows.ps1"
