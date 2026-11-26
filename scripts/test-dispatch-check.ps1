<#
    test-dispatch-check.ps1 - the suite for 'dispatch-open' and 'dispatch-close'.

    WHY THIS EXISTS. A helper subagent (an advisor, a plan reviewer, a verifier) is told by its
    brief that it reads and does not write, and a brief is text: nothing stops a helper that
    writes anyway. The two verbs bracket a helper's run - open stores a reading of the project
    folder, every repo keel.json registers and the phase folder; close re-takes it and names each
    path written while the helper was out, as WARNING lines and one 'dispatch-write' friction
    entry. This suite runs them against scratch fixtures.

    WHAT IT COVERS. Each case beside a control on the same fixture that must behave differently:
      a  a new untracked file is named 'new' and recorded as one friction entry naming the
         dispatch / nothing written: no line, no entry
      b  a second edit to a file already modified at open is named 'changed', which 'git status'
         cannot see / no second edit: not named
      c  a write in a registered repo the phase does not declare is named under that repo /
         a write in a folder no tree covers: not named
      d  a file committed inside the window is still named / one committed before it: not named
      e  in a project that shares its progress: a project write and a phase-folder write are
         named / a stray file under progress/ is not
      f  status names a dispatch never closed / not once it is closed
      g  the refusals - close with none open (90), open of a name already open (90), an unknown
         phase (94), no -Name (90) - each with its message / a success on the same store
      h  a project with no git tree says so at open / a git project does not
      i  a git-ignored file is not named, the stated limit / the same write to a file git does
         not ignore is
      j  a tracked file clean at open and deleted is named 'removed' / an untouched one is not
      k  an edit to the phase folder's plan.md is named / a new verify-report.md is not
      l  a clean tracked file edited, and a modified one restored to its base, are 'changed' /
         a file the base lacks is 'new'
      m  an untracked file present at open and deleted is 'removed' / one left alone is not named
      n  a tracked file deleted at open and back is 'new', restored or recreated; a modified one
         deleted is 'removed'; an untracked one edited is 'changed' / one deleted at open and left
         deleted is not named
      o  a file renamed with git mv names its old name 'removed' and its new name 'new' / a
         rename made before open is not named
      p  a rename that changes only letter case is named once, 'changed', under its old spelling,
         the stated limit / an ordinary rename in the same window names both names
      q  the same rename of a file already edited at open is not named at all, the stated limit /
         a marker in the same window is named
      r  a write in a subfolder of the phase folder is not named, the stated limit / a write at
         its top level is
      s  over 2000 paths differing at open, a write is one 'not itemised' line, the stated limit /
         a window with no write prints nothing
    EVERY ROW THAT SAYS A PATH IS NOT NAMED ALSO REQUIRES the close to have exited 0 and to have
    named the other write its fixture made, so no row can pass on a wrapper that refuses the verbs.
    Every refusal row asserts its message as well as its code.

    ISOLATION. The wrapper derives its whole state home from $env:USERPROFILE, so every call runs
    with USERPROFILE at a scratch home under the system temp directory, and the suite refuses to
    run if that does not resolve inside it. HOME and GIT_CONFIG_GLOBAL point at scratch,
    GIT_CONFIG_NOSYSTEM is set, and every GIT_ variable a git hook exports is cleared first, so a
    run from the pre-push reads no real git identity or repository. COMPUTERNAME is fixed for the
    project that shares its progress, and KEEL_OUTWARD is 'block'.

    Run it:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-dispatch-check.ps1
      ... -List                    every row, passing rows included
      ... -AgainstWrapper <path>   every call against another keel-state.ps1, in the repo's
                                   layout (as 'git archive' unpacks it); a wrapper without the
                                   two verbs must fail every case row. Human-invoked, not on the
                                   push path.

    Exit 0 = every row behaved. Exit 1 = at least one did not.

    Windows PowerShell 5.1 compatible. ASCII only.
#>

[CmdletBinding()]
param(
    [switch]$List,
    [string]$AgainstWrapper = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Every local in this file is Dc-prefixed: PowerShell variable names are case-insensitive, and a
# local whose name matches a param() name IS that parameter.
$DcRepoRoot = Split-Path -Parent $PSScriptRoot
$DcWrapper  = Join-Path $DcRepoRoot 'plugins\keel-workflow\skills\keel-orchestrator\wrappers\keel-state.ps1'
if (-not [string]::IsNullOrWhiteSpace($AgainstWrapper)) {
    if (-not (Test-Path -LiteralPath $AgainstWrapper -PathType Leaf)) {
        [Console]::Error.WriteLine("test-dispatch-check: -AgainstWrapper '$AgainstWrapper' is not a file.")
        exit 1
    }
    $DcWrapper = (Resolve-Path -LiteralPath $AgainstWrapper).Path
}
$DcMachine = 'KDC-SUITE'

$script:DcRows = @()

# A function returns everything it emits, so the rows go to a script-scope list and this
# returns nothing.
function Add-DcRow {
    param([string]$DcName, [bool]$DcOk, [string]$DcWhy)
    $script:DcRows += [pscustomobject]@{ Name = $DcName; Ok = $DcOk; Why = $DcWhy }
}

# One wrapper call in its own powershell.exe. Stderr arrives as ErrorRecords under 2>&1, and
# ToString() on one wrapping a blank line yields a literal RemoteException name, so each is
# read through its Exception.Message. The exit code decides, never the stream.
function Invoke-DcK {
    param([string]$DcHome, [string[]]$DcArgs)
    $dcPrevProfile = $env:USERPROFILE
    $dcPrevMachine = $env:COMPUTERNAME
    $dcPrevPref = $ErrorActionPreference
    $env:USERPROFILE = $DcHome
    $env:COMPUTERNAME = $DcMachine
    $ErrorActionPreference = 'Continue'
    $dcLines = @()
    $dcCode = 0
    try {
        $dcLines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DcWrapper @DcArgs 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
        })
        $dcCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $dcPrevPref
        $env:USERPROFILE = $dcPrevProfile
        $env:COMPUTERNAME = $dcPrevMachine
    }
    return [pscustomobject]@{ Code = $dcCode; Text = (@($dcLines) -join "`n") }
}

