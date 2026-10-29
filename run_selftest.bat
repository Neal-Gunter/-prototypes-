@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

REM ============================================================
REM  XUANJIE - one-click regression self-test
REM  usage: double-click, or run run_selftest.bat in project root
REM  step: (1) old-term audit  (2) compile/launch check  (3) full self-test
REM  require: Godot 4.7.2 console build (see GODOT var below)
REM ============================================================

set "GODOT=D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" (
    set "GODOT=%LOCALAPPDATA%\Godot\Godot_v4.7.2-stable_win64_console.exe"
)
if not exist "%GODOT%" (
    echo [ERR] Godot 4.7.2 console build not found.
    echo       Edit the GODOT var in this script to your actual path.
    pause
    exit /b 1
)

set "PROJECT=%~dp0"
if "%PROJECT:~-1%"=="\" set "PROJECT=%PROJECT:~0,-1%"
set "LOGDIR=%PROJECT%\tools\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

echo ============================================================
echo   XUANJIE one-click regression self-test
echo   project : %PROJECT%
echo   godot   : %GODOT%
echo   log dir : %LOGDIR%
echo ============================================================
echo.

echo [1/3] R17 old-term audit (tools/rename_audit.gd) ...
"%GODOT%" --headless --path "%PROJECT%" --script "res://tools/rename_audit.gd" > "%LOGDIR%\_audit.log" 2>&1
if errorlevel 1 (
    echo   [WARN] old terms found, see tools\logs\_audit.log
) else (
    echo   [OK] audit clean, 0 hits
)
echo.

echo [2/3] compile / launch check (--headless --quit) ...
"%GODOT%" --headless --path "%PROJECT%" --quit > "%LOGDIR%\_check.log" 2>&1
if errorlevel 1 (
    echo   [FAIL] launch check errored, see tools\logs\_check.log
) else (
    echo   [OK] launch check clean
)
echo.

echo [3/3] full self-test (tools/selftest.gd, 196 assertions) ...
"%GODOT%" --headless --path "%PROJECT%" --script "res://tools/selftest.gd" > "%LOGDIR%\_selftest.log" 2>&1
if errorlevel 1 (
    echo   [ERR] self-test aborted, see tools\logs\_selftest.log
) else (
    echo   [DONE] self-test finished, see summary below
)
echo.

echo ------------------------------------------------------------
echo   audit summary:
findstr /C:"PASS R17" /C:"FAIL R17" "%LOGDIR%\_audit.log" 2>nul
echo ------------------------------------------------------------
echo   self-test summary:
findstr /C:"PASS=" "%LOGDIR%\_selftest.log" 2>nul
echo ------------------------------------------------------------
echo.
echo   full per-assertion results: tools\logs\_selftest.log
echo   old-term audit output     : tools\logs\_audit.log
echo   launch check output       : tools\logs\_check.log
echo ------------------------------------------------------------

pause
