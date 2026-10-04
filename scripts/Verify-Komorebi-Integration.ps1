param(
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"

$settings = Get-Content -LiteralPath (Join-Path $SourceRoot "src\settings.py") -Raw
$client = Get-Content -LiteralPath (Join-Path $SourceRoot "src\core\widgets\services\komorebi\client.py") -Raw
$listener = Get-Content -LiteralPath (Join-Path $SourceRoot "src\core\widgets\services\komorebi\event_listener.py") -Raw

$checks = [ordered]@{
    "settings integration marker" = $settings.Contains("YASB_KOMOREBI_PORTABLE_INTEGRATION_V1")
    "sibling Komorebi discovery" = $settings.Contains('os.path.join(SCRIPT_PATH, os.pardir, "Komorebi")')
    "KOMOREBI_DATA_HOME process env" = $settings.Contains('"KOMOREBI_DATA_HOME"')
    "Komorebi folder added to PATH" = $settings.Contains('os.environ["PATH"]')
    "client integration marker" = $client.Contains("YASB_KOMOREBI_CLIENT_PORTABLE_V1")
    "exact komorebic candidate" = $client.Contains('os.path.join(portable_home, "komorebic.exe")')
    "state-query timeout 5 seconds" = $client.Contains("timeout_secs: float = 5.0")
    "named-pipe subscribe retained" = $client.Contains('"subscribe", pipe_name')
    "event listener retained" = $listener.Contains("Komorebi connected to named pipe")
}

$failed = @()
foreach ($entry in $checks.GetEnumerator()) {
    if ($entry.Value) {
        Write-Host "PASS: $($entry.Key)" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL: $($entry.Key)" -ForegroundColor Red
        $failed += $entry.Key
    }
}

if ($failed.Count -gt 0) {
    throw "YASB Komorebi integration verification failed: $($failed -join ', ')"
}

Write-Host ""
Write-Host "YASB Komorebi integration verification PASS." -ForegroundColor Green
