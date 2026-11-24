# Environment check for the dispatcher kit (Windows PowerShell 5.1 / PowerShell 7).
# READ-ONLY: never installs or changes anything. Runs only version/help commands and `claude mcp list`
# (which makes a network health check). Tokens are never printed.
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File check-env.ps1 [-Project DIR]
# Output: one line per item: [OK] / [WARN] / [FAIL] name: detail, then "  fix: ..." for WARN and FAIL.
# Exit code: 1 if any FAIL, else 0.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.
param([string]$Project = '')

$script:Fails = 0
$script:Warns = 0
function Ok($n, $d)        { Write-Output ("[OK]   {0}: {1}" -f $n, $d) }
function Warn($n, $d, $f)  { $script:Warns++; Write-Output ("[WARN] {0}: {1}" -f $n, $d); Write-Output ("       fix: {0}" -f $f) }
function Fail($n, $d, $f)  { $script:Fails++; Write-Output ("[FAIL] {0}: {1}" -f $n, $d); Write-Output ("       fix: {0}" -f $f) }
function Have($n)          { return [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Run($exe, $argList) {
    # runs a native command, returns @{ Code; Out } without throwing on stderr output
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & $exe @argList 2>&1 | Out-String; $code = $LASTEXITCODE } catch { $out = $_.Exception.Message; $code = 1 }
    $ErrorActionPreference = $old
    return @{ Code = $code; Out = $out.Trim() }
}

# project folder: given, or auto-detect (<project>\.claude\scripts\check-env.ps1)
if (-not $Project) {
    $parent = Split-Path -Parent $PSScriptRoot
    # installed layout only: the folder above scripts\ must be named .claude (in the kit it is payload\claude, not a project)
    if ((Split-Path -Leaf $parent) -eq '.claude') {
        $Project = Split-Path -Parent $parent
    }
}
if ($Project) {
    if (-not (Test-Path -LiteralPath $Project -PathType Container)) { Write-Error "project folder not found: $Project"; exit 2 }
    $Project = (Resolve-Path -LiteralPath $Project).Path
}

# 1. OS and shell
$os = [System.Environment]::OSVersion
$isWin = ($os.Platform -eq 'Win32NT')
if ($isWin) { Ok 'os' ("Windows {0}, PowerShell {1}" -f $os.Version, $PSVersionTable.PSVersion) }
else { Warn 'os' ("{0}: this is the Windows check" -f $os.Platform) 'Use check-env.sh on macOS/Linux' }

# 2. bash (Git Bash). The scripts and hooks of this kit are bash scripts.
$gitBash = $null
$cands = @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) { $cands += (Join-Path (Split-Path -Parent (Split-Path -Parent $gitCmd.Source)) 'bin\bash.exe') }
foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { $gitBash = $c; break } }
if ($gitBash) {
    # `bash --version` (not `bash -c '${...}'`: Windows PowerShell 5.1 mangles quotes and braces in native arguments)
    $r = Run $gitBash @('--version')
    $ver = 'unknown'
    if ($r.Out -match 'version (\d+\.\d+)') { $ver = $Matches[1] }
    Ok 'bash' ("Git Bash {0} at {1}" -f $ver, $gitBash)
    if ($ver -match '^(\d+)\.(\d+)$' -and (([int]$Matches[1] -lt 3) -or ([int]$Matches[1] -eq 3 -and [int]$Matches[2] -lt 2))) {
        Fail 'bash' "version $ver is too old (need 3.2+)" 'Update Git for Windows'
    }
} else {
    Fail 'bash' 'Git Bash not found (the kit scripts and hooks need it)' 'Install Git for Windows from https://git-scm.com/download/win (includes Git Bash)'
}
$wsl = Join-Path $env:SystemRoot 'System32\bash.exe'
if (Test-Path -LiteralPath $wsl) {
    Warn 'bash' 'a WSL bash.exe exists in System32; do not use it for this kit' 'Run kit scripts from Git Bash, or call Git Bash by full path'
}

