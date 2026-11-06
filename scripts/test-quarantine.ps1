<#
    test-quarantine.ps1 - the verification suite for the three quarantine code points.

    WHY THIS EXISTS. Charter P23 says sensitive material never enters a tracked folder.
    For a project carrying "quarantine": true, the mechanism enforcing that is THREE lines
    of code plus prose. A rule that is read but never run against its own input is not
    known to work, so each of the three is exercised here against scratch fixtures.

    WHAT IT COVERS. Three code points, each with a control that must behave DIFFERENTLY:

      R1  Get-HandoffDir in keel-state.ps1 - redirects a quarantined project's handoff
          OUT of the repo, into <home>/quarantine/<slug>/handoffs. A redirect, not a
          refusal, and the only wrapper write that otherwise lands in a tracked folder.
      R2  the signal path in keel-state.ps1 - refuses evidence that is multi-line or
          longer than 240 characters from a quarantined project, at exit 97 (P26).
      R3  Resolve-DocsRoot in keel-index.ps1 - refuses a declared docs root on a
          quarantined project at exit 90, because the index writes every heading into a
          file inside the repo.

    A CONTROL IS THE LOAD-BEARING HALF, not a formality. A refusal that refuses
    everybody is indistinguishable from one that reads the flag, and telling those two
    apart is the entire point. Every R-case below is paired with an identical call
    against a NON-quarantined fixture, which must NOT refuse: a control proving the
    instrument RAN is not a control proving it DISCRIMINATES.

    R3 ASSERTS THE MESSAGE, NOT ONLY THE CODE. Resolve-DocsRoot has TEN separate Fail 90
    paths ahead of the quarantine one - unparseable JSON, not a string, absolute path,
    does not exist, names a file, reparse point, the project root itself, outside the
    project, inside an always-indexed root, inside a never-indexed folder - and the
    quarantine refusal is the eleventh. A bare "exit 90" would be satisfied by any of the
    ten, so the case also requires the word `quarantine` in the message. Without that,
    breaking the guard could still score green via a neighbour.

    ISOLATION, AND IT IS VERIFIED BEFORE ANYTHING IS WRITTEN. keel-state.ps1 derives its
    whole state home from $env:USERPROFILE ($KeelHome = Join-Path $env:USERPROFILE
    '.keel'), so overriding that one variable moves state, signals AND the quarantine
    directory together. keel-index.ps1 names neither, working purely from the project
    path. The fixtures live under the system temp directory and the suite refuses to run
    if its scratch home does not resolve inside that directory - a scratch project built
    under the wrong root would write into a REAL project's state.

    Run it:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-quarantine.ps1
      ... -RealProjects   a READ-ONLY census over every real project: what handoff path
                          does the wrapper resolve for each? Writes nothing. Diagnostic
                          and deliberately NOT on the push path, exactly as the gate
                          suite's -AgainstHead is.

    Exit 0 = every case behaved. Exit 1 = at least one did not.

    Windows PowerShell 5.1 compatible. ASCII only.
#>

