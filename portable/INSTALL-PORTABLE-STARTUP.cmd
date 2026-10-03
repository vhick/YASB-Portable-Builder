@echo off
setlocal EnableExtensions
title YASB Portable Startup Setup

set "ROOT=%~dp0"
set "LAUNCHER=%ROOT%LAUNCH-YASB-PORTABLE.cmd"
set "DATADIR=%ROOT%Data"
set "VBS=%DATADIR%\Start-YASB-Portable-Hidden.vbs"

if not exist "%DATADIR%" mkdir "%DATADIR%"

> "%VBS%" echo Set sh = CreateObject("WScript.Shell")
>>"%VBS%" echo sh.CurrentDirectory = "%ROOT%"
>>"%VBS%" echo sh.Run Chr(34) ^& "%LAUNCHER%" ^& Chr(34), 0, False

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Continue';" ^
  "$run='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';" ^
  "if(Get-ItemProperty -Path $run -Name 'YASB' -ErrorAction SilentlyContinue){Remove-ItemProperty -Path $run -Name 'YASB' -ErrorAction SilentlyContinue;Write-Host 'Removed old YASB registry autostart.'};" ^
  "foreach($n in @('YASB Reborn')){try{Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction Stop;Write-Host ('Removed old scheduled task: '+$n)}catch{}};" ^
  "$startup=[Environment]::GetFolderPath('Startup');" ^
  "$lnk=Join-Path $startup 'YASB-Portable.lnk';" ^
  "$w=New-Object -ComObject WScript.Shell;" ^
  "$s=$w.CreateShortcut($lnk);" ^
  "$s.TargetPath=$env:WINDIR+'\System32\wscript.exe';" ^
  "$s.Arguments='\"%VBS%\"';" ^
  "$s.WorkingDirectory='%ROOT%';" ^
  "$s.Description='YASB Portable';" ^
  "$s.Save();" ^
  "Write-Host ('Created: '+$lnk)"

echo.
echo Portable YASB startup is installed.
echo Use this portable startup method instead of yasbc enable-autostart.
echo.
pause