function Assert-DcK {
    param([string]$DcHome, [string[]]$DcArgs)
    $dcR = Invoke-DcK $DcHome $DcArgs
    if ($dcR.Code -ne 0) { throw "fixture step '$($DcArgs -join ' ')' failed (exit $($dcR.Code)): $($dcR.Text)" }
}

function Invoke-DcGit {
    param([string]$DcDir, [string[]]$DcArgs)
    $dcPrevPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $dcOut = @(& git -C $DcDir @DcArgs 2>&1 | ForEach-Object { $_.ToString() })
        $dcCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $dcPrevPref }
    if ($dcCode -ne 0) { throw "git $($DcArgs -join ' ') failed in '$DcDir' (exit $dcCode): $($dcOut -join ' ')" }
}

function New-DcRepo {
    param([string]$DcDir)
    New-Item -ItemType Directory -Path $DcDir -Force | Out-Null
    Invoke-DcGit $DcDir @('init', '-q', '-b', 'main')
    Invoke-DcGit $DcDir @('config', 'user.name', 'Dispatch Suite')
    Invoke-DcGit $DcDir @('config', 'user.email', 'suite@example.invalid')
    Invoke-DcGit $DcDir @('config', 'core.autocrlf', 'false')
}

function Save-DcCommit {
    param([string]$DcDir, [string]$DcMsg, [string[]]$DcPaths)
    if ($null -eq $DcPaths -or @($DcPaths).Count -eq 0) { Invoke-DcGit $DcDir @('add', '-A') }
    else { Invoke-DcGit $DcDir (@('add', '--') + @($DcPaths)) }
    Invoke-DcGit $DcDir @('commit', '-q', '-m', $DcMsg)
}

function Set-DcFile {
    param([string]$DcFile, [string]$DcText)
    $dcParent = Split-Path -Parent $DcFile
    if (-not (Test-Path -LiteralPath $dcParent)) { New-Item -ItemType Directory -Path $dcParent -Force | Out-Null }
    [System.IO.File]::WriteAllText($DcFile, $DcText, (New-Object System.Text.UTF8Encoding($false)))
}

# The dispatch-write entries on a per-machine fixture's phase, read from its state.json. phases is
# an ARRAY: it is indexed, never walked as an object's properties.
function Get-DcWrites {
    param([string]$DcHome, [string]$DcSlug, [string]$DcPhase)
    $dcSp = Join-Path $DcHome ".keel\projects\$DcSlug\state.json"
    $dcState = Get-Content -LiteralPath $dcSp -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $dcState) { throw "state file '$dcSp' parsed to nothing" }
    $dcPh = @($dcState.phases | Where-Object { $_.id -eq $DcPhase })
    if ($dcPh.Count -ne 1) { throw "phase $DcPhase not found once in '$dcSp'" }
    $dcFr = $dcPh[0].PSObject.Properties['friction']
    if ($null -eq $dcFr) { return @() }
    return @(@($dcFr.Value) | Where-Object { $_.kind -eq 'dispatch-write' })
}

function Test-DcHas { param([string]$DcText, [string]$DcPart) return $DcText.Contains($DcPart) }

# One dispatch: open, the writes, close. Returns both results.
function Invoke-DcWindow {
    param([string]$DcHome, [string]$DcProj, [string]$DcName, [scriptblock]$DcWrites)
    $dcO = Invoke-DcK $DcHome @('dispatch-open', '-Phase', 'W1.1', '-Name', $DcName, '-Path', $DcProj)
    if ($null -ne $DcWrites) { & $DcWrites }
    $dcC = Invoke-DcK $DcHome @('dispatch-close', '-Phase', 'W1.1', '-Name', $DcName, '-Path', $DcProj)
    return [pscustomobject]@{ Open = $dcO; Close = $dcC; Ran = ($dcO.Code -eq 0 -and $dcC.Code -eq 0) }
}

