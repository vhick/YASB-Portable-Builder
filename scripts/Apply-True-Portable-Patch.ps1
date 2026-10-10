param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)

function Replace-Exact {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [string]$Label,
        [string]$AlternativeOld = ""
    )

    if ($Text.Contains($New)) {
        Write-Host "Already patched: $Label" -ForegroundColor DarkGray
        return $Text
    }

    $matched = $Old
    if (-not $Text.Contains($Old)) {
        if (-not [string]::IsNullOrEmpty($AlternativeOld) -and $Text.Contains($AlternativeOld)) {
            $matched = $AlternativeOld
        }
        else {
            throw "Could not apply '$Label': upstream source changed. The portable build stopped deliberately. Run inspect-source."
        }
    }

    # .NET string.Replace is literal, avoiding accidental regex changes.
    Write-Host "Applying: $Label" -ForegroundColor Cyan
    return $Text.Replace($matched, $New)
}

# Keep a list of pending modifications in memory. Only write once all anchors passed.
$pending = @{}

$file = Join-Path $SourceRoot "src\settings.py"
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Expected source file missing: $file" }
$content = (Get-Content -LiteralPath $file -Raw).Replace("`r`n", "`n")
$old = @'
SCRIPT_PATH = os.path.dirname(sys.executable) if IS_FROZEN else os.path.dirname(os.path.abspath(__file__))
'@
$new = @'
SCRIPT_PATH = os.path.dirname(sys.executable) if IS_FROZEN else os.path.dirname(os.path.abspath(__file__))

# YASB_PORTABLE_PATHS_V1
PORTABLE_DATA_DIRECTORY = os.path.join(SCRIPT_PATH, "Data")
PORTABLE_CONFIG_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Config")
PORTABLE_TEMP_DIRECTORY = os.path.join(PORTABLE_DATA_DIRECTORY, "Temp")

if IS_FROZEN:
    os.makedirs(PORTABLE_CONFIG_DIRECTORY, exist_ok=True)
    os.makedirs(PORTABLE_TEMP_DIRECTORY, exist_ok=True)
    os.environ["YASB_CONFIG_HOME"] = PORTABLE_CONFIG_DIRECTORY
    os.environ["TEMP"] = PORTABLE_TEMP_DIRECTORY
    os.environ["TMP"] = PORTABLE_TEMP_DIRECTORY
    import tempfile
    tempfile.tempdir = PORTABLE_TEMP_DIRECTORY
'@
$content = Replace-Exact -Text $content -Label "portable config and temp root" -Old $old -New $new
$old = @'
DEFAULT_CONFIG_DIRECTORY = os.getenv("YASB_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config", "yasb")
'@
$new = @'
DEFAULT_CONFIG_DIRECTORY = PORTABLE_CONFIG_DIRECTORY if IS_FROZEN else (os.getenv("YASB_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config", "yasb"))
'@
$content = Replace-Exact -Text $content -Label "frozen config directory" -Old $old -New $new
$pending[$file] = $content

$file = Join-Path $SourceRoot "src\core\utils\system.py"
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Expected source file missing: $file" }
$content = (Get-Content -LiteralPath $file -Raw).Replace("`r`n", "`n")

# Patch the single directory assignment INSIDE app_data_path(), rather than
# replacing the entire function. Upstream may change type hints, docstrings,
# or comments without changing how this function chooses its path.
# Fail closed if its structure or storage behavior changes in a meaningful way.
$functionPattern = '(?ms)^def app_data_path\([^\n]*\) -> Path:\n.*?(?=^def |^class |^@|\z)'
$functionMatches = [regex]::Matches($content, $functionPattern)
if ($functionMatches.Count -ne 1) {
    throw "Cannot find exactly one app_data_path() function. Re-inspect upstream YASB before rebuilding."
}

$function = $functionMatches[0].Value
$oldFolder = '    folder = Path(os.environ["LOCALAPPDATA"]) / "YASB"'
$newFolder = @'
    folder = (
        Path(sys.executable).resolve().parent / "Data" / "LocalState"
        if getattr(sys, "frozen", False)
        else Path(os.environ["LOCALAPPDATA"]) / "YASB"
    )
