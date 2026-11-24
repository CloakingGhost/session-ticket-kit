# Helper for reading dispatcher.conf from PowerShell (dot-source it).
#   . "$PSScriptRoot\lib-conf.ps1"; Get-DispatchConf 'MASTER_MODEL' 'opus'
# Format: KEY=value, one per line, '#' starts a comment line. Values are never executed. No secrets here.
# Location: $env:DISPATCH_CONF, else <this folder>\..\dispatcher.conf
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.
function Get-DispatchConf {
    param(
        [Parameter(Mandatory)][string]$Key,
        [string]$Default = ''
    )
    if ($Key -notmatch '^[A-Za-z0-9_]+$') { throw "bad key: $Key" }
    $conf = $env:DISPATCH_CONF
    if (-not $conf) { $conf = Join-Path (Split-Path -Parent $PSScriptRoot) 'dispatcher.conf' }
    if (Test-Path -LiteralPath $conf) {
        $line = Get-Content -LiteralPath $conf -Encoding UTF8 |
            Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -Last 1
        if ($line) {
            $v = ($line -replace '^[^=]*=', '').Trim()
            if ($v.Length -ge 2 -and (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'")))) {
                $v = $v.Substring(1, $v.Length - 2)
            }
            if ($v) { return $v }
        }
    }
    return $Default
}
