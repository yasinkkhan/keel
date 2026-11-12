<#
    test-shared-progress.ps1 - the suite for shared progress: a project whose keel.json says
    "progress": "repo" keeps its progress under progress/ in its own repo, one file per item and
    per entry, each naming its author.

    Runs in a scratch home ONLY. USERPROFILE and COMPUTERNAME are set for every wrapper call, so one
    machine stands in for several; HOME and GIT_CONFIG_GLOBAL point at an empty scratch file and
    GIT_CONFIG_NOSYSTEM is set, so no real git identity is read; KEEL_OUTWARD is 'block', except for
    ORIENT's status calls that must read the remote, which run with 'allow' only after the suite has
    checked that the clone's origin is a bare repository inside the scratch home. The suite
    refuses to start (exit 90) unless its scratch home resolves inside %TEMP%, and after the run
    the real state home must hold no project of this run.

    Groups, each case paired with a control that must behave differently:
      LAYOUT     every file under progress/ that the fixtures produce, gate artifacts aside, parses,
                 is UTF-8 with no byte-order mark and LF only, carries by (naming a person file),
                 machine and at with a UTC offset, holds exactly its kind's fields, and an entry's
                 name is <yyyyMMddTHHmmssZ>-<person id>-<4 hex>.json; all 13 kinds are produced.
                 Control: four planted files, each with one defect, are each reported.
      TWO        a bare remote and two clones, two machines, two people: different work on each
                 side merges with plain git pull and no conflict, and both clones show all of it.
                 Control: before one side pushes, the other is shown missing its work. One new
                 id taken on both sides is an add/add conflict naming that item's file.
      PEOPLE     join, join -As, join -As <id> -Clear, and their refusals; an unlisted machine and
                 a machine two person files list are refused, writing nothing.
      FOLD       close and abandon -Ws fold a workstream into closed/<id>.json, removing its phase
                 files and keeping artifacts/; tree, goal-coverage, status and status -Phase print
                 the same. Control: a fold file with one phase's entries removed changes -Phase.
      BIND       the gates after verify print no fingerprint warning about progress/. Control: a
                 change in a declared repo after verify still warns.
      LIST       list names a shared project with its root. Control: without the renamed state
                 file the row is gone.
      MACHINE    a project with no choice declared keeps its state per machine and leaves its
                 folder clean after a full gate sequence. Control: the same on a shared project
                 leaves files for git status to show.
      EXPORT     share-progress on a project with closed, abandoned and open workstreams, a
                 correction, a cap lift, an acknowledgement and a waiting phase: status and tree
                 print the same before and after (offsets aside), every file is exported and
                 names the exporter, closed and abandoned workstreams are folded, keel.json says
                 so and state.json is renamed. Control: one phase file deleted shows in the diff.
      REFUSE     share-progress refuses, writing nothing, at 90 for quarantine, git false,
                 uncommitted changes and already shared, at 95 with no user.name; each with the
                 condition removed exports at 0. After a full gate sequence, git ls-files holds
                 nothing kept per machine; control: one such file staged is listed.
      ORIENT     orientation, on its own bare remote and two clones, two people:
                   NEXT       next: is this person's and others: names the other's; a tie is the
                              ambiguity warning; an unregistered machine sees everyone's. Control: a
                              per-machine project's status and tree are HEAD's, with no others: line.
                   BEHIND     not pulled, then N commit(s) behind, then neither after a pull; the
                              reading not taken says so. Controls: an unpushed commit, a per-machine
                              project behind its remote.
                   UNCOMMITTED  the count of progress files not committed, files and not folders,
                              artifact subfolders aside; gone after a commit. Control: per machine.
                   MERGE      after a merge: a run-order clash (never named next, 92 on a further
                              add-phase, other writes go on), a phase open under a closed or
                              abandoned workstream, a reference with no file (ws, parent, goal,
                              owner, continues), a machine in two person files. Each with a control.
                   HANDOFF    authored handoffs, named per person; the newest by instant with its
                              author, your last handoff, STALE; a stamp later as an instant and
                              smaller as text is named. Control: without it, the earlier one is.
      OWNER      ownership and hand-over, on its own bare remote and two clones, people A and B:
                 every verb design section 8 lists refuses B at 88 on A's started phase, writing
                 nothing (control: the same calls by A exit 0), and the verbs run are compared with
                 that list both ways; note-friction and open-question stay open; anyone may revise,
                 take or abandon a planned phase. hand-over by a non-owner ends the phase and
                 creates its successor (Xb, then Xc), carrying its declaration (control: 92 at its
                 order before); hand-over's five refusals write nothing; a handed-over phase refuses
                 every covered verb at 90 naming its successor. status prints handed-over with its
                 successor; close counts it done and folds handedOver (control: one phase open);
                 abandon -Ws refuses it (control: a workstream with only an abandoned phase); a
                 successor at its predecessor's order is no clash (control: two merged phases at
                 one order are). After a merge, a gate entry by someone other than the owner is
                 named (control: the same with no owner change). The owner ends each unfinished
                 phase line and no finished one (control: a per-machine project prints none). Per
                 machine: -Owner and hand-over refuse at 90, and a full sequence's state.json has
                 the property paths of HEAD's wrapper's (control: a planted key is named); once the
                 change is committed that half compares the wrapper with itself, and says so.

    Modes, human-invoked and not on the push path, as the other suites' comparison modes are:
      -OldRef <rev>  the wrapper at <rev>, an older copy: a state.json it wrote keeps the same
                     property paths after one write by this wrapper (control: one key added is
                     named), and on an exported project it exits 91 and writes nothing. Refuses at
                     90 if the copy at <rev> is this one or already knows share-progress.
      -RealState     EXPORT on a scratch copy of this machine's real 'keel' project state, read
                     only, with one abandoned workstream added to the copy.
    The default run prints a NOT RUN line for each.

    Summary line, parsed by check-suite-docs.ps1 (a declared coupling):
      test-shared-progress: <n> case(s), <n> failure(s), <n> inconclusive
    Exit codes: 0 no failures; 1 failures; 5 a breach of the real state home; 6 the harness failed;
    90 refused to start. A case prints no path; a harness failure's message may. Windows PowerShell 5.1,
    ASCII only.
#>

