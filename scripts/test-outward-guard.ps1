# test-outward-guard.ps1 - the suite for the FIVE outward code points: the process
# invocations in keel-state.ps1 that leave the machine.
#
# WHY THIS EXISTS AND WHY IT IS A SIBLING rather than three more cases inside
# test-quarantine.ps1. That suite's subject is the three QUARANTINE code points, and
# quarantine is a per-project flag declared in keel.json; a sandboxed state home is a
# per-run ENVIRONMENT property. Two unrelated questions in one file is the charter P10
# error, and its case count would stop meaning one thing. That is not a fresh argument:
# check-suite-docs.ps1 section 11 answers the identical question the same way, keeping
# the charter gate's suite separate from quarantine's for exactly this reason. Departing
# from it would need an argument that this reason does not apply, and there is none - the
# outward guard shares no machinery with quarantine either.
#
# WHAT IT COVERS. Five process invocations across four verbs, found by an AST parse of the
# whole wrapper:
#
#   1  signals-push -Apply           gh api --method POST repos/<slug>/issues      exit 90
#   2  adopt-signal                  gh issue view <n> --repo <slug>               exit 90
#   3  resolve-signal -CloseIssue    gh api --method POST .../issues/<n>/comments  exit 0
#   4  resolve-signal -CloseIssue    gh issue close <n> --repo <slug>              exit 0
#   5  status                        git -C <root> ls-remote origin <ref>          exit 0
#
# Rows 3 and 4 are TWO CALLS INSIDE ONE VERB. A case that exercises the verb once and
# asserts one declined command covers row 3 and leaves row 4 untested, which is why the
# row-3/4 case asserts BOTH command strings.
#
# THREE LIMBS PER GROUP, and none of them touches the network - which is the whole point,
# since the defect being guarded is that a fixture CAN touch it:
#
#   1. The case          scratch home under %TEMP%, KEEL_OUTWARD unset, an outward verb
#                        -> the guard's own message, and the verb's UNCHANGED exit code.
#   2. The scope control the same home, a NON-outward path -> exit 0 and NO guard text.
#                        A refusal that refuses everybody is indistinguishable from one
#                        that reads the flag. This is the limb an offline-mode suite is
#                        most likely to skip, because "it refused" reads as a pass.
#   3. The reason control the same home, KEEL_OUTWARD=allow, and the verb's OTHER refusal
#                        provoked -> that other refusal's text and NOT the guard's. This
#                        is what makes the case limb's absence assertion honest: it proves
#                        the string the case asserts is ABSENT is one this suite can
#                        actually produce. An absence assertion whose string is unreachable
#                        by any limb passes for the wrong reason.
#
# THE REASON CONTROL'S STRING DIFFERS BY VERB, and getting that wrong is an easy trap. The
# three gh verbs share one: each refuses, or at resolve-signal declines, with 'No report
# destination is chosen' when no destination was chosen, and that is a real non-guard
# outcome on the same path. status resolves no gh and no destination at all - its
# false-reason string is "COULD NOT REACH the remote". Each is asserted against the group
# that can actually print it.
#
# THE REASON CONTROL CANNOT USE 'GitHub CLI not found'. Making gh unresolvable by pointing
# PATH and the three fallback roots Resolve-Gh reads at an empty scratch directory DOES NOT
# WORK on the machine this was measured on: $env:ProgramFiles did not reach a child
# process as set. A parent-process assignment, a `cmd /c set` and an explicit
# ProcessStartInfo.EnvironmentVariables entry each gave the child C:\Program Files back.
# Where gh is installed under Program Files, Resolve-Gh's SECOND fallback finds it whatever
# PATH says, and 'GitHub CLI not found' is unreachable from any child-process test. A control
# designed from READING Resolve-Gh rather than from running it misses this.
#
# WHAT IS USED INSTEAD, and why it is the same kind of control. The destination is a file
# in the scratch home, set by the fixture with 'signals-target'. So each reason control
# CLEARS that destination for its one run - and checks the file is actually gone, not just
# that the clear exited 0 - and the verb takes its genuine no-destination outcome. That is
# a real non-guard outcome from the same verb on the same path, so it discriminates the
# guard's message from a neighbouring one. PATH is still blinded on those runs, so no git
# is reachable either.
#
# NO ROW CAN REACH THE REAL gh, and that does not rest on the guard alone. The suite
# writes a fake gh.cmd into its scratch root that logs its arguments and exits 7, and
# every child runs with that folder FIRST on PATH (the blind folder carries a copy). Program
# Files cannot be hidden from a child (above), but Resolve-Gh asks PATH first, so the fake
# always wins. No row is supposed to run gh at all - guarded rows stop at the guard, reason
# controls stop at the destination check, the preview never calls it - so Invoke-Cases ends
# by THROWING if the fake's log is not empty. The throw leaves no summary line, which
# check-suite-docs.ps1 section 14 reports as a problem. Without the fake, a broken guard
# would post fixture issues with the operator's own credentials.
#
# GROUP 6 IS NOT AN OUTWARD POINT. It pins the shape check on a per-call -Repo with a case
# and a control on one open signal, and it lives here because the value it checks is the
# destination every outward row above depends on.
#
# THE ASSERTIONS ON 'GitHub CLI not found' ARE KEPT AND ARE LABELLED. They cost nothing and
# they would catch a future guard that reached for that string, but with no live control
# behind them they are assertions this suite CANNOT prove able to fire, which is the shape
# that passes for the wrong reason. The load-bearing absence assertion in each group is the
# one paired with a reachable string.
#
# Because PATH is emptied, powershell.exe itself must be invoked BY FULL PATH - $PSHOME -
# or the child never starts, and a child that never starts returns an exit code no wrapper
# can produce, which reads as a refusal.
#
# Every local in this file is Og-prefixed. PowerShell variable names are case-insensitive,
# so a local whose name matches a param() name IS that parameter, and two ordinary locals
# collide the same way.

