@echo off
setlocal
for /f "usebackq delims=" %%F in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0runtime-download.ps1" uns-backup-helper`) do set "UNS_BACKUP_HELPER_EXE=%%F"
if not defined UNS_BACKUP_HELPER_EXE (
  echo Unable to resolve UNS backup helper release binary. 1>&2
  exit /b 2
)
"%UNS_BACKUP_HELPER_EXE%" %*
