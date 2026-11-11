<#
    check-suite-docs.ps1 - the mechanical validator for this repo.

    Charter contracts:
      P11  a generated artifact must be mechanically checkable, or it does not ship
      P10  one authority per fact - a plugin version has ONE value, in two required places
      P24  a keel change must not invalidate an in-flight project

    Windows PowerShell 5.1 compatible. ASCII only - these scripts run from git hooks
    and Claude Code hooks via powershell.exe -NoProfile, which is 5.1, not pwsh 7.x.

      -CommitGate        check only what is STAGED (used by .githooks/pre-commit)
      -Strict            every check, including slow ones (used by .githooks/pre-push)
      -PrivateNamesOnly  run section 16 and the verdict only; used by scripts/test-private-names.ps1
                         against a scratch repository. The hooks never pass it.
      -HistoryOnly       run section 18 and the verdict only; used by scripts/test-history-ids.ps1
                         against a scratch repository. The hooks never pass it.
#>

param([switch]$CommitGate, [switch]$Strict, [switch]$PrivateNamesOnly, [switch]$HistoryOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$RepoRoot    = Split-Path -Parent $PSScriptRoot
$PluginsDir  = Join-Path $RepoRoot 'plugins'
$MarketPath  = Join-Path $RepoRoot '.claude-plugin\marketplace.json'
$ReadmePath  = Join-Path $RepoRoot 'README.md'
$ChangelogPath = Join-Path $RepoRoot 'CHANGELOG.md'
$CharterPath = Join-Path $RepoRoot 'DESIGN-CHARTER.md'

$script:Problems = @()
function Problem { param([string]$Msg) $script:Problems += $Msg }
function Note    { param([string]$Msg) Write-Output "      $Msg" }

# WHAT RAN, not just whether anything failed. A script that prints only the word
# 'clean' on success makes a silently skipped suite byte-identical in output to a
# passing one, and leaves a checker timing the run with a stopwatch and reading the
# elapsed seconds as a proxy for the suite having executed. When independent
# checkers invent the same workaround, the workaround is the missing feature.
#
# A PowerShell function returns EVERYTHING it emits, so a helper that both printed
# and returned would hand its caller a truthy array. This one only appends to a
# $script: list. The list is printed once, before the verdict, on every run - clean
# or not.
$script:Ran = @()
function Ran     { param([string]$Msg) $script:Ran += $Msg }

# A validator that CRASHES on a malformed manifest is a validator that reports
# nothing while looking like a tooling problem. Parse failures are findings.
function Read-JsonOrProblem {
    param([string]$FilePath, [string]$Label)
    try { $parsed = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch {
        Problem "$Label is not valid JSON: $($_.Exception.Message.Split([char]10)[0]) -- note that Windows paths need doubled backslashes inside a JSON string."
        return $null
    }
    # An EMPTY file parses to $null without throwing, so this is not redundant.
    if ($null -eq $parsed) { Problem "$Label is empty. A truncated manifest is what a botched edit leaves behind."; return $null }
    return $parsed
}

function Get-StagedFiles {
    try { return @(& git -C $RepoRoot diff --cached --name-only 2>$null) }
    catch { return @() }
}

# Which of these relative paths does git ignore? Returns a hashtable keyed by the
# path, or $null when git could not answer - which is NOT the same as "nothing is
# ignored", and a caller that conflates the two reports an exclusion it never made.
#
# NOT check-ignore --stdin. PowerShell terminates piped lines CRLF, git takes the
# carriage return as part of the pathname and answers with a C-quoted string -
# literal quote characters and a literal backslash-r - which matches no path the
# caller holds. Nothing raises; every membership test just silently finds nothing.
# Arguments carry no terminator, so they are used instead, batched to keep the
# command line bounded as the repo grows.
#
# The try/catch is load-bearing, not decoration: git invoked where it cannot
# resolve a repository THROWS under $ErrorActionPreference = 'Stop' even with
# 2>$null, because a native tool's stderr becomes a terminating error there. A
# non-zero exit does not throw, and check-ignore exits 1 whenever a batch happens
# to hold nothing ignored, so the exit code is not a failure signal here and is
# not read as one.
# The eol= pin git resolves for each path, as a hashtable, or $null when git could
# not answer - which is NOT the same as "nothing is pinned".
#
# ASKING GIT, NOT PARSING .gitattributes. A hand-written glob matcher gets this
# wrong in BOTH directions. Keying on the `text` attribute pins every tracked file,
# LICENSE and .gitignore included, every one of which git itself reports as
# `unspecified` for eol - because line 1 of .gitattributes is `* text=auto`, which
# carries no eol at all. And matching a pattern against a file's LEAF NAME rather
# than its repo-relative path silently skips `.githooks/*`, the only pinned pattern
# here containing a separator and the one whose pin is genuinely load-bearing: a
# CRLF shebang fails with "bad interpreter". check-attr resolves precedence,
# negation and path patterns the way git's own checkout does, which is the only
# definition that matters.
#
# Same batching and the same try/catch as Get-IgnoredPathSet above, for the same
# reason: git invoked where it cannot resolve a repository THROWS under
# $ErrorActionPreference = 'Stop' even with 2>$null.
function Get-EolPinSet {
    param([string[]]$RelPaths)
    $pins = @{}
    if ($RelPaths.Count -eq 0) { return $pins }
    try {
        for ($b = 0; $b -lt $RelPaths.Count; $b += 200) {
            $end = [Math]::Min($b + 199, $RelPaths.Count - 1)
            foreach ($line in @(& git -C $RepoRoot check-attr eol -- $RelPaths[$b..$end] 2>$null)) {
                # '<path>: eol: <value>'. Split from the RIGHT: a pathname may contain
                # ': ', the attribute name and its value never do.
                $vAt = $line.LastIndexOf(': ')
                if ($vAt -lt 0) { continue }
                $value = $line.Substring($vAt + 2).Trim()
                $head  = $line.Substring(0, $vAt)
                $nAt   = $head.LastIndexOf(': ')
                if ($nAt -lt 0) { continue }
                $pins[$head.Substring(0, $nAt)] = $value
            }
        }
    }
    catch { return $null }
    return $pins
}

function Get-IgnoredPathSet {
    param([string[]]$RelPaths)
    $set = @{}
    if ($RelPaths.Count -eq 0) { return $set }
    try {
        for ($b = 0; $b -lt $RelPaths.Count; $b += 200) {
            $end = [Math]::Min($b + 199, $RelPaths.Count - 1)
            foreach ($hit in @(& git -C $RepoRoot check-ignore -- $RelPaths[$b..$end] 2>$null)) {
                $set[$hit.Trim()] = $true
            }
        }
    }
    catch { return $null }
    return $set
}

Write-Output 'check-suite-docs'

# --- 16. no private name in anything this repo carries ----------------------
#
# The product is meant to be public, and the people and projects of the person who
# builds it are not. This section refuses any entry of a per-machine list of private
# names, in what a commit would carry and in what a push would publish: file contents,
# file paths and, at push, commit messages.
#
# THE LIST NEVER LIVES IN THE REPO. It is %USERPROFILE%\.keel\private-names.txt, beside
# the rest of the state home, so it travels with nothing this repo publishes, and a test
# fixture that moves USERPROFILE gets its own list or none. One entry per line; a line
# whose first non-space character is '#' is a comment. An entry matches anywhere,
# case-insensitively, unless it starts 'word:', in which case the rest matches only as a
# whole word (letters, digits and underscore are word characters) and case-sensitively.
# That form exists for an entry that is also an ordinary word.
#
# NO LIST, NO CHECK, AND IT SAYS SO ON EVERY RUN. A newcomer's clone has no list, and
# refusing every commit there would make the repo unusable to anyone but its author.
# So a missing list passes - but prints one line saying the check did not run, because
# a silent skip reads exactly like a pass.
#
# A REFUSAL NEVER PRINTS AN ENTRY. Hook output gets pasted into notes, issues and
# transcripts, which are the places this check exists to protect. A refusal names the
# file, the line number and the entry's line number in the list, never the matched text;
# any path it prints has every entry inside it replaced by asterisks; and the list's own
# path is shown with the variable unexpanded, because the expanded form holds the home
# folder's name. git's stderr is discarded rather than relayed, since an error can echo
# a pattern.
#
# WHAT EACH GATE READS. At -CommitGate, the STAGED content and path of each staged file
# (git grep --cached), never the working tree: what is committed is the index, and a
# working-tree-only edit is not in the commit. Everywhere else, every tracked path and
# its content as it stands in the working tree, plus the message of every commit on a
# local branch that no remote-tracking ref contains. Stale remote-tracking refs make
# that set larger than strictly needed, which is the safe direction.
#
# BINARY FILES ARE NOT READ, AND THE LEDGER SAYS HOW MANY. git's own rule (-I) decides,
# so a file holding a NUL byte is skipped - which includes UTF-16 text, the default
# output of Windows PowerShell 5.1's redirection. The ran line counts the files actually
# read as text and the ones skipped, rather than calling every path checked.
#
# FAILS CLOSED PER ENTRY. An entry the check cannot pass to git reliably - empty, holding
# a byte above 127, or holding a double quote, which Windows PowerShell 5.1 mangles on a
# native command line - is a problem naming its list line, never a silent skip. A git
# exit other than 0 (matches) or 1 (none) means that entry was not checked, and is a
# problem too.
#
# Defined here, ahead of section 1, so -PrivateNamesOnly can run it alone; on an ordinary
# run it is called after section 15.
function Get-PnRegex {
    param($PnEntry)
    $pnEsc = [regex]::Escape($PnEntry.Text)
    if ($PnEntry.Word) { return [regex]::new("(?<![A-Za-z0-9_])$pnEsc(?![A-Za-z0-9_])") }
    return [regex]::new($pnEsc, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Format-PnPath {
    param([string]$PnPath, [object[]]$PnList)
    $pnMasked = $PnPath
    $pnStars = [System.Text.RegularExpressions.MatchEvaluator] { param($pnM) '*' * $pnM.Value.Length }
    foreach ($pnE in $PnList) { $pnMasked = (Get-PnRegex $pnE).Replace($pnMasked, $pnStars) }
    return $pnMasked
}

function Invoke-PrivateNameCheck {
    $pnListPath = Join-Path $env:USERPROFILE '.keel\private-names.txt'
    $pnShown    = '%USERPROFILE%\.keel\private-names.txt'

    if (-not (Test-Path -LiteralPath $pnListPath -PathType Leaf)) {
        Ran "private names: NOT CHECKED - no list at $pnShown, so this check did not run"
        return
    }

    $pnEntries = @()
    $pnRaw = @(Get-Content -LiteralPath $pnListPath -Encoding UTF8)
    for ($pnI = 0; $pnI -lt $pnRaw.Count; $pnI++) {
        $pnText = ([string]$pnRaw[$pnI]).Trim()
        if ($pnText -eq '' -or $pnText.StartsWith('#')) { continue }
        $pnWord = $false
        if ($pnText.StartsWith('word:')) { $pnWord = $true; $pnText = $pnText.Substring(5).Trim() }
        $pnUsable = ($pnText -ne '') -and ($pnText -notmatch '[^\x00-\x7F]') -and (-not $pnText.Contains('"'))
        if (-not $pnUsable) {
            Problem "private names: list line $($pnI + 1) of $pnShown is empty, holds a non-ASCII character or holds a double quote, so it was NOT CHECKED. Rewrite that entry."
            continue
        }
        $pnEntries += [pscustomobject]@{ Line = ($pnI + 1); Word = $pnWord; Text = $pnText }
    }

    # The files: staged paths at the commit gate, every tracked path otherwise.
    $pnScope = 'tracked'
    $pnPrior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($CommitGate) {
        $pnScope = 'staged'
        $pnPaths = @(& git -C $RepoRoot diff --cached --name-only --diff-filter=d 2>$null)
    }
    else {
        $pnPaths = @(& git -C $RepoRoot ls-files 2>$null)
    }
    $pnListCode = $LASTEXITCODE
    $ErrorActionPreference = $pnPrior
    if ($pnListCode -ne 0) {
        Problem "private names: git could not list the $pnScope files (exit $pnListCode), so no file was checked. Not a clean run."
        $pnPaths = @()
    }

    # The paths themselves, matched here with the same two rules.
    foreach ($pnPath in $pnPaths) {
        foreach ($pnEntry in $pnEntries) {
            if ((Get-PnRegex $pnEntry).IsMatch([string]$pnPath)) {
                Problem ("private names: a {0} path holds the entry on list line {1} of {2}: {3}" -f $pnScope, $pnEntry.Line, $pnShown, (Format-PnPath ([string]$pnPath) $pnEntries))
            }
        }
    }

    # The contents, one git grep per entry and batch of paths. -I skips binary files.
    $pnTextFiles = 0
    for ($pnB = 0; $pnB -lt $pnPaths.Count; $pnB += 200) {
        $pnEnd = [Math]::Min($pnB + 199, $pnPaths.Count - 1)
        $pnBatch = @($pnPaths[$pnB..$pnEnd])

        # How many of these git reads as text: '^' matches any line, so a file is listed
        # unless it is binary or empty.
        $pnCountArgs = @('-C', $RepoRoot, 'grep', '-I', '-l', '--no-color')
        if ($CommitGate) { $pnCountArgs += '--cached' }
        $pnCountArgs += @('-e', '^', '--') + $pnBatch
        $pnPrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $pnListed = @(& git @pnCountArgs 2>$null)
        $pnCountCode = $LASTEXITCODE
        $ErrorActionPreference = $pnPrior
        if ($pnCountCode -eq 0) { $pnTextFiles += $pnListed.Count }
        elseif ($pnCountCode -ne 1) { Problem "private names: git grep could not count the text files (exit $pnCountCode). Not a clean run." }

        foreach ($pnEntry in $pnEntries) {
            $pnArgs = @('-C', $RepoRoot, 'grep', '-I', '-n', '--no-color')
            if ($CommitGate) { $pnArgs += '--cached' }
            if ($pnEntry.Word) { $pnArgs += '-w' } else { $pnArgs += '-i' }
            $pnArgs += @('-F', '-e', $pnEntry.Text, '--') + $pnBatch

            $pnPrior = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $pnHits = @(& git @pnArgs 2>$null)
            $pnCode = $LASTEXITCODE
            $ErrorActionPreference = $pnPrior

            if ($pnCode -eq 1) { continue }
            if ($pnCode -ne 0) {
                Problem "private names: git grep failed (exit $pnCode) for list line $($pnEntry.Line), so that entry was NOT CHECKED against the $pnScope files."
                continue
            }
            foreach ($pnHit in $pnHits) {
                if ([string]$pnHit -match '^(.+?):(\d+):') {
                    Problem ("private names: {0} line {1} holds the entry on list line {2} of {3}. The entry is not printed; open the list at that line." -f (Format-PnPath $Matches[1] $pnEntries), $Matches[2], $pnEntry.Line, $pnShown)
                }
            }
        }
    }

    # Commit messages, at push only: every local branch's commits no remote holds yet.
    $pnMsgCount = 0
    if (-not $CommitGate) {
        $pnSep = [string][char]0x1e
        $pnPrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $pnLog = @(& git -C $RepoRoot log --branches --not --remotes '--format=%x1e%H%n%B' 2>$null)
        $pnLogCode = $LASTEXITCODE
        $ErrorActionPreference = $pnPrior
        if ($pnLogCode -ne 0) {
            Problem "private names: git log could not list the unpushed commits (exit $pnLogCode), so no commit message was checked. Not a clean run."
        }
        else {
            foreach ($pnChunk in (($pnLog -join "`n") -split $pnSep)) {
                if ($pnChunk.Trim() -eq '') { continue }
                $pnMsgCount++
                $pnNl  = $pnChunk.IndexOf("`n")
                $pnSha = $pnChunk
                $pnMsg = ''
                if ($pnNl -ge 0) { $pnSha = $pnChunk.Substring(0, $pnNl); $pnMsg = $pnChunk.Substring($pnNl + 1) }
                $pnShort = $pnSha.Trim()
                if ($pnShort.Length -gt 7) { $pnShort = $pnShort.Substring(0, 7) }
                foreach ($pnEntry in $pnEntries) {
                    if ((Get-PnRegex $pnEntry).IsMatch($pnMsg)) {
                        Problem ("private names: the message of unpushed commit {0} holds the entry on list line {1} of {2}. The entry is not printed; open the list at that line." -f $pnShort, $pnEntry.Line, $pnShown)
                    }
                }
            }
        }
    }

    $pnSkipped = $pnPaths.Count - $pnTextFiles
    if ($CommitGate) {
        Ran ("private names: {0} entr(y/ies) from {1} checked against {2} staged path(s), {3} read as text, {4} skipped as binary or empty" -f $pnEntries.Count, $pnShown, $pnPaths.Count, $pnTextFiles, $pnSkipped)
    }
    else {
        Ran ("private names: {0} entr(y/ies) from {1} checked against {2} tracked path(s), {3} read as text, {4} skipped as binary or empty, and {5} unpushed commit message(s)" -f $pnEntries.Count, $pnShown, $pnPaths.Count, $pnTextFiles, $pnSkipped, $pnMsgCount)
    }
}

# --- 18. no record id of keel's own work in the product ---------------------
#
# The skills, scripts and documents give each rule its reason in general terms. The
# account of when and where the reason was found - which workstream, phase, signal, issue
# or measurement - belongs in the records, not in the product. Left to habit, that account
# comes back one comment or one changelog line at a time, and a newcomer reads the
# documents as well as the code, so this section refuses it in every file the product
# holds: the contents and the paths of what is staged at -CommitGate, of every tracked
# file otherwise.
#
# WHAT IT REFUSES. Five kinds, each needing a digit:
#   - a workstream or phase id numbered 10 or more, in either case, with or without a
#     phase, which also covers check ids and lowercase test-label forms;
#   - 'S' and four digits, a signal id;
#   - 'issue' and a number, or '#' and two to five digits with no hex letter or digit
#     after them. An HTML character reference such as &#9472; is not an issue number, and
#     neither is a CSS colour such as #183039 or #94AAB3, so neither is refused; a colour
#     of three or four characters that are all decimal digits still is;
#   - 'trap' and a number;
#   - 'Measured' and a date.
# A single-digit workstream number is NOT matched, on purpose: the product's examples use
# W4.2, W1.1 and the like as placeholders, and keel's own record never had a workstream
# below ten worth citing. 'record/' alone is not refused either: every keel project has a
# record/ folder and the skills name it, while a record path that names a phase is caught
# by the workstream form.
#
# THE ALLOWLIST holds the example values the product uses on purpose: the placeholder
# signal id the skills and the wrapper show, a test fixture meaning a signal with no
# record, an example issue number in two spellings, and a template's example of a dated
# measurement. It is compared case-sensitively against the exact matched text. A new
# example belongs here only if no placeholder will do.
#
# WHY .NET AND NOT git grep ALONE. The forms need look-behind and look-ahead, which git's
# extended regex lacks. So git grep lists every line holding a digit - every kind above
# needs one, so this prefilter cannot fall out of step with the patterns - and the regex
# runs here on what it returns. git grep is still what reads the files: --cached gives the
# staged blob at the commit gate, exactly as section 16 reads it, and -I skips binaries.
#
# EVERY PATH, AT BOTH GATES. There is no folder filter: the commit gate reads every staged
# path and the push gate every tracked one, so a document, a root file and a file added
# later are all read without anyone having to name them here.
#
# Defined here, ahead of section 1, so -HistoryOnly can run it alone; on an ordinary run
# it is called after section 17.
$script:HistoryRegex = [regex]::new(
    '(?<ws>(?<![A-Za-z0-9_])[Ww][1-9][0-9]+(?![0-9]))' +
    '|(?<sig>(?<![A-Za-z0-9_])[Ss][0-9]{4}(?![0-9]))' +
    '|(?<iss>(?<![A-Za-z0-9_])[Ii][Ss][Ss][Uu][Ee][Ss]? #?[0-9]+|(?<![A-Za-z0-9_&#])#[0-9]{2,5}(?![0-9A-Fa-f]))' +
    '|(?<trap>(?<![A-Za-z0-9_])[Tt][Rr][Aa][Pp][Ss]? [0-9]+)' +
    '|(?<meas>(?<![A-Za-z0-9_])[Mm][Ee][Aa][Ss][Uu][Rr][Ee][Dd] (?:[Oo][Nn] )?20[0-9]{2}-[0-9]{2}-[0-9]{2})')
$script:HistoryAllow = @('S0007', 'S9999', 'issue #12', 'Issue 12', 'Measured 2026-08-17')
$script:HistoryKinds = [ordered]@{
    ws   = 'workstream or phase id'
    sig  = 'signal id'
    iss  = 'issue number'
    trap = 'trap number'
    meas = 'dated measurement'
}

# The tokens on one line or path that are not allowlisted, each with its kind, and how
# many allowlisted ones were seen. Adds to $script: counters and returns only the list.
function Get-HistoryHits {
    param([string]$HiSubject)
    $hiFound = @()
    foreach ($hiM in $script:HistoryRegex.Matches($HiSubject)) {
        if ($script:HistoryAllow -ccontains $hiM.Value) { $script:HistoryAllowSeen++; continue }
        $hiKind = 'record id'
        foreach ($hiKey in $script:HistoryKinds.Keys) {
            if ($hiM.Groups[$hiKey].Success) { $hiKind = $script:HistoryKinds[$hiKey]; break }
        }
        $hiFound += [pscustomobject]@{ Token = $hiM.Value; Kind = $hiKind }
    }
    return $hiFound
}

function Invoke-HistoryIdCheck {
    $script:HistoryAllowSeen = 0
    $hiScope = 'tracked'
    $hiPrior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($CommitGate) {
        $hiScope = 'staged'
        $hiAll = @(& git -C $RepoRoot diff --cached --name-only --diff-filter=d 2>$null)
    }
    else {
        $hiAll = @(& git -C $RepoRoot ls-files 2>$null)
    }
    $hiListCode = $LASTEXITCODE
    $ErrorActionPreference = $hiPrior
    if ($hiListCode -ne 0) {
        Problem "history ids: git could not list the $hiScope files (exit $hiListCode), so no file was checked. Not a clean run."
        $hiAll = @()
    }
    $hiPaths = @($hiAll | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

    if ($hiPaths.Count -eq 0) {
        Ran "history ids: 0 $hiScope path(s), nothing to read"
        return
    }

    $hiAdvice = 'The history of a change goes in the records, not in the product: give the reason in general terms, use a placeholder such as W4.2 for an example, or add an example id to the allowlist in section 18.'
    $hiRefused = 0

    # The paths themselves.
    foreach ($hiPath in $hiPaths) {
        $hiHits = @(Get-HistoryHits ([string]$hiPath))
        if ($hiHits.Count -gt 0) {
            $hiRefused++
            Problem ("history ids: a {0} path holds {1} ({2}): {3}. {4}" -f $hiScope, (($hiHits | ForEach-Object { $_.Token }) -join ', '),
                     (($hiHits | ForEach-Object { $_.Kind } | Select-Object -Unique) -join ', '), $hiPath, $hiAdvice)
        }
    }

    # The contents, one git grep for the lines holding a digit per batch of paths.
    $hiTextFiles = 0
    for ($hiB = 0; $hiB -lt $hiPaths.Count; $hiB += 200) {
        $hiEnd = [Math]::Min($hiB + 199, $hiPaths.Count - 1)
        $hiBatch = @($hiPaths[$hiB..$hiEnd])

        # How many of these git reads as text: '^' matches any line, so a file is listed
        # unless it is binary or empty.
        $hiCountArgs = @('-C', $RepoRoot, 'grep', '-I', '-l', '--no-color')
        if ($CommitGate) { $hiCountArgs += '--cached' }
        $hiCountArgs += @('-e', '^', '--') + $hiBatch
        $hiPrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $hiListed = @(& git @hiCountArgs 2>$null)
        $hiCountCode = $LASTEXITCODE
        $ErrorActionPreference = $hiPrior
        if ($hiCountCode -eq 0) { $hiTextFiles += $hiListed.Count }
        elseif ($hiCountCode -ne 1) { Problem "history ids: git grep could not count the text files (exit $hiCountCode). Not a clean run." }

        $hiArgs = @('-C', $RepoRoot, 'grep', '-I', '-n', '--no-color')
        if ($CommitGate) { $hiArgs += '--cached' }
        $hiArgs += @('-e', '[0-9]', '--') + $hiBatch
        $hiPrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $hiLines = @(& git @hiArgs 2>$null)
        $hiCode = $LASTEXITCODE
        $ErrorActionPreference = $hiPrior
        if ($hiCode -eq 1) { continue }
        if ($hiCode -ne 0) {
            Problem "history ids: git grep failed (exit $hiCode), so a batch of $($hiBatch.Count) $hiScope file(s) was NOT CHECKED."
            continue
        }
        foreach ($hiLine in $hiLines) {
            if ([string]$hiLine -notmatch '^(.+?):(\d+):(.*)$') { continue }
            $hiFile = $Matches[1]
            $hiNum  = $Matches[2]
            $hiHits = @(Get-HistoryHits $Matches[3])
            if ($hiHits.Count -eq 0) { continue }
            $hiRefused++
            Problem ("history ids: {0} line {1} holds {2} ({3}). {4}" -f $hiFile, $hiNum, (($hiHits | ForEach-Object { $_.Token }) -join ', '),
                     (($hiHits | ForEach-Object { $_.Kind } | Select-Object -Unique) -join ', '), $hiAdvice)
        }
    }

    $hiSkipped = $hiPaths.Count - $hiTextFiles
    Ran ("history ids: {0} {1} path(s) in the repository, {2} read as text, {3} skipped as binary or empty, {4} line(s) or path(s) refused, {5} allowlisted example(s) seen" -f $hiPaths.Count, $hiScope, $hiTextFiles, $hiSkipped, $hiRefused, $script:HistoryAllowSeen)
}

# The ran ledger prints on EVERY run, before the verdict and whether or not anything
# failed. A gate that reports only its verdict cannot be told apart from a gate that did
# not run. A function so the -PrivateNamesOnly exit below and the end of the script share
# one verdict; it exits, and returns nothing.
function Write-Verdict {
    Write-Output ''
    foreach ($r in $script:Ran) { Write-Output "  ran   $r" }
    Write-Output ''
    if ($script:Problems.Count -eq 0) {
        Write-Output '  clean'
        exit 0
    }
    foreach ($p in $script:Problems) { Write-Output "  FAIL  $p" }
    Write-Output ''
    Write-Output ("  {0} problem(s)." -f $script:Problems.Count)
    exit 1
}

if ($PrivateNamesOnly) {
    Invoke-PrivateNameCheck
    Write-Verdict
}

if ($HistoryOnly) {
    Invoke-HistoryIdCheck
    Write-Verdict
}

# --- 1. the charter exists and is non-trivial -------------------------------
if (-not (Test-Path -LiteralPath $CharterPath)) {
    Problem 'DESIGN-CHARTER.md is missing. It is the thing every plugin change is checked against.'
}
else {
    $charterText = Get-Content -LiteralPath $CharterPath -Raw -Encoding UTF8
    if ($charterText.Length -lt 500) { Problem 'DESIGN-CHARTER.md exists but is nearly empty.' }
    else { Ran ("charter: DESIGN-CHARTER.md present, {0} chars" -f $charterText.Length) }
}

# --- 2. manifests parse, and versions agree across their TWO homes ----------
if (-not (Test-Path -LiteralPath $MarketPath)) {
    Problem '.claude-plugin/marketplace.json is missing.'
}
else {
    $market = Read-JsonOrProblem -FilePath $MarketPath -Label 'marketplace.json'
    $marketPlugins = @{}
    if ($null -ne $market) { foreach ($p in @($market.plugins)) { $marketPlugins[$p.name] = $p.version } }

    $onDisk = @()
    foreach ($d in @(Get-ChildItem -LiteralPath $PluginsDir -Directory -ErrorAction SilentlyContinue)) {
        $manifest = Join-Path $d.FullName '.claude-plugin\plugin.json'
        if (-not (Test-Path -LiteralPath $manifest)) {
            Problem "plugins/$($d.Name) has no .claude-plugin/plugin.json."
            continue
        }
        $m = Read-JsonOrProblem -FilePath $manifest -Label "plugins/$($d.Name)/.claude-plugin/plugin.json"
        if ($null -eq $m) { continue }
        $onDisk += $m.name

        if ($m.name -ne $d.Name) {
            Problem "plugins/$($d.Name)/.claude-plugin/plugin.json declares name '$($m.name)'. Folder and name must match."
        }
        if (-not $marketPlugins.ContainsKey($m.name)) {
            Problem "Plugin '$($m.name)' is not listed in marketplace.json."
        }
        elseif ($marketPlugins[$m.name] -ne $m.version) {
            Problem "Version disagreement for '$($m.name)': plugin.json says $($m.version), marketplace.json says $($marketPlugins[$m.name]). One fact, two required homes - both move together (charter P10)."
        }
    }
    foreach ($name in $marketPlugins.Keys) {
        if ($onDisk -notcontains $name) { Problem "marketplace.json lists '$name' but plugins/$name has no manifest on disk." }
    }
    Ran ("manifests: {0} plugin(s) on disk checked against {1} listed in marketplace.json" -f @($onDisk).Count, $marketPlugins.Count)
}

# --- 3. generated inventory is not stale ------------------------------------
$gen = Join-Path $PSScriptRoot 'gen-suite-docs.ps1'
if (Test-Path -LiteralPath $gen) {
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gen 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Name no file here: gen-suite-docs maintains several generated blocks and its own
        # output says which one drifted. Hardcoding one filename would send a reader to the
        # wrong document whenever a different block drifted.
        $drifted = @($out | Where-Object { $_ -match '^DRIFT\s+(\S+)' } | ForEach-Object { $Matches[1] })
        $which = if ($drifted.Count -gt 0) { $drifted -join ', ' } else { 'a generated inventory' }
        Problem "Generated inventory drift in: $which. Run: powershell -File scripts/gen-suite-docs.ps1 -Write"
        foreach ($l in @($out)) { Note $l }
    }
    else { Ran 'inventory: no drift in the generated blocks (gen-suite-docs.ps1 exit 0)' }
}
else { Problem 'scripts/gen-suite-docs.ps1 is missing, so the inventory cannot be checked (charter P11).' }

# --- 4. every script is ASCII-only ------------------------------------------
# They run under powershell.exe -NoProfile (5.1). A stray smart quote or em dash
# becomes mojibake there and can break parsing outright.
$asciiScanned = 0
foreach ($f in @(Get-ChildItem -LiteralPath $RepoRoot -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue)) {
    $asciiScanned++
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $bad = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -gt 127) { $bad++ } }
    if ($bad -gt 0) {
        $rel = $f.FullName.Substring($RepoRoot.Length + 1)
        Problem "$rel contains $bad non-ASCII byte(s). Scripts must be ASCII-only - they run under Windows PowerShell 5.1."
    }
}
Ran ("ascii: {0} .ps1 file(s) scanned for non-ASCII bytes" -f $asciiScanned)

# --- 5. the wrapper is the only writer of state -----------------------------
# Anything else touching state.json directly would make the state file stop
# outranking the conversation (charter P3/P15).
#
# The enumeration reads .ps1 and .md files that git does not ignore, and the line
# reported below is the count of what it ACTUALLY read. -Include against a
# -LiteralPath container does not filter, so an enumeration built that way reads
# logs, JSON, HTML, files with no extension and files under paths .gitignore
# excludes, and then reports the whole figure as ".ps1/.md file(s) scanned". Reading
# those other files can also fail outright, an intermittent false red; the extension
# filter is what prevents that, since a .remember/tmp file is neither .ps1 nor .md.
#
# The ignore limb is what keeps this rule from blocking the commit path: .remember/
# is rewritten by the live session, so a session that merely DISCUSSES this rule
# can leave a buffer file matching the pattern below, and without the limb the hook
# then refuses every commit in the repository. That file is git-ignored, is in no
# commit, and cannot be edited by the session that needs to commit - so the only
# route around it would be --no-verify, which disables this entire suite at the
# same time.
#
# The ignore limb is not optional, and the extension filter does not replace it:
# with the extension filter and WITHOUT the ignore limb, this rule still reports
# .remember/now.md and still blocks every commit. The ignore limb is the only
# thing that lifts that block.
$wrapperName = 'keel-state.ps1'
$stateScanned = 0
$stateSkipped = 0
$stateFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -eq '.ps1' -or $_.Extension -eq '.md' })
$stateIgnored = Get-IgnoredPathSet -RelPaths @($stateFiles | ForEach-Object { $_.FullName.Substring($RepoRoot.Length + 1).Replace([char]92, '/') })
foreach ($f in $stateFiles) {
    if ($f.Name -eq $wrapperName) { continue }
    if ($f.Name -eq 'check-suite-docs.ps1') { continue }
    $rel = $f.FullName.Substring($RepoRoot.Length + 1)
    if ($null -ne $stateIgnored -and $stateIgnored.ContainsKey($rel.Replace([char]92, '/'))) {
        $stateSkipped++
        continue
    }
    $stateScanned++
    $c = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    if ($c -match 'Set-Content[^\r\n]*state\.json' -or $c -match 'Out-File[^\r\n]*state\.json') {
        Problem "$rel writes state.json directly. Only $wrapperName may write state (charter P15)."
    }
}
if ($null -eq $stateIgnored) {
    Ran ("state writer: {0} .ps1/.md file(s) scanned, git could not report ignored paths so none were skipped; only {1} may write state.json" -f $stateScanned, $wrapperName)
}
else {
    Ran ("state writer: {0} .ps1/.md file(s) scanned, {1} skipped as git-ignored; only {2} may write state.json" -f $stateScanned, $stateSkipped, $wrapperName)
}

