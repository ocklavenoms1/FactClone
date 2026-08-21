# build_sprites.ps1 — renders every asset in assets.json through the locked
# template. This is the one command that regenerates the whole sprite set.
#
#   .\art\build_sprites.ps1                 # everything in the manifest
#   .\art\build_sprites.ps1 -Only chest     # one asset
#   .\art\build_sprites.ps1 -Sheet          # also rebuild the contact sheet
#
# Missing source GLBs are reported and skipped, not treated as failures — the
# manifest is allowed to run ahead of what has been generated in Tripo.

param(
    [string]$Only = "",
    [switch]$Sheet,
    [string]$Blender = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
)

# Deliberately NOT "Stop": Blender writes startup chatter (and any installed
# add-on's logging) to stderr, and with 2>&1 merging that into the pipeline a
# Stop preference turns harmless noise into a terminating NativeCommandError.
# Failures here are detected by checking for the success marker in stdout.
$ErrorActionPreference = "Continue"
$ArtDir   = $PSScriptRoot
$Repo     = Split-Path $ArtDir -Parent
$Template = Join-Path $ArtDir "template.blend"
$Render   = Join-Path $ArtDir "blender\render_asset.py"
$Animate  = Join-Path $ArtDir "blender\render_animated.py"
$Source   = Join-Path $ArtDir "source"
$Sprites  = Join-Path $ArtDir "sprites"

if (-not (Test-Path $Blender)) {
    Write-Host "Blender not found at $Blender" -ForegroundColor Red; exit 1
}
if (-not (Test-Path $Template)) {
    Write-Host "template.blend missing. Build it with:" -ForegroundColor Red
    Write-Host "  blender -b -P art\blender\build_template.py"
    exit 1
}

$manifest = Get-Content (Join-Path $ArtDir "assets.json") -Raw | ConvertFrom-Json
$built = @(); $skipped = @()

function Invoke-Render($argList, $label) {
    $out = & $Blender -b $Template -P $Render -- @argList 2>&1
    $line = $out | Select-String "SPRITE:"
    if ($line) { Write-Host "  ok  $label"; return $true }
    Write-Host "  FAIL $label" -ForegroundColor Red
    $out | Select-String "Error|line \d" | Select-Object -Last 4 | ForEach-Object { Write-Host "      $_" }
    return $false
}

foreach ($a in $manifest.assets) {
    if ($Only -and $a.name -ne $Only) { continue }
    $glb = Join-Path $Source "$($a.name).glb"
    if (-not (Test-Path $glb)) { $skipped += $a.name; continue }

    Write-Host "$($a.name) [$($a.footprint)x$($a.footprint)]"
    $base = @("--glb", $glb, "--name", $a.name,
              "--footprint", $a.footprint, "--inset", $a.inset)
    if ($a.max_height -gt 0) { $base += @("--max-height", $a.max_height) }

    # Empty-string sentinel, not $null: assigning @($null) unrolls to plain
    # $null, and `foreach ($x in $null)` iterates zero times — which silently
    # skips every asset that has no states and no rotations.
    $yaws = @($a.yaws); if ($yaws.Count -eq 0) { $yaws = @("") }
    $states = @($a.states); if ($states.Count -eq 0) { $states = @("") }

    foreach ($y in $yaws) {
        foreach ($st in $states) {
            # NB: not $args — that is a read-only automatic variable in PowerShell
            # and assigning to it fails silently enough to look like a no-op.
            $rargs = $base.Clone()
            $sfx = ""
            if ($st -ne "") {
                $sfx += "_$st"
                $hook = Join-Path $ArtDir "blender\states\$($a.name)_$st.py"
                if (Test-Path $hook) { $rargs += @("--extra-py", $hook) }
            }
            if ($y -ne "") { $sfx += "_d$y"; $rargs += @("--yaw", $y) }
            if ($sfx) { $rargs += @("--suffix", $sfx) }
            if (Invoke-Render $rargs "$($a.name)$sfx") { $built += "$($a.name)$sfx" }
        }
    }
}

foreach ($an in $manifest.animated) {
    if ($Only -and $an.name -ne $Only) { continue }
    $body = Join-Path $Source $an.body
    $part = Join-Path $Source $an.part
    if (-not (Test-Path $body) -or -not (Test-Path $part)) { $skipped += $an.name; continue }

    Write-Host "$($an.name) [animated, $($an.frames.Count) frames]"
    $frames = ($an.frames -join ",")
    $out = & $Blender -b $Template -P $Animate -- `
        --body $body --part $part --name $an.name `
        --footprint $an.footprint --canvas-tiles $an.canvas_tiles --frames $frames 2>&1
    if ($out | Select-String "ANIM_DONE") {
        Write-Host "  ok  $($an.name) x$($an.frames.Count)"
        $built += "$($an.name) x$($an.frames.Count)"
    } else {
        Write-Host "  FAIL $($an.name)" -ForegroundColor Red
        $out | Select-String "Error|line \d" | Select-Object -Last 4 | ForEach-Object { Write-Host "      $_" }
    }
}

if ($Sheet) {
    $pngs = Get-ChildItem $Sprites -Filter *.png | Sort-Object Name | ForEach-Object { $_.FullName }
    if ($pngs) {
        & $Blender -b -P (Join-Path $ArtDir "blender\contact_sheet.py") -- `
            --out (Join-Path $ArtDir "renders\contact_sheet.png") @pngs 2>&1 |
            Select-String "SHEET_SAVED" | ForEach-Object { Write-Host $_ }
    }
}

Write-Host ""
Write-Host "built:   $($built.Count)  [$($built -join ', ')]"
if ($skipped.Count) {
    Write-Host "skipped: $($skipped -join ', ')  (no GLB in art\source\)" -ForegroundColor Yellow
}
