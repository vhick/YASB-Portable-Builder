param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$Engine = Join-Path $PSScriptRoot "Patch-YASB-Portable.py"

if (-not (Test-Path -LiteralPath $Engine -PathType Leaf)) {
    throw "Portable patch engine is missing: $Engine"
}

Write-Host "YASB portable source preflight (all patch targets)..." -ForegroundColor Cyan
& python $Engine --source-root $SourceRoot --check-only
if ($LASTEXITCODE -ne 0) {
    throw "Portable source preflight failed. No upstream source files were changed."
}

Write-Host "Applying complete YASB true-portable patch..." -ForegroundColor Cyan
& python $Engine --source-root $SourceRoot
if ($LASTEXITCODE -ne 0) {
    throw "YASB portable patch failed. Check the named file/function in the log."
}

Write-Host "YASB source patch v1.4 completed." -ForegroundColor Green