# --- 6. no variable is named after a parameter ------------------------------
# PowerShell variable names are case-insensitive and a param()'s type constraint
# follows the name, so a local called $repos IS the [string]$Repos parameter and
# silently stringifies whatever object you assign to it.
#
# Written only in prose, this always-rule did not hold, even for the person who wrote
# it. Prose-rung enforcement of an always-rule failing with a cited failure is what
# earns the exit-code rung (charter P13, P4).
#
# Zero tolerance, including function-scope shadowing, which is legal but is the
# only rule a checker can enforce without parsing scope.
$shadowScanned = 0
foreach ($f in @(Get-ChildItem -LiteralPath $RepoRoot -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue)) {
    $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8)
    $joined = ($lines -join "`n")
    if ($joined -notmatch '(?ms)^param\((.*?)^\)') { continue }
    $shadowScanned++
    $paramNames = @()
    foreach ($pm in ([regex]::Matches($Matches[1], '\$(\w+)'))) { $paramNames += $pm.Groups[1].Value.ToLower() }
    $paramNames = @($paramNames | Sort-Object -Unique)
    if ($paramNames.Count -eq 0) { continue }

    $rel = $f.FullName.Substring($RepoRoot.Length + 1)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($ln.TrimStart().StartsWith('#')) { continue }
        if ($ln -match '^\s*\$(\w+)\s*=[^=]') {
            $vn = $Matches[1].ToLower()
            if ($paramNames -contains $vn) {
                Problem "$rel line $($i + 1): assigns to `$$($Matches[1]), which is also a parameter name. PowerShell variable names are case-insensitive, so this IS the parameter and its type constraint applies - an object assigned here is silently stringified. Rename the local."
            }
        }
    }
}
Ran ("param shadowing: {0} .ps1 file(s) with a param() block scanned" -f $shadowScanned)

