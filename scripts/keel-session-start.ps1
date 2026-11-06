<#
    keel-session-start.ps1 - the SessionStart nudge.

    Charter P16: silence is a success. This prints NOTHING on a clean session.
    Charter P13: this is the bottom rung of the enforcement ladder - it nudges,
    it never blocks.
    Charter P10: it does not reimplement any status logic. It runs the wrapper and
    surfaces only the actionable lines, so there is one implementation of "what is
    wrong here", not two that can disagree.

    Windows PowerShell 5.1 compatible. ASCII only.
#>

$ErrorActionPreference = 'SilentlyContinue'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Wrapper  = Join-Path $RepoRoot 'plugins\keel-workflow\skills\keel-orchestrator\wrappers\keel-state.ps1'

$out = @()

# --- self-heal the git hooks path in this repo -------------------------------
if (Test-Path -LiteralPath (Join-Path $RepoRoot '.git')) {
    $current = & git -C $RepoRoot config core.hooksPath 2>$null
    if ($current -ne '.githooks') {
        & git -C $RepoRoot config core.hooksPath .githooks 2>$null | Out-Null
        $out += 'keel: re-pointed core.hooksPath at .githooks'
    }
}

# --- surface only the actionable lines from the active project ---------------
if (Test-Path -LiteralPath $Wrapper) {
    $status = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Wrapper status -Brief 2>$null
    if ($LASTEXITCODE -eq 0) {
        foreach ($line in @($status)) {
            # -cmatch, CASE-SENSITIVE, and that is load-bearing rather than tidy. The three
            # unpushed-commit tokens below are upper-case on purpose: under the
            # case-INSENSITIVE -match, 'have NOT reached' also matches the 'next:' line,
            # whose text is a phase's scope - a phase whose scope happens to contain the
            # words 'have not reached the remote' would be forwarded as though it were a
            # finding. Every other token still matches case-sensitively: WARNING, STOP:,
            # OVERDUE: and CHASE: are printed upper-case, and 'open signal' is printed
            # lower-case, exactly as written here.
            #
            # Why the unpushed lines are here at all: status reads the remote on every
            # invocation for a git: true project, and this hook runs 'status -Brief', so
            # the round trip is paid in every session. Without these tokens it would be
            # paid and the answer discarded - the operator would see nothing, while the
            # defect this all exists for is commits sitting unpushed across sessions
            # unnoticed.
            if ($line -cmatch 'WARNING|STOP:|OVERDUE:|CHASE:|open signal|have NOT reached|COULD NOT REACH|is NOT on the remote') { $out += $line }
        }
    }
}

# --- unresolved signals, when the session is working on keel itself ----------
# Elsewhere this would be noise: a project session cannot act on them (P25).
#
# THIS ASKS THE WRAPPER AND FORWARDS THE ANSWER. It runs 'signals -Brief' for both
# numbers, exactly as it runs 'status -Brief' for the project lines. Walking the signal
# store and counting OPEN records here would be a second implementation of a fact the
# 'signals' verb already owns - the very thing the header above says this script does
# not do.
#
# THE DUE COUNT IS THE POINT, and it is why the selection may not move into this file.
# Which judgements are DUE and which are UNSCHEDULED is decided in ONE place, Get-ReviewState
# in the wrapper. A copy of that date logic here would be two authorities on one fact
# (charter P10) and nothing mechanical would catch them diverging.
#
# WORDING IS LOAD-BEARING, in the same way the -cmatch filter above is: the two patterns
# below read the wrapper's own summary lines, and the wrapper carries a comment beside each
# saying so. FAILS OPEN - a non-zero exit or a line that does not parse prints nothing,
# because a SessionStart nudge that breaks a session is worse than one that says nothing
# (charter P14).
#
# WHICH SESSIONS SEE IT. This repo, or a project whose keel.json declares a repo
# resolving to this repo, which is how a records folder beside this one gets the line.
# A prefix test such as $here -like "$RepoRoot*" is wrong in both directions: a sibling
# merely NAMED keel-something would get the line, while a project declaring this repo
# from elsewhere would stay silent. Both comparisons ignore case, as -like does, because
# a drive letter can be spelled either way. GetFullPath because a caller may reach this
# script through '..'. Any failure here means no line (charter P14).
function Test-SessionOnKeel {
    param([string]$StartDir, [string]$RootDir)
    $ignoreCase = [System.StringComparison]::OrdinalIgnoreCase
    try {
        $rootFull = [System.IO.Path]::GetFullPath($RootDir).TrimEnd('\')
        $hereFull = [System.IO.Path]::GetFullPath($StartDir).TrimEnd('\')
        if ([string]::Equals($hereFull, $rootFull, $ignoreCase)) { return $true }
        if ($hereFull.StartsWith("$rootFull\", $ignoreCase)) { return $true }

        # The nearest keel.json and no further, the same walk the wrapper does (charter P20).
        $walk = $hereFull
        while (-not [string]::IsNullOrEmpty($walk)) {
            $configFile = Join-Path $walk 'keel.json'
            if (Test-Path -LiteralPath $configFile) {
                $config = [System.IO.File]::ReadAllText($configFile) | ConvertFrom-Json
                if ($null -eq $config) { return $false }      # an empty file parses to null
                $declared = $config.PSObject.Properties['repos']
                if ($null -eq $declared -or $null -eq $declared.Value) { return $false }
                foreach ($entry in $declared.Value.PSObject.Properties) {
                    $repoPath = [string]$entry.Value.path
                    if ([string]::IsNullOrWhiteSpace($repoPath)) { continue }
                    $repoFull = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($walk, $repoPath)).TrimEnd('\')
                    if ([string]::Equals($repoFull, $rootFull, $ignoreCase)) { return $true }
                }
                return $false
            }
            $walk = Split-Path -Parent $walk
        }
    } catch { return $false }
    return $false
}

$here = (Get-Location).Path
if ((Test-SessionOnKeel -StartDir $here -RootDir $RepoRoot) -and (Test-Path -LiteralPath $Wrapper)) {
    $signalsBrief = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Wrapper signals -Brief 2>$null
    if ($LASTEXITCODE -eq 0) {
        $sigOpen = -1
        $sigDue  = -1
        foreach ($line in @($signalsBrief)) {
            if ($line -match '(\d+)\s+open of\s+\d+\s+total')        { $sigOpen = [int]$Matches[1] }
            if ($line -match '(\d+)\s+deprioritised signal\(s\) DUE') { $sigDue  = [int]$Matches[1] }
        }
        if ($sigOpen -gt 0) {
            $dueText = if ($sigDue -gt 0) { ", $sigDue due for review" } else { '' }
            $out += "keel: $sigOpen open signal(s) awaiting triage$dueText. Run: keel-state.ps1 signals -Cluster"
        }
    }
}

foreach ($line in $out) { Write-Output $line }
exit 0
