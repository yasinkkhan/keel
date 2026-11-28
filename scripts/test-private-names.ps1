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
      - a records path is still read: an entry in plan/ refuses with keel.json in the index
        as it does with none, at both gates; the same file clean passes
      - a file whose own name holds an accented letter is read: an entry in it refuses and
        the same file clean passes

    It also covers section 25, the user-path check, which shares this scratch repository
    and its bare remote. Every USERPATH row, controls and harness included, also fails if
    its joined output holds any of the fixture names:

      - a user folder path naming the fixture user refuses, naming file and line, in a
        records file, a script, a progress file and a patch kept byte for byte, at both
        gates; the same file without it passes
      - the JSON-escaped, POSIX-drive and folder-name spellings each refuse, and so do a
        path straight after a JSON line-break escape and a POSIX path inside a longer one
      - the placeholder the documents use, its escaped elided form and %USERPROFILE% pass
      - a path holding one refuses at both gates, printed masked; a clean name passes; a
        name holding a space, or an accented letter, is masked whole
      - a user name beginning with an accented letter refuses, and a file whose own name
        holds an accented letter is read
      - at push, an unpushed commit message holding one refuses; amended away it passes

    HOW IT REACHES THE CHECK ALONE. Every other validator section fails in a scratch
    repository, so the suite copies the validator into <scratch>\repo\scripts\ (untracked,
    so neither scan reads it) and runs that copy with -PrivateNamesOnly, which runs section
    16 and the verdict only, or with -UserPathsOnly, which runs section 25 and the verdict
    only. -AgainstValidator <path> runs the same cases against another copy - the way to
    show the suite can fail: point it at a copy whose matcher never matches and the case
    rows must fail.

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
    param([string]$PnMode, [string]$PnOnly = '-PrivateNamesOnly')
    $PnPrevProfile = $env:USERPROFILE
    $env:USERPROFILE = $script:PnHome
    $PnPrev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $PnLines = @()
    $PnCode = 0
    try {
        $PnLines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:PnCopy $PnMode $PnOnly 2>&1 |
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
    $PnFull = Join-Path $script:PnRepo $PnName
    $PnDir = Split-Path -Parent $PnFull
    if (-not (Test-Path -LiteralPath $PnDir)) { New-Item -ItemType Directory -Path $PnDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($PnFull, $PnContent, (New-Object System.Text.UTF8Encoding($false)))
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

    Invoke-RecordsReadCases $PnMixed $PnTerm $PnMain
    Invoke-UserPathCases
}

# ---------------------------------------------------------------------------
# RECORDS: section 16 still reads the records paths while the index holds keel.json
# ---------------------------------------------------------------------------
function Invoke-RecordsReadCases {
    param([string]$PnHit, [string]$PnPlain, [string[]]$PnListLines)
    Set-PnList $PnListLines
    $PnKeel = "{`n}`n"
    $PnDirty = "line one`nhas $PnHit here`n"
    $PnClean = "line one`nclean here`n"

    Set-PnFile 'keel.json' $PnKeel
    Set-PnFile 'plan/x.md' $PnDirty
    Invoke-PnGit @('add', '--', 'keel.json', 'plan/x.md')
    $PnR = Invoke-PnCheck '-CommitGate'
    $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match 'plan/x\.md line 2 ') -and (-not (Test-PnHas $PnR.Text $PnPlain))
    Add-Result 'RECORDS-staged-plan-entry-refused-with-keel-json' $PnOk `
               "exit $($PnR.Code) - wanted non-zero naming plan/x.md line 2, keel.json staged, and the entry absent"

    Invoke-PnGit @('rm', '-q', '--cached', '--', 'keel.json')
    Remove-Item -LiteralPath (Join-Path $script:PnRepo 'keel.json') -Force
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'RECORDS-staged-plan-entry-refused-without-keel-json' (($PnR.Code -ne 0) -and ($PnR.Text -match 'plan/x\.md line 2 ')) `
               "exit $($PnR.Code) - wanted non-zero naming plan/x.md line 2, no keel.json"

    Set-PnFile 'keel.json' $PnKeel
    Set-PnFile 'plan/x.md' $PnClean
    Invoke-PnGit @('add', '--', 'keel.json', 'plan/x.md')
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'RECORDS-control-staged-plan-clean-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0 with keel.json and a clean plan/x.md staged"

    Invoke-PnGit @('commit', '-q', '-m', 'records')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')
    Set-PnFile 'plan/x.md' $PnDirty
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'RECORDS-strict-plan-entry-refused-with-keel-json' (($PnR.Code -ne 0) -and ($PnR.Text -match 'plan/x\.md line 2 ')) `
               "exit $($PnR.Code) - wanted non-zero naming plan/x.md line 2, keel.json tracked"
    Invoke-PnGit @('checkout', '-q', '--', 'plan/x.md')
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'RECORDS-control-strict-plan-reverted-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"

    Invoke-PnGit @('rm', '-q', '--', 'keel.json')
    Invoke-PnGit @('commit', '-q', '-m', 'no keel.json')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')
    Set-PnFile 'plan/x.md' $PnDirty
    $PnR = Invoke-PnCheck '-Strict'
    Add-Result 'RECORDS-strict-plan-entry-refused-without-keel-json' (($PnR.Code -ne 0) -and ($PnR.Text -match 'plan/x\.md line 2 ')) `
               "exit $($PnR.Code) - wanted non-zero naming plan/x.md line 2, no keel.json tracked"
    Invoke-PnGit @('checkout', '-q', '--', 'plan/x.md')

    # --- a file whose own name holds an accented letter is read, not skipped -----------
    # git quotes such a path by default, and a quoted name given back to git grep reads
    # nothing. Assembled so this file stays ASCII.
    $PnAccent = 'caf' + [string][char]0xE9 + '-notes.txt'
    Set-PnFile $PnAccent $PnDirty
    Invoke-PnGit @('add', '--', $PnAccent)
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'ACCENT-staged-entry-in-accented-name-refused' (($PnR.Code -ne 0) -and ($PnR.Text -match 'line 2 holds the entry on list line') -and
                                                              ($PnR.Text -match '1 staged path\(s\), 1 read as text')) `
               "exit $($PnR.Code) - wanted non-zero, the file read as text and its line 2 refused"
    Set-PnFile $PnAccent $PnClean
    Invoke-PnGit @('add', '--', $PnAccent)
    $PnR = Invoke-PnCheck '-CommitGate'
    Add-Result 'ACCENT-control-same-file-clean-passes' (($PnR.Code -eq 0) -and ($PnR.Text -match '1 staged path\(s\), 1 read as text')) `
               "exit $($PnR.Code) - wanted 0 with the file read as text"
    Invoke-PnGit @('rm', '-q', '--cached', '--', $PnAccent)
    Remove-Item -LiteralPath (Join-Path $script:PnRepo $PnAccent) -Force
}