# --- 7. docs move with the change (staged only) -----------------------------
if ($CommitGate) {
    $staged = @(Get-StagedFiles)
    $pluginChanges = @($staged | Where-Object { $_ -like 'plugins/*' })
    Ran ("staged: {0} path(s) staged, {1} of them under plugins/" -f $staged.Count, $pluginChanges.Count)
    if ($pluginChanges.Count -gt 0) {
        if (@($staged | Where-Object { $_ -eq 'CHANGELOG.md' }).Count -eq 0) {
            Problem "plugins/** is staged but CHANGELOG.md is not. Docs move with the change."
            foreach ($p in $pluginChanges) { Note $p }
        }
        $touchedPlugins = @($pluginChanges | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique)
        foreach ($tp in $touchedPlugins) {
            $manifestRel = "plugins/$tp/.claude-plugin/plugin.json"
            if (@($staged | Where-Object { $_ -eq $manifestRel }).Count -eq 0) {
                Problem "plugins/$tp changed but $manifestRel is not staged. Every plugin change carries a version bump."
            }
            if (@($staged | Where-Object { $_ -eq '.claude-plugin/marketplace.json' }).Count -eq 0) {
                Problem "plugins/$tp changed but .claude-plugin/marketplace.json is not staged. The version lives in both."
            }
        }
    }
}