param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$OgRepoRoot     = Split-Path -Parent $PSScriptRoot
$OgStateWrapper = Join-Path $OgRepoRoot 'plugins\keel-workflow\skills\keel-orchestrator\wrappers\keel-state.ps1'

# By full path, deliberately: the reason-control limb empties PATH, and a bare
# 'powershell.exe' would then fail to launch at all.
$OgPwsh = Join-Path $PSHOME 'powershell.exe'

# The four strings this suite matches on. Kept here rather than inline so a wording change
# in the wrapper breaks every row at once and loudly, instead of one row quietly.
$OgGuardText    = 'Outward acts are blocked'
$OgGhMissing    = 'GitHub CLI not found'
$OgUnreachable  = 'COULD NOT REACH the remote'
$OgNoTarget     = 'No report destination is chosen'

# The destination every fixture uses. It is never contacted: the fake gh below sits first
# on PATH for every child.
$OgFixtureTarget = 'example/fixture-target'

$script:OgResults = @()
$script:OgFakeDir = ''
$script:OgFakeLog = ''

# A PowerShell function returns everything it emits, so one that both writes output and
# returns a value hands the caller an array, which is truthy. This adds to a script-scope
# list and returns nothing at all.
function Add-Result {
    param([string]$OgName, [bool]$OgOk, [string]$OgWhy)
    $script:OgResults += [pscustomobject]@{ Name = $OgName; Ok = $OgOk; Why = $OgWhy }
}

function Set-EnvVar {
    param([string]$OgName, $OgValue)
    if ($null -eq $OgValue) { Remove-Item -LiteralPath "Env:\$OgName" -ErrorAction SilentlyContinue }
    else { Set-Item -LiteralPath "Env:\$OgName" -Value $OgValue }
}

