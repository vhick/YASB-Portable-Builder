param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot,

    [Parameter(Mandatory=$true)]
    [string]$OutputRoot
)

$ErrorActionPreference = "Stop"

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)

if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot "src") -PathType Container)) {
    throw "Expected YASB src folder was not found."
}

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

$report = Join-Path $OutputRoot "YASB-Portability-Inspection.txt"
$sourceOut = Join-Path $OutputRoot "RelevantSource"
$metaOut = Join-Path $OutputRoot "Repository-Metadata"

New-Item -ItemType Directory -Path $sourceOut,$metaOut -Force | Out-Null

Set-Content -LiteralPath $report -Encoding UTF8 -Value @(
    "YASB PORTABILITY SOURCE INSPECTION",
    "Revision: $revision",
    "Generated: $(Get-Date)",
    "",
    "SOURCE CODE ONLY.",
    "This workflow does NOT read your AppData, registry, config.yaml, .env, API keys, tokens, systray cache, or local YASB installation.",
    ""
)

function Add-Section {
    param([string]$Title)

    Add-Content -LiteralPath $report -Encoding UTF8 -Value @(
        "",
        ("=" * 86),
        $Title,
        ("=" * 86)
    )
}

# Keep a few top-level project files because they are important to build/packaging analysis.
foreach ($relative in @(
    "README.md",
    "LICENSE",
    "pyproject.toml",
    "requirements.txt",
    "schema.json",
    ".python-version"
)) {
    $src = Join-Path $SourceRoot $relative
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $metaOut ($relative -replace '[\\/:*?"<>|]','_')) -Force
    }
}

# Always include the most important known files if present.
$priorityFiles = @(
    "src\settings.py",
    "src\build.py",
    "src\main.py"
)

foreach ($relative in $priorityFiles) {
    $src = Join-Path $SourceRoot $relative
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $dest = Join-Path $sourceOut $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dest -Force
    }
}

$groups = [ordered]@{
    "CONFIGURATION ROOT" = @(
        "YASB_CONFIG_HOME",
        "DEFAULT_CONFIG_DIRECTORY",
        ".config",
        "config.yaml",
        "styles.css",
        ".env",
        "dotenv"
    )

    "WINDOWS LOCALAPPDATA / APPDATA" = @(
        "LOCALAPPDATA",
        "APPDATA",
        "LocalAppData",
        "AppData",
        "os.getenv(",
        "os.environ[",
        "expandvars",
        "Path.home()"
    )

    "YASB LOCAL STATE / CACHE FILES" = @(
        "systray_state_",
        "last_update_check",
        "github_token",
        "weather",
        "cache",
        "state",
        "token",
        "sqlite",
        ".json"
    )

    "TEMP / DUMPS / LOGGING" = @(
        "tempfile",
        "gettempdir",
        "TEMP",
        "TMP",
        "dump",
        "crash",
        "log",
        "RotatingFileHandler",
        "FileHandler"
    )

    "AUTOSTART / TASK SCHEDULER / REGISTRY" = @(
        "enable-autostart",
        "disable-autostart",
        "Task Scheduler",
        "schtasks",
        "startup",
        "winreg",
        "HKEY_",
        "HKCU",
        "CurrentVersion\\Run",
        "registry"
    )

    "UPDATER / UPDATE STATE" = @(
        "update_check",
        "last_update_check",
        "yasbc update",
        "set-channel",
        "update channel",
        "github.com/amnweb/yasb/releases",
        "download",
        "installer"
    )

    "BUILD / CX_FREEZE / MSI" = @(
        "cx_Freeze",
        "Executable(",
        "build_exe",
        "bdist_msi",
        "msi",
        "yasb.exe",
        "yasbc.exe",
        "yasb_themes.exe",
        "AppUserModelID",
        "URL Protocol"
    )

    "ABSOLUTE INSTALL PATH ASSUMPTIONS" = @(
        "sys.executable",
        "sys._MEIPASS",
        "sys.frozen",
        "__file__",
        "installation",
        "install_dir",
        "PROGRAMFILES",
        "Program Files"
    )
}

$extensions = @(
    ".py",".toml",".json",".yaml",".yml",".md",".txt"
)

$roots = @(
    (Join-Path $SourceRoot "src"),
    (Join-Path $SourceRoot "docs")
)

$allFiles = @()

foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

    $allFiles += Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in $extensions }
}

$candidateMap = @{}

foreach ($group in $groups.GetEnumerator()) {
    Add-Section $group.Key
    $groupHit = $false

    foreach ($file in $allFiles) {
        $lines = Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue
        if ($null -eq $lines) { continue }

        for ($i=0; $i -lt $lines.Count; $i++) {
            $line = [string]$lines[$i]
            $hitTerm = $null

            foreach ($term in $group.Value) {
                if ($line.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $hitTerm = $term
                    break
                }
            }

            if (-not $hitTerm) { continue }

            $groupHit = $true
            $candidateMap[$file.FullName] = $true

            $rel = $file.FullName.Substring($SourceRoot.Length).TrimStart('\')
            $from = [Math]::Max(0,$i-5)
            $to = [Math]::Min($lines.Count-1,$i+10)

            Add-Content -LiteralPath $report -Encoding UTF8 `
                -Value ("--- {0} | match: {1} | line {2} ---" -f $rel,$hitTerm,($i+1))

            for ($j=$from; $j -le $to; $j++) {
                Add-Content -LiteralPath $report -Encoding UTF8 `
                    -Value ("{0,5}: {1}" -f ($j+1),$lines[$j])
            }

            Add-Content -LiteralPath $report -Encoding UTF8 -Value ""
        }
    }

    if (-not $groupHit) {
        Add-Content -LiteralPath $report -Encoding UTF8 -Value "No matches found."
    }
}

# Copy every matched source file so ChatGPT can inspect full context instead of snippets only.
foreach ($filePath in ($candidateMap.Keys | Sort-Object)) {
    $rel = $filePath.Substring($SourceRoot.Length).TrimStart('\')
    $dest = Join-Path $sourceOut $rel

    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $filePath -Destination $dest -Force
}

Add-Section "SUMMARY FOR NEXT STEP"

Add-Content -LiteralPath $report -Encoding UTF8 -Value @(
    "Known from current YASB documentation:",
    "- YASB_CONFIG_HOME redirects the main config directory.",
    "- Some runtime state is documented/observed under %LOCALAPPDATA%\\YASB.",
    "- The official project builds with cx_Freeze and can build before the MSI packaging step.",
    "",
    "This inspection is intended to identify every remaining host-specific state writer before a source-level portable patch is created.",
    "",
    "Upload the entire YASB-Portable-Inspection-<commit> artifact to ChatGPT."
)

Set-Content -LiteralPath (Join-Path $OutputRoot "UPSTREAM-REVISION.txt") `
    -Encoding UTF8 `
    -Value $revision

Write-Host ""
Write-Host "YASB portability inspection complete." -ForegroundColor Green
Write-Host "Output:"
Write-Host "  $OutputRoot"
