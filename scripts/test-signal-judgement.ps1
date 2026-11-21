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
#   the link       group LINK: a record's issue is its repo and number. adopt-signal takes the
#                  same number from another repo and refuses it from the same one;
#                  resolve-signal -CloseIssue acts on the record's own repo and refuses a -Repo
#                  naming another, writing nothing; signals-relink previews, re-points only the
#                  records whose title matches or that are named, and takes the store lock. It
#                  runs with its OWN fake gh, one that ANSWERS - see that group's helpers.
#   publishing     group PUBLISH: signals-push and resolve-signal -CloseIssue check the exact
#                  text they would send for a private-names entry, this machine's name and a
#                  user folder path, hold a finding until -Clearance clears it for one signal,
#                  name a finding by place and never by text, say whether the destination is
#                  public, and publish a machine code; and the wrapper flags the list lines
#                  section 16 of check-suite-docs.ps1 flags. Its own fake gh, as LINK has.
#
# -AgainstWrapper <path> runs every row against another copy of keel-state.ps1, -LinkOnly
# runs group LINK alone, and -PublishOnly runs group PUBLISH alone. Both exist to show a row able to fail, by running it against a copy
# with one thing broken; neither is on the push path, which runs this suite with no switches.
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

param(
    [string]$AgainstWrapper = '',
    [switch]$LinkOnly,
    [switch]$PublishOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SjRepoRoot     = Split-Path -Parent $PSScriptRoot
$SjStateWrapper = Join-Path $SjRepoRoot 'plugins\keel-workflow\skills\keel-orchestrator\wrappers\keel-state.ps1'
if ($AgainstWrapper -ne '') { $SjStateWrapper = (Resolve-Path -LiteralPath $AgainstWrapper).Path }
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
# The LINK group's helpers. A record's issue is its repo and number, read from the stored
# link; these rows need a gh that ANSWERS, which the outward suite's fake does not (it refuses
# everything, and that suite throws if a row reaches it). So this group writes its own fake:
# it logs every call, answers 'issue view <n> --repo <owner/name>' by typing a fixture file
# named <owner>_<name>_<n>.json and exits 1 when there is none, and answers 'issue close' and
# 'api' with exit 0. Every child of the group runs with it FIRST on PATH, where Resolve-Gh asks
# first, and with KEEL_OUTWARD=allow; every repo in the fixtures is under example/, and the
# harness row below proves the fake is what answered before any other row is read.
# ---------------------------------------------------------------------------
function New-AnsweringGh {
    param([string]$SjDir, [string]$SjLog, [string]$SjFix)
    New-Item -ItemType Directory -Path $SjDir -Force | Out-Null
    New-Item -ItemType Directory -Path $SjFix -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $SjDir 'gh.cmd') -Encoding ASCII -Value @(
        '@echo off',
        ('echo %*>>"' + $SjLog + '"'),
        'if "%1"=="issue" if "%2"=="view" goto view',
        'if "%1"=="issue" if "%2"=="close" exit /b 0',
        'if "%1"=="api" goto api',
        'exit /b 7',
        ':view',
        'set "SJREPO=%5"',
        'set "SJREPO=%SJREPO:/=_%"',
        ('if exist "' + $SjFix + '\%SJREPO%_%3.json" ( type "' + $SjFix + '\%SJREPO%_%3.json" & exit /b 0 )'),
        'echo fake gh: no such fixture 1>&2',
        'exit /b 1',
        ':api',
        'echo https://github.com/example/fake-comment',
        'exit /b 0')
}

# One fixture issue the fake answers for. ASCII only; the titles here are ASCII.
function Set-FixtureIssue {
    param([string]$SjFix, [string]$SjRepoSlug, [int]$SjNum, [string]$SjTitle)
    $SjObj = [ordered]@{ number = $SjNum; title = $SjTitle; state = 'OPEN'; url = "https://github.com/$SjRepoSlug/issues/$SjNum" }
    $SjName = ($SjRepoSlug -replace '/', '_') + '_' + $SjNum + '.json'
    Set-Content -LiteralPath (Join-Path $SjFix $SjName) -Encoding ASCII -Value ($SjObj | ConvertTo-Json -Compress)
}

function Invoke-WrapperGh {
    param([string[]]$SjArgs, [string]$SjHome, [string]$SjGhDir)
    $SjPrevPath = $env:PATH
    $SjPrevOut  = $env:KEEL_OUTWARD
    try {
        Set-EnvVar 'PATH' ($SjGhDir + ';' + $SjPrevPath)
        Set-EnvVar 'KEEL_OUTWARD' 'allow'
        return (Invoke-Wrapper -SjHome $SjHome -SjArgs $SjArgs)
    }
    finally {
        Set-EnvVar 'PATH' $SjPrevPath
        Set-EnvVar 'KEEL_OUTWARD' $SjPrevOut
    }
}

function Get-GhLogLines {
    param([string]$SjLog)
    if (-not (Test-Path -LiteralPath $SjLog)) { return @() }
    return @(Get-Content -LiteralPath $SjLog | ForEach-Object { ([string]$_).TrimEnd() })
}

# Writes an issue number and, unless the link is empty, a stored link onto a filed signal. The
# wrapper writes these only after a real GitHub call (signals-push, adopt-signal), so a suite
# that must not reach GitHub builds the precondition itself, in its own scratch store, as
# test-outward-guard.ps1's New-SignalWithIssue does.
function Set-LinkedRecord {
    param([string]$SjHome, [string]$SjId, [int]$SjNum, [string]$SjLink)
    $SjPath = Get-SignalPath -SjHome $SjHome -SjId $SjId
    $SjRec = Get-SignalRecord -SjHome $SjHome -SjId $SjId
    Add-Member -InputObject $SjRec -NotePropertyName 'issue' -NotePropertyValue $SjNum -Force
    $SjUrlValue = $null
    if ($SjLink -ne '') { $SjUrlValue = $SjLink }
    Add-Member -InputObject $SjRec -NotePropertyName 'issueUrl' -NotePropertyValue $SjUrlValue -Force
    Add-Member -InputObject $SjRec -NotePropertyName 'pushedAt' -NotePropertyValue '2026-01-01T00:00:00' -Force
    [System.IO.File]::WriteAllText($SjPath, ($SjRec | ConvertTo-Json -Depth 14), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-FileSha {
    param([string]$SjPath)
    # .NET rather than Get-FileHash: that cmdlet is not always loaded in a powershell.exe started
    # from a hook or a tool shell, and a missing cmdlet would end the run.
    $SjAlg = [System.Security.Cryptography.SHA256]::Create()
    try { return (-join ($SjAlg.ComputeHash([System.IO.File]::ReadAllBytes($SjPath)) | ForEach-Object { $_.ToString('x2') })) }
    finally { $SjAlg.Dispose() }
}

# The names of the properties two parsed records disagree on, compared by their compressed JSON,
# over the properties either one has.
function Get-PropDiff {
    param($SjA, $SjB)
    $SjNames = @()
    foreach ($SjP in @($SjA.PSObject.Properties)) { if ($SjNames -notcontains $SjP.Name) { $SjNames += $SjP.Name } }
    foreach ($SjP in @($SjB.PSObject.Properties)) { if ($SjNames -notcontains $SjP.Name) { $SjNames += $SjP.Name } }
    $SjDiff = @()
    foreach ($SjN in $SjNames) {
        $SjVa = ''
        $SjVb = ''
        if ($null -ne $SjA.PSObject.Properties[$SjN]) { $SjVa = ConvertTo-Json -Compress -Depth 14 -InputObject $SjA.PSObject.Properties[$SjN].Value }
        else { $SjVa = '<absent>' }
        if ($null -ne $SjB.PSObject.Properties[$SjN]) { $SjVb = ConvertTo-Json -Compress -Depth 14 -InputObject $SjB.PSObject.Properties[$SjN].Value }
        else { $SjVb = '<absent>' }
        if ($SjVa -cne $SjVb) { $SjDiff += $SjN }
    }
    return $SjDiff
}

# The write lock's name for the scratch store, computed as the wrapper's Get-WriteLockName
# computes it and as scripts/test-concurrent-writes.ps1 computes it - a DECLARED coupling: if the
# wrapper's naming moves, LINK7's case stops holding the lock and fails, loudly.
function Get-StoreLockName {
    param([string]$SjHome)
    $SjStore = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $SjHome '.keel') 'signals')).ToLowerInvariant()
    $SjAlg = [System.Security.Cryptography.SHA256]::Create()
    try { $SjHex = -join ($SjAlg.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SjStore)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $SjAlg.Dispose() }
    return ('Global\keel-write-' + $SjHex)
}

# The new lines a log gained since a count was taken.
# The visibility read signals-push and resolve-signal -CloseIssue make before they publish
# ('repo view <slug> ...') publishes nothing, and these rows count the acts, so it is left out
# unless -SjEvery asks for every line.
function Get-NewLines {
    param([string]$SjLog, [int]$SjSince, [switch]$SjEvery)
    $SjAll = @(Get-GhLogLines -SjLog $SjLog)
    if ($SjAll.Count -le $SjSince) { return @() }
    $SjNew = @($SjAll[$SjSince..($SjAll.Count - 1)])
    if ($SjEvery) { return $SjNew }
    return @($SjNew | Where-Object { -not $_.StartsWith('repo view ') })
}

# The one line of a relink listing that starts with a record's id.
function Get-RelinkRow {
    param([string]$SjText, [string]$SjId)
    foreach ($SjL in @($SjText -split "`n")) { if ($SjL.StartsWith("$SjId  ")) { return $SjL } }
    return ''
}