# A native tool's success text can arrive on stderr, and a bare 2>&1 under 'Stop' turns
# that into a terminating error. Set Continue around the call and let the EXIT CODE decide.
# No output-encoding override is taken: nothing matched on here is non-ASCII, and this
# compares rather than persists.
function Invoke-Wrapper {
    param(
        [string[]]$OgArgs,
        [string]$OgHome,
        [string]$OgOutward = '',
        [string]$OgBlindDir = '',
        [string]$OgTempDir = ''
    )

    $OgPrevProfile = $env:USERPROFILE
    $OgPrevTemp    = $env:TEMP
    $OgPrevOutward = $env:KEEL_OUTWARD
    $OgPrevPath    = $env:PATH
    $OgPrevPf      = $env:ProgramFiles
    $OgPrevPf86    = ${env:ProgramFiles(x86)}
    $OgPrevLocal   = $env:LOCALAPPDATA
    $OgPrevPref    = $ErrorActionPreference

    $OgLines = @()
    $OgCode  = 0
    try {
        Set-EnvVar 'USERPROFILE' $OgHome
        # Moving TEMP is how the override is tested in the BLOCK direction: it takes the
        # state home out of TEMP's subtree, so the automatic rule stays off and only
        # KEEL_OUTWARD can engage the guard.
        if (-not [string]::IsNullOrEmpty($OgTempDir)) { Set-EnvVar 'TEMP' $OgTempDir }
        if ([string]::IsNullOrEmpty($OgOutward)) { Set-EnvVar 'KEEL_OUTWARD' $null }
        else { Set-EnvVar 'KEEL_OUTWARD' $OgOutward }

        if (-not [string]::IsNullOrEmpty($OgBlindDir)) {
            # The blind folder holds a copy of the fake gh, so even here gh resolves to it.
            Set-EnvVar 'PATH'              $OgBlindDir
            Set-EnvVar 'ProgramFiles'      $OgBlindDir
            Set-EnvVar 'ProgramFiles(x86)' $OgBlindDir
            Set-EnvVar 'LOCALAPPDATA'      $OgBlindDir
        }
        elseif (-not [string]::IsNullOrEmpty($script:OgFakeDir)) {
            Set-EnvVar 'PATH' ($script:OgFakeDir + ';' + $OgPrevPath)
        }

        $ErrorActionPreference = 'Continue'
        $OgLines = & $OgPwsh -NoProfile -ExecutionPolicy Bypass -File $OgStateWrapper @OgArgs 2>&1 |
                   ForEach-Object { $_.ToString() }
        $OgCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $OgPrevPref
        Set-EnvVar 'USERPROFILE'      $OgPrevProfile
        Set-EnvVar 'TEMP'             $OgPrevTemp
        Set-EnvVar 'KEEL_OUTWARD'     $OgPrevOutward
        Set-EnvVar 'PATH'             $OgPrevPath
        Set-EnvVar 'ProgramFiles'     $OgPrevPf
        Set-EnvVar 'ProgramFiles(x86)' $OgPrevPf86
        Set-EnvVar 'LOCALAPPDATA'     $OgPrevLocal
    }

    return [pscustomobject]@{ Code = $OgCode; Text = (@($OgLines) -join "`n") }
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
function New-Fixture {
    param([string]$OgRepo, [string]$OgHome, [switch]$OgGitRepo)

    New-Item -ItemType Directory -Path $OgRepo -Force | Out-Null

    $OgInit = Invoke-Wrapper -OgHome $OgHome -OgArgs @(
        'init-project', '-Title', 'outward guard fixture', '-Path', $OgRepo, '-Tracker', 'none')
    if ($OgInit.Code -ne 0) { throw "fixture init-project failed (exit $($OgInit.Code)): $($OgInit.Text)" }

    foreach ($OgStep in @(
        @('add-goal',       '-Id', 'G1',     '-Text',  'fixture goal'),
        @('add-workstream', '-Id', 'W1',     '-Title', 'fixture workstream', '-Parent', 'root', '-Goals', 'G1'),
        @('add-phase',      '-Phase', 'W1.1', '-Scope', 'fixture phase', '-Actor', 'agent', '-RunOrder', '1')
    )) {
        $OgStepArgs = @($OgStep) + @('-Path', $OgRepo)
        $OgRes = Invoke-Wrapper -OgHome $OgHome -OgArgs $OgStepArgs
        if ($OgRes.Code -ne 0) { throw "fixture step '$($OgStep[0])' failed (exit $($OgRes.Code)): $($OgRes.Text)" }
    }

    if ($OgGitRepo) {
        # A real git repo with one commit and an origin that resolves to a path which does
        # NOT exist. That makes ls-remote fail LOCALLY, at exit 128, with no network call -
        # which is what lets the site-5 reason control produce the real "COULD NOT REACH"
        # string without reaching any remote.
        & git -C $OgRepo init -q 2>&1 | Out-Null
        Set-Content -LiteralPath (Join-Path $OgRepo 'fixture.txt') -Value 'fixture' -Encoding ASCII
        & git -C $OgRepo add -A 2>&1 | Out-Null
        & git -C $OgRepo -c user.email='fixture@example.invalid' -c user.name='fixture' commit -q -m 'fixture commit' 2>&1 | Out-Null
        & git -C $OgRepo remote add origin (Join-Path $OgRepo 'no-such-remote-directory') 2>&1 | Out-Null
    }
}

# Files a signal through the wrapper and returns its allocated id.
#
# THE ISSUE NUMBER IS THEN WRITTEN DIRECTLY, and that is deliberate rather than lazy.
# resolve-signal reaches rows 3 and 4 only when the record carries an 'issue', and exactly
# ONE site in the wrapper writes that field - inside signals-push -Apply, after a
# successful push - plus adopt-signal's freshly built record. Both are outward. Every verb
# was enumerated and none sets it offline, so a suite forbidden to touch the network
# cannot reach rows 3 and 4 without constructing the precondition itself. The write lands
# in a throwaway store under %TEMP% that this script creates and deletes; charter P15's
# subject is a real project's state, and the same fixture-builds-its-own-precondition
# move is already made by New-Fixture in test-quarantine.ps1, which writes its fixture's
# keel.json directly because the wrapper writes no 'docs' key.
function New-SignalWithIssue {
    param([string]$OgRepo, [string]$OgHome, [int]$OgIssueNum)

    $OgFiled = Invoke-Wrapper -OgHome $OgHome -OgArgs @(
        'signal', '-Kind', 'gap', '-Phase', 'W1.1',
        '-Detail', 'outward guard fixture signal',
        '-Evidence', 'scripts/test-outward-guard.ps1 - fixture, no real defect',
        '-Path', $OgRepo)
    if ($OgFiled.Code -ne 0) { throw "fixture signal failed (exit $($OgFiled.Code)): $($OgFiled.Text)" }

    $OgSid = ''
    foreach ($OgLine in @($OgFiled.Text -split "`n")) {
        if ($OgLine -match 'Filed signal\s+(S\d{4})') { $OgSid = $Matches[1]; break }
    }
    if ($OgSid -eq '') { throw "could not read the filed signal id from: $($OgFiled.Text)" }

    $OgSigPath = Join-Path (Join-Path (Join-Path $OgHome '.keel') 'signals') "$OgSid.json"
    if (-not (Test-Path -LiteralPath $OgSigPath)) { throw "fixture signal record not found at $OgSigPath" }
    $OgSig = Get-Content -Raw -LiteralPath $OgSigPath | ConvertFrom-Json
    # An empty or truncated file parses to $null without throwing, so the crash would
    # otherwise land on the first property access below.
    if ($null -eq $OgSig) { throw "fixture signal record at $OgSigPath parsed to null" }
    Add-Member -InputObject $OgSig -NotePropertyName 'issue' -NotePropertyValue $OgIssueNum -Force
    Add-Member -InputObject $OgSig -NotePropertyName 'pushedAt' -NotePropertyValue '2026-01-01T00:00:00' -Force
    [System.IO.File]::WriteAllText($OgSigPath, ($OgSig | ConvertTo-Json -Depth 14), (New-Object System.Text.UTF8Encoding($false)))

    return $OgSid
}

# Writes the fake gh into $OgDir. It logs every call and refuses, so a row that reaches gh
# shows up in the log instead of on GitHub. With PATH holding only such a folder,
# Get-Command gh returns the fake, and running it exits 7 and logs.
function New-FakeGh {
    param([string]$OgDir, [string]$OgLogPath)
    New-Item -ItemType Directory -Path $OgDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $OgDir 'gh.cmd') -Encoding ASCII -Value @(
        '@echo off',
        ('echo %*>>"' + $OgLogPath + '"'),
        'echo fake gh: test-outward-guard.ps1 never calls GitHub 1>&2',
        'exit /b 7')
}

