#requires -Version 5.1
<#
.SYNOPSIS
    Boot smoke: start the real game, run a fixed number of frames, quit, and
    judge the log.

.DESCRIPTION
    The one check in this repo that exercises the WHOLE game rather than one
    function. See docs/boot-smoke.md for the ritual, the pass criteria and the
    measurements behind them. Read that before changing anything here.

    Not a suite entry: it needs a window, and the headless runner calls its
    suites synchronously inside _ready with no window and no frame yield.

.PARAMETER Frames
    Frames to run before quitting. Default 120 = 2.00 s of simulated time at
    the forced 60 fps, which is exactly 40 TickSystem ticks.

.PARAMETER LogPath
    Where to write the run log. Defaults to a temp file.

.PARAMETER KeepLog
    Print the whole log at the end even when the run passes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\boot_smoke.ps1
#>
[CmdletBinding()]
param(
    [int]$Frames = 120,
    [string]$LogPath = "",
    [switch]$KeepLog
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $PSScriptRoot "Godot_v4.6.3-stable_win64_console.exe"

if (-not (Test-Path $godot)) {
    Write-Host "BOOT SMOKE: FAIL - godot console binary not found at $godot" -ForegroundColor Red
    exit 2
}
if ($LogPath -eq "") {
    $LogPath = Join-Path ([System.IO.Path]::GetTempPath()) "factclone_boot_smoke.log"
}

# --- the run -------------------------------------------------------------
#
# --position 6000,6000  window opens off-screen. A real window is required:
#                       the dummy rasterizer under --headless renders nothing,
#                       and --write-movie HARD-CRASHES under --headless
#                       (signal 11). Never combine those two.
# --fixed-fps 60        pins delta to 1/60 and drops real-time sync, so the run
#                       is both fast and deterministic in tick count. See
#                       docs/boot-smoke.md, "trap 1".
# --quit-after N        exit after N frames. Cleanly. Even after a Parse Error
#                       - which is why the exit code is the weakest of the five
#                       criteria below and not the only one.

$args = @(
    "--path", $repo,
    "--position", "6000,6000",
    "--fixed-fps", "60",
    "--quit-after", "$Frames"
)

Write-Host "BOOT SMOKE: $godot $($args -join ' ')"
Write-Host "BOOT SMOKE: log -> $LogPath"

$proc = Start-Process -FilePath $godot -ArgumentList $args -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput "$LogPath.out" -RedirectStandardError "$LogPath.err"
$exit = $proc.ExitCode

# One log, stdout then stderr, so the greps below see everything the run said.
$out = ""
$err = ""
if (Test-Path "$LogPath.out") { $out = Get-Content "$LogPath.out" -Raw }
if (Test-Path "$LogPath.err") { $err = Get-Content "$LogPath.err" -Raw }
Set-Content -Path $LogPath -Value ($out + $err) -Encoding utf8
Remove-Item "$LogPath.out", "$LogPath.err" -ErrorAction SilentlyContinue

$lines = @()
if (Test-Path $LogPath) { $lines = @(Get-Content $LogPath) }

function Count-Matching([string]$needle) {
    return @($lines | Where-Object { $_ -like "*$needle*" }).Count
}

$parseErrors  = Count-Matching "Parse Error"
$scriptErrors = Count-Matching "SCRIPT ERROR"
$engineErrors = Count-Matching "ERROR"
$warnings     = Count-Matching "WARNING"
$banner       = Count-Matching "Godot Engine v"

# --- the five criteria ---------------------------------------------------
#
# All five must hold. Each one is here because a measured failure mode gets
# past the others - docs/boot-smoke.md records which.

$failures = @()
if ($exit -ne 0)      { $failures += "process exit code was $exit, expected 0" }
if ($banner -lt 1)    { $failures += "the log has no engine banner - the run produced no output at all, so nothing was actually verified" }
if ($parseErrors -gt 0)  { $failures += "$parseErrors line(s) matched 'Parse Error'" }
if ($scriptErrors -gt 0) { $failures += "$scriptErrors line(s) matched 'SCRIPT ERROR'" }
if ($engineErrors -gt 0) { $failures += "$engineErrors line(s) matched 'ERROR' (includes engine-level failures that are neither a Parse Error nor a SCRIPT ERROR)" }

Write-Host ""
Write-Host "  exit code      : $exit"
Write-Host "  engine banner  : $banner"
Write-Host "  Parse Error    : $parseErrors"
Write-Host "  SCRIPT ERROR   : $scriptErrors"
Write-Host "  ERROR          : $engineErrors"
Write-Host "  WARNING        : $warnings   (reported, not a failure - see docs/boot-smoke.md)"
Write-Host ""

if ($failures.Count -eq 0) {
    Write-Host "BOOT SMOKE: PASS ($Frames frames)" -ForegroundColor Green
    if ($KeepLog) {
        Write-Host "--- log ---"
        $lines | ForEach-Object { Write-Host $_ }
    }
    exit 0
}

Write-Host "BOOT SMOKE: FAIL ($Frames frames)" -ForegroundColor Red
foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
Write-Host "--- log ---"
$lines | ForEach-Object { Write-Host $_ }
exit 1
