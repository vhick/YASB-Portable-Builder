param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)

$settingsFile = Join-Path $SourceRoot "src\settings.py"
$systemFile = Join-Path $SourceRoot "src\core\utils\system.py"
$cloudSessionFile = Join-Path $SourceRoot "src\core\cloud\session.py"
$cloudScheduleFile = Join-Path $SourceRoot "src\core\cloud\schedule.py"
$trayFile = Join-Path $SourceRoot "src\core\tray.py"
$updateFile = Join-Path $SourceRoot "src\core\utils\update_service.py"
$win32UtilsFile = Join-Path $SourceRoot "src\core\utils\win32\utils.py"
$cliFile = Join-Path $SourceRoot "src\cli.py"

foreach ($path in @(
    $settingsFile,
    $systemFile,
    $cloudSessionFile,
    $cloudScheduleFile,
    $trayFile,
    $updateFile,
    $win32UtilsFile,
    $cliFile
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Expected upstream source file was not found: $path"
    }
}

function Replace-Exact {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [string]$Label
    )

    if ($Text.Contains($New)) {
        Write-Host "$Label already patched." -ForegroundColor DarkGray
        return $Text
    }

    if (-not $Text.Contains($Old)) {
        throw "Could not apply '$Label': upstream source no longer matches the inspected revision. The build is stopping rather than silently losing portability."
    }

    Write-Host "Applying: $Label" -ForegroundColor Cyan
    return $Text.Replace($Old,$New)
}

# ----------------------------------------------------------------------
# 1. Portable config + YASB-owned TEMP.
#
# Frozen YASB ignores any old host YASB_CONFIG_HOME and always resolves
# Data beside yasb.exe. Development/source mode retains upstream behavior.
# ----------------------------------------------------------------------
$settings = Get-Content -LiteralPath $settingsFile -Raw

$oldScriptPath = @'
SCRIPT_PATH = os.path.dirname(sys.executable) if IS_FROZEN else os.path.dirname(os.path.abspath(__file__))
'@

$newScriptPath = @'
SCRIPT_PATH = os.path.dirname(sys.executable) if IS_FROZEN else os.path.dirname(os.path.abspath(__file__))

# YASB_PORTABLE_PATHS_V1
PORTABLE_DATA_DIRECTORY = os.path.join(SCRIPT_PATH, "Data")
PORTABLE_CONFIG_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Config")
PORTABLE_TEMP_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Temp")

if IS_FROZEN:
    os.makedirs(PORTABLE_CONFIG_DIRECTORY, exist_ok=True)
    os.makedirs(PORTABLE_TEMP_DIRECTORY, exist_ok=True)

    # Make child YASB processes inherit the portable locations too.
    os.environ["YASB_CONFIG_HOME"] = PORTABLE_CONFIG_DIRECTORY
    os.environ["TEMP"] = PORTABLE_TEMP_DIRECTORY
    os.environ["TMP"] = PORTABLE_TEMP_DIRECTORY

    # tempfile caches its selected directory. Set it explicitly so YASB-owned
    # quick-launch icon caches and other temporary files stay beside the app.
    import tempfile

    tempfile.tempdir = PORTABLE_TEMP_DIRECTORY
'@

$settings = Replace-Exact `
    -Text $settings `
    -Old $oldScriptPath `
    -New $newScriptPath `
    -Label "portable config/temp root"

$oldConfig = 'DEFAULT_CONFIG_DIRECTORY = os.getenv("YASB_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config", "yasb")'
$newConfig = 'DEFAULT_CONFIG_DIRECTORY = PORTABLE_CONFIG_DIRECTORY if IS_FROZEN else (os.getenv("YASB_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config", "yasb"))'

$settings = Replace-Exact `
    -Text $settings `
    -Old $oldConfig `
    -New $newConfig `
    -Label "force frozen config into Data\Config"

Set-Content -LiteralPath $settingsFile -Value $settings -Encoding UTF8

# ----------------------------------------------------------------------
# 2. Central YASB local-state helper.
#
# This catches systray_state_*.json, update timestamps, OAuth token files,
# Open-Meteo location, quick-launch state/caches, taskbar pins/icons,
# Claude/Codex usage caches, wallpaper thumbnails, Cava config, traffic,
# and any future code using app_data_path().
# ----------------------------------------------------------------------
$system = Get-Content -LiteralPath $systemFile -Raw