# The destination lives in the scratch home's state folder. Setting it is a wrapper call;
# clearing it is a wrapper call followed by a DIRECT check that the file is gone, because
# a reason control runs with KEEL_OUTWARD=allow and must not rely on an exit code alone to
# know it has no destination.
function Set-FixtureTarget {
    param([string]$OgHome)
    $OgSet = Invoke-Wrapper -OgHome $OgHome -OgArgs @('signals-target', '-Repo', $OgFixtureTarget)
    $OgFile = Join-Path (Join-Path $OgHome '.keel') 'signals-target.txt'
    if ($OgSet.Code -ne 0 -or -not (Test-Path -LiteralPath $OgFile)) {
        throw "fixture signals-target -Repo failed (exit $($OgSet.Code)): $($OgSet.Text)"
    }
}

function Clear-FixtureTarget {
    param([string]$OgHome)
    $OgClr = Invoke-Wrapper -OgHome $OgHome -OgArgs @('signals-target', '-Clear')
    $OgFile = Join-Path (Join-Path $OgHome '.keel') 'signals-target.txt'
    if ($OgClr.Code -ne 0 -or (Test-Path -LiteralPath $OgFile)) {
        throw "fixture signals-target -Clear did not remove $OgFile (exit $($OgClr.Code)): $($OgClr.Text)"
    }
}