# 3. claude CLI
$F0 = $script:Fails
if (Have 'claude') {
    $v = Run 'claude' @('--version'); Ok 'claude' (($v.Out -split "`n")[0])
    $help = (Run 'claude' @('--help')).Out
    foreach ($opt in '--bg', '--agent', '--name', '--model', '--effort', '--settings', '--permission-mode') {
        if ($help -notmatch [regex]::Escape($opt)) { Fail "claude option $opt" "this Claude Code version does not list $opt" 'Update Claude Code (claude update)' }
    }
    foreach ($sub in 'agents', 'logs', 'attach', 'stop', 'rm') {
        $s = Run 'claude' @($sub, '--help')
        if ($s.Code -ne 0) { Fail "claude $sub" 'subcommand not available' 'Update Claude Code (claude update)' }
    }
    if ($script:Fails -eq $F0) { Ok 'claude features' '--bg, --agent, --settings and agents/logs/attach/stop/rm are available' }
} else {
    Fail 'claude' 'not found on PATH' 'Install Claude Code (see https://code.claude.com/docs) and open a new terminal'
}

# 4. git
if (Have 'git') { Ok 'git' ((Run 'git' @('--version')).Out) } else { Fail 'git' 'not found' 'Install Git for Windows' }

# 5. gh
if (Have 'gh') {
    $a = Run 'gh' @('auth', 'status')
    if ($a.Code -eq 0) { Ok 'gh' ('{0}, logged in' -f ((Run 'gh' @('--version')).Out -split "`n")[0]) }
    else { Warn 'gh' 'installed but not logged in' "Run 'gh auth login' (needed only for PR status in ticket-sync)" }
} else {
    Warn 'gh' 'not found' "Install GitHub CLI and run 'gh auth login' (needed only for PR status in ticket-sync)"
}

# 6. time
$utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$off = (Get-Date).ToString('zzz')
Ok 'time' ("UTC {0}, system offset {1}" -f $utc, $off)
Warn 'time zone' "Git Bash 'date' ignores TZ and shows UTC" 'Set TIMEZONE_OFFSET (e.g. +09:00) in .claude\dispatcher.conf; scripts compute local time from it'