[CmdletBinding()]
param(
    [switch]$RealProjects,
    [switch]$Quiet,
    [string]$ProjectsRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Every local in this file is Tq-prefixed. PowerShell variable names are case-insensitive:
# a local whose name matches a param() name IS that parameter, and a type constraint
# follows the name - and two ordinary locals collide the same way.
$TqRepoRoot     = Split-Path -Parent $PSScriptRoot
$TqStateWrapper = Join-Path $TqRepoRoot 'plugins\keel-workflow\skills\keel-orchestrator\wrappers\keel-state.ps1'
$TqIndexWrapper = Join-Path $TqRepoRoot 'plugins\keel-project\skills\keel-project-context\wrappers\keel-index.ps1'

$script:TqResults = @()

# A PowerShell function returns everything it emits, so one that both writes output and
# returns a value hands the caller an array. These add to a script-scope list and return
# nothing at all.
function Add-Result {
    param([string]$TqName, [bool]$TqOk, [string]$TqWhy)
    $script:TqResults += [pscustomobject]@{ Name = $TqName; Ok = $TqOk; Why = $TqWhy }
}

# A native tool's success text can arrive on stderr, and 2>&1 under 'Stop' turns that
# into a terminating error. Set Continue around the call and let the EXIT CODE decide.
# Windows PowerShell decodes native stdout with [Console]::OutputEncoding, which can be
# codepage 437, so any non-ASCII byte a wrapper emits is mangled at capture. Nothing this
# suite matches on is non-ASCII, and it compares rather than persists, so no encoding
# override is taken - stated so the next reader knows it was considered.
function Invoke-Wrapper {
    param([string]$TqScript, [string[]]$TqArgs, [string]$TqHome)

    $TqPrevProfile = $env:USERPROFILE
    if (-not [string]::IsNullOrEmpty($TqHome)) { $env:USERPROFILE = $TqHome }
    $TqPrevPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    $TqLines = @()
    $TqCode  = 0
    try {
        $TqLines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $TqScript @TqArgs 2>&1 |
                   ForEach-Object { $_.ToString() }
        $TqCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $TqPrevPref
        $env:USERPROFILE       = $TqPrevProfile
    }

    return [pscustomobject]@{ Code = $TqCode; Text = (@($TqLines) -join "`n") }
}

# ---------------------------------------------------------------------------
# -RealProjects: a read-only census. `status` writes nothing - verified by an
# unchanged state.json md5 before and after - and prints the path Get-HandoffDir
# itself resolved, so this reads the flag through the wrapper's own code path
# rather than re-implementing the predicate in the test.
# ---------------------------------------------------------------------------
# It sets $script:TqCensusFailed and returns NOTHING. A PowerShell function returns
# everything it emits, so one that both printed the report and returned a code would hand
# `$code = Invoke-RealCensus` every printed line plus the value - swallowing the report
# into the exit-code variable and printing nothing at exit 0.
function Invoke-RealCensus {
    param([string]$TqRoot)

    $script:TqCensusFailed = $false

    if (-not (Test-Path -LiteralPath $TqRoot)) {
        [Console]::Error.WriteLine("test-quarantine: projects root '$TqRoot' does not exist.")
        $script:TqCensusFailed = $true
        return
    }

    $TqSeen      = 0
    $TqInside    = 0
    $TqOutside   = 0
    $TqUnknown   = 0
    $TqSeenNames = @()

    Write-Output ''
    Write-Output "== real projects (READ-ONLY census) under $TqRoot"
    Write-Output ('  {0,-26} {1,-12} {2,-9} {3}' -f 'PROJECT', 'QUARANTINE', 'HANDOFF', 'PATH')

    foreach ($TqDir in @(Get-ChildItem -LiteralPath $TqRoot -Directory)) {
        $TqCfgPath = Join-Path $TqDir.FullName 'keel.json'
        if (-not (Test-Path -LiteralPath $TqCfgPath)) { continue }

        # An empty file parses to $null without throwing, so the crash lands later on the
        # first property access. Null-check after every parse.
        $TqCfg = $null
        try { $TqCfg = Get-Content -Raw -LiteralPath $TqCfgPath | ConvertFrom-Json } catch { $TqCfg = $null }
        if ($null -eq $TqCfg) {
            Write-Output ('  {0,-26} {1,-12} {2,-9} {3}' -f $TqDir.Name, '?', 'UNREADABLE', $TqCfgPath)
            $TqUnknown++
            continue
        }

        # .PSObject.Properties.Name throws under StrictMode on an object with no
        # properties. Index the collection instead.
        $TqFlagProp = $TqCfg.PSObject.Properties['quarantine']
        $TqFlag     = $false
        if ($null -ne $TqFlagProp) { $TqFlag = [bool]$TqFlagProp.Value }

        $TqSeen++

        # The slug the state store files this project under, which is what the
        # reconciliation below compares against. Prefer the manifest's own name over the
        # directory name: the two are usually equal, and nothing guarantees they stay
        # equal.
        $TqNameProp = $TqCfg.PSObject.Properties['name']
        if ($null -ne $TqNameProp -and -not [string]::IsNullOrWhiteSpace([string]$TqNameProp.Value)) {
            $TqSeenNames += ([string]$TqNameProp.Value)
        }
        else { $TqSeenNames += $TqDir.Name }

        $TqOut  = Invoke-Wrapper -TqScript $TqStateWrapper -TqArgs @('status', '-Path', $TqDir.FullName) -TqHome ''
        $TqPath = ''
        foreach ($TqLine in @($TqOut.Text -split "`n")) {
            if ($TqLine -match 'handoff:\s*(.+?)\s*$') { $TqPath = $Matches[1]; break }
        }

        $TqWhere = 'NONE'
        if ($TqPath -ne '') {
            if ($TqPath -match '[\\/]\.keel[\\/]quarantine[\\/]') { $TqWhere = 'OUTSIDE'; $TqOutside++ }
            elseif ([System.IO.Path]::IsPathRooted($TqPath))      { $TqWhere = 'OUTSIDE'; $TqOutside++ }
            else                                                  { $TqWhere = 'INSIDE';  $TqInside++ }
        }

        Write-Output ('  {0,-26} {1,-12} {2,-9} {3}' -f $TqDir.Name, $TqFlag, $TqWhere, $TqPath)
    }

    Write-Output ''
    Write-Output ("  $TqSeen project(s): $TqInside routed INSIDE the repo, $TqOutside routed OUTSIDE, $TqUnknown unreadable.")

    # The walk above sees exactly one directory level, so a project moved into a SUBFOLDER
    # of the projects root vanishes from this census in silence - it is not counted, and it
    # is not in the 'unreadable' figure either, because that counts unparseable manifests
    # only. The census then reports fewer projects than the store holds, at exit 0, with
    # the control line below still firing correctly: nothing is wrong in the output except
    # the population, which is what makes it invisible.
    #
    # The repair is NOT a deeper walk, which would fix today's directory layout and no
    # other. Charter P10: where two authorities disagree, the disagreement is itself the
    # finding and is surfaced. So ask the store what it holds and name what the walk missed.
    # Read through the wrapper rather than by opening state.json, per charter P15.
    $TqStoreOut = Invoke-Wrapper -TqScript $TqStateWrapper -TqArgs @('list') -TqHome ''
    $TqStore    = @()
    foreach ($TqRow in @($TqStoreOut.Text -split "`n")) {
        $TqRow = $TqRow.Trim()
        if ($TqRow -eq '' -or $TqRow.StartsWith('KEEL:')) { continue }
        $TqFirst = ($TqRow -split '\s+')[0]
        if (-not [string]::IsNullOrWhiteSpace($TqFirst)) { $TqStore += $TqFirst }
    }

    $TqUnseen = @($TqStore | Where-Object { $TqSeenNames -notcontains $_ })
    if ($TqStoreOut.Code -ne 0) {
        Write-Output ("  RECONCILE: could not read the project store (keel-state.ps1 list exit {0}), so this census cannot say whether it saw every project." -f $TqStoreOut.Code)
        $script:TqCensusFailed = $true
        return
    }
    # Silent when the walk and the store agree, which is the expected state (charter P16).
    if ($TqUnseen.Count -gt 0) {
        Write-Output ("  RECONCILE: the store holds {0} project(s); this walk saw {1}. NOT SEEN: {2}." -f @($TqStore).Count, $TqSeen, ($TqUnseen -join ', '))
        Write-Output '  A project missing here has been moved below the one directory level this walk reads, or deleted. Its quarantine routing is NOT covered by the rows above.'
    }

    # The positive control for the census, and it is the half that matters. If every
    # project routes the same way the census has not read the flag at all - it has
    # measured a constant and called it a verdict.
    if ($TqSeen -gt 1 -and ($TqInside -eq 0 -or $TqOutside -eq 0)) {
        Write-Output '  CONTROL FAILED: every project routed the same way, so this census does not discriminate on the flag.'
        $script:TqCensusFailed = $true
        return
    }
    Write-Output '  Control: the projects do NOT all route the same way, so the census discriminates on the flag.'
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
function New-Fixture {
    param([string]$FxRepo, [string]$FxHome, [bool]$FxQuarantine)

    New-Item -ItemType Directory -Path $FxRepo -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $FxRepo 'docs') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path (Join-Path $FxRepo 'docs') 'note.md') `
                -Value "# Fixture note" -Encoding ASCII

    $FxArgs = @('init-project', '-Title', 'quarantine suite fixture', '-Path', $FxRepo, '-Tracker', 'none')
    if ($FxQuarantine) { $FxArgs += '-Quarantine' }
    $FxInit = Invoke-Wrapper -TqScript $TqStateWrapper -TqArgs $FxArgs -TqHome $FxHome
    if ($FxInit.Code -ne 0) { throw "fixture init-project failed (exit $($FxInit.Code)): $($FxInit.Text)" }

    # A docs root, so R3 has an input at all. init-project writes no 'docs' key, so a
    # fixture built by the wrapper alone would never reach R3.
    $FxCfgPath = Join-Path $FxRepo 'keel.json'
    $FxCfg     = Get-Content -Raw -LiteralPath $FxCfgPath | ConvertFrom-Json
    if ($null -eq $FxCfg) { throw "fixture keel.json parsed to null at $FxCfgPath" }
    Add-Member -InputObject $FxCfg -NotePropertyName 'docs' -NotePropertyValue 'docs' -Force
    [System.IO.File]::WriteAllText($FxCfgPath, ($FxCfg | ConvertTo-Json -Depth 14), (New-Object System.Text.UTF8Encoding($false)))

    # A phase must exist before a signal can cite one (the wrapper exits 97 otherwise),
    # and a workstream must declare a goal (exit 98).
    foreach ($FxStep in @(
        @('add-goal',       '-Id', 'G1',   '-Text',  'fixture goal'),
        @('add-workstream', '-Id', 'W1',   '-Title', 'fixture workstream', '-Parent', 'root', '-Goals', 'G1'),
        @('add-phase',      '-Phase', 'W1.1', '-Scope', 'fixture phase', '-Actor', 'agent', '-RunOrder', '1')
    )) {
        $FxStepArgs = @($FxStep) + @('-Path', $FxRepo)
        $FxRes = Invoke-Wrapper -TqScript $TqStateWrapper -TqArgs $FxStepArgs -TqHome $FxHome
        if ($FxRes.Code -ne 0) { throw "fixture step '$($FxStep[0])' failed (exit $($FxRes.Code)): $($FxRes.Text)" }
    }
}

# ---------------------------------------------------------------------------
# The cases
# ---------------------------------------------------------------------------
function Invoke-Cases {
    param([string]$TqTempRoot)

    $TqHome    = Join-Path $TqTempRoot 'home'
    $TqQRepo   = Join-Path $TqTempRoot 'fixture-quarantined'
    $TqNRepo   = Join-Path $TqTempRoot 'fixture-control'

    New-Fixture -FxRepo $TqQRepo -FxHome $TqHome -FxQuarantine $true
    New-Fixture -FxRepo $TqNRepo -FxHome $TqHome -FxQuarantine $false

    # Evidence over the 240-character reference limit, on ONE line. Single-line
    # deliberately: an embedded newline does not survive argument passing to
    # powershell.exe -File, so a multi-line probe would test the harness, not the guard.
    $TqLongEvidence = ('e' * 300)

    # --- HARNESS CONTROL ---------------------------------------------------
    # Group 5 of the gate suite opens the same way. If a quarantined project does not
    # refuse oversized evidence, this suite is not reaching the mechanism at all and no
    # other row below means anything.
    $TqHarness = Invoke-Wrapper -TqScript $TqStateWrapper -TqHome $TqHome -TqArgs @(
        'signal', '-Kind', 'gap', '-Phase', 'W1.1', '-Detail', 'harness control',
        '-Evidence', $TqLongEvidence, '-Path', $TqQRepo)
    Add-Result 'HARNESS-CONTROL-quarantined-signal-refused' ($TqHarness.Code -eq 97) `
               "exit $($TqHarness.Code), wanted 97"

    # --- R1: the handoff redirect ------------------------------------------
    $TqR1q = Invoke-Wrapper -TqScript $TqStateWrapper -TqHome $TqHome -TqArgs @(
        'handoff', '-Next', 'fixture next', '-Detail', 'fixture detail', '-Path', $TqQRepo)
    $TqR1qPath = ''
    foreach ($TqLine in @($TqR1q.Text -split "`n")) {
        if ($TqLine -match 'Handoff written:\s*(.+?)\s*$') { $TqR1qPath = $Matches[1]; break }
    }
    $TqR1qOk = ($TqR1q.Code -eq 0) -and ($TqR1qPath -ne '') -and
               ($TqR1qPath -notlike "$TqQRepo*") -and ($TqR1qPath -match '[\\/]quarantine[\\/]')
    Add-Result 'R1-quarantined-handoff-outside-repo' $TqR1qOk `
               "exit $($TqR1q.Code), path '$TqR1qPath' - wanted a path under the quarantine store and NOT under $TqQRepo"

    $TqR1n = Invoke-Wrapper -TqScript $TqStateWrapper -TqHome $TqHome -TqArgs @(
        'handoff', '-Next', 'fixture next', '-Detail', 'fixture detail', '-Path', $TqNRepo)
    $TqR1nPath = ''
    foreach ($TqLine in @($TqR1n.Text -split "`n")) {
        if ($TqLine -match 'Handoff written:\s*(.+?)\s*$') { $TqR1nPath = $Matches[1]; break }
    }
    $TqR1nFull = ''
    if ($TqR1nPath -ne '') {
        if ([System.IO.Path]::IsPathRooted($TqR1nPath)) { $TqR1nFull = $TqR1nPath }
        else { $TqR1nFull = (Join-Path $TqNRepo $TqR1nPath) }
    }
    $TqR1nOk = ($TqR1n.Code -eq 0) -and ($TqR1nFull -ne '') -and (Test-Path -LiteralPath $TqR1nFull) -and
               ($TqR1nFull -notmatch '[\\/]quarantine[\\/]')
    Add-Result 'R1-control-handoff-inside-repo' $TqR1nOk `
               "exit $($TqR1n.Code), path '$TqR1nPath' - wanted a path inside $TqNRepo and NOT under the quarantine store"

    # --- R2: the signal-evidence refusal -----------------------------------
    $TqR2q = Invoke-Wrapper -TqScript $TqStateWrapper -TqHome $TqHome -TqArgs @(
        'signal', '-Kind', 'gap', '-Phase', 'W1.1', '-Detail', 'r2 quarantined',
        '-Evidence', $TqLongEvidence, '-Path', $TqQRepo)
    Add-Result 'R2-quarantined-evidence-refused' `
               (($TqR2q.Code -eq 97) -and ($TqR2q.Text -match 'quarantine')) `
               "exit $($TqR2q.Code), wanted 97 with 'quarantine' in the message"

    $TqR2n = Invoke-Wrapper -TqScript $TqStateWrapper -TqHome $TqHome -TqArgs @(
        'signal', '-Kind', 'gap', '-Phase', 'W1.1', '-Detail', 'r2 control',
        '-Evidence', $TqLongEvidence, '-Path', $TqNRepo)
    Add-Result 'R2-control-evidence-accepted' ($TqR2n.Code -eq 0) `
               "exit $($TqR2n.Code), wanted 0 - the identical oversized evidence must be ACCEPTED when the flag is off"

    # --- R3: the docs-root refusal -----------------------------------------
    # The message is asserted as well as the code: Resolve-DocsRoot has TEN other Fail 90
    # paths ahead of this one, and a bare 90 would be satisfied by any of them.
    $TqR3q = Invoke-Wrapper -TqScript $TqIndexWrapper -TqHome $TqHome -TqArgs @('-Path', $TqQRepo)
    Add-Result 'R3-quarantined-docsroot-refused' `
               (($TqR3q.Code -eq 90) -and ($TqR3q.Text -match 'quarantine')) `
               "exit $($TqR3q.Code), wanted 90 with 'quarantine' in the message"

    # The control asserts NOT-90 rather than a bare 0: the indexer returns 1 - ordinary
    # staleness - on a project whose index has never been built, and 0 only after -Write
    # has run there. Asserting 0 here would fail for a reason that has nothing to do with
    # quarantine.
    $TqR3n = Invoke-Wrapper -TqScript $TqIndexWrapper -TqHome $TqHome -TqArgs @('-Path', $TqNRepo)
    Add-Result 'R3-control-docsroot-not-refused' `
               (($TqR3n.Code -ne 90) -and ($TqR3n.Text -notmatch 'quarantine')) `
               "exit $($TqR3n.Code) - wanted anything but 90, and no 'quarantine' in the message"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if ($RealProjects) {
    $TqCensusRoot = $ProjectsRoot
    if ([string]::IsNullOrWhiteSpace($TqCensusRoot)) { $TqCensusRoot = (Split-Path -Parent $TqRepoRoot) }
    $script:TqCensusFailed = $false
    Invoke-RealCensus -TqRoot $TqCensusRoot
    if ($script:TqCensusFailed) { exit 1 }
    exit 0
}