# ---------------------------------------------------------------------------
# GROUP LINK - a record's issue is its repo and number
#
# Its own scratch home and project, destination example/new. Each pair has its own records, so
# no row inherits a state an earlier row left: a resolved record would take the retry path, and a
# re-pointed one would leave the relink set. The numbers are held in variables and every id is
# parsed from the wrapper's output, because validator section 18 refuses record ids and
# issue-number phrases in product files.
# ---------------------------------------------------------------------------
function Invoke-LinkCases {
    param([string]$SjTempRoot)

    $SjLHome = Join-Path $SjTempRoot 'link-home'
    $SjLRepo = Join-Path $SjTempRoot 'link-project'
    $SjGhDir = Join-Path $SjTempRoot 'link-gh'
    $SjFix   = Join-Path $SjTempRoot 'link-fixtures'
    $SjLog   = Join-Path $SjTempRoot 'link-gh.log'
    New-AnsweringGh -SjDir $SjGhDir -SjLog $SjLog -SjFix $SjFix
    New-Fixture -SjRepo $SjLRepo -SjHome $SjLHome
    $SjTgt = Invoke-Wrapper -SjHome $SjLHome -SjArgs @('signals-target', '-Repo', 'example/new')
    if ($SjTgt.Code -ne 0) { throw "fixture signals-target failed (exit $($SjTgt.Code)): $($SjTgt.Text)" }
    $SjStoreDir = Join-Path (Join-Path $SjLHome '.keel') 'signals'
    $SjOldBase = 'https://github.com/example/old/issues/'
    $SjNewBase = 'https://github.com/example/new/issues/'
    $SjOthBase = 'https://github.com/example/other/issues/'

    # --- HARNESS: the answering fake is what gh resolves to ---------------------------------
    $SjHN = 40
    Set-FixtureIssue -SjFix $SjFix -SjRepoSlug 'example/new' -SjNum $SjHN -SjTitle 'harness fixture'
    $SjH = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @(
        'adopt-signal', '-Issue', "$SjHN", '-Repo', 'example/new', '-Project', 'link', '-Phase', 'W1.1', '-Kind', 'gap', '-Path', $SjLRepo)
    $SjHLog = @(Get-GhLogLines -SjLog $SjLog)
    Add-Result 'LINK-HARNESS-CONTROL-answering-gh-reached' `
        (($SjH.Code -eq 0) -and ($SjHLog -contains "issue view $SjHN --repo example/new --json number,title,state,url")) `
        "a fresh adopt through the answering fake must exit 0 and be logged; exit $($SjH.Code), log=[$($SjHLog -join ' || ')]"

    # --- LINK1: adopt refuses only the same repo and number ----------------------------------
    $SjN1 = 41
    $SjHeld = New-Signal -SjRepo $SjLRepo -SjHome $SjLHome -SjDetail 'link held on old'
    Set-LinkedRecord -SjHome $SjLHome -SjId $SjHeld -SjNum $SjN1 -SjLink ($SjOldBase + $SjN1)
    Set-FixtureIssue -SjFix $SjFix -SjRepoSlug 'example/new' -SjNum $SjN1 -SjTitle 'same number on another repo'
    $SjL1Case = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @(
        'adopt-signal', '-Issue', "$SjN1", '-Repo', 'example/new', '-Project', 'link', '-Phase', 'W1.1', '-Kind', 'gap', '-Path', $SjLRepo)
    $SjL1New = ''
    if ($SjL1Case.Text -match 'as (S\d{4}) \(') { $SjL1New = $Matches[1] }
    $SjL1NewUrl = ''
    $SjL1NewNum = 0
    if ($SjL1New -ne '') {
        $SjL1Rec = Get-SignalRecord -SjHome $SjLHome -SjId $SjL1New
        $SjL1NewUrl = [string]$SjL1Rec.issueUrl
        $SjL1NewNum = [int]$SjL1Rec.issue
    }
    $SjL1Files = @(Get-ChildItem -LiteralPath $SjStoreDir -Filter '*.json').Count
    $SjL1Log = @(Get-GhLogLines -SjLog $SjLog).Count
    $SjL1Ctl = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @(
        'adopt-signal', '-Issue', "$SjN1", '-Repo', 'example/old', '-Project', 'link', '-Phase', 'W1.1', '-Kind', 'gap', '-Path', $SjLRepo)
    $SjL1FilesAfter = @(Get-ChildItem -LiteralPath $SjStoreDir -Filter '*.json').Count
    $SjL1LogAfter = @(Get-GhLogLines -SjLog $SjLog).Count
    Add-Pair 'LINK1-adopt-compares-repo-and-number' `
        (($SjL1Case.Code -eq 0) -and ($SjL1NewUrl -eq ($SjNewBase + $SjN1)) -and ($SjL1NewNum -eq $SjN1)) `
        "adopting the number from example/new over a record holding it on example/old must exit 0 and store a link on example/new; exit $($SjL1Case.Code), id=$SjL1New, url=$SjL1NewUrl; output=[$($SjL1Case.Text)]" `
        (($SjL1Ctl.Code -eq 90) -and ($SjL1Ctl.Text -like "*$SjHeld*") -and ($SjL1FilesAfter -eq $SjL1Files) -and ($SjL1LogAfter -eq $SjL1Log)) `
        "adopting it from example/old, where the held record is, must refuse at 90 naming $SjHeld, add no file and call no gh; exit $($SjL1Ctl.Code), files $SjL1Files->$SjL1FilesAfter, log $SjL1Log->$SjL1LogAfter; output=[$($SjL1Ctl.Text)]" `
        ($SjL1Case.Code -ne $SjL1Ctl.Code) `
        'the same number from two repos must be answered differently, or the scan is not reading the repo'

    # --- LINK2: -CloseIssue acts on the record's own repo ------------------------------------
    $SjN2 = 42
    $SjL2Id = New-Signal -SjRepo $SjLRepo -SjHome $SjLHome -SjDetail 'link linked to other'
    Set-LinkedRecord -SjHome $SjLHome -SjId $SjL2Id -SjNum $SjN2 -SjLink ($SjOthBase + $SjN2)
    $SjL2Since = @(Get-GhLogLines -SjLog $SjLog).Count
    $SjL2Case = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @(
        'resolve-signal', '-Id', $SjL2Id, '-As', 'REJECTED', '-Detail', 'x', '-CloseIssue', '-Path', $SjLRepo)
    $SjL2Lines = @(Get-NewLines -SjLog $SjLog -SjSince $SjL2Since)
    $SjN2c = 43
    $SjL2CtlId = New-Signal -SjRepo $SjLRepo -SjHome $SjLHome -SjDetail 'link with no link'
    Set-LinkedRecord -SjHome $SjLHome -SjId $SjL2CtlId -SjNum $SjN2c -SjLink ''
    $SjL2CtlSince = @(Get-GhLogLines -SjLog $SjLog).Count
    $SjL2Ctl = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @(
        'resolve-signal', '-Id', $SjL2CtlId, '-As', 'REJECTED', '-Detail', 'x', '-CloseIssue', '-Path', $SjLRepo)
    $SjL2CtlLines = @(Get-NewLines -SjLog $SjLog -SjSince $SjL2CtlSince)
    $SjL2CaseOk = ($SjL2Case.Code -eq 0) -and ($SjL2Lines.Count -eq 2)
    if ($SjL2CaseOk) {
        $SjL2CaseOk = ($SjL2Lines[0] -like "api --method POST repos/example/other/issues/$SjN2/comments --input *") -and
            ($SjL2Lines[1] -ceq "issue close $SjN2 --repo example/other") -and
            (@($SjL2Lines | Where-Object { $_ -like '*example/new*' }).Count -eq 0)
    }
    $SjL2CtlOk = ($SjL2Ctl.Code -eq 0) -and ($SjL2CtlLines.Count -eq 2)
    if ($SjL2CtlOk) {
        $SjL2CtlOk = ($SjL2CtlLines[0] -like "api --method POST repos/example/new/issues/$SjN2c/comments --input *") -and
            ($SjL2CtlLines[1] -ceq "issue close $SjN2c --repo example/new")
    }
    Add-Pair 'LINK2-close-acts-on-the-records-repo' `
        $SjL2CaseOk `
        "a record linked to example/other, with the destination example/new, must comment on and close on example/other and nowhere else; exit $($SjL2Case.Code), lines=[$($SjL2Lines -join ' || ')]" `
        $SjL2CtlOk `
        "a record with no link must still comment on and close on the destination, example/new; exit $($SjL2Ctl.Code), lines=[$($SjL2CtlLines -join ' || ')]" `
        ((($SjL2Lines -join ' ') -like '*example/other*') -ne (($SjL2CtlLines -join ' ') -like '*example/other*')) `
        'the linked and the unlinked record must reach different repos, or the close is not reading the link'

    # --- LINK3: a -Repo that disagrees with the link is refused before anything happens -----
    $SjN3 = 44
    $SjL3Id = New-Signal -SjRepo $SjLRepo -SjHome $SjLHome -SjDetail 'link disagreeing repo'
    Set-LinkedRecord -SjHome $SjLHome -SjId $SjL3Id -SjNum $SjN3 -SjLink ($SjOthBase + $SjN3)
    $SjL3Path = Get-SignalPath -SjHome $SjLHome -SjId $SjL3Id
    $SjL3Sha = Get-FileSha -SjPath $SjL3Path
    $SjL3Since = @(Get-GhLogLines -SjLog $SjLog).Count
    $SjL3Case = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @(
        'resolve-signal', '-Id', $SjL3Id, '-As', 'REJECTED', '-Detail', 'x', '-CloseIssue', '-Repo', 'example/new', '-Path', $SjLRepo)
    $SjL3CaseLines = @(Get-NewLines -SjLog $SjLog -SjSince $SjL3Since -SjEvery)
    $SjL3ShaAfter = Get-FileSha -SjPath $SjL3Path
    $SjL3CtlSince = @(Get-GhLogLines -SjLog $SjLog).Count
    $SjL3Ctl = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @(
        'resolve-signal', '-Id', $SjL3Id, '-As', 'REJECTED', '-Detail', 'x', '-CloseIssue', '-Repo', 'example/other', '-Path', $SjLRepo)
    $SjL3CtlLines = @(Get-NewLines -SjLog $SjLog -SjSince $SjL3CtlSince)
    $SjL3CtlOk = ($SjL3Ctl.Code -eq 0) -and ($SjL3CtlLines.Count -eq 2)
    if ($SjL3CtlOk) {
        $SjL3CtlOk = ($SjL3CtlLines[0] -like "api --method POST repos/example/other/issues/$SjN3/comments --input *") -and ($SjL3CtlLines[1] -ceq "issue close $SjN3 --repo example/other")
    }
    Add-Pair 'LINK3-disagreeing-repo-refused' `
        (($SjL3Case.Code -eq 90) -and ($SjL3Case.Text -like '*signals-relink -From example/other -Repo example/new*') -and ($SjL3CaseLines.Count -eq 0) -and ($SjL3ShaAfter -eq $SjL3Sha)) `
        "-Repo example/new on a record linked to example/other must refuse at 90 naming the relink command, call no gh and leave the record's bytes alone; exit $($SjL3Case.Code), new log lines=$($SjL3CaseLines.Count), sha same=$($SjL3ShaAfter -eq $SjL3Sha); output=[$($SjL3Case.Text)]" `
        $SjL3CtlOk `
        "-Repo example/other, which agrees with the record, must exit 0 and make both calls there; exit $($SjL3Ctl.Code), lines=[$($SjL3CtlLines -join ' || ')]" `
        ($SjL3Case.Code -ne $SjL3Ctl.Code) `
        'an agreeing and a disagreeing -Repo must be answered differently, or the check refuses every -Repo'

    # --- LINK4: a record with no link, or linked to the destination, closes as before -------
    # The expected lines are the ones the wrapper as it stood before this change logged for
    # records of exactly these two shapes, read from that wrapper's own run.
    $SjN4a = 45
    $SjN4b = 46
    $SjL4a = New-Signal -SjRepo $SjLRepo -SjHome $SjLHome -SjDetail 'link no link four'
    Set-LinkedRecord -SjHome $SjLHome -SjId $SjL4a -SjNum $SjN4a -SjLink ''
    $SjL4b = New-Signal -SjRepo $SjLRepo -SjHome $SjLHome -SjDetail 'link on destination four'
    Set-LinkedRecord -SjHome $SjLHome -SjId $SjL4b -SjNum $SjN4b -SjLink ($SjNewBase + $SjN4b)
    $SjL4Since = @(Get-GhLogLines -SjLog $SjLog).Count
    $SjL4Ra = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @('resolve-signal', '-Id', $SjL4a, '-As', 'REJECTED', '-Detail', 'x', '-CloseIssue', '-Path', $SjLRepo)
    $SjL4Rb = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @('resolve-signal', '-Id', $SjL4b, '-As', 'REJECTED', '-Detail', 'x', '-CloseIssue', '-Path', $SjLRepo)
    $SjL4Lines = @(Get-NewLines -SjLog $SjLog -SjSince $SjL4Since)
    $SjL4Want = @(
        ("api --method POST repos/example/new/issues/$SjN4a/comments --input " + (Join-Path $env:TEMP "keel-resolve-$SjL4a.json") + ' --jq .html_url'),
        "issue close $SjN4a --repo example/new",
        ("api --method POST repos/example/new/issues/$SjN4b/comments --input " + (Join-Path $env:TEMP "keel-resolve-$SjL4b.json") + ' --jq .html_url'),
        "issue close $SjN4b --repo example/new")
    $SjL4Same = ($SjL4Lines.Count -eq $SjL4Want.Count)
    if ($SjL4Same) { for ($SjI = 0; $SjI -lt $SjL4Want.Count; $SjI++) { if ($SjL4Lines[$SjI] -cne $SjL4Want[$SjI]) { $SjL4Same = $false } } }
    # The control: LINK2's record, compared with the destination shape for ITS number, must NOT
    # equal it - so this comparison can tell a record that moved from one that did not.
    $SjL4Dest2 = @(
        ("api --method POST repos/example/new/issues/$SjN2/comments --input " + (Join-Path $env:TEMP "keel-resolve-$SjL2Id.json") + ' --jq .html_url'),
        "issue close $SjN2 --repo example/new")
    $SjL4CtlSame = ($SjL2Lines.Count -eq 2)
    if ($SjL4CtlSame) { $SjL4CtlSame = ($SjL2Lines[0] -ceq $SjL4Dest2[0]) -and ($SjL2Lines[1] -ceq $SjL4Dest2[1]) }
    Add-Pair 'LINK4-unlinked-and-destination-close-as-before' `
        (($SjL4Ra.Code -eq 0) -and ($SjL4Rb.Code -eq 0) -and $SjL4Same) `
        "both records must log exactly the destination lines the earlier wrapper logged; exits $($SjL4Ra.Code)/$($SjL4Rb.Code), got=[$($SjL4Lines -join ' || ')], want=[$($SjL4Want -join ' || ')]" `
        (-not $SjL4CtlSame) `
        "LINK2's record, linked to example/other, must NOT log the destination shape; got=[$($SjL2Lines -join ' || ')]" `
        ($SjL4Same -ne $SjL4CtlSame) `
        'the comparison must accept the unmoved records and reject the moved one, or it accepts everything'

    # --- LINK5: signals-relink previews, then re-points the matching records ----------------
    # Its records move from a repo of their own, example/moved, so the set the route finds is
    # exactly these three and no record an earlier pair left linked to example/old.
    $SjMovBase = 'https://github.com/example/moved/issues/'
    $SjN5 = @(51, 52, 53)
    $SjL5Ids = @()
    $SjL5Det = @('link relink alpha', 'link relink beta', 'link relink gamma')
    for ($SjI = 0; $SjI -lt 3; $SjI++) {
        $SjOneId = New-Signal -SjRepo $SjLRepo -SjHome $SjLHome -SjDetail $SjL5Det[$SjI]
        Set-LinkedRecord -SjHome $SjLHome -SjId $SjOneId -SjNum $SjN5[$SjI] -SjLink ($SjMovBase + $SjN5[$SjI])
        $SjL5Ids += $SjOneId
    }
    $SjN5o = 54
    $SjL5Oth = New-Signal -SjRepo $SjLRepo -SjHome $SjLHome -SjDetail 'link relink other repo'
    Set-LinkedRecord -SjHome $SjLHome -SjId $SjL5Oth -SjNum $SjN5o -SjLink ($SjOthBase + $SjN5o)
    # alpha matches exactly, beta's title there is signal-shaped and differs only after a shared
    # prefix (so a test reading only the '[signal:' prefix or a leading part would call it a match),
    # gamma matches once whitespace runs are collapsed. The other-repo record's number is answerable too, so a relink that ignored -From
    # would list it.
    Set-FixtureIssue -SjFix $SjFix -SjRepoSlug 'example/new' -SjNum $SjN5[0] -SjTitle '[signal:gap] link relink alpha'
    Set-FixtureIssue -SjFix $SjFix -SjRepoSlug 'example/new' -SjNum $SjN5[1] -SjTitle '[signal:gap] link relink beta, then edited'
    Set-FixtureIssue -SjFix $SjFix -SjRepoSlug 'example/new' -SjNum $SjN5[2] -SjTitle '[signal:gap]  link   relink gamma '
    Set-FixtureIssue -SjFix $SjFix -SjRepoSlug 'example/new' -SjNum $SjN5o -SjTitle '[signal:gap] link relink other repo'
    $SjL5All = @($SjL5Ids) + @($SjL5Oth)
    $SjL5Sha = @{}
    $SjL5Before = @{}
    foreach ($SjOneId in $SjL5All) {
        $SjL5Sha[$SjOneId] = Get-FileSha -SjPath (Get-SignalPath -SjHome $SjLHome -SjId $SjOneId)
        $SjL5Before[$SjOneId] = Get-SignalRecord -SjHome $SjLHome -SjId $SjOneId
    }
    $SjL5Since = @(Get-GhLogLines -SjLog $SjLog).Count
    $SjL5Prev = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @('signals-relink', '-From', 'example/moved', '-Path', $SjLRepo)
    $SjL5PrevLines = @(Get-NewLines -SjLog $SjLog -SjSince $SjL5Since)
    $SjL5Marks = @('MATCH', 'MISMATCH', 'MATCH')
    $SjL5RowsOk = $true
    for ($SjI = 0; $SjI -lt 3; $SjI++) {
        $SjRow = Get-RelinkRow -SjText $SjL5Prev.Text -SjId $SjL5Ids[$SjI]
        $SjWantLead = "$($SjL5Ids[$SjI])  #$($SjN5[$SjI])  $SjMovBase$($SjN5[$SjI]) -> $SjNewBase$($SjN5[$SjI])  $($SjL5Marks[$SjI])"
        if (-not (($SjRow -ceq $SjWantLead) -or $SjRow.StartsWith("$SjWantLead  "))) { $SjL5RowsOk = $false }
    }
    $SjL5NoOther = (-not ($SjL5Prev.Text -like "*$SjL5Oth*")) -and ($SjL5Prev.Text -like '*3 record(s) link to issues on example/moved*')
    $SjL5HashSame = $true
    foreach ($SjOneId in $SjL5All) { if ((Get-FileSha -SjPath (Get-SignalPath -SjHome $SjLHome -SjId $SjOneId)) -ne $SjL5Sha[$SjOneId]) { $SjL5HashSame = $false } }
    # The route REACHES gh when the guard allows it: one read per old-repo record.
    $SjL5Reads = $true
    for ($SjI = 0; $SjI -lt 3; $SjI++) { if ($SjL5PrevLines -notcontains "issue view $($SjN5[$SjI]) --repo example/new --json number,title,state,url") { $SjL5Reads = $false } }
    $SjL5Apply = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @('signals-relink', '-From', 'example/moved', '-Apply', '-Path', $SjLRepo)
    $SjL5Moved = $true
    foreach ($SjI in @(0, 2)) {
        $SjAfter = Get-SignalRecord -SjHome $SjLHome -SjId $SjL5Ids[$SjI]
        $SjDiff = @(Get-PropDiff $SjL5Before[$SjL5Ids[$SjI]] $SjAfter)
        if (($SjDiff.Count -ne 1) -or ($SjDiff[0] -ne 'issueUrl') -or ([string]$SjAfter.issueUrl -ne ($SjNewBase + $SjN5[$SjI]))) { $SjL5Moved = $false }
    }
    $SjL5BetaSame = ((Get-FileSha -SjPath (Get-SignalPath -SjHome $SjLHome -SjId $SjL5Ids[1])) -eq $SjL5Sha[$SjL5Ids[1]])
    $SjL5OthSame = ((Get-FileSha -SjPath (Get-SignalPath -SjHome $SjLHome -SjId $SjL5Oth)) -eq $SjL5Sha[$SjL5Oth])
    $SjL5AlphaSame = ((Get-FileSha -SjPath (Get-SignalPath -SjHome $SjLHome -SjId $SjL5Ids[0])) -eq $SjL5Sha[$SjL5Ids[0]])
    Add-Pair 'LINK5-relink-previews-then-repoints-matches' `
        (($SjL5Prev.Code -eq 0) -and $SjL5RowsOk -and $SjL5NoOther -and $SjL5HashSame -and $SjL5Reads -and ($SjL5Apply.Code -eq 0) -and $SjL5Moved) `
        "preview must exit 0, list the three old-repo records MATCH/MISMATCH/MATCH with old and new links, not list the other-repo record, change no file and read each once; -Apply must change alpha and gamma in issueUrl alone. preview exit=$($SjL5Prev.Code) rows=$SjL5RowsOk noOther=$SjL5NoOther hashSame=$SjL5HashSame reads=$SjL5Reads apply exit=$($SjL5Apply.Code) moved=$SjL5Moved; preview=[$($SjL5Prev.Text)]" `
        ($SjL5BetaSame -and $SjL5OthSame) `
        "the mismatching record and the other-repo record must keep their bytes after -Apply; beta same=$SjL5BetaSame, other same=$SjL5OthSame; apply=[$($SjL5Apply.Text)]" `
        ($SjL5AlphaSame -ne $SjL5BetaSame) `
        'a matching and a mismatching record must end differently, or the title test is not deciding'

    # --- LINK6: a mismatching record is re-pointed when named --------------------------------
    $SjL6Beta = $SjL5Ids[1]
    $SjL6Apply = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @('signals-relink', '-From', 'example/moved', '-Id', $SjL6Beta, '-Apply', '-Path', $SjLRepo)
    $SjL6After = Get-SignalRecord -SjHome $SjLHome -SjId $SjL6Beta
    $SjL6Diff = @(Get-PropDiff $SjL5Before[$SjL6Beta] $SjL6After)
    $SjL6OthSame = ((Get-FileSha -SjPath (Get-SignalPath -SjHome $SjLHome -SjId $SjL5Oth)) -eq $SjL5Sha[$SjL5Oth])
    $SjL6Moved = ($SjL6Apply.Code -eq 0) -and ($SjL6Diff.Count -eq 1)
    if ($SjL6Moved) { $SjL6Moved = ($SjL6Diff[0] -eq 'issueUrl') -and ([string]$SjL6After.issueUrl -eq ($SjNewBase + $SjN5[1])) }
    Add-Pair 'LINK6-named-mismatch-repointed' `
        ($SjL6Moved -and $SjL6OthSame) `
        "-Apply -Id naming the mismatching record must change it in issueUrl alone, to example/new, and leave the other-repo record alone; exit $($SjL6Apply.Code), diff=[$($SjL6Diff -join ',')], url=$($SjL6After.issueUrl), other same=$SjL6OthSame; output=[$($SjL6Apply.Text)]" `
        $SjL5BetaSame `
        'without the name, the same record was left alone by the earlier -Apply' `
        ($SjL6Moved -ne (-not $SjL5BetaSame)) `
        'the named and the unnamed run must end differently for the same record, or -Id is not deciding'

    # --- LINK7: -Apply waits for the store lock, and writes once it is free -----------------
    $SjN7 = 57
    $SjL7Id = New-Signal -SjRepo $SjLRepo -SjHome $SjLHome -SjDetail 'link lock fixture'
    Set-LinkedRecord -SjHome $SjLHome -SjId $SjL7Id -SjNum $SjN7 -SjLink ("https://github.com/example/lockold/issues/$SjN7")
    Set-FixtureIssue -SjFix $SjFix -SjRepoSlug 'example/new' -SjNum $SjN7 -SjTitle '[signal:gap] link lock fixture'
    $SjL7Path = Get-SignalPath -SjHome $SjLHome -SjId $SjL7Id
    $SjL7Sha = Get-FileSha -SjPath $SjL7Path
    $SjL7Mutex = [System.Threading.Mutex]::new($false, (Get-StoreLockName -SjHome $SjLHome))
    $SjL7Held = $SjL7Mutex.WaitOne([TimeSpan]::FromSeconds(5))
    $SjL7Case = $null
    try {
        $SjL7Case = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @('signals-relink', '-From', 'example/lockold', '-Apply', '-Path', $SjLRepo)
    }
    finally {
        if ($SjL7Held) { $SjL7Mutex.ReleaseMutex() }
        $SjL7Mutex.Dispose()
    }
    $SjL7ShaCase = Get-FileSha -SjPath $SjL7Path
    $SjL7Ctl = Invoke-WrapperGh -SjHome $SjLHome -SjGhDir $SjGhDir -SjArgs @('signals-relink', '-From', 'example/lockold', '-Apply', '-Path', $SjLRepo)
    $SjL7ShaCtl = Get-FileSha -SjPath $SjL7Path
    $SjL7CtlUrl = [string](Get-SignalRecord -SjHome $SjLHome -SjId $SjL7Id).issueUrl
    Add-Pair 'LINK7-relink-takes-the-store-lock' `
        ($SjL7Held -and ($SjL7Case.Code -eq 89) -and ($SjL7ShaCase -eq $SjL7Sha)) `
        "with the store's lock held past the wait, -Apply must stop at 89 and write nothing; held=$SjL7Held exit $($SjL7Case.Code), sha same=$($SjL7ShaCase -eq $SjL7Sha); output=[$($SjL7Case.Text)]" `
        (($SjL7Ctl.Code -eq 0) -and ($SjL7ShaCtl -ne $SjL7Sha) -and ($SjL7CtlUrl -eq ($SjNewBase + $SjN7))) `
        "with the lock released, the same -Apply must exit 0 and re-point the record; exit $($SjL7Ctl.Code), url=$SjL7CtlUrl" `
        ($SjL7Case.Code -ne $SjL7Ctl.Code) `
        'a held and a free lock must be answered differently, or the arm is not taking the lock'
}

