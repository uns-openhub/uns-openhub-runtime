@echo off
setlocal
set "BIN_DIR=%~dp0"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
  set "UNS_EXE=%BIN_DIR%uns-windows-arm64.exe"
) else (
  set "UNS_EXE=%BIN_DIR%uns-windows-amd64.exe"
)
if not exist "%UNS_EXE%" (
  echo Missing executable: %UNS_EXE% 1>&2
  exit /b 2
)
"%UNS_EXE%" %*
