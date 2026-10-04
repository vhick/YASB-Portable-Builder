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

rem Prefer a user-supplied process-local Komorebi path, otherwise a sibling folder.
if not defined KOMOREBI_PORTABLE_HOME set "KOMOREBI_PORTABLE_HOME=%ROOT%..\Komorebi"

if exist "%KOMOREBI_PORTABLE_HOME%\komorebic.exe" (
    for %%I in ("%KOMOREBI_PORTABLE_HOME%") do set "KOMOREBI_PORTABLE_HOME=%%~fI"
    set "KOMOREBI_PORTABLE_CONFIG_HOME=%KOMOREBI_PORTABLE_HOME%\Data\Config"
    set "WHKD_PORTABLE_CONFIG_HOME=%KOMOREBI_PORTABLE_HOME%\Data\Config"
    set "KOMOREBI_DATA_HOME=%KOMOREBI_PORTABLE_HOME%\Data\LocalState"
    set "KOMOREBI_TEMP_HOME=%KOMOREBI_PORTABLE_HOME%\Data\Temp"
    set "PATH=%KOMOREBI_PORTABLE_HOME%;%PATH%"
)

echo.>>"%LOG%"
echo ==== %date% %time% YASB Portable launch ====>>"%LOG%"
echo EXE=%EXE%>>"%LOG%"
echo CONFIG=%CONFIG%>>"%LOG%"
echo KOMOREBI_PORTABLE_HOME=%KOMOREBI_PORTABLE_HOME%>>"%LOG%"

if not exist "%EXE%" (
  echo ERROR: yasb.exe not found.>>"%LOG%"
  echo ERROR: yasb.exe was not found beside this launcher.
  pause
  exit /b 1
)

tasklist /FI "IMAGENAME eq yasb.exe" 2>NUL | find /I "yasb.exe" >NUL
if not errorlevel 1 exit /b 0

start "" "%EXE%"
exit /b 0