# ---------------------------------------------------------------------------
# GROUP PUBLISH - what a report is checked for before it leaves the machine
#
# signals-push and resolve-signal -CloseIssue check the exact text they would send for an entry of
# the private-names list, this machine's name and a user folder path; a finding holds the send
# until it is cleared for that one signal with -Clearance, and is named by place and list line,
# never by its text. Both say whether the destination is public, and a published body names the
# machine by a random code. This group runs on its OWN scratch home and project, with its own fake
# gh FIRST on PATH: it logs every call, answers 'repo view' with PUBLIC or PRIVATE when a mode file
# says so (and exits 1 otherwise), appends every '--input' file it is given to a bodies file, and
# answers an issue POST with a number and a URL. Every child runs with a scratch COMPUTERNAME and,
# except the block limb, KEEL_OUTWARD=allow; the destination is example/pub.
#
# FIXTURE TERMS ARE ASSEMBLED AT RUN TIME, with a random suffix. This file sits under scripts/, and
# the product's own private-names and history checks read it, so a literal term here could match a
# real list or be refused as a record id. No row prints a term: a failure names the row and what
# it counted.
#
# PUB9 RUNS SECTION 16 ITSELF. It copies check-suite-docs.ps1 into the untracked scripts\ folder of
# a scratch git repo, as test-private-names.ps1 does, and compares the list lines section 16 flags
# in one file with the ones the wrapper flags in the same text. Git variables a hook may export are
# cleared around it, and it refuses unless git resolves the scratch repo as its own top level.
# ---------------------------------------------------------------------------
function New-PublishGh {
    param([string]$SjDir, [string]$SjLog, [string]$SjBodies, [string]$SjMode)
    New-Item -ItemType Directory -Path $SjDir -Force | Out-Null
    New-Item -ItemType Directory -Path $SjMode -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $SjDir 'gh.cmd') -Encoding ASCII -Value @(
        '@echo off',
        ('echo %*>>"' + $SjLog + '"'),
        'if "%1"=="repo" goto repo',
        'if "%1"=="api" goto api',
        'if "%1"=="issue" if "%2"=="close" exit /b 0',
        'exit /b 7',
        ':repo',
        ('if exist "' + $SjMode + '\public" ( echo PUBLIC& exit /b 0 )'),
        ('if exist "' + $SjMode + '\private" ( echo PRIVATE& exit /b 0 )'),
        'echo fake gh: no visibility fixture 1>&2',
        'exit /b 1',
        ':api',
        ('if "%5"=="--input" ( type "%~6" >>"' + $SjBodies + '" & echo.>>"' + $SjBodies + '" & echo ----SJ-BODY-END---->>"' + $SjBodies + '" )'),
        'echo 101',
        'echo https://github.com/example/pub/issues/101',
        'exit /b 0')
}

