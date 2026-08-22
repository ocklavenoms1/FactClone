# build.ps1 - regenerates sprites for every asset in assets.json.
#
#   .\art\build.ps1                    # everything
#   .\art\build.ps1 -Only smelter      # one asset
#   .\art\build.ps1 -Calibrate         # camera check only
#   .\art\build.ps1 -Sheet             # also rebuild the verdict sheets
#   .\art\build.ps1 -NoMaterialNorm    # measure the material pass by its absence
#
# Two stages per asset, on purpose:
#   blender  -> 4x master PNG + metadata JSON
#   python   -> premultiplied LANCZOS downsample to the final sprite
# The downsample needs Pillow, which Blender's bundled Python does not have.

param(
    [string]$Only = "",
    [switch]$Sheet,
    [switch]$Calibrate,
    [switch]$NoMaterialNorm,
    [string]$Blender = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
)

# NOT "Stop": Blender writes startup chatter to stderr and, with 2>&1 merging it
# into the pipeline, a Stop preference turns harmless noise into a fatal
# NativeCommandError. Success is detected by markers in stdout instead.
$ErrorActionPreference = "Continue"

$ArtDir   = $PSScriptRoot
$Repo     = Split-Path $ArtDir -Parent
$Template = Join-Path $ArtDir "template.blend"

if (-not (Test-Path $Blender)) { Write-Host "Blender not found at $Blender" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Template)) {
    Write-Host "template.blend missing - rebuild it with:" -ForegroundColor Yellow
    Write-Host "  blender -b -P art\blender\make_template.py"
    exit 1
}

function Blend([string[]]$ScriptArgs) {
    & $Blender -b $Template -P $ScriptArgs[0] -- @($ScriptArgs[1..($ScriptArgs.Length - 1)]) 2>&1
}

if ($Calibrate) {
    $o = Blend @((Join-Path $ArtDir "blender\verify_calibration.py"))
    $o | Select-String "CALIB_RENDERED" | ForEach-Object { Write-Host "  $_" }
    python (Join-Path $ArtDir "tools\downsample.py") --check (Join-Path $ArtDir "renders\_calib.json")
    exit $LASTEXITCODE
}

$manifest = Get-Content (Join-Path $ArtDir "assets.json") -Raw | ConvertFrom-Json
$built = @(); $skipped = @(); $failed = @()

# Hard gate, before anything renders: every real asset must be on the locked
# palette era. Assets from a superseded palette cannot enter the verdict.
$era = python (Join-Path $ArtDir "tools\assert_palette_era.py")
$eraFailed = ($LASTEXITCODE -ne 0)
$era | ForEach-Object { Write-Host $_ }
if ($eraFailed) {
    Write-Host ""
    Write-Host "BUILD FAILED: palette era mismatch (see above)." -ForegroundColor Red
    exit 1
}
Write-Host ""

foreach ($a in $manifest.assets) {
    if ($Only -and $a.name -ne $Only) { continue }
    if ($a.status -eq "test" -and -not $Only) { continue }   # experiments are opt-in

    $srcName = if ($a.source) { $a.source } else { "$($a.name).glb" }
    $src = Join-Path $ArtDir "source\$srcName"
    if (-not (Test-Path $src)) { $skipped += "$($a.name) ($srcName)"; continue }

    $flag = if ($a.status -eq "proxy") { " [PROXY]" } else { "" }
    Write-Host "$($a.name)$flag  footprint=$($a.footprint) fit=$($a.fit)"

    $rargs = @((Join-Path $ArtDir "blender\render_asset.py"), "--name", $a.name)
    if ($NoMaterialNorm) { $rargs += @("--no-material-norm", "1", "--out-suffix", "_nomatnorm") }

    $out = Blend $rargs
    $meta = $out | Select-String "^META "
    if (-not $meta) {
        Write-Host "  FAIL render" -ForegroundColor Red
        $out | Select-String "Error|Traceback|line \d" | Select-Object -Last 4 |
            ForEach-Object { Write-Host "      $_" }
        $failed += $a.name
        continue
    }
    $out | Select-String "^STATE " | ForEach-Object { Write-Host "  $_" }

    $suffix = if ($NoMaterialNorm) { "_nomatnorm" } else { "" }
    $metaPath = Join-Path $ArtDir "sprites\$($a.name)$suffix.json"
    $d = python (Join-Path $ArtDir "tools\downsample.py") $metaPath
    $d | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) { $failed += $a.name; continue }

    # Tripwire: a state that renders identical to another means the transform
    # silently did nothing. Two such failures have shipped through this
    # pipeline already, both caught only by a human looking at pixels.
    $s = python (Join-Path $ArtDir "tools\assert_states.py") $metaPath
    $s | Where-Object { $_ -match "FAIL|ok  |--  " } | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  STATE ASSERTION FAILED for $($a.name)" -ForegroundColor Red
        $failed += $a.name
        continue
    }
    $built += $a.name
}

if ($Sheet) {
    $S = Join-Path $ArtDir "sprites"
    $sheetPy = Join-Path $ArtDir "tools\sheet.py"
    $trio = @("$S\chest.png", "$S\smelter_idle.png", "$S\smelter_smelting.png", "$S\power_pole.png") |
        Where-Object { Test-Path $_ }
    if ($trio) {
        python $sheetPy --out (Join-Path $ArtDir "renders\verdict_truesize.png") --zoom 1 --grid @trio
        python $sheetPy --out (Join-Path $ArtDir "renders\verdict_zoom4.png") --zoom 4 --label @trio
    }
}

Write-Host ""
Write-Host "built:   $($built.Count)  [$($built -join ', ')]"
if ($skipped.Count) { Write-Host "skipped: $($skipped -join ', ')  (no GLB in art\source\)" -ForegroundColor Yellow }
if ($failed.Count)  { Write-Host "FAILED:  $($failed -join ', ')" -ForegroundColor Red; exit 1 }
