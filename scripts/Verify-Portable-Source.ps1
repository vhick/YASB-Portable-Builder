param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)

function Read-Source([string]$Relative) {
    $path = Join-Path $SourceRoot $Relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing expected source file: $Relative"
    }
    return Get-Content -LiteralPath $path -Raw
}

$settings = Read-Source "src\settings.py"
$system = Read-Source "src\core\utils\system.py"
$cloud = Read-Source "src\core\cloud\session.py"
$schedule = Read-Source "src\core\cloud\schedule.py"
$tray = Read-Source "src\core\tray.py"
$update = Read-Source "src\core\utils\update_service.py"
$utils = Read-Source "src\core\utils\win32\utils.py"
$cli = Read-Source "src\cli.py"

$required = [ordered]@{
    "portable settings marker" = $settings.Contains("YASB_PORTABLE_PATHS_V1")
    "portable config" = $settings.Contains('PORTABLE_CONFIG_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Config")')
    "portable temp" = $settings.Contains('PORTABLE_TEMP_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Temp")')
    "frozen config ignores host profile path" = $settings.Contains('DEFAULT_CONFIG_DIRECTORY = PORTABLE_CONFIG_DIRECTORY if IS_FROZEN')
    "portable app_data_path" = $system.Contains('"Data" / "LocalState"')
    "portable cloud path" = $cloud.Contains("return app_data_path(CLOUD_DIR_NAME)")
    "official updater disabled" = $update.Contains("Portable builds are updated by the GitHub portable builder")
    "tray autostart hidden" = $tray.Contains("AUTOSTART_FILE = None")
    "registry autostart helper disabled" = $utils.Contains("Registry autostart is intentionally disabled in the portable build")
    "CLI updater disabled" = $cli.Contains("The official MSI updater is disabled in the portable build.")
    "CLI startup disabled" = $cli.Contains("Built-in registry/Task Scheduler autostart is disabled in the portable build.")
    "cloud Scheduled Task blocked" = $schedule.Contains("Automatic YASB Cloud scheduled backup is disabled in the portable build.")
}

$failed = @($required.GetEnumerator() | Where-Object { -not $_.Value })

foreach ($entry in $required.GetEnumerator()) {
    Write-Host ("{0}: {1}" -f $(if($entry.Value){"PASS"}else{"FAIL"}),$entry.Key)
}

if ($failed.Count -gt 0) {
    throw "Portable source verification failed."
}

# Source/development mode intentionally retains upstream LOCALAPPDATA behavior
# inside app_data_path(). The portable requirement is that the FROZEN branch
# resolves beside sys.executable and that Cloud no longer bypasses app_data_path.
if (-not $system.Contains('if getattr(sys, "frozen", False):')) {
    throw "Portable frozen-mode branch is missing from app_data_path()."
}

if (-not $system.Contains('folder = Path(sys.executable).resolve().parent / "Data" / "LocalState"')) {
    throw "Frozen app_data_path() does not resolve to Data\LocalState."
}

if ($cloud.Contains('os.environ.get("LOCALAPPDATA"') -or
    $cloud.Contains('%LOCALAPPDATA%\\YASB\\cloud')) {
    throw "YASB Cloud still contains a direct host LocalAppData persistence path."
}

# Keep upstream DPAPI protection. This is intentional and must not silently
# disappear in future revisions.
$dpapi = Read-Source "src\core\cloud\encryption\dpapi.py"
if (-not $dpapi.Contains("CryptProtectData") -or -not $dpapi.Contains("CryptUnprotectData")) {
    throw "YASB Cloud credential protection changed upstream; re-inspection is required."
}

Write-Host ""
Write-Host "YASB portable source verification PASS." -ForegroundColor Green
