# Runs the test suites on Windows.  PowerShell:  .\run-tests.ps1
#
# The end-to-end suites need only Aseprite itself, which is the half worth
# running on another platform: it exercises real file reading, real path
# handling and the real timeline API. The suites above it use a stand-in API
# and are platform-independent, so they are skipped unless a Lua interpreter
# happens to be around.
#
# Set $env:ASEPRITE first if Aseprite lives somewhere unusual.

$ErrorActionPreference = "Stop"
# Paths below are relative to the repo root, one level up from this script.
Set-Location -Path (Join-Path $PSScriptRoot "..")

# ------------------------------------------------------------------- Aseprite

$aseprite = $env:ASEPRITE
if (-not $aseprite) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\Aseprite\Aseprite.exe",
        "${env:ProgramFiles}\Steam\steamapps\common\Aseprite\Aseprite.exe",
        "${env:ProgramFiles}\Aseprite\Aseprite.exe",
        "${env:LOCALAPPDATA}\Aseprite\Aseprite.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { $aseprite = $c; break }
    }
    if (-not $aseprite) {
        $onPath = Get-Command aseprite -ErrorAction SilentlyContinue
        if ($onPath) { $aseprite = $onPath.Source }
    }
}

if (-not $aseprite) {
    Write-Host "Aseprite not found. Set it and run again, for example:" -ForegroundColor Yellow
    Write-Host '  $env:ASEPRITE = "C:\Path\To\Aseprite.exe"'
    exit 1
}

Write-Host "Aseprite: $aseprite"

# --------------------------------------------------------- stand-in API suites

$lua = $null
foreach ($c in @("lua", "lua54", "lua5.4", "luajit")) {
    $found = Get-Command $c -ErrorAction SilentlyContinue
    if ($found) { $lua = $found.Source; break }
}

if ($lua) {
    foreach ($suite in @(
        @{ name = "naming";  file = "tests\run_tests.lua" },
        @{ name = "builder"; file = "tests\test_builder.lua" },
        @{ name = "watcher"; file = "tests\test_watcher.lua" }
    )) {
        Write-Host ""
        Write-Host "== $($suite.name) =="
        & $lua $suite.file
        if ($LASTEXITCODE -ne 0) { Write-Host "$($suite.name) failed" -ForegroundColor Red; exit 1 }
    }
} else {
    Write-Host "(no Lua interpreter found, skipping the stand-in suites; they are platform-independent)"
}

# ------------------------------------------------------------ end-to-end pair

# Aseprite exits 0 whatever the script decides, so the verdict is read out of
# the output. A missing marker means the suite died partway and must not pass.
function Invoke-E2E {
    param([string]$Label, [string[]]$AsepriteArgs)

    Write-Host ""
    Write-Host "== $Label =="
    $out = & $aseprite @AsepriteArgs 2>&1 | Out-String
    Write-Host $out

    if ($out -match "e2e-result: FAIL") { return $false }
    if ($out -notmatch "e2e-result: ok") {
        Write-Host "  (the suite ended without reporting a result)" -ForegroundColor Red
        return $false
    }
    return $true
}

$ok = Invoke-E2E "end-to-end (real Aseprite)" @("--batch", "--script", "tests\e2e_aseprite.lua")

# The drag path suite wants the sample frames handed to Aseprite the way a drop
# would, so the names are expanded here rather than left to the shell.
$frames = Get-ChildItem -Path "samples\hero\*.png" | ForEach-Object { $_.FullName }
$dragArgs = @("--batch") + $frames + @("--script", "tests\e2e_dragpath.lua")
$okDrag = Invoke-E2E "end-to-end, drag path (files opened by Aseprite itself)" $dragArgs

if (-not ($ok -and $okDrag)) {
    Write-Host ""
    Write-Host "end-to-end suite failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "all suites passed" -ForegroundColor Green