$oldAppData = @'
def app_data_path(filename: str = None) -> Path:
    """
    Get the YASB local data folder (creating it if it doesn't exist),
    or a file path inside it if filename is provided.
    """
    folder = Path(os.environ["LOCALAPPDATA"]) / "YASB"
    folder.mkdir(parents=True, exist_ok=True)
    if filename is not None:
        return folder / filename
    return folder
'@

$newAppData = @'
def app_data_path(filename: str = None) -> Path:
    """
    Get YASB's application-owned local-state directory.

    Frozen portable builds store it beside yasb.exe. Source/development runs
    retain the upstream %LOCALAPPDATA%\YASB behavior.
    """
    if getattr(sys, "frozen", False):
        folder = Path(sys.executable).resolve().parent / "Data" / "LocalState"
    else:
        folder = Path(os.environ["LOCALAPPDATA"]) / "YASB"

    folder.mkdir(parents=True, exist_ok=True)

    if filename is not None:
        return folder / filename

    return folder
'@

$system = Replace-Exact `
    -Text $system `
    -Old $oldAppData `
    -New $newAppData `
    -Label "redirect app_data_path to Data\LocalState"

Set-Content -LiteralPath $systemFile -Value $system -Encoding UTF8

# ----------------------------------------------------------------------
# 3. YASB Cloud directory.
#
# Upstream bypasses app_data_path and directly uses %LOCALAPPDATA%\YASB\cloud.
# Redirect its files to the same portable LocalState tree.
#
# NOTE: Cloud session.bin/vault.bin remain protected by Windows DPAPI.
# Their FILES are portable, but the cached cloud sign-in cannot decrypt after
# a Windows reinstall/different account. That security protection is kept
# intentionally rather than weakening it.
# ----------------------------------------------------------------------
$cloudSession = Get-Content -LiteralPath $cloudSessionFile -Raw

$cloudSession = Replace-Exact `
    -Text $cloudSession `
    -Old 'from core.cloud.errors import CloudError' `
    -New "from core.cloud.errors import CloudError`nfrom core.utils.system import app_data_path" `
    -Label "import portable local-state helper in cloud session"

$oldCloudDir = @'
def cloud_dir() -> Path:
    """`%LOCALAPPDATA%\YASB\cloud`, created on demand."""
    base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local")) / "YASB" / CLOUD_DIR_NAME
    base.mkdir(parents=True, exist_ok=True)
    return base
'@

$newCloudDir = @'
def cloud_dir() -> Path:
    """YASB Cloud state below the portable application local-state directory."""
    return app_data_path(CLOUD_DIR_NAME)
'@

$cloudSession = Replace-Exact `
    -Text $cloudSession `
    -Old $oldCloudDir `
    -New $newCloudDir `
    -Label "redirect YASB Cloud files"

Set-Content -LiteralPath $cloudSessionFile -Value $cloudSession -Encoding UTF8

# ----------------------------------------------------------------------
# 4. Disable automatic installer updates in the portable fork.
#
# GitHub Actions is the update mechanism. This avoids an official MSI replacing
# the patched executable set.
# ----------------------------------------------------------------------
$updateService = Get-Content -LiteralPath $updateFile -Raw

$oldUpdateSupport = @'
    def is_update_supported(self) -> bool:
        """Check if updates are supported on this system.

        Updates are supported when:
        1. App is frozen (running as bundled executable)
        2. YASB is installed (not running from source)
        3. Architecture is known (x64 or ARM64)
        4. Updates are disabled for PR build channels.

        Updates are disabled for PR build channels.

        Returns:
            True if updates are supported, False otherwise
        """

        is_installed = get_app_identifier() == APP_ID
        is_arch_supported = ARCHITECTURE is not None
        is_pr_build = RELEASE_CHANNEL.startswith("pr-")

        return is_installed and is_arch_supported and IS_FROZEN and (not is_pr_build)
'@

$newUpdateSupport = @'
    def is_update_supported(self) -> bool:
        """Portable builds are updated by the GitHub portable builder, never the MSI updater."""
        return False
'@