# 7. project files
if (-not $Project) {
    Warn 'project' 'no project folder given or detected (kit not installed yet?)' "Run install first, then check-env from <project>\.claude\scripts, or pass -Project DIR"
} else {
    $C = Join-Path $Project '.claude'
    foreach ($f in 'agents\dispatcher.md', 'skills\dispatch\SKILL.md', 'skills\ticket-sync\SKILL.md', 'scripts\open-session.sh', 'scripts\alert.sh', 'scripts\watch-alerts.sh', 'scripts\now.sh', 'scripts\lib-conf.sh') {
        if (-not (Test-Path -LiteralPath (Join-Path $C $f))) { Fail "file .claude\$f" 'missing' 'Re-run the installer for this project' }
    }
    if (Test-Path -LiteralPath (Join-Path $C 'agents\dispatcher.md')) { Ok 'kit files' "agent, skills and scripts present under $C" }

    # line endings: CR in a .sh file breaks bash on macOS/Linux and can break Git Bash
    $crBad = @()
    $shFiles = @(Get-ChildItem -LiteralPath (Join-Path $C 'scripts') -Filter '*.sh' -File -ErrorAction SilentlyContinue)
    $om = Join-Path $Project 'open-master.sh'; if (Test-Path -LiteralPath $om) { $shFiles += Get-Item -LiteralPath $om }
    foreach ($f in $shFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        if (($bytes | Where-Object { $_ -eq 13 } | Select-Object -First 1) -ne $null) { $crBad += $f.Name }
    }
    if ($crBad.Count -gt 0) { Fail 'line endings' ("CR characters found in: {0}" -f ($crBad -join ', ')) 'Convert to LF and keep *.sh as eol=lf in git (.gitattributes)' }
    else { Ok 'line endings' 'shell scripts use LF' }

    # 8. config
    $conf = Join-Path $C 'dispatcher.conf'
    if (-not (Test-Path -LiteralPath $conf)) {
        Fail 'config' "$conf not found" 'Re-run the installer, or copy dispatcher.conf.example to .claude\dispatcher.conf and fill it in'
    } else {
        . (Join-Path $C 'scripts\lib-conf.ps1')
        $env:DISPATCH_CONF = $conf
        $text = Get-Content -LiteralPath $conf -Raw -Encoding UTF8
        if ($text -match '(ntn_|secret_|ghp_|gho_|github_pat_|sk-ant-|xox[bp]-)[A-Za-z0-9_-]{8,}') {
            Fail 'config secrets' 'dispatcher.conf contains something that looks like a token' 'Remove it. This file must not hold keys or tokens'
        } else { Ok 'config secrets' 'no token-like values' }
        $p = Get-DispatchConf 'TICKET_PREFIX' ''
        if ($p -match '^[A-Za-z][A-Za-z0-9]{1,9}$') { Ok 'config TICKET_PREFIX' $p } else { Fail 'config TICKET_PREFIX' "'$p' is empty or invalid" "Use 2-10 letters/digits starting with a letter, e.g. TK (Notion's Unique ID prefix needs 2-10 characters)" }
        $tz = Get-DispatchConf 'TIMEZONE_OFFSET' ''
        if ($tz -match '^[+-]\d{2}:\d{2}$') { Ok 'config TIMEZONE_OFFSET' $tz } else { Fail 'config TIMEZONE_OFFSET' "'$tz' is not +HH:MM" 'Set e.g. +09:00' }
        $rd = Get-DispatchConf 'REPO_DIR' ''
        if (-not $rd) { Warn 'config REPO_DIR' 'empty: PR/branch features are off' "Set it to the git repository folder relative to the project ('.' if the project itself is the repo)" }
        elseif ($rd -match '^([A-Za-z]:|/|\\)' -or $rd -match '\.\.') { Fail 'config REPO_DIR' "'$rd' must be a relative folder inside the project" "Use e.g. 'myrepo' or '.'" }
        else {
            $g = Run 'git' @('-C', (Join-Path $Project $rd), 'rev-parse', '--git-dir')
            if ($g.Code -eq 0) { Ok 'config REPO_DIR' "$rd is a git repository" } else { Fail 'config REPO_DIR' "$(Join-Path $Project $rd) is not a git repository" 'Fix REPO_DIR or run git init/clone there' }
        }
        $nds = Get-DispatchConf 'NOTION_DATA_SOURCE_ID' ''
        if (-not $nds) { Warn 'config NOTION_DATA_SOURCE_ID' 'empty' 'Create the Notion database (docs/NOTION-SCHEMA.md in the kit) and paste its data source ID here' }
        elseif ($nds -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { Ok 'config NOTION_DATA_SOURCE_ID' 'set (UUID format)' }
        else { Fail 'config NOTION_DATA_SOURCE_ID' 'not a UUID' "Use the ID from the 'collection://...' URL, without the 'collection://' prefix" }
        $mm = Get-DispatchConf 'MASTER_MODEL' 'opus'
        Ok 'config MASTER_MODEL' "$mm (some models need a plan or usage credits; test with: claude --model $mm)"
    }
}

# 9. Notion MCP (as far as it can be checked)
if (Have 'claude') {
    $m = Run 'claude' @('mcp', 'list')
    $notion = @($m.Out -split "`n" | Where-Object { $_ -match 'notion' })
    if ($notion.Count -gt 0) {
        if ($notion | Where-Object { $_ -match 'onnected' -and $_ -notmatch 'ot connected|isconnected' }) { Ok 'notion mcp' 'a Notion MCP server is listed and connected' }
        else { Warn 'notion mcp' 'a Notion MCP server is listed but not connected' 'Reconnect it (claude.ai Settings > Connectors, or /mcp inside a session)' }
    } else {
        Warn 'notion mcp' "no Notion MCP server found in 'claude mcp list'" 'Connect Notion: claude.ai Settings > Connectors > Notion (or add a local MCP server named notion). This check cannot see every setup'
    }
}

Write-Output ''
Write-Output ("Summary: {0} FAIL, {1} WARN" -f $script:Fails, $script:Warns)
if ($script:Fails -gt 0) { exit 1 } else { exit 0 }