# --- 7. changelog carries an ENTRY HEADING for the current version ----------
#
# Testing for the version string ANYWHERE in the file:
#   if ($mv -and $cl -notmatch [regex]::Escape($mv)) { ... }
# cannot fail for the right reason. A release entry's body routinely names both
# the old and the new version in prose ("keel-workflow 0.21.0 -> 0.22.0"), so the
# string is present even when the entry is headed with the WRONG version, or when
# no entry for that version exists at all and some older entry happens to mention
# it. A CHANGELOG headed 0.21.0 whose body names 0.22.0 raises no problem on such
# a limb at all.
#
# So it tests for a HEADING, which is text that cannot be present unless the entry
# exists - the same rule keel-plan-workstream applies.
#
# LINE-BASED, never (?m) over the raw text: under (?m) the .NET $ anchors BEFORE
# the \n with the \r still unconsumed, so a class that omits \r never reaches the
# anchor - a wrong answer that raises nothing. Get-Content splits the lines and
# strips the terminator, whatever it is.
# ONE read of CHANGELOG.md, THREE reports. The file is long, and there is one
# authority for which version
# is current - the top-level `version` in marketplace.json - so a second reader or
# a second notion of "current" would be a charter P10 violation, not a
# convenience. 7a keeps its -Strict guard; 7b and 7c run at BOTH gates.
if ((Test-Path -LiteralPath $MarketPath) -and (Test-Path -LiteralPath $ChangelogPath)) {
    $mkt = Read-JsonOrProblem -FilePath $MarketPath -Label 'marketplace.json'
    $mv = if ($null -eq $mkt) { '' } else { $mkt.version }
    if ($mv) {
        $headingPattern = '^##\s+marketplace\s+' + [regex]::Escape($mv) + '(\s|$)'
        $anyHeading     = '^##\s+marketplace\s+(\S+)'
        $headingFound   = $false
        $newestVersion  = ''
        $inEntry        = $false
        $citedIds       = New-Object System.Collections.ArrayList
        foreach ($clLine in @(Get-Content -LiteralPath $ChangelogPath -Encoding UTF8)) {
            if ($clLine -match $anyHeading) {
                # $Matches is clobbered by the NEXT -match, so read it first.
                if (-not $newestVersion) { $newestVersion = $Matches[1] }
                if ($clLine -match $headingPattern) { $headingFound = $true; $inEntry = $true }
                elseif ($inEntry) { $inEntry = $false }
                continue
            }
            if ($inEntry) {
                foreach ($sidMatch in [regex]::Matches($clLine, 'S[0-9]{4}')) {
                    if (-not $citedIds.Contains($sidMatch.Value)) { [void]$citedIds.Add($sidMatch.Value) }
                }
            }
        }

        # --- 7a. an entry heading for the current version exists SOMEWHERE ------
        if ($Strict) {
            if (-not $headingFound) {
                Problem ("CHANGELOG.md has no ENTRY HEADING for marketplace version $mv. Looked for a line matching '## marketplace $mv'. " +
                         "Mentioning the version in an entry body is not an entry: a release body names the old version too, so a file headed with the wrong version would pass.")
            }
            Ran "changelog: entry heading '## marketplace $mv'"
        }

        # --- 7b. the NEWEST entry heading is this release's ---------------------
        #
        # Why (charter P13): an entry can be written and a plugin bumped in both
        # required places while this file's TOP-LEVEL version stays at the previous
        # release. 7a asks only whether a heading for the current version exists
        # ANYWHERE, and the PREVIOUS release's own heading answers yes, so -Strict
        # passes while the two files disagree about which release this is. Same
        # family as the failure 7a itself guards against: a check that could not
        # fail for the right reason.
        if ($newestVersion -and $newestVersion -ne $mv) {
            Problem ("CHANGELOG.md's NEWEST entry is headed '## marketplace $newestVersion' but marketplace.json claims version $mv. " +
                     "One of the two was not updated. A heading for $mv further down the file is the PREVIOUS release and does not make this one described.")
        }
        Ran "changelog: newest entry heading '## marketplace $newestVersion' vs marketplace.json $mv"

        # --- 7c. every signal id cited in the current entry EXISTS --------------
        #
        # A wrong signal id in an entry tends to be PLAUSIBLE and ADJACENT rather than
        # random - a near neighbour of the right one - which is why reading carefully
        # does not catch it.
        #
        # The store is machine-local under %USERPROFILE% and this repo is not, and a
        # fresh clone must work unedited, so an absent store SKIPS.
        # It skips OUT LOUD: a silent skip looks exactly like a pass, which is
        # worse than no check at all. Scoped to the current entry, never the whole
        # file - an older entry can use an id as an example, such as an exit-code
        # example, and a whole-file scan would fail a correct repository forever.
        $signalStore = Join-Path $env:USERPROFILE '.keel\signals'
        if (-not (Test-Path -LiteralPath $signalStore)) {
            Ran "changelog: cited signal ids NOT CHECKED - no signal store at $signalStore (machine-local; a fresh clone has none)"
        }
        elseif ($citedIds.Count -eq 0) {
            Ran "changelog: entry '## marketplace $mv' cites no signal id"
        }
        else {
            $missing = @()
            foreach ($sid in $citedIds) {
                if (-not (Test-Path -LiteralPath (Join-Path $signalStore "$sid.json"))) { $missing += $sid }
            }
            if ($missing.Count -gt 0) {
                Problem ("CHANGELOG.md entry '## marketplace $mv' cites signal id(s) that do not exist in the local store: $($missing -join ', '). " +
                         "Looked for $signalStore\<id>.json. A wrong id is always plausible and adjacent to the right one, so check the signal you meant rather than the one that reads correctly.")
            }
            Ran "changelog: $($citedIds.Count) cited signal id(s) checked against the local store ($($citedIds -join ', '))"
        }
    }
}

