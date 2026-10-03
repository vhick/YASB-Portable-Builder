@echo off
setlocal EnableExtensions
title YASB Portable

set "ROOT=%~dp0"
set "EXE=%ROOT%yasb.exe"
set "DATA=%ROOT%Data"
set "CONFIG=%DATA%\Config"
set "TEMPPORT=%DATA%\Temp"
set "LOGDIR=%ROOT%LauncherLogs"
set "LOG=%LOGDIR%\Launch.log"

if not exist "%CONFIG%" mkdir "%CONFIG%" >nul 2>&1
if not exist "%DATA%\LocalState" mkdir "%DATA%\LocalState" >nul 2>&1
if not exist "%TEMPPORT%" mkdir "%TEMPPORT%" >nul 2>&1
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

set "YASB_CONFIG_HOME=%CONFIG%"
set "TEMP=%TEMPPORT%"
set "TMP=%TEMPPORT%"

echo.>>"%LOG%"
echo ==== %date% %time% YASB Portable launch ====>>"%LOG%"
echo EXE=%EXE%>>"%LOG%"
echo CONFIG=%CONFIG%>>"%LOG%"
echo TEMP=%TEMPPORT%>>"%LOG%"

if not exist "%EXE%" (
  echo ERROR: yasb.exe not found.>>"%LOG%"
  echo.
  echo ERROR: yasb.exe was not found beside this launcher.
  echo.
  pause
  exit /b 1
)

tasklist /FI "IMAGENAME eq yasb.exe" 2>NUL | find /I "yasb.exe" >NUL
if not errorlevel 1 (
  echo YASB is already running.>>"%LOG%"
  exit /b 0
)

start "" "%EXE%"
exit /b 0
