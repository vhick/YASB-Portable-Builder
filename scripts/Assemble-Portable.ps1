param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot,

    [Parameter(Mandatory=$true)]
    [string]$OutputRoot,

    [Parameter(Mandatory=$true)]
    [string]$KitRoot
)

$ErrorActionPreference = "Stop"

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$dist = Join-Path $SourceRoot "src\dist"

if (-not (Test-Path -LiteralPath $dist -PathType Container)) {
    throw "cx_Freeze dist folder was not found: $dist"
}

foreach ($exe in @("yasb.exe","yasbc.exe","yasb_themes.exe","yasb_cloud.exe")) {
    if (-not (Test-Path -LiteralPath (Join-Path $dist $exe) -PathType Leaf)) {
        throw "Expected cx_Freeze executable is missing: $exe"
    }
}

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

# Copy every file required by cx_Freeze.
Get-ChildItem -LiteralPath $dist -Force |
    Copy-Item -Destination $OutputRoot -Recurse -Force

foreach ($dir in @(
    "Data\Config",
    "Data\LocalState",
    "Data\Temp"
)) {
    New-Item -ItemType Directory -Path (Join-Path $OutputRoot $dir) -Force | Out-Null
}

foreach ($name in @(
    "LAUNCH-YASB-PORTABLE.cmd",
    "INSTALL-PORTABLE-STARTUP.cmd",
    "REMOVE-PORTABLE-STARTUP.cmd",
    "VERIFY-PORTABLE.ps1",
    "MIGRATE-OFFICIAL-DATA.ps1",
    "CLEAN-OLD-HOST-DATA.ps1"
)) {
    Copy-Item -LiteralPath (Join-Path $KitRoot "portable\$name") `
        -Destination (Join-Path $OutputRoot $name) `
        -Force
}

$patchMarker = Join-Path $SourceRoot ".yasb-true-portable-patch.json"

if (-not (Test-Path -LiteralPath $patchMarker -PathType Leaf)) {
    throw "True-portable patch marker was not found."
}

Copy-Item -LiteralPath $patchMarker `
    -Destination (Join-Path $OutputRoot "TRUE-PORTABLE-PATCH.json") `
    -Force

$revision = (git -C $SourceRoot rev-parse HEAD).Trim()

[ordered]@{
    mode = "true-portable-cxfreeze"
    upstream_revision = $revision
    built_at = (Get-Date).ToString("o")
    config_root = "./Data/Config"
    local_state_root = "./Data/LocalState"
    temp_root = "./Data/Temp"
    installer_used = $false
    msi_registry_written = $false
    built_in_updater = $false
    built_in_registry_autostart = $false
    built_in_cloud_scheduled_task = $false
    cloud_dpapi_note = "YASB Cloud session.bin/vault.bin remain Windows-DPAPI protected; re-authenticate after clean Windows install or on another account."
} |
    ConvertTo-Json -Depth 7 |
    Set-Content -LiteralPath (Join-Path $OutputRoot "PORTABLE-BUILD.json") -Encoding UTF8

Set-Content -LiteralPath (Join-Path $OutputRoot "SOURCE-REVISION.txt") `
    -Encoding UTF8 `
    -Value @(
        "Source: synced yasb fork",
        "Upstream: https://github.com/amnweb/yasb",
        "Revision: $revision",
        "Built: $(Get-Date)",
        "Packaging: raw cx_Freeze build folder (no MSI)"
    )

$license = Join-Path $SourceRoot "LICENSE"
if (Test-Path -LiteralPath $license -PathType Leaf) {
    Copy-Item -LiteralPath $license `
        -Destination (Join-Path $OutputRoot "LICENSE-UPSTREAM.txt") `
        -Force
}

Write-Host ""
Write-Host "Portable package assembled:" -ForegroundColor Green
Write-Host "  $OutputRoot"
