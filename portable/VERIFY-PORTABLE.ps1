$ErrorActionPreference = "Continue"

$root = $PSScriptRoot
$reportDir = Join-Path $root "Verification"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$report = Join-Path $reportDir ("Verify-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function W([string]$Text="") {
    Add-Content -LiteralPath $report -Value $Text -Encoding UTF8
}

W "YASB TRUE-PORTABLE + KOMOREBI INTEGRATION VERIFICATION"
W ("Generated: {0}" -f (Get-Date))
W ("YASB root: {0}" -f $root)
W ""

foreach ($relative in @(
    "yasb.exe",
    "Data\Config",
    "Data\LocalState",
    "Data\Temp"
)) {
    W ("{0}: {1}" -f $relative,(Test-Path -LiteralPath (Join-Path $root $relative)))
}

$parent = Split-Path -Parent $root
$komRoot = if ($env:KOMOREBI_PORTABLE_HOME) {
    $env:KOMOREBI_PORTABLE_HOME
}
else {
    Join-Path $parent "Komorebi"
}

$komorebic = Join-Path $komRoot "komorebic.exe"

W ""
W "=== Komorebi sibling ==="
W ("Komorebi root: {0}" -f $komRoot)
W ("komorebic.exe exists: {0}" -f (Test-Path -LiteralPath $komorebic -PathType Leaf))
W ("komorebi.exe running: {0}" -f (@(Get-Process -Name "komorebi" -ErrorAction SilentlyContinue).Count -gt 0))
W ("whkd.exe running: {0}" -f (@(Get-Process -Name "whkd" -ErrorAction SilentlyContinue).Count -gt 0))

if (Test-Path -LiteralPath $komorebic -PathType Leaf) {
    $env:KOMOREBI_PORTABLE_HOME = $komRoot
    $env:KOMOREBI_PORTABLE_CONFIG_HOME = Join-Path $komRoot "Data\Config"
    $env:WHKD_PORTABLE_CONFIG_HOME = Join-Path $komRoot "Data\Config"
    $env:KOMOREBI_DATA_HOME = Join-Path $komRoot "Data\LocalState"
    $env:KOMOREBI_TEMP_HOME = Join-Path $komRoot "Data\Temp"
    $env:PATH = "$komRoot;$env:PATH"

    W ""
    W "=== komorebic data-directory ==="
    try {
        & $komorebic data-directory 2>&1 | ForEach-Object { W ([string]$_) }
    }
    catch {
        W ("ERROR: {0}" -f $_.Exception.Message)
    }
}

W ""
W "=== YASB Komorebi log evidence ==="
$yasbLog = Join-Path $root "Data\Config\yasb.log"

if (Test-Path -LiteralPath $yasbLog -PathType Leaf) {
    $tail = Get-Content -LiteralPath $yasbLog -Tail 500 -ErrorAction SilentlyContinue
    $connected = @($tail | Select-String -SimpleMatch "Komorebi connected to named pipe").Count
    $created = @($tail | Select-String -SimpleMatch "Created named pipe").Count
    $timeouts = @($tail | Select-String -SimpleMatch "Komorebi state query timed out").Count
    $failedSubscribe = @($tail | Select-String -SimpleMatch "Komorebi failed to subscribe named pipe").Count

    W ("Created named pipe lines: {0}" -f $created)
    W ("Komorebi connected lines: {0}" -f $connected)
    W ("State-query timeout lines: {0}" -f $timeouts)
    W ("Failed-subscribe lines: {0}" -f $failedSubscribe)

    if ($connected -gt 0) {
        W "PASS: YASB has logged a successful Komorebi named-pipe connection."
    }
    else {
        W "NOTE: No successful connection line found in the last 500 log lines yet."
    }
}
else {
    W "YASB log not found yet."
}

W ""
W "=== Old Komorebi LocalAppData ==="
$old = Join-Path $env:LOCALAPPDATA "komorebi"
W ("{0}: {1}" -f $old,(Test-Path -LiteralPath $old))

Write-Host ""
Write-Host "Verification report:" -ForegroundColor Cyan
Write-Host "  $report"
