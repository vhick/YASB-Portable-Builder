$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "YASB old-host cleanup" -ForegroundColor Cyan
Write-Host ""
Write-Host "Run this ONLY after the portable build is working and your data is verified."
Write-Host ""
Write-Host "This can remove known YASB-owned leftovers:"
Write-Host "  %LOCALAPPDATA%\YASB"
Write-Host "  default %USERPROFILE%\.config\yasb"
Write-Host "  old YASB quick-launch TEMP cache"
Write-Host "  HKCU Run\YASB autostart"
Write-Host "  YASB Reborn scheduled task"
Write-Host "  YASB Cloud Automatic Backup scheduled task"
Write-Host "  optional YASB WER LocalDumps key"
Write-Host ""
Write-Host "It does NOT remove fonts or Windows theme settings."
Write-Host ""

$answer = Read-Host "Type DELETE to continue"
if ($answer -cne "DELETE") {
    Write-Host "Cancelled."
    exit 0
}

foreach ($p in @(
    (Join-Path $env:LOCALAPPDATA "YASB"),
    (Join-Path $HOME ".config\yasb"),
    (Join-Path ([IO.Path]::GetTempPath()) "yasb_quick_launch_icons")
)) {
    if (Test-Path -LiteralPath $p) {
        try {
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
            Write-Host "Removed: $p" -ForegroundColor Green
        }
        catch {
            Write-Host "Could not remove: $p" -ForegroundColor Yellow
        }
    }
}

$run = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
try {
    if (Get-ItemProperty -Path $run -Name "YASB" -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $run -Name "YASB" -ErrorAction Stop
        Write-Host "Removed old HKCU Run\YASB entry." -ForegroundColor Green
    }
}
catch {
    Write-Host "Could not remove old HKCU Run entry." -ForegroundColor Yellow
}

foreach ($name in @("YASB Reborn","YASB Cloud Automatic Backup")) {
    try {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
        Write-Host "Removed scheduled task: $name" -ForegroundColor Green
    }
    catch {}
}

$wer = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\yasb.exe"
if (Test-Path $wer) {
    try {
        Remove-Item -Path $wer -Recurse -Force -ErrorAction Stop
        Write-Host "Removed YASB WER LocalDumps key." -ForegroundColor Green
    }
    catch {
        Write-Host "YASB WER LocalDumps key exists but could not be removed without elevation." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "If you previously added YASB_CONFIG_HOME inside your PowerShell profile,"
Write-Host "that profile line is no longer needed. The frozen portable build ignores it."
Write-Host ""
Read-Host "Press Enter to close" | Out-Null