# --- 8. the charter gate's matcher covers the tools its script handles ------
#
# Why this rung exists (charter P13): a fix to keel-plugins-gate.ps1 that makes
# a shell command writing under plugins/ BLOCKED, and a `cat` of the charter ARM
# the marker, does nothing if the .claude/settings.json matcher is not updated
# with it - the hook is never INVOKED for Bash or PowerShell and both halves sit
# there as unreachable code, while the changelog asserts the fix has landed. A
# gate whose configuration does not cover its code is worse than a missing gate,
# because it gets designed around.
#
# This does NOT enforce the charter-read rule. That rule is enforced once, at
# the PreToolUse rung, and is untouched here. This enforces a DIFFERENT rule
# that was enforced nowhere: the gate's CONFIGURATION must cover the tools its
# CODE handles.
#
# The required list is written out rather than parsed back out of the gate
# script. A checker carrying its own parser is a second thing that can be wrong,
# in the file that gates every commit.
$SettingsPath      = Join-Path $RepoRoot '.claude\settings.json'
$GateRequiredTools = @('Read', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'Bash', 'PowerShell')

if (-not (Test-Path -LiteralPath $SettingsPath)) {
    Problem '.claude/settings.json is missing, so the repo-local charter gate is wired to nothing.'
}
else {
    $settings = Read-JsonOrProblem -FilePath $SettingsPath -Label '.claude/settings.json'
    if ($null -ne $settings) {
        # Index the property collection rather than reading .Name off it: under
        # Set-StrictMode an object with no properties throws.
        $gateMatchers = @()
        if ($settings.PSObject.Properties['hooks'] -and $settings.hooks.PSObject.Properties['PreToolUse']) {
            foreach ($entry in @($settings.hooks.PreToolUse)) {
                $wired = $false
                if ($entry.PSObject.Properties['hooks']) {
                    foreach ($hook in @($entry.hooks)) {
                        if ($hook.PSObject.Properties['command'] -and
                            ([string]$hook.command) -match 'keel-plugins-gate\.ps1') { $wired = $true }
                    }
                }
                if ($wired) {
                    # An ABSENT matcher key means match-all, exactly like '*'. The
                    # SessionStart hook in this very repo uses that shape. Reporting
                    # it as "nothing invokes the gate" would be a checker lying while
                    # failing - the thing this section exists to catch.
                    if ($entry.PSObject.Properties['matcher']) { $gateMatchers += [string]$entry.matcher }
                    else { $gateMatchers += '*' }
                }
            }
        }

        if ($gateMatchers.Count -eq 0) {
            Problem 'No PreToolUse hook in .claude/settings.json is wired to scripts/keel-plugins-gate.ps1. The gate exists but nothing invokes it.'
        }
        else {
            $covered = ($gateMatchers -join ' , ')

            # '*' and an empty matcher both mean match-ALL in Claude Code, so they
            # cover every required tool. Without this the check reports a FAIL whose
            # message is factually wrong - and a checker that lies while failing is
            # the same species as the defect this whole section exists to catch.
            $matchesEverything = @($gateMatchers | Where-Object {
                $_ -eq '*' -or [string]::IsNullOrWhiteSpace($_)
            }).Count -gt 0

            # Decide coverage the way the HOST does: does the matcher match the tool
            # NAME? Not "does the tool name appear in the matcher string", which is
            # wrong in both directions -
            #   * it FAILS on a perfectly good regex matcher: '^(Read|...|Bash)$'
            #     visibly contains every name and would be reported as naming none;
            #   * a substring test would PASS 'MultiEdit' against a matcher of
            #     'Edit', which does not actually cover it.
            # Anchoring is right for the matcher shape this repo ships and errs SAFE
            # for the other. Per Claude Code's hooks reference, a PLAIN matcher is an
            # exact match - "Bash matches only the Bash tool; Edit|Write and Edit, Write
            # each match either tool exactly" - and the hooks guide states "Matchers are
            # case-sensitive". A REGEX matcher such as 'Edit.*' is UNANCHORED on the
            # host and "succeeds on a match anywhere in the value".
            #
            # So against a regex matcher this check is STRICTER than the host: it would
            # report 'MultiEdit' as uncovered by 'Edit.*' when the host does cover it.
            # That is a false FAIL, never a false PASS - the safe direction for a gate
            # about a gate.
            $missingTools = @()
            if (-not $matchesEverything) {
                # -cmatch, NOT -match. PowerShell's -match is case-INSENSITIVE and
                # Claude Code's matchers are not, so a matcher of 'read|edit|bash'
                # would be reported clean while the gate is never invoked at all -
                # the very defect this section exists to catch.
                $badMatchers = @()
                foreach ($tool in $GateRequiredTools) {
                    $isCovered = $false
                    foreach ($oneMatcher in $gateMatchers) {
                        try {
                            if ($tool -cmatch ('^(?:' + $oneMatcher + ')$')) { $isCovered = $true }
                        }
                        catch {
                            # Report an unusable pattern ONCE, not once per tool.
                            if ($badMatchers -notcontains $oneMatcher) {
                                $badMatchers += $oneMatcher
                                Problem "The PreToolUse matcher '$oneMatcher' for keel-plugins-gate.ps1 is not a usable pattern: $($_.Exception.Message.Split([char]10)[0])"
                            }
                            $isCovered = $true   # already reported; do not also report it as missing
                        }
                    }
                    if (-not $isCovered) { $missingTools += $tool }
                }
            }
            if ($missingTools.Count -gt 0) {
                Problem ("The PreToolUse matcher for keel-plugins-gate.ps1 does not name: " +
                         ($missingTools -join ', ') +
                         ". The gate handles those tools but will never be invoked for them, so its code for them is unreachable. Matcher is '" + $covered + "'.")
            }
            else {
                Ran ("gate wiring: matcher '{0}' covers all {1} required tool(s)" -f $covered, $GateRequiredTools.Count)
            }
        }
    }
}

# --- 9. the charter gate still behaves: run its committed suite -------------
#
# Charter P11 names "a checker that is not wired to anything" as a violation, and
# scripts/test-plugins-gate.ps1 exists precisely so the gate's behaviour can be
# re-checked rather than re-argued. This is the wire.
#
# -Strict ONLY, so the commit gate stays fast. The suite spawns one powershell.exe
# per case. That is a per-push cost, not a per-commit one.
#
# ITS RUNTIME IS NOT A STABLE NUMBER. With no code change between runs, the first
# run can take several times as long as the runs after it, so any single figure is
# whichever run happened to be measured. Budget for the cold one.
#
# Do not trust a case count written here either: the count below is parsed from the
# suite's own output on every run, which is the point of it.
if ($Strict) {
    $suitePath = Join-Path $RepoRoot 'scripts\test-plugins-gate.ps1'
    if (-not (Test-Path -LiteralPath $suitePath)) {
        Problem 'scripts/test-plugins-gate.ps1 is missing. The charter gate ships with the suite that re-checks it (charter P11).'
    }
    else {
        # Native call, so no bare 2>&1 and no reliance on $ErrorActionPreference:
        # under 'Stop', 2>&1 turns a native tool's stderr into a terminating error.
        # The EXIT CODE decides.
        $priorPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $suiteOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $suitePath
        $suiteCode   = $LASTEXITCODE
        $ErrorActionPreference = $priorPreference

        if ($suiteCode -ne 0) {
            Problem "scripts/test-plugins-gate.ps1 reported failures (exit $suiteCode). The repo-local charter gate does not behave as specified."
            foreach ($outLine in @($suiteOutput)) {
                if (-not [string]::IsNullOrWhiteSpace($outLine)) { Note $outLine }
            }
        }
        else {
            # A DECLARED coupling to another script's output wording, taken openly.
            # test-plugins-gate.ps1 has no -Json and no machine-readable surface, and
            # adding one would be a change to that file. So the count is parsed out of
            # its prose - and an unparseable summary is a PROBLEM, never a zero and
            # never a silent skip. That is the whole difference between this and an
            # undeclared coupling to the wording of another script's output, which
            # fails by going quiet.
            #
            # Explicit loop, not a Where-Object: $Matches set inside a pipeline
            # scriptblock does not reliably survive to the caller under strict mode.
            $suiteCases = -1
            $suiteFails = -1
            foreach ($suiteLine in @($suiteOutput)) {
                if ($suiteLine -match '^test-plugins-gate:\s+(\d+)\s+case\(s\),\s+working tree\s+(\d+)\s+failure\(s\)') {
                    $suiteCases = [int]$Matches[1]
                    $suiteFails = [int]$Matches[2]
                }
            }
            if ($suiteCases -lt 0) {
                Problem ("scripts/test-plugins-gate.ps1 exited 0 but its summary line could not be parsed, so this gate cannot say how many cases actually ran. " +
                         "Expected a line matching: test-plugins-gate: <n> case(s), working tree <n> failure(s). If the suite's output format moved, move this pattern with it.")
                foreach ($suiteLine in @($suiteOutput)) {
                    if (-not [string]::IsNullOrWhiteSpace($suiteLine)) { Note $suiteLine }
                }
            }
            else {
                Ran ("gate suite: {0} case(s), {1} failure(s) (scripts/test-plugins-gate.ps1)" -f $suiteCases, $suiteFails)
            }
        }
    }
}

