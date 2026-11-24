# Opens the master (dispatcher) session from Windows PowerShell.
# Model and effort come from .claude\dispatcher.conf (MASTER_MODEL, MASTER_EFFORT; empty effort = model default).
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '.claude\scripts\lib-conf.ps1')
$model  = Get-DispatchConf 'MASTER_MODEL' 'opus'
$effort = Get-DispatchConf 'MASTER_EFFORT' ''
Set-Location -LiteralPath $here
$cargs = @('--agent', 'dispatcher', '--model', $model, '--name', 'master')
if ($effort) { $cargs += @('--effort', $effort) }
& claude @cargs 'Master start: arm the alert monitor and summarize the open tickets in one line.'
exit $LASTEXITCODE