function Get-DcBrief {
    param($DcW)
    return "open exit $($DcW.Open.Code), close exit $($DcW.Close.Code); close printed: [$($DcW.Close.Text)]"
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
function New-DcProject {
    param([string]$DcHome, [string]$DcDir, [string]$DcTitle, [bool]$DcGit, [bool]$DcShare)
    if ($DcGit) { New-DcRepo $DcDir } else { New-Item -ItemType Directory -Path $DcDir -Force | Out-Null }
    $dcInit = @('init-project', '-Path', $DcDir, '-Title', $DcTitle)
    if (-not $DcGit) { $dcInit += '-NoGit' }
    Assert-DcK $DcHome $dcInit
    Assert-DcK $DcHome @('add-goal', '-Path', $DcDir, '-Id', 'G1', '-Text', 'fixture goal')
    Assert-DcK $DcHome @('add-workstream', '-Path', $DcDir, '-Id', 'W1', '-Title', 'fixture workstream', '-Parent', 'root', '-Goals', 'G1', '-Express')
    if ($DcShare) {
        Save-DcCommit $DcDir 'project' @()
        Assert-DcK $DcHome @('share-progress', '-Path', $DcDir)
    }
    Assert-DcK $DcHome @('add-phase', '-Path', $DcDir, '-Phase', 'W1.1', '-Scope', 'fixture phase', '-Actor', 'agent', '-RunOrder', '1')
}

# ---------------------------------------------------------------------------
# The cases
# ---------------------------------------------------------------------------
function Invoke-DcCases {
    param([string]$DcRoot)

    $dcHome = Join-Path $DcRoot 'home'
    New-Item -ItemType Directory -Path $dcHome -Force | Out-Null

    # Fixture P: a git project with three tracked files and an ignore rule, and a second git repo
    # it registers but its phase does not declare.
    $dcP = Join-Path $DcRoot 'p\projp'
    $dcOther = Join-Path $DcRoot 'p\other'
    $dcLoose = Join-Path $DcRoot 'p\loose'
    New-DcRepo $dcP
    Set-DcFile (Join-Path $dcP 'tracked.md') "tracked`n"
    Set-DcFile (Join-Path $dcP 'clean.md') "clean`n"
    Set-DcFile (Join-Path $dcP 'keep.md') "keep`n"
    Set-DcFile (Join-Path $dcP '.gitignore') "ignored.txt`n"
    Save-DcCommit $dcP 'base' @()
    New-DcRepo $dcOther
    Set-DcFile (Join-Path $dcOther 'o.md') "other`n"
    Save-DcCommit $dcOther 'base' @()
    New-DcProject $dcHome $dcP 'dispatch fixture P' $true $false
    Assert-DcK $dcHome @('add-repo', '-Path', $dcP, '-Name', 'other', '-RepoPath', $dcOther)
    $dcPhaseDir = Join-Path $dcHome '.keel\projects\projp\phases\W1.1'

    # --- HARNESS: the fixture's state is in the scratch home, and status reads it.
    $dcHs = Invoke-DcK $dcHome @('status', '-Path', $dcP)
    $dcStateFile = Join-Path $dcHome '.keel\projects\projp\state.json'
    Add-DcRow 'HARNESS-state-in-scratch-home' (($dcHs.Code -eq 0) -and (Test-Path -LiteralPath $dcStateFile)) `
        "status exit $($dcHs.Code); state file present: $(Test-Path -LiteralPath $dcStateFile)"

    # --- h: a project with no git tree says so at open; a git project does not.
    $dcH0 = Invoke-DcWindow $dcHome $dcP 'h0' $null
    Add-DcRow 'h-control-git-project-no-line' ($dcH0.Ran -and -not (Test-DcHas $dcH0.Open.Text 'no git tree')) (Get-DcBrief $dcH0)

    # --- a: a new file is named and recorded once; nothing written, nothing named or recorded.
    $dcA0Before = @(Get-DcWrites $dcHome 'projp' 'W1.1').Count
    $dcA0 = Invoke-DcWindow $dcHome $dcP 'a0' $null
    $dcA0After = @(Get-DcWrites $dcHome 'projp' 'W1.1').Count
    Add-DcRow 'a-control-nothing-written-silent' ($dcA0.Ran -and ($dcA0.Close.Text.Trim() -eq '') -and ($dcA0After -eq $dcA0Before)) `
        "$(Get-DcBrief $dcA0); dispatch-write entries $dcA0Before -> $dcA0After"
    $dcA1 = Invoke-DcWindow $dcHome $dcP 'a1' { Set-DcFile (Join-Path $dcP 'sim\doc.md') "simulation`n" }
    $dcA1W = @(Get-DcWrites $dcHome 'projp' 'W1.1')
    Add-DcRow 'a-case-new-file-named' ($dcA1.Ran -and (Test-DcHas $dcA1.Close.Text '(project): sim/doc.md (new)') -and (Test-DcHas $dcA1.Close.Text "dispatch 'a1'")) (Get-DcBrief $dcA1)
    $dcA1Last = ''
    if ($dcA1W.Count -gt 0) { $dcA1Last = [string]$dcA1W[$dcA1W.Count - 1].detail }
    Add-DcRow 'a-case-one-friction-entry' ($dcA1.Ran -and ($dcA1W.Count -eq $dcA0After + 1) -and (Test-DcHas $dcA1Last "dispatch 'a1'") -and (Test-DcHas $dcA1Last 'sim/doc.md')) `
        "dispatch-write entries $dcA0After -> $($dcA1W.Count); last detail: [$dcA1Last]"

    # --- b: a second edit to a file already modified at open.
    Set-DcFile (Join-Path $dcP 'tracked.md') "tracked, edit one`n"
    $dcB0 = Invoke-DcWindow $dcHome $dcP 'b0' { Set-DcFile (Join-Path $dcP 'b0-marker.md') "marker`n" }
    Add-DcRow 'b-control-no-second-edit-not-named' ($dcB0.Ran -and (Test-DcHas $dcB0.Close.Text '(project): b0-marker.md (new)') -and -not (Test-DcHas $dcB0.Close.Text 'tracked.md')) (Get-DcBrief $dcB0)
    $dcB1 = Invoke-DcWindow $dcHome $dcP 'b1' { Set-DcFile (Join-Path $dcP 'tracked.md') "tracked, edit two`n" }
    Add-DcRow 'b-case-second-edit-named-changed' ($dcB1.Ran -and (Test-DcHas $dcB1.Close.Text '(project): tracked.md (changed)')) (Get-DcBrief $dcB1)

    # --- c: a registered repo the phase does not declare is read; a folder no tree covers is not.
    $dcC0 = Invoke-DcWindow $dcHome $dcP 'c0' {
        Set-DcFile (Join-Path $dcLoose 'x.txt') "loose`n"
        Set-DcFile (Join-Path $dcP 'c0-marker.md') "marker`n"
    }
    Add-DcRow 'c-control-unregistered-folder-not-named' ($dcC0.Ran -and (Test-DcHas $dcC0.Close.Text '(project): c0-marker.md (new)') -and -not (Test-DcHas $dcC0.Close.Text 'x.txt')) (Get-DcBrief $dcC0)
    $dcC1 = Invoke-DcWindow $dcHome $dcP 'c1' { Set-DcFile (Join-Path $dcOther 'new.txt') "written in other`n" }
    Add-DcRow 'c-case-registered-repo-named' ($dcC1.Ran -and (Test-DcHas $dcC1.Close.Text 'other: new.txt (new)')) (Get-DcBrief $dcC1)

    # --- d: a commit inside the window still shows its file; one before the window does not.
    Set-DcFile (Join-Path $dcP 'd0-committed.md') "committed before`n"
    Save-DcCommit $dcP 'before the window' @()
    $dcD0 = Invoke-DcWindow $dcHome $dcP 'd0' { Set-DcFile (Join-Path $dcP 'd0-marker.md') "marker`n" }
    Add-DcRow 'd-control-committed-before-not-named' ($dcD0.Ran -and (Test-DcHas $dcD0.Close.Text '(project): d0-marker.md (new)') -and -not (Test-DcHas $dcD0.Close.Text 'd0-committed.md')) (Get-DcBrief $dcD0)
    $dcD1 = Invoke-DcWindow $dcHome $dcP 'd1' {
        Set-DcFile (Join-Path $dcP 'd1-committed.md') "committed inside`n"
        Save-DcCommit $dcP 'inside the window' @('d1-committed.md')
    }
    Add-DcRow 'd-case-committed-inside-named' ($dcD1.Ran -and (Test-DcHas $dcD1.Close.Text '(project): d1-committed.md (new)')) (Get-DcBrief $dcD1)

    # --- i: a git-ignored file is not named, the stated limit; the same write unignored is.
    $dcI1 = Invoke-DcWindow $dcHome $dcP 'i1' {
        Set-DcFile (Join-Path $dcP 'ignored.txt') "same text`n"
        Set-DcFile (Join-Path $dcP 'i1-unignored.txt') "same text`n"
    }
    Add-DcRow 'i-case-ignored-not-named-stated-limit' ($dcI1.Ran -and (Test-DcHas $dcI1.Close.Text '(project): i1-unignored.txt (new)') -and -not (Test-DcHas $dcI1.Close.Text '(project): ignored.txt')) (Get-DcBrief $dcI1)
    Add-DcRow 'i-control-unignored-named' ($dcI1.Ran -and (Test-DcHas $dcI1.Close.Text '(project): i1-unignored.txt (new)')) (Get-DcBrief $dcI1)

    # --- j: a tracked file clean at open and deleted is 'removed'; an untouched one is not named.
    $dcJ1 = Invoke-DcWindow $dcHome $dcP 'j1' { Remove-Item -LiteralPath (Join-Path $dcP 'clean.md') -Force }
    Add-DcRow 'j-case-deleted-named-removed' ($dcJ1.Ran -and (Test-DcHas $dcJ1.Close.Text '(project): clean.md (removed)')) (Get-DcBrief $dcJ1)
    Add-DcRow 'j-control-untouched-not-named' ($dcJ1.Ran -and (Test-DcHas $dcJ1.Close.Text 'clean.md (removed)') -and -not (Test-DcHas $dcJ1.Close.Text 'keep.md')) (Get-DcBrief $dcJ1)
    # A path already deleted at open, and left alone, is the same entry at both ends.
    $dcJ2 = Invoke-DcWindow $dcHome $dcP 'j2' { Set-DcFile (Join-Path $dcP 'j2-marker.md') "marker`n" }
    Add-DcRow 'j-control-deleted-before-open-not-named' ($dcJ2.Ran -and (Test-DcHas $dcJ2.Close.Text '(project): j2-marker.md (new)') -and -not (Test-DcHas $dcJ2.Close.Text 'clean.md')) (Get-DcBrief $dcJ2)

    # --- l: the label for a path missing from one reading. The readings hold only paths that
    # differ from the base, so a clean tracked file is absent at open and one restored to the
    # base is absent at close; both are 'changed', and only a file the base lacks is 'new'.
    # tracked.md was committed with everything else before d0's window, so its base is that text.
    Set-DcFile (Join-Path $dcP 'tracked.md') "tracked, edit three`n"
    $dcL1 = Invoke-DcWindow $dcHome $dcP 'l1' {
        Set-DcFile (Join-Path $dcP 'keep.md') "keep, edited by a helper`n"
        Set-DcFile (Join-Path $dcP 'tracked.md') "tracked, edit two`n"
        Set-DcFile (Join-Path $dcP 'l1-new.md') "new`n"
    }
    Add-DcRow 'l-case-clean-tracked-edit-changed' ($dcL1.Ran -and (Test-DcHas $dcL1.Close.Text '(project): keep.md (changed)') -and -not (Test-DcHas $dcL1.Close.Text 'keep.md (new)')) (Get-DcBrief $dcL1)
    Add-DcRow 'l-case-restored-to-base-changed' ($dcL1.Ran -and (Test-DcHas $dcL1.Close.Text '(project): tracked.md (changed)') -and -not (Test-DcHas $dcL1.Close.Text 'tracked.md (removed)')) (Get-DcBrief $dcL1)
    Add-DcRow 'l-control-file-base-lacks-new' ($dcL1.Ran -and (Test-DcHas $dcL1.Close.Text '(project): l1-new.md (new)')) (Get-DcBrief $dcL1)

    # --- m: an untracked file present at open and deleted is 'removed'; one left alone is not named.
    Set-DcFile (Join-Path $dcP 'm-goes.md') "goes`n"
    Set-DcFile (Join-Path $dcP 'm-stays.md') "stays`n"
    $dcM1 = Invoke-DcWindow $dcHome $dcP 'm1' { Remove-Item -LiteralPath (Join-Path $dcP 'm-goes.md') -Force }
    Add-DcRow 'm-case-untracked-deleted-removed' ($dcM1.Ran -and (Test-DcHas $dcM1.Close.Text '(project): m-goes.md (removed)')) (Get-DcBrief $dcM1)
    Add-DcRow 'm-control-untracked-left-not-named' ($dcM1.Ran -and (Test-DcHas $dcM1.Close.Text '(project): m-goes.md (removed)') -and -not (Test-DcHas $dcM1.Close.Text 'm-stays.md')) (Get-DcBrief $dcM1)

    # --- n: the rest of the label table, each start state not covered above. The label is whether
    # the file existed at open and whether it exists at close: a tracked file deleted at open and
    # back is 'new', whether restored or recreated; a modified one deleted is 'removed'; an
    # untracked one edited is 'changed'. Control: a tracked file deleted at open and left deleted.
    foreach ($dcNf in @('n-restore.md', 'n-recreate.md', 'n-moddel.md', 'n-left.md')) { Set-DcFile (Join-Path $dcP $dcNf) "$dcNf at base`n" }
    Save-DcCommit $dcP 'n base' @('n-restore.md', 'n-recreate.md', 'n-moddel.md', 'n-left.md')
    foreach ($dcNf in @('n-restore.md', 'n-recreate.md', 'n-left.md')) { Remove-Item -LiteralPath (Join-Path $dcP $dcNf) -Force }
    Set-DcFile (Join-Path $dcP 'n-moddel.md') "modified before open`n"
    Set-DcFile (Join-Path $dcP 'n-untracked.md') "untracked at open`n"
    $dcN1 = Invoke-DcWindow $dcHome $dcP 'n1' {
        Set-DcFile (Join-Path $dcP 'n-restore.md') "n-restore.md at base`n"
        Set-DcFile (Join-Path $dcP 'n-recreate.md') "recreated with other text`n"
        Remove-Item -LiteralPath (Join-Path $dcP 'n-moddel.md') -Force
        Set-DcFile (Join-Path $dcP 'n-untracked.md') "untracked, edited by a helper`n"
    }
    Add-DcRow 'n-case-deleted-at-open-restored-new' ($dcN1.Ran -and (Test-DcHas $dcN1.Close.Text '(project): n-restore.md (new)')) (Get-DcBrief $dcN1)
    Add-DcRow 'n-case-deleted-at-open-recreated-new' ($dcN1.Ran -and (Test-DcHas $dcN1.Close.Text '(project): n-recreate.md (new)')) (Get-DcBrief $dcN1)
    Add-DcRow 'n-case-modified-deleted-removed' ($dcN1.Ran -and (Test-DcHas $dcN1.Close.Text '(project): n-moddel.md (removed)')) (Get-DcBrief $dcN1)
    Add-DcRow 'n-case-untracked-edited-changed' ($dcN1.Ran -and (Test-DcHas $dcN1.Close.Text '(project): n-untracked.md (changed)')) (Get-DcBrief $dcN1)
    Add-DcRow 'n-control-deleted-at-open-left-not-named' ($dcN1.Ran -and (Test-DcHas $dcN1.Close.Text '(project): n-restore.md (new)') -and -not (Test-DcHas $dcN1.Close.Text 'n-left.md')) (Get-DcBrief $dcN1)

    # --- o: a rename through git inside the window names both names, because git diff would
    # otherwise report it as the new name alone. Control: a rename made before open, not named.
    foreach ($dcOf in @('o-old.md', 'o-pre-old.md')) { Set-DcFile (Join-Path $dcP $dcOf) "$dcOf at base`n" }
    Save-DcCommit $dcP 'o base' @('o-old.md', 'o-pre-old.md')
    Invoke-DcGit $dcP @('mv', 'o-pre-old.md', 'o-pre-new.md')
    $dcO1 = Invoke-DcWindow $dcHome $dcP 'o1' { Invoke-DcGit $dcP @('mv', 'o-old.md', 'o-new.md') }
    Add-DcRow 'o-case-git-mv-names-both' ($dcO1.Ran -and (Test-DcHas $dcO1.Close.Text '(project): o-old.md (removed)') -and (Test-DcHas $dcO1.Close.Text '(project): o-new.md (new)')) (Get-DcBrief $dcO1)
    Add-DcRow 'o-control-rename-before-open-not-named' ($dcO1.Ran -and (Test-DcHas $dcO1.Close.Text '(project): o-new.md (new)') -and -not (Test-DcHas $dcO1.Close.Text 'o-pre-')) (Get-DcBrief $dcO1)

    # --- p: the stated limit for a rename that changes only letter case. Windows treats the two
    # spellings as one file, so it is named once, 'changed', under its old spelling, and the new
    # spelling is not named. Control: an ordinary rename in the same window names both names.
    # Test-DcHas is String.Contains, which compares case-sensitively.
    foreach ($dcPf in @('p-case.md', 'p-plain.md')) { Set-DcFile (Join-Path $dcP $dcPf) "$dcPf at base`n" }
    Save-DcCommit $dcP 'p base' @('p-case.md', 'p-plain.md')
    $dcP1 = Invoke-DcWindow $dcHome $dcP 'p1' {
        Invoke-DcGit $dcP @('mv', 'p-case.md', 'P-Case.md')
        Invoke-DcGit $dcP @('mv', 'p-plain.md', 'p-plain-renamed.md')
    }
    Add-DcRow 'p-case-case-only-rename-named-once-stated-limit' ($dcP1.Ran -and (Test-DcHas $dcP1.Close.Text '(project): p-case.md (changed)') -and -not (Test-DcHas $dcP1.Close.Text 'P-Case.md')) (Get-DcBrief $dcP1)
    Add-DcRow 'p-control-ordinary-rename-both-names' ($dcP1.Ran -and (Test-DcHas $dcP1.Close.Text '(project): p-plain.md (removed)') -and (Test-DcHas $dcP1.Close.Text '(project): p-plain-renamed.md (new)')) (Get-DcBrief $dcP1)

    # --- q: the stated limit for the same rename of a file already edited at open: the open reading
    # holds the old spelling with that content, both spellings fold onto it, and it is not named at
    # all. Control: a marker written in the same window is named, so the close ran and compared.
    Set-DcFile (Join-Path $dcP 'q-case.md') "q-case.md at base`n"
    Save-DcCommit $dcP 'q base' @('q-case.md')
    Set-DcFile (Join-Path $dcP 'q-case.md') "q-case.md, edited before open`n"
    $dcQ1 = Invoke-DcWindow $dcHome $dcP 'q1' {
        Invoke-DcGit $dcP @('mv', 'q-case.md', 'Q-Case.md')
        Set-DcFile (Join-Path $dcP 'q1-marker.md') "marker`n"
    }
    Add-DcRow 'q-case-case-only-rename-of-edited-file-not-named-stated-limit' ($dcQ1.Ran -and (Test-DcHas $dcQ1.Close.Text '(project): q1-marker.md (new)') -and -not (Test-DcHas $dcQ1.Close.Text 'q-case.md') -and -not (Test-DcHas $dcQ1.Close.Text 'Q-Case.md')) (Get-DcBrief $dcQ1)
    Add-DcRow 'q-control-marker-named' ($dcQ1.Ran -and (Test-DcHas $dcQ1.Close.Text '(project): q1-marker.md (new)')) (Get-DcBrief $dcQ1)

    # --- r: the stated limit for the phase folder: only its top level is compared, so a write in a
    # subfolder of it is not named. Control: a top-level write in the same window is.
    $dcR1 = Invoke-DcWindow $dcHome $dcP 'r1' {
        Set-DcFile (Join-Path $dcPhaseDir 'evidence\helper-note.md') "written in a subfolder`n"
        Set-DcFile (Join-Path $dcPhaseDir 'r1-top.md') "written at the top`n"
    }
    Add-DcRow 'r-case-phase-subfolder-not-named-stated-limit' ($dcR1.Ran -and (Test-DcHas $dcR1.Close.Text 'phase folder: r1-top.md (new)') -and -not (Test-DcHas $dcR1.Close.Text 'helper-note.md')) (Get-DcBrief $dcR1)
    Add-DcRow 'r-control-phase-top-level-named' ($dcR1.Ran -and (Test-DcHas $dcR1.Close.Text 'phase folder: r1-top.md (new)')) (Get-DcBrief $dcR1)

    # --- k: the phase folder's plan.md edited is named; a verifier's report is not.
    Set-DcFile (Join-Path $dcPhaseDir 'plan.md') "# plan`n"
    $dcK1 = Invoke-DcWindow $dcHome $dcP 'k1' {
        Set-DcFile (Join-Path $dcPhaseDir 'plan.md') "# plan, edited by a helper`n"
        Set-DcFile (Join-Path $dcPhaseDir 'verify-report.md') "# report`n"
        Set-DcFile (Join-Path $dcPhaseDir 'verify-report-round1.md') "# report`n"
    }
    Add-DcRow 'k-case-plan-edit-named' ($dcK1.Ran -and (Test-DcHas $dcK1.Close.Text 'phase folder: plan.md (changed)')) (Get-DcBrief $dcK1)
    Add-DcRow 'k-control-verify-report-not-named' ($dcK1.Ran -and (Test-DcHas $dcK1.Close.Text 'phase folder: plan.md (changed)') -and -not (Test-DcHas $dcK1.Close.Text 'verify-report')) (Get-DcBrief $dcK1)

    # --- f: status names a dispatch never closed, and not once it is closed.
    $dcF1o = Invoke-DcK $dcHome @('dispatch-open', '-Phase', 'W1.1', '-Name', 'f1', '-Path', $dcP)
    $dcF1s = Invoke-DcK $dcHome @('status', '-Path', $dcP)
    Add-DcRow 'f-case-status-names-unclosed' (($dcF1o.Code -eq 0) -and ($dcF1s.Code -eq 0) -and (Test-DcHas $dcF1s.Text "WARNING: W1.1 dispatch 'f1' opened ") -and (Test-DcHas $dcF1s.Text 'was never closed')) `
        "open exit $($dcF1o.Code), status exit $($dcF1s.Code); status names f1: $(Test-DcHas $dcF1s.Text "dispatch 'f1'")"
    $dcF1c = Invoke-DcK $dcHome @('dispatch-close', '-Phase', 'W1.1', '-Name', 'f1', '-Path', $dcP)
    $dcF1t = Invoke-DcK $dcHome @('status', '-Path', $dcP)
    Add-DcRow 'f-control-status-silent-once-closed' (($dcF1c.Code -eq 0) -and ($dcF1t.Code -eq 0) -and -not (Test-DcHas $dcF1t.Text "dispatch 'f1'")) `
        "close exit $($dcF1c.Code), status exit $($dcF1t.Code); status still names f1: $(Test-DcHas $dcF1t.Text "dispatch 'f1'")"

    # --- g: the refusals, each beside a success on the same store.
    $dcGn = Invoke-DcK $dcHome @('dispatch-close', '-Phase', 'W1.1', '-Name', 'g-none', '-Path', $dcP)
    Add-DcRow 'g-case-close-none-open-90' (($dcGn.Code -eq 90) -and (Test-DcHas $dcGn.Text "No dispatch 'g-none' is open on W1.1")) "exit $($dcGn.Code): [$($dcGn.Text)]"
    $dcG1 = Invoke-DcWindow $dcHome $dcP 'g1' $null
    Add-DcRow 'g-control-close-after-open-0' $dcG1.Ran (Get-DcBrief $dcG1)
    $dcG2a = Invoke-DcK $dcHome @('dispatch-open', '-Phase', 'W1.1', '-Name', 'g2', '-Path', $dcP)
    $dcG2b = Invoke-DcK $dcHome @('dispatch-open', '-Phase', 'W1.1', '-Name', 'g2', '-Path', $dcP)
    $dcG2c = Invoke-DcK $dcHome @('dispatch-close', '-Phase', 'W1.1', '-Name', 'g2', '-Path', $dcP)
    Add-DcRow 'g-case-open-twice-90' (($dcG2b.Code -eq 90) -and (Test-DcHas $dcG2b.Text "Dispatch 'g2' is already open on W1.1")) "second open exit $($dcG2b.Code): [$($dcG2b.Text)]"
    Add-DcRow 'g-control-first-open-0' (($dcG2a.Code -eq 0) -and ($dcG2c.Code -eq 0)) "first open exit $($dcG2a.Code), close exit $($dcG2c.Code)"
    $dcG3 = Invoke-DcK $dcHome @('dispatch-open', '-Phase', 'W9.9', '-Name', 'g3', '-Path', $dcP)
    Add-DcRow 'g-case-unknown-phase-94' (($dcG3.Code -eq 94) -and (Test-DcHas $dcG3.Text "Phase 'W9.9' is not declared")) "exit $($dcG3.Code): [$($dcG3.Text)]"
    $dcG4 = Invoke-DcK $dcHome @('dispatch-open', '-Phase', 'W1.1', '-Path', $dcP)
    Add-DcRow 'g-case-missing-name-90' (($dcG4.Code -eq 90) -and (Test-DcHas $dcG4.Text "-Name is required for 'dispatch-open'")) "exit $($dcG4.Code): [$($dcG4.Text)]"
    $dcG5 = Invoke-DcWindow $dcHome $dcP 'g3' $null
    Add-DcRow 'g-control-declared-phase-with-name-0' $dcG5.Ran (Get-DcBrief $dcG5)

    # --- h, the case: a project with no git tree.
    $dcN = Join-Path $DcRoot 'n\projn'
    New-DcProject $dcHome $dcN 'dispatch fixture N' $false $false
    $dcH1 = Invoke-DcWindow $dcHome $dcN 'h1' $null
    Add-DcRow 'h-case-no-git-tree-says-so' ($dcH1.Ran -and (Test-DcHas $dcH1.Open.Text 'no git tree')) "open exit $($dcH1.Open.Code): [$($dcH1.Open.Text)]; close exit $($dcH1.Close.Code)"

    # --- s: the stated limit over the cap. With more than 2000 paths differing from the last commit
    # at open, a write is reported as one line saying the tree changed, not by its path. Control: a
    # window with no write in that tree prints nothing.
    $dcC = Join-Path $DcRoot 'c\projc'
    New-DcRepo $dcC
    Set-DcFile (Join-Path $dcC 'base.md') "base`n"
    Save-DcCommit $dcC 'base' @()
    New-DcProject $dcHome $dcC 'dispatch fixture C' $true $false
    for ($dcBi = 0; $dcBi -lt 2001; $dcBi++) { Set-DcFile (Join-Path $dcC "bulk\b$dcBi.txt") "bulk $dcBi`n" }
    $dcS0 = Invoke-DcWindow $dcHome $dcC 's0' $null
    Add-DcRow 's-control-over-cap-no-write-silent' ($dcS0.Ran -and ($dcS0.Close.Text.Trim() -eq '')) (Get-DcBrief $dcS0)
    $dcS1 = Invoke-DcWindow $dcHome $dcC 's1' { Set-DcFile (Join-Path $dcC 's1-new.md') "new`n" }
    Add-DcRow 's-case-over-cap-one-line-stated-limit' ($dcS1.Ran -and (Test-DcHas $dcS1.Close.Text 'over the 2000 cap - not itemised) (changed)') -and -not (Test-DcHas $dcS1.Close.Text 's1-new.md')) (Get-DcBrief $dcS1)

    # --- e: a project that shares its progress through its repo.
    $dcS = Join-Path $DcRoot 's\projs'
    New-DcProject $dcHome $dcS 'dispatch fixture S' $true $true
    $dcSArt = Join-Path $dcS 'progress\phases\W1.1\artifacts'
    $dcE1 = Invoke-DcWindow $dcHome $dcS 'e1' {
        Set-DcFile (Join-Path $dcS 'notes.md') "notes`n"
        Set-DcFile (Join-Path $dcS 'progress\stray.txt') "stray`n"
        Set-DcFile (Join-Path $dcSArt 'plan.md') "# plan`n"
    }
    Add-DcRow 'e-case-project-write-named' ($dcE1.Ran -and (Test-DcHas $dcE1.Close.Text '(project): notes.md (new)')) (Get-DcBrief $dcE1)
    Add-DcRow 'e-case-phase-folder-under-progress-named' ($dcE1.Ran -and (Test-DcHas $dcE1.Close.Text 'phase folder: plan.md (new)')) (Get-DcBrief $dcE1)
    Add-DcRow 'e-control-progress-write-not-named' ($dcE1.Ran -and (Test-DcHas $dcE1.Close.Text '(project): notes.md (new)') -and -not (Test-DcHas $dcE1.Close.Text 'stray.txt')) (Get-DcBrief $dcE1)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$DcTempBase = [System.IO.Path]::GetTempPath()
$DcRoot = Join-Path $DcTempBase ('keel-dispatch-suite-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 12))

# The scratch root must resolve INSIDE the system temp directory before anything is written.
$DcTempBaseFull = (Get-Item -LiteralPath $DcTempBase).FullName.TrimEnd('\', '/')
New-Item -ItemType Directory -Path $DcRoot -Force | Out-Null
$DcRootFull = (Get-Item -LiteralPath $DcRoot).FullName.TrimEnd('\', '/')
if (-not $DcRootFull.StartsWith("$DcTempBaseFull$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine("test-dispatch-check: refusing to run - scratch root '$DcRootFull' does not resolve inside '$DcTempBaseFull'.")
    exit 1
}

# No git identity, repository or hook variable from the caller reaches a fixture.
foreach ($DcVar in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'GIT_*' })) { Remove-Item -LiteralPath "Env:$($DcVar.Name)" }
$DcGitGlobal = Join-Path $DcRoot 'gitglobal'
Set-DcFile $DcGitGlobal ''
$env:GIT_CONFIG_GLOBAL = $DcGitGlobal
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:HOME = $DcRoot
$env:KEEL_OUTWARD = 'block'

$DcFailed = 0
$DcAbort = ''
try {
    try { Invoke-DcCases -DcRoot $DcRoot }
    catch { $DcAbort = $_.Exception.Message }

    Write-Output ''
    Write-Output "== dispatch check: $DcWrapper"
    foreach ($DcRow in @($script:DcRows)) {
        if (-not $DcRow.Ok) { $DcFailed++ }
        if ($List -or -not $DcRow.Ok) {
            Write-Output ("  {0}  {1,-44} {2}" -f $(if ($DcRow.Ok) { 'PASS' } else { 'FAIL' }), $DcRow.Name, $DcRow.Why)
        }
    }
    if ($DcAbort) {
        # A fixture step that failed stops the run; it is a failure, never a short green list.
        $DcFailed++
        Write-Output "  FAIL  fixture step: $DcAbort"
    }
}
finally {
    if (Test-Path -LiteralPath $DcRoot) {
        try { Remove-Item -LiteralPath $DcRoot -Recurse -Force -ErrorAction Stop } catch { }
    }
}

Write-Output ''
Write-Output ("test-dispatch-check: {0} case(s), {1} failure(s)." -f @($script:DcRows).Count, $DcFailed)
if ($DcFailed -gt 0) { exit 1 }
exit 0
