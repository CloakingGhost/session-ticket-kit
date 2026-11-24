@echo off
rem Opens the master (dispatcher) session. Reads model/effort from .claude\dispatcher.conf via PowerShell.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open-master.ps1" %*
