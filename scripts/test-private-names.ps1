<#
    test-private-names.ps1 - the verification suite for the private-names check,
    section 16 of check-suite-docs.ps1.

    WHAT IT COVERS. The check refuses any entry of a per-machine list, read from
    %USERPROFILE%\.keel\private-names.txt, in the staged content of a commit and, at push,
    in every tracked file and in the message of every commit no remote holds yet. Each
    behaviour below has a control that must behave DIFFERENTLY, because a refusal that
    refuses everything is indistinguishable from one that reads the list:

      - a staged entry refuses, and the refusal names file, line and list line but never
        the entry; the same file without it passes
      - a path holding an entry refuses at both gates and is printed with the entry masked;
        the same content under a clean name passes
      - the commit gate reads the STAGED blob: an entry only in the working tree passes,
        the same change staged refuses
      - at push, an entry in a tracked file that is not staged refuses; reverted, it passes
      - at push, an entry in an unpushed commit message refuses; amended away it passes,
        and a commit already on the remote is not refused
      - with no list, both gates pass and print the not-checked line; with a list, that
        line is absent and the scan line is printed
      - a 'word:' entry matches a whole word with case, in a file and in a message; a plain
        entry matches anywhere, any case
      - a binary file is skipped; the same bytes without the NUL are not
      - an entry the check cannot pass to git is a problem, never a silent skip

    HOW IT REACHES THE CHECK ALONE. Every other validator section fails in a scratch
    repository, so the suite copies the validator into <scratch>\repo\scripts\ (untracked,
    so neither scan reads it) and runs that copy with -PrivateNamesOnly, which runs section
    16 and the verdict only. -AgainstValidator <path> runs the same cases against another
    copy - the way to show the suite can fail: point it at a copy whose matcher never
    matches and the case rows must fail.

    ISOLATION, VERIFIED BEFORE ANYTHING IS WRITTEN. The scratch root must resolve inside
    the system temp directory. USERPROFILE is overridden for each child only, so the child
    reads the fixture list and never the real one. Git variables a hook may export
    (GIT_DIR, GIT_INDEX_FILE and the like) are cleared first, and the suite refuses to run
    unless git resolves the scratch repository as its own top level - otherwise a run from
    inside a hook could commit into the repository being pushed.

    FIXTURE TERMS ARE ASSEMBLED AT RUN TIME. A real list may share a term with a fixture,
    and a literal here would make the real push gate refuse this file.

    IT PRINTS NO PATH AND NO FIXTURE TERM. Section 17 copies this suite's output into the
    validator's notes on a failure, and the scratch paths sit under the home folder. So a
    failure line carries the row name and the exit codes, a failed git step names only its
    subcommand (some arguments are commit messages holding a fixture term), and the suite
    never relays a child's output.

    Run it:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-private-names.ps1
      ... -AgainstValidator <path>   run the cases against another validator file

    Exit 0 = every case behaved. Exit 1 = at least one did not.

    Windows PowerShell 5.1 compatible. ASCII only.
#>

[CmdletBinding()]
param(
    [string]$AgainstValidator = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Every local in this file is Pn-prefixed, so none can collide with a parameter name.
$PnRepoRoot  = Split-Path -Parent $PSScriptRoot
$PnValidator = Join-Path $PnRepoRoot 'scripts\check-suite-docs.ps1'
if (-not [string]::IsNullOrWhiteSpace($AgainstValidator)) {
    $PnValidator = (Resolve-Path -LiteralPath $AgainstValidator).Path
}

$script:PnResults = @()

# Adds to a script-scope list and returns nothing: a function that both printed and
# returned a value would hand its caller an array of every line it emitted.
function Add-Result {
    param([string]$PnName, [bool]$PnOk, [string]$PnWhy)
    $script:PnResults += [pscustomobject]@{ Name = $PnName; Ok = $PnOk; Why = $PnWhy }
}

# A native tool's success text can arrive on stderr, and 2>&1 under 'Stop' turns it into
# a terminating error, so every native call sets Continue and lets the EXIT CODE decide.
function Invoke-PnGit {
    param([string[]]$PnGitArgs)
    $PnPrev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & git -C $script:PnRepo @PnGitArgs 2>$null
        $PnGitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $PnPrev }
    if ($PnGitCode -ne 0) { throw "fixture: git $($PnGitArgs[0]) failed (exit $PnGitCode)" }
}

