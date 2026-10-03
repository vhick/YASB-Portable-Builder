@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$lnk=Join-Path ([Environment]::GetFolderPath('Startup')) 'YASB-Portable.lnk';" ^
  "if(Test-Path -LiteralPath $lnk){Remove-Item -LiteralPath $lnk -Force;Write-Host ('Removed: '+$lnk)}else{Write-Host 'Portable startup shortcut already absent.'}"
pause