# --- 11. the quarantine refusals still behave: run their committed suite -----
#
# Section 9's sibling, and deliberately a sibling rather than an extension of it:
# scripts/test-plugins-gate.ps1 is the CHARTER GATE's suite and shares none of its
# machinery with quarantine - no marker file, no PreToolUse payload, no tool name. One
# file answering two unrelated questions is the P10 error, and its case count would stop
# meaning one thing.
#
# WHY THIS EXISTS AT ALL. Charter P23 is enforced for every quarantined project through
# three lines of code, and a mechanism that guards projects needs a test as much as the
# charter gate does. P11 names "a checker that is not wired to anything" as a
# violation, which is why the suite is here and not left to be run by hand.
#
# COST: around ten seconds. Read section 9's note on cold-versus-warm before budgeting a
# push against that.
#
# -Strict ONLY, same as section 9, so the commit gate stays fast.
if ($Strict) {
    $quarPath = Join-Path $RepoRoot 'scripts\test-quarantine.ps1'
    if (-not (Test-Path -LiteralPath $quarPath)) {
        Problem 'scripts/test-quarantine.ps1 is missing. The quarantine refusals ship with the suite that re-checks them (charter P11).'
    }
    else {
        # Native call, so no bare 2>&1 and no reliance on $ErrorActionPreference:
        # under 'Stop', 2>&1 turns a native tool's stderr into a terminating error.
        # The EXIT CODE decides.
        $quarPrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $quarOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $quarPath
        $quarCode   = $LASTEXITCODE
        $ErrorActionPreference = $quarPrior

        if ($quarCode -ne 0) {
            Problem "scripts/test-quarantine.ps1 reported failures (exit $quarCode). A quarantine refusal does not behave as specified (charter P23)."
            foreach ($quarLine in @($quarOutput)) {
                if (-not [string]::IsNullOrWhiteSpace($quarLine)) { Note $quarLine }
            }
        }
        else {
            # The same DECLARED coupling to another script's output wording that section 9
            # takes, and taken openly for the same reason: an unparseable summary is a
            # PROBLEM, never a zero and never a silent skip.
            #
            # Explicit loop, not a Where-Object: $Matches set inside a pipeline
            # scriptblock does not reliably survive to the caller under strict mode.
            $quarCases = -1
            $quarFails = -1
            foreach ($quarLine in @($quarOutput)) {
                if ($quarLine -match '^test-quarantine:\s+(\d+)\s+case\(s\),\s+(\d+)\s+failure\(s\)') {
                    $quarCases = [int]$Matches[1]
                    $quarFails = [int]$Matches[2]
                }
            }
            if ($quarCases -lt 0) {
                Problem ("scripts/test-quarantine.ps1 exited 0 but its summary line could not be parsed, so this gate cannot say how many cases actually ran. " +
                         "Expected a line matching: test-quarantine: <n> case(s), <n> failure(s). If the suite's output format moved, move this pattern with it.")
                foreach ($quarLine in @($quarOutput)) {
                    if (-not [string]::IsNullOrWhiteSpace($quarLine)) { Note $quarLine }
                }
            }
            else {
                Ran ("quarantine suite: {0} case(s), {1} failure(s) (scripts/test-quarantine.ps1)" -f $quarCases, $quarFails)
            }
        }
    }
}

# --- 10. the project document index is not stale ----------------------------
#
# Section 3's sibling, and it sits here rather than beside it only to keep the diff
# readable - the numbering follows the order sections were added, not an order of
# operations.
#
# Charter P11 requires a drift check on every generated artifact. README.md and
# ARCHITECTURE.html are checked in section 3; reference/INDEX.md, generated from a
# project's own documents by keel-index.ps1, is checked here.
#
# It runs at BOTH gates, exactly where gen-suite-docs already runs: a push-only
# third class of generated artifact has no justification anyone could state later.
# The check is cheap; the slow gate suite above stays -Strict.
#
# Presence-guarded in both directions, because the wiring must not assume an index
# exists: a repo that is not a keel project, or a project that has not built an
# index yet, must not FAIL this gate - it is reported as skipped, and the skip is
# visible in the ran ledger rather than silent.
$IndexScript = Join-Path $RepoRoot 'plugins\keel-project\skills\keel-project-context\wrappers\keel-index.ps1'
$ProjectFile = Join-Path $RepoRoot 'keel.json'
$IndexFile   = Join-Path $RepoRoot 'reference\INDEX.md'

if (-not (Test-Path -LiteralPath $ProjectFile)) {
    Ran 'index: skipped - this repo has no keel.json, so it is not a keel project'
}
elseif (-not (Test-Path -LiteralPath $IndexFile)) {
    Ran 'index: skipped - no reference/INDEX.md exists yet, so there is no generated artifact to drift'
}
elseif (-not (Test-Path -LiteralPath $IndexScript)) {
    Problem 'reference/INDEX.md exists but plugins/keel-project/skills/keel-project-context/wrappers/keel-index.ps1 does not, so the index cannot be checked. A generated file with no checker is charter P11''s own example of a violation.'
}
else {
    # No bare 2>&1 on a native call. keel-index writes its drift lines to STDOUT and
    # nothing at all to stderr on that path, but its Fail helper (exit 91, no project
    # resolved) writes to [Console]::Error - and 2>&1 under Stop turns that into a
    # terminating error, so a working call would look broken. The EXIT CODE decides.
    $indexPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $indexOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $IndexScript
    $indexCode   = $LASTEXITCODE
    $ErrorActionPreference = $indexPreference

    if ($indexCode -eq 0) {
        Ran 'index: reference/INDEX.md is current (keel-index.ps1 exit 0)'
    }
    else {
        Problem ("reference/INDEX.md is stale or unreadable (keel-index.ps1 exit $indexCode). " +
                 "Run: powershell -File plugins/keel-project/skills/keel-project-context/wrappers/keel-index.ps1 -Write")
        foreach ($indexLine in @($indexOutput)) {
            if (-not [string]::IsNullOrWhiteSpace($indexLine)) { Note $indexLine }
        }
    }
}

# --- 12. the wrapper's help block names every verb its switch exposes -------
#
# Why this rung exists (charter P13): keel-state.ps1 prints a verb list when run
# with no arguments, and that list is the ONLY place a session is told what the
# wrapper can do - sessions are told to run it with no arguments for exactly that.
# Nothing else checks that the list matches the switch, and a verb the list leaves
# out is a verb nobody uses.
#
# WHY THIS ONE PARSES WHERE SECTION 8 REFUSES TO. Section 8 says a checker carrying
# its own parser is a second thing that can be wrong, and writes its required list
# out by hand. That reasoning does not transfer: section 8 compares a CONFIG file
# against a CODE file, so one of the two sides has to be stated somewhere. Here
# both lists live in the SAME file and the whole defect is drift BETWEEN them, so a
# written-out copy would be a third home for the verb list (charter P10) and would
# go stale on the next verb added - which is the failure mode rather than the fix.
#
# THE TRAP THIS SECTION IS MOST LIKELY TO FALL INTO is passing because it parsed
# nothing. When the two lists agree, a check that silently matches zero verbs on
# each side looks identical to one that matched every verb on each. Three guards,
# and the third is the one that actually holds: an empty list on either side is a
# PROBLEM; the ran line prints BOTH counts so a zero is visible; and the section
# must be shown FAILING in both directions before it is believed. Deleting one
# verb from a help-block line fires the exposed-but-undocumented direction; adding
# a verb the switch does not have fires the other. RENAMING a switch case fires
# BOTH at once - the new name is undocumented and the old one is now unexposed -
# so it does not isolate either direction, which is why the second mutation adds
# rather than renames.
#
# Runs at BOTH gates. It is a regex over one file that is already read elsewhere in
# this script, so there is no cost argument for making it -Strict only.
$helpWrappers = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'plugins') -Recurse -File -Filter 'keel-state.ps1' -ErrorAction SilentlyContinue)
if ($helpWrappers.Count -ne 1) {
    Problem ("Expected exactly one keel-state.ps1 under plugins/, found {0}. The help-block check cannot say which wrapper it is reading, and section 5 skips every file with this name, so a second copy is invisible to both." -f $helpWrappers.Count)
}
else {
    $helpSource = Get-Content -LiteralPath $helpWrappers[0].FullName -Raw -Encoding UTF8

    # The switch's top-level cases: a single-quoted verb at column 0 followed by an
    # opening brace. The column-0 anchor is what discriminates - without it the same
    # pattern also matches the cases of nested switches further in.
    $helpSwitchVerbs = @()
    foreach ($sv in [regex]::Matches($helpSource, "(?m)^'([a-z][a-z0-9-]*)' \{")) {
        $helpSwitchVerbs += $sv.Groups[1].Value
    }

    # The no-argument block, from its guard to the closing brace at column 0.
    $helpBlockMatch = [regex]::Match($helpSource, '(?ms)^if \(\[string\]::IsNullOrWhiteSpace\(\$Command\)\) \{.*?^\}')
    $helpListedVerbs = @()
    if ($helpBlockMatch.Success) {
        foreach ($hl in [regex]::Matches($helpBlockMatch.Value, '(?m)^\s*Write-Output "([^"]*)"')) {
            $helpLine = $hl.Groups[1].Value -replace '^\s*[A-Za-z]+:\s*', ''
            $helpTokens = @($helpLine -split '\s+' | Where-Object { $_ -ne '' })
            if ($helpTokens.Count -eq 0) { continue }
            # A verb line is ONLY verbs. Every prose line in that block carries a
            # capital, an apostrophe or a bracket, and the title line carries dots,
            # so one non-conforming token rejects the whole line.
            $helpAllVerbs = $true
            foreach ($ht in $helpTokens) { if ($ht -notmatch '^[a-z][a-z0-9-]*$') { $helpAllVerbs = $false } }
            if ($helpAllVerbs) { $helpListedVerbs += $helpTokens }
        }
    }

    if (-not $helpBlockMatch.Success) {
        Problem 'Could not find keel-state.ps1''s no-argument help block. It is the only place a session is told what verbs exist, and this check cannot confirm it matches the switch.'
    }
    elseif ($helpSwitchVerbs.Count -eq 0 -or $helpListedVerbs.Count -eq 0) {
        Problem ("The help-block check parsed {0} switch verb(s) and {1} listed verb(s); a zero on either side means this check matched nothing rather than that the two agree." -f $helpSwitchVerbs.Count, $helpListedVerbs.Count)
    }
    else {
        $helpMissing = @($helpSwitchVerbs | Where-Object { $helpListedVerbs -notcontains $_ })
        $helpExtra   = @($helpListedVerbs | Where-Object { $helpSwitchVerbs -notcontains $_ })
        if ($helpMissing.Count -gt 0) {
            Problem ("keel-state.ps1 exposes verb(s) its no-argument help block does not name: {0}. A verb nobody is told about is a verb nobody uses." -f ($helpMissing -join ', '))
        }
        if ($helpExtra.Count -gt 0) {
            Problem ("keel-state.ps1's help block names verb(s) the switch does not expose: {0}. Running one returns exit 90, Unknown command." -f ($helpExtra -join ', '))
        }
        if ($helpMissing.Count -eq 0 -and $helpExtra.Count -eq 0) {
            Ran ("wrapper help: {0} verb(s) in the switch, {1} named in the no-argument help block, same set" -f $helpSwitchVerbs.Count, $helpListedVerbs.Count)
        }
    }
}

