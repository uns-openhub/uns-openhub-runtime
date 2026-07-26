@echo off
setlocal
for /f "usebackq delims=" %%F in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime-download.ps1" infisical-rotator`) do set "ROTATOR_EXE=%%F"
if not defined ROTATOR_EXE (
  echo Unable to resolve Infisical rotator release binary. 1>&2
  exit /b 2
)
"%ROTATOR_EXE%" %*