'@

if (-not $content.Contains("import sys")) {
    throw "system.py no longer imports sys; inspect before patching its portable path."
}

if ($function.Contains($newFolder)) {
    Write-Host "Already patched: portable LocalAppData" -ForegroundColor DarkGray
}
else {
    $oldOccurrences = ([regex]::Matches($function, [regex]::Escape($oldFolder))).Count

    if ($oldOccurrences -ne 1 -or
        -not $function.Contains('folder.mkdir(parents=True, exist_ok=True)') -or
        -not $function.Contains('if filename is not None:') -or
        -not $function.Contains('return folder / filename') -or
        -not $function.Contains('return folder')) {
        throw "app_data_path() storage behavior differs from inspected source. Refusing unsafe portable patch."
    }

    $patchedFunction = $function.Replace($oldFolder, $newFolder)
    $content = $content.Remove($functionMatches[0].Index, $functionMatches[0].Length).Insert($functionMatches[0].Index, $patchedFunction)
    Write-Host "Applying: portable LocalAppData (single-assignment patch)" -ForegroundColor Cyan
}

$pending[$file] = $content

$file = Join-Path $SourceRoot "src\core\cloud\session.py"
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Expected source file missing: $file" }
$content = (Get-Content -LiteralPath $file -Raw).Replace("`r`n", "`n")
$old = @'
from core.cloud.errors import CloudError
'@
$new = @'
from core.cloud.errors import CloudError
from core.utils.system import app_data_path
'@
$content = Replace-Exact -Text $content -Label "import state-path helper" -Old $old -New $new
# Match the Cloud function itself, but modify only the directory assignment.
# This deliberately ignores comments/docstrings and newline formatting.
# The rest of the Cloud session and DPAPI protection remain unchanged.
$cloudFunctionPattern = '(?ms)^def cloud_dir\(\)\s*->\s*Path:\n.*?(?=^def |^class |^@|\z)'
$cloudFunctionMatches = [regex]::Matches($content, $cloudFunctionPattern)
if ($cloudFunctionMatches.Count -ne 1) {
    throw "Expected exactly one cloud_dir() function, found $($cloudFunctionMatches.Count). Inspect current upstream source."
}

$cloudFunction = $cloudFunctionMatches[0].Value
$oldCloudAssignment = '    base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local")) / "YASB" / CLOUD_DIR_NAME'
$newCloudAssignment = '    base = app_data_path(CLOUD_DIR_NAME)'

if ($cloudFunction.Contains($newCloudAssignment)) {
    Write-Host "Already patched: cloud state path" -ForegroundColor DarkGray
}
else {
    $oldCount = ([regex]::Matches($cloudFunction, [regex]::Escape($oldCloudAssignment))).Count
    if ($oldCount -ne 1 -or
        -not $cloudFunction.Contains('base.mkdir(parents=True, exist_ok=True)') -or
        -not $cloudFunction.Contains('return base')) {
        Write-Host 'Current cloud_dir() source for diagnosis:' -ForegroundColor Yellow
        Write-Host $cloudFunction
        throw "Cloud directory logic changed, expected one old assignment plus mkdir/return; refusing unsafe patch."
    }

    $replacement = $cloudFunction.Replace($oldCloudAssignment, $newCloudAssignment)
    $content = $content.Remove($cloudFunctionMatches[0].Index, $cloudFunctionMatches[0].Length).Insert($cloudFunctionMatches[0].Index, $replacement)
    Write-Host "Applying: cloud state path (single-assignment patch)" -ForegroundColor Cyan
}

# Require the imported portable helper to be present before writing any files.
if (-not $content.Contains('from core.utils.system import app_data_path')) {
    throw 'Cloud path helper import is missing; refusing portable build.'
}
$pending[$file] = $content

$file = Join-Path $SourceRoot "src\core\utils\update_service.py"
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Expected source file missing: $file" }
$content = (Get-Content -LiteralPath $file -Raw).Replace("`r`n", "`n")
$old = @'
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
$new = @'
    def is_update_supported(self) -> bool:
        """The portable build is updated only by its GitHub Actions builder."""
        return False