# ---------------------------------------------------------------------------
# The cases
# ---------------------------------------------------------------------------
function Invoke-Cases {
    param([string]$OgTempRoot)

    $OgHome   = Join-Path $OgTempRoot 'home'
    $OgRepo   = Join-Path $OgTempRoot 'fixture-project'
    $OgGit    = Join-Path $OgTempRoot 'fixture-gitrepo'
    $OgBlind  = Join-Path $OgTempRoot 'blind'
    New-Item -ItemType Directory -Path $OgBlind -Force | Out-Null

    # The fake gh first, before any child runs, and a copy in the blind folder.
    $script:OgFakeLog = Join-Path $OgTempRoot 'fake-gh.log'
    $script:OgFakeDir = Join-Path $OgTempRoot 'fake-gh'
    New-FakeGh -OgDir $script:OgFakeDir -OgLogPath $script:OgFakeLog
    New-FakeGh -OgDir $OgBlind -OgLogPath $script:OgFakeLog

    New-Fixture -OgRepo $OgRepo -OgHome $OgHome
    New-Fixture -OgRepo $OgGit  -OgHome $OgHome -OgGitRepo

    # Every guarded row needs a destination to get as far as the guard.
    Set-FixtureTarget -OgHome $OgHome

    # =====================================================================
    # GROUP 1 - signals-push -Apply (row 1)
    # =====================================================================

    # A pending OPEN, un-pushed signal must exist FIRST. Without one, signals-push returns
    # at "Nothing to push - every open signal already has an issue" - which sits BEFORE the
    # preview branch and before the guard - at exit 0. Both the case and its scope control
    # would then pass for a reason that has nothing to do with the guard, and the scope
    # control would be green whatever the guard does. That is the failure the scope control
    # exists to catch, arriving inside the suite itself.
    $OgPushArgs = @('signals-push', '-Apply', '-Path', $OgRepo)
    [void](New-SignalWithIssue -OgRepo $OgRepo -OgHome $OgHome -OgIssueNum 0)
    # New-SignalWithIssue stamps an issue, which would make it non-pending. File a second,
    # untouched one for the push to find.
    $OgPushFiled = Invoke-Wrapper -OgHome $OgHome -OgArgs @(
        'signal', '-Kind', 'gap', '-Phase', 'W1.1',
        '-Detail', 'outward guard fixture pending signal',
        '-Evidence', 'scripts/test-outward-guard.ps1 - fixture, no real defect',
        '-Path', $OgRepo)
    if ($OgPushFiled.Code -ne 0) { throw "fixture pending signal failed (exit $($OgPushFiled.Code)): $($OgPushFiled.Text)" }

    # --- HARNESS CONTROL ---------------------------------------------------
    # If the guard does not engage on the most outward act in the suite, nothing else
    # measured below means anything - the run has not reached the mechanism at all.
    $OgG1Case = Invoke-Wrapper -OgHome $OgHome -OgArgs $OgPushArgs
    Add-Result 'HARNESS-CONTROL-signals-push-guarded' `
               ($OgG1Case.Text -like "*$OgGuardText*") `
               "exit $($OgG1Case.Code); wanted the guard's text in the output"

    Add-Result 'G1-case-signals-push-apply-refused-90' `
               (($OgG1Case.Code -eq 90) -and ($OgG1Case.Text -like "*$OgGuardText*")) `
               "exit $($OgG1Case.Code), wanted 90 with the guard's text"
    Add-Result 'G1-case-names-the-declined-command' `
               ($OgG1Case.Text -like '*gh api --method POST repos/*/issues*') `
               'wanted the literal declined command named in the message'
    # UNCONTROLLED BY DESIGN - see the header. 'GitHub CLI not found' is unreachable from a
    # child process on a machine with gh under Program Files, so this row cannot be shown
    # able to fire. G1-reason-control- above is the load-bearing one.
    Add-Result 'G1-case-does-NOT-claim-gh-missing-UNCONTROLLED' `
               (-not ($OgG1Case.Text -like "*$OgGhMissing*")) `
               "wanted '$OgGhMissing' ABSENT - the guard must not claim a false reason"

    # --- scope control: the PREVIEW is local and must be untouched ----------
    # Asserted on the preview's own text, not merely on exit 0: exit 0 alone is also what
    # the "Nothing to push" early return produces, so a control keyed on the code would be
    # satisfied without ever reaching the branch it is meant to prove is unguarded.
    $OgG1Prev = Invoke-Wrapper -OgHome $OgHome -OgArgs @('signals-push', '-Path', $OgRepo)
    Add-Result 'G1-scope-control-preview-not-guarded' `
               (($OgG1Prev.Code -eq 0) -and ($OgG1Prev.Text -like '*PREVIEW ONLY*') -and
                (-not ($OgG1Prev.Text -like "*$OgGuardText*"))) `
               "exit $($OgG1Prev.Code), wanted 0 with 'PREVIEW ONLY' and NO guard text"

    $OgG1Hand = Invoke-Wrapper -OgHome $OgHome -OgArgs @(
        'handoff', '-Next', 'fixture next', '-Detail', 'fixture detail', '-Path', $OgRepo)
    Add-Result 'G1-scope-control-handoff-not-guarded' `
               (($OgG1Hand.Code -eq 0) -and (-not ($OgG1Hand.Text -like "*$OgGuardText*"))) `
               "exit $($OgG1Hand.Code), wanted 0 and NO guard text"

    # --- reason control: the OTHER refusal is still reachable ---------------
    Clear-FixtureTarget -OgHome $OgHome
    $OgG1Reason = Invoke-Wrapper -OgHome $OgHome -OgArgs $OgPushArgs -OgOutward 'allow' -OgBlindDir $OgBlind
    Set-FixtureTarget -OgHome $OgHome
    Add-Result 'G1-reason-control-other-refusal-still-produced' `
               (($OgG1Reason.Text -like "*$OgNoTarget*") -and (-not ($OgG1Reason.Text -like "*$OgGuardText*"))) `
               "exit $($OgG1Reason.Code), wanted '$OgNoTarget' PRESENT and the guard's text ABSENT"

    # =====================================================================
    # GROUP 2 - adopt-signal (row 2)
    # =====================================================================
    $OgG2Args = @('adopt-signal', '-Issue', '999999', '-Project', 'fixture-project',
                  '-Phase', 'W1.1', '-Kind', 'gap', '-Path', $OgRepo)

    $OgG2Case = Invoke-Wrapper -OgHome $OgHome -OgArgs $OgG2Args
    Add-Result 'G2-case-adopt-signal-refused-90' `
               (($OgG2Case.Code -eq 90) -and ($OgG2Case.Text -like "*$OgGuardText*")) `
               "exit $($OgG2Case.Code), wanted 90 with the guard's text"
    Add-Result 'G2-case-names-the-declined-command' `
               ($OgG2Case.Text -like '*gh issue view 999999*') `
               'wanted the literal declined command named in the message'
    # UNCONTROLLED BY DESIGN - see the header, as G1's above.
    Add-Result 'G2-case-does-NOT-claim-gh-missing-UNCONTROLLED' `
               (-not ($OgG2Case.Text -like "*$OgGhMissing*")) `
               "wanted '$OgGhMissing' ABSENT"

    $OgG2Scope = Invoke-Wrapper -OgHome $OgHome -OgArgs @(
        'signal', '-Kind', 'gap', '-Phase', 'W1.1',
        '-Detail', 'scope control signal', '-Evidence', 'scripts/test-outward-guard.ps1 - fixture',
        '-Path', $OgRepo)
    Add-Result 'G2-scope-control-signal-not-guarded' `
               (($OgG2Scope.Code -eq 0) -and (-not ($OgG2Scope.Text -like "*$OgGuardText*"))) `
               "exit $($OgG2Scope.Code), wanted 0 and NO guard text"

    Clear-FixtureTarget -OgHome $OgHome
    $OgG2Reason = Invoke-Wrapper -OgHome $OgHome -OgArgs $OgG2Args -OgOutward 'allow' -OgBlindDir $OgBlind
    Set-FixtureTarget -OgHome $OgHome
    Add-Result 'G2-reason-control-other-refusal-still-produced' `
               (($OgG2Reason.Text -like "*$OgNoTarget*") -and (-not ($OgG2Reason.Text -like "*$OgGuardText*"))) `
               "exit $($OgG2Reason.Code), wanted '$OgNoTarget' PRESENT and the guard's text ABSENT"

    # =====================================================================
    # GROUP 3 - resolve-signal -CloseIssue (rows 3 AND 4, one verb, two calls)
    # =====================================================================
    $OgG3Sid = New-SignalWithIssue -OgRepo $OgRepo -OgHome $OgHome -OgIssueNum 424242
    $OgG3Case = Invoke-Wrapper -OgHome $OgHome -OgArgs @(
        'resolve-signal', '-Id', $OgG3Sid, '-As', 'PROMOTED',
        '-Detail', 'fixture resolution', '-Addresses', 'defect', '-CloseIssue', '-Path', $OgRepo)

    # This verb does NOT refuse. It records the local resolution and continues at 0.
    Add-Result 'G3-case-resolve-signal-continues-0' `
               (($OgG3Case.Code -eq 0) -and ($OgG3Case.Text -like "*$OgGuardText*")) `
               "exit $($OgG3Case.Code), wanted 0 with the guard's text (it continues, it does not refuse)"

    # Row 3 AND row 4. One verb, two declined calls; asserting one would leave the other
    # untested while the group looked covered.
    Add-Result 'G3-case-names-row3-comment-call' `
               ($OgG3Case.Text -like '*gh api --method POST repos/*/issues/424242/comments*') `
               'wanted the comment POST named (row 3)'
    Add-Result 'G3-case-names-row4-close-call' `
               ($OgG3Case.Text -like '*gh issue close 424242*') `
               'wanted the issue close named (row 4)'

    # The false reason available on THIS verb is not 'GitHub CLI not found' - that string
    # does not exist in resolve-signal - it is the no-destination wording, which the reason
    # control below proves this verb can print.
    Add-Result 'G3-case-does-NOT-claim-no-destination' `
               (-not ($OgG3Case.Text -like "*$OgNoTarget*")) `
               "wanted '$OgNoTarget' ABSENT - a destination WAS chosen"

    # The local half must still have happened - that is the whole reason this verb
    # continues rather than refusing.
    Add-Result 'G3-case-local-resolution-still-recorded' `
               ($OgG3Case.Text -like "*$OgG3Sid -> PROMOTED*") `
               'wanted the local resolution recorded despite the outward half being skipped'

    $OgG3Scope = Invoke-Wrapper -OgHome $OgHome -OgArgs @(
        'signal', '-Kind', 'gap', '-Phase', 'W1.1',
        '-Detail', 'group 3 scope control', '-Evidence', 'scripts/test-outward-guard.ps1 - fixture',
        '-Path', $OgRepo)
    Add-Result 'G3-scope-control-signal-not-guarded' `
               (($OgG3Scope.Code -eq 0) -and (-not ($OgG3Scope.Text -like "*$OgGuardText*"))) `
               "exit $($OgG3Scope.Code), wanted 0 and NO guard text"

    # A SECOND signal, because the one above is now terminal and would take the retry path.
    $OgG3Sid2 = New-SignalWithIssue -OgRepo $OgRepo -OgHome $OgHome -OgIssueNum 515151
    Clear-FixtureTarget -OgHome $OgHome
    $OgG3Reason = Invoke-Wrapper -OgHome $OgHome -OgOutward 'allow' -OgBlindDir $OgBlind -OgArgs @(
        'resolve-signal', '-Id', $OgG3Sid2, '-As', 'PROMOTED',
        '-Detail', 'fixture resolution', '-Addresses', 'defect', '-CloseIssue', '-Path', $OgRepo)
    Set-FixtureTarget -OgHome $OgHome
    Add-Result 'G3-reason-control-no-destination-text-still-produced' `
               (($OgG3Reason.Text -like "*$OgNoTarget*") -and (-not ($OgG3Reason.Text -like "*$OgGuardText*"))) `
               "exit $($OgG3Reason.Code), wanted '$OgNoTarget' PRESENT and the guard's text ABSENT"

    # =====================================================================
    # GROUP 4 - status / Get-UnpushedReading (row 5)
    # =====================================================================
    $OgG4Case = Invoke-Wrapper -OgHome $OgHome -OgArgs @('status', '-Path', $OgGit)

    Add-Result 'G4-case-status-continues-0' `
               (($OgG4Case.Code -eq 0) -and ($OgG4Case.Text -like "*$OgGuardText*")) `
               "exit $($OgG4Case.Code), wanted 0 with the guard's text (site-5 constraint 2)"
    Add-Result 'G4-case-names-the-declined-command' `
               ($OgG4Case.Text -like '*ls-remote origin*') `
               'wanted the literal declined command named (site-5 constraint 4)'
    Add-Result 'G4-case-does-NOT-claim-remote-unreachable' `
               (-not ($OgG4Case.Text -like "*$OgUnreachable*")) `
               "wanted '$OgUnreachable' ABSENT - nothing was attempted, so that string would assert a reading that never happened (site-5 constraint 3)"

    # The scope control for site 5 is that the REST of status is untouched: it is the only
    # group whose guarded verb still has to print everything else it prints.
    Add-Result 'G4-scope-control-rest-of-status-intact' `
               (($OgG4Case.Text -like '*root:*') -and ($OgG4Case.Text -like '*goals:*')) `
               'wanted every other status line still printed (site-5 constraint 2)'

    $OgG4Reason = Invoke-Wrapper -OgHome $OgHome -OgOutward 'allow' -OgArgs @('status', '-Path', $OgGit)
    Add-Result 'G4-reason-control-unreachable-still-produced' `
               (($OgG4Reason.Text -like "*$OgUnreachable*") -and (-not ($OgG4Reason.Text -like "*$OgGuardText*"))) `
               "exit $($OgG4Reason.Code), wanted '$OgUnreachable' PRESENT and the guard's text ABSENT"

    # =====================================================================
    # GROUP 5 - the override reads in the BLOCK direction too
    # =====================================================================
    # KEEL_OUTWARD=block must ENGAGE the guard from a home that is not sandboxed, or the
    # variable is decorative in one direction and only 'allow' is ever exercised.
    #
    # HOW A NON-SANDBOXED HOME IS BUILT WITHOUT LEAVING %TEMP%: point the child's TEMP at
    # a different directory. The state home stays where it is, but it no longer resolves
    # inside TEMP, so the automatic rule is OFF and KEEL_OUTWARD is the only thing that
    # can engage the guard - which is exactly what makes the pair below discriminate.
    #
    # IT IS TESTED ON 'status' AND DELIBERATELY NOT ON signals-push. If 'block' failed to
    # engage, this fixture's origin is a non-existent LOCAL directory, so the worst case is
    # a local ls-remote at exit 128 and no network call. Testing the block direction on an
    # outward gh verb would mean a fixture with a pending signal reaching the real
    # repository the moment the thing under test was broken - the defect this suite exists
    # to prevent, rebuilt inside its own suite.
    #
    # DO NOT TEST THE BLOCK DIRECTION WITH signals-push PREVIEW AGAINST THE REAL STATE HOME
    # and an assertion that the guard's text is absent. With no pending signal the verb
    # returns at "Nothing to push" first, so such a row passes vacuously and nothing tests
    # the block direction at all - the same early return Group 1's comment above warns about.
    $OgG5Away = Join-Path $OgTempRoot 'temp-elsewhere'
    New-Item -ItemType Directory -Path $OgG5Away -Force | Out-Null

    $OgG5Block = Invoke-Wrapper -OgHome $OgHome -OgOutward 'block' -OgTempDir $OgG5Away `
                                -OgArgs @('status', '-Path', $OgGit)
    Add-Result 'G5-case-block-engages-from-a-non-sandboxed-home' `
               (($OgG5Block.Code -eq 0) -and ($OgG5Block.Text -like "*$OgGuardText*") -and
                (-not ($OgG5Block.Text -like "*$OgUnreachable*"))) `
               "exit $($OgG5Block.Code), wanted 0 with the guard's text and no '$OgUnreachable'"
    Add-Result 'G5-case-block-names-the-variable-as-the-reason' `
               ($OgG5Block.Text -like '*KEEL_OUTWARD*') `
               'wanted the message to name the variable, not the temp directory, as what engaged it'

    # The control: same moved TEMP, override UNSET. The automatic rule cannot fire from
    # here, so the guard must NOT engage - which is what proves 'block' is what engaged it
    # above, rather than the containment test still being on.
    $OgG5Ctl = Invoke-Wrapper -OgHome $OgHome -OgTempDir $OgG5Away `
                              -OgArgs @('status', '-Path', $OgGit)
    Add-Result 'G5-control-unset-does-NOT-engage-from-the-same-home' `
               (($OgG5Ctl.Code -eq 0) -and ($OgG5Ctl.Text -like "*$OgUnreachable*") -and
                (-not ($OgG5Ctl.Text -like "*$OgGuardText*"))) `
               "exit $($OgG5Ctl.Code), wanted 0 with '$OgUnreachable' and NO guard text"

    # =====================================================================
    # GROUP 6 - a per-call -Repo is shape-checked before anything is written
    # =====================================================================
    # Tested on resolve-signal because it is the one verb that WRITES before it reaches
    # GitHub, so a check placed too late would refuse after the local resolution landed.
    # The case and its control run on the SAME open signal: the case must leave it OPEN,
    # and the control must then resolve it, which proves the case's refusal came from the
    # -Repo value and not from the signal or the store.
    $OgG6Sid = New-SignalWithIssue -OgRepo $OgRepo -OgHome $OgHome -OgIssueNum 616161
    $OgG6SigPath = Join-Path (Join-Path (Join-Path $OgHome '.keel') 'signals') "$OgG6Sid.json"
    $OgG6Base = @('resolve-signal', '-Id', $OgG6Sid, '-As', 'PROMOTED',
                  '-Detail', 'fixture resolution', '-Addresses', 'defect', '-CloseIssue', '-Path', $OgRepo)

    $OgG6Case = Invoke-Wrapper -OgHome $OgHome -OgArgs (@($OgG6Base) + @('-Repo', 'a/b/c'))
    $OgG6State = (Get-Content -Raw -LiteralPath $OgG6SigPath | ConvertFrom-Json).state
    Add-Result 'G6-case-bad-repo-refused-90-nothing-written' `
               (($OgG6Case.Code -eq 90) -and ($OgG6Case.Text -like '*is not owner/name*') -and ($OgG6State -eq 'OPEN')) `
               "exit $($OgG6Case.Code), state $OgG6State; wanted 90, 'is not owner/name', and the signal still OPEN"

    $OgG6Ctl = Invoke-Wrapper -OgHome $OgHome -OgArgs (@($OgG6Base) + @('-Repo', 'example/fixture-other'))
    $OgG6CtlState = (Get-Content -Raw -LiteralPath $OgG6SigPath | ConvertFrom-Json).state
    Add-Result 'G6-control-good-repo-passes-the-check' `
               (($OgG6Ctl.Code -eq 0) -and (-not ($OgG6Ctl.Text -like '*is not owner/name*')) -and ($OgG6CtlState -ne 'OPEN')) `
               "exit $($OgG6Ctl.Code), state $OgG6CtlState; wanted 0, no shape refusal, and the signal resolved"

    # No row in this suite may run gh. A non-empty log means one got past the guard or the
    # destination check - throw, so the run ends with no summary line and is reported.
    if ((Test-Path -LiteralPath $script:OgFakeLog) -and ((Get-Item -LiteralPath $script:OgFakeLog).Length -gt 0)) {
        throw ("a row reached gh (the fake logged it): " + ((Get-Content -LiteralPath $script:OgFakeLog) -join ' || '))
    }
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------
$OgTempBase = [System.IO.Path]::GetTempPath()
$OgTempRoot = Join-Path $OgTempBase ("keel-outward-suite-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 12))

# The scratch home must resolve INSIDE the system temp directory before anything is
# written - and here that is doubly load-bearing, because it is ALSO what makes the guard
# under test engage at all. A fixture built under the wrong root would both write state
# into a real project and run every case with the guard disengaged, so each outward verb
# would reach the real GitHub repository. That is the exact failure this suite exists to
# prevent, and it must not be reachable from inside the suite itself.
$OgTempBaseFull = (Get-Item -LiteralPath $OgTempBase).FullName.TrimEnd('\', '/')
New-Item -ItemType Directory -Path $OgTempRoot -Force | Out-Null
$OgTempRootFull = (Get-Item -LiteralPath $OgTempRoot).FullName.TrimEnd('\', '/')
if (-not $OgTempRootFull.StartsWith("$OgTempBaseFull$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine("test-outward-guard: refusing to run - scratch root '$OgTempRootFull' does not resolve inside '$OgTempBaseFull'.")
    exit 1
}

$OgFailed = 0
$OgHarnessOk = $false
try {
    Invoke-Cases -OgTempRoot $OgTempRoot

    foreach ($OgResult in @($script:OgResults)) {
        if (-not $OgResult.Ok) {
            $OgFailed++
            if (-not $Quiet) { Write-Output ("  FAIL  {0,-52} {1}" -f $OgResult.Name, $OgResult.Why) }
        }
        if ($OgResult.Name -eq 'HARNESS-CONTROL-signals-push-guarded') { $OgHarnessOk = $OgResult.Ok }
    }

    if ($OgHarnessOk -ne $true) {
        Write-Output ''
        Write-Output '  HARNESS CONTROL FAILED: the guard did not engage on signals-push -Apply from a scratch state home.'
        Write-Output '  The suite is not reaching the mechanism. No other row in this run means anything.'
    }

    if (-not $Quiet) {
        Write-Output ("  {0} case(s), {1} failure(s)." -f @($script:OgResults).Count, $OgFailed)
    }
}
finally {
    # Best effort. A leftover fixture under TEMP is noise; a failure to remove it is not a
    # reason to report a green suite as red.
    if (Test-Path -LiteralPath $OgTempRoot) {
        try { Remove-Item -LiteralPath $OgTempRoot -Recurse -Force -ErrorAction Stop } catch { }
    }
}

Write-Output ''
Write-Output ("test-outward-guard: {0} case(s), {1} failure(s)." -f @($script:OgResults).Count, $OgFailed)
if ($OgFailed -gt 0) { exit 1 }
exit 0
