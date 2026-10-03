$ErrorActionPreference = "Continue"

$root = $PSScriptRoot
$reportDir = Join-Path $root "Verification"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$report = Join-Path $reportDir ("Verify-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function W([string]$Text="") {
    Add-Content -LiteralPath $report -Value $Text -Encoding UTF8
}

W "YASB TRUE-PORTABLE VERIFICATION"
W ("Generated: {0}" -f (Get-Date))
W ("Portable folder: {0}" -f $root)
W ""

foreach ($p in @(
    "yasb.exe",
    "yasbc.exe",
    "yasb_themes.exe",
    "yasb_cloud.exe",
    "Data\Config",
    "Data\LocalState",
    "Data\Temp"
)) {
    $full = Join-Path $root $p
    W ("{0}: {1}" -f $p,(Test-Path -LiteralPath $full))
}

W ""
W "=== Portable Data contents ==="
$data = Join-Path $root "Data"
if (Test-Path -LiteralPath $data -PathType Container) {
    Get-ChildItem -LiteralPath $data -Force -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 500 |
        ForEach-Object { W $_.FullName }
}

W ""
W "=== Known old host YASB locations ==="
$oldLocations = @(
    (Join-Path $env:LOCALAPPDATA "YASB"),
    (Join-Path $HOME ".config\yasb"),
    (Join-Path ([IO.Path]::GetTempPath()) "yasb_quick_launch_icons")
)

foreach ($p in $oldLocations) {
    W ("{0}: {1}" -f $p,(Test-Path -LiteralPath $p))
}

W ""
W "=== YASB_CONFIG_HOME environment ==="
W ("Current process: {0}" -f $env:YASB_CONFIG_HOME)
W ("User environment: {0}" -f [Environment]::GetEnvironmentVariable("YASB_CONFIG_HOME","User"))

W ""
W "=== Registry autostart ==="
$run = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
try {
    $value = (Get-ItemProperty -Path $run -Name "YASB" -ErrorAction Stop).YASB
    W ("HKCU Run YASB = {0}" -f $value)
}
catch {
    W "HKCU Run YASB: absent"
}

W ""
W "=== Scheduled Tasks ==="
foreach ($name in @("YASB Reborn","YASB Cloud Automatic Backup")) {
    try {
        $task = Get-ScheduledTask -TaskName $name -ErrorAction Stop
        W ("{0}: PRESENT" -f $name)
    }
    catch {
        W ("{0}: absent" -f $name)
    }
}

W ""
W "=== WER LocalDumps ==="
$wer = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\yasb.exe"
W ("{0}: {1}" -f $wer,(Test-Path $wer))

W ""
W "=== Old MSI integration ==="
foreach ($p in @(
    "HKLM:\SOFTWARE\Classes\AppUserModelId\YASB.YetAnotherStatusBar",
    "HKCU:\Software\Classes\AppUserModelId\YASB.YetAnotherStatusBar",
    "HKLM:\SOFTWARE\Classes\yasb-themes",
    "HKCU:\Software\Classes\yasb-themes"
)) {
    W ("{0}: {1}" -f $p,(Test-Path $p))
}

W ""
W "=== Cloud portability note ==="
W "YASB Cloud files are stored below Data\LocalState\cloud."
W "Upstream protects cached cloud login/session material with Windows DPAPI."
W "Those cached credentials are intentionally machine/user-bound."
W "After clean Windows reinstall or on another Windows account, sign in to YASB Cloud again."
W "This does not affect Data\Config, .env, widget state, GitHub OAuth token files, caches, or normal YASB settings."

Write-Host ""
Write-Host "Verification report:" -ForegroundColor Cyan
Write-Host "  $report"
