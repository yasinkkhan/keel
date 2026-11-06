# test-signal-judgement.ps1 - the suite for the SIGNAL-RECORD write points.
#
# WHY THIS IS A SIBLING rather than more cases inside one of the suites that already run.
# Each existing suite's subject is a named surface: test-plugins-gate.ps1 has the charter
# gate's marker file, test-quarantine.ps1 has the three quarantine code points behind a
# per-project keel.json flag, and test-outward-guard.ps1 has the five process invocations
# that leave the machine. This suite's subject is what the signal RECORD holds and what the
# listing prints - a question none of the three asks. test-outward-guard.ps1 does exercise
# the signal verbs, but its rows on them assert which outward COMMAND was declined, not
# what the store then holds. judge-signal makes no process call at all, so a row for it
# inside a suite whose stated subject is outward invocations would have no outward
# dimension. One file answering two unrelated questions is the charter P10 error and its
# case count stops meaning one thing; section 14 of check-suite-docs.ps1 rests on the same
# argument.
#
# WHAT IT COVERS.
#
#   judge-signal   the append onto an OPEN signal, and NINE of its FIFTEEN refusals
#   resolve-signal the 'addresses' key persisted on a terminal PROMOTED resolution
#   signals        the JUDGED continuation lines and the terminal line's scope suffix, the
#                  review-date suffix and its two counts, and -Id's scoping and refusals
#   the hook       scripts/keel-session-start.ps1's parse of the counts line - RUN, not
#                  imitated: row P26 invokes the real file against the scratch store
#
# THE REFUSAL COVERAGE IS STATED AS A FRACTION ON PURPOSE: how many refusal paths the verb
# has, and how many of them this suite exercises. judge-signal has FIFTEEN refusal paths
# and this suite exercises NINE - the -As enum, -Phase missing at 97, -Phase undeclared at
# 94, an unknown id at 94, a null parse at 96, a terminal signal at 90, a bad -Addresses at
# 90, the missing review date at 95, and a malformed review date at 90. UNCOVERED, and named
# rather than left to be discovered: -Id missing, -Id malformed, -As missing, -Detail
# missing, -Phase malformed, and no project resolved at 91. Each of those six is a one-line
# Require-Param, Assert-PhaseId or Resolve-ProjectOrFail shared with verbs that already
# ship, which is the reason they are lower value here.
#
# EVERY CASE IS PAIRED WITH A CONTROL THAT MUST BEHAVE DIFFERENTLY, and the pair is
# asserted together in a third row named -DISCRIMINATES. That third row is the point: a
# refusal that refuses everybody is indistinguishable from one that reads the field, and
# an assertion that something is absent is worthless unless the same instrument, on the
# same fixture, has been shown to find it when it is there. Where the case asserts a
# refusal the control provokes a SUCCESS from the same verb on the same store, so the
# refusal is shown to be selective rather than total.
#
# THE SCRATCH HOME IS ASSERTED, NEVER ASSUMED. The suite refuses to run unless its root
# resolves inside the system temp directory - the rule test-quarantine.ps1 already
# enforces - and a harness control then asserts that the record it writes really landed
# under that scratch home. A fixture whose home silently fell back to the real
# %USERPROFILE% would pass every row below while writing into the live signal store.
#
# Every local in this file is Sj-prefixed, because PowerShell variable names are
# case-insensitive: a local whose name matches a param() name IS that parameter, and two
# ordinary locals collide the same way.
#
# Add-Result appends to a script-scope list and returns NOTHING. A function that both
# writes output and returns a value hands the caller a two-element array, which is truthy.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SjRepoRoot     = Split-Path -Parent $PSScriptRoot
$SjStateWrapper = Join-Path $SjRepoRoot 'plugins\keel-workflow\skills\keel-orchestrator\wrappers\keel-state.ps1'
$SjHook         = Join-Path $SjRepoRoot 'scripts\keel-session-start.ps1'
$SjPwsh         = Join-Path $PSHOME 'powershell.exe'

# The literal strings this suite matches on. Kept here rather than inline so a wording
# change in the wrapper breaks every row at once and loudly, instead of one row quietly.
$SjJudgedLead   = '      JUDGED '
$SjLegendJudged = 'JUDGED = read and judged with NO terminal verdict'
$SjLegendVals   = 'DEPRIORITISED = judged real and consciously not scheduled'
$SjDetailA      = 'scratch judgement A - real and not scheduled'
$SjDetailB      = 'scratch judgement B - re-measured and still real'

# The review date on a judgement. FIXED LITERALS rather than offsets from Get-Date,
# so a row that breaks names the value it expected instead of one computed at run time.
# ONE ROW IS THE EXCEPTION, deliberately: P24 tests the boundary itself, and no fixed date
# can sit on a boundary that moves every day - a second past constant would leave a '-le'
# regressed to '-lt' exactly as invisible as this one does. P24 computes today and tomorrow
# at run time and says so beside it.
# PAST is far enough back that it reads DUE on any day this suite is ever run, and FUTURE
# far enough forward that no row starts failing on a date this file could not see coming.
# BAD matches ^\d{4}-\d{2}-\d{2}$ but is not a real date, so it reaches Assert-Date's
# SECOND Fail 90 path - the ParseExact one - rather than the cheap regex rejection.
$SjReviewPast   = '2020-01-01'
$SjReviewFuture = '2099-12-31'
$SjReviewBad    = '2026-13-45'
$SjLegendReview = "UNSCHEDULED = deprioritised with no return date"

$script:SjResults = @()

function Add-Result {
    param([string]$SjName, [bool]$SjOk, [string]$SjWhy)
    $script:SjResults += [pscustomobject]@{ Name = $SjName; Ok = $SjOk; Why = $SjWhy }
}

# Asserts a case, its control, and that the two DIFFER. Three rows from one call, so a
# pair can never be added with its discrimination row forgotten.
function Add-Pair {
    param(
        [string]$SjName,
        [bool]$SjCaseOk,   [string]$SjCaseWhy,
        [bool]$SjCtlOk,    [string]$SjCtlWhy,
        [bool]$SjDiffers,  [string]$SjDiffWhy
    )
    Add-Result "$SjName-case"    $SjCaseOk $SjCaseWhy
    Add-Result "$SjName-CONTROL" $SjCtlOk  $SjCtlWhy
    Add-Result "$SjName-DISCRIMINATES" $SjDiffers $SjDiffWhy
}

function Set-EnvVar {
    param([string]$SjName, $SjValue)
    if ($null -eq $SjValue) { Remove-Item -LiteralPath "Env:\$SjName" -ErrorAction SilentlyContinue }
    else { Set-Item -LiteralPath "Env:\$SjName" -Value $SjValue }
}

# A native tool's success text can arrive on stderr, and a bare 2>&1
# under 'Stop' turns that into a terminating error. Set Continue around the call and let
# the EXIT CODE decide.
function Invoke-Wrapper {
    param([string[]]$SjArgs, [string]$SjHome)

    $SjPrevProfile = $env:USERPROFILE
    $SjPrevPref    = $ErrorActionPreference

    $SjLines = @()
    $SjCode  = 0
    try {
        Set-EnvVar 'USERPROFILE' $SjHome
        $ErrorActionPreference = 'Continue'
        $SjLines = & $SjPwsh -NoProfile -ExecutionPolicy Bypass -File $SjStateWrapper @SjArgs 2>&1 |
                   ForEach-Object { $_.ToString() }
        $SjCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $SjPrevPref
        Set-EnvVar 'USERPROFILE' $SjPrevProfile
    }

    return [pscustomobject]@{ Code = $SjCode; Text = (@($SjLines) -join "`n") }
}

function Get-SignalPath {
    param([string]$SjHome, [string]$SjId)
    return (Join-Path (Join-Path (Join-Path $SjHome '.keel') 'signals') "$SjId.json")
}

function Get-SignalRecord {
    param([string]$SjHome, [string]$SjId)
    $SjPath = Get-SignalPath -SjHome $SjHome -SjId $SjId
    if (-not (Test-Path -LiteralPath $SjPath)) { throw "fixture signal record not found at $SjPath" }
    $SjRec = Get-Content -Raw -LiteralPath $SjPath | ConvertFrom-Json
    # An empty or truncated file parses to $null without throwing.
    if ($null -eq $SjRec) { throw "fixture signal record at $SjPath parsed to null" }
    return $SjRec
}

# Indexed rather than read off .Name: under Set-StrictMode, '.Properties.Name' throws on
# an object with no properties.
function Test-HasKey {
    param($SjObj, [string]$SjKey)
    if ($null -eq $SjObj) { return $false }
    return ($null -ne $SjObj.PSObject.Properties[$SjKey])
}

