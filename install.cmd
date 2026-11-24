@echo off
rem Installer entry point for cmd.exe / double-click. Runs install.ps1, which runs install.sh through Git Bash.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
