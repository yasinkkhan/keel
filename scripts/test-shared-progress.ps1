<#
    test-shared-progress.ps1 - the suite for shared progress: a project whose keel.json says
    "progress": "repo" keeps its progress under progress/ in its own repo, one file per item and
    per entry, each naming its author.

    Runs in a scratch home ONLY. USERPROFILE and COMPUTERNAME are set for every wrapper call, so one
    machine stands in for several; HOME and GIT_CONFIG_GLOBAL point at an empty scratch file and
    GIT_CONFIG_NOSYSTEM is set, so no real git identity is read; KEEL_OUTWARD is 'block'. The suite
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
    param([string]$KHome, [string]$KMachine, [string[]]$KArgs, [string]$KWrapper = '')
    if (-not $KWrapper) { $KWrapper = $wtWrapper }
    $env:USERPROFILE = $KHome
    $env:COMPUTERNAME = $KMachine
    $kPrior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = -1
    $kRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $KWrapper @KArgs 2>&1
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