function Invoke-PnCheck {
    param([string]$PnMode)
    $PnPrevProfile = $env:USERPROFILE
    $env:USERPROFILE = $script:PnHome
    $PnPrev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $PnLines = @()
    $PnCode = 0
    try {
        $PnLines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:PnCopy $PnMode -PrivateNamesOnly 2>&1 |
                   ForEach-Object { $_.ToString() }
        $PnCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PnPrev
        $env:USERPROFILE = $PnPrevProfile
    }
    return [pscustomobject]@{ Code = $PnCode; Text = (@($PnLines) -join "`n") }
}

# The list for the next run, or no list at all when $PnLines is $null.
function Set-PnList {
    param([string[]]$PnLines)
    $PnListFile = Join-Path $script:PnHome '.keel\private-names.txt'
    if ($null -eq $PnLines) {
        if (Test-Path -LiteralPath $PnListFile) { Remove-Item -LiteralPath $PnListFile -Force }
        return
    }
    [System.IO.File]::WriteAllText($PnListFile, (($PnLines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function Set-PnFile {
    param([string]$PnName, [string]$PnContent)
    [System.IO.File]::WriteAllText((Join-Path $script:PnRepo $PnName), $PnContent, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-PnHas {
    param([string]$PnHaystack, [string]$PnNeedle)
    return ($PnHaystack.IndexOf($PnNeedle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

# ---------------------------------------------------------------------------
# The cases
# ---------------------------------------------------------------------------
function Invoke-Cases {
    # Fixture terms, assembled so that no real list can match this file's own text.
    $PnTerm   = 'qz' + 'vfixture' + 'name'
    $PnMixed  = 'Qz' + 'VFixture' + 'Name'
    $PnUp     = 'E' + 'MU'
    $PnLow    = $PnUp.ToLower()
    $PnLonger = $PnLow + 'late'
    $PnShown  = '%USERPROFILE%\.keel\private-names.txt'
    $PnMain   = @('# fixture list', $PnTerm, "word:$PnUp")

    Invoke-PnGit @('remote', 'add', 'origin', $script:PnRemote)
    Set-PnFile 'base.txt' "base`n"
    Invoke-PnGit @('add', 'base.txt')
    Invoke-PnGit @('commit', '-q', '-m', 'base')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')

    # --- HARNESS CONTROL ---------------------------------------------------
    Set-PnList @('# comments only')
    $PnH = Invoke-PnCheck '-CommitGate'
    Add-Result 'HARNESS-CONTROL-validator-copy-runs' (($PnH.Code -eq 0) -and ($PnH.Text -match 'private names: 0 entr')) `
               "exit $($PnH.Code), wanted 0 and the scan line for an empty list"

    Set-PnList $PnMain

    # --- Group 1: a staged entry refuses, and the refusal never prints it ---------
    Set-PnFile 'notes.txt' "line one`nhas $PnMixed here`n"
    Invoke-PnGit @('add', 'notes.txt')
    $PnR = Invoke-PnCheck '-CommitGate'
    $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match 'notes\.txt line 2 ') -and ($PnR.Text -match 'list line 2 ') -and
            (-not (Test-PnHas $PnR.Text $PnTerm))
    Add-Result 'G1-staged-entry-refused-not-printed' $PnOk `
               "exit $($PnR.Code) - wanted non-zero, 'notes.txt line 2', 'list line 2', and the entry absent from the joined output"

    Set-PnFile 'notes.txt' "line one`nclean here`n"
    Invoke-PnGit @('add', 'notes.txt')
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'G1-control-same-file-clean-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"

    # --- a staged PATH holding the entry refuses, and is printed masked -------
    $PnBadName = "doc-$PnMixed.txt"
    Set-PnFile $PnBadName "clean content`n"
    Invoke-PnGit @('add', $PnBadName)
    $PnR = Invoke-PnCheck '-CommitGate'
    $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match 'a staged path holds the entry on list line 2 ') -and
            ($PnR.Text -match 'doc-\*{14}\.txt') -and (-not (Test-PnHas $PnR.Text $PnTerm))
    Add-Result 'G1-staged-path-refused-masked' $PnOk `
               "exit $($PnR.Code) - wanted non-zero, the path refusal for list line 2, the path masked, and the entry absent"
    Invoke-PnGit @('rm', '-q', '--cached', $PnBadName)
    Remove-Item -LiteralPath (Join-Path $script:PnRepo $PnBadName) -Force

    Set-PnFile 'doc-clean.txt' "clean content`n"
    Invoke-PnGit @('add', 'doc-clean.txt')
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'G1-control-same-content-clean-name-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"
    Invoke-PnGit @('rm', '-q', '--cached', 'doc-clean.txt')
    Remove-Item -LiteralPath (Join-Path $script:PnRepo 'doc-clean.txt') -Force

    # --- the commit gate reads the staged blob, not the working tree ------------
    Set-PnFile 'notes.txt' "line one`nhas $PnMixed here`n"
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'STAGED-working-tree-only-passes' ($PnR.Code -eq 0) `
               "exit $($PnR.Code), wanted 0 - the entry is in the working tree only, and the commit carries the staged blob"

    Invoke-PnGit @('add', 'notes.txt')
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'STAGED-control-same-change-staged-refused' (($PnR.Code -ne 0) -and ($PnR.Text -match 'notes\.txt line 2 ')) `
               "exit $($PnR.Code), wanted non-zero naming notes.txt line 2"

    Set-PnFile 'notes.txt' "line one`nclean here`n"
    Invoke-PnGit @('add', 'notes.txt')
    Invoke-PnGit @('commit', '-q', '-m', 'notes')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')

    # --- Group 2 file: at push, an unstaged entry in a tracked file refuses -------
    Set-PnFile 'notes.txt' "line one`nhas $PnMixed here`n"
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'G2-strict-unstaged-tracked-entry-refused' (($PnR.Code -ne 0) -and ($PnR.Text -match 'notes\.txt line 2 ')) `
               "exit $($PnR.Code), wanted non-zero naming notes.txt line 2"

    Invoke-PnGit @('checkout', '-q', '--', 'notes.txt')
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'G2-control-strict-reverted-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"

    # --- Group 2 path: at push, a tracked path holding the entry refuses ----------
    Set-PnFile $PnBadName "clean content`n"
    Invoke-PnGit @('add', $PnBadName)
    Invoke-PnGit @('commit', '-q', '-m', 'add a file')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')
    $PnR = Invoke-PnCheck '-Strict'
    $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match 'a tracked path holds the entry on list line 2 ') -and
            (-not (Test-PnHas $PnR.Text $PnTerm))
    Add-Result 'G2-strict-tracked-path-refused-masked' $PnOk `
               "exit $($PnR.Code) - wanted non-zero, the tracked path refusal for list line 2, and the entry absent"

    Invoke-PnGit @('mv', $PnBadName, 'doc-renamed.txt')
    Invoke-PnGit @('commit', '-q', '-m', 'rename a file')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'G2-control-strict-path-renamed-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"

    # --- Group 2 message: at push, an unpushed message refuses --------------------
    Invoke-PnGit @('commit', '-q', '--allow-empty', '-m', "message with $PnMixed inside")
    $PnR = Invoke-PnCheck '-Strict'
    $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match 'unpushed commit [0-9a-f]{7} ') -and ($PnR.Text -match 'list line 2 ') -and
            (-not (Test-PnHas $PnR.Text $PnTerm))
    Add-Result 'G2-strict-unpushed-message-refused-not-printed' $PnOk `
               "exit $($PnR.Code) - wanted non-zero, 'unpushed commit <sha>', 'list line 2', and the entry absent"

    Invoke-PnGit @('commit', '-q', '--amend', '--allow-empty', '-m', 'message made clean')
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'G2-control-strict-message-amended-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"

    Invoke-PnGit @('commit', '-q', '--allow-empty', '-m', "pushed with $PnMixed inside")
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'G2-control-strict-message-already-on-remote-passes' ($PnR.Code -eq 0) `
               "exit $($PnR.Code), wanted 0 - a commit the remote already holds is not this push's to refuse"

    # --- Group 3: no list, no check, and a line saying so -------------------------
    Set-PnFile 'staged.txt' "has $PnMixed here`n"
    Invoke-PnGit @('add', 'staged.txt')
    Set-PnList $null
    foreach ($PnMode in @('-CommitGate', '-Strict')) {
        $PnR = Invoke-PnCheck $PnMode
        $PnOk = ($PnR.Code -eq 0) -and (Test-PnHas $PnR.Text "NOT CHECKED - no list at $PnShown") -and ($PnR.Text -match 'did not run')
        Add-Result "G3-no-list$PnMode-passes-with-not-checked-line" $PnOk `
                   "exit $($PnR.Code) - wanted 0 and the not-checked line naming $PnShown, with an entry staged"
    }
    Set-PnList $PnMain
    foreach ($PnMode in @('-CommitGate', '-Strict')) {
        $PnR = Invoke-PnCheck $PnMode
        $PnOk = (-not ($PnR.Text -match 'NOT CHECKED - no list')) -and ($PnR.Text -match 'private names: 2 entr')
        Add-Result "G3-control-list$PnMode-scan-line-not-not-checked" $PnOk `
                   "wanted the scan line for 2 entries and no not-checked line"
    }
    Invoke-PnGit @('rm', '-q', '--cached', 'staged.txt')
    Remove-Item -LiteralPath (Join-Path $script:PnRepo 'staged.txt') -Force

    # --- Group 4: a word entry matches a whole word with case ---------------------
    # The two same-case rows are what prove the WORD boundary rather than only the case:
    # the upper-case term with a letter after it, and with a letter before it, must pass
    # under the word entry and refuse under the plain one.
    $PnWordCases = @(
        @{ Text = $PnUp;           Label = 'upper-term';            Word = $true;  Plain = $true },
        @{ Text = $PnLonger;       Label = 'longer-lower-word';     Word = $false; Plain = $true },
        @{ Text = $PnLow;          Label = 'lower-term';            Word = $false; Plain = $true },
        @{ Text = ($PnUp + 'X');   Label = 'upper-term-suffixed';   Word = $false; Plain = $true },
        @{ Text = ('X' + $PnUp);   Label = 'upper-term-prefixed';   Word = $false; Plain = $true }
    )
    foreach ($PnList in @(@{ Name = 'word'; Lines = @('# word list', "word:$PnUp") },
                          @{ Name = 'plain'; Lines = @('# plain list', $PnLow) })) {
        Set-PnList $PnList.Lines
        foreach ($PnWc in $PnWordCases) {
            Set-PnFile 'word.txt' "before $($PnWc.Text) after`n"
            Invoke-PnGit @('add', 'word.txt')
            $PnR = Invoke-PnCheck '-CommitGate'
            $PnRefused = ($PnR.Code -ne 0) -and ($PnR.Text -match 'word\.txt line 1 ')
            if ($PnList.Name -eq 'word') {
                $PnWant = [bool]$PnWc.Word
                $PnRow = "G4-word-entry-$($PnWc.Label)"
            }
            else {
                $PnWant = [bool]$PnWc.Plain
                $PnRow = "G4-control-plain-entry-$($PnWc.Label)"
            }
            $PnWantText = if ($PnWant) { 'refused' } else { 'passed' }
            Add-Result $PnRow ($PnRefused -eq $PnWant) "exit $($PnR.Code) - wanted the line $PnWantText"
        }
    }
    Invoke-PnGit @('rm', '-q', '--cached', 'word.txt')
    Remove-Item -LiteralPath (Join-Path $script:PnRepo 'word.txt') -Force

    # --- the word rule on a commit message ------------------------------------
    Set-PnList @('# word list', "word:$PnUp")
    Invoke-PnGit @('commit', '-q', '--allow-empty', '-m', "message holds $PnUp here")
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'MSG-word-entry-upper-term-refused' (($PnR.Code -ne 0) -and ($PnR.Text -match 'unpushed commit ')) `
               "exit $($PnR.Code), wanted non-zero naming the unpushed commit"
    Invoke-PnGit @('commit', '-q', '--amend', '--allow-empty', '-m', "message holds $PnLonger here")
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'MSG-control-word-entry-longer-lower-word-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"
    Invoke-PnGit @('commit', '-q', '--amend', '--allow-empty', '-m', "message holds $($PnUp)X here")
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'MSG-control-word-entry-upper-term-suffixed-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')

    # --- binary files are skipped --------------------------------------------
    Set-PnList $PnMain
    [System.IO.File]::WriteAllBytes((Join-Path $script:PnRepo 'blob.dat'),
        [byte[]](@(97, 98, 0, 99) + [System.Text.Encoding]::ASCII.GetBytes(" $PnMixed`n")))
    Invoke-PnGit @('add', 'blob.dat')
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'BINARY-staged-file-with-nul-skipped' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"
    [System.IO.File]::WriteAllBytes((Join-Path $script:PnRepo 'blob.dat'),
        [byte[]](@(97, 98, 99) + [System.Text.Encoding]::ASCII.GetBytes(" $PnMixed`n")))
    Invoke-PnGit @('add', 'blob.dat')
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'BINARY-control-same-bytes-without-nul-refused' (($PnR.Code -ne 0) -and ($PnR.Text -match 'blob\.dat line 1 ')) `
               "exit $($PnR.Code), wanted non-zero naming blob.dat line 1"
    Invoke-PnGit @('rm', '-q', '--cached', 'blob.dat')
    Remove-Item -LiteralPath (Join-Path $script:PnRepo 'blob.dat') -Force

    # --- an entry the check cannot use is a problem, not a silent skip ---------
    Set-PnList @('# unusable', ('bad' + '"' + 'entry'))
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'UNUSABLE-entry-with-quote-is-a-problem' (($PnR.Code -ne 0) -and ($PnR.Text -match 'list line 2 .*NOT CHECKED')) `
               "exit $($PnR.Code), wanted non-zero naming list line 2 as not checked"
    Set-PnList @('# usable', ('bad' + 'entry'))
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'UNUSABLE-control-same-entry-without-quote-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $PnValidator -PathType Leaf)) {
    [Console]::Error.WriteLine("test-private-names: the validator file to test does not exist.")
    exit 1
}

# Variables a git hook may export would point every scratch git call at the repository
# being committed or pushed. Clear them for this process and its children.
foreach ($PnVar in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
                     'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_COMMON_DIR', 'GIT_PREFIX', 'GIT_NAMESPACE')) {
    Remove-Item -LiteralPath "Env:\$PnVar" -ErrorAction SilentlyContinue
}

$PnTempBase = [System.IO.Path]::GetTempPath()
$PnTempRoot = Join-Path $PnTempBase ("keel-private-names-suite-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 12))

# The scratch root must resolve INSIDE the system temp directory before anything is written.
$PnTempBaseFull = (Get-Item -LiteralPath $PnTempBase).FullName.TrimEnd('\', '/')
New-Item -ItemType Directory -Path $PnTempRoot -Force | Out-Null
$PnTempRootFull = (Get-Item -LiteralPath $PnTempRoot).FullName.TrimEnd('\', '/')
if (-not $PnTempRootFull.StartsWith("$PnTempBaseFull$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine("test-private-names: refusing to run - scratch root does not resolve inside the temp directory.")
    exit 1
}

$script:PnHome   = Join-Path $PnTempRootFull 'home'
$script:PnRepo   = Join-Path $PnTempRootFull 'repo'
$script:PnRemote = Join-Path $PnTempRootFull 'remote.git'
$script:PnCopy   = Join-Path $script:PnRepo 'scripts\check-suite-docs.ps1'

$PnFailed = 0
try {
    New-Item -ItemType Directory -Path (Join-Path $script:PnHome '.keel') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:PnRepo 'scripts') -Force | Out-Null

    $PnPrev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $null = & git -c init.defaultBranch=main init -q --bare $script:PnRemote 2>$null
    $PnInitBare = $LASTEXITCODE
    $null = & git -c init.defaultBranch=main init -q $script:PnRepo 2>$null
    $PnInitRepo = $LASTEXITCODE
    $PnTop = @(& git -C $script:PnRepo rev-parse --show-toplevel 2>$null)
    $ErrorActionPreference = $PnPrev
    if ($PnInitBare -ne 0 -or $PnInitRepo -ne 0) { throw "fixture: git init failed (bare exit $PnInitBare, repo exit $PnInitRepo)" }

    # Refuse unless git sees the scratch repository as its own top level. Compared on the
    # unique tail of the path rather than the whole of it, because TEMP can be spelled in a
    # short 8.3 form that git reports in its long form.
    $PnTail = ((Split-Path -Leaf $PnTempRootFull) + '/repo')
    $PnTopText = ''
    if ($PnTop.Count -gt 0) { $PnTopText = ([string]$PnTop[0]).Replace('\', '/').TrimEnd('/') }
    if (-not $PnTopText.EndsWith($PnTail, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "fixture: git does not resolve the scratch repository as its own top level - refusing to run any case"
    }

    Invoke-PnGit @('config', 'user.email', 'suite@example.invalid')
    Invoke-PnGit @('config', 'user.name', 'private names suite')
    Invoke-PnGit @('config', 'core.autocrlf', 'false')
    Copy-Item -LiteralPath $PnValidator -Destination $script:PnCopy -Force

    Invoke-Cases

    if (-not $Quiet) { Write-Output ''; Write-Output "== private-names check: $([System.IO.Path]::GetFileName($PnValidator))" }

    $PnHarnessOk = $null
    foreach ($PnResult in @($script:PnResults)) {
        if (-not $PnResult.Ok) {
            $PnFailed++
            if (-not $Quiet) { Write-Output ("  FAIL  {0,-56} {1}" -f $PnResult.Name, $PnResult.Why) }
        }
        if ($PnResult.Name -eq 'HARNESS-CONTROL-validator-copy-runs') { $PnHarnessOk = $PnResult.Ok }
    }
    if ($PnHarnessOk -ne $true) {
        Write-Output ''
        Write-Output '  HARNESS CONTROL FAILED: the validator copy did not run the check on an empty list.'
        Write-Output '  The suite is not reaching the mechanism. No other row in this run means anything.'
    }
}
catch {
    # Our own throws start 'fixture:' and carry no path; anything else is reported by its
    # type only, since a PowerShell error message usually quotes a scratch path.
    $PnFailed++
    $PnWhy = $_.Exception.GetType().Name
    if ($_.Exception.Message.StartsWith('fixture:')) { $PnWhy = $_.Exception.Message }
    Write-Output ("  FAIL  the suite could not finish: {0}" -f $PnWhy)
}
finally {
    if (Test-Path -LiteralPath $PnTempRoot) {
        try { Remove-Item -LiteralPath $PnTempRoot -Recurse -Force -ErrorAction Stop } catch { }
    }
}

Write-Output ''
Write-Output ("test-private-names: {0} case(s), {1} failure(s)." -f @($script:PnResults).Count, $PnFailed)
if ($PnFailed -gt 0) { exit 1 }
exit 0