$updateService = Replace-Exact `
    -Text $updateService `
    -Old $oldUpdateSupport `
    -New $newUpdateSupport `
    -Label "disable official MSI updater"

Set-Content -LiteralPath $updateFile -Value $updateService -Encoding UTF8

# ----------------------------------------------------------------------
# 5. Disable YASB's registry-based autostart implementation.
#
# The packaged INSTALL-PORTABLE-STARTUP.cmd creates our Startup-folder
# shortcut instead.
# ----------------------------------------------------------------------
$tray = Get-Content -LiteralPath $trayFile -Raw
$tray = Replace-Exact `
    -Text $tray `
    -Old 'AUTOSTART_FILE = EXE_PATH if os.path.exists(EXE_PATH) else None' `
    -New 'AUTOSTART_FILE = None  # Portable build uses INSTALL-PORTABLE-STARTUP.cmd' `
    -Label "hide registry autostart menu in portable build"
Set-Content -LiteralPath $trayFile -Value $tray -Encoding UTF8

$win32Utils = Get-Content -LiteralPath $win32UtilsFile -Raw

$oldAutostartFunctions = @'
def enable_autostart(app_name: str, executable_path: str) -> bool:
    """Add application to Windows startup."""
    try:
        with _open_startup_registry(winreg.KEY_SET_VALUE) as key:
            winreg.SetValueEx(key, app_name, 0, winreg.REG_SZ, executable_path)
        logging.info("%s added to startup", app_name)
        return True
    except Exception as e:
        logging.error("Failed to add %s to startup: %s", app_name, e)
        return False


def disable_autostart(app_name: str) -> bool:
    """Remove application from Windows startup."""
    try:
        # First check if the entry exists
        if is_autostart_enabled(app_name):
            with _open_startup_registry(winreg.KEY_ALL_ACCESS) as key:
                winreg.DeleteValue(key, app_name)
            logging.info("%s removed from startup", app_name)
        else:
            logging.info("Startup entry for %s not found", app_name)
        return True
    except Exception as e:
        logging.error("Failed to remove %s from startup: %s", app_name, e)
        return False


def is_autostart_enabled(app_name: str) -> bool:
    """Check if application is in Windows startup."""
    try:
        with _open_startup_registry(winreg.KEY_READ) as key:
            winreg.QueryValueEx(key, app_name)
        return True
    except OSError:
        return False
    except Exception as e:
        logging.error("Failed to check startup status for %s: %s", app_name, e)
        return False
'@

$newAutostartFunctions = @'
def enable_autostart(app_name: str, executable_path: str) -> bool:
    """Registry autostart is intentionally disabled in the portable build."""
    logging.warning("Portable YASB uses INSTALL-PORTABLE-STARTUP.cmd instead of registry autostart.")
    return False


def disable_autostart(app_name: str) -> bool:
    """Registry autostart is intentionally disabled in the portable build."""
    logging.info("Portable YASB does not own a registry autostart value.")
    return True


def is_autostart_enabled(app_name: str) -> bool:
    """Registry autostart is intentionally disabled in the portable build."""
    return False
'@

$win32Utils = Replace-Exact `
    -Text $win32Utils `
    -Old $oldAutostartFunctions `
    -New $newAutostartFunctions `
    -Label "disable registry autostart helper functions"

Set-Content -LiteralPath $win32UtilsFile -Value $win32Utils -Encoding UTF8

# ----------------------------------------------------------------------
# 6. Disable CLI actions that would install an MSI, write autostart registry/
# Task Scheduler entries, or configure WER crash-dump registry keys.
# ----------------------------------------------------------------------
$cli = Get-Content -LiteralPath $cliFile -Raw

$oldCliIntegration = @'
        elif args.command == "set-channel":
            self.channel_handler.switch_channel(args.target_channel)
            sys.exit(0)

        elif args.command == "update":
            self.update_handler.update_yasb(YASB_VERSION)

        elif args.command == "enable-autostart":
            if args.task:
                if not self.task_handler.is_admin():
                    print("Please run this command as an administrator.")
                else:
                    self.task_handler.create_task()
            else:
                self.enable_startup()
            sys.exit(0)

        elif args.command == "disable-autostart":
            if args.task:
                if not self.task_handler.is_admin():
                    print("Please run this command as an administrator.")
                else:
                    self.task_handler.delete_task()
            else:
                self.disable_startup()
            sys.exit(0)

        elif args.command == "enable-crash-dumps":
            if not self.task_handler.is_admin():
                print("Please run this command as an administrator.")
            else:
                self.crash_dump_handler.enable()
            sys.exit(0)

        elif args.command == "disable-crash-dumps":
            if not self.task_handler.is_admin():
                print("Please run this command as an administrator.")
            else:
                self.crash_dump_handler.disable()
            sys.exit(0)
