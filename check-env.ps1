# Environment check you can run BEFORE installing (Windows PowerShell). Read-only.
# After installing, use <project>\.claude\scripts\check-env.ps1 instead (it also checks the project's config).
#   powershell -NoProfile -ExecutionPolicy Bypass -File check-env.ps1 [-Project DIR]
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.
& (Join-Path $PSScriptRoot 'payload\claude\scripts\check-env.ps1') @args
exit $LASTEXITCODE