# --- 13. line terminators match the pin git resolves ------------------------
#
# .gitattributes pins *.ps1 to CRLF and *.md, *.json, *.html, *.txt and
# .githooks/* to LF, and this section checks that the working tree obeys it. git
# normalises on read, so `git status` is clean and `git diff` is empty while the
# file on disk is wrong - the working tree diverges from what the repository
# checks out and no other instrument says so. Wrong terminators kept reaching the
# working tree while every other check stayed green; a rule enforced only in prose
# kept failing at its rung, and charter P13's ladder says such a rule earns the next
# one. This is that rung.
#
# The state wrapper's own handoff verb writes CRLF into an LF-pinned tree, and
# every committed blob still reads clean because git normalises it. Every handoff
# write therefore recreates the condition for its own commit, which is exactly
# what the standing write-repair-rebuild-commit order requires and this section
# enforces.
#
# TWO FILE LISTS, DELIBERATELY, AND THEY DO NOT REACH THE SAME THINGS. At
# -CommitGate only what is STAGED, matching this script's contract for staged
# checks: a divergence in a file nobody touched must not refuse an unrelated
# commit. Everywhere else, every tracked file - so a push still cannot carry one.
#
# BE CLEAR WHAT THE STAGED LIMB CANNOT SEE, because the obvious reading of the
# paragraph above overstates it. `git add` normalises the blob on the way in, so a
# file whose ONLY divergence is its terminators produces no cached diff and
# `git diff --cached --name-only` does not list it at all: a CRLF-converted copy
# of an LF-pinned document, staged, gives `0 staged file(s)` here.
# That is exactly the shape of a handoff document written CRLF, and it is how such
# documents go unnoticed. So the staged limb catches a NEW or CONTENT-CHANGED file
# whose terminators are wrong - the case a session creates while working - and
# -Strict at push is what catches pure terminator drift in a file nobody edited.
#
# THE INVARIANT IS OVER TERMINATORS, NOT OVER A LINE COUNT. "CRLF pairs equals line
# count" is the natural rule and it is wrong: a file with no trailing newline has
# pairs = lines - 1 and is correct, and many tracked files end without one. So:
# under a crlf pin every 0a must be preceded by 0d and no 0d may stand alone; under
# an lf pin there may be no 0d at all. Both are true of an empty file, which is
# the right answer for one.
$eolPaths = $null
$eolScope = 'tracked'
if ($CommitGate) {
    $eolScope = 'staged'
    $eolPaths = @(Get-StagedFiles)
}
else {
    try { $eolPaths = @(& git -C $RepoRoot ls-files 2>$null) }
    catch { $eolPaths = $null }
}

if ($null -eq $eolPaths) {
    Problem 'line endings: git could not list the files to check, so nothing was checked. An empty answer from git is not an empty set of files, and treating it as one is how a gate reports clean while running nothing.'
}
else {
    $eolPins = Get-EolPinSet -RelPaths $eolPaths
    if ($null -eq $eolPins) {
        Problem 'line endings: git check-attr could not resolve the eol pins, so nothing was checked. Not a clean run.'
    }
    else {
        $eolChecked = 0
        $eolSkipped = 0
        foreach ($rel in $eolPaths) {
            $pin = ''
            if ($eolPins.ContainsKey($rel)) { $pin = $eolPins[$rel] }
            if ($pin -ne 'lf' -and $pin -ne 'crlf') { $eolSkipped++; continue }

            $full = Join-Path $RepoRoot $rel
            # A staged deletion is listed and is not on disk. Not a problem.
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $eolSkipped++; continue }

            $bytes = $null
            try { $bytes = [System.IO.File]::ReadAllBytes($full) }
            catch { $bytes = $null }
            if ($null -eq $bytes) {
                Problem "line endings: $rel is pinned eol=$pin and could not be read. A file the check cannot open is not a file that passed."
                continue
            }

            $cr = 0; $lf = 0; $crlf = 0; $nul = $false
            for ($i = 0; $i -lt $bytes.Length; $i++) {
                $b = $bytes[$i]
                if ($b -eq 0)  { $nul = $true; break }
                if ($b -eq 13) { $cr++ }
                if ($b -eq 10) {
                    $lf++
                    if ($i -gt 0 -and $bytes[$i - 1] -eq 13) { $crlf++ }
                }
            }
            if ($nul) { $eolSkipped++; continue }

            $eolChecked++
            if ($pin -eq 'lf') {
                if ($cr -ne 0) {
                    Problem ("$rel is pinned eol=lf and carries $cr carriage return(s) in the working tree. git normalises on read, so git status and git diff are both silent - repair it rather than committing a tree that differs from what the repo checks out.")
                }
            }
            else {
                if ($lf -ne $crlf -or $cr -ne $crlf) {
                    Problem ("$rel is pinned eol=crlf but its terminators do not match: $lf line feed(s), $crlf CRLF pair(s), $cr carriage return(s). Every LF must be preceded by a CR and no CR may stand alone.")
                }
            }
        }
        Ran ("line endings: {0} {1} file(s) with an eol pin checked against it, {2} skipped as unpinned, absent or binary" -f $eolChecked, $eolScope, $eolSkipped)
    }
}

# --- 14. the outward-act guard still behaves: run its committed suite --------
#
# The third sibling, and a sibling for the reason sections 9 and 11 are siblings
# rather than one file: scripts/test-outward-guard.ps1's subject is the FIVE
# outward code points, which share no machinery with quarantine's three (a
# per-project keel.json flag) or with the charter gate's marker file. One file
# answering three unrelated questions is the P10 error, and each suite's case
# count would stop meaning one thing.
#
# WHY THIS EXISTS AT ALL. A fixture that overrides USERPROFILE into the temp
# directory sandboxes STATE and nothing else, so a verifier following the
# prescribed fixture pattern could comment on and close a real GitHub issue. P11
# names "a checker that is not wired to anything" as a violation, which is why the
# suite is here and not left to be run by hand.
#
# COST: tens of seconds, more when cold. Read section 9's note on cold-versus-warm
# before budgeting a push against that.
#
# -Strict ONLY, same as sections 9 and 11, so the commit gate stays fast.
if ($Strict) {
    $owPath = Join-Path $RepoRoot 'scripts\test-outward-guard.ps1'
    if (-not (Test-Path -LiteralPath $owPath)) {
        Problem 'scripts/test-outward-guard.ps1 is missing. The outward-act guard ships with the suite that re-checks it (charter P11).'
    }
    else {
        # Native call, so no bare 2>&1 and no reliance on $ErrorActionPreference:
        # under 'Stop', 2>&1 turns a native tool's stderr into a terminating error.
        # The EXIT CODE decides.
        $owPrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $owOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $owPath
        $owCode   = $LASTEXITCODE
        $ErrorActionPreference = $owPrior

        if ($owCode -ne 0) {
            Problem "scripts/test-outward-guard.ps1 reported failures (exit $owCode). An outward act is reachable from a sandboxed run, or the guard refuses something it should not."
            foreach ($owLine in @($owOutput)) {
                if (-not [string]::IsNullOrWhiteSpace($owLine)) { Note $owLine }
            }
        }
        else {
            # The same DECLARED coupling to another script's output wording that
            # sections 9 and 11 take, and taken openly for the same reason: an
            # unparseable summary is a PROBLEM, never a zero and never a silent
            # skip.
            #
            # Explicit loop, not a Where-Object: $Matches set inside a pipeline
            # scriptblock does not reliably survive to the caller under strict mode.
            $owCases = -1
            $owFails = -1
            foreach ($owLine in @($owOutput)) {
                if ($owLine -match '^test-outward-guard:\s+(\d+)\s+case\(s\),\s+(\d+)\s+failure\(s\)') {
                    $owCases = [int]$Matches[1]
                    $owFails = [int]$Matches[2]
                }
            }
            if ($owCases -lt 0) {
                Problem ("scripts/test-outward-guard.ps1 exited 0 but its summary line could not be parsed, so this gate cannot say how many cases actually ran. " +
                         "Expected a line matching: test-outward-guard: <n> case(s), <n> failure(s). If the suite's output format moved, move this pattern with it.")
                foreach ($owLine in @($owOutput)) {
                    if (-not [string]::IsNullOrWhiteSpace($owLine)) { Note $owLine }
                }
            }
            else {
                Ran ("outward guard suite: {0} case(s), {1} failure(s) (scripts/test-outward-guard.ps1)" -f $owCases, $owFails)
            }
        }
    }
}

# --- 15. the signal record's write points still behave: run their suite ------
#
# The fourth sibling, and a sibling for the reason sections 9, 11 and 14 are
# siblings rather than one file. scripts/test-signal-judgement.ps1's subject is
# what the signal RECORD holds and what 'signals' prints - the judge-signal
# append, refusals guarding it, and the 'addresses' key resolve-signal persists.
# That shares no machinery with the charter gate's marker file, with
# quarantine's per-project keel.json flag, or with the five outward invocations,
# and judge-signal makes no process call at all. One file answering two unrelated
# questions is the charter P10 error and each suite's case count would stop
# meaning one thing.
#
# WHY THIS EXISTS AT ALL. The store must distinguish a signal judged real and
# consciously not scheduled from one nobody has ever opened, and must persist the
# -Addresses answer resolve-signal makes mandatory. Both are additive writes onto
# a record that already-stored signals carry, so the thing that must not regress
# is that every record lacking the new keys still renders exactly as it did. P11
# names "a checker that is not wired to anything" as a violation, which is why the
# suite runs here rather than being left to be run by hand.
#
# COST: the case count is not written here. A count hand-maintained beside the one
# this script PRINTS from the suite's own summary line a few lines below can
# disagree with it silently; the printed one is right. Read section 9's note on
# cold-versus-warm before budgeting a push against this suite.
#
# -Strict ONLY, same as sections 9, 11 and 14, so the commit gate stays fast.
if ($Strict) {
    $sjPath = Join-Path $RepoRoot 'scripts\test-signal-judgement.ps1'
    if (-not (Test-Path -LiteralPath $sjPath)) {
        Problem 'scripts/test-signal-judgement.ps1 is missing. The signal record''s write points ship with the suite that re-checks them (charter P11).'
    }
    else {
        # Native call, so no bare 2>&1 and no reliance on $ErrorActionPreference:
        # under 'Stop', 2>&1 turns a native tool's stderr into a terminating error.
        # The EXIT CODE decides.
        $sjPrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $sjOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sjPath
        $sjCode   = $LASTEXITCODE
        $ErrorActionPreference = $sjPrior

        if ($sjCode -ne 0) {
            Problem "scripts/test-signal-judgement.ps1 reported failures (exit $sjCode). A signal record's write point, one of judge-signal's refusals, or the 'signals' rendering has moved."
            foreach ($sjLine in @($sjOutput)) {
                if (-not [string]::IsNullOrWhiteSpace($sjLine)) { Note $sjLine }
            }
        }
        else {
            # The same DECLARED coupling to another script's output wording that
            # sections 9, 11 and 14 take, and taken openly for the same reason: an
            # unparseable summary is a PROBLEM, never a zero and never a silent
            # skip.
            #
            # Explicit loop, not a Where-Object: $Matches set inside a pipeline
            # scriptblock does not reliably survive to the caller under strict mode.
            $sjCases = -1
            $sjFails = -1
            foreach ($sjLine in @($sjOutput)) {
                if ($sjLine -match '^test-signal-judgement:\s+(\d+)\s+case\(s\),\s+(\d+)\s+failure\(s\)') {
                    $sjCases = [int]$Matches[1]
                    $sjFails = [int]$Matches[2]
                }
            }
            if ($sjCases -lt 0) {
                Problem ("scripts/test-signal-judgement.ps1 exited 0 but its summary line could not be parsed, so this gate cannot say how many cases actually ran. " +
                         "Expected a line matching: test-signal-judgement: <n> case(s), <n> failure(s). If the suite's output format moved, move this pattern with it.")
                foreach ($sjLine in @($sjOutput)) {
                    if (-not [string]::IsNullOrWhiteSpace($sjLine)) { Note $sjLine }
                }
            }
            else {
                Ran ("signal judgement suite: {0} case(s), {1} failure(s) (scripts/test-signal-judgement.ps1)" -f $sjCases, $sjFails)
            }
        }
    }
}