function Set-PubMode {
    param([string]$SjMode, [string]$SjWord)
    foreach ($SjM in @('public', 'private')) {
        $SjF = Join-Path $SjMode $SjM
        if (Test-Path -LiteralPath $SjF) { Remove-Item -LiteralPath $SjF -Force }
    }
    if ($SjWord -ne '') { Set-Content -LiteralPath (Join-Path $SjMode $SjWord) -Encoding ASCII -Value 'x' }
}

function Invoke-WrapperPub {
    param([string[]]$SjArgs, [string]$SjHome, [string]$SjGhDir, [string]$SjMachine, [string]$SjOutward = 'allow')
    $SjPrevPath    = $env:PATH
    $SjPrevOut     = $env:KEEL_OUTWARD
    $SjPrevMachine = $env:COMPUTERNAME
    try {
        Set-EnvVar 'PATH' ($SjGhDir + ';' + $SjPrevPath)
        Set-EnvVar 'KEEL_OUTWARD' $SjOutward
        Set-EnvVar 'COMPUTERNAME' $SjMachine
        return (Invoke-Wrapper -SjHome $SjHome -SjArgs $SjArgs)
    }
    finally {
        Set-EnvVar 'PATH' $SjPrevPath
        Set-EnvVar 'KEEL_OUTWARD' $SjPrevOut
        Set-EnvVar 'COMPUTERNAME' $SjPrevMachine
    }
}

