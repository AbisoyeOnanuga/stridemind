Param(
  [string]$DeviceId = "",
  [switch]$VerboseRun
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$definesPath = Join-Path $projectRoot "config\dart_defines.local.json"

if (-not (Test-Path $definesPath)) {
  Write-Host "Missing config file: $definesPath" -ForegroundColor Yellow
  Write-Host "Create it from config\dart_defines.local.example.json" -ForegroundColor Yellow
  exit 1
}

$args = @(
  "run",
  "--dart-define-from-file=$definesPath"
)

if ($DeviceId -ne "") {
  $args += "-d"
  $args += $DeviceId
}

if ($VerboseRun) {
  $args += "--verbose"
}

Write-Host "Running: flutter $($args -join ' ')" -ForegroundColor Cyan
flutter @args