'@

$newCliIntegration = @'
        elif args.command == "set-channel":
            print("Release-channel switching is disabled in the portable build.")
            print("Use your YASB-Portable-Builder GitHub workflow to update the application.")
            sys.exit(0)

        elif args.command == "update":
            print("The official MSI updater is disabled in the portable build.")
            print("Use your YASB-Portable-Builder GitHub workflow to update the application.")
            sys.exit(0)

        elif args.command == "enable-autostart":
            print("Built-in registry/Task Scheduler autostart is disabled in the portable build.")
            print("Run INSTALL-PORTABLE-STARTUP.cmd from the portable folder instead.")
            sys.exit(0)

        elif args.command == "disable-autostart":
            print("Run REMOVE-PORTABLE-STARTUP.cmd from the portable folder.")
            sys.exit(0)

        elif args.command == "enable-crash-dumps":
            print("WER registry crash-dump registration is disabled in the portable build.")
            print("Portable logs and normal application state remain under the Data folder.")
            sys.exit(0)

        elif args.command == "disable-crash-dumps":
            print("WER registry crash-dump registration is not used by the portable build.")
            sys.exit(0)
'@

$cli = Replace-Exact `
    -Text $cli `
    -Old $oldCliIntegration `
    -New $newCliIntegration `
    -Label "disable CLI MSI/autostart/WER integration"

Set-Content -LiteralPath $cliFile -Value $cli -Encoding UTF8

# ----------------------------------------------------------------------
# 7. YASB Cloud auto-backup normally registers its own Scheduled Task.
# Keep manual Cloud features, but block creation of that host-persistent task.
# ----------------------------------------------------------------------
$cloudSchedule = Get-Content -LiteralPath $cloudScheduleFile -Raw

$oldScheduleStart = @'
def create() -> tuple[bool, str]:
    """Register the task, replacing any existing one. Returns success and any failure text."""
    executable = _executable()
'@

$newScheduleStart = @'
def create() -> tuple[bool, str]:
    """Portable builds do not register a host-persistent Scheduled Task."""
    return False, "Automatic YASB Cloud scheduled backup is disabled in the portable build."

    executable = _executable()
'@

$cloudSchedule = Replace-Exact `
    -Text $cloudSchedule `
    -Old $oldScheduleStart `
    -New $newScheduleStart `
    -Label "disable YASB Cloud scheduled-task creation"

Set-Content -LiteralPath $cloudScheduleFile -Value $cloudSchedule -Encoding UTF8

# ----------------------------------------------------------------------
# Patch marker.
# ----------------------------------------------------------------------
$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    patch = "YASB true-portable"
    patch_version = "1.0"
    inspected_revision = "ebfc0580683d8f27abb98e87019018f0e52cc26d"
    upstream_revision = $revision
    applied_at = (Get-Date).ToString("o")
    config_root = "./Data/Config"
    local_state_root = "./Data/LocalState"
    temp_root = "./Data/Temp"
    log_file = "./Data/Config/yasb.log"
    built_in_msi_updater = $false
    built_in_registry_autostart = $false
    built_in_task_autostart = $false
    wer_registry_crash_dump_setup = $false
    cloud_scheduled_backup_task = $false
    cloud_files_portable = $true
    cloud_cached_login_machine_portable = $false
    cloud_cached_login_note = "session.bin/vault.bin retain upstream Windows DPAPI protection and require re-authentication after Windows reinstall or on another account."
} |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".yasb-true-portable-patch.json") -Encoding UTF8

Write-Host ""
Write-Host "YASB true-portable source patch applied." -ForegroundColor Green
Write-Host "Config:     .\Data\Config"
Write-Host "LocalState: .\Data\LocalState"
Write-Host "Temp:       .\Data\Temp"