function New-PubSignal {
    param([string]$SjRepo, [string]$SjHome, [string]$SjGhDir, [string]$SjMachine, [string]$SjDetail)
    $SjFiled = Invoke-WrapperPub -SjHome $SjHome -SjGhDir $SjGhDir -SjMachine $SjMachine -SjArgs @(
        'signal', '-Kind', 'gap', '-Phase', 'W1.1', '-Detail', $SjDetail,
        '-Evidence', 'scripts/test-signal-judgement.ps1 - fixture, no real defect', '-Path', $SjRepo)
    if ($SjFiled.Code -ne 0) { throw "fixture signal failed (exit $($SjFiled.Code))" }
    foreach ($SjLine in @($SjFiled.Text -split "`n")) {
        if ($SjLine -match 'Filed signal\s+(S\d{4})') { return $Matches[1] }
    }
    throw 'could not read the filed signal id'
}

function Set-PubList {
    param([string]$SjHome, [string[]]$SjLines)
    $SjListFile = Join-Path (Join-Path $SjHome '.keel') 'private-names.txt'
    if ($null -eq $SjLines) {
        if (Test-Path -LiteralPath $SjListFile) { Remove-Item -LiteralPath $SjListFile -Force }
        return
    }
    [System.IO.File]::WriteAllText($SjListFile, (($SjLines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

# A preview split into its per-signal sections: from a '--- <id>' line to that signal's FINDINGS
# line, the text the operator reads; the finding lines after it; and every other line.
function Get-PubSections {
    param([string]$SjText)
    $SjSec = @{}
    $SjRest = @()
    $SjCur = ''
    $SjInFind = $false
    foreach ($SjL in @($SjText -split "`n")) {
        $SjT = $SjL.TrimEnd("`r")
        if ($SjT -match '^--- (S\d{4}) ') {
            $SjCur = $Matches[1]
            $SjSec[$SjCur] = [pscustomobject]@{ Body = @(); Findings = @(); Count = -1 }
            $SjInFind = $false
            continue
        }
        if ($SjCur -ne '' -and -not $SjInFind -and $SjT -match '^FINDINGS: (\d+)') {
            $SjSec[$SjCur].Count = [int]$Matches[1]
            $SjInFind = $true
            continue
        }
        if ($SjInFind -and $SjT -match '^  (S\d{4})  ') { $SjSec[$SjCur].Findings += $SjT; continue }
        if ($SjInFind) { $SjCur = ''; $SjInFind = $false }
        if ($SjCur -ne '') { $SjSec[$SjCur].Body += $SjT } else { $SjRest += $SjT }
    }
    return [pscustomobject]@{ Sections = $SjSec; Rest = $SjRest }
}

# One finding line, parsed: its signal id, category, list line (0 for none) and places.
function Get-PubFinding {
    param([string]$SjLine)
    if ($SjLine -match '^  (S\d{4})  (.+?)(?:, list line (\d+))?: (.+)$') {
        $SjLl = 0
        if ($Matches[3]) { $SjLl = [int]$Matches[3] }
        return [pscustomobject]@{ Id = $Matches[1]; Category = $Matches[2]; ListLine = $SjLl; Places = $Matches[4] }
    }
    return $null
}

function Get-PubFindingsOf {
    param($SjParsed, [string]$SjId)
    if (-not $SjParsed.Sections.ContainsKey($SjId)) { return @() }
    return @($SjParsed.Sections[$SjId].Findings | ForEach-Object { Get-PubFinding $_ } | Where-Object { $null -ne $_ })
}

function Test-PubHas {
    param([string]$SjHay, [string]$SjNeedle)
    return ($SjHay.IndexOf($SjNeedle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Get-PubLogCount {
    param([string]$SjLog, [string]$SjPrefix)
    return @(Get-GhLogLines -SjLog $SjLog | Where-Object { $_.StartsWith($SjPrefix) }).Count
}

function Get-PubShas {
    param([string]$SjHome, [string[]]$SjIds)
    $SjOut = @{}
    foreach ($SjI in $SjIds) { $SjOut[$SjI] = Get-FileSha -SjPath (Get-SignalPath -SjHome $SjHome -SjId $SjI) }
    return $SjOut
}

# The bodies the fake received, decoded from the JSON the wrapper wrote for gh.
function Get-PubBodies {
    param([string]$SjBodies)
    if (-not (Test-Path -LiteralPath $SjBodies)) { return @() }
    $SjOut = @()
    foreach ($SjChunk in ((Get-Content -Raw -LiteralPath $SjBodies) -split '----SJ-BODY-END----')) {
        if ($SjChunk.Trim() -eq '') { continue }
        $SjObj = $SjChunk.Trim() | ConvertFrom-Json
        if ($null -ne $SjObj) { $SjOut += $SjObj }
    }
    return $SjOut
}

function Invoke-PubGit {
    param([string]$SjRepoDir, [string[]]$SjGitArgs)
    $SjPrev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & git -C $SjRepoDir @SjGitArgs 2>$null
        $SjGitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $SjPrev }
    if ($SjGitCode -ne 0) { throw "fixture: git $($SjGitArgs[0]) failed (exit $SjGitCode)" }
}

# The list lines section 16 flags in a scratch repo holding one file with this text.
function Get-Section16Lines {
    param([string]$SjRoot, [string]$SjHome, [string]$SjTextLine)
    $SjGitVars = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
                   'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_COMMON_DIR', 'GIT_PREFIX', 'GIT_NAMESPACE')
    $SjSaved = @{}
    foreach ($SjV in $SjGitVars) {
        $SjSaved[$SjV] = [Environment]::GetEnvironmentVariable($SjV, 'Process')
        Remove-Item -LiteralPath "Env:\$SjV" -ErrorAction SilentlyContinue
    }
    $SjPrevProfile = $env:USERPROFILE
    try {
        $SjRepoDir = Join-Path $SjRoot ('pub9-repo-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 6))
        New-Item -ItemType Directory -Path (Join-Path $SjRepoDir 'scripts') -Force | Out-Null
        $SjPrev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $null = & git -c init.defaultBranch=main init -q $SjRepoDir 2>$null
        $SjInit = $LASTEXITCODE
        $SjTop = @(& git -C $SjRepoDir rev-parse --show-toplevel 2>$null)
        $ErrorActionPreference = $SjPrev
        if ($SjInit -ne 0) { throw "fixture: git init failed (exit $SjInit)" }
        $SjTail = (Split-Path -Leaf $SjRepoDir)
        $SjTopText = ''
        if ($SjTop.Count -gt 0) { $SjTopText = ([string]$SjTop[0]).Replace('\', '/').TrimEnd('/') }
        if (-not $SjTopText.EndsWith($SjTail, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'fixture: git does not resolve the scratch repository as its own top level - refusing to run'
        }
        Invoke-PubGit $SjRepoDir @('config', 'user.email', 'suite@example.invalid')
        Invoke-PubGit $SjRepoDir @('config', 'user.name', 'signal judgement suite')
        Invoke-PubGit $SjRepoDir @('config', 'core.autocrlf', 'false')
        [System.IO.File]::WriteAllText((Join-Path $SjRepoDir 'text.txt'), ($SjTextLine + "`n"), (New-Object System.Text.UTF8Encoding($false)))
        Invoke-PubGit $SjRepoDir @('add', 'text.txt')
        Invoke-PubGit $SjRepoDir @('commit', '-q', '-m', 'fixture')
        $SjCopy = Join-Path $SjRepoDir 'scripts\check-suite-docs.ps1'
        Copy-Item -LiteralPath (Join-Path $SjRepoRoot 'scripts\check-suite-docs.ps1') -Destination $SjCopy -Force
        $env:USERPROFILE = $SjHome
        $ErrorActionPreference = 'Continue'
        $SjOut = @(& $SjPwsh -NoProfile -ExecutionPolicy Bypass -File $SjCopy -PrivateNamesOnly 2>&1 | ForEach-Object { $_.ToString() })
        $ErrorActionPreference = $SjPrev
        $SjLines = @()
        foreach ($SjL in $SjOut) { if ($SjL -match 'holds the entry on list line (\d+) of') { $SjLines += [int]$Matches[1] } }
        return @($SjLines | Sort-Object -Unique)
    }
    finally {
        $env:USERPROFILE = $SjPrevProfile
        foreach ($SjV in $SjGitVars) { if ($null -ne $SjSaved[$SjV]) { Set-Item -LiteralPath "Env:\$SjV" -Value $SjSaved[$SjV] } }
    }
}

function Invoke-PublishCases {
    param([string]$SjTempRoot)

    $SjPHome  = Join-Path $SjTempRoot 'pub-home'
    $SjPHome2 = Join-Path $SjTempRoot 'pub-home-two'
    $SjPRepo  = Join-Path $SjTempRoot 'pub-project'
    $SjPRepo2 = Join-Path $SjTempRoot 'pub-project-two'
    $SjPGh    = Join-Path $SjTempRoot 'pub-gh'
    $SjPMode  = Join-Path $SjTempRoot 'pub-gh-mode'
    $SjPLog   = Join-Path $SjTempRoot 'pub-gh.log'
    $SjPBod   = Join-Path $SjTempRoot 'pub-gh-bodies.txt'
    New-PublishGh -SjDir $SjPGh -SjLog $SjPLog -SjBodies $SjPBod -SjMode $SjPMode
    New-Fixture -SjRepo $SjPRepo -SjHome $SjPHome
    New-Fixture -SjRepo $SjPRepo2 -SjHome $SjPHome2
    foreach ($SjH in @($SjPHome, $SjPHome2)) {
        $SjT = Invoke-Wrapper -SjHome $SjH -SjArgs @('signals-target', '-Repo', 'example/pub')
        if ($SjT.Code -ne 0) { throw "fixture signals-target failed (exit $($SjT.Code))" }
    }

    # The planted terms, assembled here so no literal of them is in this file.
    $SjSfx     = [System.Guid]::NewGuid().ToString('N').Substring(0, 6)
    $SjPlain   = 'qz' + 'plain' + $SjSfx
    $SjWordT   = 'Qz' + 'Word' + $SjSfx
    $SjNearT   = 'Qz' + 'Near' + $SjSfx
    $SjAbsent  = 'qz' + 'absent' + $SjSfx
    $SjMachine = 'QZ' + 'HOST-' + $SjSfx.ToUpper()
    $SjPathJ   = 'C:' + '\\' + 'Users' + '\\' + 'x'
    $SjList    = @('# fixture list', $SjPlain, ('word:' + $SjWordT), ('word:' + $SjNearT), $SjAbsent)
    Set-PubList -SjHome $SjPHome -SjLines $SjList
    $SjCatList = 'a private-names entry'
    $SjCatBad  = 'a private-names entry this check cannot read'
    $SjCatMach = "this machine's name"
    $SjCatPath = 'a user folder path'
    $SjVis     = 'Destination visibility:'
    $SjPubArgs   = @{ SjHome = $SjPHome; SjGhDir = $SjPGh; SjMachine = $SjMachine }

    # --- HARNESS: the fake is what gh resolves to ------------------------------------------
    $SjE = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail 'fixture detail with nothing to find'
    Set-PubMode -SjMode $SjPMode -SjWord 'public'
    $SjHLog = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'repo view '
    $SjHr = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Id', $SjE, '-Path', $SjPRepo)
    Add-Result 'PUB-HARNESS-CONTROL-fake-gh-answers' `
        (($SjHr.Code -eq 0) -and (Test-PubHas $SjHr.Text "$SjVis public (example/pub)") -and ((Get-PubLogCount -SjLog $SjPLog -SjPrefix 'repo view example/pub --json visibility') -eq ($SjHLog + 1))) `
        "a preview through the publish fake must exit 0, print the public line and log one visibility read; exit $($SjHr.Code)"

    # --- PUB1: one finding per planted detail, of the right category -----------------------
    $SjA = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail ('fixture detail holding ' + $SjPlain.ToUpper() + ' once')
    $SjB = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail ('fixture detail holding ' + $SjWordT + ' once')
    $SjC = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail ('fixture detail holding ' + $SjMachine.ToLower() + ' once')
    $SjD = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail ('fixture detail holding ' + $SjPathJ + ' once')
    $SjF = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail ('fixture detail holding x' + $SjWordT + 'y once')
    $SjP1 = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Path', $SjPRepo)
    $SjP1Parsed = Get-PubSections -SjText $SjP1.Text
    $SjP1Want = @(@($SjA, $SjCatList), @($SjB, $SjCatList), @($SjC, $SjCatMach), @($SjD, $SjCatPath))
    $SjP1Ok = ($SjP1.Code -eq 0)
    $SjP1Why = @()
    foreach ($SjW in $SjP1Want) {
        $SjFs = @(Get-PubFindingsOf $SjP1Parsed $SjW[0])
        if (($SjFs.Count -ne 1) -or ($SjFs[0].Category -cne $SjW[1])) { $SjP1Ok = $false; $SjP1Why += "$($SjW[0]):$($SjFs.Count)" }
    }
    $SjP1CtlE = @(Get-PubFindingsOf $SjP1Parsed $SjE).Count
    $SjP1CtlF = @(Get-PubFindingsOf $SjP1Parsed $SjF).Count
    $SjP1CtlOk = ($SjP1Parsed.Sections.ContainsKey($SjE)) -and ($SjP1Parsed.Sections.ContainsKey($SjF)) -and ($SjP1CtlE -eq 0) -and ($SjP1CtlF -eq 0) -and ($SjP1Parsed.Sections[$SjE].Count -eq 0)
    Add-Pair 'PUB1-findings-by-category' `
        $SjP1Ok "each of the four planted signals must have exactly one finding of its category in the preview; exit $($SjP1.Code), off: [$($SjP1Why -join ' ')]" `
        $SjP1CtlOk "the clean signal and the one holding the word: entry inside a longer word must have none; clean $SjP1CtlE, longer word $SjP1CtlF" `
        ($SjP1Ok -and $SjP1CtlOk) 'a planted and an unplanted signal must be answered differently, or the check finds everything or nothing'

    # --- PUB1b: with no list, the list check says so and the other two still run ------------
    Set-PubList -SjHome $SjPHome -SjLines $null
    $SjP1b = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Path', $SjPRepo)
    $SjP1bParsed = Get-PubSections -SjText $SjP1b.Text
    Set-PubList -SjHome $SjPHome -SjLines $SjList
    $SjP1bCtl = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Id', $SjE, '-Path', $SjPRepo)
    $SjNotChecked = 'private names: NOT CHECKED'
    $SjP1bCaseOk = (Test-PubHas $SjP1b.Text $SjNotChecked) -and
        (@(Get-PubFindingsOf $SjP1bParsed $SjA).Count -eq 0) -and
        (@(Get-PubFindingsOf $SjP1bParsed $SjC | Where-Object { $_.Category -ceq $SjCatMach }).Count -eq 1) -and
        (@(Get-PubFindingsOf $SjP1bParsed $SjD | Where-Object { $_.Category -ceq $SjCatPath }).Count -eq 1)
    Add-Pair 'PUB1b-no-list' `
        $SjP1bCaseOk "with no list the preview must print the NOT CHECKED line, find no list entry, and still find the machine name and the path; exit $($SjP1b.Code)" `
        (($SjP1bCtl.Code -eq 0) -and -not (Test-PubHas $SjP1bCtl.Text $SjNotChecked)) "with the list in place there must be no NOT CHECKED line; exit $($SjP1bCtl.Code)" `
        ((Test-PubHas $SjP1b.Text $SjNotChecked) -ne (Test-PubHas $SjP1bCtl.Text $SjNotChecked)) 'a missing and a present list must be answered differently'

    # --- PUB1c: every other path form is a path; a near one is not ---------------------------
    $SjG  = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail ('fixture detail holding ' + 'C:' + '\' + 'Users' + '\' + 'x once')
    $SjH2 = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail ('fixture detail holding ' + 'C:' + '/' + 'Users' + '/' + 'x once')
    $SjI  = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail ('fixture detail holding ' + '/c/' + 'Users' + '/x once')
    $SjJ  = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail ('fixture detail holding ' + 'C:' + '\' + 'Usersx\y and D:\Program Files\x once')
    $SjP1c = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Path', $SjPRepo)
    $SjP1cParsed = Get-PubSections -SjText $SjP1c.Text
    $SjP1cOk = $true
    $SjP1cWhy = @()
    foreach ($SjX in @($SjG, $SjH2, $SjI)) {
        $SjFs = @(Get-PubFindingsOf $SjP1cParsed $SjX)
        if (($SjFs.Count -ne 1) -or ($SjFs[0].Category -cne $SjCatPath)) { $SjP1cOk = $false; $SjP1cWhy += "$($SjX):$($SjFs.Count)" }
    }
    $SjP1cCtl = @(Get-PubFindingsOf $SjP1cParsed $SjJ).Count
    $SjP1cCtlOk = ($SjP1cParsed.Sections.ContainsKey($SjJ) -and $SjP1cCtl -eq 0)
    Add-Pair 'PUB1c-every-path-form' `
        $SjP1cOk "the single-backslash, forward-slash and /c/ forms must each be exactly one user-path finding; off: [$($SjP1cWhy -join ' ')]" `
        $SjP1cCtlOk "a text whose Users is not a whole word, beside a path with no Users, must have none; got $SjP1cCtl" `
        ($SjP1cOk -and $SjP1cCtlOk) 'path forms and a near miss must be answered differently'
    foreach ($SjX in @($SjG, $SjH2, $SjI, $SjJ)) { Remove-Item -LiteralPath (Get-SignalPath -SjHome $SjPHome -SjId $SjX) -Force }

    # --- PUB1d: an entry the check cannot read is a finding, as section 16 refuses it -------
    Set-PubList -SjHome $SjPHome -SjLines ($SjList + @('qz"bad' + $SjSfx))
    $SjP1d = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Id', $SjE, '-Path', $SjPRepo)
    Set-PubList -SjHome $SjPHome -SjLines $SjList
    $SjP1dCtl = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Id', $SjE, '-Path', $SjPRepo)
    $SjP1dFs = @(Get-PubFindingsOf (Get-PubSections -SjText $SjP1d.Text) $SjE)
    $SjP1dCtlFs = @(Get-PubFindingsOf (Get-PubSections -SjText $SjP1dCtl.Text) $SjE)
    $SjP1dOk = ($SjP1dFs.Count -eq 1) -and ($SjP1dFs[0].Category -ceq $SjCatBad) -and ($SjP1dFs[0].ListLine -eq ($SjList.Count + 1))
    Add-Pair 'PUB1d-unreadable-entry' `
        $SjP1dOk "an entry holding a double quote must be a cannot-read finding naming its list line on a clean signal; got $($SjP1dFs.Count)" `
        ($SjP1dCtlFs.Count -eq 0) "with that line gone the same signal must have none; got $($SjP1dCtlFs.Count)" `
        ($SjP1dFs.Count -ne $SjP1dCtlFs.Count) 'a list with and without the unreadable line must be answered differently'

    # --- PUB3: the visibility line --------------------------------------------------------
    Set-PubMode -SjMode $SjPMode -SjWord 'public'
    $SjV1 = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Id', $SjE, '-Path', $SjPRepo)
    Set-PubMode -SjMode $SjPMode -SjWord 'private'
    $SjVPrivSince = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'repo view '
    $SjV2 = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Id', $SjE, '-Path', $SjPRepo)
    $SjVPrivDelta = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'repo view ') - $SjVPrivSince
    Set-PubMode -SjMode $SjPMode -SjWord ''
    $SjV3 = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Id', $SjE, '-Path', $SjPRepo)
    Set-PubMode -SjMode $SjPMode -SjWord 'private'
    $SjVBlockSince = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'repo view '
    $SjV4 = Invoke-WrapperPub @SjPubArgs -SjOutward 'block' -SjArgs @('signals-push', '-Id', $SjE, '-Path', $SjPRepo)
    $SjVBlockDelta = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'repo view ') - $SjVBlockSince
    $SjV3Ok = (Test-PubHas $SjV1.Text "$SjVis public") -and (Test-PubHas $SjV2.Text "$SjVis private") -and (Test-PubHas $SjV3.Text "$SjVis could not tell") -and
        (Test-PubHas $SjV4.Text "$SjVis could not tell") -and ($SjVBlockDelta -eq 0) -and ($SjV4.Code -eq 0)
    Add-Pair 'PUB3-visibility-line' `
        $SjV3Ok "PUBLIC, PRIVATE and a failed read must print public, private and could not tell, and KEEL_OUTWARD=block could not tell with no read logged; block log delta $SjVBlockDelta, block exit $($SjV4.Code)" `
        ($SjVPrivDelta -eq 1) "the allowed PRIVATE run must log exactly one visibility read; got $SjVPrivDelta" `
        ($SjVPrivDelta -ne $SjVBlockDelta) 'an allowed and a blocked run must differ in whether the read is made'

    # --- PUB4 (case): -Apply holds every signal while one has an uncleared finding ---------
    $SjAll = @($SjA, $SjB, $SjC, $SjD, $SjE, $SjF)
    $SjShas = Get-PubShas -SjHome $SjPHome -SjIds $SjAll
    $SjApiSince = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api '
    $SjP4 = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Apply', '-Path', $SjPRepo)
    $SjP4Api = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api ') - $SjApiSince
    $SjShasAfter = Get-PubShas -SjHome $SjPHome -SjIds $SjAll
    $SjP4Same = $true
    foreach ($SjX in $SjAll) { if ($SjShas[$SjX] -ne $SjShasAfter[$SjX]) { $SjP4Same = $false } }
    $SjApiSince2 = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api '
    $SjP4b = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Apply', '-Id', $SjE, '-Path', $SjPRepo)
    $SjP4bApi = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api ') - $SjApiSince2
    $SjP4bRec = Get-SignalRecord -SjHome $SjPHome -SjId $SjE
    $SjP4bIssue = 0
    if (Test-HasKey $SjP4bRec 'issue') { $SjP4bIssue = [int]$SjP4bRec.issue }
    $SjP4CaseOk = ($SjP4.Code -eq 95) -and ($SjP4Api -eq 0) -and $SjP4Same -and (Test-PubHas $SjP4.Text $SjVis) -and
        ($SjP4b.Code -eq 0) -and ($SjP4bApi -eq 1) -and ($SjP4bIssue -eq 101) -and (Test-PubHas $SjP4b.Text $SjVis)
    $SjP4CaseWhy = "held -Apply exit $($SjP4.Code) (want 95), posts $SjP4Api (want 0), records unchanged $SjP4Same; -Apply -Id clean exit $($SjP4b.Code), posts $SjP4bApi (want 1), issue $SjP4bIssue"

    # --- PUB2: a finding never prints the text it found -------------------------------------
    $SjTerms = @($SjPlain, $SjWordT, $SjMachine, $SjPathJ)
    $SjRestText = (@($SjP1Parsed.Rest) + @($SjP1Parsed.Sections.Values | ForEach-Object { $_.Findings })) -join "`n"
    $SjInText = (@($SjP1Parsed.Sections.Values | ForEach-Object { $_.Body })) -join "`n"
    $SjP2Leak = @($SjTerms | Where-Object { (Test-PubHas $SjRestText $_) -or (Test-PubHas $SjP4.Text $_) }).Count
    $SjP2Shape = $true
    $SjP2Why = @()
    foreach ($SjW in $SjP1Want) {
        $SjSecW = $SjP1Parsed.Sections[$SjW[0]]
        $SjFs = @(Get-PubFindingsOf $SjP1Parsed $SjW[0])
        if ($SjFs.Count -ne 1) { $SjP2Shape = $false; continue }
        $SjBodyLines = @($SjSecW.Body)
        $SjBodyStart = [array]::IndexOf($SjBodyLines, 'BODY:')
        $SjBodyAt = -1
        for ($SjK = $SjBodyStart + 1; $SjK -lt $SjBodyLines.Count; $SjK++) {
            if ($SjBodyLines[$SjK] -like 'fixture detail holding*') { $SjBodyAt = $SjK - $SjBodyStart; break }
        }
        if (($SjFs[0].Id -ne $SjW[0]) -or ($SjFs[0].Places -cne "title, body line $SjBodyAt")) { $SjP2Shape = $false; $SjP2Why += "$($SjW[0]):[$($SjFs[0].Places)] want body line $SjBodyAt" }
    }
    $SjP2CtlIn = @($SjTerms | Where-Object { Test-PubHas $SjInText $_ }).Count
    Add-Pair 'PUB2-findings-never-print-the-text' `
        (($SjP2Leak -eq 0) -and $SjP2Shape) "no planted term may occur outside the per-signal text or in the held -Apply's output, and each finding must name its id and places; leaks $SjP2Leak, shape $SjP2Shape [$($SjP2Why -join ' ')]" `
        ($SjP2CtlIn -eq $SjTerms.Count) "every planted term must occur in the per-signal text, so the search can find one; found $SjP2CtlIn of $($SjTerms.Count)" `
        (($SjP2CtlIn -eq $SjTerms.Count) -and ($SjP2Leak -eq 0) -and $SjP2Shape) 'the same search must find every term inside the text and none outside it, beside findings that name their places'

    # --- PUB5: a clearance is for one signal, with a reason, and is recorded -------------
    $SjReason = 'fixture reason one, read by the operator'
    $SjOthers = @($SjB, $SjC, $SjD)
    $SjShas5 = Get-PubShas -SjHome $SjPHome -SjIds $SjOthers
    $SjApi5 = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api '
    $SjP5a = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Apply', '-Id', $SjA, '-Clearance', $SjReason, '-Path', $SjPRepo)
    $SjApi5a = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api ') - $SjApi5
    $SjP5Rec = Get-SignalRecord -SjHome $SjPHome -SjId $SjA
    $SjApi5b0 = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api '
    $SjP5b = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Apply', '-Clearance', $SjReason, '-Path', $SjPRepo)
    $SjP5c = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Apply', '-Id', $SjB, '-Clearance', ' ', '-Path', $SjPRepo)
    $SjApi5bc = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api ') - $SjApi5b0
    $SjShas5After = Get-PubShas -SjHome $SjPHome -SjIds $SjOthers
    $SjP5Same = $true
    foreach ($SjX in $SjOthers) { if ($SjShas5[$SjX] -ne $SjShas5After[$SjX]) { $SjP5Same = $false } }
    $SjP5Reason = ''
    if (Test-HasKey $SjP5Rec 'pushClearance') { $SjP5Reason = [string]$SjP5Rec.pushClearance.reason }
    Add-Pair 'PUB5-clearance-is-per-signal' `
        (($SjP5a.Code -eq 0) -and ($SjApi5a -eq 1) -and ($SjP5Reason -ceq $SjReason) -and ($SjP5b.Code -eq 90) -and ($SjP5c.Code -eq 95) -and ($SjApi5bc -eq 0)) `
        "a clearance with -Id and a reason must post once and record the reason; without -Id 90, with no reason 95, neither posting; exits $($SjP5a.Code)/$($SjP5b.Code)/$($SjP5c.Code), posts $SjApi5a then $SjApi5bc" `
        $SjP5Same 'the other planted records must be byte-unchanged' `
        (($SjP5Reason -ceq $SjReason) -and $SjP5Same) 'the cleared record must change and the others must not'

    # Clear and push the machine-name signal too, so one body the fake received carries the name.
    $SjP5d = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Apply', '-Id', $SjC, '-Clearance', 'fixture reason two', '-Path', $SjPRepo)

    # --- PUB6: the Machine row is a code -------------------------------------------------
    $SjBodies1 = @(Get-PubBodies -SjBodies $SjPBod | Where-Object { Test-HasKey $_ 'title' })
    $null = New-PubSignal -SjRepo $SjPRepo2 -SjHome $SjPHome2 -SjGhDir $SjPGh -SjMachine $SjMachine -SjDetail 'fixture detail from the second home'
    $SjP6Two = Invoke-WrapperPub -SjHome $SjPHome2 -SjGhDir $SjPGh -SjMachine $SjMachine -SjArgs @('signals-push', '-Apply', '-Path', $SjPRepo2)
    $SjBodies2 = @(Get-PubBodies -SjBodies $SjPBod | Where-Object { Test-HasKey $_ 'title' })
    $SjCodes = @()
    foreach ($SjBo in $SjBodies2) {
        if ([string]$SjBo.body -match '(?m)^\| Machine \| (.+?) \|') { $SjCodes += $Matches[1] } else { $SjCodes += '' }
    }
    $SjCodes1 = @($SjCodes | Select-Object -First $SjBodies1.Count)
    $SjCodeTwo = ''
    if ($SjCodes.Count -gt $SjBodies1.Count) { $SjCodeTwo = $SjCodes[$SjCodes.Count - 1] }
    $SjP6Shape = (@($SjCodes | Where-Object { ($_ -cmatch '^m-[0-9a-f]{8}$') -and -not (Test-PubHas $_ $SjMachine) }).Count -eq $SjCodes.Count) -and ($SjCodes.Count -ge 4)
    $SjP6Same = (@($SjCodes1 | Sort-Object -Unique).Count -eq 1)
    $SjP6Diff = ($SjCodeTwo -ne '') -and ($SjCodes1.Count -gt 0) -and ($SjCodeTwo -ne $SjCodes1[0])
    $SjP6Names = $true
    foreach ($SjX in @($SjA, $SjC, $SjE)) { if ((Get-SignalRecord -SjHome $SjPHome -SjId $SjX).machine -cne $SjMachine) { $SjP6Names = $false } }
    $SjP6CtlHits = @($SjBodies2 | Where-Object { Test-PubHas ([string]$_.body) $SjMachine }).Count
    Add-Pair 'PUB6-machine-code' `
        ($SjP6Shape -and $SjP6Same -and $SjP6Diff -and $SjP6Names -and ($SjP5d.Code -eq 0) -and ($SjP6Two.Code -eq 0)) `
        "every Machine row must be m- and eight hex, never the machine name, one code per home and another from the second home, and each record must keep the name; rows $($SjCodes.Count), shape $SjP6Shape, same $SjP6Same, differs $SjP6Diff, names kept $SjP6Names, exits $($SjP5d.Code)/$($SjP6Two.Code)" `
        ($SjP6CtlHits -ge 1) "the same search over the same bodies must find the machine name in the cleared signal's text; found it in $SjP6CtlHits" `
        ($SjP6Shape -and ($SjP6CtlHits -ge 1)) 'the name must be findable in the bodies and absent from every Machine row'

    # --- PUB6b: a code file that holds no code is refused, not replaced --------------------
    $SjCodeFile = Join-Path (Join-Path $SjPHome2 '.keel') 'machine-code.txt'
    $null = New-PubSignal -SjRepo $SjPRepo2 -SjHome $SjPHome2 -SjGhDir $SjPGh -SjMachine $SjMachine -SjDetail 'fixture detail for the code file'
    [System.IO.File]::WriteAllText($SjCodeFile, '', (New-Object System.Text.UTF8Encoding($false)))
    $SjP6b = Invoke-WrapperPub -SjHome $SjPHome2 -SjGhDir $SjPGh -SjMachine $SjMachine -SjArgs @('signals-push', '-Path', $SjPRepo2)
    Remove-Item -LiteralPath $SjCodeFile -Force
    $SjP6bCtl = Invoke-WrapperPub -SjHome $SjPHome2 -SjGhDir $SjPGh -SjMachine $SjMachine -SjArgs @('signals-push', '-Path', $SjPRepo2)
    $SjP6bNew = ''
    if (Test-Path -LiteralPath $SjCodeFile) { $SjP6bNew = ([string](Get-Content -Raw -LiteralPath $SjCodeFile)).Trim() }
    Add-Pair 'PUB6b-bad-code-file-refused' `
        (($SjP6b.Code -eq 96) -and (Test-PubHas $SjP6b.Text 'machine-code.txt')) "an empty machine-code.txt must refuse the preview at 96 naming the file; exit $($SjP6b.Code)" `
        (($SjP6bCtl.Code -eq 0) -and ($SjP6bNew -cmatch '^m-[0-9a-f]{8}$')) "with it deleted the preview must exit 0 and leave a new code; exit $($SjP6bCtl.Code)" `
        ($SjP6b.Code -ne $SjP6bCtl.Code) 'an empty and a missing code file must be answered differently'

    # --- PUB7: the closing comment is checked ---------------------------------------------
    $SjK7 = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail 'fixture detail to resolve with a finding'
    $SjL7 = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail 'fixture detail to resolve cleanly'
    Set-LinkedRecord -SjHome $SjPHome -SjId $SjK7 -SjNum 71 -SjLink 'https://github.com/example/pub/issues/71'
    Set-LinkedRecord -SjHome $SjPHome -SjId $SjL7 -SjNum 72 -SjLink 'https://github.com/example/pub/issues/72'
    $SjResDetail = 'fixture resolution naming ' + $SjPlain
    $SjApi7 = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api '
    $SjClose7 = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'issue close '
    $SjR7a = Invoke-WrapperPub @SjPubArgs -SjArgs @('resolve-signal', '-Id', $SjK7, '-As', 'REJECTED', '-Detail', $SjResDetail, '-CloseIssue', '-Path', $SjPRepo)
    $SjR7aApi = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api ') - $SjApi7
    $SjR7aClose = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'issue close ') - $SjClose7
    $SjR7aRec = Get-SignalRecord -SjHome $SjPHome -SjId $SjK7
    $SjR7b = Invoke-WrapperPub @SjPubArgs -SjArgs @('resolve-signal', '-Id', $SjK7, '-As', 'REJECTED', '-Detail', $SjResDetail, '-CloseIssue', '-Clearance', 'fixture reason three', '-Path', $SjPRepo)
    $SjR7bApi = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api ') - $SjApi7 - $SjR7aApi
    $SjR7bClose = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'issue close ') - $SjClose7 - $SjR7aClose
    $SjR7bRec = Get-SignalRecord -SjHome $SjPHome -SjId $SjK7
    $SjR7Reason = ''
    if (Test-HasKey $SjR7bRec 'commentClearance') { $SjR7Reason = [string]$SjR7bRec.commentClearance.reason }
    $SjApi7c = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api '
    $SjClose7c = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'issue close '
    $SjR7c = Invoke-WrapperPub @SjPubArgs -SjArgs @('resolve-signal', '-Id', $SjL7, '-As', 'REJECTED', '-Detail', 'fixture clean resolution', '-CloseIssue', '-Path', $SjPRepo)
    $SjR7cApi = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api ') - $SjApi7c
    $SjR7cClose = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'issue close ') - $SjClose7c
    $SjR7CaseOk = ($SjR7a.Code -eq 0) -and ($SjR7aRec.state -eq 'REJECTED') -and ($SjR7aApi -eq 0) -and ($SjR7aClose -eq 0) -and
        (Test-PubHas $SjR7a.Text '-Clearance') -and (Test-PubHas $SjR7a.Text $SjVis) -and
        ($SjR7b.Code -eq 0) -and ($SjR7bApi -eq 1) -and ($SjR7bClose -eq 1) -and ($SjR7Reason -ceq 'fixture reason three')
    Add-Pair 'PUB7-close-comment-checked' `
        $SjR7CaseOk "a resolution holding a list entry must be recorded with no comment and no close, naming -Clearance and the visibility line; then cleared, one comment and one close with the reason stored; first exit $($SjR7a.Code) posts $SjR7aApi closes $SjR7aClose, cleared exit $($SjR7b.Code) posts $SjR7bApi closes $SjR7bClose" `
        (($SjR7c.Code -eq 0) -and ($SjR7cApi -eq 1) -and ($SjR7cClose -eq 1)) "a clean resolution must comment and close on the first call; exit $($SjR7c.Code), posts $SjR7cApi, closes $SjR7cClose" `
        ($SjR7aApi -ne $SjR7cApi) 'a held and a clean comment must be answered differently'

    # --- PUB4 (control): with the planted signals removed, every remaining signal is sent ---
    foreach ($SjX in @($SjB, $SjD)) { Remove-Item -LiteralPath (Get-SignalPath -SjHome $SjPHome -SjId $SjX) -Force }
    $null = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail 'fixture detail clean two'
    $null = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail 'fixture detail clean three'
    $SjPending = @(Get-ChildItem -LiteralPath (Join-Path (Join-Path $SjPHome '.keel') 'signals') -Filter 'S*.json' | ForEach-Object {
        Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json } | Where-Object { ($_.state -eq 'OPEN') -and ((-not (Test-HasKey $_ 'issue')) -or ($null -eq $_.issue)) }).Count
    $SjApi4c = Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api '
    $SjP4c = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Apply', '-Path', $SjPRepo)
    $SjP4cApi = (Get-PubLogCount -SjLog $SjPLog -SjPrefix 'api ') - $SjApi4c
    Add-Pair 'PUB4-apply-holds' `
        $SjP4CaseOk $SjP4CaseWhy `
        (($SjP4c.Code -eq 0) -and ($SjP4cApi -eq $SjPending) -and ($SjPending -ge 3)) "with the planted signals removed, -Apply must exit 0 and post each of the $SjPending pending signals; exit $($SjP4c.Code), posts $SjP4cApi" `
        ($SjP4.Code -ne $SjP4c.Code) 'a store holding a finding and one without must be answered differently'

    # --- PUB9: the wrapper flags the list lines section 16 flags ----------------------------
    $SjText9  = 'start ' + $SjPlain.ToUpper() + ' mid ' + $SjWordT + ' and ' + $SjNearT.ToLower() + ' end'
    $SjText9b = 'start ' + $SjPlain.ToUpper() + ' mid ' + $SjWordT + ' and ' + $SjNearT + ' end'
    $SjS9  = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail $SjText9
    $SjS9b = New-PubSignal -SjRepo $SjPRepo @SjPubArgs -SjDetail $SjText9b
    $SjSec16  = @(Get-Section16Lines -SjRoot $SjTempRoot -SjHome $SjPHome -SjTextLine $SjText9)
    $SjSec16b = @(Get-Section16Lines -SjRoot $SjTempRoot -SjHome $SjPHome -SjTextLine $SjText9b)
    $SjW9  = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Id', $SjS9, '-Path', $SjPRepo)
    $SjW9b = Invoke-WrapperPub @SjPubArgs -SjArgs @('signals-push', '-Id', $SjS9b, '-Path', $SjPRepo)
    $SjWr9  = @(Get-PubFindingsOf (Get-PubSections -SjText $SjW9.Text) $SjS9 | Where-Object { $_.Category -ceq $SjCatList } | ForEach-Object { $_.ListLine } | Sort-Object -Unique)
    $SjWr9b = @(Get-PubFindingsOf (Get-PubSections -SjText $SjW9b.Text) $SjS9b | Where-Object { $_.Category -ceq $SjCatList } | ForEach-Object { $_.ListLine } | Sort-Object -Unique)
    $SjS9Ok  = (($SjSec16 -join ',') -eq ($SjWr9 -join ',')) -and (($SjSec16 -join ',') -eq '2,3')
    $SjS9bOk = (($SjSec16b -join ',') -eq ($SjWr9b -join ',')) -and (($SjSec16b -join ',') -eq '2,3,4')
    Add-Pair 'PUB9-matches-section-16' `
        $SjS9Ok "section 16 and the wrapper must flag the same list lines, the plain and the first word: entry and not the near miss; section 16 [$($SjSec16 -join ',')], wrapper [$($SjWr9 -join ',')]" `
        $SjS9bOk "with the near miss in the entry's own case both must flag it too; section 16 [$($SjSec16b -join ',')], wrapper [$($SjWr9b -join ',')]" `
        ((($SjWr9 -join ',') -ne ($SjWr9b -join ',')) -and (($SjSec16 -join ',') -ne ($SjSec16b -join ','))) 'the wrapper and section 16 must each answer the near miss and the exact word differently'
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
    if (-not $LinkOnly -and -not $PublishOnly) { Invoke-Cases -SjTempRoot $SjTempRoot }
    if (-not $PublishOnly) { Invoke-LinkCases -SjTempRoot $SjTempRoot }
    if (-not $LinkOnly) { Invoke-PublishCases -SjTempRoot $SjTempRoot }

    foreach ($SjResult in @($script:SjResults)) {
        if (-not $SjResult.Ok) {
            $SjFailed++
            Write-Output ("  FAIL  {0,-46} {1}" -f $SjResult.Name, $SjResult.Why)
        }
        if ($SjResult.Name -eq 'HARNESS-CONTROL-judge-signal-succeeds') { $SjHarnessOk = $SjResult.Ok }
        if ($SjResult.Name -eq 'HARNESS-CONTROL-store-is-sandboxed')    { $SjSandboxOk = $SjResult.Ok }
    }

    if ($LinkOnly -or $PublishOnly) { $SjHarnessOk = $true; $SjSandboxOk = $true }
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
