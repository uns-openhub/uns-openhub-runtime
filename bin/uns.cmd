@echo off
setlocal
for %%I in ("%~dp0..") do set "UNS_RUNTIME_ROOT=%%~fI"
for /f "usebackq delims=" %%F in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime-download.ps1" uns`) do set "UNS_EXE=%%F"
if not defined UNS_EXE (
  echo Unable to resolve UNS CLI release binary. 1>&2
  exit /b 2
)
"%UNS_EXE%" %*
