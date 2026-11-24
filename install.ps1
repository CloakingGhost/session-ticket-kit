# Installer entry point for Windows PowerShell. It finds Git Bash and runs install.sh with the same arguments,
# so there is one installer implementation for every OS.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 --target "C:\work\my project" --yes --prefix TK
#   install.cmd            (double-click or run from cmd; calls this script)
#
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.
$ErrorActionPreference = 'Stop'

function Find-GitBash {
    $cands = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) { $cands += (Join-Path (Split-Path -Parent (Split-Path -Parent $git.Source)) 'bin\bash.exe') }
    foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    return $null
}

$bash = Find-GitBash
if (-not $bash) {
    Write-Error "Git Bash was not found. Install Git for Windows (https://git-scm.com/download/win), then run this again. (Do not use the WSL bash.exe in System32.)"
    exit 1
}

# Forward slashes are accepted by Git Bash and avoid backslash-escape surprises.
$script = (Join-Path $PSScriptRoot 'install.sh') -replace '\\', '/'
& $bash $script @args
exit $LASTEXITCODE
