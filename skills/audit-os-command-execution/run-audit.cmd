@echo off
REM Wrapper script to run the OS command audit without execution policy issues
REM Usage: run-audit.cmd [arguments]
REM Example: run-audit.cmd -Roots src/base,src/med10 -Mode full

cd /d "%~dp0"
powershell -NoProfile -File ".\generate-os-command-audit.ps1" %*