# The indented continuation lines that belong to one signal's row: everything after the
# row until the next unindented line. Continuation lines carry no signal id, so counting
# them globally cannot attribute a JUDGED line to a particular record - which is how a
# control asserting "this signal has no JUDGED line" can be written so that it searches
# for a string it could never find, and passes for the wrong reason.
#
# A one-element array unrolls through 'return', and there are TWO remedies; applying BOTH
# is itself a bug. `return ,$SjOut` wraps the array so a one-element result does not
# unroll; `@()` at the call site re-wraps whatever arrives. Doing both yields an array
# whose single element is an array, and `@()` does not flatten nested arrays. The
# followers then dump as the single string 'System.Object[]', `-contains` compares against
# the inner array and returns false, and the JUDGED count still comes back 1 - because
# `-like` against a COLLECTION filters rather than tests, so a match on any element reads
# as a match. A broken structure and a plausible number.
#
# So: return the array plainly and let the call site's @() do the one re-wrap.
function Get-RowFollowers {
    param([string[]]$SjLines, [string]$SjId)
    $SjOut  = @()
    $SjSeen = $false
    foreach ($SjL in $SjLines) {
        if ($SjSeen) {
            if ($SjL -like '      *') { $SjOut += $SjL } else { break }
        }
        elseif (($SjL -notlike '      *') -and ($SjL -like "*$SjId*")) { $SjSeen = $true }
    }
    return $SjOut
}

# PLANTS THE ONE SHAPE THE VERB CAN NO LONGER CREATE: a DEPRIORITISED judgement carrying
# no reviewOn. judge-signal refuses that at 95, so judgements written before the field
# existed cannot be reproduced through the wrapper - and they are the entire population
# the UNSCHEDULED rendering exists for. Written directly, exactly as P8 truncates a record
# directly.
#
# WITH A BOM, because that is what the records it emulates carry: a record written by the
# wrapper itself begins ef bb bf. The wrapper re-reads the record either way, so a planted
# record without one would pass while being byte-shaped unlike every record it stands in
# for; this is stated as a measurement rather than as an assurance for that reason.
#
# WITHOUT THIS, every assertion about UNSCHEDULED is an ABSENCE assertion, and a suite made
# only of those passes with the marker deleted outright.
function Remove-StoredReviewOn {
    param([string]$SjHome, [string]$SjId)
    $SjPath = Get-SignalPath -SjHome $SjHome -SjId $SjId
    $SjRec  = Get-Content -Raw -LiteralPath $SjPath | ConvertFrom-Json
    if ($null -eq $SjRec) { throw "record at $SjPath parsed to null" }
    $SjOut = @()
    foreach ($SjJ in @($SjRec.judgements)) {
        $SjKeep = [ordered]@{}
        foreach ($SjProp in $SjJ.PSObject.Properties) {
            if ($SjProp.Name -ne 'reviewOn') { $SjKeep[$SjProp.Name] = $SjProp.Value }
        }
        $SjOut += [pscustomobject]$SjKeep
    }
    $SjRec.judgements = $SjOut
    [System.IO.File]::WriteAllText($SjPath, ($SjRec | ConvertTo-Json -Depth 14), (New-Object System.Text.UTF8Encoding($true)))
}

# The two numbers the closing line carries, read back out of the verb's own output.
#
# THE PATTERN IS A SUPERSET OF THE HOOK'S, NOT THE SAME ONE, and the difference has a
# direction worth knowing: scripts/keel-session-start.ps1 matches only as far as DUE, so a
# wording change AFTER that word breaks these rows and not the hook, while one at or before
# it breaks both. The rows are therefore the stricter reader of the two, which is the useful
# way round - but they do not prove the hook still parses. Row P26 does that, by running the
# hook itself; these rows only read the same line more strictly.
function Get-ReviewCounts {
    param([string]$SjText)
    $SjDue = -1
    $SjUns = -1
    foreach ($SjL in @($SjText -split "`n")) {
        if ($SjL -match '(\d+)\s+deprioritised signal\(s\) DUE for review;\s+(\d+)\s+unscheduled') {
            $SjDue = [int]$Matches[1]
            $SjUns = [int]$Matches[2]
        }
    }
    return [pscustomobject]@{ Due = $SjDue; Unscheduled = $SjUns }
}

# RUNS THE REAL HOOK, so a change to the hook's own pattern is exercised where it lives
# rather than through a copy of it kept here - a copy is exactly what would let the two
# drift apart unseen. Two things must be set for the hook to reach its signals section:
# USERPROFILE, which the hook's own child 'signals -Brief' inherits, exactly as
# Invoke-Wrapper sets it; and the PowerShell LOCATION, because the hook runs that section
# only when (Get-Location) is under its own repo root. With open signals planted in a
# scratch home, the hook run from the repo prints the scratch count, not the live store's;
# the same hook run from %TEMP% prints nothing.
#
# The hook's first section runs 'status -Brief', which exits 91 under a scratch home with no
# project state, so it forwards nothing; and 'git config core.hooksPath', a read while the
# value is already .githooks - the same thing every session start in this repo does.
function Invoke-Hook {
    param([string]$SjHome)

    $SjPrevProfile = $env:USERPROFILE
    $SjPrevPref    = $ErrorActionPreference

    $SjLines = @()
    $SjCode  = 0
    Push-Location -LiteralPath $SjRepoRoot
    try {
        Set-EnvVar 'USERPROFILE' $SjHome
        $ErrorActionPreference = 'Continue'
        $SjLines = & $SjPwsh -NoProfile -ExecutionPolicy Bypass -File $SjHook 2>&1 |
                   ForEach-Object { $_.ToString() }
        $SjCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $SjPrevPref
        Set-EnvVar 'USERPROFILE' $SjPrevProfile
        Pop-Location
    }

    return [pscustomobject]@{ Code = $SjCode; Text = (@($SjLines) -join "`n") }
}

# The two numbers the hook PRINTS, read out of its one signals line. COUPLED TO THE HOOK'S
# OUTPUT WORDING, declared here: 'keel: <n> open signal(s) awaiting triage' with an optional
# ', <m> due for review' before the full stop. The hook appends the due suffix only when the
# number it parsed is above zero, so an absent suffix reads as 0 - which is also what a hook
# whose parse broke prints, and that is why P26's control has to be a reading where 0 is the
# TRUE answer, set against a case where it is not. -1 means no signals line at all.
function Get-HookCounts {
    param([string]$SjText)
    $SjOpen = -1
    $SjDue  = -1
    foreach ($SjL in @($SjText -split "`n")) {
        if ($SjL -match '^keel: (\d+) open signal\(s\) awaiting triage(, (\d+) due for review)?\.') {
            $SjOpen = [int]$Matches[1]
            $SjDue  = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
        }
    }
    return [pscustomobject]@{ Open = $SjOpen; Due = $SjDue }
}

# The open count from 'signals -Brief', read with the hook's own open pattern.
function Get-BriefOpen {
    param([string]$SjText)
    $SjOpen = -1
    foreach ($SjL in @($SjText -split "`n")) {
        if ($SjL -match '(\d+)\s+open of\s+\d+\s+total') { $SjOpen = [int]$Matches[1] }
    }
    return $SjOpen
}

function New-Fixture {
    param([string]$SjRepo, [string]$SjHome)

    New-Item -ItemType Directory -Path $SjRepo -Force | Out-Null

    $SjInit = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'init-project', '-Title', 'signal judgement fixture', '-Path', $SjRepo, '-Tracker', 'none')
    if ($SjInit.Code -ne 0) { throw "fixture init-project failed (exit $($SjInit.Code)): $($SjInit.Text)" }

    foreach ($SjStep in @(
        @('add-goal',       '-Id', 'G1',     '-Text',  'fixture goal'),
        @('add-workstream', '-Id', 'W1',     '-Title', 'fixture workstream', '-Parent', 'root', '-Goals', 'G1'),
        @('add-phase',      '-Phase', 'W1.1', '-Scope', 'fixture phase', '-Actor', 'agent', '-RunOrder', '1')
    )) {
        $SjStepArgs = @($SjStep) + @('-Path', $SjRepo)
        $SjRes = Invoke-Wrapper -SjHome $SjHome -SjArgs $SjStepArgs
        if ($SjRes.Code -ne 0) { throw "fixture step '$($SjStep[0])' failed (exit $($SjRes.Code)): $($SjRes.Text)" }
    }
}

function New-Signal {
    param([string]$SjRepo, [string]$SjHome, [string]$SjDetail)

    $SjFiled = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'signal', '-Kind', 'gap', '-Phase', 'W1.1',
        '-Detail', $SjDetail,
        '-Evidence', 'scripts/test-signal-judgement.ps1 - fixture, no real defect',
        '-Path', $SjRepo)
    if ($SjFiled.Code -ne 0) { throw "fixture signal failed (exit $($SjFiled.Code)): $($SjFiled.Text)" }

    foreach ($SjLine in @($SjFiled.Text -split "`n")) {
        if ($SjLine -match 'Filed signal\s+(S\d{4})') { return $Matches[1] }
    }
    throw "could not read the filed signal id from: $($SjFiled.Text)"
}

