@echo off
setlocal
set "BIN_DIR=%~dp0"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
  set "ROTATOR_EXE=%BIN_DIR%infisical-rotator-windows-arm64.exe"
) else (
  set "ROTATOR_EXE=%BIN_DIR%infisical-rotator-windows-amd64.exe"
)
if not exist "%ROTATOR_EXE%" (
  echo Missing executable: %ROTATOR_EXE% 1>&2
  exit /b 2
)
"%ROTATOR_EXE%" %*