# --- 16. no private name in anything this repo carries ----------------------
#
# Defined above section 1, where its reasoning is written; called here, at both gates.
Invoke-PrivateNameCheck

# --- 17. the private-names check still behaves: run its committed suite ------
#
# The fifth sibling of sections 9, 11, 14 and 15, and a sibling for the same reason:
# scripts/test-private-names.ps1's subject is section 16 alone, which shares no
# machinery with the charter gate, quarantine, the outward guard or the signal record.
# A checker that is not wired to anything is a violation of charter P11.
#
# The suite builds one scratch repository with a local bare remote under the temp
# directory and runs a copy of this script in it once per case, so it costs one
# powershell.exe per case. -Strict ONLY, like the other suites, so the commit gate stays fast.
if ($Strict) {
    $pnSuitePath = Join-Path $RepoRoot 'scripts\test-private-names.ps1'
    if (-not (Test-Path -LiteralPath $pnSuitePath)) {
        Problem 'scripts/test-private-names.ps1 is missing. The private-names check ships with the suite that re-checks it (charter P11).'
    }
    else {
        # Native call, so no bare 2>&1 and no reliance on $ErrorActionPreference.
        # The EXIT CODE decides.
        $pnSuitePrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $pnSuiteOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pnSuitePath
        $pnSuiteCode   = $LASTEXITCODE
        $ErrorActionPreference = $pnSuitePrior

        if ($pnSuiteCode -ne 0) {
            Problem "scripts/test-private-names.ps1 reported failures (exit $pnSuiteCode). The private-names check does not behave as specified."
            foreach ($pnSuiteLine in @($pnSuiteOutput)) {
                if (-not [string]::IsNullOrWhiteSpace($pnSuiteLine)) { Note $pnSuiteLine }
            }
        }
        else {
            # A DECLARED coupling to another script's output wording, taken openly as
            # sections 9, 11, 14 and 15 take theirs: the count is parsed from the suite's
            # summary line, and an unparseable summary is a PROBLEM, never a zero and
            # never a silent skip.
            #
            # Explicit loop, not a Where-Object: $Matches set inside a pipeline
            # scriptblock does not reliably survive to the caller under strict mode.
            $pnSuiteCases = -1
            $pnSuiteFails = -1
            foreach ($pnSuiteLine in @($pnSuiteOutput)) {
                if ($pnSuiteLine -match '^test-private-names:\s+(\d+)\s+case\(s\),\s+(\d+)\s+failure\(s\)') {
                    $pnSuiteCases = [int]$Matches[1]
                    $pnSuiteFails = [int]$Matches[2]
                }
            }
            if ($pnSuiteCases -lt 0) {
                Problem ("scripts/test-private-names.ps1 exited 0 but its summary line could not be parsed, so this gate cannot say how many cases actually ran. " +
                         "Expected a line matching: test-private-names: <n> case(s), <n> failure(s). If the suite's output format moved, move this pattern with it.")
                foreach ($pnSuiteLine in @($pnSuiteOutput)) {
                    if (-not [string]::IsNullOrWhiteSpace($pnSuiteLine)) { Note $pnSuiteLine }
                }
            }
            else {
                Ran ("private names suite: {0} case(s), {1} failure(s) (scripts/test-private-names.ps1)" -f $pnSuiteCases, $pnSuiteFails)
            }
        }
    }
}

# --- 18. no record id of keel's own work in the product ---------------------
#
# Defined above section 1, where its reasoning is written; called here, at both gates.
Invoke-HistoryIdCheck

# --- 19. the history check still behaves: run its committed suite -----------
#
# The sixth sibling of sections 9, 11, 14, 15 and 17, and a sibling for the same reason:
# scripts/test-history-ids.ps1's subject is section 18 alone, which shares no machinery
# with the other suites' subjects, so its case count means one thing. A checker that is
# not wired to anything is a violation of charter P11.
#
# The suite builds one scratch repository under the temp directory and runs a copy of
# this script in it once per case, so it costs one powershell.exe per case. -Strict ONLY,
# like the other suites, so the commit gate stays fast.
if ($Strict) {
    $hiSuitePath = Join-Path $RepoRoot 'scripts\test-history-ids.ps1'
    if (-not (Test-Path -LiteralPath $hiSuitePath)) {
        Problem 'scripts/test-history-ids.ps1 is missing. The history check ships with the suite that re-checks it (charter P11).'
    }
    else {
        # Native call, so no bare 2>&1 and no reliance on $ErrorActionPreference.
        # The EXIT CODE decides.
        $hiSuitePrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $hiSuiteOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hiSuitePath
        $hiSuiteCode   = $LASTEXITCODE
        $ErrorActionPreference = $hiSuitePrior

        if ($hiSuiteCode -ne 0) {
            Problem "scripts/test-history-ids.ps1 reported failures (exit $hiSuiteCode). The history check does not behave as specified."
            foreach ($hiSuiteLine in @($hiSuiteOutput)) {
                if (-not [string]::IsNullOrWhiteSpace($hiSuiteLine)) { Note $hiSuiteLine }
            }
        }
        else {
            # A DECLARED coupling to another script's output wording, taken openly as
            # sections 9, 11, 14, 15 and 17 take theirs: the count is parsed from the
            # suite's summary line, and an unparseable summary is a PROBLEM, never a zero
            # and never a silent skip.
            #
            # Explicit loop, not a Where-Object: $Matches set inside a pipeline
            # scriptblock does not reliably survive to the caller under strict mode.
            $hiSuiteCases = -1
            $hiSuiteFails = -1
            foreach ($hiSuiteLine in @($hiSuiteOutput)) {
                if ($hiSuiteLine -match '^test-history-ids:\s+(\d+)\s+case\(s\),\s+(\d+)\s+failure\(s\)') {
                    $hiSuiteCases = [int]$Matches[1]
                    $hiSuiteFails = [int]$Matches[2]
                }
            }
            if ($hiSuiteCases -lt 0) {
                Problem ("scripts/test-history-ids.ps1 exited 0 but its summary line could not be parsed, so this gate cannot say how many cases actually ran. " +
                         "Expected a line matching: test-history-ids: <n> case(s), <n> failure(s). If the suite's output format moved, move this pattern with it.")
                foreach ($hiSuiteLine in @($hiSuiteOutput)) {
                    if (-not [string]::IsNullOrWhiteSpace($hiSuiteLine)) { Note $hiSuiteLine }
                }
            }
            else {
                Ran ("history ids suite: {0} case(s), {1} failure(s) (scripts/test-history-ids.ps1)" -f $hiSuiteCases, $hiSuiteFails)
            }
        }
    }
}

# --- 20. the wrapper's write lock still behaves: run its committed suite --------
#
# The seventh sibling of sections 9, 11, 14, 15, 17 and 19. scripts/test-concurrent-writes.ps1
# has two keel commands write one project, keel.json or the signal store at overlapping moments
# and checks that every write lands or is refused with exit 89, never lost while its command
# reports success; it also holds the lock past the wait, changes a file under a paused writer and
# kills a writer holding the lock. A checker that is not wired to anything is a violation of
# charter P11.
#
# It starts a few dozen powershell.exe children and waits out one ten-second lock on purpose, so
# it costs about a minute. -Strict ONLY, like the other suites, so the commit gate stays fast.
if ($Strict) {
    $cwSuitePath = Join-Path $RepoRoot 'scripts\test-concurrent-writes.ps1'
    if (-not (Test-Path -LiteralPath $cwSuitePath)) {
        Problem 'scripts/test-concurrent-writes.ps1 is missing. The write lock ships with the suite that re-checks it (charter P11).'
    }
    else {
        # Native call, so no bare 2>&1 and no reliance on $ErrorActionPreference.
        # The EXIT CODE decides.
        $cwSuitePrior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $cwSuiteOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cwSuitePath
        $cwSuiteCode   = $LASTEXITCODE
        $ErrorActionPreference = $cwSuitePrior

        if ($cwSuiteCode -ne 0) {
            Problem "scripts/test-concurrent-writes.ps1 reported failures (exit $cwSuiteCode). The wrapper's write lock does not behave as specified."
            foreach ($cwSuiteLine in @($cwSuiteOutput)) {
                if (-not [string]::IsNullOrWhiteSpace($cwSuiteLine)) { Note $cwSuiteLine }
            }
        }
        else {
            # A DECLARED coupling to another script's output wording, taken openly as
            # sections 9, 11, 14, 15, 17 and 19 take theirs: the count is parsed from the
            # suite's summary line, and an unparseable summary is a PROBLEM, never a zero
            # and never a silent skip.
            #
            # Explicit loop, not a Where-Object: $Matches set inside a pipeline
            # scriptblock does not reliably survive to the caller under strict mode.
            $cwSuiteCases = -1
            $cwSuiteFails = -1
            foreach ($cwSuiteLine in @($cwSuiteOutput)) {
                if ($cwSuiteLine -match '^test-concurrent-writes:\s+(\d+)\s+case\(s\),\s+(\d+)\s+failure\(s\)') {
                    $cwSuiteCases = [int]$Matches[1]
                    $cwSuiteFails = [int]$Matches[2]
                }
            }
            if ($cwSuiteCases -lt 0) {
                Problem ("scripts/test-concurrent-writes.ps1 exited 0 but its summary line could not be parsed, so this gate cannot say how many cases actually ran. " +
                         "Expected a line matching: test-concurrent-writes: <n> case(s), <n> failure(s). If the suite's output format moved, move this pattern with it.")
                foreach ($cwSuiteLine in @($cwSuiteOutput)) {
                    if (-not [string]::IsNullOrWhiteSpace($cwSuiteLine)) { Note $cwSuiteLine }
                }
            }
            else {
                Ran ("concurrent writes suite: {0} case(s), {1} failure(s) (scripts/test-concurrent-writes.ps1)" -f $cwSuiteCases, $cwSuiteFails)
            }
        }
    }
}

# --- verdict ----------------------------------------------------------------
Write-Verdict