# ---------------------------------------------------------------------------
# The cases
# ---------------------------------------------------------------------------
function Invoke-Cases {
    param([string]$SjTempRoot)

    $SjHome = Join-Path $SjTempRoot 'home'
    $SjRepo = Join-Path $SjTempRoot 'fixture-project'

    New-Fixture -SjRepo $SjRepo -SjHome $SjHome

    # =====================================================================
    # HARNESS CONTROLS - if either fails, nothing below means anything
    # =====================================================================
    $SjBase = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the judgement harness control'
    # -ReviewOn is MANDATORY on DEPRIORITISED, so the harness control carries one. Without
    # it this call refuses at 95 and every row below fails for a reason that has nothing to
    # do with what it is testing.
    $SjHarness = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjBase, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewFuture, '-Detail', $SjDetailA, '-Path', $SjRepo)
    Add-Result 'HARNESS-CONTROL-judge-signal-succeeds' `
               ($SjHarness.Code -eq 0) `
               "exit $($SjHarness.Code); wanted 0 judging a freshly filed OPEN scratch signal"

    # The record must have landed under the SCRATCH home, not the real one. A fixture
    # whose USERPROFILE override silently failed would pass every row below while
    # writing into the live signal store.
    $SjBasePath = Get-SignalPath -SjHome $SjHome -SjId $SjBase
    $SjHomeFull = (Get-Item -LiteralPath $SjHome).FullName.TrimEnd('\', '/')
    Add-Result 'HARNESS-CONTROL-store-is-sandboxed' `
               ((Test-Path -LiteralPath $SjBasePath) -and $SjBasePath.StartsWith("$SjHomeFull\", [System.StringComparison]::OrdinalIgnoreCase)) `
               "record path '$SjBasePath' must exist and resolve inside the scratch home '$SjHomeFull'"

    # =====================================================================
    # P1 - the append lands, and the signal STAYS OPEN
    # =====================================================================
    $SjP1Rec  = Get-SignalRecord -SjHome $SjHome -SjId $SjBase
    $SjUnjudged = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal deliberately never judged'
    $SjP1Ctl  = Get-SignalRecord -SjHome $SjHome -SjId $SjUnjudged

    $SjP1CaseOk = (Test-HasKey $SjP1Rec 'judgements') -and ($SjP1Rec.state -eq 'OPEN') -and (@($SjP1Rec.judgements).Count -eq 1)
    $SjP1CtlOk  = (-not (Test-HasKey $SjP1Ctl 'judgements')) -and ($SjP1Ctl.state -eq 'OPEN')
    Add-Pair 'P1-append-onto-open-signal' `
        $SjP1CaseOk "judged record must carry exactly 1 judgement and still be OPEN; state=$($SjP1Rec.state)" `
        $SjP1CtlOk  "unjudged record must carry NO judgements key and still be OPEN; state=$($SjP1Ctl.state)" `
        ((Test-HasKey $SjP1Rec 'judgements') -ne (Test-HasKey $SjP1Ctl 'judgements')) `
        'the judged and unjudged records must differ on the judgements key'

    # =====================================================================
    # P2 - the rendered line, matched against the LITERAL the design specifies
    # =====================================================================
    $SjJAt = $SjP1Rec.judgements[0].at
    # The review suffix is part of the literal. It is APPENDED after the phase
    # and any scope suffix and before the colon, so everything left of it is unchanged - and
    # this row is what proves that, because it is an exact-equality match and not a substring.
    $SjWantLine = "      JUDGED DEPRIORITISED $SjJAt W1.1 review ${SjReviewFuture}: $SjDetailA"
    $SjList = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Path', $SjRepo)

    # The control is the unjudged signal's own row: it must appear in the same listing,
    # from the same command, with no JUDGED line anywhere attributable to it. Counting
    # JUDGED lines is what makes that checkable - exactly one judgement exists.
    $SjJudgedLines = @(@($SjList.Text -split "`n") | Where-Object { $_ -like "$SjJudgedLead*" })
    Add-Pair 'P2-rendered-literal' `
        (($SjList.Code -eq 0) -and (@($SjList.Text -split "`n") -contains $SjWantLine)) `
        "listing (exit $($SjList.Code)) must contain the literal: $SjWantLine" `
        ((@(@($SjList.Text -split "`n") | Where-Object { $_ -like "*$SjUnjudged*" }).Count -ge 1) -and ($SjJudgedLines.Count -eq 1)) `
        "the unjudged signal must appear in the same listing, and exactly 1 JUDGED line must exist in total; found $($SjJudgedLines.Count)" `
        ($SjJudgedLines.Count -eq 1) `
        'a listing carrying one judged and one unjudged signal must print exactly one JUDGED line'

    # The two legend lines ship with the trail or a reader cannot decode it. The control
    # is a legend line that does NOT exist - and it names LAPSED, a time-derived verdict the
    # design forbids, so if a LAPSED legend ever appears this row is the thing that says so.
    # Without it, a -like test that is vacuously true would pass for the wrong reason.
    Add-Pair 'P2b-legend-lines' `
        (($SjList.Text -like "*$SjLegendJudged*") -and ($SjList.Text -like "*$SjLegendVals*") -and ($SjList.Text -like "*$SjLegendReview*")) `
        'all three trail legend lines must appear beneath the existing four - the third is for the review date' `
        (-not ($SjList.Text -like '*LAPSED = *')) `
        'a legend line for a forbidden time-derived verdict must NOT appear' `
        (($SjList.Text -like "*$SjLegendJudged*") -ne ($SjList.Text -like '*LAPSED = *')) `
        'the same instrument must find one legend string and not the other, or it proves nothing'

    # =====================================================================
    # P3 - it APPENDS rather than replaces (the single re-wrap, exercised)
    # =====================================================================
    $SjP3 = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjBase, '-Phase', 'W1.1', '-As', 'CONFIRMED',
        '-Detail', $SjDetailB, '-Path', $SjRepo)
    $SjP3Rec = Get-SignalRecord -SjHome $SjHome -SjId $SjBase
    $SjP3Trail = @($SjP3Rec.judgements)
    Add-Pair 'P3-second-judgement-appends' `
        (($SjP3.Code -eq 0) -and ($SjP3Trail.Count -eq 2) -and ($SjP3Trail[1].as -eq 'CONFIRMED')) `
        "exit $($SjP3.Code); a second judgement must make 2 entries, the newest CONFIRMED; got $($SjP3Trail.Count)" `
        ($SjP3Trail[0].detail -eq $SjDetailA) `
        'the FIRST judgement must survive the second unaltered - a scalar field would have overwritten it' `
        ($SjP3Trail[0].as -ne $SjP3Trail[1].as) `
        'the two stored entries must differ, proving append and not replace'

    # =====================================================================
    # P4 - the enum READS the value (a sunset verdict is refused; a real one is not)
    # =====================================================================
    $SjP4Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjUnjudged, '-Phase', 'W1.1', '-As', 'LAPSED',
        '-Detail', 'a time-derived verdict must be unexpressible', '-Path', $SjRepo)
    $SjP4Ctl = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjUnjudged, '-Phase', 'W1.1', '-As', 'CONFIRMED',
        '-Detail', 'the same call with a legal verdict', '-Path', $SjRepo)
    Add-Pair 'P4-as-enum-is-selective' `
        ($SjP4Case.Code -eq 90) "exit $($SjP4Case.Code); -As LAPSED must be refused at 90 (no time-derived verdict)" `
        ($SjP4Ctl.Code -eq 0)   "exit $($SjP4Ctl.Code); -As CONFIRMED must succeed on the same signal and store" `
        ($SjP4Case.Code -ne $SjP4Ctl.Code) `
        'the enum must refuse one value and accept another - a refusal that refuses everybody reads no field'

    # =====================================================================
    # P5 - a missing -Phase refuses at 97, not 90 and not 95
    # =====================================================================
    $SjP5Sig  = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the phase refusals'
    $SjP5Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP5Sig, '-As', 'CONFIRMED', '-Detail', 'no phase supplied', '-Path', $SjRepo)
    $SjP5Ctl  = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP5Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED', '-Detail', 'phase supplied', '-Path', $SjRepo)
    Add-Pair 'P5-missing-phase-is-97' `
        ($SjP5Case.Code -eq 97) "exit $($SjP5Case.Code); a judgement with no author must refuse at 97, the code the 'signal' verb uses" `
        ($SjP5Ctl.Code -eq 0)   "exit $($SjP5Ctl.Code); the same call with -Phase must succeed" `
        ($SjP5Case.Code -ne $SjP5Ctl.Code) 'the refusal must turn on -Phase and nothing else'

    # =====================================================================
    # P6 - an UNDECLARED phase refuses at 94 (the phase is validated, not stored as text)
    # =====================================================================
    $SjP6Sig  = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the undeclared-phase refusal'
    $SjP6Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP6Sig, '-Phase', 'W9.9', '-As', 'CONFIRMED', '-Detail', 'undeclared phase', '-Path', $SjRepo)
    $SjP6Ctl  = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP6Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED', '-Detail', 'declared phase', '-Path', $SjRepo)
    Add-Pair 'P6-undeclared-phase-is-94' `
        ($SjP6Case.Code -eq 94) "exit $($SjP6Case.Code); an undeclared phase must refuse at 94" `
        ($SjP6Ctl.Code -eq 0)   "exit $($SjP6Ctl.Code); the declared phase must succeed on the same signal" `
        ($SjP6Case.Code -ne $SjP6Ctl.Code) 'the refusal must read the phase table, not refuse every phase'

    # =====================================================================
    # P7 - an id with no record refuses at 94
    # =====================================================================
    $SjP7Sig  = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the unknown-id refusal'
    $SjP7Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', 'S9999', '-Phase', 'W1.1', '-As', 'CONFIRMED', '-Detail', 'no such signal', '-Path', $SjRepo)
    $SjP7Ctl  = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP7Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED', '-Detail', 'a signal that exists', '-Path', $SjRepo)
    Add-Pair 'P7-unknown-id-is-94' `
        ($SjP7Case.Code -eq 94) "exit $($SjP7Case.Code); an id with no file in the store must refuse at 94" `
        ($SjP7Ctl.Code -eq 0)   "exit $($SjP7Ctl.Code); an id that does exist must succeed" `
        ($SjP7Case.Code -ne $SjP7Ctl.Code) 'the refusal must turn on the record existing'

    # =====================================================================
    # P8 - a record that parses to $null refuses at 96 (an empty file parses without throwing)
    # =====================================================================
    $SjP8Sig  = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the null-parse refusal'
    $SjP8Path = Get-SignalPath -SjHome $SjHome -SjId $SjP8Sig
    $SjP8Keep = Get-Content -Raw -LiteralPath $SjP8Path
    [System.IO.File]::WriteAllText($SjP8Path, '', (New-Object System.Text.UTF8Encoding($false)))
    $SjP8Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP8Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED', '-Detail', 'empty file', '-Path', $SjRepo)
    [System.IO.File]::WriteAllText($SjP8Path, $SjP8Keep, (New-Object System.Text.UTF8Encoding($false)))
    $SjP8Ctl = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP8Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED', '-Detail', 'file restored', '-Path', $SjRepo)
    Add-Pair 'P8-null-parse-is-96' `
        ($SjP8Case.Code -eq 96) "exit $($SjP8Case.Code); a zero-byte record must refuse at 96, not crash on a property access" `
        ($SjP8Ctl.Code -eq 0)   "exit $($SjP8Ctl.Code); the same id with its content restored must succeed" `
        ($SjP8Case.Code -ne $SjP8Ctl.Code) 'the refusal must turn on the file content, not on the id'

    # =====================================================================
    # P9 - a TERMINAL signal is refused at 90
    # =====================================================================
    $SjP9Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal resolved before judging'
    $SjP9Res = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'resolve-signal', '-Id', $SjP9Sig, '-As', 'REJECTED', '-Detail', 'scratch rejection', '-Path', $SjRepo)
    if ($SjP9Res.Code -ne 0) { throw "fixture resolve-signal failed (exit $($SjP9Res.Code)): $($SjP9Res.Text)" }
    $SjP9Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP9Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED', '-Detail', 'judging a terminal signal', '-Path', $SjRepo)
    $SjP9Open = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal left open'
    $SjP9Ctl  = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP9Open, '-Phase', 'W1.1', '-As', 'CONFIRMED', '-Detail', 'judging an open signal', '-Path', $SjRepo)
    Add-Pair 'P9-terminal-signal-is-90' `
        ($SjP9Case.Code -eq 90) "exit $($SjP9Case.Code); a signal with a terminal verdict must refuse at 90" `
        ($SjP9Ctl.Code -eq 0)   "exit $($SjP9Ctl.Code); an OPEN signal must be judged on the same store" `
        ($SjP9Case.Code -ne $SjP9Ctl.Code) 'the refusal must read the state, not refuse every signal'

    # =====================================================================
    # P10 - -Addresses is validated against the EXISTING constant
    # =====================================================================
    $SjP10Sig  = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the addresses refusal'
    $SjP10Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP10Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED',
        '-Detail', 'bad scope', '-Addresses', 'classwide', '-Path', $SjRepo)
    $SjP10Ctl = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP10Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED',
        '-Detail', 'good scope', '-Addresses', 'defect', '-Path', $SjRepo)
    $SjP10Rec = Get-SignalRecord -SjHome $SjHome -SjId $SjP10Sig
    Add-Pair 'P10-addresses-enum-is-selective' `
        ($SjP10Case.Code -eq 90) "exit $($SjP10Case.Code); a value outside defect|instance must refuse at 90" `
        (($SjP10Ctl.Code -eq 0) -and (Test-HasKey (@($SjP10Rec.judgements)[0]) 'addresses') -and ((@($SjP10Rec.judgements)[0]).addresses -eq 'defect')) `
        "exit $($SjP10Ctl.Code); -Addresses defect must succeed AND be stored on the entry" `
        ($SjP10Case.Code -ne $SjP10Ctl.Code) 'the refusal must read the value'

    # A judgement given no -Addresses must carry NO addresses key - the conditional write.
    # This is an ABSENCE claim, so its control is the same instrument, Test-HasKey, over a
    # judgement that DID supply -Addresses. Without that, a Test-HasKey that always
    # returned false would satisfy the case and prove nothing.
    Add-Pair 'P10b-addresses-omitted-writes-no-key' `
        (-not (Test-HasKey (@($SjP3Rec.judgements)[0]) 'addresses')) `
        'a judgement with no -Addresses must not carry an empty addresses key' `
        (Test-HasKey (@($SjP10Rec.judgements)[0]) 'addresses') `
        'the same instrument must FIND the key on a judgement that supplied -Addresses' `
        ((Test-HasKey (@($SjP3Rec.judgements)[0]) 'addresses') -ne (Test-HasKey (@($SjP10Rec.judgements)[0]) 'addresses')) `
        'the key must turn on whether -Addresses was supplied, not be absent from everything'

    # =====================================================================
    # P11 - resolve-signal PERSISTS the addresses answer
    # =====================================================================
    $SjP11Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal resolved as a defect fix'
    $SjP11Res = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'resolve-signal', '-Id', $SjP11Sig, '-As', 'PROMOTED', '-Addresses', 'defect',
        '-Detail', 'scratch promotion addressing the class', '-Path', $SjRepo)
    $SjP11Rec = Get-SignalRecord -SjHome $SjHome -SjId $SjP11Sig

    $SjP11CtlSig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal resolved as rejected'
    $SjP11CtlRes = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'resolve-signal', '-Id', $SjP11CtlSig, '-As', 'REJECTED', '-Detail', 'scratch rejection, no scope applies', '-Path', $SjRepo)
    $SjP11CtlRec = Get-SignalRecord -SjHome $SjHome -SjId $SjP11CtlSig

    Add-Pair 'P11-terminal-addresses-persisted' `
        (($SjP11Res.Code -eq 0) -and (Test-HasKey $SjP11Rec 'addresses') -and ($SjP11Rec.addresses -eq 'defect')) `
        "exit $($SjP11Res.Code); a PROMOTED -Addresses defect resolution must store addresses=defect" `
        (($SjP11CtlRes.Code -eq 0) -and (-not (Test-HasKey $SjP11CtlRec 'addresses'))) `
        "exit $($SjP11CtlRes.Code); a REJECTED resolution must store NO addresses key - an empty one is not a fact" `
        ((Test-HasKey $SjP11Rec 'addresses') -ne (Test-HasKey $SjP11CtlRec 'addresses')) `
        'the key must turn on the answer having been given'

    # And the listing must show the scope suffix on one and not the other. The
    # discrimination row compares the two terminal lines the fixture planted, computed
    # from the listing rather than asserted as a constant: exactly one of them may carry
    # a parenthesised scope. A hardcoded $true here would be a row that cannot fail,
    # which is the defect the third limb exists to catch.
    $SjList2 = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Path', $SjRepo)
    $SjLines2 = @($SjList2.Text -split "`n")
    $SjP11PromLine = @($SjLines2 | Where-Object { $_ -like '      PROMOTED*scratch promotion addressing the class' })
    $SjP11RejLine  = @($SjLines2 | Where-Object { $_ -like '      REJECTED*scratch rejection, no scope applies' })
    $SjP11PromHasScope = ($SjP11PromLine.Count -eq 1) -and ($SjP11PromLine[0] -like '*(defect)*')
    $SjP11RejHasScope  = ($SjP11RejLine.Count -eq 1)  -and ($SjP11RejLine[0]  -like '*(*')
    Add-Pair 'P11b-terminal-line-scope-suffix' `
        (($SjP11PromLine.Count -eq 1) -and ($SjLines2 -contains '      PROMOTED (defect): scratch promotion addressing the class')) `
        "the terminal line must carry the scope suffix where the record has one; found $($SjP11PromLine.Count) matching line(s)" `
        (($SjP11RejLine.Count -eq 1) -and ($SjLines2 -contains '      REJECTED: scratch rejection, no scope applies')) `
        "a record with no addresses key must print the terminal line exactly as it always did; found $($SjP11RejLine.Count) matching line(s)" `
        ($SjP11PromHasScope -and (-not $SjP11RejHasScope)) `
        'exactly one of the two planted terminal lines may carry a parenthesised scope - both or neither is a failure'

    # =====================================================================
    # P12 - the trail SURVIVES the terminal verdict
    # =====================================================================
    $SjP12Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal judged then resolved'
    $SjP12J = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP12Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewFuture, '-Detail', 'judged before being resolved', '-Path', $SjRepo)
    if ($SjP12J.Code -ne 0) { throw "fixture judge-signal failed (exit $($SjP12J.Code)): $($SjP12J.Text)" }
    $SjP12Rec = Get-SignalRecord -SjHome $SjHome -SjId $SjP12Sig
    $SjP12At  = @($SjP12Rec.judgements)[0].at
    $SjP12Res = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'resolve-signal', '-Id', $SjP12Sig, '-As', 'REJECTED', '-Detail', 'resolved after being judged', '-Path', $SjRepo)
    if ($SjP12Res.Code -ne 0) { throw "fixture resolve-signal failed (exit $($SjP12Res.Code)): $($SjP12Res.Text)" }

    # The control is P9's signal: resolved on the same store and NEVER judged. Both are
    # attributed by ROW rather than by searching the whole listing, because a JUDGED line
    # carries the JUDGEMENT's detail and never the resolution's - so a control that
    # searched JUDGED lines for a resolution's text could never match, and would report
    # the absence it was written to find whatever the wrapper did.
    $SjList3 = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Path', $SjRepo)
    $SjLines3 = @($SjList3.Text -split "`n")
    $SjP12Want = "      JUDGED DEPRIORITISED $SjP12At W1.1 review ${SjReviewFuture}: judged before being resolved"

    $SjP12Foll = @(Get-RowFollowers -SjLines $SjLines3 -SjId $SjP12Sig)
    $SjP9Foll  = @(Get-RowFollowers -SjLines $SjLines3 -SjId $SjP9Sig)
    $SjP12Judged = @($SjP12Foll | Where-Object { $_ -like "$SjJudgedLead*" }).Count
    $SjP9Judged  = @($SjP9Foll  | Where-Object { $_ -like "$SjJudgedLead*" }).Count

    Add-Pair 'P12-trail-survives-resolution' `
        (($SjP12Judged -eq 1) -and ($SjP12Foll -contains $SjP12Want) -and (@($SjP12Foll | Where-Object { $_ -like '      REJECTED:*' }).Count -eq 1)) `
        "a judgement made while the signal was open must still print after it resolves, above its terminal line; found $SjP12Judged JUDGED line(s) under row $SjP12Sig; followers=[$($SjP12Foll -join ' || ')]; wanted=[$SjP12Want]" `
        (($SjP9Foll.Count -ge 1) -and ($SjP9Judged -eq 0)) `
        "a signal resolved and never judged must print NO JUDGED line under its own row; found $($SjP9Foll.Count) continuation line(s), $SjP9Judged of them JUDGED" `
        ($SjP12Judged -ne $SjP9Judged) `
        'the two resolved signals must differ in how many JUDGED lines their rows carry - a global count could not tell them apart'

    # =====================================================================
    # P13 - DEPRIORITISED REQUIRES a return date; CONFIRMED does not
    #
    # The control is a SUCCESS from the same verb on the same store, because a refusal
    # that refuses everybody is indistinguishable from one that reads the field. It is
    # also the row that pins the ASYMMETRY: if -ReviewOn ever became mandatory on both
    # verdicts, the case would still pass and only this control would notice.
    # =====================================================================
    $SjP13Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the missing-date refusal'
    $SjP13Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP13Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-Detail', 'deprioritised with no return date', '-Path', $SjRepo)
    $SjP13Ctl = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP13Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED',
        '-Detail', 'confirmed with no return date', '-Path', $SjRepo)
    Add-Pair 'P13-deprioritised-needs-date' `
        ($SjP13Case.Code -eq 95) `
        "a DEPRIORITISED judgement with no -ReviewOn must refuse at 95; got $($SjP13Case.Code): $($SjP13Case.Text)" `
        ($SjP13Ctl.Code -eq 0) `
        "the SAME verb on the SAME signal must SUCCEED for CONFIRMED with no date; got $($SjP13Ctl.Code): $($SjP13Ctl.Text)" `
        ($SjP13Case.Code -ne $SjP13Ctl.Code) `
        'the two verdicts must be treated differently, or the refusal is not reading -As at all'

    # =====================================================================
    # P14 - the same verdict SUCCEEDS once a date is supplied
    #
    # P13 proves a refusal happens. This proves the refusal is about the DATE and not
    # about the verdict: same verb, same store, same DEPRIORITISED, one flag apart.
    # =====================================================================
    $SjP14Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the dated deprioritisation'
    $SjP14Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP14Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewFuture, '-Detail', 'deprioritised with a return date', '-Path', $SjRepo)
    $SjP14Ctl = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP14Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-Detail', 'deprioritised with a return date', '-Path', $SjRepo)
    Add-Pair 'P14-dated-deprioritisation-succeeds' `
        ($SjP14Case.Code -eq 0) `
        "a DEPRIORITISED judgement WITH -ReviewOn must succeed; got $($SjP14Case.Code): $($SjP14Case.Text)" `
        ($SjP14Ctl.Code -eq 95) `
        "the identical call WITHOUT the date must refuse at 95; got $($SjP14Ctl.Code)" `
        ($SjP14Case.Code -ne $SjP14Ctl.Code) `
        'one flag must be the whole difference between the two, or the refusal is reading something else'

    # =====================================================================
    # P15 - a malformed date is refused at 90, by Assert-Date, on EITHER verdict
    #
    # The value used is well-formed by SHAPE and impossible as a date, so it reaches
    # Assert-Date's ParseExact branch rather than its regex branch. 90 and not 95: a
    # supplied-but-wrong answer is not a missing one, and the two codes must not merge.
    # =====================================================================
    $SjP15Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the malformed-date refusal'
    $SjP15Case = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP15Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewBad, '-Detail', 'deprioritised with an impossible date', '-Path', $SjRepo)
    $SjP15Ctl = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP15Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewFuture, '-Detail', 'deprioritised with a real date', '-Path', $SjRepo)
    Add-Pair 'P15-malformed-date-refused' `
        ($SjP15Case.Code -eq 90) `
        "an impossible -ReviewOn must refuse at 90 via Assert-Date; got $($SjP15Case.Code): $($SjP15Case.Text)" `
        ($SjP15Ctl.Code -eq 0) `
        "a REAL date on the identical call must succeed; got $($SjP15Ctl.Code): $($SjP15Ctl.Text)" `
        ($SjP15Case.Code -ne $SjP15Ctl.Code) `
        'the date VALUE must be what decides, not the presence of the flag'

    # =====================================================================
    # P16 - the key is STORED, with the value passed, and absent when none was
    #
    # Decided by parsing the record field by field rather than by reading the listing,
    # because the listing is a rendering and this row is about what the store holds.
    # The control is a judgement written WITHOUT a date on the same store, so the
    # assertion is about the change and not about the parser.
    # =====================================================================
    $SjP16Rec  = Get-SignalRecord -SjHome $SjHome -SjId $SjP14Sig
    $SjP16Last = @($SjP16Rec.judgements)[-1]
    $SjP16CtlRec  = Get-SignalRecord -SjHome $SjHome -SjId $SjP13Sig
    $SjP16CtlLast = @($SjP16CtlRec.judgements)[-1]
    Add-Pair 'P16-reviewon-key-stored' `
        ((Test-HasKey $SjP16Last 'reviewOn') -and ($SjP16Last.reviewOn -eq $SjReviewFuture)) `
        "the stored judgement must carry reviewOn = $SjReviewFuture; hasKey=$(Test-HasKey $SjP16Last 'reviewOn')" `
        (-not (Test-HasKey $SjP16CtlLast 'reviewOn')) `
        'a judgement written with no date must carry NO reviewOn key - absent, not empty' `
        ((Test-HasKey $SjP16Last 'reviewOn') -ne (Test-HasKey $SjP16CtlLast 'reviewOn')) `
        'the dated and undated judgements must differ on the key itself'

    # =====================================================================
    # P17 - CONFIRMED PERMITS a date, and stores it when given one
    #
    # The date is optional here by design rather than refused, and this is the row that
    # holds that open. Its control is the same verb storing NO key when none is given.
    # =====================================================================
    $SjP17Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the optional date on CONFIRMED'
    $SjP17J = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP17Sig, '-Phase', 'W1.1', '-As', 'CONFIRMED',
        '-ReviewOn', $SjReviewFuture, '-Detail', 'confirmed and scheduled', '-Path', $SjRepo)
    $SjP17Rec  = Get-SignalRecord -SjHome $SjHome -SjId $SjP17Sig
    $SjP17Last = @($SjP17Rec.judgements)[-1]
    Add-Pair 'P17-confirmed-date-optional' `
        (($SjP17J.Code -eq 0) -and (Test-HasKey $SjP17Last 'reviewOn') -and ($SjP17Last.reviewOn -eq $SjReviewFuture)) `
        "CONFIRMED must ACCEPT a date and store it; exit $($SjP17J.Code), hasKey=$(Test-HasKey $SjP17Last 'reviewOn')" `
        ((-not (Test-HasKey $SjP16CtlLast 'reviewOn')) -and ($SjP16CtlLast.as -eq 'CONFIRMED')) `
        'a CONFIRMED judgement given no date must succeed and store no key - the date is permitted, never required' `
        ((Test-HasKey $SjP17Last 'reviewOn') -ne (Test-HasKey $SjP16CtlLast 'reviewOn')) `
        'the two CONFIRMED judgements must differ on the key, or the optionality is not real'

    # =====================================================================
    # P26's CONTROL READING, taken HERE and not beside the case
    #
    # This is the last point in the fixture holding no past-dated judgement, so the true due
    # count is 0 - which is what makes it a control. A hook whose parse broke also prints no
    # due suffix, so this reading only discriminates when set against P26's case, taken at
    # the end of the fixture where the true count is at least 1. Nothing here writes to the
    # store.
    # =====================================================================
    $SjHookCtlOut   = Invoke-Hook -SjHome $SjHome
    $SjHookCtlBrief = (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text

    # =====================================================================
    # P18 - a date that has ARRIVED surfaces; one in the future does not
    #
    # This is the row that tests the DATE COMPARISON rather than merely that a line
    # printed. Attributed BY ROW with Get-RowFollowers, never against the joined
    # listing: the legend and the counts line both carry the literal DUE, so a
    # joined-string search would be true whatever any row rendered - the case could
    # not fail and the control could not pass.
    # =====================================================================
    $SjP18Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal whose review date has arrived'
    $SjP18J = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP18Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewPast, '-Detail', 'deprioritised and now due', '-Path', $SjRepo)
    if ($SjP18J.Code -ne 0) { throw "fixture judge-signal (past date) failed (exit $($SjP18J.Code)): $($SjP18J.Text)" }

    $SjList4  = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Path', $SjRepo)
    $SjLines4 = @($SjList4.Text -split "`n")
    $SjP18Foll = @(Get-RowFollowers -SjLines $SjLines4 -SjId $SjP18Sig)
    $SjP14Foll = @(Get-RowFollowers -SjLines $SjLines4 -SjId $SjP14Sig)
    $SjP18Due  = @($SjP18Foll | Where-Object { $_ -like "*review $SjReviewPast DUE*" }).Count
    $SjP14Due  = @($SjP14Foll | Where-Object { $_ -like '*DUE*' }).Count
    Add-Pair 'P18-arrived-date-surfaces' `
        (($SjP18Due -eq 1) -and (@($SjP18Foll | Where-Object { $_ -like "$SjJudgedLead*" }).Count -eq 1)) `
        "a judgement whose date has passed must render 'review $SjReviewPast DUE' on its OWN row; found $SjP18Due; followers=[$($SjP18Foll -join ' || ')]" `
        (($SjP14Foll.Count -ge 1) -and ($SjP14Due -eq 0)) `
        "a judgement dated $SjReviewFuture must render NO DUE on its own row; found $SjP14Due DUE marker(s) in $($SjP14Foll.Count) continuation line(s)" `
        ($SjP18Due -ne $SjP14Due) `
        'a past and a future date must render differently, or the row ignores the date entirely'

    # =====================================================================
    # P19 - a DEPRIORITISED judgement with NO date reads UNSCHEDULED
    #
    # Judgements written before the review date existed are exactly this shape, and the
    # design reads them as unscheduled rather than as due - so this row is what stops a
    # later change quietly reclassifying them. Row-attributed for the same reason as P18.
    #
    # THE CASE ASSERTS PRESENCE, NOT ABSENCE, and that is the whole point of the planting
    # step. With absence on both limbs, deleting the UNSCHEDULED marker from the wrapper
    # outright leaves the pair green. A marker no row demands to SEE is a marker no row
    # protects.
    # =====================================================================
    $SjP19Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal shaped like the eighteen that predate the field'
    $SjP19J = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP19Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewFuture, '-Detail', 'deprioritised, date about to be stripped', '-Path', $SjRepo)
    if ($SjP19J.Code -ne 0) { throw "fixture judge-signal (P19) failed (exit $($SjP19J.Code)): $($SjP19J.Text)" }
    Remove-StoredReviewOn -SjHome $SjHome -SjId $SjP19Sig

    $SjList5  = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Path', $SjRepo)
    $SjLines5 = @($SjList5.Text -split "`n")
    $SjP19Foll  = @(Get-RowFollowers -SjLines $SjLines5 -SjId $SjP19Sig)
    $SjP19Unsch = @($SjP19Foll | Where-Object { $_ -like '* UNSCHEDULED:*' }).Count
    $SjP14Foll5 = @(Get-RowFollowers -SjLines $SjLines5 -SjId $SjP14Sig)
    $SjP14Unsch = @($SjP14Foll5 | Where-Object { $_ -like '* UNSCHEDULED:*' }).Count
    Add-Pair 'P19-undated-deprioritisation-reads-unscheduled' `
        ($SjP19Unsch -eq 1) `
        "a DEPRIORITISED judgement with its date stripped must render UNSCHEDULED on its OWN row; found $SjP19Unsch; followers=[$($SjP19Foll -join ' || ')]" `
        (($SjP14Foll5.Count -ge 1) -and ($SjP14Unsch -eq 0)) `
        "a DEPRIORITISED judgement that KEPT its date must not render UNSCHEDULED; found $SjP14Unsch in $($SjP14Foll5.Count) continuation line(s)" `
        ($SjP19Unsch -ne $SjP14Unsch) `
        'the dated and the stripped judgement must render differently, or the marker is not reading the field'

    # =====================================================================
    # P21 - the two COUNTS track the store, and are not decoration
    #
    # Measured as a DELTA across one known act rather than as an absolute, so the row does
    # not have to know the whole fixture's composition and cannot rot as cases are added
    # above it. Planting one undated deprioritisation must move 'unscheduled' by exactly
    # one and leave 'due' where it was.
    #
    # WHY THIS EXISTS: with no row asserting a VALUE, replacing BOTH counts with the literal
    # string '0 ... ; 0 ...' leaves the suite green - and one of these two numbers is the one
    # scripts/keel-session-start.ps1 parses out of this same line, so the arithmetic behind
    # the operator's nudge would be unguarded. Get-ReviewCounts reads it with a pattern that
    # begins with the hook's and extends it.
    # =====================================================================
    $SjCountsBefore = Get-ReviewCounts -SjText (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text
    $SjP21Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the unscheduled count delta'
    $SjP21J = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP21Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewFuture, '-Detail', 'deprioritised for the count delta', '-Path', $SjRepo)
    if ($SjP21J.Code -ne 0) { throw "fixture judge-signal (P21) failed (exit $($SjP21J.Code)): $($SjP21J.Text)" }
    Remove-StoredReviewOn -SjHome $SjHome -SjId $SjP21Sig
    $SjCountsAfter = Get-ReviewCounts -SjText (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text

    Add-Pair 'P21-counts-track-the-store' `
        (($SjCountsBefore.Unscheduled -ge 0) -and ($SjCountsAfter.Unscheduled -eq ($SjCountsBefore.Unscheduled + 1))) `
        "planting ONE undated deprioritisation must raise the unscheduled count by exactly 1; before=$($SjCountsBefore.Unscheduled) after=$($SjCountsAfter.Unscheduled)" `
        ($SjCountsAfter.Due -eq $SjCountsBefore.Due) `
        "the same act must leave the DUE count untouched - it is a different question; before=$($SjCountsBefore.Due) after=$($SjCountsAfter.Due)" `
        (($SjCountsAfter.Unscheduled - $SjCountsBefore.Unscheduled) -ne ($SjCountsAfter.Due - $SjCountsBefore.Due)) `
        'the two counts must move differently under one act, or they are not counting two different things'

    # And the DUE count must move on its own act, for the same reason. A past date is the
    # only thing that can raise it, and this is the number the session-start nudge prints.
    $SjP22Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal for the due count delta'
    $SjP22J = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP22Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewPast, '-Detail', 'deprioritised and already due', '-Path', $SjRepo)
    if ($SjP22J.Code -ne 0) { throw "fixture judge-signal (P22) failed (exit $($SjP22J.Code)): $($SjP22J.Text)" }
    $SjCountsDue = Get-ReviewCounts -SjText (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text

    Add-Pair 'P22-due-count-tracks-the-store' `
        ($SjCountsDue.Due -eq ($SjCountsAfter.Due + 1)) `
        "judging one signal with a PAST date must raise the due count by exactly 1; before=$($SjCountsAfter.Due) after=$($SjCountsDue.Due)" `
        ($SjCountsDue.Unscheduled -eq $SjCountsAfter.Unscheduled) `
        "that same act must leave the unscheduled count untouched; before=$($SjCountsAfter.Unscheduled) after=$($SjCountsDue.Unscheduled)" `
        (($SjCountsDue.Due - $SjCountsAfter.Due) -ne ($SjCountsDue.Unscheduled - $SjCountsAfter.Unscheduled)) `
        'a past-dated judgement must move due and not unscheduled, or the two states are the same state'

    # =====================================================================
    # P23 - the counts print in ALL THREE modes, with the same numbers
    #
    # WHY THIS EXISTS: if every count row reads 'signals -Brief', deleting the counts line
    # from the -Cluster branch, or from the full listing, leaves the suite green, and the
    # arithmetic is proved only through the machine-readable face.
    #
    # -Cluster IS THE MODE THAT MATTERS, and that is the whole reason the line is in all
    # three: it is the command scripts/keel-session-start.ps1 NAMES in its nudge. An
    # operator told that N deferrals are due follows that instruction and lands in the one
    # listing that could then show neither the count nor a single UNSCHEDULED marker. A
    # defect there is invisible to a reader, and to a suite that reads only -Brief.
    #
    # THE CONTROL VARIES THE MODE, not the store: the same three commands on the same store
    # must differ in how many JUDGED rows they print - the full listing has them, -Cluster
    # and -Brief do not. Without it, three identical readings would also be produced by a
    # verb that ignored the switches entirely.
    # =====================================================================
    $SjFullTxt = (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Path', $SjRepo)).Text
    $SjClusTxt = (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Cluster', '-Path', $SjRepo)).Text
    $SjBrfTxt  = (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text

    $SjCFull = Get-ReviewCounts -SjText $SjFullTxt
    $SjCClus = Get-ReviewCounts -SjText $SjClusTxt
    $SjCBrf  = Get-ReviewCounts -SjText $SjBrfTxt

    $SjJudgedFull = @(@($SjFullTxt -split "`n") | Where-Object { $_ -like "$SjJudgedLead*" }).Count
    $SjJudgedClus = @(@($SjClusTxt -split "`n") | Where-Object { $_ -like "$SjJudgedLead*" }).Count
    $SjJudgedBrf  = @(@($SjBrfTxt  -split "`n") | Where-Object { $_ -like "$SjJudgedLead*" }).Count

    Add-Pair 'P23-counts-in-every-mode' `
        (($SjCFull.Due -ge 0) -and ($SjCClus.Due -ge 0) -and ($SjCBrf.Due -ge 0) -and
         ($SjCFull.Due -eq $SjCClus.Due) -and ($SjCFull.Due -eq $SjCBrf.Due) -and
         ($SjCFull.Unscheduled -eq $SjCClus.Unscheduled) -and ($SjCFull.Unscheduled -eq $SjCBrf.Unscheduled)) `
        "all three modes must carry the counts line with the SAME numbers; full=$($SjCFull.Due)/$($SjCFull.Unscheduled) cluster=$($SjCClus.Due)/$($SjCClus.Unscheduled) brief=$($SjCBrf.Due)/$($SjCBrf.Unscheduled) (-1 means the line was absent)" `
        (($SjJudgedFull -ge 1) -and ($SjJudgedClus -eq 0) -and ($SjJudgedBrf -eq 0)) `
        "the three modes must really be three modes: only the full listing prints JUDGED rows; full=$SjJudgedFull cluster=$SjJudgedClus brief=$SjJudgedBrf" `
        ($SjJudgedFull -ne $SjJudgedClus) `
        'the counts must agree across modes while the ROWS do not, or the switches are being ignored'

    # =====================================================================
    # P20 - -Brief prints the counts and NO rows
    #
    # This is the face scripts/keel-session-start.ps1 reads, and the reason it may be
    # run in every session in this repo: the full listing is hundreds of lines and the
    # hook needs two numbers. The control is the SAME command without -Brief on the
    # SAME store, which must print rows - so the row asserts suppression rather than
    # an empty store.
    # =====================================================================
    $SjBriefOut = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)
    $SjBriefRows = @(@($SjBriefOut.Text -split "`n") | Where-Object { $_ -match '^[!*< ]S\d{4}\b' }).Count
    $SjFullRows  = @($SjLines4 | Where-Object { $_ -match '^[!*< ]S\d{4}\b' }).Count
    $SjBriefHasCounts = ($SjBriefOut.Text -like '*deprioritised signal(s) DUE for review*')
    Add-Pair 'P20-brief-suppresses-rows' `
        (($SjBriefOut.Code -eq 0) -and ($SjBriefRows -eq 0) -and $SjBriefHasCounts) `
        "signals -Brief must exit 0, print the counts line and NO signal rows; exit $($SjBriefOut.Code), rows=$SjBriefRows, counts=$SjBriefHasCounts" `
        ($SjFullRows -ge 1) `
        "the same command WITHOUT -Brief on the same store must print rows; found $SjFullRows" `
        ($SjBriefRows -ne $SjFullRows) `
        'the two modes must differ in row count, or -Brief is suppressing nothing'

    # =====================================================================
    # P24 - the date comparison is INCLUSIVE: a review date of TODAY is due
    #
    # Every other past-date row uses 2020-01-01, so a '-le' in Get-ReviewState regressed to
    # '-lt' would delay every signal by one day and leave all of them green. That regression
    # fails this pair's case and discrimination rows.
    #
    # TODAY AND TOMORROW ARE COMPUTED AT RUN TIME, the one exception to the fixed-literal
    # rule above, and in the form the wrapper computes its own today (yyyy-MM-dd, local
    # date). A run that straddles midnight between the judge calls and the listing would
    # turn the control's tomorrow into today and fail the control; that is the cost of
    # testing a boundary that moves daily, and it is confined to this pair - the control
    # signal is resolved below, so no open signal dated tomorrow survives into P25 or P26.
    # =====================================================================
    $SjToday    = (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    $SjTomorrow = (Get-Date).AddDays(1).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)

    $SjP24Sig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal whose review date is today'
    $SjP24J = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP24Sig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjToday, '-Detail', 'deprioritised until today', '-Path', $SjRepo)
    if ($SjP24J.Code -ne 0) { throw "fixture judge-signal (P24 today) failed (exit $($SjP24J.Code)): $($SjP24J.Text)" }
    $SjP24CtlSig = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal whose review date is tomorrow'
    $SjP24CtlJ = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP24CtlSig, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjTomorrow, '-Detail', 'deprioritised until tomorrow', '-Path', $SjRepo)
    if ($SjP24CtlJ.Code -ne 0) { throw "fixture judge-signal (P24 tomorrow) failed (exit $($SjP24CtlJ.Code)): $($SjP24CtlJ.Text)" }

    $SjLines6     = @((Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Path', $SjRepo)).Text -split "`n")
    $SjP24Foll    = @(Get-RowFollowers -SjLines $SjLines6 -SjId $SjP24Sig)
    $SjP24CtlFoll = @(Get-RowFollowers -SjLines $SjLines6 -SjId $SjP24CtlSig)
    $SjP24Due     = @($SjP24Foll    | Where-Object { $_ -like "*review $SjToday DUE*" }).Count
    $SjP24CtlDue  = @($SjP24CtlFoll | Where-Object { $_ -like '*DUE*' }).Count

    # Resolved NOW, locally - no -CloseIssue, so no network, the same call P9 makes - so that
    # a run crossing midnight cannot turn this signal due underneath P25's deltas or between
    # P26's two readings. A terminal signal is outside both counts.
    $SjP24Res = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'resolve-signal', '-Id', $SjP24CtlSig, '-As', 'REJECTED', '-Detail', 'P24 control retired', '-Path', $SjRepo)
    if ($SjP24Res.Code -ne 0) { throw "fixture resolve-signal (P24 control) failed (exit $($SjP24Res.Code)): $($SjP24Res.Text)" }

    Add-Pair 'P24-date-boundary-is-inclusive' `
        (($SjP24Due -eq 1) -and (@($SjP24Foll | Where-Object { $_ -like "$SjJudgedLead*" }).Count -eq 1)) `
        "a judgement dated TODAY ($SjToday) must render 'review $SjToday DUE' on its own row; found $SjP24Due; followers=[$($SjP24Foll -join ' || ')]" `
        (($SjP24CtlFoll.Count -ge 1) -and ($SjP24CtlDue -eq 0)) `
        "a judgement dated TOMORROW ($SjTomorrow) must render NO DUE on its own row; found $SjP24CtlDue in $($SjP24CtlFoll.Count) continuation line(s)" `
        ($SjP24Due -ne $SjP24CtlDue) `
        'today and tomorrow must render differently, or the comparison is not inclusive at the boundary'

    # =====================================================================
    # P25 - the per-signal count reads the LAST judgement, not the first
    #
    # Every other fixture signal carrying two judgements reads the same state on both
    # entries, so Get-SignalReviewState's $jgs[$jgs.Count - 1] replaced by $jgs[0] would
    # leave all of them green. Here the two entries of each trail read DIFFERENTLY, and the
    # two signals run in opposite orders.
    #
    # THE CONTROL REVERSES THE ORDER, holding the verb, the store and both dates fixed: X goes
    # future-then-past and must raise the due count by one; Y goes past-then-future and must
    # lower it by one. Reading the first judgement makes both deltas zero, and all three rows
    # fail. Both dates are the fixed literals, so midnight cannot move either.
    # =====================================================================
    $SjP25X = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal judged future then past'
    $SjP25XJ1 = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP25X, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewFuture, '-Detail', 'first judgement, future date', '-Path', $SjRepo)
    if ($SjP25XJ1.Code -ne 0) { throw "fixture judge-signal (P25 X first) failed (exit $($SjP25XJ1.Code)): $($SjP25XJ1.Text)" }
    $SjP25CA = Get-ReviewCounts -SjText (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text
    $SjP25XJ2 = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP25X, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewPast, '-Detail', 'second judgement, past date', '-Path', $SjRepo)
    if ($SjP25XJ2.Code -ne 0) { throw "fixture judge-signal (P25 X second) failed (exit $($SjP25XJ2.Code)): $($SjP25XJ2.Text)" }
    $SjP25CB   = Get-ReviewCounts -SjText (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text
    $SjP25XRec = Get-SignalRecord -SjHome $SjHome -SjId $SjP25X

    $SjP25Y = New-Signal -SjRepo $SjRepo -SjHome $SjHome -SjDetail 'scratch signal judged past then future'
    $SjP25YJ1 = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP25Y, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewPast, '-Detail', 'first judgement, past date', '-Path', $SjRepo)
    if ($SjP25YJ1.Code -ne 0) { throw "fixture judge-signal (P25 Y first) failed (exit $($SjP25YJ1.Code)): $($SjP25YJ1.Text)" }
    $SjP25CC = Get-ReviewCounts -SjText (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text
    $SjP25YJ2 = Invoke-Wrapper -SjHome $SjHome -SjArgs @(
        'judge-signal', '-Id', $SjP25Y, '-Phase', 'W1.1', '-As', 'DEPRIORITISED',
        '-ReviewOn', $SjReviewFuture, '-Detail', 'second judgement, future date', '-Path', $SjRepo)
    if ($SjP25YJ2.Code -ne 0) { throw "fixture judge-signal (P25 Y second) failed (exit $($SjP25YJ2.Code)): $($SjP25YJ2.Text)" }
    $SjP25CD = Get-ReviewCounts -SjText (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text

    $SjP25DeltaX = $SjP25CB.Due - $SjP25CA.Due
    $SjP25DeltaY = $SjP25CD.Due - $SjP25CC.Due
    Add-Pair 'P25-count-reads-last-judgement' `
        (($SjP25CA.Due -ge 0) -and ($SjP25DeltaX -eq 1) -and (@($SjP25XRec.judgements).Count -eq 2)) `
        "re-judging a future-dated deferral with a PAST date must raise the due count by exactly 1; before=$($SjP25CA.Due) after=$($SjP25CB.Due), trail=$(@($SjP25XRec.judgements).Count)" `
        (($SjP25CC.Due -ge 0) -and ($SjP25DeltaY -eq -1)) `
        "re-judging a past-dated deferral with a FUTURE date must lower the due count by exactly 1; before=$($SjP25CC.Due) after=$($SjP25CD.Due)" `
        ($SjP25DeltaX -ne $SjP25DeltaY) `
        'the two orders must move the count in opposite directions, or the count is not reading the last judgement'

    # =====================================================================
    # P26 - the session-start hook still PARSES the wrapper's counts line
    #
    # The hook is RUN (Invoke-Hook), not imitated, so a change to its own pattern in
    # scripts/keel-session-start.ps1 fails here, and so does a change to the wrapper's
    # wording that the hook's pattern stops matching - the two sides of the one coupling.
    # 'deprioritised' spelled 'deprioritized' in the hook's pattern fails this pair's case
    # and discrimination rows; the control still passes.
    #
    # THE CONTROL IS THE READING TAKEN BEFORE P18, where the true due count is 0 and the hook
    # must print its open line with no due suffix. Against it, the case demands the hook
    # print the wrapper's non-zero number. Both readings also check the hook's OPEN number
    # against the wrapper's, which is the hook's other parse.
    # =====================================================================
    $SjHookOut   = Invoke-Hook -SjHome $SjHome
    $SjHookBrief = (Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Brief', '-Path', $SjRepo)).Text
    $SjHookC     = Get-HookCounts -SjText $SjHookOut.Text
    $SjHookW     = Get-ReviewCounts -SjText $SjHookBrief
    $SjHookWOpen = Get-BriefOpen -SjText $SjHookBrief

    $SjHookCtlC     = Get-HookCounts -SjText $SjHookCtlOut.Text
    $SjHookCtlW     = Get-ReviewCounts -SjText $SjHookCtlBrief
    $SjHookCtlWOpen = Get-BriefOpen -SjText $SjHookCtlBrief

    Add-Pair 'P26-hook-parses-the-due-count' `
        (($SjHookOut.Code -eq 0) -and ($SjHookW.Due -ge 1) -and ($SjHookC.Due -eq $SjHookW.Due) -and ($SjHookC.Open -ge 1) -and ($SjHookC.Open -eq $SjHookWOpen)) `
        "the hook must print the wrapper's due count ($($SjHookW.Due), at least 1) and open count ($SjHookWOpen); it printed due=$($SjHookC.Due) open=$($SjHookC.Open), exit $($SjHookOut.Code); output=[$($SjHookOut.Text)]" `
        (($SjHookCtlOut.Code -eq 0) -and ($SjHookCtlW.Due -eq 0) -and ($SjHookCtlC.Due -eq 0) -and ($SjHookCtlC.Open -ge 1) -and ($SjHookCtlC.Open -eq $SjHookCtlWOpen)) `
        "before any past date the wrapper's due count must be 0 and the hook must print its open line ($SjHookCtlWOpen) with no due suffix; wrapper due=$($SjHookCtlW.Due), hook due=$($SjHookCtlC.Due) open=$($SjHookCtlC.Open); output=[$($SjHookCtlOut.Text)]" `
        ($SjHookC.Due -ne $SjHookCtlC.Due) `
        'the hook must print different due numbers when the store holds different due counts, or it is not parsing the line'

    # =====================================================================
    # P27 - signals -Id SCOPES the listing to the one signal
    #
    # The control is the same verb on the same store with no -Id, which must print more than
    # one row - so the case asserts a filter rather than a store that happens to hold one
    # signal. Against a wrapper that ignores -Id, the case fails.
    # =====================================================================
    $SjP27Out     = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Id', $SjBase, '-Path', $SjRepo)
    $SjP27Rows    = @(@($SjP27Out.Text -split "`n") | Where-Object { $_ -match '^[!*< ]S\d{4}\b' })
    $SjP27All     = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Path', $SjRepo)
    $SjP27AllRows = @(@($SjP27All.Text -split "`n") | Where-Object { $_ -match '^[!*< ]S\d{4}\b' })
    Add-Pair 'P27-id-scopes-the-listing' `
        (($SjP27Out.Code -eq 0) -and ($SjP27Rows.Count -eq 1) -and ($SjP27Rows[0] -like "*$SjBase*")) `
        "signals -Id $SjBase must exit 0 and print exactly that one signal row; exit $($SjP27Out.Code), rows=$($SjP27Rows.Count)" `
        (($SjP27All.Code -eq 0) -and ($SjP27AllRows.Count -ge 2)) `
        "the same verb with no -Id on the same store must print more than one row; found $($SjP27AllRows.Count)" `
        ($SjP27Rows.Count -ne $SjP27AllRows.Count) `
        'the two calls must differ in row count, or -Id is being ignored'

    # =====================================================================
    # P28 - signals -Id REFUSES what is not a signal id, and what has no record
    #
    # The codes and messages mirror signals-push -Id: bad shape at 90, unknown id at 94.
    # The control is P27's SUCCESS from the same verb on the same store with a real id, so
    # the refusals are shown to read the value rather than refuse every -Id.
    # =====================================================================
    $SjP28Bad  = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Id', 'NOTANID', '-Path', $SjRepo)
    $SjP28None = Invoke-Wrapper -SjHome $SjHome -SjArgs @('signals', '-Id', 'S9999', '-Path', $SjRepo)
    Add-Pair 'P28-id-is-validated' `
        (($SjP28Bad.Code -eq 90) -and ($SjP28None.Code -eq 94)) `
        "signals -Id NOTANID must refuse at 90 and -Id S9999 at 94; got $($SjP28Bad.Code) and $($SjP28None.Code)" `
        ($SjP27Out.Code -eq 0) `
        "signals -Id with a real id on the same store must succeed; got $($SjP27Out.Code)" `
        (($SjP28Bad.Code -ne $SjP27Out.Code) -and ($SjP28None.Code -ne $SjP27Out.Code)) `
        'both refusals must differ from the success, or the verb refuses every -Id'
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
$SjTempBase = [System.IO.Path]::GetTempPath()
$SjTempRoot = Join-Path $SjTempBase ("keel-judgement-suite-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 12))

# The scratch home must resolve INSIDE the system temp directory before anything is
# written. A fixture built under the wrong root would file signals into the real store
# and resolve them there - and every row below would still be green, because the rows
# assert what the wrapper did and not where it did it. This is the rule
# test-quarantine.ps1 already enforces, applied to the store it protects.
$SjTempBaseFull = (Get-Item -LiteralPath $SjTempBase).FullName.TrimEnd('\', '/')
New-Item -ItemType Directory -Path $SjTempRoot -Force | Out-Null
$SjTempRootFull = (Get-Item -LiteralPath $SjTempRoot).FullName.TrimEnd('\', '/')
if (-not $SjTempRootFull.StartsWith("$SjTempBaseFull$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine("test-signal-judgement: refusing to run - scratch root '$SjTempRootFull' does not resolve inside '$SjTempBaseFull'.")
    exit 1
}

$SjFailed = 0
$SjHarnessOk = $false
$SjSandboxOk = $false
try {
    Invoke-Cases -SjTempRoot $SjTempRoot

    foreach ($SjResult in @($script:SjResults)) {
        if (-not $SjResult.Ok) {
            $SjFailed++
            Write-Output ("  FAIL  {0,-46} {1}" -f $SjResult.Name, $SjResult.Why)
        }
        if ($SjResult.Name -eq 'HARNESS-CONTROL-judge-signal-succeeds') { $SjHarnessOk = $SjResult.Ok }
        if ($SjResult.Name -eq 'HARNESS-CONTROL-store-is-sandboxed')    { $SjSandboxOk = $SjResult.Ok }
    }

    if ($SjHarnessOk -ne $true) {
        Write-Output ''
        Write-Output '  HARNESS CONTROL FAILED: judge-signal did not succeed on a freshly filed OPEN scratch signal.'
        Write-Output '  The suite is not reaching the mechanism. No other row in this run means anything.'
    }
    if ($SjSandboxOk -ne $true) {
        Write-Output ''
        Write-Output '  HARNESS CONTROL FAILED: the scratch store did not resolve inside the temp scratch home.'
        Write-Output '  Rows below may have been measured against the REAL signal store.'
    }

    Write-Output ("  {0} case(s), {1} failure(s)." -f @($script:SjResults).Count, $SjFailed)
}
finally {
    # Best effort. A leftover fixture under TEMP is noise; a failure to remove it is not a
    # reason to report a green suite as red.
    if (Test-Path -LiteralPath $SjTempRoot) {
        try { Remove-Item -LiteralPath $SjTempRoot -Recurse -Force -ErrorAction Stop } catch { }
    }
}

Write-Output ''
Write-Output ("test-signal-judgement: {0} case(s), {1} failure(s)." -f @($script:SjResults).Count, $SjFailed)
if ($SjFailed -gt 0) { exit 1 }
exit 0