'@
$content = Replace-Exact -Text $content -Label "disable MSI updater" -Old $old -New $new
$pending[$file] = $content

$file = Join-Path $SourceRoot "src\core\tray.py"
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Expected source file missing: $file" }
$content = (Get-Content -LiteralPath $file -Raw).Replace("`r`n", "`n")
$old = @'
AUTOSTART_FILE = EXE_PATH if os.path.exists(EXE_PATH) else None
'@
$new = @'
AUTOSTART_FILE = None  # Portable build uses INSTALL-PORTABLE-STARTUP.cmd
'@
$content = Replace-Exact -Text $content -Label "disable tray registry startup" -Old $old -New $new
$pending[$file] = $content

$file = Join-Path $SourceRoot "src\core\utils\win32\utils.py"
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Expected source file missing: $file" }
$content = (Get-Content -LiteralPath $file -Raw).Replace("`r`n", "`n")
$old = @'
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
$new = @'
def enable_autostart(app_name: str, executable_path: str) -> bool:
    """Disable registry autostart in the portable build."""
    logging.warning("Portable YASB uses INSTALL-PORTABLE-STARTUP.cmd, not registry autostart.")
    return False


def disable_autostart(app_name: str) -> bool:
    """Registry autostart is not used in the portable build."""
    return True


def is_autostart_enabled(app_name: str) -> bool:
    """Registry autostart is intentionally disabled in the portable build."""
    return False
'@
$content = Replace-Exact -Text $content -Label "disable registry autostart" -Old $old -New $new
$pending[$file] = $content

$file = Join-Path $SourceRoot "src\cli.py"
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Expected source file missing: $file" }
$content = (Get-Content -LiteralPath $file -Raw).Replace("`r`n", "`n")
$old = @'
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
$new = @'
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
            sys.exit(0)

        elif args.command == "disable-crash-dumps":
            print("WER registry crash-dump registration is not used by the portable build.")
            sys.exit(0)
'@
$content = Replace-Exact -Text $content -Label "disable host integration CLI" -Old $old -New $new
$pending[$file] = $content

$file = Join-Path $SourceRoot "src\core\cloud\schedule.py"
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Expected source file missing: $file" }
$content = (Get-Content -LiteralPath $file -Raw).Replace("`r`n", "`n")
$old = @'
def create() -> tuple[bool, str]:
    """Register the task, replacing any existing one. Returns success and any failure text."""
    executable = _executable()
'@
$new = @'
def create() -> tuple[bool, str]:
    """The portable build must not register a persistent Scheduled Task."""
    return False, "Automatic YASB Cloud scheduled backup is disabled in the portable build."

    executable = _executable()
'@
$content = Replace-Exact -Text $content -Label "disable cloud scheduled task" -Old $old -New $new
$pending[$file] = $content

foreach ($file in $pending.Keys) {
    Set-Content -LiteralPath $file -Value $pending[$file] -Encoding UTF8
}

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()
$marker = [ordered]@{
    patch = "YASB true-portable"
    patch_version = "1.3"
    upstream_revision = $revision
    inspected_revision = "7cd25351444d35111f08999f6b2b447965ce1932"
    applied_at = (Get-Date).ToString("o")
    config_root = "./Data/Config"
    local_state_root = "./Data/LocalState"
    temp_root = "./Data/Temp"
    built_in_msi_updater = $false
    built_in_registry_autostart = $false
    built_in_task_autostart = $false
    wer_registry_crash_dump_setup = $false
    cloud_scheduled_backup_task = $false
    cloud_files_portable = $true
    cloud_cached_login_machine_portable = $false
    cloud_cached_login_note = "Windows DPAPI-protected cloud sign-in must be renewed after clean Windows install."
}
$marker | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".yasb-true-portable-patch.json") -Encoding UTF8

Write-Host "YASB true-portable patch v1.3 applied successfully." -ForegroundColor Green
