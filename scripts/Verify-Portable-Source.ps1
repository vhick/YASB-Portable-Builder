param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)

function Read-Source([string]$Relative) {
    $file = Join-Path $SourceRoot $Relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Missing expected source file: $Relative"
    }
    return (Get-Content -LiteralPath $file -Raw).Replace("`r`n", "`n")
}

$settings = Read-Source "src\settings.py"
$system = Read-Source "src\core\utils\system.py"
$cloud = Read-Source "src\core\cloud\session.py"
$cloudSchedule = Read-Source "src\core\cloud\schedule.py"
$update = Read-Source "src\core\utils\update_service.py"
$tray = Read-Source "src\core\tray.py"
$win32Utils = Read-Source "src\core\utils\win32\utils.py"
$cli = Read-Source "src\cli.py"

$checks = [ordered]@{
    "portable settings marker" = $settings.Contains("YASB_PORTABLE_PATHS_V1")
    "portable config" = $settings.Contains('PORTABLE_CONFIG_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Config")')
    "portable TEMP" = $settings.Contains('PORTABLE_TEMP_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Temp")')
    "frozen config override" = $settings.Contains('DEFAULT_CONFIG_DIRECTORY = PORTABLE_CONFIG_DIRECTORY if IS_FROZEN')
    "portable frozen state" = $system.Contains('Path(sys.executable).resolve().parent / "Data" / "LocalState"')
    "source-mode fallback only" = $system.Contains('else Path(os.environ["LOCALAPPDATA"]) / "YASB"')
    "cloud state relocated" = $cloud.Contains('base = app_data_path(CLOUD_DIR_NAME)') -and $cloud.Contains('return base')
    "MSI updater disabled" = $update.Contains('return False') -and $update.Contains('def is_update_supported(self)')
    "tray startup hidden" = $tray.Contains('AUTOSTART_FILE = None')
    "registry startup disabled" = $win32Utils.Contains('Portable YASB uses INSTALL-PORTABLE-STARTUP.cmd')
    "CLI installer disabled" = $cli.Contains('The official MSI updater is disabled in the portable build.')
    "CLI autostart disabled" = $cli.Contains('Built-in registry/Task Scheduler autostart is disabled in the portable build.')
    "cloud scheduled task blocked" = $cloudSchedule.Contains('Automatic YASB Cloud scheduled backup is disabled in the portable build.')
}

foreach ($entry in $checks.GetEnumerator()) {
    $state = if ($entry.Value) { "PASS" } else { "FAIL" }
    Write-Host ("{0}: {1}" -f $state, $entry.Key)
    if (-not $entry.Value) {
        throw "Portable source verification failed: $($entry.Key)"
    }
}

# A legitimate source/development-mode fallback can mention LOCALAPPDATA.
# Do NOT fail the portable build merely because that fallback exists.
# Instead verify the frozen branch explicitly chooses Data\LocalState.

$dpapi = Read-Source "src\core\cloud\encryption\dpapi.py"
if (-not $dpapi.Contains("CryptProtectData") -or -not $dpapi.Contains("CryptUnprotectData")) {
    throw "YASB Cloud encryption changed upstream. Re-inspection required."
}

Write-Host "Portable source verification v1.3 PASSED." -ForegroundColor Green
