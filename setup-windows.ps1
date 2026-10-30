# First-run setup for Windows: populate the offline pre-install store, then build & start.
# Requires Docker Desktop for Windows and PowerShell 5.1+.
# Run from the repo root:  powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
# Mirrors setup-linux.sh / setup-mac.sh (kept intentionally duplicated).

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot

# 1. Locate the compose file: $env:COMPOSE_FILE override wins, then a parent-level
#    docker-compose.yaml (workspace layout), else the repo's example. The example's
#    paths (./opencode, ./pre-install) are relative to the parent dir, so pass
#    -ProjectDirectory there when it is used in place.
$ProjectDir = $null
if ($env:COMPOSE_FILE) {
    $ComposeFile = (Resolve-Path $env:COMPOSE_FILE).Path
    Write-Host "==> compose file: $ComposeFile (from `$env:COMPOSE_FILE)"
} elseif (Test-Path (Join-Path $RepoRoot "..\docker-compose.yaml")) {
    $ComposeFile = (Resolve-Path (Join-Path $RepoRoot "..\docker-compose.yaml")).Path
    Write-Host "==> compose file: parent docker-compose.yaml"
} else {
    $ComposeFile = Join-Path $RepoRoot "docker-compose.example.yaml"
    $ProjectDir = (Resolve-Path (Join-Path $RepoRoot "..")).Path
    Write-Host "==> compose file: repo docker-compose.example.yaml (project dir: $ProjectDir)"
}

# 2. Docker + compose v2 available?
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker not found. Install Docker Desktop for Windows: https://www.docker.com/products/docker-desktop/"
    exit 1
}
docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "'docker compose' v2 plugin not available. Update Docker Desktop to a current version."
    exit 1
}

# 3. CRLF guard (best-effort, non-fatal): autocrlf corruption breaks sh scripts.
#    (.gitattributes enforces LF for *.sh; this catches hand-edited copies.)
$PopulateScript = Join-Path $RepoRoot "populate-preinstall.sh"
if ((Test-Path $PopulateScript) -and ((Get-Content -Raw $PopulateScript) -match "`r")) {
    Write-Warning "CRLF line endings detected in populate-preinstall.sh."
    Write-Warning "Fix with: git config core.autocrlf false ; git checkout -- populate-preinstall.sh"
}

# 4. Populate the offline store in a throwaway stock node container
#    (works before the custom image exists; re-runs fetch only what is missing).
Write-Host "==> populating pre-install store (compose profile: tools)"
if ($ProjectDir) {
    docker compose -f $ComposeFile --project-directory $ProjectDir --profile tools run --rm populate
} else {
    docker compose -f $ComposeFile --profile tools run --rm populate
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 5. Build & start.
Write-Host "==> building and starting"
if ($ProjectDir) {
    docker compose -f $ComposeFile --project-directory $ProjectDir up -d --build
} else {
    docker compose -f $ComposeFile up -d --build
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 6. Done.
Write-Host ""
Write-Host "==> done. Store: $RepoRoot\pre-install (gitignored, never committed or pushed)."
Write-Host "    Re-populate later: re-run this script (fetches only what is missing)."
Write-Host "    Next: open http://localhost:4096 once the build finishes."
