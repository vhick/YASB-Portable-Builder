param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)

function Normalize-Newlines {
    param([string]$Text)

    if ($null -eq $Text) {
        return $Text
    }

    # Git can check text out with CRLF on Windows while patch templates may
    # contain LF. Compare one canonical representation so identical source is
    # not falsely reported as "upstream changed".
    return $Text.Replace("`r`n","`n").Replace("`r","`n")
}


$settingsFile = Join-Path $SourceRoot "src\settings.py"
$clientFile = Join-Path $SourceRoot "src\core\widgets\services\komorebi\client.py"

foreach ($path in @($settingsFile,$clientFile)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Expected YASB source file not found: $path"
    }
}

# ---------------------------------------------------------------------------
# settings.py: locate sibling Komorebi portable folder early, before widgets.
# This works even when yasb.exe is started directly rather than through CMD.
# ---------------------------------------------------------------------------
$settings = Normalize-Newlines (Get-Content -LiteralPath $settingsFile -Raw)

if (-not $settings.Contains("YASB_KOMOREBI_PORTABLE_INTEGRATION_V1")) {
    $needle = 'SCRIPT_PATH = os.path.dirname(sys.executable) if IS_FROZEN else os.path.dirname(os.path.abspath(__file__))'

    if (-not $settings.Contains($needle)) {
        throw "YASB settings.py changed; SCRIPT_PATH anchor not found."
    }

    $block = @'

# YASB_KOMOREBI_PORTABLE_INTEGRATION_V1
# Prefer an explicit process-local location, otherwise discover a sibling
# folder: <parent>\YASB and <parent>\Komorebi.
if IS_FROZEN:
    _komorebi_home = os.getenv("KOMOREBI_PORTABLE_HOME")

    if not _komorebi_home:
        _komorebi_home = os.path.normpath(os.path.join(SCRIPT_PATH, os.pardir, "Komorebi"))

    _komorebic_exe = os.path.join(_komorebi_home, "komorebic.exe")

    if os.path.isfile(_komorebic_exe):
        os.environ["KOMOREBI_PORTABLE_HOME"] = _komorebi_home
        os.environ["KOMOREBI_PORTABLE_CONFIG_HOME"] = os.path.join(_komorebi_home, "Data", "Config")
        os.environ["WHKD_PORTABLE_CONFIG_HOME"] = os.path.join(_komorebi_home, "Data", "Config")
        os.environ["KOMOREBI_DATA_HOME"] = os.path.join(_komorebi_home, "Data", "LocalState")
        os.environ["KOMOREBI_TEMP_HOME"] = os.path.join(_komorebi_home, "Data", "Temp")

        _path_entries = os.environ.get("PATH", "").split(os.pathsep)
        if not any(os.path.normcase(p) == os.path.normcase(_komorebi_home) for p in _path_entries if p):
            os.environ["PATH"] = _komorebi_home + os.pathsep + os.environ.get("PATH", "")
'@

    $settings = $settings.Replace($needle,$needle + $block)
    Set-Content -LiteralPath $settingsFile -Value $settings -Encoding UTF8
    Write-Host "Applied YASB sibling-Kommorebi environment discovery." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# client.py: use exact patched komorebic.exe when available and make the
# initial state query less vulnerable to AV/process-start scanning latency.
# ---------------------------------------------------------------------------
$client = Normalize-Newlines (Get-Content -LiteralPath $clientFile -Raw)

if (-not $client.Contains("YASB_KOMOREBI_CLIENT_PORTABLE_V1")) {
    if (-not $client.Contains("import json`nimport logging`nimport subprocess")) {
        throw "YASB Komorebi client import block changed."
    }

    $client = $client.Replace(
        "import json`nimport logging`nimport subprocess",
        "import json`nimport logging`nimport os`nimport subprocess"
    )

    $oldInit = @'
    def __init__(self, komorebic_path: str = "komorebic.exe", timeout_secs: float = 0.5):
        if hasattr(self, "_komorebi_initialized"):
            return
        self._komorebi_initialized = True

        super().__init__()
        self._timeout_secs = timeout_secs
        self._komorebic_path = komorebic_path
'@

    $newInit = @'
    # YASB_KOMOREBI_CLIENT_PORTABLE_V1
    def __init__(self, komorebic_path: str | None = None, timeout_secs: float = 5.0):
        if hasattr(self, "_komorebi_initialized"):
            return
        self._komorebi_initialized = True

        super().__init__()

        if komorebic_path is None:
            portable_home = os.getenv("KOMOREBI_PORTABLE_HOME")
            if portable_home:
                candidate = os.path.join(portable_home, "komorebic.exe")
                if os.path.isfile(candidate):
                    komorebic_path = candidate

        self._timeout_secs = timeout_secs
        self._komorebic_path = komorebic_path or "komorebic.exe"
'@

    $oldInit = Normalize-Newlines $oldInit
    $newInit = Normalize-Newlines $newInit

    if (-not $client.Contains($oldInit)) {
        throw "YASB KomorebiClient constructor changed upstream."
    }

    $client = $client.Replace($oldInit,$newInit)
    Set-Content -LiteralPath $clientFile -Value $client -Encoding UTF8
    Write-Host "Applied YASB Komorebi client portable-path + timeout patch." -ForegroundColor Green
}

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    patch = "YASB Komorebi portable integration"
    patch_version = "1.0"
    inspected_yasb_revision = "ebfc0580683d8f27abb98e87019018f0e52cc26d"
    upstream_revision = $revision
    sibling_folder = "../Komorebi"
    client_timeout_seconds = 5.0
    exact_komorebic_path = $true
    path_injected_process_only = $true
} |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $SourceRoot ".yasb-komorebi-portable-integration.json") -Encoding UTF8