$TqTempBase = [System.IO.Path]::GetTempPath()
$TqTempRoot = Join-Path $TqTempBase ("keel-quarantine-suite-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 12))

# The scratch home must resolve INSIDE the system temp directory before anything is
# written. A fixture built under the wrong root writes state into a REAL project, and
# that is the one failure in this file that would not be recoverable by re-running it.
$TqTempBaseFull = (Get-Item -LiteralPath $TqTempBase).FullName.TrimEnd('\', '/')
New-Item -ItemType Directory -Path $TqTempRoot -Force | Out-Null
$TqTempRootFull = (Get-Item -LiteralPath $TqTempRoot).FullName.TrimEnd('\', '/')
if (-not $TqTempRootFull.StartsWith("$TqTempBaseFull$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine("test-quarantine: refusing to run - scratch root '$TqTempRootFull' does not resolve inside '$TqTempBaseFull'.")
    exit 1
}

$TqFailed = 0
try {
    Invoke-Cases -TqTempRoot $TqTempRoot

    if (-not $Quiet) { Write-Output ''; Write-Output "== quarantine refusals: $TqRepoRoot" }

    $TqHarnessOk = $null
    foreach ($TqResult in @($script:TqResults)) {
        if (-not $TqResult.Ok) {
            $TqFailed++
            if (-not $Quiet) { Write-Output ("  FAIL  {0,-44} {1}" -f $TqResult.Name, $TqResult.Why) }
        }
        if ($TqResult.Name -eq 'HARNESS-CONTROL-quarantined-signal-refused') { $TqHarnessOk = $TqResult.Ok }
    }

    if ($TqHarnessOk -ne $true) {
        Write-Output ''
        Write-Output '  HARNESS CONTROL FAILED: a quarantined project did not refuse oversized signal evidence.'
        Write-Output '  The suite is not reaching the mechanism. No other row in this run means anything.'
    }

    if (-not $Quiet) {
        Write-Output ("  {0} case(s), {1} failure(s)." -f @($script:TqResults).Count, $TqFailed)
    }
}
finally {
    # Best effort. A leftover fixture under TEMP is noise; a failure to remove it is not
    # a reason to report a green suite as red.
    if (Test-Path -LiteralPath $TqTempRoot) {
        try { Remove-Item -LiteralPath $TqTempRoot -Recurse -Force -ErrorAction Stop } catch { }
    }
}

Write-Output ''
Write-Output ("test-quarantine: {0} case(s), {1} failure(s)." -f @($script:TqResults).Count, $TqFailed)
if ($TqFailed -gt 0) { exit 1 }
exit 0
