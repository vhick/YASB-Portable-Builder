$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$data = Join-Path $root "Data"
$configTarget = Join-Path $data "Config"
$stateTarget = Join-Path $data "LocalState"
$backupRoot = Join-Path $root "MigrationBackups"

New-Item -ItemType Directory -Path $configTarget,$stateTarget,$backupRoot -Force | Out-Null

function Has-Items([string]$Path) {
    return (Test-Path -LiteralPath $Path -PathType Container) -and
        (@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Count -gt 0)
}

function Safe-Copy([string]$Source,[string]$Target,[string]$Label) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = Join-Path $backupRoot ("{0}-{1}" -f $Label,$stamp)

    if (Has-Items $Source) {
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        & robocopy.exe "$Source" "$backup" /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -gt 7) {
            throw "Backup failed for $Source. Robocopy exit code $LASTEXITCODE"
        }

        & robocopy.exe "$Source" "$Target" /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -gt 7) {
            throw "Migration failed for $Source. Robocopy exit code $LASTEXITCODE"
        }

        Write-Host "Migrated: $Source" -ForegroundColor Green
        Write-Host "Backup:   $backup"
    }
}

Write-Host ""
Write-Host "YASB portable data migration" -ForegroundColor Cyan
Write-Host ""

$configCandidates = New-Object System.Collections.Generic.List[string]

$userEnv = [Environment]::GetEnvironmentVariable("YASB_CONFIG_HOME","User")
if (-not [string]::IsNullOrWhiteSpace($userEnv)) {
    $configCandidates.Add($userEnv)
}

if (-not [string]::IsNullOrWhiteSpace($env:YASB_CONFIG_HOME)) {
    $configCandidates.Add($env:YASB_CONFIG_HOME)
}

$configCandidates.Add((Join-Path $HOME ".config\yasb"))

$configSource = $null
foreach ($candidate in ($configCandidates | Select-Object -Unique)) {
    if ((Test-Path -LiteralPath $candidate -PathType Container) -and
        ($candidate.TrimEnd('\') -ine $configTarget.TrimEnd('\'))) {
        if ((Test-Path -LiteralPath (Join-Path $candidate "config.yaml")) -or
            (Test-Path -LiteralPath (Join-Path $candidate "styles.css"))) {
            $configSource = $candidate
            break
        }
    }
}

if (-not $configSource) {
    Write-Host "Automatic config detection did not find an old config directory." -ForegroundColor Yellow
    $manual = Read-Host "Enter the old YASB config folder, or press Enter to skip config migration"

    if (-not [string]::IsNullOrWhiteSpace($manual) -and
        (Test-Path -LiteralPath $manual -PathType Container)) {
        $configSource = $manual
    }
}

if ($configSource) {
    Write-Host "Config source: $configSource"
    Safe-Copy $configSource $configTarget "Config"
}
else {
    Write-Host "No old config was migrated."
}

$stateSource = Join-Path $env:LOCALAPPDATA "YASB"
if (Test-Path -LiteralPath $stateSource -PathType Container) {
    Write-Host "Local state source: $stateSource"
    Safe-Copy $stateSource $stateTarget "LocalState"
}
else {
    Write-Host "No old %LOCALAPPDATA%\YASB folder was found."
}

Write-Host ""
Write-Host "Migration complete." -ForegroundColor Green
Write-Host "Nothing was deleted from the old locations."
Write-Host ""
Write-Host "Start YASB Portable and verify it before running CLEAN-OLD-HOST-DATA.ps1."
Write-Host ""
Write-Host "YASB Cloud note: its cached login uses Windows DPAPI. On this same Windows"
Write-Host "account it may continue to work after migration. After a clean Windows"
Write-Host "installation, sign in to YASB Cloud again."
Write-Host ""
Read-Host "Press Enter to close" | Out-Null