# ---------------------------------------------------------------------------
# USERPATH: section 25, run alone with -UserPathsOnly
# ---------------------------------------------------------------------------
# The fixture names are assembled here, and so is every refused form, so that this file's
# own text holds none: the check reads every tracked file.
#
# EVERY USERPATH ROW, CONTROLS AND HARNESS INCLUDED, also requires that its joined output
# holds no fixture name nor either part of the spaced one: Add-UpRow adds that to the row's
# own condition, so a row cannot be written without it.
$script:UpNames = @()
function Add-UpRow {
    param([object]$UpResult, [string]$UpRow, [bool]$UpOk, [string]$UpWhy)
    $UpClean = $true
    foreach ($UpN in $script:UpNames) { if (Test-PnHas $UpResult.Text $UpN) { $UpClean = $false } }
    Add-Result $UpRow ($UpOk -and $UpClean) ($UpWhy + '; and no fixture name in the output')
}

function Invoke-UserPathCases {
    $UpName   = 'qz' + 'vperson'
    $UpFirst  = 'qz' + 'jane'
    $UpLast   = 'qz' + 'doe'
    $UpTail   = 'qz' + 'lise'
    $UpAccented = [string][char]0xC9 + $UpTail
    $script:UpNames = @($UpName, $UpFirst, $UpLast, $UpTail)
    $UpDrive  = 'C:\Users\' + $UpName + '\work'
    $UpJson   = 'C:\\Users\\' + $UpName + '\\work'
    $UpPosix  = '/c/Users/' + $UpName + '/work'
    $UpFolder = 'c--Users-' + $UpName + '-Projects'
    $UpOnly   = '-UserPathsOnly'

    # A base the remote holds: patches kept byte for byte, and keel.json, so the records
    # paths below are records paths.
    Set-PnFile '.gitattributes' "*.patch -text`n"
    Set-PnFile 'keel.json' "{`n}`n"
    Invoke-PnGit @('add', '--', '.gitattributes', 'keel.json')
    Invoke-PnGit @('commit', '-q', '-m', 'user path base')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')

    # --- harness: the mode runs and prints its ran line ---
    Set-PnFile 'up-harness.txt' "clean`n"
    Invoke-PnGit @('add', '--', 'up-harness.txt')
    $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
    Add-UpRow $PnR 'USERPATH-HARNESS-mode-runs' (($PnR.Code -eq 0) -and ($PnR.Text -match 'user paths: 1 staged path')) `
               "exit $($PnR.Code), wanted 0 and the user-path ran line for 1 staged path"
    Invoke-PnGit @('rm', '-q', '--cached', '--', 'up-harness.txt')
    Remove-Item -LiteralPath (Join-Path $script:PnRepo 'up-harness.txt') -Force

    # --- contents, at both gates, in records and product files and a patch ---
    foreach ($UpCase in @(@{ Row = 'plan';     Path = 'plan/x.md';       Nl = "`n";   Records = 1 },
                          @{ Row = 'script';   Path = 'scripts/x.ps1';   Nl = "`r`n"; Records = 0 },
                          @{ Row = 'progress'; Path = 'progress/x.json'; Nl = "`n";   Records = 1 },
                          @{ Row = 'patch';    Path = 'progress/phases/W1.1/artifacts/changes-keel.patch'; Nl = "`r`n"; Records = 1 })) {
        $UpAt = '(^|\s)' + [regex]::Escape($UpCase.Path) + ' line 2 '
        $UpDirty = "line one$($UpCase.Nl)+see $UpDrive here$($UpCase.Nl)"
        $UpClean = "line one$($UpCase.Nl)+see no folder here$($UpCase.Nl)"

        Set-PnFile $UpCase.Path $UpDirty
        Invoke-PnGit @('add', '--', $UpCase.Path)
        $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
        $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match $UpAt) -and (-not (Test-PnHas $PnR.Text $UpName)) -and
                ($PnR.Text -match ", $($UpCase.Records) records path\(s\) read, 1 line\(s\) or path\(s\) refused")
        Add-UpRow $PnR "USERPATH-staged-$($UpCase.Row)-refused" $PnOk `
                   "exit $($PnR.Code) - wanted non-zero naming $($UpCase.Path) line 2, $($UpCase.Records) records path(s) read, 1 refused, and the name absent"

        Set-PnFile $UpCase.Path $UpClean
        Invoke-PnGit @('add', '--', $UpCase.Path)
        $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
        Add-UpRow $PnR "USERPATH-control-staged-$($UpCase.Row)-clean-passes" ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"

        Invoke-PnGit @('commit', '-q', '-m', 'clean file')
        Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')
        Set-PnFile $UpCase.Path $UpDirty
        $PnR = Invoke-PnCheck '-Strict' $UpOnly
        $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match $UpAt) -and (-not (Test-PnHas $PnR.Text $UpName))
        Add-UpRow $PnR "USERPATH-strict-$($UpCase.Row)-refused" $PnOk `
                   "exit $($PnR.Code) - wanted non-zero naming $($UpCase.Path) line 2 and the name absent"
        Invoke-PnGit @('checkout', '-q', '--', $UpCase.Path)
        $PnR = Invoke-PnCheck '-Strict' $UpOnly
        Add-UpRow $PnR "USERPATH-control-strict-$($UpCase.Row)-reverted-passes" ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"
    }

    # --- the other spellings, each on its own ---
    # The last two are glued to what comes before them: a path that starts a line inside a
    # JSON string follows the line-break escape, and a POSIX path can sit inside a longer one.
    foreach ($UpForm in @(@{ Row = 'json-escaped';             Text = $UpJson },
                          @{ Row = 'posix-drive';              Text = $UpPosix },
                          @{ Row = 'folder-name';              Text = $UpFolder },
                          @{ Row = 'json-after-line-break';    Text = ('"line\nC:\\Users\\' + $UpName + '\\work"') },
                          @{ Row = 'posix-inside-longer-path'; Text = ('/mnt/c/Users/' + $UpName + '/work') },
                          @{ Row = 'name-with-accented-first-letter'; Text = ('C:\Users\' + $UpAccented + '\work') })) {
        Set-PnFile 'forms.txt' "see $($UpForm.Text) here`n"
        Invoke-PnGit @('add', '--', 'forms.txt')
        $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
        $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match 'forms\.txt line 1 ') -and (-not (Test-PnHas $PnR.Text $UpName))
        Add-UpRow $PnR "USERPATH-staged-$($UpForm.Row)-refused" $PnOk "exit $($PnR.Code) - wanted non-zero naming forms.txt line 1 and the name absent"
        Invoke-PnGit @('rm', '-q', '--cached', '--', 'forms.txt')
        Remove-Item -LiteralPath (Join-Path $script:PnRepo 'forms.txt') -Force
    }

    # --- the placeholders the documents use pass, at both gates ---
    $UpPlaceholders = 'usually C:\Users\<your user name>, escaped as C:\\Users\\..., or %USERPROFILE%'
    Set-PnFile 'placeholders.md' "# where things are`n$UpPlaceholders`n"
    Invoke-PnGit @('add', '--', 'placeholders.md')
    $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
    Add-UpRow $PnR 'USERPATH-control-staged-placeholders-pass' (($PnR.Code -eq 0) -and ($PnR.Text -match ', 0 line\(s\) or path\(s\) refused')) `
               "exit $($PnR.Code), wanted 0 and 0 refused"
    Invoke-PnGit @('commit', '-q', '-m', 'placeholders')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')
    $PnR = Invoke-PnCheck '-Strict' $UpOnly
    Add-UpRow $PnR 'USERPATH-control-strict-placeholders-pass' (($PnR.Code -eq 0) -and ($PnR.Text -match ', 0 line\(s\) or path\(s\) refused')) `
               "exit $($PnR.Code), wanted 0 and 0 refused"

    # --- a path holding one, at both gates, printed masked ---
    $UpBadPath = "keep/$UpFolder.md"
    Set-PnFile $UpBadPath "clean content`n"
    Invoke-PnGit @('add', '--', $UpBadPath)
    $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
    $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match 'a staged path holds a user folder path: keep/\*+\.?\*') -and (-not (Test-PnHas $PnR.Text $UpName))
    Add-UpRow $PnR 'USERPATH-staged-path-refused-masked' $PnOk "exit $($PnR.Code) - wanted non-zero, the staged path refusal masked, and the name absent"
    Invoke-PnGit @('rm', '-q', '--cached', '--', $UpBadPath)
    Remove-Item -LiteralPath (Join-Path $script:PnRepo $UpBadPath) -Force

    # A name holding a space is masked whole, both parts of it.
    $UpSpacedPath = 'keep/c--Users-' + $UpFirst + ' ' + $UpLast + '-Projects.md'
    Set-PnFile $UpSpacedPath "clean content`n"
    Invoke-PnGit @('add', '--', $UpSpacedPath)
    $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
    Add-UpRow $PnR 'USERPATH-staged-path-with-a-space-masked-whole' (($PnR.Code -ne 0) -and ($PnR.Text -match 'a staged path holds a user folder path: keep/\*+\. The path is shown masked')) `
              "exit $($PnR.Code) - wanted non-zero and the staged path refusal with the whole file name masked"
    Invoke-PnGit @('rm', '-q', '--cached', '--', $UpSpacedPath)
    Remove-Item -LiteralPath (Join-Path $script:PnRepo $UpSpacedPath) -Force

    # A name holding an accented letter is masked whole too: git would quote it by default,
    # and a mask over the quoted form stops at the first escape.
    $UpAccentPath = 'keep/c--Users-' + $UpFirst + [string][char]0xEB + ' ' + $UpLast + '-Projects.md'
    Set-PnFile $UpAccentPath "clean content`n"
    Invoke-PnGit @('add', '--', $UpAccentPath)
    $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
    Add-UpRow $PnR 'USERPATH-staged-path-with-an-accent-masked-whole' (($PnR.Code -ne 0) -and ($PnR.Text -match 'a staged path holds a user folder path: keep/\*+\. The path is shown masked')) `
              "exit $($PnR.Code) - wanted non-zero and the staged path refusal with the whole file name masked"
    Invoke-PnGit @('rm', '-q', '--cached', '--', $UpAccentPath)
    Remove-Item -LiteralPath (Join-Path $script:PnRepo $UpAccentPath) -Force

    # A file whose own name holds an accented letter is read.
    $UpAccentFile = 'keep/caf' + [string][char]0xE9 + '-notes.md'
    Set-PnFile $UpAccentFile "line one`nsee $UpDrive here`n"
    Invoke-PnGit @('add', '--', $UpAccentFile)
    $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
    Add-UpRow $PnR 'USERPATH-staged-content-of-accented-name-refused' (($PnR.Code -ne 0) -and ($PnR.Text -match '1 staged path\(s\), 1 read as text') -and
                                                                       ($PnR.Text -match ', 1 line\(s\) or path\(s\) refused')) `
              "exit $($PnR.Code) - wanted non-zero, the file read as text and 1 line refused"
    Invoke-PnGit @('rm', '-q', '--cached', '--', $UpAccentFile)
    Remove-Item -LiteralPath (Join-Path $script:PnRepo $UpAccentFile) -Force

    Set-PnFile 'keep/clean.md' "clean content`n"
    Invoke-PnGit @('add', '--', 'keep/clean.md')
    $PnR = Invoke-PnCheck '-CommitGate' $UpOnly
    Add-UpRow $PnR 'USERPATH-control-staged-clean-name-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"
    Invoke-PnGit @('rm', '-q', '--cached', '--', 'keep/clean.md')
    Remove-Item -LiteralPath (Join-Path $script:PnRepo 'keep/clean.md') -Force

    Set-PnFile $UpBadPath "clean content`n"
    Invoke-PnGit @('add', '--', $UpBadPath)
    Invoke-PnGit @('commit', '-q', '-m', 'add a file')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')
    $PnR = Invoke-PnCheck '-Strict' $UpOnly
    $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match 'a tracked path holds a user folder path: keep/\*+') -and (-not (Test-PnHas $PnR.Text $UpName))
    Add-UpRow $PnR 'USERPATH-strict-path-refused-masked' $PnOk "exit $($PnR.Code) - wanted non-zero, the tracked path refusal masked, and the name absent"
    Invoke-PnGit @('mv', '--', $UpBadPath, 'keep/renamed.md')
    Invoke-PnGit @('commit', '-q', '-m', 'rename a file')
    Invoke-PnGit @('push', '-q', 'origin', 'HEAD:refs/heads/main')
    $PnR = Invoke-PnCheck '-Strict' $UpOnly
    Add-UpRow $PnR 'USERPATH-control-strict-path-renamed-passes' ($PnR.Code -eq 0) "exit $($PnR.Code), wanted 0"

    # --- an unpushed commit message, at push ---
    Invoke-PnGit @('commit', '-q', '--allow-empty', '-m', "copied from $UpDrive")
    $PnR = Invoke-PnCheck '-Strict' $UpOnly
    $PnOk = ($PnR.Code -ne 0) -and ($PnR.Text -match 'unpushed commit [0-9a-f]{7} holds a user folder path') -and (-not (Test-PnHas $PnR.Text $UpName))
    Add-UpRow $PnR 'USERPATH-strict-unpushed-message-refused' $PnOk "exit $($PnR.Code) - wanted non-zero naming the unpushed commit and the name absent"
    Invoke-PnGit @('commit', '-q', '--amend', '--allow-empty', '-m', 'copied from the user folder')
    $PnR = Invoke-PnCheck '-Strict' $UpOnly
    Add-UpRow $PnR 'USERPATH-control-strict-message-amended-passes' (($PnR.Code -eq 0) -and ($PnR.Text -match 'and 1 unpushed commit message')) `
               "exit $($PnR.Code), wanted 0 with 1 unpushed commit message read"
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