param(
    [string]$OldRef = '',
    [switch]$RealState,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Stop-Suite {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("test-shared-progress: $Message")
    exit $Code
}

# ------------------------------------------------------------- the fence --
if ([string]::IsNullOrWhiteSpace($env:TEMP)) { Stop-Suite 90 'TEMP is not set, so the fence cannot be checked.' }
$tempFull = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\', '/')
$runTag = [guid]::NewGuid().ToString('N').Substring(0, 8)
$scratch = [System.IO.Path]::GetFullPath((Join-Path $tempFull ('keel-sp-' + $runTag))).TrimEnd('\', '/')
if (-not $scratch.StartsWith($tempFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    Stop-Suite 90 'Refusing to run: the scratch home does not resolve inside the temp directory.'
}
if (Test-Path -LiteralPath $scratch) { Stop-Suite 90 'Refusing to run: the scratch home already exists.' }

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$wrapperRel = 'plugins/keel-workflow/skills/keel-orchestrator/wrappers/keel-state.ps1'
$wtWrapper = Join-Path $repoRoot ($wrapperRel -replace '/', '\')
if (-not (Test-Path -LiteralPath $wtWrapper)) { Stop-Suite 90 'The working-tree wrapper was not found under plugins/.' }

$realEnv = @{}
foreach ($evName in @('USERPROFILE', 'COMPUTERNAME', 'HOME', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'KEEL_OUTWARD')) {
    $realEnv[$evName] = [Environment]::GetEnvironmentVariable($evName, 'Process')
}
$realProjects = Join-Path (Join-Path $realEnv['USERPROFILE'] '.keel') 'projects'
$realProjectsBefore = @()
if (Test-Path -LiteralPath $realProjects) { $realProjectsBefore = @(Get-ChildItem -LiteralPath $realProjects -Directory | ForEach-Object { $_.Name }) }

# ------------------------------------------------------------ results --
$script:CaseCount = 0
$script:FailCount = 0
$script:InconCount = 0
function Add-Case {
    param([string]$CaseName, [bool]$Ok, [string]$Info)
    $script:CaseCount++
    if ($Ok) { Write-Output "PASS  $CaseName - $Info" }
    else { $script:FailCount++; Write-Output "FAIL  $CaseName - $Info" }
}

# ------------------------------------------------------------ helpers --
function Get-Sha {
    param([byte[]]$ShaBytes)
    $shaAlg = [System.Security.Cryptography.SHA256]::Create()
    try { return (-join ($shaAlg.ComputeHash($ShaBytes) | ForEach-Object { $_.ToString('x2') })) }
    finally { $shaAlg.Dispose() }
}

function Invoke-K {
    # One wrapper call in its own powershell.exe, as one machine: its scratch home and its name.
    # -KOutward 'allow' for one call only, restored to 'block' after it.
    param([string]$KHome, [string]$KMachine, [string[]]$KArgs, [string]$KWrapper = '', [string]$KOutward = '')
    if (-not $KWrapper) { $KWrapper = $wtWrapper }
    $env:USERPROFILE = $KHome
    $env:COMPUTERNAME = $KMachine
    if ($KOutward) { $env:KEEL_OUTWARD = $KOutward }
    $kPrior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = -1
    try { $kRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $KWrapper @KArgs 2>&1 }
    finally { $env:KEEL_OUTWARD = 'block' }
    $kCode = $LASTEXITCODE
    $ErrorActionPreference = $kPrior
    $kOut = New-Object System.Collections.Generic.List[string]
    $kErr = New-Object System.Collections.Generic.List[string]
    foreach ($kLine in @($kRaw)) {
        if ($kLine -is [System.Management.Automation.ErrorRecord]) { $kErr.Add($kLine.Exception.Message) } else { $kOut.Add("$kLine") }
    }
    return [pscustomobject]@{ Code = $kCode; Out = ($kOut -join "`n"); Err = ($kErr -join "`n"); Lines = $kOut.ToArray() }
}

function Assert-K {
    # A setup call that must succeed; a failure here is the harness's, not a case.
    param([string]$KHome, [string]$KMachine, [string[]]$KArgs, [string]$KWrapper = '')
    $akRes = Invoke-K $KHome $KMachine $KArgs $KWrapper
    if ($akRes.Code -ne 0) { throw "Setup call '$($KArgs[0])' exited $($akRes.Code): $($akRes.Err)" }
    return $akRes
}

function Invoke-G {
    param([string]$GDir, [string[]]$GArgs)
    $gPrior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = -1
    $gRaw = & git -C $GDir @GArgs 2>&1
    $gCode = $LASTEXITCODE
    $ErrorActionPreference = $gPrior
    $gText = (@($gRaw) | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" } }) -join "`n"
    return [pscustomobject]@{ Code = $gCode; Out = $gText }
}

function Assert-G {
    param([string]$GDir, [string[]]$GArgs)
    $agRes = Invoke-G $GDir $GArgs
    if ($agRes.Code -ne 0) { throw "Setup git '$($GArgs[0])' exited $($agRes.Code): $($agRes.Out)" }
    return $agRes
}

function New-Repo {
    param([string]$RDir, [string]$RUser)
    New-Item -ItemType Directory -Path $RDir -Force | Out-Null
    Assert-G $RDir @('init', '-q', '-b', 'main') | Out-Null
    if ($RUser) { Assert-G $RDir @('config', 'user.name', $RUser) | Out-Null }
    Assert-G $RDir @('config', 'user.email', 'suite@example.invalid') | Out-Null
    Assert-G $RDir @('config', 'pull.rebase', 'false') | Out-Null
    Assert-G $RDir @('config', 'core.autocrlf', 'false') | Out-Null
}

function Save-Commit {
    param([string]$CDir, [string]$CMessage)
    Assert-G $CDir @('add', '-A') | Out-Null
    $cRes = Invoke-G $CDir @('-c', 'user.name=Suite Committer', 'commit', '-q', '-m', $CMessage)
    if ($cRes.Code -ne 0 -and $cRes.Out -notmatch 'nothing to commit') { throw "Setup commit failed: $($cRes.Out)" }
}

function New-Home {
    param([string]$HLabel)
    $hDir = Join-Path (Join-Path $scratch 'homes') $HLabel
    New-Item -ItemType Directory -Path $hDir -Force | Out-Null
    return $hDir
}

function Get-ArtDir {
    param([string]$ADir, [string]$AHome, [string]$APhase, [switch]$AShared)
    if ($AShared) { return (Join-Path $ADir "progress\phases\$APhase\artifacts") }
    return (Join-Path $AHome ".keel\projects\$(Split-Path -Leaf $ADir)\phases\$APhase")
}

function Write-Artifacts {
    param([string]$ArtDir, [string]$APhase, [string[]]$ARepos = @())
    New-Item -ItemType Directory -Path $ArtDir -Force | Out-Null
    $aEnc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $ArtDir 'grounding.md'), "Measured: fixture`n`nNot read: nothing else`n", $aEnc)
    [System.IO.File]::WriteAllText((Join-Path $ArtDir 'investigation.md'), "Positive control: fixture`n", $aEnc)
    [System.IO.File]::WriteAllText((Join-Path $ArtDir 'plan.md'), "## Changes`n`n- the fixture file`n", $aEnc)
    if (@($ARepos).Count -gt 0) {
        foreach ($aRepo in @($ARepos)) { [System.IO.File]::WriteAllText((Join-Path $ArtDir "changes-$aRepo.patch"), "fixture patch`n", $aEnc) }
    }
    else { [System.IO.File]::WriteAllText((Join-Path $ArtDir 'act-log.md'), "Done by: claude`nDone on: 2026-01-01`nProduced: the fixture file`n", $aEnc) }
    [System.IO.File]::WriteAllText((Join-Path $ArtDir 'verify-report.md'), "| $APhase-C1 | PASS | run-by: agent |`n`nPositive control: fixture`n", $aEnc)
    [System.IO.File]::WriteAllText((Join-Path $ArtDir 'delivery-record.md'), "# $($APhase.ToUpper()) delivered`n`nEvidence: $($ARepos -join ', ')`n`nDocs impact: none`n`nRemaining phases: unchanged`n", $aEnc)
}

$GateVerdict = [ordered]@{ ground = 'DONE'; investigate = 'DONE'; plan = 'APPROVED'; implement = 'DONE'; verify = 'PASS'; human = 'APPROVED'; enact = 'N/A'; record = 'DONE' }

function Invoke-Gates {
    # Records the named gates in order, each required to succeed; returns each gate's output.
    param([string]$GHome, [string]$GMachine, [string]$GDir, [string]$GPhase, [string[]]$GGates, [string]$GWrapper = '')
    $gOut = [ordered]@{}
    foreach ($gName in $GGates) {
        $gRes = Assert-K $GHome $GMachine @('record-verdict', '-Path', $GDir, '-Phase', $GPhase, '-Gate', $gName, '-Verdict', $GateVerdict[$gName]) $GWrapper
        $gOut[$gName] = $gRes.Out
    }
    return $gOut
}

$AllGates = @('ground', 'investigate', 'plan', 'implement', 'verify', 'human', 'enact', 'record')

function Get-View {
    # What a reader is shown: status, tree, goal-coverage and status -Phase for each phase named,
    # with a stamp's offset removed (an export adds one) and the root line left out (a copy moves it).
    param([string]$VHome, [string]$VMachine, [string]$VDir, [string[]]$VPhases)
    $vAll = New-Object System.Collections.Generic.List[string]
    $vCalls = @(, @('status')) + @(, @('tree')) + @(, @('goal-coverage'))
    foreach ($vPh in @($VPhases)) { $vCalls += , @('status', '-Phase', $vPh) }
    foreach ($vCall in $vCalls) {
        $vRes = Invoke-K $VHome $VMachine (@($vCall) + @('-Path', $VDir))
        $vAll.Add("== $($vCall -join ' ') exit $($vRes.Code)")
        foreach ($vLine in $vRes.Lines) {
            if ($vLine -match '^KEEL:\s+root: ') { continue }
            # Lines only a shared project prints about this copy's git state, which an export and a
            # fold move by design: the uncommitted count, and a reading not taken.
            if ($vLine -match 'progress file\(s\) written here are not committed|was NOT checked \(') { continue }
            # The owner a shared project prints at the end of an unfinished phase's line, which a
            # per-machine project has no owner to print; OWNER-column tests it.
            $vLine = $vLine -replace '  owner: [^()]*\(p-[0-9a-f]{4}\)$', ''
            $vAll.Add(($vLine -replace '(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})[+-]\d{2}:\d{2}', '$1'))
        }
    }
    return $vAll.ToArray()
}

function Compare-View {
    # The lines that differ, position by position, each side's; empty when the views are the
    # same. -CvAllow names the lines a case expects to move; they leave both sides first, so the
    # rest still line up and a line moved out of place still counts.
    param([string[]]$CvA, [string[]]$CvB, [string]$CvAllow = '')
    if ($CvAllow) {
        $CvA = @($CvA | Where-Object { $_ -notmatch $CvAllow })
        $CvB = @($CvB | Where-Object { $_ -notmatch $CvAllow })
    }
    $cvDiff = @(Compare-Object -ReferenceObject @($CvA) -DifferenceObject @($CvB) -SyncWindow 0 -CaseSensitive)
    return @($cvDiff | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
}

function Get-TreeHash {
    # The listing and hashes of every file under a folder: a write anywhere moves it.
    param([string]$TDir)
    if (-not (Test-Path -LiteralPath $TDir)) { return '(none)' }
    $tLines = @(Get-ChildItem -LiteralPath $TDir -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName.Substring($TDir.Length) + '|' + (Get-Sha ([System.IO.File]::ReadAllBytes($_.FullName)))
    })
    return (Get-Sha ([System.Text.Encoding]::UTF8.GetBytes(($tLines -join "`n"))))
}

function Get-WriteSnapshot {
    # What "writes nothing" is decided by: the project repo's status, keel.json's bytes, and the
    # per-machine folder's listing and hashes.
    param([string]$SDir, [string]$SHome)
    $sSt = Invoke-G $SDir @('status', '--porcelain', '--untracked-files=all')
    $sCfg = Join-Path $SDir 'keel.json'
    $sCfgSha = if (Test-Path -LiteralPath $sCfg) { Get-Sha ([System.IO.File]::ReadAllBytes($sCfg)) } else { '' }
    return "$($sSt.Code)|$($sSt.Out)|$sCfgSha|$(Get-TreeHash (Join-Path $SHome ".keel\projects\$(Split-Path -Leaf $SDir)"))|$(Get-TreeHash (Join-Path $SDir 'progress'))"
}

function Read-JsonFile {
    param([string]$JFile)
    return ([System.IO.File]::ReadAllText($JFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

function Get-FriendlyFiles {
    # Every file under progress/ other than gate artifacts, relative, forward slashes.
    param([string]$FDir)
    $fRoot = Join-Path $FDir 'progress'
    if (-not (Test-Path -LiteralPath $fRoot)) { return @() }
    return @(Get-ChildItem -LiteralPath $fRoot -Recurse -File | ForEach-Object {
        $_.FullName.Substring($fRoot.Length + 1) -replace '\\', '/'
    } | Where-Object { $_ -notmatch '^phases/[^/]+/artifacts/' } | Sort-Object)
}

# ------------------------------------------------------- the layout check --
$EntryName = '^\d{8}T\d{6}Z-p-[0-9a-f]{4}-[0-9a-f]{4}\.json$'
$OffsetStamp = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$'
$script:KindsSeen = @{}
$KindFields = @{
    project    = @('schema', 'title', 'created', 'status')
    person     = @('id', 'name', 'machines')
    goal       = @('id', 'text', 'status', 'statusReason', 'statusSetAt', 'created')
    node       = @('id', 'role', 'title', 'parent', 'goals', 'created', 'closedAt', 'abandonedReason', 'abandonedAt')
    decl       = @('id', 'ws', 'scope', 'actor', 'runOrder', 'repos', 'due', 'promptPath', 'created', 'owner', 'needs', 'continues')
    run        = @('stage', 'waitingOn', 'reviewOn', 'iterations', 'abandonedReason')
    gate       = @('gate', 'verdict', 'artifact')
    friction   = @('kind', 'detail')
    question   = @('question', 'answer', 'resolvedBy')
    correction = @('text')
    caplift    = @('rounds', 'afterIteration', 'words')
    ack        = @('from', 'to', 'detail')
    closed     = @('ws', 'phases')
}
$FoldPhaseFields = @($KindFields['decl'] + $KindFields['run'] + @('declaredBy', 'declaredMachine', 'declaredAt', 'by', 'machine', 'at', 'gates', 'friction', 'questions', 'corrections', 'capLifts'))

function Get-FileKind {
    param([string]$KRel)
    switch -regex ($KRel) {
        '^project\.json$'                    { return 'project' }
        '^people/[^/]+\.json$'               { return 'person' }
        '^goals/[^/]+\.json$'                { return 'goal' }
        '^nodes/[^/]+\.json$'                { return 'node' }
        '^closed/[^/]+\.json$'               { return 'closed' }
        '^acks/[^/]+\.json$'                 { return 'ack' }
        '^phases/[^/]+/phase\.json$'         { return 'decl' }
        '^phases/[^/]+/run\.json$'           { return 'run' }
        '^phases/[^/]+/gates/[^/]+/[^/]+\.json$' { return 'gate' }
        '^phases/[^/]+/friction/[^/]+\.json$'    { return 'friction' }
        '^phases/[^/]+/questions/[^/]+\.json$'   { return 'question' }
        '^phases/[^/]+/corrections/[^/]+\.json$' { return 'correction' }
        '^phases/[^/]+/cap-lifts/[^/]+\.json$'   { return 'caplift' }
    }
    return 'unknown'
}

function Test-ProgressFiles {
    # Every problem with the files under one project's progress/, as text; empty when there are none.
    param([string]$TpDir)
    $tpProblems = New-Object System.Collections.Generic.List[string]
    $tpRoot = Join-Path $TpDir 'progress'
    foreach ($tpRel in @(Get-FriendlyFiles $TpDir)) {
        $tpFull = Join-Path $tpRoot ($tpRel -replace '/', '\')
        $tpKind = Get-FileKind $tpRel
        if ($tpKind -eq 'unknown') { $tpProblems.Add("${tpRel}: not a file of any kind the layout names"); continue }
        $tpBytes = [System.IO.File]::ReadAllBytes($tpFull)
        if ($tpBytes.Length -ge 3 -and $tpBytes[0] -eq 0xEF -and $tpBytes[1] -eq 0xBB -and $tpBytes[2] -eq 0xBF) { $tpProblems.Add("${tpRel}: has a byte-order mark") }
        if (@($tpBytes | Where-Object { $_ -eq 13 }).Count -gt 0) { $tpProblems.Add("${tpRel}: has a carriage return") }
        $tpObj = $null
        try { $tpObj = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($tpBytes) | ConvertFrom-Json } catch { $tpObj = $null }
        if ($null -eq $tpObj) { $tpProblems.Add("${tpRel}: does not parse as UTF-8 JSON"); continue }
        $script:KindsSeen[$tpKind] = $true
        $tpNames = @($tpObj.PSObject.Properties | ForEach-Object { $_.Name })

        $tpBy = $tpObj.PSObject.Properties['by']
        if ($null -eq $tpBy -or [string]::IsNullOrWhiteSpace([string]$tpBy.Value)) { $tpProblems.Add("${tpRel}: no 'by'") }
        elseif (-not (Test-Path -LiteralPath (Join-Path $tpRoot "people\$($tpBy.Value).json"))) { $tpProblems.Add("${tpRel}: 'by' $($tpBy.Value) names no person file") }
        $tpMachine = $tpObj.PSObject.Properties['machine']
        if ($null -eq $tpMachine -or [string]::IsNullOrWhiteSpace([string]$tpMachine.Value)) { $tpProblems.Add("${tpRel}: no 'machine'") }
        $tpAt = $tpObj.PSObject.Properties['at']
        if ($null -eq $tpAt -or [string]$tpAt.Value -notmatch $OffsetStamp) { $tpProblems.Add("${tpRel}: 'at' has no UTC offset") }
        $tpSrc = $tpObj.PSObject.Properties['source']
        if ($null -ne $tpSrc -and [string]$tpSrc.Value -ne 'export') { $tpProblems.Add("${tpRel}: 'source' is not 'export'") }

        $tpWant = @($KindFields[$tpKind])
        $tpMay = @()
        switch ($tpKind) {
            'node' {
                if ([string](@($tpObj.PSObject.Properties | Where-Object { $_.Name -eq 'role' } | ForEach-Object { $_.Value })) -eq 'epic') { $tpWant += 'groups' } else { $tpWant += 'status' }
                $tpFold = Join-Path $tpRoot "closed\$([string]$tpObj.id).json"
                if (Test-Path -LiteralPath $tpFold) { $tpWant += @('phaseStages', 'handedOver') }
            }
            'run' {
                if ([string]$tpObj.stage -eq 'handed-over') { $tpWant += @('handedOverTo', 'handOverReason') }
            }
            'gate' {
                $tpGate = [string]$tpObj.gate
                if ($tpGate -eq 'enact') { $tpWant += @('reversible', 'observable'); $tpMay += 'bindingCheck' }
                if ($tpGate -eq 'verify' -and @('PASS', 'INCONCLUSIVE') -contains [string]$tpObj.verdict) { $tpWant += 'binding' }
                if (@('human', 'record') -contains $tpGate) { $tpMay += 'bindingCheck' }
                if ($tpRel -notmatch "/gates/$tpGate/") { $tpProblems.Add("${tpRel}: gate '$tpGate' is not the folder it is in") }
            }
            'decl' {
                $tpOwner = [string]$tpObj.owner
                if (-not (Test-Path -LiteralPath (Join-Path $tpRoot "people\$tpOwner.json"))) { $tpProblems.Add("${tpRel}: 'owner' $tpOwner names no person file") }
                if (@($tpObj.needs).Count -ne 0) { $tpProblems.Add("${tpRel}: 'needs' is not empty") }
                if ($null -ne $tpObj.continues) { $tpProblems.Add("${tpRel}: 'continues' is not null") }
            }
            'closed' {
                foreach ($tpFp in @($tpObj.phases)) {
                    $tpFpNames = @($tpFp.PSObject.Properties | ForEach-Object { $_.Name })
                    $tpFpMiss = @($FoldPhaseFields | Where-Object { $tpFpNames -notcontains $_ })
                    $tpFpExtra = @($tpFpNames | Where-Object { $FoldPhaseFields -notcontains $_ -and @('handedOverTo', 'handOverReason') -notcontains $_ })
                    if ($tpFpMiss.Count -gt 0) { $tpProblems.Add("${tpRel}: folded phase $($tpFp.id) lacks $($tpFpMiss -join ', ')") }
                    if ($tpFpExtra.Count -gt 0) { $tpProblems.Add("${tpRel}: folded phase $($tpFp.id) has unexpected $($tpFpExtra -join ', ')") }
                }
            }
        }
        $tpMeta = @('by', 'machine', 'at', 'source')
        $tpMissing = @($tpWant | Where-Object { $tpNames -notcontains $_ })
        $tpExtra = @($tpNames | Where-Object { $tpWant -notcontains $_ -and $tpMay -notcontains $_ -and $tpMeta -notcontains $_ })
        if ($tpMissing.Count -gt 0) { $tpProblems.Add("${tpRel}: lacks $($tpMissing -join ', ')") }
        if ($tpExtra.Count -gt 0) { $tpProblems.Add("${tpRel}: has fields its kind does not: $($tpExtra -join ', ')") }
        if (@('gate', 'friction', 'question', 'correction', 'caplift', 'ack') -contains $tpKind -and (Split-Path -Leaf $tpFull) -notmatch $EntryName) {
            $tpProblems.Add("${tpRel}: entry name is not <yyyyMMddTHHmmssZ>-<person id>-<4 hex>.json")
        }
    }
    return $tpProblems.ToArray()
}

$LayoutDirs = New-Object System.Collections.Generic.List[string]

# =================================================================== run ==
$script:HarnessError = $null
$homeMarkers = New-Object System.Collections.Generic.List[string]
try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $gitGlobal = Join-Path $scratch 'gitglobal'
    [System.IO.File]::WriteAllText($gitGlobal, '')
    $env:HOME = $scratch
    $env:GIT_CONFIG_GLOBAL = $gitGlobal
    $env:GIT_CONFIG_NOSYSTEM = '1'
    $env:KEEL_OUTWARD = 'block'

    # A child must see the scratch home before the first wrapper call.
    $probeHome = New-Home 'probe'
    $env:USERPROFILE = $probeHome
    $env:COMPUTERNAME = 'KSP-PROBE'
    $probeEnc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes('[Console]::Out.WriteLine($env:USERPROFILE + "|" + $env:COMPUTERNAME + "|" + $env:KEEL_OUTWARD)'))
    $probeSeen = & powershell.exe -NoProfile -EncodedCommand $probeEnc
    if ("$probeSeen".Trim() -ne ($probeHome + '|KSP-PROBE|block')) { throw 'Harness control failed before any write: a child does not see the scratch home, the machine name and the outward block.' }

    # A copy of this wrapper under a plugin that says it is keel 0.0.1, so a project planned with it
    # has a version to acknowledge.
    $v001 = Join-Path $scratch 'v001\plugins\keel-workflow'
    New-Item -ItemType Directory -Path (Join-Path $v001 'skills\keel-orchestrator\wrappers') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $v001 '.claude-plugin') -Force | Out-Null
    Copy-Item -LiteralPath $wtWrapper -Destination (Join-Path $v001 'skills\keel-orchestrator\wrappers\keel-state.ps1')
    [System.IO.File]::WriteAllText((Join-Path $v001 '.claude-plugin\plugin.json'), '{ "name": "keel-workflow", "version": "0.0.1" }')
    $v001Wrapper = Join-Path $v001 'skills\keel-orchestrator\wrappers\keel-state.ps1'

    # ============================================================ TWO, PEOPLE ==
    $remote = Join-Path $scratch 'remote.git'
    New-Item -ItemType Directory -Path $remote -Force | Out-Null
    Assert-G $remote @('init', '-q', '--bare', '-b', 'main') | Out-Null
    $slug = 'ksp' + $runTag
    $homeA = New-Home 'A'; $homeB = New-Home 'B'; $homeC = New-Home 'C'; $homeD = New-Home 'D'; $homeE = New-Home 'E'; $homeX = New-Home 'X'
    $dirA = Join-Path $scratch "cloneA\$slug"
    $dirB = Join-Path $scratch "cloneB\$slug"
    New-Repo $dirA 'Person A'
    Assert-G $dirA @('remote', 'add', 'origin', $remote) | Out-Null
    Assert-K $homeA 'KSP-A' @('init-project', '-Path', $dirA, '-Title', 'two people') $v001Wrapper | Out-Null
    foreach ($gl in @(@('G1', 'first goal'), @('G2', 'second goal'))) { Assert-K $homeA 'KSP-A' @('add-goal', '-Path', $dirA, '-Id', $gl[0], '-Text', $gl[1]) | Out-Null }
    foreach ($wl in @(@('W1', 'G1'), @('W2', 'G1'), @('W3', 'G2'), @('W4', 'G2'))) {
        Assert-K $homeA 'KSP-A' @('add-workstream', '-Path', $dirA, '-Id', $wl[0], '-Title', "workstream $($wl[0])", '-Parent', 'root', '-Goals', $wl[1]) | Out-Null
    }
    foreach ($pl in @(@('W1.1', 1), @('W2.1', 1), @('W3.1', 1), @('W3.2', 2), @('W4.1', 1))) {
        Assert-K $homeA 'KSP-A' @('add-phase', '-Path', $dirA, '-Phase', $pl[0], '-Scope', "phase $($pl[0])", '-Actor', 'agent', '-RunOrder', "$($pl[1])") | Out-Null
    }
    Save-Commit $dirA 'project'
    Assert-K $homeA 'KSP-A' @('share-progress', '-Path', $dirA) | Out-Null
    Assert-K $homeA 'KSP-A' @('ack-keel-version', '-Path', $dirA, '-Detail', 'suite acknowledgement') | Out-Null
    Save-Commit $dirA 'shared'
    Assert-G $dirA @('push', '-q', '-u', 'origin', 'main') | Out-Null
    $LayoutDirs.Add($dirA)

    New-Item -ItemType Directory -Path (Join-Path $scratch 'cloneB') -Force | Out-Null
    Assert-G (Join-Path $scratch 'cloneB') @('clone', '-q', $remote, $slug) | Out-Null
    Assert-G $dirB @('config', 'user.name', 'Person B') | Out-Null
    Assert-G $dirB @('config', 'user.email', 'suite@example.invalid') | Out-Null
    Assert-G $dirB @('config', 'pull.rebase', 'false') | Out-Null
    Assert-G $dirB @('config', 'core.autocrlf', 'false') | Out-Null
    $LayoutDirs.Add($dirB)

    # PEOPLE: an unlisted machine is refused, naming join, and writes nothing.
    $snap0 = Get-WriteSnapshot $dirB $homeB
    $unl = Invoke-K $homeB 'KSP-B' @('note-friction', '-Path', $dirB, '-Phase', 'W2.1', '-Kind', 'gap', '-Detail', 'unregistered')
    Add-Case 'PEOPLE-unlisted-95' (($unl.Code -eq 95) -and ($unl.Err -match "'join'") -and ((Get-WriteSnapshot $dirB $homeB) -eq $snap0)) "exit $($unl.Code), names join: $($unl.Err -match "'join'"), wrote nothing: $((Get-WriteSnapshot $dirB $homeB) -eq $snap0)"

    $jb = Invoke-K $homeB 'KSP-B' @('join', '-Path', $dirB)
    $pidB = ''
    if ($jb.Out -match 'as person (p-[0-9a-f]{4}) ') { $pidB = $Matches[1] }
    $pfB = Join-Path $dirB "progress\people\$pidB.json"
    $pfBText = if ($pidB -and (Test-Path -LiteralPath $pfB)) { [System.IO.File]::ReadAllText($pfB) } else { '' }
    $pfBObj = if ($pfBText) { $pfBText | ConvertFrom-Json } else { $null }
    $jbOk = ($jb.Code -eq 0) -and ($pidB -match '^p-[0-9a-f]{4}$') -and ($null -ne $pfBObj) -and ([string]$pfBObj.id -eq $pidB) -and ([string]$pfBObj.name -eq 'Person B') -and (@($pfBObj.machines) -contains 'KSP-B') -and ($pfBText -notmatch '@') -and ($pfBText -notmatch '"email"')
    Add-Case 'PEOPLE-join' $jbOk "exit $($jb.Code), id '$pidB', name from git config, machine listed, no email in the file"
    $ctl = Invoke-K $homeB 'KSP-B' @('note-friction', '-Path', $dirB, '-Phase', 'W2.1', '-Kind', 'gap', '-Detail', 'registered now')
    Add-Case 'PEOPLE-listed-CONTROL' ($ctl.Code -eq 0) "a write from a machine one person file lists exits $($ctl.Code)"

    # join -As adds a second machine to that person; joining again from it is refused.
    $jc = Invoke-K $homeC 'KSP-C' @('join', '-Path', $dirB, '-As', $pidB)
    $pfBObj2 = Read-JsonFile $pfB
    Add-Case 'PEOPLE-join-As' (($jc.Code -eq 0) -and (@($pfBObj2.machines) -contains 'KSP-C') -and (@($pfBObj2.machines) -contains 'KSP-B')) "exit $($jc.Code), machines now $(@($pfBObj2.machines) -join ', ')"
    $snap1 = Get-WriteSnapshot $dirB $homeC
    $jc2 = Invoke-K $homeC 'KSP-C' @('join', '-Path', $dirB)
    Add-Case 'PEOPLE-join-again-90' (($jc2.Code -eq 90) -and ($jc2.Err -match 'already listed') -and ((Get-WriteSnapshot $dirB $homeC) -eq $snap1)) "exit $($jc2.Code), wrote nothing: $((Get-WriteSnapshot $dirB $homeC) -eq $snap1)"

    # join with no user.name is refused at 95, naming the git config command.
    Assert-G $dirB @('config', '--unset', 'user.name') | Out-Null
    $snap2 = Get-WriteSnapshot $dirB $homeD
    $jd = Invoke-K $homeD 'KSP-D' @('join', '-Path', $dirB)
    Add-Case 'PEOPLE-no-name-95' (($jd.Code -eq 95) -and ($jd.Err -match 'git -C .* config user\.name') -and ((Get-WriteSnapshot $dirB $homeD) -eq $snap2)) "exit $($jd.Code), names git config: $($jd.Err -match 'config user\.name'), wrote nothing: $((Get-WriteSnapshot $dirB $homeD) -eq $snap2)"
    Assert-G $dirB @('config', 'user.name', 'Person B') | Out-Null
    $jdCtl = Invoke-K $homeD 'KSP-D' @('join', '-Path', $dirB)
    Add-Case 'PEOPLE-no-name-CONTROL' ($jdCtl.Code -eq 0) "with user.name set the same join exits $($jdCtl.Code)"
    Save-Commit $dirB 'people'
    Assert-G $dirB @('push', '-q') | Out-Null
    Assert-G $dirA @('pull', '-q') | Out-Null

    # TWO: each person adds a phase to a different workstream, records verdicts on a different
    # phase and notes friction; plain git pull merges both.
    $tokA = "TOKA$runTag"; $tokB = "TOKB$runTag"
    Assert-K $homeA 'KSP-A' @('add-phase', '-Path', $dirA, '-Phase', 'W1.2', '-Scope', "added by A $tokA", '-Actor', 'agent', '-RunOrder', '2') | Out-Null
    Write-Artifacts (Get-ArtDir $dirA $homeA 'W1.1' -AShared) 'W1.1'
    Invoke-Gates $homeA 'KSP-A' $dirA 'W1.1' $AllGates | Out-Null
    Assert-K $homeA 'KSP-A' @('note-friction', '-Path', $dirA, '-Phase', 'W1.1', '-Kind', 'gap', '-Detail', $tokA) | Out-Null
    Assert-K $homeA 'KSP-A' @('revise-phase', '-Path', $dirA, '-Phase', 'W1.1', '-Correction', "correction $tokA") | Out-Null
    Assert-K $homeA 'KSP-A' @('lift-cap', '-Path', $dirA, '-Phase', 'W1.2', '-Rounds', '1', '-Detail', 'suite words') | Out-Null
    Assert-K $homeB 'KSP-B' @('add-phase', '-Path', $dirB, '-Phase', 'W2.2', '-Scope', "added by B $tokB", '-Actor', 'agent', '-RunOrder', '2') | Out-Null
    Write-Artifacts (Get-ArtDir $dirB $homeB 'W2.1' -AShared) 'W2.1'
    # W2.1 was planned by A, so it is A's; B takes it while it is still planned, as anyone may.
    Assert-K $homeB 'KSP-B' @('revise-phase', '-Path', $dirB, '-Phase', 'W2.1', '-Owner', $pidB) | Out-Null
    Invoke-Gates $homeB 'KSP-B' $dirB 'W2.1' @('ground', 'investigate', 'plan') | Out-Null
    Assert-K $homeB 'KSP-B' @('note-friction', '-Path', $dirB, '-Phase', 'W2.1', '-Kind', 'gap', '-Detail', $tokB) | Out-Null
    Assert-K $homeB 'KSP-B' @('open-question', '-Path', $dirB, '-Phase', 'W2.1', '-Question', "question $tokB", '-Answer', 'answered') | Out-Null
    Save-Commit $dirA 'work A'
    Save-Commit $dirB 'work B'
    Assert-G $dirA @('push', '-q') | Out-Null
    $pullB = Invoke-G $dirB @('pull', '--no-edit')
    # The control: A pulls while B's work is committed but not pushed, and must not see it.
    Assert-G $dirA @('pull', '-q') | Out-Null
    $aEarly = (Invoke-K $homeA 'KSP-A' @('status', '-Path', $dirA, '-Phase', 'W2.1')).Out + (Invoke-K $homeA 'KSP-A' @('tree', '-Path', $dirA)).Out
    Add-Case 'TWO-unpushed-CONTROL' (($aEarly -notmatch $tokB) -and ($aEarly -match 'W2\.1')) "before B pushes, clone A shows B's friction and phase: $($aEarly -match $tokB)"
    Assert-G $dirB @('push', '-q') | Out-Null
    $pullA = Invoke-G $dirA @('pull', '--no-edit')
    Add-Case 'TWO-merge-clean' (($pullB.Code -eq 0) -and ($pullA.Code -eq 0) -and ($pullB.Out -notmatch 'CONFLICT') -and ($pullA.Out -notmatch 'CONFLICT')) "git pull in B exit $($pullB.Code), in A exit $($pullA.Code), no conflict"
    foreach ($side in @(@('A', $dirA, $homeA, 'KSP-A'), @('B', $dirB, $homeB, 'KSP-B'))) {
        $sv = (Invoke-K $side[2] $side[3] @('tree', '-Path', $side[1])).Out + "`n" +
              (Invoke-K $side[2] $side[3] @('status', '-Path', $side[1])).Out + "`n" +
              (Invoke-K $side[2] $side[3] @('status', '-Path', $side[1], '-Phase', 'W1.1')).Out + "`n" +
              (Invoke-K $side[2] $side[3] @('status', '-Path', $side[1], '-Phase', 'W2.1')).Out
        $svOk = ($sv -match "added by A $tokA") -and ($sv -match "added by B $tokB") -and ($sv -match "W1\.1\s+#1\s+agent\s+delivered") -and ($sv -match "W2\.1\s+#1\s+agent\s+implementing") -and ($sv -match "-> $tokA") -and ($sv -match "-> $tokB") -and ($sv -match "question $tokB")
        Add-Case "TWO-both-visible-$($side[0])" $svOk "clone $($side[0]) shows both phases added, both stages, both people's friction and the question"
    }

    # One id taken on both sides is an add/add conflict on that item's file.
    Assert-K $homeA 'KSP-A' @('add-goal', '-Path', $dirA, '-Id', 'G9', '-Text', 'goal nine from A') | Out-Null
    Assert-K $homeB 'KSP-B' @('add-goal', '-Path', $dirB, '-Id', 'G9', '-Text', 'goal nine from B') | Out-Null
    Save-Commit $dirA 'G9 A'
    Save-Commit $dirB 'G9 B'
    Assert-G $dirA @('push', '-q') | Out-Null
    $clash = Invoke-G $dirB @('pull', '--no-edit')
    Add-Case 'TWO-same-id-conflict' (($clash.Code -ne 0) -and ($clash.Out -match 'CONFLICT \(add/add\)') -and ($clash.Out -match 'progress/goals/G9\.json')) "second pull exit $($clash.Code), names progress/goals/G9.json as add/add"
    Invoke-G $dirB @('merge', '--abort') | Out-Null
    Assert-G $dirB @('reset', '-q', '--hard', 'HEAD~1') | Out-Null
    Assert-G $dirB @('pull', '-q', '--no-edit') | Out-Null

    # PEOPLE: one machine joins on both sides offline, so after the merge two person files list it.
    Assert-K $homeX 'KSP-X' @('join', '-Path', $dirA) | Out-Null
    Assert-K $homeX 'KSP-X' @('join', '-Path', $dirB) | Out-Null
    Save-Commit $dirA 'X joins on A'
    Save-Commit $dirB 'X joins on B'
    Assert-G $dirB @('push', '-q') | Out-Null
    Assert-G $dirA @('pull', '-q', '--no-edit') | Out-Null
    $xPeople = @(Get-ChildItem -LiteralPath (Join-Path $dirA 'progress\people') -Filter '*.json' | ForEach-Object { Read-JsonFile $_.FullName } | Where-Object { @($_.machines) -contains 'KSP-X' })
    $snap3 = Get-WriteSnapshot $dirA $homeX
    $xw = Invoke-K $homeX 'KSP-X' @('note-friction', '-Path', $dirA, '-Phase', 'W1.2', '-Kind', 'gap', '-Detail', 'from X')
    $xa = Invoke-K $homeX 'KSP-X' @('add-goal', '-Path', $dirA, '-Id', 'G7', '-Text', 'from X')
    $xNothing = (Get-WriteSnapshot $dirA $homeX) -eq $snap3
    Add-Case 'PEOPLE-two-files-90' (($xPeople.Count -eq 2) -and ($xw.Code -eq 90) -and ($xa.Code -eq 90) -and ($xw.Err -match 'join -As <person id> -Clear') -and $xNothing) "$($xPeople.Count) person files list the machine; note-friction exit $($xw.Code), add-goal exit $($xa.Code), wrote nothing: $xNothing"
    $xDrop = if ($xPeople.Count -ge 2) { [string]$xPeople[1].id } else { 'p-0000' }
    $xc = Invoke-K $homeX 'KSP-X' @('join', '-Path', $dirA, '-As', $xDrop, '-Clear')
    $xw2 = Invoke-K $homeX 'KSP-X' @('note-friction', '-Path', $dirA, '-Phase', 'W1.2', '-Kind', 'gap', '-Detail', 'from X after clear')
    Add-Case 'PEOPLE-clear-then-write' (($xc.Code -eq 0) -and ($xw2.Code -eq 0)) "join -As <id> -Clear exit $($xc.Code); the same write then exits $($xw2.Code)"

    # ================================================================ BIND ==
    $side = Join-Path $scratch 'side'
    New-Repo $side 'Side'
    [System.IO.File]::WriteAllText((Join-Path $side 'one.txt'), "one`n")
    Save-Commit $side 'side'
    Assert-K $homeA 'KSP-A' @('add-repo', '-Path', $dirA, '-Name', 'side', '-RepoPath', $side) | Out-Null
    foreach ($bp in @('W3.1', 'W3.2')) {
        Assert-K $homeA 'KSP-A' @('revise-phase', '-Path', $dirA, '-Phase', $bp, '-Repos', 'side') | Out-Null
        Write-Artifacts (Get-ArtDir $dirA $homeA $bp -AShared) $bp @('side')
    }
    $b1 = Invoke-Gates $homeA 'KSP-A' $dirA 'W3.1' $AllGates
    $bWarn = @(@('human', 'enact', 'record') | Where-Object { $b1[$_] -match 'progress[/\\]' })
    Add-Case 'BIND-progress-exempt' ($bWarn.Count -eq 0) "gates after verify naming a progress/ file: $(if ($bWarn.Count) { $bWarn -join ', ' } else { 'none' })"
    Invoke-Gates $homeA 'KSP-A' $dirA 'W3.2' @('ground', 'investigate', 'plan', 'implement', 'verify') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $side 'one.txt'), "one changed`n")
    $b2 = Invoke-Gates $homeA 'KSP-A' $dirA 'W3.2' @('human')
    Add-Case 'BIND-repo-CONTROL' (($b2['human'] -match 'one\.txt') -and ($b2['human'] -notmatch 'progress[/\\]')) "a declared repo's file changed after verify is named at human: $($b2['human'] -match 'one\.txt')"
    Invoke-Gates $homeA 'KSP-A' $dirA 'W3.2' @('enact', 'record') | Out-Null

    # ================================================================ FOLD ==
    Assert-K $homeA 'KSP-A' @('note-friction', '-Path', $dirA, '-Phase', 'W3.1', '-Kind', 'gap', '-Detail', 'fold friction') | Out-Null
    Assert-K $homeA 'KSP-A' @('open-question', '-Path', $dirA, '-Phase', 'W3.1', '-Question', 'fold question', '-Answer', 'yes') | Out-Null
    $fv0 = Get-View $homeA 'KSP-A' $dirA @('W3.1', 'W3.2')
    $fc = Invoke-K $homeA 'KSP-A' @('close', '-Path', $dirA, '-Ws', 'W3')
    $fv1 = Get-View $homeA 'KSP-A' $dirA @('W3.1', 'W3.2')
    # The one line close itself moves: tree marks W3 delivered. Every other line stays.
    $fd = @(Compare-View $fv0 $fv1 '^ +W3 \[workstream\] ')
    $foldFile = Join-Path $dirA 'progress\closed\W3.json'
    $leftFiles = @(Get-ChildItem -LiteralPath (Join-Path $dirA 'progress\phases\W3.1') -Recurse -File | Where-Object { $_.FullName -notmatch '\\artifacts\\' })
    $artLeft = @(Get-ChildItem -LiteralPath (Join-Path $dirA 'progress\phases\W3.1\artifacts') -File -ErrorAction SilentlyContinue)
    $nodeW3 = Read-JsonFile (Join-Path $dirA 'progress\nodes\W3.json')
    $nodeOk = ($null -ne $nodeW3.PSObject.Properties['phaseStages']) -and ([string]$nodeW3.phaseStages.'W3.1' -eq 'delivered') -and ([string]$nodeW3.phaseStages.'W3.2' -eq 'delivered') -and (@($nodeW3.handedOver.PSObject.Properties).Count -eq 0)
    Add-Case 'FOLD-close' (($fc.Code -eq 0) -and (Test-Path -LiteralPath $foldFile) -and ($leftFiles.Count -eq 0) -and ($artLeft.Count -gt 0) -and $nodeOk) "close exit $($fc.Code), fold file, $($leftFiles.Count) phase file(s) left, $($artLeft.Count) artifact(s) kept, node stages: $nodeOk"
    Add-Case 'FOLD-close-same-view' ($fd.Count -eq 0) "lines that differ before and after the fold: $($fd.Count)$(if ($fd.Count) { ': ' + (@($fd | Select-Object -First 4) -join ' / ') })"
    # Control: the fold file with one phase's friction and questions removed shows in -Phase.
    $foldText = [System.IO.File]::ReadAllText($foldFile)
    $foldObj = $foldText | ConvertFrom-Json
    foreach ($fp in @($foldObj.phases)) { if ($fp.id -eq 'W3.1') { $fp.friction = @(); $fp.questions = @() } }
    [System.IO.File]::WriteAllText($foldFile, ($foldObj | ConvertTo-Json -Depth 14))
    $fv2 = Get-View $homeA 'KSP-A' $dirA @('W3.1')
    [System.IO.File]::WriteAllText($foldFile, $foldText)
    $fd2 = @(Compare-View (Get-View $homeA 'KSP-A' $dirA @('W3.1')) $fv2)
    Add-Case 'FOLD-entries-CONTROL' (@($fd2 | Where-Object { $_ -match 'fold friction|fold question' }).Count -gt 0) "a fold without W3.1's entries changes status -Phase W3.1 by $($fd2.Count) line(s)"

    Assert-K $homeA 'KSP-A' @('abandon', '-Path', $dirA, '-Phase', 'W4.1', '-Detail', 'never ran') | Out-Null
    $av0 = Get-View $homeA 'KSP-A' $dirA @('W4.1')
    $ab = Invoke-K $homeA 'KSP-A' @('abandon', '-Path', $dirA, '-Ws', 'W4', '-Detail', 'never ran')
    $av1 = Get-View $homeA 'KSP-A' $dirA @('W4.1')
    $adAllow = '^ +W4 \[workstream\] |^ +abandoned: never ran$|^G2  CLAIMED by '
    $ad = @(Compare-View $av0 $av1 $adAllow)
    # The one line that should move: tree marks W4 abandoned. Every other line stays.
    $adOther = $ad
    $w4Left = @(Get-ChildItem -LiteralPath (Join-Path $dirA 'progress\phases\W4.1') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\artifacts\\' })
    Add-Case 'FOLD-abandon' (($ab.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $dirA 'progress\closed\W4.json')) -and ($w4Left.Count -eq 0) -and ($adOther.Count -eq 0)) "abandon -Ws exit $($ab.Code), fold file, $($w4Left.Count) phase file(s) left, unexpected view changes: $($adOther.Count)"

    # ================================================================ LIST ==
    $ls = Invoke-K $homeA 'KSP-A' @('list')
    $lsRow = @($ls.Lines | Where-Object { $_ -match "^$slug\s+shared" -and $_.Contains($dirA) })
    $lsFile = @(Get-ChildItem -LiteralPath (Join-Path $homeA ".keel\projects\$slug") -Filter 'state.json.shared-*' -File)
    $lsAside = Join-Path $scratch 'aside'
    New-Item -ItemType Directory -Path $lsAside -Force | Out-Null
    foreach ($lf in $lsFile) { Move-Item -LiteralPath $lf.FullName -Destination $lsAside }
    $ls2 = Invoke-K $homeA 'KSP-A' @('list')
    foreach ($lf in @(Get-ChildItem -LiteralPath $lsAside -File)) { Move-Item -LiteralPath $lf.FullName -Destination (Join-Path $homeA ".keel\projects\$slug") }
    Add-Case 'LIST-shared' ($lsRow.Count -eq 1) "rows naming the project as shared with its root: $($lsRow.Count)"
    Add-Case 'LIST-shared-CONTROL' (@($ls2.Lines | Where-Object { $_ -match "^$slug\s" }).Count -eq 0) "with the renamed state file put aside, rows naming it: $(@($ls2.Lines | Where-Object { $_ -match "^$slug\s" }).Count)"

    # =========================================== REFUSE: nothing per machine is committed ==
    Save-Commit $dirA 'everything'
    $perMachine = '(^|/)state\.json|^progress/phases/[^/]+/artifacts/[^/]+/|(^|/)(quarantine|markers|signals)/|(^|/)\.keel/'
    $lsf = (Invoke-G $dirA @('ls-files')).Out -split "`n" | Where-Object { $_ -match $perMachine }
    $plant = Join-Path $dirA 'progress\phases\W1.1\artifacts\scratch'
    New-Item -ItemType Directory -Path $plant -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $plant 'copy-of-state.json'), '{}')
    Assert-G $dirA @('add', '-A') | Out-Null
    $lsf2 = (Invoke-G $dirA @('ls-files')).Out -split "`n" | Where-Object { $_ -match $perMachine }
    Assert-G $dirA @('rm', '-q', '-r', '--cached', 'progress/phases/W1.1/artifacts/scratch') | Out-Null
    Remove-Item -LiteralPath $plant -Recurse -Force
    Add-Case 'REFUSE-nothing-per-machine' (@($lsf).Count -eq 0) "tracked files of a kind kept per machine: $(@($lsf).Count)"
    Add-Case 'REFUSE-nothing-per-machine-CONTROL' (@($lsf2).Count -eq 1) "one planted scratch file staged is listed: $(@($lsf2).Count)"

    # ============================================================== MACHINE ==
    $homeM = New-Home 'M'
    $dirM = Join-Path $scratch "machine\pm$runTag"
    New-Repo $dirM 'Person M'
    Assert-K $homeM 'KSP-M' @('init-project', '-Path', $dirM, '-Title', 'per machine') | Out-Null
    Save-Commit $dirM 'project'
    Assert-K $homeM 'KSP-M' @('add-goal', '-Path', $dirM, '-Id', 'G1', '-Text', 'goal') | Out-Null
    Assert-K $homeM 'KSP-M' @('add-workstream', '-Path', $dirM, '-Id', 'W1', '-Title', 'ws', '-Parent', 'root', '-Goals', 'G1') | Out-Null
    Assert-K $homeM 'KSP-M' @('add-phase', '-Path', $dirM, '-Phase', 'W1.1', '-Scope', 'one', '-Actor', 'agent', '-RunOrder', '1') | Out-Null
    Write-Artifacts (Get-ArtDir $dirM $homeM 'W1.1') 'W1.1'
    Invoke-Gates $homeM 'KSP-M' $dirM 'W1.1' $AllGates | Out-Null
    Assert-K $homeM 'KSP-M' @('note-friction', '-Path', $dirM, '-Phase', 'W1.1', '-Kind', 'gap', '-Detail', 'per machine') | Out-Null
    $mState = Join-Path $homeM ".keel\projects\pm$runTag\state.json"
    $mSt = Invoke-G $dirM @('status', '--porcelain', '--untracked-files=all')
    Add-Case 'MACHINE-unchanged' ((Test-Path -LiteralPath $mState) -and ($mSt.Code -eq 0) -and [string]::IsNullOrWhiteSpace($mSt.Out) -and -not (Test-Path -LiteralPath (Join-Path $dirM 'progress'))) "state per machine: $(Test-Path -LiteralPath $mState); git status clean: $([string]::IsNullOrWhiteSpace($mSt.Out)); no progress/"
    $aSt = Invoke-G $dirA @('status', '--porcelain', '--untracked-files=all')
    Assert-K $homeA 'KSP-A' @('note-friction', '-Path', $dirA, '-Phase', 'W1.2', '-Kind', 'gap', '-Detail', 'shared control') | Out-Null
    $aSt2 = Invoke-G $dirA @('status', '--porcelain', '--untracked-files=all')
    Add-Case 'MACHINE-unchanged-CONTROL' ([string]::IsNullOrWhiteSpace($aSt.Out) -and ($aSt2.Out -match 'progress/')) "on the shared project the same kind of write leaves files for git status: $($aSt2.Out -match 'progress/')"

    # ============================================================== EXPORT ==
    function Invoke-ExportCase {
        param([string]$EcLabel, [string]$EcHome, [string]$EcDir, [string[]]$EcPhases, [string]$EcMissing)
        $ecBefore = Get-View $EcHome 'KSP-E' $EcDir $EcPhases
        $ecRes = Invoke-K $EcHome 'KSP-E' @('share-progress', '-Path', $EcDir)
        $ecAfter = Get-View $EcHome 'KSP-E' $EcDir $EcPhases
        $ecDiff = @(Compare-View $ecBefore $ecAfter)
        Add-Case "EXPORT-$EcLabel-same-view" (($ecRes.Code -eq 0) -and ($ecDiff.Count -eq 0)) "share-progress exit $($ecRes.Code); lines that differ: $($ecDiff.Count)$(if ($ecDiff.Count) { ': ' + (@($ecDiff | Select-Object -First 4) -join ' / ') })"
        $ecPeople = @(Get-ChildItem -LiteralPath (Join-Path $EcDir 'progress\people') -Filter '*.json' -ErrorAction SilentlyContinue)
        $ecPid = if ($ecPeople.Count -eq 1) { $ecPeople[0].BaseName } else { '' }
        $ecBad = @(Get-FriendlyFiles $EcDir | Where-Object {
            $ecO = Read-JsonFile (Join-Path (Join-Path $EcDir 'progress') ($_ -replace '/', '\'))
            $ecSrc = $ecO.PSObject.Properties['source']
            ($null -eq $ecSrc) -or ([string]$ecSrc.Value -ne 'export') -or ([string]$ecO.by -ne $ecPid)
        })
        Add-Case "EXPORT-$EcLabel-exported" (($ecPid -ne '') -and ($ecBad.Count -eq 0)) "files not marked exported or not naming the exporter: $($ecBad.Count)"
        $ecSt = Read-JsonFile (Join-Path $EcHome ".keel\projects\$(Split-Path -Leaf $EcDir)\state.json.shared-$((Get-Date).ToString('yyyy-MM-dd'))")
        $ecClosed = @(@($ecSt.nodes) | Where-Object { $_.role -eq 'workstream' -and $_.PSObject.Properties['status'] -and @('DELIVERED', 'ABANDONED') -contains [string]$_.status })
        $ecUnfolded = @($ecClosed | Where-Object {
            $ecW = $_.id
            -not (Test-Path -LiteralPath (Join-Path $EcDir "progress\closed\$ecW.json")) -or @(@($ecSt.phases) | Where-Object { $_.ws -eq $ecW -and (Test-Path -LiteralPath (Join-Path $EcDir "progress\phases\$($_.id)\phase.json")) }).Count -gt 0
        })
        $ecCfg = Read-JsonFile (Join-Path $EcDir 'keel.json')
        $ecGone = -not (Test-Path -LiteralPath (Join-Path $EcHome ".keel\projects\$(Split-Path -Leaf $EcDir)\state.json"))
        Add-Case "EXPORT-$EcLabel-folded-switched" (($ecClosed.Count -gt 0) -and ($ecUnfolded.Count -eq 0) -and ([string]$ecCfg.progress -eq 'repo') -and $ecGone) "$($ecClosed.Count) closed or abandoned workstream(s), $($ecUnfolded.Count) not folded; keel.json progress '$($ecCfg.progress)'; state.json renamed: $ecGone"
        # Control: the same view with one phase's declaration deleted names that phase.
        $ecDecl = Join-Path $EcDir "progress\phases\$EcMissing\phase.json"
        $ecKeep = [System.IO.File]::ReadAllBytes($ecDecl)
        Remove-Item -LiteralPath $ecDecl
        $ecGap = @(Compare-View $ecBefore (Get-View $EcHome 'KSP-E' $EcDir $EcPhases))
        [System.IO.File]::WriteAllBytes($ecDecl, $ecKeep)
        Add-Case "EXPORT-$EcLabel-missing-CONTROL" (@($ecGap | Where-Object { $_ -match [regex]::Escape($EcMissing) }).Count -gt 0) "with $EcMissing's phase.json deleted, differing lines naming it: $(@($ecGap | Where-Object { $_ -match [regex]::Escape($EcMissing) }).Count)"
    }

    $dirE = Join-Path $scratch "export\ex$runTag"
    New-Repo $dirE 'Person E'
    Assert-K $homeE 'KSP-E' @('init-project', '-Path', $dirE, '-Title', 'export') $v001Wrapper | Out-Null
    $ek = @(
        @('add-goal', '-Id', 'G1', '-Text', 'goal one'), @('add-goal', '-Id', 'G2', '-Text', 'goal two'),
        @('set-goal-status', '-Id', 'G2', '-Status', 'UNADDRESSED', '-Detail', 'not yet'),
        @('add-epic', '-Id', 'E1', '-Title', 'an epic', '-Parent', 'root', '-Groups', 'the closed work'),
        @('add-workstream', '-Id', 'W1', '-Title', 'closed one', '-Parent', 'E1', '-Goals', 'G1'),
        @('add-workstream', '-Id', 'W2', '-Title', 'abandoned one', '-Parent', 'root', '-Goals', 'G1'),
        @('add-workstream', '-Id', 'W3', '-Title', 'open one', '-Parent', 'root', '-Goals', 'G1'),
        @('add-phase', '-Phase', 'W1.1', '-Scope', 'delivered', '-Actor', 'agent', '-RunOrder', '1'),
        @('add-phase', '-Phase', 'W1.2', '-Scope', 'abandoned in a closed ws', '-Actor', 'self', '-RunOrder', '2'),
        @('add-phase', '-Phase', 'W2.1', '-Scope', 'never ran', '-Actor', 'agent', '-RunOrder', '1'),
        @('add-phase', '-Phase', 'W3.1', '-Scope', 'delivered open', '-Actor', 'agent', '-RunOrder', '1'),
        @('add-phase', '-Phase', 'W3.2', '-Scope', 'waiting', '-Actor', 'external', '-RunOrder', '2'),
        @('add-phase', '-Phase', 'W3.3', '-Scope', 'in flight', '-Actor', 'agent', '-RunOrder', '3'),
        @('add-phase', '-Phase', 'W3.4', '-Scope', 'planned', '-Actor', 'agent', '-RunOrder', '4', '-Due', '2099-01-01')
    )
    foreach ($ec in $ek) { Assert-K $homeE 'KSP-E' (@($ec[0]) + @('-Path', $dirE) + @($ec | Select-Object -Skip 1)) | Out-Null }
    foreach ($ep in @('W1.1', 'W3.1')) { Write-Artifacts (Get-ArtDir $dirE $homeE $ep) $ep; Invoke-Gates $homeE 'KSP-E' $dirE $ep $AllGates | Out-Null }
    Write-Artifacts (Get-ArtDir $dirE $homeE 'W3.3') 'W3.3'
    Invoke-Gates $homeE 'KSP-E' $dirE 'W3.3' @('ground', 'investigate') | Out-Null
    $ek2 = @(
        @('abandon', '-Phase', 'W1.2', '-Detail', 'not needed'), @('close', '-Ws', 'W1'),
        @('abandon', '-Phase', 'W2.1', '-Detail', 'never ran'), @('abandon', '-Ws', 'W2', '-Detail', 'never ran'),
        @('revise-phase', '-Phase', 'W3.1', '-Correction', 'a correction'),
        @('set-waiting', '-Phase', 'W3.2', '-WaitingOn', 'a third party', '-ReviewOn', '2099-01-01'),
        @('note-friction', '-Phase', 'W3.3', '-Kind', 'gap', '-Detail', 'friction one'),
        @('note-friction', '-Phase', 'W3.3', '-Kind', 'rework', '-Detail', 'friction two'),
        @('open-question', '-Phase', 'W3.3', '-Question', 'a question', '-Answer', 'an answer'),
        @('new-iteration', '-Phase', 'W3.3', '-Trigger', 'plan', '-Detail', 'a round'),
        @('lift-cap', '-Phase', 'W3.3', '-Rounds', '2', '-Detail', 'operator words'),
        @('ack-keel-version', '-Detail', 'suite acknowledgement')
    )
    foreach ($ec in $ek2) { Assert-K $homeE 'KSP-E' (@($ec[0]) + @('-Path', $dirE) + @($ec | Select-Object -Skip 1)) | Out-Null }
    Save-Commit $dirE 'project'
    Invoke-ExportCase 'synthetic' $homeE $dirE @('W1.1', 'W1.2', 'W2.1', 'W3.1', 'W3.2', 'W3.3') 'W3.4'
    $LayoutDirs.Add($dirE)

    # ============================================================== REFUSE ==
    function New-Candidate {
        param([string]$NcLabel, [string]$NcUser, [string[]]$NcInit)
        $ncHome = New-Home "R-$NcLabel"
        $ncDir = Join-Path $scratch "refuse\$NcLabel$runTag"
        New-Repo $ncDir $NcUser
        Assert-K $ncHome 'KSP-R' (@('init-project', '-Path', $ncDir, '-Title', "refuse $NcLabel") + @($NcInit)) | Out-Null
        Assert-K $ncHome 'KSP-R' @('add-goal', '-Path', $ncDir, '-Id', 'G1', '-Text', 'goal') | Out-Null
        Save-Commit $ncDir 'project'
        return [pscustomobject]@{ Home = $ncHome; Dir = $ncDir }
    }
    function Set-CfgField {
        param([string]$ScDir, [string]$ScField, $ScValue)
        $scFile = Join-Path $ScDir 'keel.json'
        $scObj = Read-JsonFile $scFile
        $scObj.$ScField = $ScValue
        [System.IO.File]::WriteAllText($scFile, ($scObj | ConvertTo-Json -Depth 8))
        Save-Commit $ScDir "set $ScField"
    }
    function Test-Refusal {
        param([string]$TrLabel, $TrCand, [int]$TrCode, [string]$TrPhrase, [scriptblock]$TrRemove)
        $trSnap = Get-WriteSnapshot $TrCand.Dir $TrCand.Home
        $trRes = Invoke-K $TrCand.Home 'KSP-R' @('share-progress', '-Path', $TrCand.Dir)
        $trSame = (Get-WriteSnapshot $TrCand.Dir $TrCand.Home) -eq $trSnap
        Add-Case "REFUSE-$TrLabel" (($trRes.Code -eq $TrCode) -and ($trRes.Err -match $TrPhrase) -and $trSame) "exit $($trRes.Code), names its reason: $($trRes.Err -match $TrPhrase), wrote nothing: $trSame"
        & $TrRemove
        $trCtl = Invoke-K $TrCand.Home 'KSP-R' @('share-progress', '-Path', $TrCand.Dir)
        Add-Case "REFUSE-$TrLabel-CONTROL" ($trCtl.Code -eq 0) "with that one condition removed the export exits $($trCtl.Code)"
    }
    $cq = New-Candidate 'quar' 'Person R' @('-Quarantine')
    Test-Refusal 'quarantine' $cq 90 'quarantine on' { Set-CfgField $cq.Dir 'quarantine' $false }
    $cg = New-Candidate 'nogit' 'Person R' @('-NoGit')
    Test-Refusal 'git-false' $cg 90 'git: false' { Set-CfgField $cg.Dir 'git' $true }
    $cd = New-Candidate 'dirty' 'Person R' @()
    [System.IO.File]::WriteAllText((Join-Path $cd.Dir 'notes.txt'), "uncommitted`n")
    Test-Refusal 'uncommitted' $cd 90 'uncommitted changes' { Save-Commit $cd.Dir 'notes' }
    $cn = New-Candidate 'noname' '' @()
    Test-Refusal 'no-user-name' $cn 95 'git -C .* config user\.name' { Assert-G $cn.Dir @('config', 'user.name', 'Person R') | Out-Null }
    Save-Commit $cd.Dir 'exported'
    $snapS = Get-WriteSnapshot $cd.Dir $cd.Home
    $again = Invoke-K $cd.Home 'KSP-R' @('share-progress', '-Path', $cd.Dir)
    Add-Case 'REFUSE-already-shared' (($again.Code -eq 90) -and ($again.Err -match 'already shares') -and ((Get-WriteSnapshot $cd.Dir $cd.Home) -eq $snapS)) "a second export exits $($again.Code), names its reason, wrote nothing; its control is REFUSE-uncommitted-CONTROL's export"

    # ============================================================== LAYOUT ==
    $allProblems = New-Object System.Collections.Generic.List[string]
    foreach ($ld in $LayoutDirs) { foreach ($lp in @(Test-ProgressFiles $ld)) { $allProblems.Add("$(Split-Path -Leaf (Split-Path -Parent $ld))/$lp") } }
    Add-Case 'LAYOUT-every-file' ($allProblems.Count -eq 0) "problems across $($LayoutDirs.Count) fixture project(s): $($allProblems.Count)$(if ($allProblems.Count) { ': ' + (@($allProblems | Select-Object -First 5) -join ' / ') })"
    $kindsWanted = @($KindFields.Keys | Sort-Object)
    $kindsMissing = @($kindsWanted | Where-Object { -not $script:KindsSeen.ContainsKey($_) })
    Add-Case 'LAYOUT-all-13-kinds' (($kindsWanted.Count -eq 13) -and ($kindsMissing.Count -eq 0)) "$($kindsWanted.Count) kinds named, missing from the fixtures: $(if ($kindsMissing.Count) { $kindsMissing -join ', ' } else { 'none' })"
    # Control: four planted files, one defect each, and one clean file, in a tree of their own.
    $pl = Join-Path $scratch 'planted'
    $plFr = Join-Path $pl 'progress\phases\W1.1\friction'
    New-Item -ItemType Directory -Path $plFr -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $pl 'progress\people') -Force | Out-Null
    $plEnc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $pl 'progress\people\p-00aa.json'), "{ `"id`": `"p-00aa`", `"name`": `"P`", `"machines`": [`"M`"], `"by`": `"p-00aa`", `"machine`": `"M`", `"at`": `"2026-01-01T00:00:00+00:00`" }`n", $plEnc)
    $plGood = '"kind": "gap", "detail": "d", "machine": "M"'
    [System.IO.File]::WriteAllText((Join-Path $plFr '20260101T000000Z-p-00aa-0001.json'), "{ $plGood, `"by`": `"p-00aa`", `"at`": `"2026-01-01T00:00:00+00:00`" }`n", $plEnc)
    [System.IO.File]::WriteAllText((Join-Path $plFr '20260101T000000Z-p-00aa-0002.json'), "{ $plGood, `"at`": `"2026-01-01T00:00:00+00:00`" }`n", $plEnc)
    [System.IO.File]::WriteAllText((Join-Path $plFr '20260101T000000Z-p-00aa-0003.json'), "{ $plGood, `"by`": `"p-00aa`", `"at`": `"2026-01-01T00:00:00`" }`n", $plEnc)
    [System.IO.File]::WriteAllText((Join-Path $plFr '20260101T000000Z-p-00aa-0004.json'), "{ $plGood, `"by`": `"p-00aa`", `"at`": `"2026-01-01T00:00:00+00:00`", `"extra`": 1 }`n", $plEnc)
    [System.IO.File]::WriteAllText((Join-Path $plFr '20260101T000000Z-p-00aa-0005.json'), "{ $plGood, `"by`": `"p-00aa`", `"at`": `"2026-01-01T00:00:00+00:00`" }`n", (New-Object System.Text.UTF8Encoding($true)))
    $plProb = @(Test-ProgressFiles $pl)
    $plWant = @(@('0002', "no 'by'"), @('0003', 'no UTC offset'), @('0004', 'fields its kind does not'), @('0005', 'byte-order mark'))
    $plHit = @($plWant | Where-Object { $plW = $_; @($plProb | Where-Object { $_ -match $plW[0] -and $_ -match [regex]::Escape($plW[1]) }).Count -gt 0 })
    $plClean = @($plProb | Where-Object { $_ -match '0001|people/' }).Count -eq 0
    Add-Case 'LAYOUT-planted-CONTROL' (($plHit.Count -eq 4) -and $plClean) "of four planted defects $($plHit.Count) reported; the clean file and the person file reported: $(-not $plClean)"

    # ============================================================== ORIENT ==
    # Its own bare remote and two clones, so no earlier group's state reaches it. Not added to the
    # LAYOUT sweep: MERGE plants defects in it on purpose.
    function Save-Push {
        param([string]$SuDir, [string]$SuMsg)
        Save-Commit $SuDir $SuMsg
        Assert-G $SuDir @('push', '-q') | Out-Null
    }
    function Sync-Pair {
        # Both sides commit what they wrote offline; the second pushes first, the first merges it
        # with plain git pull and pushes, and the second pulls that back.
        param([string]$SyFirst, [string]$SySecond, [string]$SyMsg)
        Save-Commit $SyFirst "$SyMsg (first)"
        Save-Commit $SySecond "$SyMsg (second)"
        Assert-G $SySecond @('push', '-q') | Out-Null
        Assert-G $SyFirst @('pull', '-q', '--no-edit') | Out-Null
        Assert-G $SyFirst @('push', '-q') | Out-Null
        Assert-G $SySecond @('pull', '-q', '--no-edit') | Out-Null
    }
    function Save-Part {
        # A partial commit, pushed: only the paths named, as a person who stages by hand might.
        param([string]$PtDir, [string[]]$PtPaths, [string]$PtMsg)
        foreach ($ptP in $PtPaths) { Assert-G $PtDir @('add', '--', $ptP) | Out-Null }
        $ptRes = Invoke-G $PtDir @('-c', 'user.name=Suite Committer', 'commit', '-q', '-m', $PtMsg)
        if ($ptRes.Code -ne 0) { throw "Setup partial commit failed: $($ptRes.Out)" }
        Assert-G $PtDir @('push', '-q') | Out-Null
    }
    function Assert-LocalOrigin {
        # The fence for every call this group makes with the outward block lifted.
        param([string]$LoDir)
        $loUrl = (Invoke-G $LoDir @('config', '--get', 'remote.origin.url')).Out.Trim()
        $loFull = [System.IO.Path]::GetFullPath($loUrl).TrimEnd('\', '/')
        if (-not $loFull.StartsWith($scratch + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'An ORIENT clone''s origin is not inside the scratch home, so the outward block stays on.' }
    }
    function Get-OrStatus {
        # status as a person sees it, reading the bare remote.
        param([string]$OsHome, [string]$OsMachine, [string]$OsDir)
        Assert-LocalOrigin $OsDir
        return (Invoke-K $OsHome $OsMachine @('status', '-Path', $OsDir) '' 'allow')
    }
    function Get-OrBoth {
        # status and tree, joined, for the read-time check (no remote reading needed).
        param([string]$ObHome, [string]$ObMachine, [string]$ObDir)
        $obS = Invoke-K $ObHome $ObMachine @('status', '-Path', $ObDir)
        $obT = Invoke-K $ObHome $ObMachine @('tree', '-Path', $ObDir)
        return [pscustomobject]@{ S = $obS.Out; T = $obT.Out }
    }
    function Get-PorcelainCount {
        param([string]$PcDir, [switch]$PcAll)
        $pcArgs = @('status', '--porcelain')
        if ($PcAll) { $pcArgs += '--untracked-files=all' }
        $pcArgs += @('--', 'progress')
        return @((Invoke-G $PcDir $pcArgs).Out -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    }
    function Get-LatestAt {
        # The latest 'at' anywhere under progress/, every "at" field of every file, as an instant;
        # returned as the stamp text that holds it.
        param([string]$LaDir)
        $laBest = $null; $laText = ''
        foreach ($laF in @(Get-ChildItem -LiteralPath (Join-Path $LaDir 'progress') -Recurse -File -Filter '*.json')) {
            foreach ($laM in [regex]::Matches([System.IO.File]::ReadAllText($laF.FullName), '"at"\s*:\s*"([^"]+)"')) {
                $laI = [DateTimeOffset]::MinValue
                if ([DateTimeOffset]::TryParse($laM.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$laI)) {
                    if ($null -eq $laBest -or $laI -gt $laBest) { $laBest = $laI; $laText = $laM.Groups[1].Value }
                }
            }
        }
        return $laText
    }

    $oRemote = Join-Path $scratch 'oremote.git'
    New-Item -ItemType Directory -Path $oRemote -Force | Out-Null
    Assert-G $oRemote @('init', '-q', '--bare', '-b', 'main') | Out-Null
    $oSlug = 'kor' + $runTag
    $homeP = New-Home 'P'; $homeQ = New-Home 'Q'; $homeU = New-Home 'U'; $homeR3 = New-Home 'R3'; $homeY = New-Home 'Y'; $homeZ = New-Home 'Z'
    $dirP = Join-Path $scratch "cloneP\$oSlug"
    $dirQ = Join-Path $scratch "cloneQ\$oSlug"
    New-Repo $dirP 'Person P'
    Assert-G $dirP @('remote', 'add', 'origin', $oRemote) | Out-Null
    Assert-K $homeP 'KSP-P' @('init-project', '-Path', $dirP, '-Title', 'orientation') | Out-Null
    Assert-K $homeP 'KSP-P' @('add-goal', '-Path', $dirP, '-Id', 'G1', '-Text', 'first goal') | Out-Null
    foreach ($ow in @('W1', 'W2', 'W3', 'W5', 'W6', 'W7', 'W8', 'W9')) {
        Assert-K $homeP 'KSP-P' @('add-workstream', '-Path', $dirP, '-Id', $ow, '-Title', "workstream $ow", '-Parent', 'root', '-Goals', 'G1') | Out-Null
    }
    foreach ($opl in @(@('W1.1', 1), @('W1.2', 2))) {
        Assert-K $homeP 'KSP-P' @('add-phase', '-Path', $dirP, '-Phase', $opl[0], '-Scope', "phase $($opl[0])", '-Actor', 'agent', '-RunOrder', "$($opl[1])") | Out-Null
    }
    Save-Commit $dirP 'project'
    Assert-K $homeP 'KSP-P' @('share-progress', '-Path', $dirP) | Out-Null
    Save-Commit $dirP 'shared'
    Assert-G $dirP @('push', '-q', '-u', 'origin', 'main') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $scratch 'cloneQ') -Force | Out-Null
    Assert-G (Join-Path $scratch 'cloneQ') @('clone', '-q', $oRemote, $oSlug) | Out-Null
    foreach ($oc in @(@('user.name', 'Person Q'), @('user.email', 'suite@example.invalid'), @('pull.rebase', 'false'), @('core.autocrlf', 'false'))) { Assert-G $dirQ @('config', $oc[0], $oc[1]) | Out-Null }
    $ojq = Assert-K $homeQ 'KSP-Q' @('join', '-Path', $dirQ)
    $pidQ = if ($ojq.Out -match 'as person (p-[0-9a-f]{4}) ') { $Matches[1] } else { throw 'join on Q printed no person id.' }
    $pidP = [string](@(Get-ChildItem -LiteralPath (Join-Path $dirP 'progress\people') -Filter '*.json' | ForEach-Object { Read-JsonFile $_.FullName } | Where-Object { @($_.machines) -contains 'KSP-P' })[0].id)
    foreach ($opl in @(@('W2.1', 1), @('W2.2', 2))) {
        Assert-K $homeQ 'KSP-Q' @('add-phase', '-Path', $dirQ, '-Phase', $opl[0], '-Scope', "phase $($opl[0])", '-Actor', 'agent', '-RunOrder', "$($opl[1])") | Out-Null
    }
    Save-Push $dirQ 'Q joins and plans'
    Assert-G $dirP @('pull', '-q', '--no-edit') | Out-Null

    # ---- NEXT: next per person, and others:
    $nP = Get-OrStatus $homeP 'KSP-P' $dirP
    $nQ = Get-OrStatus $homeQ 'KSP-Q' $dirQ
    $nPok = ($nP.Out -match '(?m)^KEEL:\s+next: W1\.1 ') -and ($nP.Out -match "(?m)^KEEL:\s+others: Person Q \($pidQ\): W2\.1$") -and ($nP.Out -notmatch 'next is ambiguous')
    $nQok = ($nQ.Out -match '(?m)^KEEL:\s+next: W2\.1 ') -and ($nQ.Out -match "(?m)^KEEL:\s+others: Person P \($pidP\): W1\.1$") -and ($nQ.Out -notmatch 'next is ambiguous')
    Add-Case 'ORIENT-next-per-person' ($nPok -and $nQok) "P's next W1.1 and others names Person Q with W2.1: $nPok; Q's next W2.1 and others names Person P with W1.1: $nQok (a whole-project rule would print the ambiguity, W1.1 and W2.1 both #1)"
    Assert-K $homeP 'KSP-P' @('add-phase', '-Path', $dirP, '-Phase', 'W3.1', '-Scope', 'phase W3.1', '-Actor', 'agent', '-RunOrder', '1') | Out-Null
    Save-Push $dirP 'W3.1'
    Assert-G $dirQ @('pull', '-q', '--no-edit') | Out-Null
    $nP2 = Get-OrStatus $homeP 'KSP-P' $dirP
    $nQ2 = Get-OrStatus $homeQ 'KSP-Q' $dirQ
    $nTieOk = ($nP2.Out -match 'WARNING: next is ambiguous - 2 phases share the lowest run order 1, across 2 workstream') -and ($nP2.Out -match '(?m)^KEEL:\s+W1\.1  ') -and ($nP2.Out -match '(?m)^KEEL:\s+W3\.1  ') -and ($nP2.Out -notmatch '(?m)^KEEL:\s+next: W')
    $nTieQ = $nQ2.Out -match "(?m)^KEEL:\s+others: Person P \($pidP\): ambiguous, W1\.1 or W3\.1$"
    Add-Case 'ORIENT-next-tie' ($nTieOk -and $nTieQ) "P's own lowest order shared across two workstreams prints the ambiguity warning: $nTieOk; Q's others says ambiguous: $nTieQ"
    $nU = Get-OrStatus $homeU 'KSP-U' $dirP
    $nUok = ($nU.Out -match "note: next: is over everyone's phases") -and ($nU.Out -match 'next is ambiguous - 3 phases share the lowest run order 1, across 3 workstream') -and ($nU.Out -notmatch 'others:')
    Add-Case 'ORIENT-next-unregistered' $nUok "a machine no person file lists is told next is everyone's and sees the whole project's tie of W1.1, W2.1 and W3.1: $nUok"
    Assert-K $homeP 'KSP-P' @('abandon', '-Path', $dirP, '-Phase', 'W3.1', '-Detail', 'tie case done') | Out-Null
    Save-Push $dirP 'W3.1 abandoned'
    Assert-G $dirQ @('pull', '-q', '--no-edit') | Out-Null

    # Control: a project kept per machine prints what HEAD's wrapper prints, and no others: line.
    $headW = Join-Path $scratch 'headw\plugins\keel-workflow'
    New-Item -ItemType Directory -Path (Join-Path $headW 'skills\keel-orchestrator\wrappers') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $headW '.claude-plugin') -Force | Out-Null
    $headText = (Invoke-G $repoRoot @('show', "HEAD:$wrapperRel")).Out
    $headWrapper = Join-Path $headW 'skills\keel-orchestrator\wrappers\keel-state.ps1'
    [System.IO.File]::WriteAllText($headWrapper, (($headText -replace "`r`n", "`n") -replace "`n", "`r`n") + "`r`n")
    Copy-Item -LiteralPath (Join-Path $repoRoot 'plugins\keel-workflow\.claude-plugin\plugin.json') -Destination (Join-Path $headW '.claude-plugin\plugin.json')
    $headSame = (($headText -replace "`r`n", "`n").TrimEnd()) -eq ((([System.IO.File]::ReadAllText($wtWrapper)) -replace "`r`n", "`n").TrimEnd())
    $homeN = New-Home 'N'
    $dirN = Join-Path $scratch "permachine\pn$runTag"
    New-Repo $dirN 'Person N'
    Assert-K $homeN 'KSP-N' @('init-project', '-Path', $dirN, '-Title', 'per machine next') | Out-Null
    Assert-K $homeN 'KSP-N' @('add-goal', '-Path', $dirN, '-Id', 'G1', '-Text', 'goal') | Out-Null
    foreach ($ow in @('W1', 'W2')) { Assert-K $homeN 'KSP-N' @('add-workstream', '-Path', $dirN, '-Id', $ow, '-Title', "ws $ow", '-Parent', 'root', '-Goals', 'G1') | Out-Null }
    Assert-K $homeN 'KSP-N' @('add-phase', '-Path', $dirN, '-Phase', 'W1.1', '-Scope', 'phase W1.1', '-Actor', 'agent', '-RunOrder', '1') | Out-Null
    Assert-K $homeN 'KSP-N' @('add-phase', '-Path', $dirN, '-Phase', 'W2.1', '-Scope', 'phase W2.1', '-Actor', 'agent', '-RunOrder', '2') | Out-Null
    $mnSame = $true
    $mnLit = $true
    foreach ($mnRound in @(1, 2)) {
        if ($mnRound -eq 2) { Assert-K $homeN 'KSP-N' @('add-phase', '-Path', $dirN, '-Phase', 'W2.2', '-Scope', 'phase W2.2', '-Actor', 'agent', '-RunOrder', '1') | Out-Null }
        foreach ($mnV in @('status', 'tree')) {
            $mnW = Invoke-K $homeN 'KSP-N' @($mnV, '-Path', $dirN)
            $mnH = Invoke-K $homeN 'KSP-N' @($mnV, '-Path', $dirN) $headWrapper
            if ($mnW.Out -cne $mnH.Out -or $mnW.Code -ne $mnH.Code) { $mnSame = $false }
            if ($mnV -eq 'status') {
                if ($mnW.Out -match 'others:') { $mnLit = $false }
                if ($mnRound -eq 1 -and $mnW.Out -notmatch '(?m)^KEEL:\s+next: W1\.1  \(phase W1\.1\)$') { $mnLit = $false }
                if ($mnRound -eq 2 -and $mnW.Out -notmatch 'WARNING: next is ambiguous - 2 phases share the lowest run order 1, across 2 workstream') { $mnLit = $false }
            }
        }
    }
    Add-Case 'ORIENT-next-per-machine-CONTROL' ($mnSame -and $mnLit) "per machine: status and tree equal HEAD's wrapper's: $mnSame$(if ($headSame) { " (HEAD holds this same wrapper, so that half compares it with itself)" }); next: W1.1, then the tie warning, and no others: line: $mnLit"

    # ---- BEHIND
    Assert-K $homeQ 'KSP-Q' @('note-friction', '-Path', $dirQ, '-Phase', 'W2.1', '-Kind', 'gap', '-Detail', 'behind one') | Out-Null
    Save-Commit $dirQ 'behind one'
    Assert-K $homeQ 'KSP-Q' @('note-friction', '-Path', $dirQ, '-Phase', 'W2.1', '-Kind', 'gap', '-Detail', 'behind two') | Out-Null
    Save-Commit $dirQ 'behind two'
    # Control first: committed and not pushed, so the other copy has nothing to pull.
    $bNo = Get-OrStatus $homeP 'KSP-P' $dirP
    $bNoOk = ($bNo.Out -notmatch 'has not pulled|commit\(s\) behind|was NOT checked \(')
    Add-Case 'ORIENT-behind-unpushed-CONTROL' $bNoOk "with Q's commits not pushed, P prints no behind, not-pulled or not-checked line: $bNoOk"
    Assert-G $dirQ @('push', '-q') | Out-Null
    $qSha = (Invoke-G $dirQ @('rev-parse', 'HEAD')).Out.Trim()
    $bUn = Get-OrStatus $homeP 'KSP-P' $dirP
    $bUnOk = ($bUn.Out -match "WARNING: the remote 'origin' holds work this copy has not pulled \($($qSha.Substring(0, 7)) on 'main'\)\. Pull before acting on what follows\.") -and ($bUn.Out -notmatch 'which is not in this clone') -and ($bUn.Out -notmatch 'commit\(s\) behind')
    Add-Case 'ORIENT-behind-not-pulled' $bUnOk "Q pushed and P has not fetched: P names Q's sha as not pulled, and not the old unpushed-count line: $bUnOk"
    $bBlk = Invoke-K $homeP 'KSP-P' @('status', '-Path', $dirP)
    $bBlkOk = ($bBlk.Out -match "WARNING: whether this copy is behind 'origin' was NOT checked \(KEEL_OUTWARD is set to 'block'\)") -and ($bBlk.Out -notmatch 'has not pulled|commit\(s\) behind')
    Add-Case 'ORIENT-behind-not-checked' $bBlkOk "with the outward block on, P says the behind reading was not taken and prints no behind line: $bBlkOk"
    Assert-G $dirP @('fetch', '-q') | Out-Null
    $bF = Get-OrStatus $homeP 'KSP-P' $dirP
    $bFOk = ($bF.Out -match "WARNING: this copy is 2 commit\(s\) behind 'origin'\. Pull before acting on what follows\.") -and ($bF.Out -notmatch 'has not pulled')
    Add-Case 'ORIENT-behind-fetched' $bFOk "fetched and not merged: P is 2 commit(s) behind, the number Q pushed: $bFOk"
    Assert-G $dirP @('pull', '-q', '--no-edit') | Out-Null
    $bP = Get-OrStatus $homeP 'KSP-P' $dirP
    $bPOk = ($bP.Out -notmatch 'has not pulled|commit\(s\) behind|was NOT checked \(')
    Add-Case 'ORIENT-behind-pulled' $bPOk "after a pull P prints neither line: $bPOk"
    # Control: a project kept per machine whose remote is two commits ahead prints neither line.
    $mRemote = Join-Path $scratch 'mremote.git'
    New-Item -ItemType Directory -Path $mRemote -Force | Out-Null
    Assert-G $mRemote @('init', '-q', '--bare', '-b', 'main') | Out-Null
    $homeM2 = New-Home 'M2'
    $dirM1 = Join-Path $scratch "pmA\pmb$runTag"
    New-Repo $dirM1 'Person M'
    Assert-G $dirM1 @('remote', 'add', 'origin', $mRemote) | Out-Null
    Assert-K $homeM2 'KSP-M2' @('init-project', '-Path', $dirM1, '-Title', 'per machine behind') | Out-Null
    Save-Commit $dirM1 'project'
    Assert-G $dirM1 @('push', '-q', '-u', 'origin', 'main') | Out-Null
    $dirM2 = Join-Path $scratch "pmB\pmb$runTag"
    New-Item -ItemType Directory -Path (Join-Path $scratch 'pmB') -Force | Out-Null
    Assert-G (Join-Path $scratch 'pmB') @('clone', '-q', $mRemote, "pmb$runTag") | Out-Null
    foreach ($oc in @(@('user.name', 'Person M2'), @('user.email', 'suite@example.invalid'), @('core.autocrlf', 'false'))) { Assert-G $dirM2 @('config', $oc[0], $oc[1]) | Out-Null }
    foreach ($mi in @(1, 2)) { [System.IO.File]::WriteAllText((Join-Path $dirM2 "f$mi.txt"), "$mi`n"); Save-Commit $dirM2 "m2 $mi" }
    Assert-G $dirM2 @('push', '-q') | Out-Null
    $mU = Get-OrStatus $homeM2 'KSP-M2' $dirM1
    Assert-G $dirM1 @('fetch', '-q') | Out-Null
    $mF = Get-OrStatus $homeM2 'KSP-M2' $dirM1
    $mOk = ($mU.Out -match 'which is not in this clone') -and ($mU.Out -notmatch 'has not pulled|commit\(s\) behind|progress file') -and ($mF.Out -notmatch 'has not pulled|commit\(s\) behind|progress file')
    Add-Case 'ORIENT-behind-per-machine-CONTROL' $mOk "per machine, remote 2 ahead: unfetched it prints the old not-in-this-clone line (so the remote was read) and no behind, not-pulled or uncommitted line, nor fetched: $mOk"

    # ---- UNCOMMITTED
    $uClean = Get-OrStatus $homeP 'KSP-P' $dirP
    Assert-K $homeP 'KSP-P' @('add-phase', '-Path', $dirP, '-Phase', 'W1.3', '-Scope', 'phase W1.3', '-Actor', 'agent', '-RunOrder', '3') | Out-Null
    $uAll = Get-PorcelainCount $dirP -PcAll
    $uPlain = Get-PorcelainCount $dirP
    $uS = Get-OrStatus $homeP 'KSP-P' $dirP
    $uN = if ($uS.Out -match 'WARNING: (\d+) progress file\(s\) written here are not committed, so nobody else can see them\.') { [int]$Matches[1] } else { -1 }
    Add-Case 'ORIENT-uncommitted-count' (($uClean.Out -notmatch 'progress file\(s\)') -and ($uN -eq 2) -and ($uAll -eq 2) -and ($uPlain -eq 1)) "clean: no line; after add-phase the line says $uN, files listed $uAll (a new folder of two files), folders listed plainly $uPlain"
    $uPlant = Join-Path $dirP 'progress\phases\W1.1\artifacts\scratch'
    New-Item -ItemType Directory -Path $uPlant -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $uPlant 'copy.json'), '{}')
    $uS2 = Get-OrStatus $homeP 'KSP-P' $dirP
    $uN2 = if ($uS2.Out -match 'WARNING: (\d+) progress file\(s\) written here') { [int]$Matches[1] } else { -1 }
    Remove-Item -LiteralPath $uPlant -Recurse -Force
    Save-Push $dirP 'W1.3'
    Assert-G $dirQ @('pull', '-q', '--no-edit') | Out-Null
    $uS3 = Get-OrStatus $homeP 'KSP-P' $dirP
    Add-Case 'ORIENT-uncommitted-scratch-and-commit' (($uN2 -eq 2) -and ($uS3.Out -notmatch 'progress file\(s\)')) "a file in an artifacts subfolder leaves the count at $uN2; after the commit the line is gone: $($uS3.Out -notmatch 'progress file\(s\)')"
    New-Item -ItemType Directory -Path (Join-Path $dirN 'progress') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dirN 'progress\x.json'), '{}')
    $uM = Invoke-K $homeN 'KSP-N' @('status', '-Path', $dirN)
    Add-Case 'ORIENT-uncommitted-per-machine-CONTROL' (($uM.Code -eq 0) -and ($uM.Out -notmatch 'progress file\(s\)|has not pulled|commit\(s\) behind')) "a project kept per machine with an untracked progress/ file prints none of the three lines"

    # ---- HANDOFF
    $hoDirP = Join-Path $dirP 'plan\handoffs'
    $hSnap = Get-TreeHash $hoDirP
    $hU = Invoke-K $homeU 'KSP-U' @('handoff', '-Path', $dirP, '-Next', 'same text', '-Detail', 'unregistered')
    Add-Case 'ORIENT-handoff-unregistered-95' (($hU.Code -eq 95) -and ($hU.Err -match "'join'") -and ((Get-TreeHash $hoDirP) -eq $hSnap)) "handoff from an unregistered machine exits $($hU.Code), names join, writes nothing"
    Assert-K $homeP 'KSP-P' @('note-friction', '-Path', $dirP, '-Phase', 'W1.1', '-Kind', 'gap', '-Detail', 'before P hands off') | Out-Null
    Assert-K $homeP 'KSP-P' @('handoff', '-Path', $dirP, '-Next', 'same text', '-Detail', 'from P') | Out-Null
    $hFileP = Join-Path $hoDirP "$pidP-same-text.md"
    $hTextP = if (Test-Path -LiteralPath $hFileP) { [System.IO.File]::ReadAllText($hFileP) } else { '' }
    $hLatestP = Get-LatestAt $dirP
    $hStampP = if ($hTextP -match '(?m)^State revision:[ \t]*(\S+)') { $Matches[1] } else { '' }
    Save-Push $dirP 'P hands off'
    Assert-G $dirQ @('pull', '-q', '--no-edit') | Out-Null
    Assert-K $homeQ 'KSP-Q' @('note-friction', '-Path', $dirQ, '-Phase', 'W2.1', '-Kind', 'gap', '-Detail', 'before Q hands off') | Out-Null
    Assert-K $homeQ 'KSP-Q' @('handoff', '-Path', $dirQ, '-Next', 'same text', '-Detail', 'from Q') | Out-Null
    $hFileQ = Join-Path $dirQ "plan\handoffs\$pidQ-same-text.md"
    $hTextQ = if (Test-Path -LiteralPath $hFileQ) { [System.IO.File]::ReadAllText($hFileQ) } else { '' }
    $hLatestQ = Get-LatestAt $dirQ
    $hStampQ = if ($hTextQ -match '(?m)^State revision:[ \t]*(\S+)') { $Matches[1] } else { '' }
    Save-Push $dirQ 'Q hands off'
    Assert-G $dirP @('pull', '-q', '--no-edit') | Out-Null
    $hFilesOk = (Test-Path -LiteralPath $hFileP) -and (Test-Path -LiteralPath (Join-Path $hoDirP "$pidQ-same-text.md")) -and
        ($hTextP -match "(?m)^Author: Person P \($pidP\)\r?$") -and ($hTextP -match '(?m)^Machine: KSP-P\r?$') -and
        ($hTextQ -match "(?m)^Author: Person Q \($pidQ\)\r?$") -and ($hTextQ -match '(?m)^Machine: KSP-Q\r?$') -and
        ($hStampP -ne '') -and ($hStampP -ceq $hLatestP) -and ($hStampQ -ceq $hLatestQ) -and ($hStampP -cne $hStampQ)
    Add-Case 'ORIENT-handoff-files' $hFilesOk "two people with one -Next wrote two files, each with Author and Machine; stamps $hStampP and $hStampQ, each the latest at under progress/ ($hLatestP, $hLatestQ)"
    # P's own file is made the last written, so the tie rule alone would pick it: only the instant
    # comparison names Q's.
    (Get-Item -LiteralPath $hFileP).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(1)
    $hSP = Invoke-K $homeP 'KSP-P' @('status', '-Path', $dirP)
    $hSQ = Invoke-K $homeQ 'KSP-Q' @('status', '-Path', $dirQ)
    $hLinesP = @($hSP.Lines | Where-Object { $_ -match '^KEEL:\s+(handoff:|your last handoff:|STALE)' })
    $hNamedOk = ($hLinesP.Count -eq 3) -and ($hLinesP[0] -match "handoff: plan\\handoffs\\$pidQ-same-text\.md  \(by Person Q, $pidQ\)$") -and
        ($hLinesP[1] -match "your last handoff: plan\\handoffs\\$pidP-same-text\.md$") -and ($hLinesP[2] -match 'STALE - written at state revision')
    $hQOk = ($hSQ.Out -match "handoff: plan\\handoffs\\$pidQ-same-text\.md  \(by Person Q, $pidQ\)") -and ($hSQ.Out -notmatch 'your last handoff:')
    Add-Case 'ORIENT-handoff-named' ($hNamedOk -and $hQOk) "P is shown Q's (newest by instant, not STALE) with its author and its own as your last handoff (STALE): $hNamedOk; Q is shown its own and no your-last line: $hQOk"
    Assert-K $homeP 'KSP-P' @('note-friction', '-Path', $dirP, '-Phase', 'W1.1', '-Kind', 'gap', '-Detail', 'after both handoffs') | Out-Null
    $hSP2 = Invoke-K $homeP 'KSP-P' @('status', '-Path', $dirP)
    $hStale2 = @($hSP2.Lines | Where-Object { $_ -match '^KEEL:\s+STALE - written at state revision' }).Count
    Add-Case 'ORIENT-handoff-stale' ($hStale2 -eq 2) "after one more write both named handoffs are STALE: $hStale2 STALE line(s)"
    # A stamp three hours behind this machine's offset, an hour later as an instant than Q's: later
    # as an instant, smaller as text. Planted: the fixture cannot set a child's time zone.
    $hQI = [DateTimeOffset]::Parse($hStampQ, [Globalization.CultureInfo]::InvariantCulture)
    $hOff = [TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now).Subtract([TimeSpan]::FromHours(3))
    $hPlantI = $hQI.AddHours(1).ToOffset($hOff)
    $hPlantText = $hPlantI.ToString('yyyy-MM-ddTHH:mm:sszzz', [Globalization.CultureInfo]::InvariantCulture)
    if (-not ([string]::CompareOrdinal($hPlantText, $hStampQ) -lt 0 -and $hPlantI -gt $hQI)) { throw "The planted handoff stamp $hPlantText is not later than $hStampQ as an instant and smaller as text." }
    $hPlant = Join-Path $hoDirP 'p-0abc-planted.md'
    [System.IO.File]::WriteAllText($hPlant, "# Handoff - planted`r`n`r`nState revision: $hPlantText`r`nAuthor: Person Planted (p-0abc)`r`nMachine: KSP-FAR`r`n")
    (Get-Item -LiteralPath $hPlant).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-5)
    $hSP3 = Invoke-K $homeP 'KSP-P' @('status', '-Path', $dirP)
    Remove-Item -LiteralPath $hPlant
    $hSP4 = Invoke-K $homeP 'KSP-P' @('status', '-Path', $dirP)
    Add-Case 'ORIENT-handoff-by-instant' ($hSP3.Out -match 'handoff: plan\\handoffs\\p-0abc-planted\.md  \(by Person Planted, p-0abc\)') "a stamp later as an instant and smaller as text ($hPlantText against $hStampQ) is named"
    Add-Case 'ORIENT-handoff-by-instant-CONTROL' ($hSP4.Out -match "handoff: plan\\handoffs\\$pidQ-same-text\.md") "with the planted handoff removed, Q's is named again"
    Save-Push $dirP 'handoffs'
    Assert-G $dirQ @('pull', '-q', '--no-edit') | Out-Null

    # ---- MERGE: a run-order clash. Control first: the same two writes at different orders.
    Assert-K $homeP 'KSP-P' @('add-phase', '-Path', $dirP, '-Phase', 'W6.1', '-Scope', 'phase W6.1', '-Actor', 'agent', '-RunOrder', '0') | Out-Null
    Assert-K $homeQ 'KSP-Q' @('add-phase', '-Path', $dirQ, '-Phase', 'W6.2', '-Scope', 'phase W6.2', '-Actor', 'agent', '-RunOrder', '7') | Out-Null
    Sync-Pair $dirP $dirQ 'W6'
    $mc = Get-OrBoth $homeP 'KSP-P' $dirP
    Add-Case 'ORIENT-merge-clash-CONTROL' (($mc.S -notmatch 'after a merge') -and ($mc.T -notmatch 'after a merge') -and ($mc.S -match '(?m)^KEEL:\s+next: W6\.1 ')) "W6.1 #0 and W6.2 #7 merged: no after-a-merge line, and P's next is the lower, W6.1"
    Assert-K $homeP 'KSP-P' @('abandon', '-Path', $dirP, '-Phase', 'W6.1', '-Detail', 'control done') | Out-Null
    Assert-K $homeQ 'KSP-Q' @('abandon', '-Path', $dirQ, '-Phase', 'W6.2', '-Detail', 'control done') | Out-Null
    Sync-Pair $dirP $dirQ 'W6 done'
    Assert-K $homeP 'KSP-P' @('add-phase', '-Path', $dirP, '-Phase', 'W5.1', '-Scope', 'phase W5.1', '-Actor', 'agent', '-RunOrder', '0') | Out-Null
    Assert-K $homeQ 'KSP-Q' @('add-phase', '-Path', $dirQ, '-Phase', 'W5.2', '-Scope', 'phase W5.2', '-Actor', 'agent', '-RunOrder', '0') | Out-Null
    Sync-Pair $dirP $dirQ 'W5'
    $mClash = 'WARNING: after a merge, W5\.1 and W5\.2 share run order 0 in W5, so neither is named as next\.'
    $mcP = Get-OrBoth $homeP 'KSP-P' $dirP
    $mcQ = Get-OrBoth $homeQ 'KSP-Q' $dirQ
    $mcWarn = ($mcP.S -match $mClash) -and ($mcP.T -match $mClash) -and ($mcQ.S -match $mClash) -and ($mcQ.T -match $mClash)
    $mcNext = ($mcP.S -match '(?m)^KEEL:\s+next: none named - W5\.1 shares run order 0 in W5 with W5\.2') -and ($mcQ.S -match '(?m)^KEEL:\s+next: none named - W5\.2 shares run order 0 in W5 with W5\.1') -and ($mcP.S -notmatch '(?m)^KEEL:\s+next: W5') -and ($mcQ.S -notmatch '(?m)^KEEL:\s+next: W5')
    Add-Case 'ORIENT-merge-clash' ($mcWarn -and $mcNext) "status and tree in both clones name W5.1, W5.2, order 0 and W5: $mcWarn; neither is named as next in either clone: $mcNext"
    $mc92 = Invoke-K $homeP 'KSP-P' @('add-phase', '-Path', $dirP, '-Phase', 'W5.3', '-Scope', 'phase W5.3', '-Actor', 'agent', '-RunOrder', '0')
    $mcOther = Invoke-K $homeP 'KSP-P' @('note-friction', '-Path', $dirP, '-Phase', 'W1.1', '-Kind', 'gap', '-Detail', 'a write in another workstream')
    Add-Case 'ORIENT-merge-clash-writes' (($mc92.Code -eq 92) -and ($mcOther.Code -eq 0) -and ($mcOther.Out -match $mClash)) "a further add-phase at order 0 in W5 exits $($mc92.Code); a write in W1 exits $($mcOther.Code) and prints the warning first: $($mcOther.Out -match $mClash)"
    Assert-K $homeQ 'KSP-Q' @('revise-phase', '-Path', $dirQ, '-Phase', 'W5.2', '-RunOrder', '9') | Out-Null
    Sync-Pair $dirP $dirQ 'W5 repaired'
    $mcFix = Get-OrBoth $homeP 'KSP-P' $dirP
    Add-Case 'ORIENT-merge-clash-repaired' (($mcFix.S -notmatch 'share run order') -and ($mcFix.S -match '(?m)^KEEL:\s+next: W5\.1 ')) "with W5.2 moved to 9 the line is gone and P's next is W5.1"
    Assert-K $homeP 'KSP-P' @('abandon', '-Path', $dirP, '-Phase', 'W5.1', '-Detail', 'clash case done') | Out-Null
    Assert-K $homeQ 'KSP-Q' @('abandon', '-Path', $dirQ, '-Phase', 'W5.2', '-Detail', 'clash case done') | Out-Null
    Sync-Pair $dirP $dirQ 'W5 done'

    # ---- MERGE: a phase open under a workstream another person closed or abandoned.
    foreach ($ow in @('W7.1', 'W8.1', 'W9.1')) { Assert-K $homeP 'KSP-P' @('add-phase', '-Path', $dirP, '-Phase', $ow, '-Scope', "phase $ow", '-Actor', 'agent', '-RunOrder', '1') | Out-Null }
    Sync-Pair $dirP $dirQ 'W7 to W9'
    foreach ($oa in @(@('abandon', '-Phase', 'W7.1', '-Detail', 'x'), @('abandon', '-Ws', 'W7', '-Detail', 'x'), @('abandon', '-Phase', 'W8.1', '-Detail', 'x'), @('close', '-Ws', 'W8'),
                      @('abandon', '-Phase', 'W9.1', '-Detail', 'x'), @('abandon', '-Ws', 'W9', '-Detail', 'x'))) {
        Assert-K $homeP 'KSP-P' (@($oa[0]) + @('-Path', $dirP) + @($oa | Select-Object -Skip 1)) | Out-Null
    }
    Assert-K $homeQ 'KSP-Q' @('add-phase', '-Path', $dirQ, '-Phase', 'W7.2', '-Scope', 'phase W7.2', '-Actor', 'agent', '-RunOrder', '2') | Out-Null
    Assert-K $homeQ 'KSP-Q' @('add-phase', '-Path', $dirQ, '-Phase', 'W8.2', '-Scope', 'phase W8.2', '-Actor', 'agent', '-RunOrder', '2') | Out-Null
    Assert-K $homeQ 'KSP-Q' @('note-friction', '-Path', $dirQ, '-Phase', 'W2.1', '-Kind', 'gap', '-Detail', 'nothing in W9') | Out-Null
    Sync-Pair $dirP $dirQ 'closed under'
    $mu = Get-OrBoth $homeP 'KSP-P' $dirP
    $muA = 'WARNING: after a merge, phase W7\.2 is planned under W7, which is ABANDONED\.'
    $muD = 'WARNING: after a merge, phase W8\.2 is planned under W8, which is DELIVERED\.'
    Add-Case 'ORIENT-merge-open-under-closed' (($mu.S -match $muA) -and ($mu.T -match $muA) -and ($mu.S -match $muD) -and ($mu.T -match $muD)) "status and tree name W7.2 under ABANDONED W7 and W8.2 under DELIVERED W8"
    Add-Case 'ORIENT-merge-open-under-closed-CONTROL' (($mu.S -notmatch 'under W9') -and ($mu.T -notmatch 'under W9')) "W9 abandoned while the other side wrote elsewhere: no line names W9"

    # ---- MERGE: a reference to an id with no file, each by a partial commit, then completed.
    # Ids of two digits are assembled at run time: the product's history check refuses a
    # workstream id of 10 or more written into any file of the product, this one included.
    $wsTen = 'W' + '10'; $wsEleven = 'W' + '11'; $wsTwelve = 'W' + '12'
    $refCases = @(
        @{ Label = 'ws'; Setup = { Assert-K $homeQ 'KSP-Q' @('add-workstream', '-Path', $dirQ, '-Id', $wsTen, '-Title', 'ws ten', '-Parent', 'root', '-Goals', 'G1') | Out-Null
                                   Assert-K $homeQ 'KSP-Q' @('add-phase', '-Path', $dirQ, '-Phase', "$wsTen.1", '-Scope', 'phase ten one', '-Actor', 'agent', '-RunOrder', '1') | Out-Null }
           Part = @("progress/phases/$wsTen.1"); Line = "WARNING: after a merge, phase $wsTen\.1 names workstream $wsTen, which has no file under progress/nodes/\." }
        @{ Label = 'parent'; Setup = { Assert-K $homeQ 'KSP-Q' @('add-epic', '-Path', $dirQ, '-Id', 'E1', '-Title', 'an epic', '-Parent', 'root', '-Groups', 'the parent case') | Out-Null
                                       Assert-K $homeQ 'KSP-Q' @('add-workstream', '-Path', $dirQ, '-Id', $wsEleven, '-Title', 'ws eleven', '-Parent', 'E1', '-Goals', 'G1') | Out-Null }
           Part = @("progress/nodes/$wsEleven.json"); Line = "WARNING: after a merge, workstream $wsEleven names parent E1, which has no file under progress/nodes/\." }
        @{ Label = 'goal'; Setup = { Assert-K $homeQ 'KSP-Q' @('add-goal', '-Path', $dirQ, '-Id', 'G5', '-Text', 'goal five') | Out-Null
                                     Assert-K $homeQ 'KSP-Q' @('add-workstream', '-Path', $dirQ, '-Id', $wsTwelve, '-Title', 'ws twelve', '-Parent', 'root', '-Goals', 'G5') | Out-Null }
           Part = @("progress/nodes/$wsTwelve.json"); Line = "WARNING: after a merge, workstream $wsTwelve names goal G5, which has no file under progress/goals/\." }
    )
    foreach ($rc in $refCases) {
        & $rc.Setup
        Save-Part $dirQ $rc.Part "partial $($rc.Label)"
        Assert-G $dirP @('pull', '-q', '--no-edit') | Out-Null
        $rcBroken = Get-OrBoth $homeP 'KSP-P' $dirP
        Save-Push $dirQ "rest of $($rc.Label)"
        Assert-G $dirP @('pull', '-q', '--no-edit') | Out-Null
        $rcWhole = Get-OrBoth $homeP 'KSP-P' $dirP
        Add-Case "ORIENT-merge-missing-$($rc.Label)" (($rcBroken.S -match $rc.Line) -and ($rcBroken.T -match $rc.Line)) "pulled without the file it names: status and tree say so"
        Add-Case "ORIENT-merge-missing-$($rc.Label)-CONTROL" (($rcWhole.S -notmatch $rc.Line) -and ($rcWhole.T -notmatch $rc.Line)) "with the rest committed and pulled the line is gone"
    }
    # The owner: a third person joins on Q's clone and plans a phase, committing the phase but not
    # the person file.
    $ojr = Assert-K $homeR3 'KSP-R3' @('join', '-Path', $dirQ)
    $pidR = if ($ojr.Out -match 'as person (p-[0-9a-f]{4}) ') { $Matches[1] } else { throw 'join from R3 printed no person id.' }
    Assert-K $homeR3 'KSP-R3' @('add-phase', '-Path', $dirQ, '-Phase', 'W2.3', '-Scope', 'phase W2.3', '-Actor', 'agent', '-RunOrder', '3') | Out-Null
    Save-Part $dirQ @('progress/phases/W2.3') 'partial owner'
    Assert-G $dirP @('pull', '-q', '--no-edit') | Out-Null
    $roBroken = Get-OrBoth $homeP 'KSP-P' $dirP
    Save-Push $dirQ 'rest of owner'
    Assert-G $dirP @('pull', '-q', '--no-edit') | Out-Null
    $roWhole = Get-OrBoth $homeP 'KSP-P' $dirP
    $roLine = "WARNING: after a merge, phase W2\.3 names owner $pidR, which has no file under progress/people/\."
    Add-Case 'ORIENT-merge-missing-owner' (($roBroken.S -match $roLine) -and ($roBroken.T -match $roLine)) "a phase owned by a person whose file was not committed: status and tree say so"
    Add-Case 'ORIENT-merge-missing-owner-CONTROL' (($roWhole.S -notmatch $roLine) -and ($roWhole.T -notmatch $roLine)) "with the person file committed and pulled the line is gone"
    # continues: no verb writes one yet, so it is planted, as an unknown id and then a known one.
    Assert-K $homeQ 'KSP-Q' @('add-phase', '-Path', $dirQ, '-Phase', 'W2.4', '-Scope', 'phase W2.4', '-Actor', 'agent', '-RunOrder', '4') | Out-Null
    $rcFile = Join-Path $dirQ 'progress\phases\W2.4\phase.json'
    $rcLine = 'WARNING: after a merge, phase W2\.4 continues W2\.9, which has no file under progress/phases/ or progress/closed/\.'
    $rcSeen = @{}
    foreach ($rcTo in @('W2.9', 'W2.1')) {
        $rcObj = Read-JsonFile $rcFile
        $rcObj.continues = $rcTo
        [System.IO.File]::WriteAllText($rcFile, (($rcObj | ConvertTo-Json -Depth 8) -replace "`r`n", "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
        Save-Push $dirQ "continues $rcTo"
        Assert-G $dirP @('pull', '-q', '--no-edit') | Out-Null
        $rcSeen[$rcTo] = Get-OrBoth $homeP 'KSP-P' $dirP
    }
    Add-Case 'ORIENT-merge-missing-continues' (($rcSeen['W2.9'].S -match $rcLine) -and ($rcSeen['W2.9'].T -match $rcLine)) "a phase continuing an id with no file: status and tree say so"
    Add-Case 'ORIENT-merge-missing-continues-CONTROL' (($rcSeen['W2.1'].S -notmatch 'continues W2') -and ($rcSeen['W2.1'].T -notmatch 'continues W2')) "continuing a phase that exists prints no such line"

    # ---- MERGE: one machine in two person files. Control first: a machine joining on one side only.
    Assert-K $homeZ 'KSP-Z' @('join', '-Path', $dirP) | Out-Null
    Assert-K $homeY 'KSP-Y' @('join', '-Path', $dirP) | Out-Null
    Assert-K $homeY 'KSP-Y' @('join', '-Path', $dirQ) | Out-Null
    Sync-Pair $dirP $dirQ 'Y and Z'
    $my = Get-OrBoth $homeP 'KSP-P' $dirP
    $myLine ='WARNING: after a merge, machine KSP-Y is listed by two person files, p-[0-9a-f]{4} \([^)]*\) and p-[0-9a-f]{4} \([^)]*\), so writes from it are refused'
    Add-Case 'ORIENT-merge-machine-twice' (($my.S -match $myLine) -and ($my.T -match $myLine)) "a machine that joined on both clones offline: status and tree name it and both person files"
    Add-Case 'ORIENT-merge-machine-twice-CONTROL' (($my.S -notmatch 'machine KSP-Z') -and ($my.T -notmatch 'machine KSP-Z')) "a machine that joined on one clone only is not named"

    # =============================================================== OWNER ==
    # Ownership and hand-over, on its own bare remote and two clones, people A and B. Uses ORIENT's
    # helpers (Save-Push, Sync-Pair, Get-OrBoth) and its copy of HEAD's wrapper.
    function Get-PhaseHash {
        # The phase's own files - phase.json, run.json and every entry folder - artifacts left out.
        param([string]$PhDir, [string]$PhId)
        $phRoot = Join-Path $PhDir "progress\phases\$PhId"
        if (-not (Test-Path -LiteralPath $phRoot)) { return '(none)' }
        $phLines = @(Get-ChildItem -LiteralPath $phRoot -Recurse -File | Where-Object { $_.FullName.Substring($phRoot.Length) -notmatch '^\\artifacts\\' } | Sort-Object FullName | ForEach-Object {
            $_.FullName.Substring($phRoot.Length) + '|' + (Get-Sha ([System.IO.File]::ReadAllBytes($_.FullName)))
        })
        return (Get-Sha ([System.Text.Encoding]::UTF8.GetBytes(($phLines -join "`n"))))
    }
    function Get-JsonPaths {
        # Every property path of a parsed JSON value, an array's elements as [].
        param($JpVal, [string]$JpAt, $JpOut)
        if ($JpVal -is [System.Management.Automation.PSCustomObject]) {
            foreach ($jpP in @($JpVal.PSObject.Properties)) { $jpPath = "$JpAt.$($jpP.Name)"; [void]$JpOut.Add($jpPath); Get-JsonPaths $jpP.Value $jpPath $JpOut }
        }
        elseif ($JpVal -is [System.Collections.IEnumerable] -and $JpVal -isnot [string]) {
            foreach ($jpE in $JpVal) { Get-JsonPaths $jpE "$JpAt[]" $JpOut }
        }
    }
    function Get-JField {
        # A field of a parsed file, or $null where the file or the field is missing.
        param($JfObj, [string]$JfName)
        if ($null -eq $JfObj) { return $null }
        $jfP = $JfObj.PSObject.Properties[$JfName]
        if ($null -eq $jfP) { return $null }
        return $jfP.Value
    }
    function Get-PhaseFile {
        param([string]$PfDir, [string]$PfId, [string]$PfName)
        $pfFull = Join-Path $PfDir "progress\phases\$PfId\$PfName"
        if (-not (Test-Path -LiteralPath $pfFull)) { return $null }
        return (Read-JsonFile $pfFull)
    }

    $wRemote = Join-Path $scratch 'wremote.git'
    New-Item -ItemType Directory -Path $wRemote -Force | Out-Null
    Assert-G $wRemote @('init', '-q', '--bare', '-b', 'main') | Out-Null
    $wSlug = 'kow' + $runTag
    $homeOA = New-Home 'OA'; $homeOB = New-Home 'OB'
    $dirOA = Join-Path $scratch "cloneOA\$wSlug"
    $dirOB = Join-Path $scratch "cloneOB\$wSlug"
    New-Repo $dirOA 'Owner A'
    Assert-G $dirOA @('remote', 'add', 'origin', $wRemote) | Out-Null
    Assert-K $homeOA 'KSP-OA' @('init-project', '-Path', $dirOA, '-Title', 'ownership') | Out-Null
    Assert-K $homeOA 'KSP-OA' @('add-goal', '-Path', $dirOA, '-Id', 'G1', '-Text', 'goal') | Out-Null
    Assert-K $homeOA 'KSP-OA' @('add-repo', '-Path', $dirOA, '-Name', 'side', '-RepoPath', $side) | Out-Null
    foreach ($ow in @('W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7')) {
        Assert-K $homeOA 'KSP-OA' @('add-workstream', '-Path', $dirOA, '-Id', $ow, '-Title', "workstream $ow", '-Parent', 'root', '-Goals', 'G1') | Out-Null
    }
    Save-Commit $dirOA 'project'
    Assert-K $homeOA 'KSP-OA' @('share-progress', '-Path', $dirOA) | Out-Null
    $wPlan = @(@('W1.1', 1), @('W1.2', 2), @('W1.3', 3), @('W2.2', 2), @('W2.3', 3), @('W2.4', 4), @('W2.5', 5), @('W3.1', 1), @('W3.2', 2), @('W4.1', 1), @('W7.1', 1))
    foreach ($wpl in $wPlan) {
        Assert-K $homeOA 'KSP-OA' @('add-phase', '-Path', $dirOA, '-Phase', $wpl[0], '-Scope', "phase $($wpl[0])", '-Actor', 'agent', '-RunOrder', "$($wpl[1])") | Out-Null
    }
    Assert-K $homeOA 'KSP-OA' @('add-phase', '-Path', $dirOA, '-Phase', 'W2.1', '-Scope', 'phase W2.1 to hand over', '-Actor', 'self', '-RunOrder', '1', '-Repos', 'side', '-Due', '2099-01-02', '-PromptPath', 'plan/prompts/W2.1-prompt.md') | Out-Null
    Save-Commit $dirOA 'shared'
    Assert-G $dirOA @('push', '-q', '-u', 'origin', 'main') | Out-Null
    $wPidA = [string](@(Get-ChildItem -LiteralPath (Join-Path $dirOA 'progress\people') -Filter '*.json' | ForEach-Object { Read-JsonFile $_.FullName } | Where-Object { @($_.machines) -contains 'KSP-OA' })[0].id)
    New-Item -ItemType Directory -Path (Join-Path $scratch 'cloneOB') -Force | Out-Null
    Assert-G (Join-Path $scratch 'cloneOB') @('clone', '-q', $wRemote, $wSlug) | Out-Null
    foreach ($oc in @(@('user.name', 'Owner B'), @('user.email', 'suite@example.invalid'), @('pull.rebase', 'false'), @('core.autocrlf', 'false'))) { Assert-G $dirOB @('config', $oc[0], $oc[1]) | Out-Null }
    $wjb = Assert-K $homeOB 'KSP-OB' @('join', '-Path', $dirOB)
    $wPidB = if ($wjb.Out -match 'as person (p-[0-9a-f]{4}) ') { $Matches[1] } else { throw 'join on OB printed no person id.' }
    Save-Push $dirOB 'B joins'
    Assert-G $dirOA @('pull', '-q', '--no-edit') | Out-Null
    $wWhoA = "Owner A \($wPidA\)"; $wWhoB = "Owner B \($wPidB\)"
    # Two phases owned by B, for the merge case, added by A with -Owner.
    foreach ($wpl in @(@('W5.1', 1), @('W5.2', 2))) {
        Assert-K $homeOA 'KSP-OA' @('add-phase', '-Path', $dirOA, '-Phase', $wpl[0], '-Scope', "phase $($wpl[0])", '-Actor', 'agent', '-RunOrder', "$($wpl[1])", '-Owner', $wPidB) | Out-Null
    }
    $wOwnB = Get-JField (Get-PhaseFile $dirOA 'W5.1' 'phase.json') 'owner'
    $wOwnA = Get-JField (Get-PhaseFile $dirOA 'W1.1' 'phase.json') 'owner'
    Add-Case 'OWNER-add-phase-owner' (($wOwnB -ceq $wPidB) -and ($wOwnA -ceq $wPidA)) "add-phase -Owner B stores B: $($wOwnB -ceq $wPidB); with no -Owner, the writer A: $($wOwnA -ceq $wPidA)"

    # ---- anyone but the owner is refused at 88 on a started phase. A starts W1.1.
    foreach ($wp in @('W1.1', 'W2.1', 'W2.3', 'W2.5', 'W3.1', 'W3.2', 'W4.1')) { Write-Artifacts (Get-ArtDir $dirOA $homeOA $wp -AShared) $wp @() }
    foreach ($wp in @('W1.1', 'W2.1', 'W2.5', 'W3.2', 'W4.1')) { Invoke-Gates $homeOA 'KSP-OA' $dirOA $wp @('ground') | Out-Null }
    Save-Push $dirOA 'A starts phases'
    Assert-G $dirOB @('pull', '-q', '--no-edit') | Out-Null
    # The verbs design section 8 "Ownership" lists: the work verbs always, and the two that change
    # a phase once it has left 'planned' (revise-phase other than -Correction, and abandon -Phase).
    $wCovered = @('set-stage', 'set-waiting', 'clear-waiting', 'record-verdict', 'new-iteration', 'lift-cap', 'revise-phase', 'abandon -Phase')
    $wCalls = @(
        @{ Verb = 'set-stage'; Args = @('set-stage', '-Phase', 'W1.1', '-Stage', 'investigating') }
        @{ Verb = 'set-waiting'; Args = @('set-waiting', '-Phase', 'W1.1', '-WaitingOn', 'a supplier', '-ReviewOn', '2099-01-01') }
        @{ Verb = 'clear-waiting'; Args = @('clear-waiting', '-Phase', 'W1.1') }
        @{ Verb = 'record-verdict'; Args = @('record-verdict', '-Phase', 'W1.1', '-Gate', 'investigate', '-Verdict', 'DONE') }
        @{ Verb = 'new-iteration'; Args = @('new-iteration', '-Phase', 'W1.1', '-Trigger', 'plan', '-Detail', 'a round') }
        @{ Verb = 'lift-cap'; Args = @('lift-cap', '-Phase', 'W1.1', '-Rounds', '1', '-Detail', 'operator words') }
        @{ Verb = 'revise-phase'; Args = @('revise-phase', '-Phase', 'W1.1', '-Scope', 'rescoped') }
        @{ Verb = 'abandon -Phase'; Args = @('abandon', '-Phase', 'W1.1', '-Detail', 'not needed') }
    )
    $wRan = New-Object System.Collections.Generic.List[string]
    foreach ($wc in $wCalls) {
        $wBefore = Get-PhaseHash $dirOB 'W1.1'
        $wr = Invoke-K $homeOB 'KSP-OB' (@($wc.Args[0]) + @('-Path', $dirOB) + @($wc.Args | Select-Object -Skip 1))
        $wSame = (Get-PhaseHash $dirOB 'W1.1') -eq $wBefore
        $wMsg = ($wr.Err -match "owned by $wWhoA") -and ($wr.Err -match "this machine is $wWhoB") -and ($wr.Err -match 'hand-over -Phase W1\.1 -To <person id>')
        $wRan.Add($wc.Verb)
        Add-Case "OWNER-refuse-$($wc.Verb -replace ' ', '')" (($wr.Code -eq 88) -and $wSame -and $wMsg) "B on A's started W1.1: exit $($wr.Code), phase files unchanged: $wSame, names A by name and id, B, and hand-over: $wMsg"
    }
    $wSetA = @($wCovered | Where-Object { @($wRan) -notcontains $_ })
    $wSetB = @(@($wRan) | Where-Object { $wCovered -notcontains $_ })
    Add-Case 'OWNER-refuse-set' (($wSetA.Count -eq 0) -and ($wSetB.Count -eq 0) -and ($wRan.Count -eq $wCovered.Count)) "the verbs the refusal cases ran against design section 8's list: missing '$($wSetA -join ',')', extra '$($wSetB -join ',')', $($wRan.Count) ran"
    $wnf = Invoke-K $homeOB 'KSP-OB' @('note-friction', '-Path', $dirOB, '-Phase', 'W1.1', '-Kind', 'gap', '-Detail', 'from B')
    $woq = Invoke-K $homeOB 'KSP-OB' @('open-question', '-Path', $dirOB, '-Phase', 'W1.1', '-Question', 'from B', '-Answer', 'yes')
    Add-Case 'OWNER-open-to-anyone' (($wnf.Code -eq 0) -and ($woq.Code -eq 0)) "B's note-friction exit $($wnf.Code), open-question exit $($woq.Code) on A's W1.1"
    # Control: each refused call, made by the owner, exits 0, in an order a phase allows.
    $wCtl = @()
    foreach ($wc in $wCalls) {
        $wa = Invoke-K $homeOA 'KSP-OA' (@($wc.Args[0]) + @('-Path', $dirOA) + @($wc.Args | Select-Object -Skip 1))
        $wCtl += "$($wc.Verb)=$($wa.Code)"
    }
    Add-Case 'OWNER-refuse-CONTROL' (@($wCtl | Where-Object { $_ -notmatch '=0$' }).Count -eq 0) "the same eight calls by A: $($wCtl -join ' ')"
    # A planned phase: anyone may revise it, change its owner, or abandon it.
    $wpr = Invoke-K $homeOB 'KSP-OB' @('revise-phase', '-Path', $dirOB, '-Phase', 'W1.2', '-Scope', 'rescoped by B')
    $wpo = Invoke-K $homeOB 'KSP-OB' @('revise-phase', '-Path', $dirOB, '-Phase', 'W1.2', '-Owner', $wPidB)
    $wpa = Invoke-K $homeOB 'KSP-OB' @('abandon', '-Path', $dirOB, '-Phase', 'W1.3', '-Detail', 'by B while planned')
    $wpOwner = Get-JField (Get-PhaseFile $dirOB 'W1.2' 'phase.json') 'owner'
    Add-Case 'OWNER-planned-anyone' (($wpr.Code -eq 0) -and ($wpo.Code -eq 0) -and ($wpa.Code -eq 0) -and ($wpOwner -ceq $wPidB)) "on A's planned phases, B's revise-phase exit $($wpr.Code), revise-phase -Owner exit $($wpo.Code) (owner now B: $($wpOwner -ceq $wPidB)), abandon -Phase exit $($wpa.Code)"
    $wpu = Invoke-K $homeOB 'KSP-OB' @('revise-phase', '-Path', $dirOB, '-Phase', 'W1.2', '-Owner', 'p-0000')
    $wps = Invoke-K $homeOA 'KSP-OA' @('revise-phase', '-Path', $dirOA, '-Phase', 'W2.1', '-Owner', $wPidB)
    Add-Case 'OWNER-revise-owner-refused' (($wpu.Code -eq 90) -and ($wps.Code -eq 90) -and ($wps.Err -match 'hand-over')) "-Owner naming no person file exit $($wpu.Code); -Owner on a started phase, by its owner, exit $($wps.Code), naming hand-over"
    Sync-Pair $dirOA $dirOB 'C1 cases'

    # ---- hand-over, run by someone other than the owner, and its successor.
    $wDup = Invoke-K $homeOA 'KSP-OA' @('add-phase', '-Path', $dirOA, '-Phase', 'W2.9', '-Scope', 'at the same order', '-Actor', 'agent', '-RunOrder', '1')
    Add-Case 'OWNER-handover-92-CONTROL' ($wDup.Code -eq 92) "before the hand-over, add-phase at W2.1's order 1 exits $($wDup.Code)"
    $who = Invoke-K $homeOB 'KSP-OB' @('hand-over', '-Path', $dirOB, '-Phase', 'W2.1', '-To', $wPidB, '-Detail', 'A was moved to other work')
    $wxR = Get-PhaseFile $dirOB 'W2.1' 'run.json'
    $wxD = Get-PhaseFile $dirOB 'W2.1' 'phase.json'
    $wbD = Get-PhaseFile $dirOB 'W2.1b' 'phase.json'
    $wbR = Get-PhaseFile $dirOB 'W2.1b' 'run.json'
    $wxOk = ($who.Code -eq 0) -and ((Get-JField $wxR 'stage') -eq 'handed-over') -and ((Get-JField $wxR 'handedOverTo') -eq 'W2.1b') -and ((Get-JField $wxR 'handOverReason') -eq 'A was moved to other work')
    $wbOk = ($null -ne $wbD) -and ((Get-JField $wbD 'scope') -ceq (Get-JField $wxD 'scope')) -and ((Get-JField $wbD 'actor') -eq 'self') -and ((@(Get-JField $wbD 'repos') -join ',') -eq 'side') -and
            ((Get-JField $wbD 'due') -eq '2099-01-02') -and ((Get-JField $wbD 'promptPath') -eq 'plan/prompts/W2.1-prompt.md') -and
            ((@(Get-JField $wbD 'needs') | ConvertTo-Json -Compress) -eq (@(Get-JField $wxD 'needs') | ConvertTo-Json -Compress)) -and ((Get-JField $wbD 'runOrder') -eq 1) -and
            ((Get-JField $wbD 'owner') -ceq $wPidB) -and ((Get-JField $wbD 'continues') -eq 'W2.1') -and ((Get-JField $wbR 'stage') -eq 'planned')
    Add-Case 'OWNER-handover' ($wxOk -and $wbOk) "B hands over A's W2.1 to B: exit $($who.Code); W2.1 handed-over with handedOverTo W2.1b and the reason: $wxOk; W2.1b carries scope, actor, repos, due, prompt path, needs and order 1, owner B, continues W2.1, planned: $wbOk"
    Assert-K $homeOB 'KSP-OB' @('set-stage', '-Path', $dirOB, '-Phase', 'W2.1b', '-Stage', 'grounding') | Out-Null
    $whc = Invoke-K $homeOB 'KSP-OB' @('hand-over', '-Path', $dirOB, '-Phase', 'W2.1b', '-To', $wPidA, '-Detail', 'back to A')
    $wcD = Get-PhaseFile $dirOB 'W2.1c' 'phase.json'
    Add-Case 'OWNER-handover-again' (($whc.Code -eq 0) -and ((Get-JField $wcD 'continues') -eq 'W2.1b') -and ((Get-JField $wcD 'owner') -ceq $wPidA) -and ((Get-JField (Get-PhaseFile $dirOB 'W2.1b' 'run.json') 'handedOverTo') -eq 'W2.1c')) "handing W2.1b over exits $($whc.Code) and creates W2.1c, continuing W2.1b, owned by A"
    Save-Push $dirOB 'hand-overs'
    Assert-G $dirOA @('pull', '-q', '--no-edit') | Out-Null

    # ---- hand-over's refusals write nothing; a handed-over phase is finished.
    Invoke-Gates $homeOA 'KSP-OA' $dirOA 'W2.3' $AllGates | Out-Null
    Assert-K $homeOA 'KSP-OA' @('abandon', '-Path', $dirOA, '-Phase', 'W2.4', '-Detail', 'not needed') | Out-Null
    $wRef = @(@('planned', 'W2.2', $wPidB), @('delivered', 'W2.3', $wPidB), @('abandoned', 'W2.4', $wPidB), @('handed-over', 'W2.1', $wPidB), @('unknown-to', 'W2.5', 'p-0000'))
    foreach ($wrf in $wRef) {
        $wSnap = Get-WriteSnapshot $dirOA $homeOA
        $wrr = Invoke-K $homeOA 'KSP-OA' @('hand-over', '-Path', $dirOA, '-Phase', $wrf[1], '-To', $wrf[2], '-Detail', 'refused')
        $wNo = (Get-WriteSnapshot $dirOA $homeOA) -eq $wSnap
        Add-Case "OWNER-handover-refused-$($wrf[0])" (($wrr.Code -eq 90) -and $wNo) "hand-over of $($wrf[1]) ($($wrf[0])) exits $($wrr.Code), wrote nothing: $wNo"
    }
    $wok = Invoke-K $homeOA 'KSP-OA' @('hand-over', '-Path', $dirOA, '-Phase', 'W2.5', '-To', $wPidB, '-Detail', 'a started phase')
    Add-Case 'OWNER-handover-refused-CONTROL' ($wok.Code -eq 0) "the hand-over of started W2.5 to a person who exists exits $($wok.Code)"
    $wClosed = @()
    foreach ($wc in $wCalls) {
        $wcArgs = @($wc.Args | ForEach-Object { if ($_ -eq 'W1.1') { 'W2.1' } else { $_ } })
        $wcr = Invoke-K $homeOA 'KSP-OA' (@($wcArgs[0]) + @('-Path', $dirOA) + @($wcArgs | Select-Object -Skip 1))
        $wClosed += "$($wc.Verb)=$($wcr.Code)$(if ($wcr.Err -match 'W2\.1b continues it') { '+names' } else { '-silent' })"
    }
    $wcf = Invoke-K $homeOB 'KSP-OB' @('note-friction', '-Path', $dirOB, '-Phase', 'W2.1', '-Kind', 'gap', '-Detail', 'after the hand-over')
    $wcq = Invoke-K $homeOB 'KSP-OB' @('open-question', '-Path', $dirOB, '-Phase', 'W2.1', '-Question', 'after the hand-over')
    $wcc = Invoke-K $homeOB 'KSP-OB' @('revise-phase', '-Path', $dirOB, '-Phase', 'W2.1', '-Correction', 'a correction by B')
    $wcco = Invoke-K $homeOB 'KSP-OB' @('revise-phase', '-Path', $dirOB, '-Phase', 'W2.1', '-Correction', 'with owner', '-Owner', $wPidA)
    Add-Case 'OWNER-handed-over-finished' (@($wClosed | Where-Object { $_ -notmatch '^[^=]+=90\+names$' }).Count -eq 0) "on handed-over W2.1, by its owner A: $($wClosed -join ' ')"
    Add-Case 'OWNER-handed-over-entries' (($wcf.Code -eq 0) -and ($wcq.Code -eq 0) -and ($wcc.Code -eq 0) -and ($wcco.Code -eq 90)) "on handed-over W2.1, by B: note-friction $($wcf.Code), open-question $($wcq.Code), revise-phase -Correction $($wcc.Code); -Correction with -Owner $($wcco.Code)"
    Sync-Pair $dirOA $dirOB 'C3 cases'

    # ---- status, close, abandon -Ws and the run-order check know a handed-over phase.
    $wst = Invoke-K $homeOA 'KSP-OA' @('status', '-Path', $dirOA)
    $wtr = Invoke-K $homeOA 'KSP-OA' @('tree', '-Path', $dirOA)
    Add-Case 'OWNER-status-handed-over' (($wst.Out -match '(?m)^\s+W2\.1\s+#1\s+self\s+handed-over -> W2\.1b\s+due: 2099-01-02\s*$') -and ($wst.Out -match '(?m)^\s+W2\.1b\s+#1\s+self\s+handed-over -> W2\.1c\s+due: 2099-01-02\s*$')) "status prints W2.1 as handed-over -> W2.1b and W2.1b as handed-over -> W2.1c"
    Add-Case 'OWNER-runorder' (($wst.Out -notmatch 'share run order') -and ($wtr.Out -notmatch 'share run order')) "W2.1, W2.1b and W2.1c at one order: no run-order line in status or tree"
    Assert-K $homeOA 'KSP-OA' @('add-phase', '-Path', $dirOA, '-Phase', 'W6.1', '-Scope', 'phase W6.1', '-Actor', 'agent', '-RunOrder', '5') | Out-Null
    Assert-K $homeOB 'KSP-OB' @('add-phase', '-Path', $dirOB, '-Phase', 'W6.2', '-Scope', 'phase W6.2', '-Actor', 'agent', '-RunOrder', '5') | Out-Null
    Sync-Pair $dirOA $dirOB 'W6 clash'
    $wcl = Get-OrBoth $homeOA 'KSP-OA' $dirOA
    Add-Case 'OWNER-runorder-CONTROL' (($wcl.S -match 'W6\.1 and W6\.2 share run order 5 in W6') -and ($wcl.T -match 'W6\.1 and W6\.2 share run order 5 in W6')) "two phases at one order, neither handed over, merged: status and tree flag them"
    Assert-K $homeOA 'KSP-OA' @('abandon', '-Path', $dirOA, '-Phase', 'W6.1', '-Detail', 'clash done') | Out-Null
    Assert-K $homeOB 'KSP-OB' @('abandon', '-Path', $dirOB, '-Phase', 'W6.2', '-Detail', 'clash done') | Out-Null
    Sync-Pair $dirOA $dirOB 'W6 done'
    # close: W3.1 delivered, W3.2 handed over, its successor W3.2b delivered.
    Invoke-Gates $homeOA 'KSP-OA' $dirOA 'W3.1' $AllGates | Out-Null
    Assert-K $homeOA 'KSP-OA' @('hand-over', '-Path', $dirOA, '-Phase', 'W3.2', '-To', $wPidA, '-Detail', 'a fresh start') | Out-Null
    $wcl0 = Invoke-K $homeOA 'KSP-OA' @('close', '-Path', $dirOA, '-Ws', 'W3')
    Write-Artifacts (Get-ArtDir $dirOA $homeOA 'W3.2b' -AShared) 'W3.2b' @()
    Invoke-Gates $homeOA 'KSP-OA' $dirOA 'W3.2b' $AllGates | Out-Null
    $wcl1 = Invoke-K $homeOA 'KSP-OA' @('close', '-Path', $dirOA, '-Ws', 'W3')
    $wHo = Get-JField (Read-JsonFile (Join-Path $dirOA 'progress\nodes\W3.json')) 'handedOver'
    Add-Case 'OWNER-close' (($wcl1.Code -eq 0) -and ([string](Get-JField $wHo 'W3.2') -eq 'W3.2b') -and (Test-Path -LiteralPath (Join-Path $dirOA 'progress\closed\W3.json'))) "close of W3 (W3.1 delivered, W3.2 handed over, W3.2b delivered) exits $($wcl1.Code); the folded node's handedOver maps W3.2 to W3.2b"
    Add-Case 'OWNER-close-CONTROL' ($wcl0.Code -eq 90) "the same close while W3.2b was still planned exits $($wcl0.Code)"
    # abandon -Ws: W4.1 handed over, its successor abandoned. Control: W7, whose one phase is abandoned.
    Assert-K $homeOA 'KSP-OA' @('hand-over', '-Path', $dirOA, '-Phase', 'W4.1', '-To', $wPidB, '-Detail', 'to B') | Out-Null
    Assert-K $homeOA 'KSP-OA' @('abandon', '-Path', $dirOA, '-Phase', 'W4.1b', '-Detail', 'not needed after all') | Out-Null
    $waw = Invoke-K $homeOA 'KSP-OA' @('abandon', '-Path', $dirOA, '-Ws', 'W4', '-Detail', 'never mind')
    Assert-K $homeOA 'KSP-OA' @('abandon', '-Path', $dirOA, '-Phase', 'W7.1', '-Detail', 'not needed') | Out-Null
    $waw7 = Invoke-K $homeOA 'KSP-OA' @('abandon', '-Path', $dirOA, '-Ws', 'W7', '-Detail', 'never ran')
    Add-Case 'OWNER-abandon-ws' (($waw.Code -eq 90) -and ($waw.Err -match 'W4\.1') -and ($waw.Err -match 'did run')) "abandon -Ws W4 with W4.1 handed over exits $($waw.Code), naming W4.1 as having run"
    Add-Case 'OWNER-abandon-ws-CONTROL' ($waw7.Code -eq 0) "abandon -Ws W7, whose one phase is abandoned, exits $($waw7.Code)"
    Save-Push $dirOA 'close and abandon'
    Assert-G $dirOB @('pull', '-q', '--no-edit') | Out-Null

    # ---- a gate entry by someone other than the owner, after a merge. W5.1 and W5.2 are
    # B's. A takes W5.1 while it is planned; B, offline, starts both.
    Assert-K $homeOA 'KSP-OA' @('revise-phase', '-Path', $dirOA, '-Phase', 'W5.1', '-Owner', $wPidA) | Out-Null
    foreach ($wp in @('W5.1', 'W5.2')) {
        Write-Artifacts (Get-ArtDir $dirOB $homeOB $wp -AShared) $wp @()
        Assert-K $homeOB 'KSP-OB' @('set-stage', '-Path', $dirOB, '-Phase', $wp, '-Stage', 'grounding') | Out-Null
        Invoke-Gates $homeOB 'KSP-OB' $dirOB $wp @('ground') | Out-Null
    }
    Sync-Pair $dirOA $dirOB 'owner changed while started'
    $wm = Get-OrBoth $homeOA 'KSP-OA' $dirOA
    $wmLine = "WARNING: after a merge, phase W5\.1's gate entry ground/\d{8}T\d{6}Z-$wPidB-[0-9a-f]{4}\.json is by $wWhoB, but its owner is $($wWhoA):"
    Add-Case 'OWNER-merge-author' (($wm.S -match $wmLine) -and ($wm.T -match $wmLine)) "status and tree name W5.1's ground entry, B as its author and A as its owner"
    Add-Case 'OWNER-merge-author-CONTROL' (($wm.S -notmatch 'phase W5\.2''s gate') -and ($wm.T -notmatch 'phase W5\.2''s gate')) "W5.2, started by its owner with no owner change, is not named"

    # ---- the owner beside each phase not finished; none on a finished one.
    $wcs = Invoke-K $homeOA 'KSP-OA' @('status', '-Path', $dirOA)
    $wct = Invoke-K $homeOA 'KSP-OA' @('tree', '-Path', $dirOA)
    $wColS = ($wcs.Out -match "(?m)^\s+W2\.2\s+#2\s+agent\s+planned\s+owner: $wWhoA\s*$") -and ($wcs.Out -match "(?m)^\s+W5\.2\s+#2\s+agent\s+investigating\s+owner: $wWhoB\s*$") -and ($wcs.Out -match "(?m)^\s+W2\.1c\s+#1\s+self\s+planned\s+due: 2099-01-02\s+owner: $wWhoA\s*$")
    $wColT = ($wct.Out -match "(?m)W2\.2 \[phase\] phase W2\.2  actor:agent  planned  owner: $wWhoA\s*$") -and ($wct.Out -match "(?m)W5\.2 \[phase\] phase W5\.2  actor:agent  investigating  owner: $wWhoB\s*$")
    $wNone = $true
    $wFinished = 0
    foreach ($wl in @(($wcs.Out + "`n" + $wct.Out) -split "`n")) {
        if ($wl -match '^\s+(W2\.3|W2\.4|W2\.1|W2\.1b)(\s|\s\[phase\])') { $wFinished++; if ($wl -match 'owner:') { $wNone = $false } }
    }
    Add-Case 'OWNER-column' ($wColS -and $wColT -and $wNone -and ($wFinished -eq 8)) "status ends a planned, a started and a due phase's line with its owner: $wColS; tree the same: $wColT; delivered W2.3, abandoned W2.4 and handed-over W2.1 and W2.1b carry none, over $wFinished lines (8 expected): $wNone"

    # ---- a per-machine project: no owners, no hand-over, and its state keeps HEAD's paths.
    $wPmRuns = @{}
    foreach ($wSide in @(@('wt', $wtWrapper), @('head', $headWrapper))) {
        $wpHome = New-Home "PM$($wSide[0])"
        $wpDir = Join-Path $scratch "permachine-own\pm$($wSide[0])$runTag"
        New-Repo $wpDir 'Person M'
        $wpSteps = @(@('init-project', '-Title', 'per machine'), @('add-goal', '-Id', 'G1', '-Text', 'goal'), @('add-workstream', '-Id', 'W1', '-Title', 'ws', '-Parent', 'root', '-Goals', 'G1'),
                     @('add-phase', '-Phase', 'W1.1', '-Scope', 'one', '-Actor', 'agent', '-RunOrder', '1'), @('add-phase', '-Phase', 'W1.2', '-Scope', 'two', '-Actor', 'agent', '-RunOrder', '2'))
        $wpCodes = New-Object System.Collections.Generic.List[string]
        foreach ($ws1 in $wpSteps) { $wpCodes.Add("$($ws1[0])=$((Invoke-K $wpHome 'KSP-PM' (@($ws1[0]) + @('-Path', $wpDir) + @($ws1 | Select-Object -Skip 1)) $wSide[1]).Code)") }
        Write-Artifacts (Get-ArtDir $wpDir $wpHome 'W1.1') 'W1.1' @()
        foreach ($wg in $AllGates) { $wpCodes.Add("$wg=$((Invoke-K $wpHome 'KSP-PM' @('record-verdict', '-Path', $wpDir, '-Phase', 'W1.1', '-Gate', $wg, '-Verdict', $GateVerdict[$wg]) $wSide[1]).Code)") }
        foreach ($ws2 in @(@('set-waiting', '-Phase', 'W1.2', '-WaitingOn', 'a supplier', '-ReviewOn', '2099-01-01'), @('clear-waiting', '-Phase', 'W1.2'), @('new-iteration', '-Phase', 'W1.2', '-Trigger', 'plan', '-Detail', 'round'),
                           @('lift-cap', '-Phase', 'W1.2', '-Rounds', '1', '-Detail', 'words'), @('revise-phase', '-Phase', 'W1.2', '-Scope', 'two again'), @('note-friction', '-Phase', 'W1.2', '-Kind', 'gap', '-Detail', 'x'),
                           @('open-question', '-Phase', 'W1.2', '-Question', 'q'), @('revise-phase', '-Phase', 'W1.1', '-Correction', 'c'))) {
            $wpCodes.Add("$($ws2[0])=$((Invoke-K $wpHome 'KSP-PM' (@($ws2[0]) + @('-Path', $wpDir) + @($ws2 | Select-Object -Skip 1)) $wSide[1]).Code)")
        }
        $wpSet = New-Object 'System.Collections.Generic.HashSet[string]'
        Get-JsonPaths (Read-JsonFile (Join-Path $wpHome ".keel\projects\$(Split-Path -Leaf $wpDir)\state.json")) '$' $wpSet
        $wPmRuns[$wSide[0]] = @{ Codes = $wpCodes.ToArray(); Paths = $wpSet; Home = $wpHome; Dir = $wpDir }
    }
    $wPmBad = @($wPmRuns['wt'].Codes | Where-Object { $_ -notmatch '=0$' })
    $wPmA = @($wPmRuns['wt'].Paths | Where-Object { -not $wPmRuns['head'].Paths.Contains($_) })
    $wPmB = @($wPmRuns['head'].Paths | Where-Object { -not $wPmRuns['wt'].Paths.Contains($_) })
    $wHeadNote = if ($headSame) { ' (HEAD holds this same wrapper, so the comparison is of the wrapper with itself)' } else { '' }
    Add-Case 'OWNER-machine-paths' (($wPmBad.Count -eq 0) -and ($wPmA.Count -eq 0) -and ($wPmB.Count -eq 0) -and ($wPmRuns['wt'].Paths.Count -gt 20)) "per machine, a full gate sequence and eight more verbs: steps not at 0 '$($wPmBad -join ',')'; paths only here '$($wPmA -join ',')'; only at HEAD '$($wPmB -join ',')'; $($wPmRuns['wt'].Paths.Count) paths$wHeadNote"
    $wPmCopy = Read-JsonFile (Join-Path $wPmRuns['wt'].Home ".keel\projects\$(Split-Path -Leaf $wPmRuns['wt'].Dir)\state.json")
    @($wPmCopy.phases)[0] | Add-Member -NotePropertyName 'owner' -NotePropertyValue 'p-0000'
    $wPmSet2 = New-Object 'System.Collections.Generic.HashSet[string]'
    Get-JsonPaths $wPmCopy '$' $wPmSet2
    $wPmC = @($wPmSet2 | Where-Object { -not $wPmRuns['head'].Paths.Contains($_) })
    Add-Case 'OWNER-machine-paths-CONTROL' ((@($wPmC) -join ',') -eq '$.phases[].owner') "one key planted in a copy is named: $($wPmC -join ',')"
    $wpmHome = $wPmRuns['wt'].Home; $wpmDir = $wPmRuns['wt'].Dir
    $wpmSnap = Get-WriteSnapshot $wpmDir $wpmHome
    $wpo1 = Invoke-K $wpmHome 'KSP-PM' @('add-phase', '-Path', $wpmDir, '-Phase', 'W1.3', '-Scope', 'three', '-Actor', 'agent', '-RunOrder', '3', '-Owner', 'p-0000')
    $wpo2 = Invoke-K $wpmHome 'KSP-PM' @('hand-over', '-Path', $wpmDir, '-Phase', 'W1.2', '-To', 'p-0000', '-Detail', 'x')
    $wpo3 = Invoke-K $wpmHome 'KSP-PM' @('revise-phase', '-Path', $wpmDir, '-Phase', 'W1.2', '-Owner', 'p-0000')
    $wpmNo = (Get-WriteSnapshot $wpmDir $wpmHome) -eq $wpmSnap
    Add-Case 'OWNER-per-machine-refuse' (($wpo1.Code -eq 90) -and ($wpo2.Code -eq 90) -and ($wpo3.Code -eq 90) -and $wpmNo) "per machine: add-phase -Owner exit $($wpo1.Code), hand-over exit $($wpo2.Code), revise-phase -Owner exit $($wpo3.Code), wrote nothing: $wpmNo"
    $wpmS = Invoke-K $wpmHome 'KSP-PM' @('status', '-Path', $wpmDir)
    $wpmT = Invoke-K $wpmHome 'KSP-PM' @('tree', '-Path', $wpmDir)
    Add-Case 'OWNER-column-CONTROL' (($wpmS.Out -notmatch 'owner:') -and ($wpmT.Out -notmatch 'owner:') -and ($wpmS.Out -match '(?m)^\s+W1\.2\s+#2\s+agent\s')) "a per-machine project's status and tree print no owner: beside W1.2, which is not finished"

    # ============================================================== modes ==
    if ($OldRef) {
        $orText = (Invoke-G $repoRoot @('show', "${OldRef}:$wrapperRel"))
        $orPlug = (Invoke-G $repoRoot @('show', "${OldRef}:plugins/keel-workflow/.claude-plugin/plugin.json"))
        if ($orText.Code -ne 0 -or $orPlug.Code -ne 0) { Stop-Suite 90 "-OldRef '$OldRef' does not name a revision holding the wrapper." }
        $orNow = ([System.IO.File]::ReadAllText($wtWrapper)) -replace "`r`n", "`n"
        if (($orText.Out -replace "`r`n", "`n").TrimEnd() -eq $orNow.TrimEnd()) { Stop-Suite 90 "-OldRef '$OldRef' holds this same wrapper, so it cannot stand for an older copy." }
        if ($orText.Out -match "'share-progress' \{") { Stop-Suite 90 "-OldRef '$OldRef' already knows share-progress, so it cannot stand for an older copy." }
        $orDir = Join-Path $scratch 'old\plugins\keel-workflow'
        New-Item -ItemType Directory -Path (Join-Path $orDir 'skills\keel-orchestrator\wrappers') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $orDir '.claude-plugin') -Force | Out-Null
        $orWrapper = Join-Path $orDir 'skills\keel-orchestrator\wrappers\keel-state.ps1'
        [System.IO.File]::WriteAllText($orWrapper, (($orText.Out -replace "`r`n", "`n") -replace "`n", "`r`n") + "`r`n")
        [System.IO.File]::WriteAllText((Join-Path $orDir '.claude-plugin\plugin.json'), $orPlug.Out)

        # The older wrapper refuses an exported project, writing nothing.
        $snapO = Get-WriteSnapshot $dirE $homeE
        $orRes = Invoke-K $homeE 'KSP-E' @('status', '-Path', $dirE) $orWrapper
        $orW = Invoke-K $homeE 'KSP-E' @('note-friction', '-Path', $dirE, '-Phase', 'W3.3', '-Kind', 'gap', '-Detail', 'old copy') $orWrapper
        Add-Case 'OLDREF-exported-91' (($orRes.Code -eq 91) -and ($orW.Code -eq 91) -and ((Get-WriteSnapshot $dirE $homeE) -eq $snapO)) "older status exit $($orRes.Code), older write exit $($orW.Code), wrote nothing"

        # A state.json the older wrapper wrote keeps its property paths after one write by this one.
        function Get-PropPaths {
            param($PpVal, [string]$PpAt)
            $ppOut = New-Object System.Collections.Generic.List[string]
            if ($PpVal -is [System.Management.Automation.PSCustomObject]) {
                foreach ($ppP in @($PpVal.PSObject.Properties)) {
                    $ppOut.Add("$PpAt.$($ppP.Name)")
                    foreach ($ppS in @(Get-PropPaths $ppP.Value "$PpAt.$($ppP.Name)")) { $ppOut.Add($ppS) }
                }
            }
            elseif ($PpVal -is [System.Array]) { foreach ($ppE in $PpVal) { foreach ($ppS in @(Get-PropPaths $ppE "$PpAt[]")) { $ppOut.Add($ppS) } } }
            return @($ppOut | Sort-Object -Unique)
        }
        $homeO = New-Home 'O'
        $dirO = Join-Path $scratch "oldref\or$runTag"
        New-Repo $dirO 'Person O'
        Assert-K $homeO 'KSP-O' @('init-project', '-Path', $dirO, '-Title', 'older') $orWrapper | Out-Null
        foreach ($oc in @(@('add-goal', '-Id', 'G1', '-Text', 'goal'), @('add-workstream', '-Id', 'W1', '-Title', 'ws', '-Parent', 'root', '-Goals', 'G1'),
                          @('add-phase', '-Phase', 'W1.1', '-Scope', 'one', '-Actor', 'agent', '-RunOrder', '1'), @('add-phase', '-Phase', 'W1.2', '-Scope', 'two', '-Actor', 'agent', '-RunOrder', '2'))) {
            Assert-K $homeO 'KSP-O' (@($oc[0]) + @('-Path', $dirO) + @($oc | Select-Object -Skip 1)) $orWrapper | Out-Null
        }
        Write-Artifacts (Get-ArtDir $dirO $homeO 'W1.1') 'W1.1'
        Invoke-Gates $homeO 'KSP-O' $dirO 'W1.1' $AllGates $orWrapper | Out-Null
        foreach ($oc in @(@('note-friction', '-Phase', 'W1.1', '-Kind', 'gap', '-Detail', 'old'), @('open-question', '-Phase', 'W1.1', '-Question', 'q', '-Answer', 'a'),
                          @('revise-phase', '-Phase', 'W1.1', '-Correction', 'c'), @('lift-cap', '-Phase', 'W1.2', '-Rounds', '1', '-Detail', 'w'))) {
            Assert-K $homeO 'KSP-O' (@($oc[0]) + @('-Path', $dirO) + @($oc | Select-Object -Skip 1)) $orWrapper | Out-Null
        }
        $oState = Join-Path $homeO ".keel\projects\or$runTag\state.json"
        $oBefore = Read-JsonFile $oState
        Assert-K $homeO 'KSP-O' @('note-friction', '-Path', $dirO, '-Phase', 'W1.1', '-Kind', 'gap', '-Detail', 'new') | Out-Null
        $oAfter = Read-JsonFile $oState
        $pathsA = @(Get-PropPaths $oBefore '')
        $pathsB = @(Get-PropPaths $oAfter '')
        $pathDiff = @(Compare-Object $pathsA $pathsB)
        Add-Case 'OLDREF-property-paths' (($pathsA.Count -gt 20) -and ($pathDiff.Count -eq 0)) "$($pathsA.Count) property paths before, differing after one write by this wrapper: $($pathDiff.Count)"
        $oPlus = Read-JsonFile $oState
        @($oPlus.phases)[0] | Add-Member -NotePropertyName 'suiteExtra' -NotePropertyValue 1
        $pathCtl = @(Compare-Object $pathsB @(Get-PropPaths $oPlus ''))
        Add-Case 'OLDREF-property-paths-CONTROL' (@($pathCtl | Where-Object { $_.InputObject -eq '.phases[].suiteExtra' }).Count -eq 1) "a copy with one key added is named: $(@($pathCtl | ForEach-Object { $_.InputObject }) -join ', ')"
    }
    else { Write-Output 'NOT RUN: OLDREF-exported-91 and OLDREF-property-paths need -OldRef <rev>, an older copy of the wrapper.' }

    if ($RealState) {
        $realStateFile = Join-Path $realEnv['USERPROFILE'] '.keel\projects\keel\state.json'
        if (-not (Test-Path -LiteralPath $realStateFile)) { Stop-Suite 90 '-RealState: this machine has no keel project state to copy.' }
        $homeR = New-Home 'real'
        $dirR = Join-Path $scratch 'real\keel'
        New-Repo $dirR 'Person Real'
        $rReal = Read-JsonFile $realStateFile
        $rCfg = [pscustomobject][ordered]@{ '$schema' = 'keel/project'; name = 'keel'; title = $rReal.title; created = '2026-01-01'; git = $true; tracker = [pscustomobject]@{ kind = 'none'; ref = $null }; quarantine = $false; repos = [pscustomobject]@{}; keelVersion = $rReal.plannedUnder }
        [System.IO.File]::WriteAllText((Join-Path $dirR 'keel.json'), ($rCfg | ConvertTo-Json -Depth 6))
        $rHomeProj = Join-Path $homeR '.keel\projects\keel'
        New-Item -ItemType Directory -Path (Join-Path $rHomeProj 'phases') -Force | Out-Null
        Copy-Item -LiteralPath $realStateFile -Destination (Join-Path $rHomeProj 'state.json')
        $rPhasesReal = Join-Path $realEnv['USERPROFILE'] '.keel\projects\keel\phases'
        foreach ($rPd in @(Get-ChildItem -LiteralPath $rPhasesReal -Directory -ErrorAction SilentlyContinue)) {
            $rDest = Join-Path (Join-Path $rHomeProj 'phases') $rPd.Name
            New-Item -ItemType Directory -Path $rDest -Force | Out-Null
            foreach ($rF in @(Get-ChildItem -LiteralPath $rPd.FullName -File)) { Copy-Item -LiteralPath $rF.FullName -Destination $rDest }
        }
        $rGoal = [string](@($rReal.goals)[0].id)
        foreach ($rc in @(@('add-workstream', '-Id', 'W9', '-Title', 'suite abandoned', '-Parent', 'root', '-Goals', $rGoal), @('add-phase', '-Phase', 'W9.1', '-Scope', 'never ran', '-Actor', 'agent', '-RunOrder', '1'),
                          @('abandon', '-Phase', 'W9.1', '-Detail', 'never ran'), @('abandon', '-Ws', 'W9', '-Detail', 'never ran'))) {
            Assert-K $homeR 'KSP-E' (@($rc[0]) + @('-Path', $dirR) + @($rc | Select-Object -Skip 1)) | Out-Null
        }
        Save-Commit $dirR 'real copy'
        $rOpen = @(@((Read-JsonFile (Join-Path $rHomeProj 'state.json')).phases) | Where-Object { @('delivered', 'abandoned') -notcontains [string]$_.stage } | ForEach-Object { $_.id })
        $rMissing = if ($rOpen.Count -gt 0) { $rOpen[0] } else { 'W9.1' }
        $rSample = @(@((Read-JsonFile (Join-Path $rHomeProj 'state.json')).phases) | Where-Object { @($_.friction).Count -gt 0 } | Select-Object -Last 3 | ForEach-Object { $_.id })
        Invoke-ExportCase 'real' $homeR $dirR $rSample $rMissing
        $LayoutDirs.Add($dirR)
        $rProb = @(Test-ProgressFiles $dirR)
        Add-Case 'EXPORT-real-layout' ($rProb.Count -eq 0) "layout problems in the real export: $($rProb.Count)$(if ($rProb.Count) { ': ' + (@($rProb | Select-Object -First 5) -join ' / ') })"
    }
    else { Write-Output 'NOT RUN: EXPORT-real-* need -RealState, a scratch copy of this machine''s keel project state.' }
}
catch {
    $script:HarnessError = $_.Exception.Message
}
finally {
    foreach ($evName in @($realEnv.Keys)) { [Environment]::SetEnvironmentVariable($evName, $realEnv[$evName], 'Process') }
    if (-not $Keep -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

$realProjectsAfter = @()
if (Test-Path -LiteralPath $realProjects) { $realProjectsAfter = @(Get-ChildItem -LiteralPath $realProjects -Directory | ForEach-Object { $_.Name }) }
$breach = @($realProjectsAfter | Where-Object { $realProjectsBefore -notcontains $_ -and $_ -match $runTag })
if ($breach.Count -gt 0) {
    Write-Output "test-shared-progress: $($script:CaseCount) case(s), $($script:FailCount) failure(s), $($script:InconCount) inconclusive"
    Stop-Suite 5 'BREACH: the real state home holds a project of this run.'
}
if ($script:HarnessError) {
    Write-Output "test-shared-progress: $($script:CaseCount) case(s), $($script:FailCount) failure(s), $($script:InconCount) inconclusive"
    Stop-Suite 6 "The harness failed: $($script:HarnessError)"
}
Write-Output "test-shared-progress: $($script:CaseCount) case(s), $($script:FailCount) failure(s), $($script:InconCount) inconclusive"
if ($script:FailCount -gt 0) { exit 1 }
exit 0
