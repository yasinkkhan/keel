<#
    keel-state.ps1 - the ONLY writer of keel project state.

    Windows PowerShell 5.1 compatible. ASCII only. Runs from git hooks and Claude Code
    hooks via powershell.exe -NoProfile, which is 5.1 and not the 7.x on pwsh.

    Charter contracts this script exists to enforce:
      P3   a gate is three facts: artifact exists, artifact conforms, verdict recorded
      P4   caps and refusals are exit codes, never prose
      P15  state lives under %USERPROFILE%\.keel and is written only here
      P17  depth is free, roles are not - nesting rules are refused, not warned about
      P18  actor selects evidence, never steps
      P19  a wait names who and when it is re-checked
      P20  the active project is derived from the working directory, never stored
      P21  irreversibility is declared before the act
      P22  every goal is claimed or explicitly unaddressed
      P24  each project records the keel version it was planned under
      P25  a project files signals; it does not edit keel

    Exit codes
      0   ok
      2   CAP-REACHED       iteration cap hit; nothing was incremented or created. The cap is
                            $IterationCap below, raised for ONE phase only by 'lift-cap'
      88  not the owner: in a project that shares its progress, someone other than a phase's
          owner tried to work on it, or to change it once it had started. Nothing was written;
          the message names the owner and 'hand-over'
      89  a concurrent write: another keel command held the write lock past the bounded
          wait ($LockWaitSeconds below), or a file changed after this command read it.
          Nothing more was written; re-running the command is the answer
      90  bad argument, invalid id, or an attempt to change something immutable
      91  no project resolved, or no state for it
      92  duplicate run order
      93  role or nesting violation
      94  unknown node or undeclared phase
      95  a mandatory answer was not supplied
      96  artifact missing or non-conforming
      97  signal without a citable moment
      98  goal-linkage violation
      99  an outward act did not complete
#>

param(
    [Parameter(Position = 0)][string]$Command,

    [string]$Path,
    [string]$Project,
    [string]$Title,
    [string]$Id,
    [string]$Text,
    [string]$Parent,
    [string]$Next,
    [string]$Groups,
    [string]$Goals,
    [string]$Ws,
    [string]$Phase,
    [string]$Scope,
    [string]$Actor,
    [int]$RunOrder = -1,
    [string]$Repos,
    [string]$Due,
    [string]$PromptPath,
    [string]$Stage,
    [string]$Gate,
    [string]$Verdict,
    [string]$Artifact,
    [string]$WaitingOn,
    [string]$ReviewOn,
    [string]$Trigger,
    [string]$Detail,
    [string]$Kind,
    [string]$Evidence,
    [string]$As,

    # WHAT A 'PROMOTED' RESOLUTION ACTUALLY FIXED: the defect, or one instance of it.
    # Required on PROMOTED and refused on the other two verdicts, which have no fix whose
    # scope could be named. NOT -Scope, which is a phase's scope text at three add-phase
    # and revise-phase sites, and NOT -Shape, whose variable occurs 16 times in this file;
    # both were counted rather than assumed, because PowerShell variable names are
    # case-insensitive and a collision with an existing name is silent.
    [string]$Addresses,
    # A GitHub issue number, for 'adopt-signal'. NOT -Id: 'resolve-signal' validates -Id as
    # ^S\d{4}$, and one flag meaning a signal id on one verb and an integer on another is the
    # ambiguity that produces a wrong call rather than an error. Optional, defaults to 0, so
    # no existing invocation changes (charter P24).
    [int]$Issue = 0,
    # How many extra rounds 'lift-cap' grants one phase. A STRING, validated in that arm, not
    # [int] like -RunOrder and -Issue: under powershell.exe -File, an [int] parameter given
    # 'abc' exits 1 before this script runs - outside the exit-code contract - and given 2.7
    # silently binds 3, which would authorise a round nobody said.
    [string]$Rounds,
    [string]$Reversible,
    [string]$Observable,
    [string]$Tracker,
    [string]$Question,
    [string]$Answer,
    # An append-only dated note on a DELIVERED phase, for 'revise-phase'.
    # Read through $PSBoundParameters there, because -Correction "" must refuse rather than read
    # as absent, which is how every other revise-phase parameter treats an empty string.
    [string]$Correction,
    [string]$Status,
    # A phase's owner, a person id, for 'add-phase' and 'revise-phase'; and the person 'hand-over'
    # hands a phase to. A project that shares its progress only.
    [string]$Owner,
    [string]$To,
    # The phases (W<n>.<p>) and workstreams (W<n>) a phase needs delivered first, comma-separated,
    # for 'add-phase' and 'revise-phase'; 'none' declares no needs.
    [string]$Needs,
    [string]$Repo,
    [string]$Name,
    [string]$RepoPath,
    [string]$Branch,
    [switch]$NoGit,
    [switch]$Quarantine,
    [switch]$Cluster,
    [switch]$Apply,
    [switch]$CloseIssue,
    [switch]$Clear,
    [switch]$Brief,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ---------------------------------------------------------------- constants --

$KeelHome     = Join-Path $env:USERPROFILE '.keel'
$ProjectsHome = Join-Path $KeelHome 'projects'
$SignalsHome  = Join-Path $KeelHome 'signals'
# Where this machine's signals are sent: one line, owner/name, written only by 'signals-target'.
# Under the state home on purpose: a fixture that overrides USERPROFILE loses it.
$SignalsTargetFile = Join-Path $KeelHome 'signals-target.txt'

$IterationCap = 3

# How long a writing command waits for another one writing the same project, or the signal
# store, before it stops with exit 89. The slowest measured hold of a project, a verify verdict
# taking its binding on a state file of about 2.7 MB, is over a second, so this lets several
# queued writers all land. The
# signal store is held longer by 'signals-push -Apply' and 'resolve-signal -CloseIssue', across
# their GitHub calls, about a second each (a read-only GitHub API call measured 0.7 to 1 s), so a push of more than about ten signals
# can make a judgement or resolution started meanwhile stop with 89 - refused, never lost.
$LockWaitSeconds = 10

$Actors = @('agent', 'self', 'external')

$Stages = @('planned', 'grounding', 'investigating', 'planning', 'implementing',
            'verifying', 'awaiting-human', 'enacting', 'recording',
            'delivered', 'waiting', 'escalated', 'abandoned')

$GateOrder = @('ground', 'investigate', 'plan', 'implement', 'verify', 'human', 'enact', 'record')

# Where a PASSING verdict leaves the phase: the activity the gate hands over to.
# These live next to $GateOrder so a gate cannot be added without a stage either side.
$GatePassStage = @{
    'ground'      = 'investigating'
    'investigate' = 'planning'
    'plan'        = 'implementing'
    'implement'   = 'verifying'
    'verify'      = 'awaiting-human'
    'human'       = 'enacting'
    'enact'       = 'recording'
    'record'      = 'delivered'
}

# Where a NON-passing verdict leaves it: the gate's own activity. The phase is still
# at that gate and must not advance past it.
$GateHoldStage = @{
    'ground'      = 'grounding'
    'investigate' = 'investigating'
    'plan'        = 'planning'
    'implement'   = 'implementing'
    'verify'      = 'verifying'
    'human'       = 'awaiting-human'
    'enact'       = 'enacting'
    'record'      = 'recording'
}

# The verdicts that pass their gate. Every other verdict in $GateVerdicts holds the
# phase where it is: BLOCKED, REJECTED, FAIL, INCONCLUSIVE, DEFERRED. 'N/A' passes
# because it means the phase has no outward act, not that the gate failed.
$PassingVerdicts = @('DONE', 'APPROVED', 'PASS', 'N/A')

# Stages record-verdict must not move a phase out of. 'waiting' owns the
# waitingOn/reviewOn pair and only clear-waiting may release it (charter P19);
# 'abandoned' is a decision, not a position in the pipeline. 'delivered' is refused
# earlier with exit 90, and 'escalated' is deliberately absent - recording a verdict
# is how an escalated phase resumes.
$StickyStages = @('waiting', 'abandoned')

$GateVerdicts = @{
    'ground'      = @('DONE')
    'investigate' = @('DONE', 'BLOCKED')
    'plan'        = @('APPROVED', 'REJECTED')
    'implement'   = @('DONE')
    'verify'      = @('PASS', 'FAIL', 'INCONCLUSIVE')
    'human'       = @('APPROVED', 'REJECTED')
    'enact'       = @('DONE', 'N/A', 'DEFERRED')
    'record'      = @('DONE')
}

# The artifact each gate is judged on. 'implement' is actor-dependent and 'human'
# happens in chat, so both are resolved at check time rather than listed here.
$GateArtifacts = @{
    'ground'      = 'grounding.md'
    'investigate' = 'investigation.md'
    'plan'        = 'plan.md'
    'verify'      = 'verify-report.md'
    'enact'       = 'enact-record.md'
    'record'      = 'delivery-record.md'
}

# The verify binding; the helpers are under 'verify binding'.
# The two phase-folder files the gates after verify are REQUIRED to write: the enact and
# delivery records.
$BindFolderExempt   = @('enact-record.md', 'delivery-record.md')
# A file created in the phase folder after the verdict counts only if it is one of these.
$BindFolderArtifact = '^(changes-.+\.patch|act-log\.md)$'
$BindCap            = 2000
$BindEmptyTree      = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
$BindGates          = @('human', 'enact', 'record')
# The project root's tree name. add-repo refuses any name outside ^[A-Za-z0-9][A-Za-z0-9._-]*$,
# so no declared repo can carry it, and the by-path exemptions key on it.
$BindProjectTree    = '(project)'

$GoalStatuses   = @('OPEN', 'UNADDRESSED')
$SignalKinds    = @('unsafe', 'refusal', 'wrong-doc', 'gap', 'friction')
$FrictionKinds  = @('correction', 'rework', 'assertion', 'gap', 'stale-doc')
$TrackerKinds   = @('none', 'trello', 'jira', 'github')
$AddressesVals  = @('defect', 'instance')
$ReversibleVals = @('none', 'partial', 'full')
$ObservableVals = @('yes', 'no')

# ------------------------------------------------------------------ helpers --

function Fail {
    # Write-Error would throw under $ErrorActionPreference = 'Stop' and never reach
    # the exit, collapsing every refusal to exit 1. The exit CODE is the contract
    # (charter P4), so the message goes straight to stderr instead.
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("KEEL-STATE: $Message")
    exit $Code
}

function Say { param([string]$Message) Write-Output "KEEL: $Message" }

function Now      { (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') }
function Today    { (Get-Date).ToString('yyyy-MM-dd') }

function Ensure-Dir {
    param([string]$DirPath)
    if (-not (Test-Path -LiteralPath $DirPath)) {
        New-Item -ItemType Directory -Path $DirPath -Force | Out-Null
    }
    return $DirPath
}

function Require-Param {
    param([string]$Value, [string]$ParamName)
    if ([string]::IsNullOrWhiteSpace($Value)) { Fail 90 "-$ParamName is required for '$Command'." }
}

function Assert-Enum {
    param([string]$Value, [string[]]$Allowed, [string]$ParamName)
    if ($Allowed -notcontains $Value) {
        Fail 90 "-$ParamName '$Value' is not valid. Expected one of: $($Allowed -join ', ')."
    }
}

function Assert-Date {
    param([string]$Value, [string]$ParamName)
    if ($Value -notmatch '^\d{4}-\d{2}-\d{2}$') {
        Fail 90 "-$ParamName '$Value' is not a date. Expected yyyy-MM-dd."
    }
    try { [void][datetime]::ParseExact($Value, 'yyyy-MM-dd', $null) }
    catch { Fail 90 "-$ParamName '$Value' is not a real date." }
}

# Index the property collection by name rather than reading its .Name list: under
# Set-StrictMode, '.Properties.Name' throws on an object with NO properties, and
# a phase's 'gates' object starts empty. Indexing returns $null instead.
function Get-Prop {
    param($Obj, [string]$Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    $prop = $Obj.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function Set-Prop {
    param($Obj, [string]$Name, $Value)
    if ($null -ne $Obj.PSObject.Properties[$Name]) { $Obj.$Name = $Value }
    else { $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Split-Csv {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Read-Json {
    param([string]$FilePath)
    $raw = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    return ($raw | ConvertFrom-Json)
}

# Write-Json re-serialises the whole object, and a writer that imposes ONE fixed on-disk shape
# on whatever it overwrites makes a small edit look like a rewrite: ConvertTo-Json emits CRLF
# on 5.1, and Set-Content -Encoding UTF8 adds a BOM plus a trailing CRLF, so a one-field update
# to a no-BOM/LF keel.json would come back BOM/CRLF with every line reported changed. A
# reviewer of a preview-gated estate cannot see what a command did if every line moved
# (charter P6). The writer preserves what it finds.
#
# NOT preserved: indentation. ConvertTo-Json re-indents unconditionally, so a file some OTHER
# tool formatted still diffs wholesale. Preserving that would mean not re-serialising at all.
#
# Do not 'simplify' this back to Set-Content. That cmdlet cannot write without a BOM on 5.1
# and cannot be told which terminator to use.

function Get-JsonFileShape {
    param([string]$FilePath)

    # The defaults reproduce the fixed shape a writer with no preservation produced, byte for
    # byte, so a file that does not exist yet is written exactly the way it always was
    # (charter P24: contracts widen, they do not shift under an in-flight project).
    $shape = @{ Bom = $true; Eol = "`r`n"; TrailingNewline = $true }

    if (-not (Test-Path -LiteralPath $FilePath)) { return $shape }
    try { $bytes = [System.IO.File]::ReadAllBytes($FilePath) } catch { return $shape }
    if ($bytes.Length -eq 0) { return $shape }

    $shape.Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

    $crlfCount = 0
    $lfCount   = 0
    $crCount   = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 13) {
            if (($i + 1) -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { $crlfCount++; $i++ }
            else { $crCount++ }
        }
        elseif ($bytes[$i] -eq 10) { $lfCount++ }
    }

    # A re-serialised file cannot keep MIXED terminators line for line - the lines themselves
    # change, and a file can hold CRLF and lone CR together. The dominant terminator wins, ties
    # broken CRLF > LF > CR. Deliberate, not incidental.
    if ($crlfCount -gt 0 -or $lfCount -gt 0 -or $crCount -gt 0) {
        if ($crlfCount -ge $lfCount -and $crlfCount -ge $crCount) { $shape.Eol = "`r`n" }
        elseif ($lfCount -ge $crCount) { $shape.Eol = "`n" }
        else { $shape.Eol = "`r" }
    }

    $lastByte = $bytes[$bytes.Length - 1]
    $shape.TrailingNewline = ($lastByte -eq 10 -or $lastByte -eq 13)
    return $shape
}

# -CheckUnchanged runs the write lock's hash check (Assert-Unchanged, under 'write lock' below)
# AFTER the text is built and immediately before the write. Serialising a large state takes most
# of a second, and a check made before it left that whole second for another writer's change to
# be overwritten unseen.
function Write-Json {
    param([string]$FilePath, $Obj, [switch]$CheckUnchanged)
    Ensure-Dir (Split-Path -Parent $FilePath) | Out-Null

    # [IO.File] is not provider-aware: it resolves a relative path against the .NET current
    # directory, which is NOT PowerShell's location. Set-Content was provider-aware, so this
    # resolution is part of moving off it rather than an extra.
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)

    $shape    = Get-JsonFileShape $fullPath
    $jsonText = $Obj | ConvertTo-Json -Depth 14

    # Normalise to LF first so the result does not depend on what ConvertTo-Json emitted
    # (CRLF on 5.1, measured), then apply the shape found on disk.
    $payloadText = ($jsonText -replace "`r`n", "`n") -replace "`r", "`n"
    if ($shape.Eol -ne "`n") { $payloadText = $payloadText.Replace("`n", $shape.Eol) }
    if ($shape.TrailingNewline) { $payloadText += $shape.Eol }

    $encoder = New-Object System.Text.UTF8Encoding($shape.Bom)
    if ($CheckUnchanged) { Assert-Unchanged $FilePath }
    [System.IO.File]::WriteAllText($fullPath, $payloadText, $encoder)
}

# Write-Json preserves the shape it finds and so cannot be used for a file that must NEVER
# carry a BOM. Set-Content -Encoding UTF8 emits one under Windows PowerShell 5.1 (first
# bytes EF BB BF), and a preserved BOM is just as fatal in a JSON request
# body handed to an HTTP API. Anything that leaves the machine is written here instead.
function Write-TextNoBom {
    # $Payload, not $Text: the script's own param() block has a [string]$Text, and a local
    # of that name IS that parameter, because variable names are case-insensitive. Harmless
    # here - both are [string] - but the rule is zero tolerance because the harmless cases are
    # what teach you to write the harmful one.
    param([string]$FilePath, [string]$Payload)
    Ensure-Dir (Split-Path -Parent $FilePath) | Out-Null
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($FilePath, $Payload, $enc)
}

# -------------------------------------------------------------- write lock --
# Two keel commands writing the same file at overlapping moments used to lose one of the two
# writes while both reported success: each read the whole file, changed its copy and wrote the
# whole file back. Every read-modify-write now runs under a lock taken BEFORE the read and let go
# after the write, so a second writer waits, then reads the first one's result.
#
# THE LOCK IS A NAMED MUTEX, one per guarded target: a project's state path, which also covers
# that project's keel.json, or the signal folder. Chosen by measurement across separate
# powershell.exe processes, beside a lock file opened with FileShare.None: both worked; the
# mutex waits natively, leaves no file behind, and a holder that dies while another process waits
# surfaces as AbandonedMutexException, which hands ownership over, so a killed command never
# blocks the next one. Global\ so that every logon session on the machine shares it; an account
# that is not an administrator can create one. A mutex is owned by a THREAD, which is why the
# dispatch below lets go in a finally: a command run in-process by a caller that keeps running
# would otherwise keep the lock until that caller exits.
#
# scripts/test-concurrent-writes.ps1 computes the same name to hold the lock itself. A DECLARED
# coupling: change the prefix or the hashing here and change it there.
#
# THE HASH CHECK is the second line. A command records the SHA-256 of each file it reads for a
# rewrite and, once its new text is built, checks again immediately before writing, refusing if
# the file has moved. Between two copies of this wrapper that cannot happen under the lock; it is
# what notices a writer that takes no lock, such as an older copy of keel. It cannot notice a
# change landing in the instant between that last check and the write, nor one written AFTER this
# command has written, and nothing on this side can, while an older copy can still write.
$script:WriteLocks  = @{}
$script:ReadShas    = @{}
$script:WrittenList = New-Object System.Collections.Generic.List[string]

function Get-ContentSha {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return '' }
    $csAlg = [System.Security.Cryptography.SHA256]::Create()
    try { return (-join ($csAlg.ComputeHash([System.IO.File]::ReadAllBytes($FilePath)) | ForEach-Object { $_.ToString('x2') })) }
    finally { $csAlg.Dispose() }
}

function Get-FullPathKey {
    param([string]$FilePath)
    return [System.IO.Path]::GetFullPath($FilePath).ToLowerInvariant()
}

function Get-WriteLockName {
    param([string]$Target)
    $wlAlg = [System.Security.Cryptography.SHA256]::Create()
    try { $wlHex = -join ($wlAlg.ComputeHash([System.Text.Encoding]::UTF8.GetBytes((Get-FullPathKey $Target))) | ForEach-Object { $_.ToString('x2') }) }
    finally { $wlAlg.Dispose() }
    return ('Global\keel-write-' + $wlHex)
}

# Every 89 says what this command had already written, so the message stays true whichever write
# it stops at.
function Get-WrittenNote {
    if ($script:WrittenList.Count -eq 0) { return 'Nothing was written.' }
    return "This command had already written $($script:WrittenList -join ', '); nothing more was written."
}

function Enter-WriteLock {
    param([string]$Target, [string]$What)
    $elName = Get-WriteLockName $Target
    if ($script:WriteLocks.ContainsKey($elName)) { return }
    $elMutex = $null
    try { $elMutex = [System.Threading.Mutex]::new($false, $elName) }
    catch [System.UnauthorizedAccessException] {
        Fail 89 "The write lock for $What exists but this process may not open it; most likely another user or an elevated session created it and is still running. $(Get-WrittenNote) Re-run the command when that session has finished."
    }
    $elGot = $false
    try { $elGot = $elMutex.WaitOne([TimeSpan]::FromSeconds($LockWaitSeconds)) }
    catch [System.Threading.AbandonedMutexException] { $elGot = $true }
    if (-not $elGot) {
        $elMutex.Dispose()
        Fail 89 "Another keel command is writing $What and did not finish within $LockWaitSeconds seconds. $(Get-WrittenNote) Re-run the command."
    }
    $script:WriteLocks[$elName] = $elMutex
}

function Exit-WriteLocks {
    foreach ($xlMutex in @($script:WriteLocks.Values)) {
        try { $xlMutex.ReleaseMutex() } catch { }
        $xlMutex.Dispose()
    }
    $script:WriteLocks.Clear()
}

function Save-ReadSha {
    param([string]$FilePath)
    $script:ReadShas[(Get-FullPathKey $FilePath)] = Get-ContentSha $FilePath
}

# A path never recorded is not checked: a file this command creates has no earlier reading.
function Assert-Unchanged {
    param([string]$FilePath)
    $auKey = Get-FullPathKey $FilePath
    if (-not $script:ReadShas.ContainsKey($auKey)) { return }
    if ((Get-ContentSha $FilePath) -ne $script:ReadShas[$auKey]) {
        Fail 89 "'$(Split-Path -Leaf $FilePath)' changed after this command read it, so writing now would erase another command's write. $(Get-WrittenNote) Re-run the command."
    }
}

function Write-GuardedJson {
    param([string]$FilePath, $Obj)
    Write-Json $FilePath $Obj -CheckUnchanged
    Save-ReadSha $FilePath
    $script:WrittenList.Add((Split-Path -Leaf $FilePath))
}

# A signal rewrite made AFTER a GitHub call never refuses: refusing would leave a live outward act
# with no local record of it. Under the store lock it re-reads the file and copies onto it only the
# fields that record the call, so a change another writer made meanwhile survives as well.
function Write-SignalFields {
    param([string]$FilePath, $SigObj, [string[]]$Fields)
    $sfFresh = $null
    try { $sfFresh = Read-Json $FilePath } catch { $sfFresh = $null }
    if ($null -eq $sfFresh) { $sfFresh = $SigObj }
    else {
        foreach ($sfField in $Fields) { Set-Prop $sfFresh $sfField $SigObj.PSObject.Properties[$sfField].Value }
    }
    Write-Json $FilePath $sfFresh
    Save-ReadSha $FilePath
    $script:WrittenList.Add((Split-Path -Leaf $FilePath))
}

# ------------------------------------------------------------ id validation --

function Assert-GoalId {
    param([string]$Value)
    if ($Value -notmatch '^G\d+$') { Fail 90 "-Id '$Value' is not a goal id. Expected G<n>, e.g. G1." }
}

function Assert-EpicId {
    param([string]$Value)
    if ($Value -notmatch '^E\d+$') { Fail 90 "-Id '$Value' is not an epic id. Expected E<n>, e.g. E3." }
}

function Test-WsClaiming {
    # Whether a node counts as claiming its goals. An ABANDONED workstream does not. The
    # one definition for 'status', 'goal-coverage' and 'set-goal-status', which would otherwise
    # state one fact three ways (charter P10).
    param($WsNode)
    return ($WsNode.role -eq 'workstream' -and (Get-Prop $WsNode 'status' '') -ne 'ABANDONED')
}

function Assert-WsNotAbandoned {
    # ABANDONED is terminal. Every verb that could move, revise or rewrite a phase beneath one, or
    # rewrite the workstream itself, stops here, or 'status' names as next a phase beneath a
    # workstream 'tree' calls ABANDONED. note-friction and open-question still write: they add, and
    # move nothing.
    param($WsNode)
    if ($null -ne $WsNode -and (Get-Prop $WsNode 'status' '') -eq 'ABANDONED') {
        Fail 90 "Workstream '$($WsNode.id)' is ABANDONED and cannot be changed: $(Get-Prop $WsNode 'abandonedReason' ''). New work takes a new workstream."
    }
}

function Assert-WsId {
    param([string]$Value, [string]$ParamName = 'Id')
    if ($Value -notmatch '^W\d+$') { Fail 90 "-$ParamName '$Value' is not a workstream id. Expected W<n>, e.g. W4." }
}

function Assert-PhaseId {
    param([string]$Value)
    if ($Value -notmatch '^W\d+\.\d+[a-z]?$') {
        Fail 90 "-Phase '$Value' is not a phase id. Expected W<n>.<p> with an optional single lowercase letter, e.g. W4.2 or W4.5b."
    }
}

function Ws-Of-Phase {
    param([string]$PhaseId)
    return ($PhaseId -split '\.')[0]
}

# ----------------------------------------------------- project resolution ----
# P20: derived from the working directory, never stored.

function Resolve-Project {
    param([string]$StartPath)

    $dir = $StartPath
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $dir)) { Fail 90 "-Path '$dir' does not exist." }
    $dir = (Resolve-Path -LiteralPath $dir).Path

    while ($true) {
        $cfg = Join-Path $dir 'keel.json'
        if (Test-Path -LiteralPath $cfg) {
            # Whether it shares its progress through its repo (see 'shared progress'). An
            # unreadable keel.json reads as not sharing, and every verb that needs it says so.
            $rpCfg = $null
            try { $rpCfg = Read-Json $cfg } catch { $rpCfg = $null }
            if ($null -ne $rpCfg -and [string](Get-Prop $rpCfg 'progress' '') -eq 'repo') { $script:SpRoots[(Split-Path -Leaf $dir)] = $dir }
            return [pscustomobject]@{
                Slug       = (Split-Path -Leaf $dir)
                Root       = $dir
                ConfigPath = $cfg
            }
        }
        $parentDir = Split-Path -Parent $dir
        if ([string]::IsNullOrWhiteSpace($parentDir) -or $parentDir -eq $dir) { return $null }
        $dir = $parentDir
    }
}

function Resolve-ProjectOrFail {
    param([string]$StartPath)
    $p = Resolve-Project -StartPath $StartPath
    if ($null -eq $p) {
        Fail 91 "No keel project here. Walked up from '$(if ($StartPath) { $StartPath } else { (Get-Location).Path })' and found no keel.json. Run 'init-project' in the project folder, or cd into one."
    }
    return $p
}

function Get-StatePath { param([string]$Slug) Join-Path (Join-Path $ProjectsHome $Slug) 'state.json' }
# In a project that shares its progress the artifacts are committed with it, under
# progress/phases/<id>/artifacts/; the per-machine phase folder stays as this machine's scratch.
function Get-PhaseDir  {
    param([string]$Slug, [string]$PhaseId)
    if (Test-SharedProgress $Slug) { return (Join-Path (Join-Path (Join-Path (Get-ProgressDir $Slug) 'phases') $PhaseId) 'artifacts') }
    Join-Path (Join-Path (Join-Path $ProjectsHome $Slug) 'phases') $PhaseId
}

# -ForWrite on every read that a Write-State follows: the lock is taken before the read, so a
# second writer waits and then reads the first one's result. A read that misses it still cannot
# lose a write - Write-State takes the lock and the hash check refuses - it is refused instead.
function Read-State {
    param([string]$Slug, [switch]$ForWrite)
    $sp = Get-StatePath $Slug
    if ($ForWrite) { Enter-WriteLock $sp "project '$Slug'" }
    if (Test-SharedProgress $Slug) {
        $rsShared = Read-SharedState $Slug
        if ($ForWrite) {
            # The read-time check runs before every write too, so a person writing into a broken
            # whole hears about it. Written to the console directly, never through Say: Say is
            # Write-Output, and every writing arm assigns this function's result to $state, which
            # would then hold the warning lines as well as the state.
            foreach ($rsLine in @((Get-SpMergeProblems $Slug $rsShared).Lines)) { [Console]::Out.WriteLine("KEEL:   WARNING: after a merge, $rsLine") }
            [void](Get-SpWriter $Slug)
        }
        return $rsShared
    }
    if (-not (Test-Path -LiteralPath $sp)) {
        Fail 91 "No state for project '$Slug'. Expected '$sp'. Run 'init-project' first."
    }
    Save-ReadSha $sp
    return (Read-Json $sp)
}

function Write-State {
    param([string]$Slug, $State)
    $wsPath = Get-StatePath $Slug
    Enter-WriteLock $wsPath "project '$Slug'"
    if (Test-SharedProgress $Slug) { [void](Write-SharedState $Slug $State); return }
    Set-Prop $State 'updated' (Now)
    Write-GuardedJson $wsPath $State
}
# --------------------------------------------------------- shared progress --
# A project whose keel.json says "progress": "repo" keeps its progress in its own repo, under
# progress/, one small JSON file per item and per entry, each naming its author (charter P15, as
# amended). Read-State and Write-State are the only doors to state, so this layout sits behind
# them: the reader builds the same object state.json holds, and the writer compares that object
# with what was read and writes only what changed. No verb decides anything differently.
#
# THE FILES: project.json; people/<person id>.json; goals/<id>.json; nodes/<id>.json;
# phases/<id>/phase.json (what the phase is) and run.json (where it got to); one file per entry
# under phases/<id>/gates/<gate>/, friction/, questions/, corrections/ and cap-lifts/;
# phases/<id>/artifacts/, the gate artifacts; closed/<workstream id>.json, a closed or abandoned
# workstream's phases folded into one file; acks/, one file per version acknowledgement. Every
# file carries 'by' (a person id), 'machine' and 'at' with a UTC offset; on a file that is
# rewritten they name the LAST writer, and git history names the earlier ones. The fields of each
# kind are in New-SpForm and New-SpGateForm, and nowhere else.
#
# WHAT A VERB CAN DO TO STATE, read in every writing arm, is what makes a comparison enough: an
# item is rewritten in place; an entry list only grows at its end; a gate is replaced wholesale.
# So a changed item is one rewritten file, each new list element one new entry file, and a
# replaced gate one new gate entry. A list that SHRANK is a change this writer cannot store, and
# it refuses rather than guess.
#
# AN ENTRY'S NAME is '<UTC instant>-<person id>-<4 hex>.json', so two people's entries never share
# a name and never conflict at a merge. Where this writer already has an entry in that folder in
# that second, the hex digits go above the highest there, so one writer's entries sort in the
# order written; across people, one second sorts by person id. An ITEM's name is its id, so two
# people taking one id write one name, which git reports as a conflict at the second pull.
#
# STAMPS. Every verb stamps with (Now), which has no offset. A stamp is given this machine's
# offset for that moment when it is written to a file, so what is read back compares equal.
#
# ONE WRITE IS SEVERAL FILES, in a fixed order: every file to be replaced or removed is first
# checked against the text this command read, and any that moved refuses with 89 before anything
# is written; then new entries, then items (run.json after phase.json), then a fold, then the
# files the fold replaces are removed. No transaction spans several files, so a crash part-way can
# leave an entry whose item was not advanced, or a fold beside the files it replaces, which a
# reader shows twice until the command is re-run.
#
# THE LOCK is the mutex named for the per-machine state.json path, as for a per-machine project,
# so one lock per project per machine covers every file here and scripts/test-concurrent-writes.ps1
# computes the same name. Read-only verbs take no lock, as before.
#
# FOLD FILES ARE READ ON EVERY COMMAND: 'status' prints each phase's run order and actor, finished
# phases included, and a node's phaseStages holds only the stage. Measured on a project of 52
# closed workstreams: the fold files read and parse in about the time its one state.json did.

$SpStampPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$'
$SpEntryKinds = [ordered]@{ friction = 'friction'; questions = 'questions'; corrections = 'corrections'; capLifts = 'cap-lifts' }
$SpClosedStatuses = @('DELIVERED', 'ABANDONED')
$SpPhaseKeys = @('id', 'ws', 'scope', 'actor', 'runOrder', 'repos', 'due', 'promptPath', 'stage', 'waitingOn', 'reviewOn', 'iterations')
$script:SpRoots = @{}
$script:SpCtx = @{}

function Test-SharedProgress { param([string]$SpSlug) return $script:SpRoots.ContainsKey($SpSlug) }
function Get-ProgressDir { param([string]$SpSlug) return (Join-Path $script:SpRoots[$SpSlug] 'progress') }

function Add-SpOffset {
    param($SpVal)
    if ($SpVal -is [datetime]) { $SpVal = $SpVal.ToString('yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) }
    if ($SpVal -isnot [string] -or $SpVal -notmatch $SpStampPattern) { return $SpVal }
    $spDt = [datetime]::ParseExact($SpVal, 'yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
    $spOff = [TimeZoneInfo]::Local.GetUtcOffset($spDt)
    return ([DateTimeOffset]::new($spDt, $spOff)).ToString('yyyy-MM-ddTHH:mm:sszzz', [Globalization.CultureInfo]::InvariantCulture)
}

# A stamp as an instant, for comparing - never the text, because text order and time order differ
# across offsets. $null for anything that is not a stamp.
function Get-SpInstant {
    param($SpVal)
    $spS = Add-SpOffset $SpVal
    if ($spS -isnot [string] -or [string]::IsNullOrWhiteSpace($spS)) { return $null }
    $spOut = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($spS, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$spOut)) { return $spOut }
    return $null
}

function Get-SpTicks {
    param($SpVal)
    $spI = Get-SpInstant $SpVal
    if ($null -eq $spI) { return [long]0 }
    return $spI.UtcTicks
}

# A copy of a value with every offset-less stamp given its offset and every dictionary made an
# object, so two copies of one value serialise alike whatever built them.
function ConvertTo-SpValue {
    param($SpVal)
    if ($null -eq $SpVal) { return $null }
    if ($SpVal -is [string] -or $SpVal -is [datetime]) { return (Add-SpOffset $SpVal) }
    if ($SpVal -is [System.Collections.IDictionary]) {
        $spOut = [ordered]@{}
        foreach ($spK in @($SpVal.Keys)) { $spOut[[string]$spK] = ConvertTo-SpValue $SpVal[$spK] }
        return [pscustomobject]$spOut
    }
    if ($SpVal -is [System.Management.Automation.PSCustomObject]) {
        $spOut = [ordered]@{}
        foreach ($spP in @($SpVal.PSObject.Properties)) { $spOut[$spP.Name] = ConvertTo-SpValue $spP.Value }
        return [pscustomobject]$spOut
    }
    if ($SpVal -is [System.Collections.IEnumerable]) {
        $spList = New-Object System.Collections.Generic.List[object]
        foreach ($spE in $SpVal) { $spList.Add((ConvertTo-SpValue $spE)) }
        return ,$spList.ToArray()
    }
    return $SpVal
}

function Get-SpJson { param($SpObj) return ($SpObj | ConvertTo-Json -Depth 14 -Compress) }

# The fields of each kind of file, in order, built from the object a verb holds. A field the kind
# always carries is written as null where unset. 'by', 'machine', 'at' and 'source' are added by
# New-SpFileObj. -SpOwner is the owner a phase with none is given: its writer.
function New-SpForm {
    param([string]$SpKind, $SpObj, [string]$SpOwner)
    $spF = [ordered]@{}
    $spNames = switch ($SpKind) {
        'project'     { @('title', 'created', 'status') }
        'goal'        { @('id', 'text', 'status', 'statusReason', 'statusSetAt', 'created') }
        'node'        { @('id', 'role', 'title', 'parent', 'goals') }
        'decl'        { @('id', 'ws', 'scope', 'actor', 'runOrder', 'repos', 'due', 'promptPath', 'created', 'revisedAt', 'owner', 'needs', 'continues') }
        'run'         { @('stage', 'waitingOn', 'reviewOn', 'iterations', 'abandonedReason') }
        'friction'    { @('kind', 'detail') }
        'questions'   { @('question', 'answer', 'resolvedBy') }
        'corrections' { @('text') }
        'capLifts'    { @('rounds', 'afterIteration', 'words') }
        'ack'         { @('from', 'to', 'detail') }
        default       { throw "There is no progress-file form for '$SpKind'." }
    }
    if ($SpKind -eq 'project') { $spF['schema'] = 2 }
    foreach ($spN in $spNames) {
        $spV = $null
        $spP = $SpObj.PSObject.Properties[$spN]
        if ($null -ne $spP) { $spV = $spP.Value }
        if ($SpKind -eq 'decl' -and $null -eq $spV -and $spN -eq 'owner') { $spV = $SpOwner }
        if (@('goals', 'repos', 'needs') -contains $spN) {
            if ($null -eq $spV) { $spV = @() } else { $spV = @($spV) }
        }
        $spF[$spN] = $spV
    }
    if ($SpKind -eq 'node') {
        if ([string](Get-Prop $SpObj 'role' '') -eq 'epic') { $spF['groups'] = Get-Prop $SpObj 'groups' $null }
        else { $spF['status'] = Get-Prop $SpObj 'status' $null }
        foreach ($spN in @('created', 'revisedAt', 'closedAt', 'abandonedReason', 'abandonedAt')) { $spF[$spN] = Get-Prop $SpObj $spN $null }
    }
    if ($SpKind -eq 'run' -and [string](Get-Prop $SpObj 'stage' '') -eq 'handed-over') {
        $spF['handedOverTo'] = Get-Prop $SpObj 'handedOverTo' $null
        $spF['handOverReason'] = Get-Prop $SpObj 'handOverReason' $null
    }
    return (ConvertTo-SpValue $spF)
}

function New-SpGateForm {
    # A gate entry: a gate's own fields only at that gate, and only where record-verdict wrote them.
    param([string]$SpGate, $SpObj)
    $spF = [ordered]@{ gate = $SpGate; verdict = (Get-Prop $SpObj 'verdict' $null); artifact = (Get-Prop $SpObj 'artifact' $null) }
    $spOwn = @()
    if ($SpGate -eq 'enact') { $spOwn = @('reversible', 'observable', 'bindingCheck') }
    elseif ($SpGate -eq 'verify') { $spOwn = @('binding') }
    elseif (@('human', 'record') -contains $SpGate) { $spOwn = @('bindingCheck') }
    foreach ($spN in $spOwn) {
        if ($null -ne $SpObj.PSObject.Properties[$spN]) { $spF[$spN] = $SpObj.PSObject.Properties[$spN].Value }
    }
    return (ConvertTo-SpValue $spF)
}

function Get-SpGateSig {
    param([string]$SpGate, $SpObj)
    return ((Get-SpJson (New-SpGateForm $SpGate $SpObj)) + '|' + [string](Add-SpOffset (Get-Prop $SpObj 'at' '')))
}

function New-SpFileObj {
    # A file's contents: its fields, then who wrote it, from where and when.
    param($SpForm, [string]$SpBy, [string]$SpMachine, [string]$SpAt, [bool]$SpExported)
    $spO = [ordered]@{}
    foreach ($spP in @($SpForm.PSObject.Properties)) { $spO[$spP.Name] = $spP.Value }
    $spO['by'] = $SpBy
    $spO['machine'] = $SpMachine
    $spO['at'] = $SpAt
    if ($SpExported) { $spO['source'] = 'export' }
    return [pscustomobject]$spO
}

function Write-SpFile {
    # UTF-8 with no byte-order mark, LF, one trailing newline: the same bytes on every machine, so a
    # file nobody changed never shows in a diff.
    param([string]$SpFull, $SpObj)
    Ensure-Dir (Split-Path -Parent $SpFull) | Out-Null
    $spText = (($SpObj | ConvertTo-Json -Depth 14) -replace "`r`n", "`n") -replace "`r", "`n"
    [System.IO.File]::WriteAllText($SpFull, $spText + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

function Read-SpFile {
    param([string]$SpFull, $SpContext)
    $spText = $null
    try { $spText = [System.IO.File]::ReadAllText($SpFull, [System.Text.Encoding]::UTF8) }
    catch { Fail 90 "Could not read the progress file '$SpFull': $($_.Exception.Message)" }
    $spObj = $null
    try { $spObj = $spText | ConvertFrom-Json } catch { $spObj = $null }
    if ($null -eq $spObj) { Fail 90 "The progress file '$SpFull' is not a JSON object. Restore it from the project's git history, then re-run." }
    if ($null -ne $SpContext) { $SpContext.Texts[(Get-FullPathKey $SpFull)] = $spText }
    return $spObj
}

function Split-SpMeta {
    # The object a verb sees, and the writer's fields kept aside. -KeepAt leaves 'at' in the object
    # as well, for an entry, where it is also the entry's own time.
    param($SpObj, [string[]]$SpDrop, [switch]$KeepAt)
    $spMeta = [ordered]@{ by = $null; machine = $null; at = $null; source = $null }
    $spOut = [ordered]@{}
    foreach ($spP in @($SpObj.PSObject.Properties)) {
        if ($spMeta.Contains($spP.Name)) {
            $spMeta[$spP.Name] = $spP.Value
            if ($spP.Name -eq 'at' -and $KeepAt) { $spOut['at'] = $spP.Value }
            continue
        }
        if (@($SpDrop) -contains $spP.Name) { continue }
        $spOut[$spP.Name] = $spP.Value
    }
    return @{ Obj = [pscustomobject]$spOut; Meta = [pscustomobject]$spMeta }
}

function New-SpEntryName {
    param([string]$SpAt, [string]$SpBy, [string]$SpFolder, [hashtable]$SpTaken)
    $spI = Get-SpInstant $SpAt
    if ($null -eq $spI) { $spI = [DateTimeOffset]::Now }
    $spStem = $spI.UtcDateTime.ToString('yyyyMMddTHHmmss', [Globalization.CultureInfo]::InvariantCulture) + 'Z-' + $SpBy + '-'
    $spMax = -1
    $spStemKey = 'stem|' + (Get-FullPathKey (Join-Path $SpFolder $spStem))
    if ($SpTaken.ContainsKey($spStemKey)) { $spMax = [int]$SpTaken[$spStemKey] }
    if (Test-Path -LiteralPath $SpFolder -PathType Container) {
        foreach ($spEx in @(Get-ChildItem -LiteralPath $SpFolder -Filter "$spStem*.json" -File)) {
            if ($spEx.Name -match '-([0-9a-f]{4})\.json$') { $spMax = [Math]::Max($spMax, [Convert]::ToInt32($Matches[1], 16)) }
        }
    }
    for ($spTry = 0; $spTry -lt 300; $spTry++) {
        $spHex = if ($spMax -ge 0 -and $spMax -lt 65535) { $spMax + 1 + $spTry } else { Get-Random -Minimum 0 -Maximum 32768 }
        if ($spHex -gt 65535) { $spHex = Get-Random -Minimum 0 -Maximum 65536 }
        $spFull = Join-Path $SpFolder ($spStem + ('{0:x4}' -f $spHex) + '.json')
        $spKey = Get-FullPathKey $spFull
        if (-not $SpTaken.ContainsKey($spKey) -and -not (Test-Path -LiteralPath $spFull)) {
            $SpTaken[$spKey] = $true
            $SpTaken[$spStemKey] = $spHex
            return $spFull
        }
    }
    Fail 90 "Could not choose a free entry name under '$SpFolder'."
}

function New-SpContext {
    param([string]$SpDir)
    return @{
        Dir = $SpDir; Texts = @{}; Snap = @{}; Meta = @{}; Paths = @{}; People = @()
        GateSnap = @{}; Counts = @{}; Raw = @{}; Folded = @{}; NodeStatus = @{}; NodeExtras = @{}; GateBy = @{}
        MaxAt = $null; MaxAtText = $null
    }
}

function Add-SpSeen {
    # The newest stamp under progress/ is the project's revision: what a handoff is stamped with,
    # and what 'status' compares a handoff against.
    param($SpContext, $SpAt)
    $spI = Get-SpInstant $SpAt
    if ($null -eq $spI) { return }
    if ($null -eq $SpContext.MaxAt -or $spI -gt $SpContext.MaxAt) { $SpContext.MaxAt = $spI; $SpContext.MaxAtText = [string](Add-SpOffset $SpAt) }
}

function Add-SpGateBy {
    # Who wrote each gate entry, kept for the read-time check of gate authors: the in-memory gate
    # keeps only its newest entry and drops 'by'.
    param($SpContext, [string]$GbPhase, [string]$GbBy, [string]$GbName)
    if (-not $SpContext.GateBy.ContainsKey($GbPhase)) { $SpContext.GateBy[$GbPhase] = New-Object System.Collections.Generic.List[object] }
    $SpContext.GateBy[$GbPhase].Add([pscustomobject]@{ By = $GbBy; Name = $GbName })
}

function Get-SpJsonFiles {
    param([string]$SpFolder)
    if (-not (Test-Path -LiteralPath $SpFolder -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $SpFolder -Filter '*.json' -File | Sort-Object Name)
}

function Get-SpOrderKey {
    # Goals, nodes and phases in the order they were made, as state.json keeps them.
    param($SpObj)
    return ('{0:D20}|{1}' -f (Get-SpTicks (Get-Prop $SpObj 'created' $null)), [string](Get-Prop $SpObj 'id' ''))
}

function New-SpMemPhase {
    # The phase object a verb sees, from a declaration and a run record (or one fold object, twice).
    param($SpDecl, $SpRun)
    $spP = [ordered]@{}
    foreach ($spN in $SpPhaseKeys) {
        $spSrc = if ($null -ne $SpDecl.PSObject.Properties[$spN]) { $SpDecl } else { $SpRun }
        $spV = Get-Prop $spSrc $spN $null
        if ($spN -eq 'repos') { if ($null -eq $spV) { $spV = @() } else { $spV = @($spV) } }
        $spP[$spN] = $spV
    }
    if ($null -eq $spP['iterations']) { $spP['iterations'] = 0 }
    $spP['gates'] = [pscustomobject]@{}
    $spP['friction'] = @()
    $spP['questions'] = @()
    $spP['created'] = Get-Prop $SpDecl 'created' $null
    $spP['corrections'] = @()
    $spP['capLifts'] = @()
    $spP['abandonedReason'] = Get-Prop $SpRun 'abandonedReason' $null
    foreach ($spN in @('revisedAt', 'owner', 'needs', 'continues')) { $spP[$spN] = Get-Prop $SpDecl $spN $null }
    if ($null -eq $spP['needs']) { $spP['needs'] = @() } else { $spP['needs'] = @($spP['needs']) }
    foreach ($spN in @('handedOverTo', 'handOverReason')) {
        if ($null -ne $SpRun.PSObject.Properties[$spN]) { $spP[$spN] = $SpRun.PSObject.Properties[$spN].Value }
    }
    return [pscustomobject]$spP
}

function Set-SpLatestGate {
    # The gate's verdict is its newest entry by instant; an equal instant goes to the later name.
    param($SpMem, [string]$SpGate, $SpEntryObj)
    $spCur = Get-Prop $SpMem.gates $SpGate $null
    if ($null -eq $spCur -or (Get-SpTicks (Get-Prop $SpEntryObj 'at' $null)) -ge (Get-SpTicks (Get-Prop $spCur 'at' $null))) {
        Set-Prop $SpMem.gates $SpGate (Split-SpMeta $SpEntryObj @('gate') -KeepAt).Obj
    }
}

function Add-SpEntries {
    # The entry files under one phase folder, appended to the phase's lists (after any the fold
    # already gave it) and kept raw, so a fold can carry them whole.
    param($SpContext, $SpMem, [string]$SpPhaseDir)
    $spId = $SpMem.id
    if (-not $SpContext.Raw.ContainsKey($spId)) { $SpContext.Raw[$spId] = New-Object System.Collections.Generic.List[object] }
    $spGatesDir = Join-Path $SpPhaseDir 'gates'
    if (Test-Path -LiteralPath $spGatesDir -PathType Container) {
        foreach ($spGd in @(Get-ChildItem -LiteralPath $spGatesDir -Directory | Sort-Object Name)) {
            foreach ($spF in @(Get-SpJsonFiles $spGd.FullName)) {
                $spRawObj = Read-SpFile $spF.FullName $SpContext
                $SpContext.Raw[$spId].Add(@{ Kind = 'gate'; Path = $spF.FullName; Obj = $spRawObj; Name = $spF.Name })
                Add-SpGateBy $SpContext $spId ([string](Get-Prop $spRawObj 'by' '')) "$($spGd.Name)/$($spF.Name)"
                Add-SpSeen $SpContext (Get-Prop $spRawObj 'at' $null)
                Set-SpLatestGate $SpMem $spGd.Name $spRawObj
            }
        }
    }
    foreach ($spKind in @($SpEntryKinds.Keys)) {
        $spSeq = New-Object System.Collections.Generic.List[object]
        foreach ($spE in @(Get-Prop $SpMem $spKind @())) { $spSeq.Add([pscustomobject]@{ T = (Get-SpTicks (Get-Prop $spE 'at' $null)); I = $spSeq.Count; O = $spE }) }
        foreach ($spF in @(Get-SpJsonFiles (Join-Path $SpPhaseDir $SpEntryKinds[$spKind]))) {
            $spRawObj = Read-SpFile $spF.FullName $SpContext
            $SpContext.Raw[$spId].Add(@{ Kind = $spKind; Path = $spF.FullName; Obj = $spRawObj; Name = $spF.Name })
            Add-SpSeen $SpContext (Get-Prop $spRawObj 'at' $null)
            $spSeq.Add([pscustomobject]@{ T = (Get-SpTicks (Get-Prop $spRawObj 'at' $null)); I = $spSeq.Count; O = (Split-SpMeta $spRawObj @() -KeepAt).Obj })
        }
        # Sort-Object is not stable on Windows PowerShell 5.1, so the position is part of the key.
        Set-Prop $SpMem $spKind @($spSeq | Sort-Object -Property T, I | ForEach-Object { $_.O })
    }
}

function Read-SharedState {
    param([string]$SpSlug)
    $spDir = Get-ProgressDir $SpSlug
    $spProjFile = Join-Path $spDir 'project.json'
    if (-not (Test-Path -LiteralPath $spProjFile)) {
        Fail 91 "Project '$SpSlug' says in keel.json that it shares its progress, but '$spProjFile' does not exist. Pull the project repo, or check out the commit that added progress/."
    }
    $spCtx = New-SpContext $spDir
    $script:SpCtx[$SpSlug] = $spCtx

    $spPs = Split-SpMeta (Read-SpFile $spProjFile $spCtx) @('schema')
    $spCtx.Snap['project'] = Get-SpJson (New-SpForm 'project' $spPs.Obj)
    Add-SpSeen $spCtx $spPs.Meta.at

    $spPeople = New-Object System.Collections.Generic.List[object]
    foreach ($spF in @(Get-SpJsonFiles (Join-Path $spDir 'people'))) {
        $spO = Read-SpFile $spF.FullName $spCtx
        $spPeople.Add($spO)
        Add-SpSeen $spCtx (Get-Prop $spO 'at' $null)
    }
    $spCtx.People = $spPeople.ToArray()

    $spGoals = New-Object System.Collections.Generic.List[object]
    foreach ($spF in @(Get-SpJsonFiles (Join-Path $spDir 'goals'))) {
        $spS = Split-SpMeta (Read-SpFile $spF.FullName $spCtx) @()
        $spCtx.Snap["goal|$($spS.Obj.id)"] = Get-SpJson (New-SpForm 'goal' $spS.Obj)
        Add-SpSeen $spCtx $spS.Meta.at
        $spGoals.Add($spS.Obj)
    }

    $spNodes = New-Object System.Collections.Generic.List[object]
    foreach ($spF in @(Get-SpJsonFiles (Join-Path $spDir 'nodes'))) {
        $spRawNode = Read-SpFile $spF.FullName $spCtx
        $spS = Split-SpMeta $spRawNode @('phaseStages', 'handedOver')
        if ($null -ne $spRawNode.PSObject.Properties['phaseStages']) {
            $spCtx.NodeExtras[$spS.Obj.id] = @{ phaseStages = $spRawNode.phaseStages; handedOver = (Get-Prop $spRawNode 'handedOver' ([pscustomobject]@{})) }
        }
        $spCtx.Snap["node|$($spS.Obj.id)"] = Get-SpJson (New-SpForm 'node' $spS.Obj)
        $spCtx.NodeStatus[$spS.Obj.id] = [string](Get-Prop $spS.Obj 'status' '')
        Add-SpSeen $spCtx $spS.Meta.at
        $spNodes.Add($spS.Obj)
    }

    # Closed workstreams first: each phase folded into one, then any file written for it since.
    $spPhases = @{}
    foreach ($spF in @(Get-SpJsonFiles (Join-Path $spDir 'closed'))) {
        $spFold = Read-SpFile $spF.FullName $spCtx
        Add-SpSeen $spCtx (Get-Prop $spFold 'at' $null)
        foreach ($spFp in @(Get-Prop $spFold 'phases' @())) {
            $spMem = New-SpMemPhase $spFp $spFp
            $spCtx.Folded[$spMem.id] = [string](Get-Prop $spFold 'ws' '')
            $spCtx.Meta["decl|$($spMem.id)"] = [pscustomobject]@{ by = (Get-Prop $spFp 'declaredBy' $null); machine = (Get-Prop $spFp 'declaredMachine' $null); at = (Get-Prop $spFp 'declaredAt' $null) }
            $spCtx.Meta["run|$($spMem.id)"] = [pscustomobject]@{ by = (Get-Prop $spFp 'by' $null); machine = (Get-Prop $spFp 'machine' $null); at = (Get-Prop $spFp 'at' $null) }
            foreach ($spGe in @(Get-Prop $spFp 'gates' @())) {
                Add-SpGateBy $spCtx $spMem.id ([string](Get-Prop $spGe 'by' '')) "$(Get-Prop $spGe 'gate' '?') at $(Get-Prop $spGe 'at' '?')"
                Add-SpSeen $spCtx (Get-Prop $spGe 'at' $null)
                Set-SpLatestGate $spMem ([string](Get-Prop $spGe 'gate' '')) $spGe
            }
            foreach ($spKind in @($SpEntryKinds.Keys)) {
                $spL = @(foreach ($spE in @(Get-Prop $spFp $spKind @())) { Add-SpSeen $spCtx (Get-Prop $spE 'at' $null); (Split-SpMeta $spE @() -KeepAt).Obj })
                Set-Prop $spMem $spKind $spL
            }
            $spPhases[$spMem.id] = $spMem
        }
    }

    $spPhRoot = Join-Path $spDir 'phases'
    if (Test-Path -LiteralPath $spPhRoot -PathType Container) {
        foreach ($spPd in @(Get-ChildItem -LiteralPath $spPhRoot -Directory | Sort-Object Name)) {
            $spDeclFile = Join-Path $spPd.FullName 'phase.json'
            $spRunFile = Join-Path $spPd.FullName 'run.json'
            $spMem = $null
            if (Test-Path -LiteralPath $spDeclFile) {
                $spD = Split-SpMeta (Read-SpFile $spDeclFile $spCtx) @()
                $spR = $null
                if (Test-Path -LiteralPath $spRunFile) { $spR = Split-SpMeta (Read-SpFile $spRunFile $spCtx) @() }
                $spBase = $null
                if ($spPhases.ContainsKey($spPd.Name)) { $spBase = $spPhases[$spPd.Name] }
                $spRunObj = if ($null -ne $spR) { $spR.Obj } elseif ($null -ne $spBase) { $spBase } else { [pscustomobject]@{ stage = 'planned'; iterations = 0 } }
                $spMem = New-SpMemPhase $spD.Obj $spRunObj
                if ($null -ne $spBase) {
                    # A file written for a folded phase overrides the fold; the fold's entries stay.
                    $spMem.gates = $spBase.gates
                    foreach ($spKind in @($SpEntryKinds.Keys)) { Set-Prop $spMem $spKind @(Get-Prop $spBase $spKind @()) }
                }
                $spCtx.Meta["decl|$($spMem.id)"] = $spD.Meta
                $spCtx.Paths["decl|$($spMem.id)"] = $spDeclFile
                Add-SpSeen $spCtx $spD.Meta.at
                if ($null -ne $spR) {
                    $spCtx.Meta["run|$($spMem.id)"] = $spR.Meta
                    $spCtx.Paths["run|$($spMem.id)"] = $spRunFile
                    Add-SpSeen $spCtx $spR.Meta.at
                }
            }
            elseif ($spPhases.ContainsKey($spPd.Name)) { $spMem = $spPhases[$spPd.Name] }
            if ($null -eq $spMem) { continue }
            Add-SpEntries $spCtx $spMem $spPd.FullName
            $spPhases[$spMem.id] = $spMem
        }
    }

    foreach ($spMem in @($spPhases.Values)) {
        $spCtx.Snap["decl|$($spMem.id)"] = Get-SpJson (New-SpForm 'decl' $spMem)
        $spCtx.Snap["run|$($spMem.id)"] = Get-SpJson (New-SpForm 'run' $spMem)
        foreach ($spGp in @($spMem.gates.PSObject.Properties)) {
            $spCtx.GateSnap["$($spMem.id)|$($spGp.Name)"] = Get-SpGateSig $spGp.Name $spGp.Value
        }
        foreach ($spKind in @($SpEntryKinds.Keys)) { $spCtx.Counts["$($spMem.id)|$spKind"] = @(Get-Prop $spMem $spKind @()).Count }
    }

    $spAcks = New-Object System.Collections.Generic.List[object]
    foreach ($spF in @(Get-SpJsonFiles (Join-Path $spDir 'acks'))) {
        $spO = Read-SpFile $spF.FullName $spCtx
        Add-SpSeen $spCtx (Get-Prop $spO 'at' $null)
        $spAcks.Add((Split-SpMeta $spO @() -KeepAt).Obj)
    }
    $spCtx.Counts['acks'] = $spAcks.Count

    # plannedUnder has no file of its own: the newest acknowledgement's 'to', or, with none, the
    # keelVersion keel.json carries, which init-project and ack-keel-version write equal to it.
    $spPlanned = 'unknown'
    if ($spAcks.Count -gt 0) { $spPlanned = [string](Get-Prop $spAcks[$spAcks.Count - 1] 'to' 'unknown') }
    else {
        $spCfgObj = Read-ProjectConfig (Join-Path $script:SpRoots[$SpSlug] 'keel.json')
        if ($null -ne $spCfgObj) { $spPlanned = [string](Get-Prop $spCfgObj 'keelVersion' 'unknown') }
    }
    $spRevision = $spCtx.MaxAtText
    if ([string]::IsNullOrWhiteSpace($spRevision)) { $spRevision = [string](Get-Prop $spPs.Obj 'created' '') }

    return [pscustomobject]@{
        schema       = 2
        project      = $SpSlug
        root         = $script:SpRoots[$SpSlug]
        title        = Get-Prop $spPs.Obj 'title' ''
        created      = Get-Prop $spPs.Obj 'created' $null
        updated      = $spRevision
        plannedUnder = $spPlanned
        status       = Get-Prop $spPs.Obj 'status' 'active'
        goals        = @($spGoals | Sort-Object -Property @{ Expression = { Get-SpOrderKey $_ } })
        nodes        = @($spNodes | Sort-Object -Property @{ Expression = { Get-SpOrderKey $_ } })
        phases       = @($spPhases.Values | Sort-Object -Property @{ Expression = { Get-SpOrderKey $_ } })
        versionAcks  = $spAcks.ToArray()
    }
}

function Get-SpLatest {
    # The latest of several stamps, as stamp text; $null when none is one.
    param([object[]]$SpVals)
    $spBest = $null
    $spBestText = $null
    foreach ($spV in @($SpVals)) {
        $spI = Get-SpInstant $spV
        if ($null -ne $spI -and ($null -eq $spBest -or $spI -gt $spBest)) { $spBest = $spI; $spBestText = [string](Add-SpOffset $spV) }
    }
    return $spBestText
}

function Get-SpWriter {
    # Which person this machine is: the one person file whose machines list names it. Decided at
    # Read-State -ForWrite, before a writing verb changes anything, so a refusal writes nothing.
    param([string]$SpSlug)
    $spM = $env:COMPUTERNAME
    $spMine = @($script:SpCtx[$SpSlug].People | Where-Object { @(Get-Prop $_ 'machines' @()) -contains $spM })
    if ($spMine.Count -eq 0) {
        Fail 95 "This machine ('$spM') is not registered in '$SpSlug', which shares its progress, so a write here would name nobody as its author. Register it first: 'join' as a new person, or 'join -As <person id>' for a person already under progress/people/. Nothing was written."
    }
    if ($spMine.Count -gt 1) {
        $spWho = ($spMine | ForEach-Object { "$($_.id) ($(Get-Prop $_ 'name' '?'))" }) -join ' and '
        Fail 90 "This machine ('$spM') is listed by two person files, $spWho, most likely after a merge, so whose entry a write would be cannot be told. Take it off the one it is not: 'join -As <person id> -Clear'. Nothing was written."
    }
    return [string]$spMine[0].id
}

function Get-SpMe {
    # Which person this machine is, for READING: the one person file whose machines list names it,
    # or $null when none does or two do. It never refuses; Get-SpWriter is the version that does.
    param([string]$SmSlug)
    $smM = $env:COMPUTERNAME
    $smMine = @($script:SpCtx[$SmSlug].People | Where-Object { @(Get-Prop $_ 'machines' @()) -contains $smM })
    if ($smMine.Count -ne 1) { return $null }
    return $smMine[0]
}

# OWNERSHIP. In a project that shares its progress every phase has one owner, a person id set when
# it is planned. Only the owner works on it: the verbs that do the work refuse anyone else at every
# stage, and the verbs that change it refuse anyone else once it has left 'planned', each at 88.
# note-friction and open-question stay open to anyone, as does revise-phase -Correction on a
# finished phase. An owner who cannot finish a started phase hands it over ('hand-over'): the phase
# ends as 'handed-over' and a successor continues it. A per-machine project has no owners.
function Get-SpPersonText {
    # A person as status and the refusals name them: '<display name> (<person id>)'.
    param([string]$PtSlug, [string]$PtId)
    $ptPe = @($script:SpCtx[$PtSlug].People | Where-Object { [string](Get-Prop $_ 'id' '') -ceq $PtId })
    if ($ptPe.Count -eq 0) { return "(no person file) ($PtId)" }
    return "$(Get-Prop $ptPe[0] 'name' '?') ($PtId)"
}

function Assert-SpPerson {
    param([string]$PsSlug, [string]$PsId, [string]$PsParam)
    $psPe = @($script:SpCtx[$PsSlug].People | Where-Object { [string](Get-Prop $_ 'id' '') -ceq $PsId })
    if ($psPe.Count -eq 0) {
        $psKnown = (@($script:SpCtx[$PsSlug].People | ForEach-Object { Get-SpPersonText $PsSlug ([string](Get-Prop $_ 'id' '')) })) -join ', '
        Fail 90 "-$PsParam '$PsId' names no person file under progress/people/ (registered: $psKnown). Nothing was written."
    }
}

function Assert-PhaseOpen {
    # A handed-over phase is finished: nothing more runs on it, and it can never also read as abandoned.
    param([string]$PoSlug, $PoPhase)
    if (-not (Test-SharedProgress $PoSlug)) { return }
    if ([string](Get-Prop $PoPhase 'stage' '') -ne 'handed-over') { return }
    $poSucc = [string](Get-Prop $PoPhase 'handedOverTo' '?')
    Fail 90 "Phase '$($PoPhase.id)' was handed over and is finished: $poSucc continues it, so work on $poSucc instead. note-friction, open-question and revise-phase -Correction still accept entries on $($PoPhase.id). Nothing was written."
}

function Assert-PhaseOwner {
    param([string]$OwSlug, $OwPhase, [string]$OwVerb)
    if (-not (Test-SharedProgress $OwSlug)) { return }
    $owId = [string](Get-Prop $OwPhase 'owner' '')
    if (-not $owId) { return }
    $owMe = Get-SpWriter $OwSlug
    if ($owMe -ceq $owId) { return }
    Fail 88 "Phase '$($OwPhase.id)' is owned by $(Get-SpPersonText $OwSlug $owId); only its owner may $OwVerb it, and this machine is $(Get-SpPersonText $OwSlug $owMe). Ask them, or, if they cannot finish it, hand it over: keel-state.ps1 hand-over -Phase $($OwPhase.id) -To <person id> -Detail `"<why>`". Nothing was written."
}

# THE READ-TIME CHECK AFTER A MERGE. Git merges two files without asking keel, so two writes each
# valid alone can merge into a whole that breaks a rule the wrapper refuses for a single writer.
# Run on what Read-SharedState built, which holds every phase, folded ones included, and on the
# person files. Returns one line of text per broken rule (each printed after 'WARNING: after a
# merge, ') and the phases in a run-order clash, which 'status' never names as next. Read by
# 'status', 'tree' and every write; it refuses nothing itself - a write that would add to a broken
# rule is refused by the code that refuses it for one writer (92 for a run order).
function Get-SpMergeProblems {
    param([string]$MpSlug, $MpState)
    $mpOut = @{ Lines = (New-Object System.Collections.Generic.List[string]); Clash = @{} }
    $mpPhases = @(Get-Phases $MpState)
    $mpNodes = @(Get-Nodes $MpState)
    $mpNodeIds = @{}
    foreach ($mpN in $mpNodes) { $mpNodeIds[[string]$mpN.id] = $mpN }
    $mpGoalIds = @{}
    foreach ($mpG in @(Get-GoalList $MpState)) { $mpGoalIds[[string]$mpG.id] = $true }
    $mpPhaseIds = @{}
    foreach ($mpP in $mpPhases) { $mpPhaseIds[[string]$mpP.id] = $true }
    $mpPeople = @($script:SpCtx[$MpSlug].People)
    $mpPersonIds = @{}
    foreach ($mpPe in $mpPeople) { $mpPersonIds[[string](Get-Prop $mpPe 'id' '')] = $true }
    $mpPull = 'Pull again, or have whoever wrote it commit and push that file.'

    # Two phases of one workstream at one run order: the rule add-phase and revise-phase refuse at
    # 92, every stage counted as they count it. A handed-over phase is set aside, since the phase
    # that continues it takes its place in the order.
    $mpGroups = @{}
    foreach ($mpP in $mpPhases) {
        $mpRo = Get-Prop $mpP 'runOrder' -1
        if ($mpRo -lt 0 -or [string](Get-Prop $mpP 'stage' '') -eq 'handed-over') { continue }
        $mpKey = "$($mpP.ws)|$mpRo"
        if (-not $mpGroups.ContainsKey($mpKey)) { $mpGroups[$mpKey] = New-Object System.Collections.Generic.List[object] }
        $mpGroups[$mpKey].Add($mpP)
    }
    foreach ($mpKey in @($mpGroups.Keys | Sort-Object)) {
        $mpSet = @($mpGroups[$mpKey] | Sort-Object -Property id)
        if ($mpSet.Count -lt 2) { continue }
        $mpIds = @($mpSet | ForEach-Object { [string]$_.id })
        $mpWsId = [string]$mpSet[0].ws
        $mpRo = Get-Prop $mpSet[0] 'runOrder' -1
        $mpNone = if ($mpIds.Count -eq 2) { 'neither is' } else { 'none of them is' }
        $mpOut.Lines.Add("$($mpIds -join ' and ') share run order $mpRo in $mpWsId, so $mpNone named as next. Move one with revise-phase -RunOrder, agreed with whoever owns the other.")
        foreach ($mpI in $mpIds) { $mpOut.Clash[$mpI] = [pscustomobject]@{ Order = $mpRo; Ws = $mpWsId; Others = @($mpIds | Where-Object { $_ -ne $mpI }) } }
    }

    # A phase still open under a workstream that one person closed or abandoned while another
    # added the phase.
    foreach ($mpP in $mpPhases) {
        $mpSt = [string](Get-Prop $mpP 'stage' '')
        if (@('delivered', 'abandoned', 'handed-over') -contains $mpSt) { continue }
        $mpW = $mpNodeIds[[string]$mpP.ws]
        if ($null -eq $mpW) { continue }
        $mpWsSt = [string](Get-Prop $mpW 'status' '')
        if ($SpClosedStatuses -contains $mpWsSt) {
            $mpOut.Lines.Add("phase $($mpP.id) is $mpSt under $($mpP.ws), which is $mpWsSt. Abandon the phase, or plan its work in an open workstream.")
        }
    }

    # A reference to an id with no file: each reference a progress file carries.
    foreach ($mpP in $mpPhases) {
        foreach ($mpNeedId in @(Get-NeedIds $mpP)) {
            if ($mpNeedId -match '^W\d+$') {
                if (-not $mpNodeIds.ContainsKey($mpNeedId)) { $mpOut.Lines.Add("phase $($mpP.id) needs $mpNeedId, which has no file under progress/nodes/. $mpPull") }
            }
            elseif (-not $mpPhaseIds.ContainsKey($mpNeedId)) {
                $mpOut.Lines.Add("phase $($mpP.id) needs $mpNeedId, which has no file under progress/phases/ or progress/closed/. $mpPull")
            }
        }
        if (-not $mpNodeIds.ContainsKey([string]$mpP.ws)) {
            $mpOut.Lines.Add("phase $($mpP.id) names workstream $($mpP.ws), which has no file under progress/nodes/. $mpPull")
        }
        $mpOwner = [string](Get-Prop $mpP 'owner' '')
        if ($mpOwner -and -not $mpPersonIds.ContainsKey($mpOwner)) {
            $mpOut.Lines.Add("phase $($mpP.id) names owner $mpOwner, which has no file under progress/people/. $mpPull")
        }
        $mpCont = [string](Get-Prop $mpP 'continues' '')
        if ($mpCont -and -not $mpPhaseIds.ContainsKey($mpCont)) {
            $mpOut.Lines.Add("phase $($mpP.id) continues $mpCont, which has no file under progress/phases/ or progress/closed/. $mpPull")
        }
    }
    foreach ($mpN in $mpNodes) {
        $mpPar = [string](Get-Prop $mpN 'parent' '')
        if ($mpPar -and $mpPar -ne 'root' -and -not $mpNodeIds.ContainsKey($mpPar)) {
            $mpOut.Lines.Add("$($mpN.role) $($mpN.id) names parent $mpPar, which has no file under progress/nodes/. $mpPull")
        }
        if ([string](Get-Prop $mpN 'role' '') -ne 'workstream') { continue }
        foreach ($mpGid in @(Get-Prop $mpN 'goals' @())) {
            if (-not $mpGoalIds.ContainsKey([string]$mpGid)) {
                $mpOut.Lines.Add("workstream $($mpN.id) names goal $mpGid, which has no file under progress/goals/. $mpPull")
            }
        }
    }

    # Needs that form a cycle: two writes, each valid alone, that each add one need. No phase in the
    # cycle can be named as next, since each waits on another.
    foreach ($mpCyc in @(Get-NeedCycles $MpState)) {
        $mpCycIds = @($mpCyc.Ids)
        if ($mpCycIds.Count -eq 2) { $mpCycText = "phases $($mpCycIds -join ' and ') need each other in a cycle, so neither" }
        else { $mpCycText = "phases $(($mpCycIds[0..($mpCycIds.Count - 2)]) -join ', ') and $($mpCycIds[-1]) need each other in a cycle, so none of them" }
        $mpOut.Lines.Add("$mpCycText can be named as next. Re-declare one's needs with revise-phase -Phase $($mpCycIds[0]) -Needs <ids, or none>.")
    }

    # A gate entry written by someone other than the phase's owner. The owner cannot change once work
    # has started, so only a merge produces one: one person changed a planned phase's owner while
    # another, offline, started it. One line per phase and author.
    $mpGateBy = $script:SpCtx[$MpSlug].GateBy
    foreach ($mpP in $mpPhases) {
        $mpOwnerId = [string](Get-Prop $mpP 'owner' '')
        if (-not $mpOwnerId -or -not $mpGateBy.ContainsKey([string]$mpP.id)) { continue }
        $mpByAuthor = [ordered]@{}
        foreach ($mpGe in $mpGateBy[[string]$mpP.id]) {
            $mpBy = [string]$mpGe.By
            if (-not $mpBy -or $mpBy -ceq $mpOwnerId) { continue }
            if (-not $mpByAuthor.Contains($mpBy)) { $mpByAuthor[$mpBy] = New-Object System.Collections.Generic.List[string] }
            $mpByAuthor[$mpBy].Add([string]$mpGe.Name)
        }
        foreach ($mpBy in @($mpByAuthor.Keys)) {
            $mpEntries = $mpByAuthor[$mpBy]
            $mpNoun = if ($mpEntries.Count -eq 1) { 'gate entry' } else { 'gate entries' }
            $mpAre = if ($mpEntries.Count -eq 1) { 'is' } else { 'are' }
            $mpOut.Lines.Add("phase $($mpP.id)'s $mpNoun $($mpEntries -join ', ') $mpAre by $(Get-SpPersonText $MpSlug $mpBy), but its owner is $(Get-SpPersonText $MpSlug $mpOwnerId): the owner was changed while the phase was planned, as someone else started it. Agree who finishes it; if not its owner, hand it over: hand-over -Phase $($mpP.id) -To <person id>.")
        }
    }

    # One machine in two person files: every write from it refuses (Get-SpWriter) until one drops it.
    $mpMach = @{}
    foreach ($mpPe in $mpPeople) {
        foreach ($mpM in @(Get-Prop $mpPe 'machines' @())) {
            $mpMk = [string]$mpM
            if (-not $mpMach.ContainsKey($mpMk)) { $mpMach[$mpMk] = New-Object System.Collections.Generic.List[object] }
            $mpMach[$mpMk].Add($mpPe)
        }
    }
    foreach ($mpMk in @($mpMach.Keys | Sort-Object)) {
        if ($mpMach[$mpMk].Count -lt 2) { continue }
        $mpWho = (@($mpMach[$mpMk] | ForEach-Object { "$(Get-Prop $_ 'id' '?') ($(Get-Prop $_ 'name' '?'))" })) -join ' and '
        $mpOut.Lines.Add("machine $mpMk is listed by two person files, $mpWho, so writes from it are refused until one drops it: join -As <person id> -Clear.")
    }
    return $mpOut
}

function Get-SpNextText {
    # One person's next, in a few words, for the 'others:' line: by the rule 'next:' uses.
    param($NtPool, $NtClash, $NtHeld)
    $ntOrdered = @($NtPool | Where-Object { (Get-Prop $_ 'runOrder' -1) -ge 0 } | Sort-Object -Property @{ Expression = { Get-Prop $_ 'runOrder' -1 } })
    $ntRun = @($ntOrdered | Where-Object { (Get-Prop $_ 'stage' '') -ne 'waiting' -and -not $NtHeld.ContainsKey([string]$_.id) })
    if ($ntRun.Count -eq 0) {
        if (@($ntOrdered | Where-Object { $NtHeld.ContainsKey([string]$_.id) }).Count -gt 0) { return 'waiting or waits on other work' }
        if ($ntOrdered.Count -gt 0) { return 'waiting' }
        return 'no declared run order'
    }
    $ntLow = Get-Prop $ntRun[0] 'runOrder' -1
    $ntTied = @($ntRun | Where-Object { (Get-Prop $_ 'runOrder' -1) -eq $ntLow } | Sort-Object -Property id)
    if ($ntTied.Count -gt 1) { return ('ambiguous, ' + ((@($ntTied | ForEach-Object { [string]$_.id })) -join ' or ')) }
    if ($NtClash.ContainsKey([string]$ntRun[0].id)) { return "none named (run-order clash in $($ntRun[0].ws))" }
    return [string]$ntRun[0].id
}

function Write-SharedState {
    # Writes what changed since Read-SharedState. With -SpExport it writes everything the object
    # holds, every file marked as exported and naming the exporter, each item dated by the latest
    # stamp it stores rather than by now. Returns how many files it wrote.
    param([string]$SpSlug, $SpState, [switch]$SpExport, [string]$SpExporter)
    $spCtx = $script:SpCtx[$SpSlug]
    $spDir = $spCtx.Dir
    $spWho = if ($SpExport) { $SpExporter } else { Get-SpWriter $SpSlug }
    $spMachine = $env:COMPUTERNAME
    $spNow = [string](Add-SpOffset (Now))
    $spX = [bool]$SpExport
    $spWrites = [ordered]@{}
    $spRank = @{}
    $spOwned = @{}
    $spTaken = @{}
    $spFresh = @{}
    $spDeclMeta = @{}
    $spRunMeta = @{}
    $spDeletes = New-Object System.Collections.Generic.List[string]

    # ---- project
    $spProjForm = New-SpForm 'project' $SpState
    if ($spX -or $spCtx.Snap['project'] -ne (Get-SpJson $spProjForm)) {
        $spF = Join-Path $spDir 'project.json'
        $spWrites[$spF] = New-SpFileObj $spProjForm $spWho $spMachine $spNow $spX
        $spRank[$spF] = 1
    }

    # ---- goals
    foreach ($spG in @(Get-GoalList $SpState)) {
        $spForm = New-SpForm 'goal' $spG
        if ($spX -or $spCtx.Snap["goal|$($spG.id)"] -ne (Get-SpJson $spForm)) {
            $spAt = $spNow
            if ($spX) { $spAt = Get-SpLatest @((Get-Prop $spG 'created' $null), (Get-Prop $spG 'statusSetAt' $null)) }
            if (-not $spAt) { $spAt = $spNow }
            $spF = Join-Path (Join-Path $spDir 'goals') "$($spG.id).json"
            $spWrites[$spF] = New-SpFileObj $spForm $spWho $spMachine $spAt $spX
            $spRank[$spF] = 1
        }
    }

    # ---- phases: declaration, run record, and every entry added since the read
    foreach ($spP in @(Get-Phases $SpState)) {
        $spId = $spP.id
        $spPd = Join-Path (Join-Path $spDir 'phases') $spId
        $spOwned[$spId] = New-Object System.Collections.Generic.List[string]
        $spFresh[$spId] = New-Object System.Collections.Generic.List[object]

        $spDecl = New-SpForm 'decl' $spP $spWho
        $spDeclMeta[$spId] = $spCtx.Meta["decl|$spId"]
        if ($spX -or $spCtx.Snap["decl|$spId"] -ne (Get-SpJson $spDecl)) {
            $spAt = $spNow
            if ($spX) { $spAt = Get-SpLatest @((Get-Prop $spP 'revisedAt' $null)) }
            if (-not $spAt) { $spAt = [string](Add-SpOffset (Get-Prop $spP 'created' $spNow)) }
            if (-not $spX) { $spAt = $spNow }
            $spF = Join-Path $spPd 'phase.json'
            $spWrites[$spF] = New-SpFileObj $spDecl $spWho $spMachine $spAt $spX
            $spRank[$spF] = 1
            $spOwned[$spId].Add($spF)
            $spDeclMeta[$spId] = [pscustomobject]@{ by = $spWho; machine = $spMachine; at = $spAt }
        }

        $spRun = New-SpForm 'run' $spP
        $spRunMeta[$spId] = $spCtx.Meta["run|$spId"]
        if ($spX -or $spCtx.Snap["run|$spId"] -ne (Get-SpJson $spRun)) {
            $spAt = $spNow
            if ($spX) {
                $spGateAts = @(foreach ($spGp in @((Get-Prop $spP 'gates' ([pscustomobject]@{})).PSObject.Properties)) { Get-Prop $spGp.Value 'at' $null })
                $spAt = Get-SpLatest $spGateAts
                if (-not $spAt) { $spAt = [string](Add-SpOffset (Get-Prop $spP 'created' $spNow)) }
            }
            $spF = Join-Path $spPd 'run.json'
            $spWrites[$spF] = New-SpFileObj $spRun $spWho $spMachine $spAt $spX
            $spRank[$spF] = 2
            $spOwned[$spId].Add($spF)
            $spRunMeta[$spId] = [pscustomobject]@{ by = $spWho; machine = $spMachine; at = $spAt }
        }

        foreach ($spGp in @((Get-Prop $spP 'gates' ([pscustomobject]@{})).PSObject.Properties)) {
            if (-not $spX -and $spCtx.GateSnap["$spId|$($spGp.Name)"] -eq (Get-SpGateSig $spGp.Name $spGp.Value)) { continue }
            $spAt = [string](Add-SpOffset (Get-Prop $spGp.Value 'at' $spNow))
            $spObj = New-SpFileObj (New-SpGateForm $spGp.Name $spGp.Value) $spWho $spMachine $spAt $spX
            $spF = New-SpEntryName $spAt $spWho (Join-Path (Join-Path $spPd 'gates') $spGp.Name) $spTaken
            $spWrites[$spF] = $spObj
            $spRank[$spF] = 0
            $spOwned[$spId].Add($spF)
            $spFresh[$spId].Add(@{ Kind = 'gate'; Obj = $spObj; Name = (Split-Path -Leaf $spF) })
        }

        foreach ($spKind in @($SpEntryKinds.Keys)) {
            $spArr = @(Get-Prop $spP $spKind @())
            $spN0 = 0
            if (-not $spX -and $spCtx.Counts.ContainsKey("$spId|$spKind")) { $spN0 = [int]$spCtx.Counts["$spId|$spKind"] }
            if ($spArr.Count -lt $spN0) {
                Fail 90 "Phase '$spId' now holds fewer $spKind entries than were read. Shared progress only adds entries; nothing was written."
            }
            for ($spI = $spN0; $spI -lt $spArr.Count; $spI++) {
                $spE = $spArr[$spI]
                $spAt = [string](Add-SpOffset (Get-Prop $spE 'at' $spNow))
                $spObj = New-SpFileObj (New-SpForm $spKind $spE) $spWho $spMachine $spAt $spX
                $spF = New-SpEntryName $spAt $spWho (Join-Path $spPd $SpEntryKinds[$spKind]) $spTaken
                $spWrites[$spF] = $spObj
                $spRank[$spF] = 0
                $spOwned[$spId].Add($spF)
                $spFresh[$spId].Add(@{ Kind = $spKind; Obj = $spObj; Name = (Split-Path -Leaf $spF) })
            }
        }
    }

    # ---- nodes, folding a workstream this write closed or abandoned (or, on export, every one)
    foreach ($spNd in @(Get-Nodes $SpState)) {
        $spForm = New-SpForm 'node' $spNd
        $spSt = [string](Get-Prop $spNd 'status' '')
        $spWasClosed = $SpClosedStatuses -contains [string]$spCtx.NodeStatus[$spNd.id]
        $spFolding = ([string](Get-Prop $spNd 'role' '') -eq 'workstream') -and ($SpClosedStatuses -contains $spSt) -and ($spX -or -not $spWasClosed)
        $spExtras = $null
        if ($spFolding) {
            $spExtras = Add-SpFold $spCtx $SpState $spNd $spWho $spMachine $spNow $spX $spWrites $spRank $spOwned $spFresh $spDeclMeta $spRunMeta $spDeletes
        }
        elseif ($spCtx.NodeExtras.ContainsKey($spNd.id)) { $spExtras = $spCtx.NodeExtras[$spNd.id] }
        if ($spX -or $spFolding -or $spCtx.Snap["node|$($spNd.id)"] -ne (Get-SpJson $spForm)) {
            $spAt = $spNow
            if ($spX) { $spAt = Get-SpLatest @((Get-Prop $spNd 'created' $null), (Get-Prop $spNd 'revisedAt' $null), (Get-Prop $spNd 'closedAt' $null), (Get-Prop $spNd 'abandonedAt' $null)) }
            if (-not $spAt) { $spAt = $spNow }
            $spBody = [ordered]@{}
            foreach ($spFp in @($spForm.PSObject.Properties)) { $spBody[$spFp.Name] = $spFp.Value }
            if ($null -ne $spExtras) { $spBody['phaseStages'] = $spExtras.phaseStages; $spBody['handedOver'] = $spExtras.handedOver }
            $spF = Join-Path (Join-Path $spDir 'nodes') "$($spNd.id).json"
            $spWrites[$spF] = New-SpFileObj ([pscustomobject]$spBody) $spWho $spMachine $spAt $spX
            $spRank[$spF] = 1
        }
    }

    # ---- version acknowledgements
    $spAcks = @(Get-Prop $SpState 'versionAcks' @())
    $spA0 = 0
    if (-not $spX) { $spA0 = [int]$spCtx.Counts['acks'] }
    if ($spAcks.Count -lt $spA0) { Fail 90 "The project now holds fewer version acknowledgements than were read. Shared progress only adds them; nothing was written." }
    for ($spI = $spA0; $spI -lt $spAcks.Count; $spI++) {
        $spAt = [string](Add-SpOffset (Get-Prop $spAcks[$spI] 'at' $spNow))
        $spF = New-SpEntryName $spAt $spWho (Join-Path $spDir 'acks') $spTaken
        $spWrites[$spF] = New-SpFileObj (New-SpForm 'ack' $spAcks[$spI]) $spWho $spMachine $spAt $spX
        $spRank[$spF] = 0
    }

    # ---- the hash check, by text, on every file this command read and now replaces or removes,
    # all before the first write, so an 89 writes nothing
    foreach ($spF in @(@($spWrites.Keys) + @($spDeletes))) {
        $spKey = Get-FullPathKey $spF
        if ($spCtx.Texts.ContainsKey($spKey)) {
            $spNowText = $null
            if (Test-Path -LiteralPath $spF) { $spNowText = [System.IO.File]::ReadAllText($spF, [System.Text.Encoding]::UTF8) }
            if ($spNowText -cne $spCtx.Texts[$spKey]) {
                Fail 89 "'$(Split-Path -Leaf $spF)' under progress/ changed after this command read it, so writing now would erase another write. $(Get-WrittenNote) Re-run the command."
            }
        }
        elseif ((Test-Path -LiteralPath $spF) -and -not $spTaken.ContainsKey($spKey)) {
            Fail 89 "'$(Split-Path -Leaf $spF)' under progress/ appeared after this command read the project, so writing now would erase another write. $(Get-WrittenNote) Re-run the command."
        }
    }
    $spKeys = @($spWrites.Keys)
    $spOrder = @(for ($spIx = 0; $spIx -lt $spKeys.Count; $spIx++) { [pscustomobject]@{ F = $spKeys[$spIx]; R = [int]$spRank[$spKeys[$spIx]]; I = $spIx } })
    $spOrder = @($spOrder | Sort-Object -Property R, I)
    foreach ($spW in $spOrder) {
        Write-SpFile $spW.F $spWrites[$spW.F]
        $script:WrittenList.Add((Split-Path -Leaf $spW.F))
    }
    foreach ($spF in @($spDeletes)) {
        if (Test-Path -LiteralPath $spF) { Remove-Item -LiteralPath $spF -Force }
    }
    return $spWrites.Count
}

function Add-SpFold {
    # A workstream that has just closed or been abandoned: its phases' records go into
    # closed/<id>.json, their own files are removed in the same write, and the node gains each
    # phase's final stage and any hand-over. The artifacts stay where they are, read as documents.
    param($SpContext, $SpState, $SpNode, [string]$SpWho, [string]$SpMachine, [string]$SpNow, [bool]$SpX,
          $SpWrites, $SpRank, $SpOwned, $SpFresh, $SpDeclMeta, $SpRunMeta, $SpDeletes)
    $spStages = [ordered]@{}
    $spHanded = [ordered]@{}
    $spOut = New-Object System.Collections.Generic.List[object]
    foreach ($spP in @(Get-Phases $SpState | Where-Object { $_.ws -eq $SpNode.id -and -not $SpContext.Folded.ContainsKey($_.id) })) {
        $spId = $spP.id
        $spO = [ordered]@{}
        foreach ($spFp in @((New-SpForm 'decl' $spP $SpWho).PSObject.Properties)) { $spO[$spFp.Name] = $spFp.Value }
        foreach ($spFp in @((New-SpForm 'run' $spP).PSObject.Properties)) { $spO[$spFp.Name] = $spFp.Value }
        $spDm = $SpDeclMeta[$spId]
        $spRm = $SpRunMeta[$spId]
        $spO['declaredBy'] = Get-Prop $spDm 'by' $null
        $spO['declaredMachine'] = Get-Prop $spDm 'machine' $null
        $spO['declaredAt'] = Get-Prop $spDm 'at' $null
        $spO['by'] = Get-Prop $spRm 'by' $null
        $spO['machine'] = Get-Prop $spRm 'machine' $null
        $spO['at'] = Get-Prop $spRm 'at' $null
        $spAll = New-Object System.Collections.Generic.List[object]
        if ($SpContext.Raw.ContainsKey($spId)) { foreach ($spR in $SpContext.Raw[$spId]) { $spAll.Add($spR); $SpDeletes.Add($spR.Path) } }
        foreach ($spR in $SpFresh[$spId]) { $spAll.Add($spR) }
        $spSorted = @($spAll | Sort-Object -Property @{ Expression = { $_.Name } })
        $spO['gates'] = @($spSorted | Where-Object { $_.Kind -eq 'gate' } | ForEach-Object { $_.Obj })
        foreach ($spKind in @($SpEntryKinds.Keys)) { $spO[$spKind] = @($spSorted | Where-Object { $_.Kind -eq $spKind } | ForEach-Object { $_.Obj }) }
        $spOut.Add([pscustomobject]$spO)
        foreach ($spF in @($SpOwned[$spId])) { if ($SpWrites.Contains($spF)) { $SpWrites.Remove($spF) } }
        foreach ($spPk in @("decl|$spId", "run|$spId")) { if ($SpContext.Paths.ContainsKey($spPk)) { $SpDeletes.Add($SpContext.Paths[$spPk]) } }
        $spStages[$spId] = Get-Prop $spP 'stage' $null
        if ([string](Get-Prop $spP 'stage' '') -eq 'handed-over') { $spHanded[$spId] = Get-Prop $spP 'handedOverTo' $null }
    }
    $spF = Join-Path (Join-Path $SpContext.Dir 'closed') "$($SpNode.id).json"
    $SpWrites[$spF] = New-SpFileObj ([pscustomobject][ordered]@{ ws = $SpNode.id; phases = $spOut.ToArray() }) $SpWho $SpMachine $SpNow $SpX
    $SpRank[$spF] = 3
    return @{ phaseStages = [pscustomobject]$spStages; handedOver = [pscustomobject]$spHanded }
}

function Get-SpGitName {
    # The display name a new person file takes, from the project repo's git config, once.
    param([string]$SpRoot)
    $spRes = Invoke-Native -Exe 'git' -Arguments @('-C', $SpRoot, 'config', '--get', 'user.name') -NativeSplitStderr
    if ($spRes.NotFound -or $spRes.Code -ne 0) { return '' }
    return $spRes.Text.Trim()
}

function New-SpPersonId {
    param([string]$SpPeopleDir)
    for ($spTry = 0; $spTry -lt 500; $spTry++) {
        $spCand = 'p-' + ('{0:x4}' -f (Get-Random -Minimum 0 -Maximum 65536))
        if (-not (Test-Path -LiteralPath (Join-Path $SpPeopleDir "$spCand.json"))) { return $spCand }
    }
    Fail 90 "Could not choose a free person id under '$SpPeopleDir'."
}

function New-SpPersonObj {
    param([string]$SpPid, [string]$SpDisplay, [string[]]$SpMachines, [string]$SpAt, [bool]$SpExported)
    $spForm = [pscustomobject][ordered]@{ id = $SpPid; name = $SpDisplay; machines = @($SpMachines) }
    return (New-SpFileObj $spForm $SpPid $env:COMPUTERNAME $SpAt $SpExported)
}

function Assert-SpUnread {
    # The text check for a person file 'join' rewrites, which goes through no Write-SharedState.
    param($SpContext, [string]$SpFull)
    $spWas = $SpContext.Texts[(Get-FullPathKey $SpFull)]
    $spIs = $null
    if (Test-Path -LiteralPath $SpFull) { $spIs = [System.IO.File]::ReadAllText($SpFull, [System.Text.Encoding]::UTF8) }
    if ($spIs -cne $spWas) { Fail 89 "'$(Split-Path -Leaf $SpFull)' changed after this command read it. Nothing was written. Re-run the command." }
}


# ------------------------------------------------------------ keel version --
# P9/P10: read live from the plugin manifest rather than hardcoded here.

function Get-KeelVersion {
    try {
        $manifest = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) '.claude-plugin\plugin.json'
        if (Test-Path -LiteralPath $manifest) { return (Read-Json $manifest).version }
    } catch { }
    return 'unknown'
}

# --------------------------------------------------------------- node access --

function Get-Nodes  { param($State) return @(Get-Prop $State 'nodes'  @()) }
function Get-Phases { param($State) return @(Get-Prop $State 'phases' @()) }
function Get-GoalList { param($State) return @(Get-Prop $State 'goals' @()) }

function Find-Node {
    param($State, [string]$NodeId)
    foreach ($n in @(Get-Nodes $State)) { if ($n.id -eq $NodeId) { return $n } }
    return $null
}

function Find-Phase {
    param($State, [string]$PhaseId)
    foreach ($p in @(Get-Phases $State)) { if ($p.id -eq $PhaseId) { return $p } }
    return $null
}

function Get-PhaseOrFail {
    param($State, [string]$PhaseId)
    $p = Find-Phase $State $PhaseId
    if ($null -eq $p) { Fail 94 "Phase '$PhaseId' is not declared. Declare it with add-phase before touching it." }
    return $p
}

# The iteration cap for ONE phase: $IterationCap plus every lift 'lift-cap' recorded on it.
# A phase never lifted has no 'capLifts' field at all - add-phase does not create one - so
# every phase written by an earlier keel reads as the default.
function Get-EffectiveCap {
    param($PhaseObj)
    $lifted = 0
    foreach ($lift in @(Get-Prop $PhaseObj 'capLifts' @())) { $lifted += [int](Get-Prop $lift 'rounds' 0) }
    return ($IterationCap + $lifted)
}

# A phase may only declare a repo the project has registered. Without this, a typo
# ('walletapp' for 'wallet-app') silently creates a repo that never gets a patch, and
# the implement gate then demands changes-walletapp.patch forever.
function Assert-ReposDeclared {
    param($Proj, [string[]]$RepoNames)
    if ($RepoNames.Count -eq 0) { return }
    $cfg = Read-ProjectConfig $Proj.ConfigPath
    $known = @()
    $reg = Get-Prop $cfg 'repos' $null
    if ($null -ne $reg) { $known = @($reg.PSObject.Properties | ForEach-Object { $_.Name }) }
    foreach ($r in $RepoNames) {
        if ($known -notcontains $r) {
            Fail 94 ("Repo '$r' is not declared for project '$($Proj.Slug)'. Known: " + $(if ($known.Count) { $known -join ', ' } else { '(none)' }) + ". Declare it first: add-repo -Name $r -RepoPath <relative-or-absolute path>.")
        }
    }
}

function Assert-GoalsExist {
    param($State, [string[]]$GoalIds)
    $known = @(@(Get-GoalList $State) | ForEach-Object { $_.id })
    foreach ($g in $GoalIds) {
        if ($known -notcontains $g) { Fail 98 "Goal '$g' does not exist in this project. Add it with add-goal first." }
    }
}

function Assert-Parent {
    param($State, [string]$ParentId, [string]$ChildRole)
    if ([string]::IsNullOrWhiteSpace($ParentId) -or $ParentId -eq 'root') { return $null }
    $p = Find-Node $State $ParentId
    if ($null -eq $p) { Fail 94 "Parent '$ParentId' does not exist." }
    if ($p.role -ne 'epic') {
        Fail 93 "Parent '$ParentId' is a $($p.role). Only an epic may contain a $ChildRole (charter P17)."
    }
    return $p
}

# Both revise verbs refuse once anything beneath the node is delivered, for the reason
# 'revise-phase' already gives in its own words: a delivery record cites evidence that
# exists and checks that were run, and retitling what it sits under would make that
# record describe something else.
#
# ONE EXCEPTION: an epic's -Groups line on its own. It says what
# the epic holds, not what a delivered phase did, and an epic's ledger grows after its
# first workstreams deliver - so 'revise-epic' calls this only when -Title or -Goals is
# supplied, and a groups line can be kept true. Title and goal links stay locked.
#
# The WALK is the whole point. For a workstream the set is itself. For an EPIC it is a
# walk DOWN the tree, because an epic contains epics and workstreams and NEVER phases
# directly (charter P17) - so a check on immediate children finds no phases and would
# permit every edit while looking like it had checked. The control that exposes that is
# an epic with no delivered descendant, which must still exit 0.
#
# One helper rather than two copies, so the refusal has ONE home (P10) and the
# workstream and epic paths are the same code reached from two directions.
function Assert-NoDeliveredBeneath {
    param($State, [string]$NodeId, [string]$NodeRole)

    $wsIds = @()
    if ($NodeRole -eq 'workstream') {
        $wsIds = @($NodeId)
    }
    else {
        $pending = @($NodeId)
        while ($pending.Count -gt 0) {
            $cur     = $pending[0]
            $pending = @($pending | Select-Object -Skip 1)
            foreach ($kid in @(Get-Nodes $State | Where-Object { (Get-Prop $_ 'parent' '') -eq $cur })) {
                $kidRole = Get-Prop $kid 'role' ''
                if     ($kidRole -eq 'workstream') { $wsIds   += $kid.id }
                elseif ($kidRole -eq 'epic')       { $pending += $kid.id }
            }
        }
    }
    if ($wsIds.Count -eq 0) { return }

    $hit = @(Get-Phases $State | Where-Object { $wsIds -contains $_.ws -and (Get-Prop $_ 'stage' '') -eq 'delivered' })
    if ($hit.Count -gt 0) {
        Fail 90 ("'$NodeId' has $($hit.Count) delivered phase(s) beneath it: $(($hit | ForEach-Object { $_.id }) -join ', '). " +
                 "A delivery record cites evidence that exists and checks that were run. If delivered work needs redoing, that is a NEW phase whose scope says what it supersedes.")
    }
}

# --------------------------------------------------------- gate conformance --
# P3, second fact: the artifact must CONFORM, not merely exist.

# The non-repo implement artifact. Shared by 'self', 'external', and by an 'agent' phase
# that declares no repos.
function Assert-ActLog {
    param([string]$PhaseDirPath, [string]$MissingMessage)
    $log = Join-Path $PhaseDirPath 'act-log.md'
    if (-not (Test-Path -LiteralPath $log)) { Fail 96 $MissingMessage }
    $c = Get-Content -LiteralPath $log -Raw -Encoding UTF8
    if ($c -notmatch 'Done by:')  { Fail 96 "'act-log.md' must carry a 'Done by:' line naming who acted." }
    if ($c -notmatch 'Done on:')  { Fail 96 "'act-log.md' must carry a 'Done on:' line dating the act." }
}

# ------------------------------------------------- what a gate contract means --
# A gate contract is NOT decided by $content -notmatch '<literal>' - a bare substring
# search anywhere in the file. That fails in BOTH directions. It refuses a plan that
# enumerates its changes under a heading '## Changes' because the contract wants a colon,
# and it accepts one whose only occurrence of the word is 'Changes: none' - or a
# grounding.md that satisfies the gate on a code span quoting the contract's own regex
# while its real answers are headings the check cannot see.
#
# The accepted forms are counted, not invented: across real artifacts in three projects
# they are 'Label:', '**Label:**', '## Label:', '## Label', '## 7. Changes', '*Label:' and
# indented variants of each. Nearly every plan measured uses a heading form, which a
# colon-only contract cannot see at all.
#
# LINE-BASED, never (?m) over the raw text. Artifacts arrive both CRLF and LF, and under
# (?m) the .NET '$' anchors before the \n with the \r unconsumed, so a pattern can fail to
# reach it across a CRLF ending. No line still carries a CR after Get-Content, so
# splitting first disarms that rather than navigating it.
#
# Locals are La-prefixed throughout. PowerShell variable names are case-insensitive
# and a param type constraint follows the name, so a local sharing a name with a
# parameter IS that parameter.

# Does this ONE line introduce $LaLabel? $null when it does not; otherwise what is
# left on the line after the label, and the heading level it sits at - 7 for a
# non-heading, so a plain label line owns the deepest possible section.
function Get-LabelIntroducer {
    param([string]$LaLine, [string]$LaLabel)

    $laText  = $LaLine -replace '^[ \t>]+', ''
    $laLevel = 7
    $laHead  = [regex]::Match($laText, '^(#{1,6})[ \t]+')
    if ($laHead.Success) { $laLevel = $laHead.Groups[1].Value.Length }

    $laText = $laText -replace '^#{1,6}[ \t]+', ''
    $laText = $laText -replace '^[-*+][ \t]+', ''
    $laText = $laText -replace '^\d+[.)][ \t]+', ''
    $laText = $laText -replace '^[*_]{1,3}[ \t]*', ''

    $laPattern = '^' + [regex]::Escape($LaLabel) + '\b[ \t]*[*_]{0,3}[ \t]*:?[ \t]*[*_]{0,3}[ \t]*(?<rest>.*?)[ \t\r]*$'
    $laMatch   = [regex]::Match($laText, $laPattern, 'IgnoreCase')
    if (-not $laMatch.Success) { return $null }

    $laRest = $laMatch.Groups['rest'].Value -replace '[*_`\s]+$', ''
    return [pscustomobject]@{ Rest = $laRest; Level = $laLevel }
}

# ANSWERED: content on the introducer line, or a non-blank line in the section
# below it. A section runs to the next heading at the SAME OR HIGHER level; a
# DEEPER heading is PART of the section. That last clause is not a nicety - the
# house style is '## Changes:' followed by '### 1. <path>', and treating a deeper
# heading as the end of the section refuses real plans in that style.
#
# -LaNotTableRow SKIPS table rows while scanning instead of accepting them, so a
# section holding ONLY table rows falls through to $false. Set by the 'verify'
# limb ALONE: 'verify-report.md' is REQUIRED to
# carry a per-check table, and a bare 'Positive control:' line directly above it
# would be answered BY THAT TABLE, so the limb could never refuse. Skipping - rather
# than treating a table row as closing the section - is deliberate: it still
# accepts a control written below the table, which is a real layout and not the
# defect. The switch defaults OFF, so the other six call sites ('Measured',
# 'Not read', 'Changes', 'Reversible', 'Observable', and investigation.md's own
# 'Positive control') are unchanged. Re-measure before setting it anywhere else:
# real reports pass with it on, but some of them would be refused if the same-line
# limb above were dropped as well.
function Test-LabelAnswered {
    param([string[]]$LaLines, [string]$LaLabel, [switch]$LaNotTableRow)

    for ($laI = 0; $laI -lt $LaLines.Count; $laI++) {
        $laIntro = Get-LabelIntroducer $LaLines[$laI] $LaLabel
        if ($null -eq $laIntro) { continue }
        if ($laIntro.Rest -match '\S') { return $true }
        for ($laJ = $laI + 1; $laJ -lt $LaLines.Count; $laJ++) {
            $laNext = $LaLines[$laJ].TrimEnd("`r")
            if ($laNext -notmatch '\S') { continue }
            $laH = [regex]::Match($laNext, '^[ \t]*(#{1,6})[ \t]+')
            if ($laH.Success -and $laH.Groups[1].Value.Length -le $laIntro.Level) { break }
            if ($LaNotTableRow -and $laNext -match '^[ \t>]*\|') { continue }
            return $true
        }
    }
    return $false
}

# ENUMERATED: the section carries STRUCTURE rather than prose - a deeper heading, a
# list bullet, a numbered item, a table row, or a fenced code block. Used by the
# 'plan' limb only, which is the one contract that asks for changes to be listed
# rather than described. 'Changes: none' is exactly the answer this refuses.
function Test-LabelEnumerated {
    param([string[]]$LaLines, [string]$LaLabel)

    for ($laI = 0; $laI -lt $LaLines.Count; $laI++) {
        $laIntro = Get-LabelIntroducer $LaLines[$laI] $LaLabel
        if ($null -eq $laIntro) { continue }
        for ($laJ = $laI + 1; $laJ -lt $LaLines.Count; $laJ++) {
            $laNext = $LaLines[$laJ].TrimEnd("`r")
            $laH = [regex]::Match($laNext, '^[ \t]*(#{1,6})[ \t]+')
            if ($laH.Success) {
                if ($laH.Groups[1].Value.Length -le $laIntro.Level) { break }
                return $true
            }
            if ($laNext -match '^[ \t]*([-*+][ \t]|\d+[.)][ \t]|\||```|~~~)') { return $true }
        }
    }
    return $false
}

# $TcCfg is the project's parsed keel.json, or $null. It is a PARAMETER and not something
# this function resolves, because $Slug locates the STATE directory and nothing here locates
# the PROJECT directory - the one caller already holds $proj, and re-resolving would give a
# contract checker its own exit-91 failure mode. Get-HandoffDir takes $HoProj/$HoCfg for the
# same reason. Tc-prefixed: locals are prefixed per function in this file, because a local
# sharing a parameter's name IS that parameter.
function Test-Contract {
    param($State, $PhaseObj, [string]$GateName, [string]$VerdictValue, [string]$Slug, $TcCfg)

    # Verdicts that record a non-event carry no artifact requirement.
    if ($GateName -eq 'human') { return }
    if ($VerdictValue -eq 'N/A') { return }
    if ($GateName -eq 'investigate' -and $VerdictValue -eq 'BLOCKED') { return }
    if ($GateName -eq 'plan'   -and $VerdictValue -eq 'REJECTED') { return }

    $phaseDir = Get-PhaseDir $Slug $PhaseObj.id
    if (-not (Test-Path -LiteralPath $phaseDir)) {
        Fail 96 "Phase directory '$phaseDir' does not exist, so gate '$GateName' has no artifact. Write the artifact before recording a verdict (charter P3)."
    }

    # --- implement: the artifact depends on the actor, never the gate list (P18)
    if ($GateName -eq 'implement') {
        $phaseActor    = Get-Prop $PhaseObj 'actor' 'agent'
        $declaredRepos = @(Get-Prop $PhaseObj 'repos' @())
        if ($phaseActor -eq 'agent') {
            $patches = @(Get-ChildItem -LiteralPath $phaseDir -Filter 'changes-*.patch' -File -ErrorAction SilentlyContinue)

            # An agent phase whose legitimate output is documents, in a project with no
            # repos, has NO satisfiable artifact if the patch is demanded unconditionally,
            # while 'self' and 'external' have act-log.md. Research, analysis and
            # bookkeeping projects are mostly such phases. A phase that declares no repos
            # may satisfy the gate either way. WIDENING only (P24): >= 1 patch still passes
            # exactly as before, so nothing already recorded is invalidated.
            if ($declaredRepos.Count -eq 0) {
                if ($patches.Count -eq 0) {
                    Assert-ActLog $phaseDir "Gate 'implement' on an agent phase that declares no repos needs either a 'changes-<repo>.patch' or an 'act-log.md' in '$phaseDir'. Found neither. If the phase produced code, declare its repo with add-repo and revise-phase -Repos; if it produced documents, write act-log.md."
                }
                return
            }

            if ($patches.Count -eq 0) {
                Fail 96 "Gate 'implement' on an agent phase needs at least one 'changes-<repo>.patch' in '$phaseDir'. Found none."
            }
            foreach ($r in $declaredRepos) {
                $want = "changes-$r.patch"
                if (-not (Test-Path -LiteralPath (Join-Path $phaseDir $want))) {
                    Fail 96 "Phase declares repo '$r' but '$want' is not in '$phaseDir'. Every declared repo gets its own patch (the multi-repo trap)."
                }
            }
        }
        else {
            Assert-ActLog $phaseDir "Gate 'implement' on a '$phaseActor' phase needs 'act-log.md' in '$phaseDir'. Found none."
        }
        return
    }

    $artifactName = $GateArtifacts[$GateName]
    if ([string]::IsNullOrWhiteSpace($artifactName)) { return }

    $artifactPath = Join-Path $phaseDir $artifactName
    if (-not (Test-Path -LiteralPath $artifactPath)) {
        Fail 96 "Gate '$GateName' requires '$artifactName' in '$phaseDir'. It is not there."
    }

    $content = Get-Content -LiteralPath $artifactPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($content)) {
        Fail 96 "'$artifactName' exists but is empty. An artifact that exists and says nothing is the failure this check is for."
    }
    $lines = @(Get-Content -LiteralPath $artifactPath -Encoding UTF8)

    switch ($GateName) {

        'ground' {
            if (-not (Test-LabelAnswered $lines 'Measured')) {
                Fail 96 "'grounding.md' must ANSWER 'Measured' - the label followed by what you actually ran or read, either on the same line or as a section under it (charter P7). '## Measured' with a body counts; the word appearing inside a quotation or a code span does not."
            }
            if (-not (Test-LabelAnswered $lines 'Not read')) {
                Fail 96 "'grounding.md' must ANSWER 'Not read' - the label followed by the gaps and why they did not matter. '## Not read' with a body counts. An inventory whose gaps are unstated reads as complete."
            }
        }

        'investigate' {
            if (-not (Test-LabelAnswered $lines 'Positive control')) {
                Fail 96 "'investigation.md' must ANSWER 'Positive control' - the second query proving the instrument would have found the thing had it been there (charter P7). The label with nothing after it is not an answer."
            }
        }

        'plan' {
            if (-not (Test-LabelAnswered $lines 'Changes')) {
                Fail 96 "'plan.md' must ANSWER 'Changes' - the label followed by what will change. '## Changes' with a body counts, and so does 'Changes:' with the list under it."
            }
            if (-not (Test-LabelEnumerated $lines 'Changes')) {
                Fail 96 "'plan.md' names 'Changes' but does not ENUMERATE anything under it - no list, table, sub-heading or code block, only prose. 'Changes: none' is the case this refuses. Say which files, documents, forms, accounts or money change, one item each."
            }
        }

        'verify' {
            # Two conditions, not one. Asking only whether an id sits between two pipes fails
            # in opposite directions: it makes a BOLDED id in a real row invisible, and makes
            # an id quoted in PROSE into a phantom row - which carries no 'run-by:' and so
            # fails the whole report, even for a footnote documenting this very contract. So:
            # the line must BE a table row, and the id cell may carry emphasis. The contract
            # itself is unchanged - the detector was wrong, not the rule. Condition 1 tightens
            # (P24), and shipped with a corpus measurement standing in for a migration: on a
            # snapshot of every verify report then available, it changed no conformance
            # verdict and no matched-row count.
            #
            # ONE named expression, because two copies of it would be two authorities for what
            # a check row is (charter P10). The capture group is new and changes nothing about
            # what -match matches - it is what lets the rule below read the id out of the same
            # cell the detector selected on.
            $tcIdCell = '\|\s*[*_`]*\s*(W\d+\.\d+[a-z]?-C\d+)\s*[*_`]*\s*\|'
            $rows = @($lines | Where-Object { $_ -match '^\s*\|' -and $_ -match $tcIdCell })
            if ($rows.Count -eq 0) {
                Fail 96 "'verify-report.md' has no check rows. Expected at least one table row naming a check id like '| $($PhaseObj.id)-C1 |'."
            }

            # A THIRD face of this contract, and one the DETECTOR is not to blame for. A
            # verifier writes a correct, fully attributed main table and then a short RECAP
            # table lower in the same report, repeating ids the main table had already
            # introduced and attributed. Every recap row is a real table row holding a real
            # check-id cell, so the detector selects it correctly - and none carries
            # 'run-by:', so a row-level rule refuses the whole report. The repair a session
            # reaches for is to DELETE the recap table from a correct report, i.e. this
            # mechanism editing the project's own evidence record to satisfy itself. So the
            # rule moves and the detector does not: what must be attributed is every check
            # ID, on at least one of its rows, rather than every row.
            #
            # Order-independent on purpose. "First matching row wins" would refuse the same
            # report written with its recap ABOVE its main table, and would stop requiring
            # attribution of a row that legitimately repeats an id - a report may list
            # W4.2-C4 twice, as 'row 1: CONFIRMS' and 'row 2: CORRECTS'.
            #
            # WIDENING, not a tightening (charter P24): every report that conformed before
            # still conforms, because every row carrying 'run-by:' implies every id does.
            # Nothing in flight is stranded and no recorded verdict is invalidated. Measured
            # on a frozen snapshot of verify reports: none refused before, none refused
            # after, no change of conformance verdict, no change of matched-row count. That
            # zero carries a positive control, because a zero from an instrument that cannot
            # see movement is worth nothing: the same sweep run against a DETECTOR-narrowed
            # variant - the shape this deliberately does not take - moves the matched-row
            # count on some of those files.
            #
            # ONE further widening, disclosed rather than discovered: Groups[1] takes the
            # FIRST id cell on a row, so a row carrying two check-id cells attributes only the
            # first and the second is never required to carry 'run-by:' at all. Not live: no
            # measured row holds more than one id cell, with a positive control confirming
            # the instrument finds a two-id row when one is planted. If a house style ever
            # puts two checks on one row, this is the line to revisit.
            $tcAttributed = @{}
            foreach ($tcRow in $rows) {
                $tcId = [regex]::Match($tcRow, $tcIdCell).Groups[1].Value
                if (-not $tcAttributed.ContainsKey($tcId)) { $tcAttributed[$tcId] = $false }
                if ($tcRow -match 'run-by:') { $tcAttributed[$tcId] = $true }
            }
            $tcUnattributed = @(@($tcAttributed.Keys) | Where-Object { -not $tcAttributed[$_] } | Sort-Object)
            if ($tcUnattributed.Count -gt 0) {
                Fail 96 "$($tcUnattributed.Count) check id(s) in 'verify-report.md' have no row carrying 'run-by:': $($tcUnattributed -join ', '). Who ran a check is part of the result. A row repeating an id that another row already attributes is a recap, not a second unattributed check."
            }
            if (-not (Test-LabelAnswered $lines 'Positive control' -LaNotTableRow)) {
                Fail 96 "'verify-report.md' must ANSWER 'Positive control' - what proves the checks would have failed had the work been wrong. Every absence claim needs one (charter P7). The per-check table does NOT count: put the control on the label line, or in prose under it."
            }
        }

        'enact' {
            if (-not (Test-LabelAnswered $lines 'Reversible')) {
                Fail 96 "'enact-record.md' must ANSWER 'Reversible' - none, partial or full, for the act in front of you (charter P21)."
            }
            if (-not (Test-LabelAnswered $lines 'Observable')) {
                Fail 96 "'enact-record.md' must ANSWER 'Observable' - yes or no, and how the outcome is read back (charter P21)."
            }
        }

        'record' {
            # -cnotmatch, not -notmatch: PowerShell's -notmatch is case-INSENSITIVE,
            # so with it this limb would print the word 'uppercase' while accepting 'w4.2'
            # - a check that does not mean what it says. Measured before tightening
            # (charter P24): every delivery-record.md then available already carried the id
            # in genuine uppercase, so it strands nothing.
            if ($content -cnotmatch [regex]::Escape($PhaseObj.id.ToUpper())) {
                Fail 96 "'delivery-record.md' must name '$($PhaseObj.id.ToUpper())' in uppercase - it is the only index across projects, and this check is case-sensitive."
            }
            foreach ($r in @(Get-Prop $PhaseObj 'repos' @())) {
                if ($content -notmatch [regex]::Escape($r)) {
                    Fail 96 "'delivery-record.md' does not mention declared repo '$r'. One evidence reference per declared repo."
                }
            }

            # The third assertion, and the only one in this whole switch that is gated on
            # the project's own declaration.
            #
            # The QUESTION is universal and the REFUSAL is not, which is the entire design.
            # A docs set is opt-in, so refusing every project would strand pending phases
            # behind an exit 96 until every record was rewritten - the
            # tightening charter P24 forbids. The route the -cnotmatch limb above used is
            # unavailable here: that one shipped on the measured fact that every record
            # then measured already passed, and when this limb was added no measured record
            # carried a 'Docs impact' line. So the universal half is carried as prose
            # instead, in keel-run-phase gate 8 and PHASE_PROMPT_TEMPLATE.md, and this limb
            # refuses only where a docs root is declared.
            #
            # Presence and non-emptiness ONLY. keel-index.ps1's Resolve-DocsRoot is the one
            # authority on whether a docs declaration is VALID and refuses eleven ways at
            # exit 90 (charter P10); a second, weaker copy here would add a second tightening
            # to the one this limb is. Anything that is not a non-empty string reads as no
            # docs root, which can only ever OMIT this requirement, never invent one.
            $tcDocsRoot = ''
            if ($null -ne $TcCfg) {
                # Index the collection: .PSObject.Properties.Name throws under
                # Set-StrictMode when the object has no properties.
                $tcProp = $TcCfg.PSObject.Properties['docs']
                if ($null -ne $tcProp -and $tcProp.Value -is [string]) {
                    $tcDocsRoot = "$($tcProp.Value)".Trim()
                }
            }
            if ($tcDocsRoot -ne '') {
                # Test-LabelAnswered and NOT a fresh (?m)...$ regex. These artifacts are
                # written CRLF and .NET anchors $ before the \n with the \r unconsumed, so a
                # class omitting \r never reaches it - a correct file reporting nothing, with
                # no error and no exit code. The helper already ends
                # [ \t\r]*$ and accepts 'Docs impact: none', the bold form, and a
                # '## Docs impact' heading with content under it.
                if (-not (Test-LabelAnswered $lines 'Docs impact')) {
                    Fail 96 "'delivery-record.md' must ANSWER 'Docs impact' - this project declares a docs root ('$tcDocsRoot'), so every delivery record says which files under it this phase changed, or answers 'none'. What is required is the STATEMENT and not an edit: 'Docs impact: none' passes and is the common case."
                }
            }
        }
    }
}

# ---------------------------------------------------------- verify binding --
# A verify PASS or INCONCLUSIVE stores a fingerprint of what it verified: the phase folder,
# every git work tree the phase can write to, and any act-log 'Produced:' file no tree covers.
# The human, enact and record gates and 'status' re-take it and WARN naming what moved; they
# never refuse (charter P13 and P24).
#
# Every git call here goes through Invoke-Native, which decodes UTF-8: git's output decoded as
# codepage 437 stores a non-ASCII file name as 'deleted' without a word. This script never
# sets $OutputEncoding, so the paths piped to hash-object use Invoke-Native -NativeInput,
# which does - and which also sets the console input encoding, because without it the whole
# fingerprint fails in any session calling the wrapper from a shell at code page 65001.
#
# Two guarantees, because a broken binding must never read like an unmoved one:
# New-Binding and Compare-Binding never throw - a failure is stored or returned as 'error' - and
# every failure prints one line. Nothing here calls Fail.
#
# Every local and parameter carries a 'Bd' prefix: this script's param() block holds $Path,
# $Name, $Text, $Ws and forty more, and a local of the same name IS that parameter.

function Invoke-BindGit {
    param([string]$BdDir, [string[]]$BdArgs, [string[]]$BdIn)
    $bdAll = @('-C', $BdDir) + $BdArgs
    if ($null -ne $BdIn) { return (Invoke-Native -Exe 'git' -Arguments $bdAll -NativeInput $BdIn -NativeSplitStderr) }
    return (Invoke-Native -Exe 'git' -Arguments $bdAll -NativeSplitStderr)
}

function Get-BindGitMessage {
    # git's own words for a failed call, for the stored error: without them the error could
    # say a call failed and never why. Only 'fatal:' and 'error:' lines, or the
    # last line if there are none, so a line-ending warning naming some other file is not carried.
    #
    # Where the project has quarantine on (charter P23) the file name must not be stored. With
    # the names known, each is replaced literally and any quoted token after it. With none known -
    # the diff and ls-files calls, which run before the name list exists - the message is withheld
    # whole, because git has unquoted formats and no pattern can promise to catch a name there. A
    # leak cannot be taken back; the exit code and the command are still stored.
    param($BdRes, [bool]$BdMask, [string[]]$BdNames)
    $bdErrs = @($BdRes.StdErr | Where-Object { $_ })
    $bdPick = @($bdErrs | Where-Object { $_ -match '^(fatal|error):' })
    if ($bdPick.Count -eq 0) { $bdPick = @($bdErrs | Select-Object -Last 1) }
    $bdMsg = (@($bdPick) -join ' ').Trim()
    if (-not $bdMsg) { return '' }
    if ($BdMask) {
        if (@($BdNames).Count -eq 0) { return ": <git's message withheld: quarantine>" }
        # One pass, longest first. A name inside another name would otherwise be replaced first and
        # leave the rest of the longer one standing, and git's filter failures print the name
        # unquoted. Separate passes also rewrote a short name inside the text already written.
        # Select-Object -Unique, not Sort-Object -Unique: that one compares the sort property, so it
        # would keep one name of each length and leave the others unmasked.
        $bdForms = @(@($BdNames) + @($BdNames | ForEach-Object { $_ -replace '/', '\' }) | Select-Object -Unique | Sort-Object Length -Descending)
        $bdAlt = (@($bdForms | ForEach-Object { [regex]::Escape($_) }) -join '|')
        $bdMsg = [regex]::Replace($bdMsg, $bdAlt, '<masked: quarantine>')
        $bdMsg = $bdMsg -replace "'[^']*'", "'<masked: quarantine>'" -replace '"[^"]*"', '"<masked: quarantine>"'
    }
    return ": $bdMsg"
}

function Split-BindNul {
    param([string]$BdRaw)
    return @($BdRaw -split [char]0 | ForEach-Object { $_.Trim([char[]]@([char]13, [char]10)) } | Where-Object { $_ })
}

function Test-BindExempt {
    # The paths exempt by name, applied to the PROJECT tree only. Derived from keel-run-phase
    # gates 6 to 8. If those sections gain a required write to the project tree, add it here: a
    # missing row fails loud - a warning naming the path - never silent.
    param([string]$BdRel, [string]$BdWs)
    $bdR = $BdRel -replace '\\', '/'
    if ($bdR -eq 'reference/INDEX.md') { return $true }                # gate 8: the index rebuild
    if ($bdR -like 'plan/handoffs/*.md') { return $true }              # gate 8: the handoff
    if ($bdR -like "plan/workstreams/$($BdWs)_*.md") { return $true }  # gate 8: record appended to the spec
    if ($bdR -like "plan/prompts/$BdWs.*-prompt.md") { return $true }  # gate 8: the next phase's prompt
    if ($bdR -like 'progress/*') { return $true }                      # every gate: shared progress, written by the gates themselves
    return $false
}

function Test-BindVersionAckOnly {
    # True only when the working keel.json differs from the stored base in 'keelVersion' alone,
    # which is the one key ack-keel-version writes there. Without this, a version
    # acknowledgement alone warned '(project):keel.json (new since PASS)' at three gates. Any
    # other key still warns, and any failure
    # here returns false, which warns. A keel.json already differing from the base at verify is
    # not reached: its old content is only a hash, so it warns on any change, and recovering it
    # would need a new stored field for a case that is loud and rare (charter P12).
    param([string]$BdDir, [string]$BdBase)
    try {
        # './': a bare '<rev>:<path>' reads from the top of the work tree even under -C, which a
        # project in a subfolder of its repo is not at.
        $bdThen = Invoke-BindGit $BdDir @('show', "${BdBase}:./keel.json")
        if ($bdThen.Code -ne 0) { return $false }
        $bdA = $bdThen.Text | ConvertFrom-Json
        $bdB = Get-Content -LiteralPath (Join-Path $BdDir 'keel.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $bdA -or $null -eq $bdB) { return $false }
        $bdA.PSObject.Properties.Remove('keelVersion')
        $bdB.PSObject.Properties.Remove('keelVersion')
        return (($bdA | ConvertTo-Json -Depth 20 -Compress) -ceq ($bdB | ConvertTo-Json -Depth 20 -Compress))
    }
    catch { return $false }
}

function Get-BindSha {
    param([byte[]]$BdBytes)
    $bdAlg = [System.Security.Cryptography.SHA256]::Create()
    try { return (([BitConverter]::ToString($bdAlg.ComputeHash($BdBytes)) -replace '-', '').ToLower()) }
    finally { $bdAlg.Dispose() }
}

function Get-BindFoldSha {
    # SHA-256 over the file's bytes with every 0x0D that precedes 0x0A removed, so a
    # line-ending repair is not a change. Latin-1 maps byte to character one for one, which keeps
    # a binary file's bytes faithful through the string replace.
    param([string]$BdFile)
    $bdL1 = [Text.Encoding]::GetEncoding(28591)
    $bdS = $bdL1.GetString([IO.File]::ReadAllBytes($BdFile)) -replace "`r`n", "`n"
    return (Get-BindSha -BdBytes ($bdL1.GetBytes($bdS)))
}

function Get-BindPatchSha {
    # A changes-*.patch hashed per file section, leaving out the sections for exempt paths,
    # so a patch re-taken after the record gate's own writes hashes the same and one re-taken after
    # a repair does not.
    param([string]$BdFile, [string]$BdWs)
    $bdL1 = [Text.Encoding]::GetEncoding(28591)
    $bdS = $bdL1.GetString([IO.File]::ReadAllBytes($BdFile)) -replace "`r`n", "`n"
    $bdKeep = New-Object System.Text.StringBuilder
    foreach ($bdSec in [regex]::Split($bdS, '(?m)^(?=diff --git )')) {
        if ($bdSec -match '^diff --git a/(\S+) b/(\S+)' -and (Test-BindExempt $Matches[2] $BdWs)) { continue }
        [void]$bdKeep.Append($bdSec)
    }
    return (Get-BindSha -BdBytes ($bdL1.GetBytes($bdKeep.ToString())))
}

function Get-BindFolderFiles {
    # Top-level files of the phase folder only; subfolders are not read.
    param([string]$BdDir, [string]$BdWs)
    $bdMap = @{}
    if (-not (Test-Path -LiteralPath $BdDir -PathType Container)) { return $bdMap }
    foreach ($bdF in @(Get-ChildItem -LiteralPath $BdDir -File)) {
        if ($bdF.Name -like 'changes-*.patch') { $bdMap[$bdF.Name] = Get-BindPatchSha $bdF.FullName $BdWs }
        else { $bdMap[$bdF.Name] = Get-BindFoldSha $bdF.FullName }
    }
    return $bdMap
}

function Get-BindTreeFiles {
    # Paths differing from $BdBase in the working tree, plus untracked files git does not ignore,
    # each hashed by 'git hash-object' with filters on, so a line-ending-only rewrite hashes the
    # same. A path that no longer exists is 'deleted'. Throws on any git failure; the
    # callers turn that into 'error'.
    param([string]$BdDir, [string]$BdBase, [bool]$BdMask)
    $bdDiff = Invoke-BindGit $BdDir @('diff', '--name-only', '--relative', '-z', $BdBase)
    if ($bdDiff.Code -ne 0) { throw "git diff against $BdBase failed in '$BdDir' (exit $($bdDiff.Code))$(Get-BindGitMessage $bdDiff $BdMask @())" }
    $bdOth = Invoke-BindGit $BdDir @('ls-files', '-o', '--exclude-standard', '-z')
    if ($bdOth.Code -ne 0) { throw "git ls-files failed in '$BdDir' (exit $($bdOth.Code))$(Get-BindGitMessage $bdOth $BdMask @())" }
    $bdNames = @(@(Split-BindNul $bdDiff.Text) + @(Split-BindNul $bdOth.Text) | Sort-Object -Unique)
    $bdMap = @{}
    $bdPresent = New-Object System.Collections.Generic.List[string]
    foreach ($bdN in $bdNames) {
        if (Test-Path -LiteralPath (Join-Path $BdDir $bdN) -PathType Leaf) { $bdPresent.Add($bdN) }
        else { $bdMap[$bdN] = 'deleted' }
    }
    if ($bdPresent.Count -gt 0) {
        # --stdin-paths reads a path from the top of the work tree even under -C, where the names
        # above are relative to $BdDir, so a project in a subfolder of its repo would fail 0 of
        # N. The map stays keyed by the relative name.
        $bdPre = Invoke-BindGit $BdDir @('rev-parse', '--show-prefix')
        $bdPrefix = if ($bdPre.Code -eq 0) { $bdPre.Text.Trim() } else { '' }
        $bdFromTop = @($bdPresent | ForEach-Object { "$bdPrefix$_" })
        $bdH = Invoke-BindGit $BdDir @('hash-object', '--stdin-paths') $bdFromTop
        $bdHs = @($bdH.Output | Where-Object { $_ } | ForEach-Object { $_.Trim() })
        if ($bdH.Code -ne 0 -or $bdHs.Count -ne $bdPresent.Count) {
            throw "git hash-object failed in '$BdDir' (exit $($bdH.Code), $($bdHs.Count) of $($bdPresent.Count) hashed)$(Get-BindGitMessage $bdH $BdMask ($bdFromTop + $bdPresent.ToArray()))"
        }
        for ($bdI = 0; $bdI -lt $bdPresent.Count; $bdI++) { $bdMap[$bdPresent[$bdI]] = $bdHs[$bdI] }
    }
    return $bdMap
}

function Get-BindDigest {
    # SHA-256 over the sorted 'path NUL hash' lines - ordinal sort, so it cannot vary by culture.
    param([hashtable]$BdMap)
    [string[]]$bdKeys = @($BdMap.Keys | ForEach-Object { [string]$_ })
    [Array]::Sort($bdKeys, [StringComparer]::Ordinal)
    $bdLines = @($bdKeys | ForEach-Object { "$_`0$($BdMap[$_])" })
    return (Get-BindSha -BdBytes ([Text.Encoding]::UTF8.GetBytes(($bdLines -join "`n"))))
}

function Get-BindMap {
    # A stored map comes back from state.json as a PSCustomObject; a fresh one is a hashtable.
    # Both become a hashtable here. Properties are enumerated, never read as '.Properties.Name',
    # which throws under strict mode on an object with none.
    param($BdObj)
    $bdMap = @{}
    if ($null -eq $BdObj) { return $bdMap }
    if ($BdObj -is [System.Collections.IDictionary]) {
        foreach ($bdK in @($BdObj.Keys)) { $bdMap[[string]$bdK] = [string]$BdObj[$bdK] }
        return $bdMap
    }
    foreach ($bdP in @($BdObj.PSObject.Properties)) { $bdMap[$bdP.Name] = [string]$bdP.Value }
    return $bdMap
}

function Get-BindQuarRoot {
    return (([IO.Path]::GetFullPath((Join-Path $KeelHome 'quarantine'))).TrimEnd('\').ToLower() + '\')
}

function Get-BindTrees {
    # Which work trees a phase can write to. The project root, named '(project)', when
    # keel.json has git: true - and if it is not a work tree for ANY reason, that is an error, not
    # a silent bind of the folder alone. Then each phase repo from
    # keel.json, kept only if it is a work tree, de-duplicated by full path. Nothing under the
    # quarantine store is ever bound.
    param($BdProj, $BdCfg, $BdPhaseObj)
    $bdTrees = @()
    $bdSeen = @{}
    $bdQuar = Get-BindQuarRoot
    $bdRoot = ([IO.Path]::GetFullPath($BdProj.Root)).TrimEnd('\')
    $bdNeedGit = [bool](Get-Prop $BdCfg 'git' $false)
    $bdRepoNames = @(Get-Prop $BdPhaseObj 'repos' @())
    if (($bdNeedGit -or $bdRepoNames.Count -gt 0) -and $null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git not found on PATH'
    }
    if ($bdNeedGit -and -not ($bdRoot.ToLower() + '\').StartsWith($bdQuar)) {
        $bdRp = Invoke-BindGit $bdRoot @('rev-parse', '--is-inside-work-tree')
        if ($bdRp.Code -ne 0 -or $bdRp.Text.Trim() -ne 'true') {
            throw "the project root is not a git work tree (rev-parse exit $($bdRp.Code))"
        }
        $bdTrees += [pscustomobject]@{ name = $BindProjectTree; dir = $bdRoot }
        $bdSeen[$bdRoot.ToLower()] = $true
    }
    $bdReg = Get-Prop $BdCfg 'repos' $null
    foreach ($bdRn in $bdRepoNames) {
        $bdRepoPath = [string](Get-Prop (Get-Prop $bdReg $bdRn $null) 'path' '')
        if (-not $bdRepoPath) { continue }
        $bdTreeDir = if ([IO.Path]::IsPathRooted($bdRepoPath)) { $bdRepoPath } else { Join-Path $bdRoot $bdRepoPath }
        $bdTreeDir = ([IO.Path]::GetFullPath($bdTreeDir)).TrimEnd('\')
        if ($bdSeen.ContainsKey($bdTreeDir.ToLower())) { continue }
        if (($bdTreeDir.ToLower() + '\').StartsWith($bdQuar)) { continue }
        if (-not (Test-Path -LiteralPath $bdTreeDir -PathType Container)) { continue }
        $bdTr = Invoke-BindGit $bdTreeDir @('rev-parse', '--is-inside-work-tree')
        if ($bdTr.Code -ne 0 -or $bdTr.Text.Trim() -ne 'true') { continue }
        $bdTrees += [pscustomobject]@{ name = $bdRn; dir = $bdTreeDir }
        $bdSeen[$bdTreeDir.ToLower()] = $true
    }
    return $bdTrees
}

function Get-BindProduced {
    # act-log.md 'Produced:' paths that NO bound tree covers - outside every tree, or inside one
    # but ignored by git. A path in the quarantine store is keyed by a hash of the path, so
    # its name is never stored or printed.
    param([string]$BdPhaseDir, [string]$BdRoot, [object[]]$BdTrees)
    $bdMap = @{}
    $bdAl = Join-Path $BdPhaseDir 'act-log.md'
    if (-not (Test-Path -LiteralPath $bdAl -PathType Leaf)) { return $bdMap }
    $bdQuar = Get-BindQuarRoot
    foreach ($bdLine in @(Get-Content -LiteralPath $bdAl -Encoding UTF8)) {
        if ($bdLine -notmatch '^\s*(?:[-*]\s*)?\**Produced\**\s*:\s*(.+)$') { continue }
        foreach ($bdTok in @($Matches[1] -split '[,;]')) {
            $bdT = $bdTok.Trim().Trim([char[]]@('`', '*')).Trim()
            if (-not $bdT) { continue }
            try { $bdFull = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($bdT)) { $bdT } else { Join-Path $BdRoot $bdT })) }
            catch { continue }
            $bdCovered = $false
            foreach ($bdTr in @($BdTrees)) {
                $bdTd = [string](Get-Prop $bdTr 'dir' '')
                $bdTk = $bdTd.TrimEnd('\').ToLower() + '\'
                if (-not $bdFull.ToLower().StartsWith($bdTk)) { continue }
                $bdRel = $bdFull.Substring($bdTk.Length) -replace '\\', '/'
                if ((Invoke-BindGit $bdTd @('check-ignore', '-q', '--', $bdRel)).Code -ne 0) { $bdCovered = $true }
            }
            if ($bdCovered) { continue }
            $bdKey = $bdT
            if ($bdFull.ToLower().StartsWith($bdQuar)) {
                $bdKey = 'quarantine-store file ' + (Get-BindSha -BdBytes ([Text.Encoding]::UTF8.GetBytes($bdFull.ToLower()))).Substring(0, 12)
            }
            if (Test-Path -LiteralPath $bdFull -PathType Leaf) { $bdMap[$bdKey] = Get-BindFoldSha $bdFull }
            else { $bdMap[$bdKey] = 'missing' }
        }
    }
    return $bdMap
}

function New-Binding {
    # Taken at record-verdict -Gate verify with PASS or INCONCLUSIVE. Never throws.
    param($BdProj, $BdCfg, $BdPhaseObj, [string]$BdVerdict)
    $bdOut = [pscustomobject]@{ takenAt = (Now); boundTo = $BdVerdict; folder = @{}; trees = @(); produced = @{}; error = $null }
    try {
        $bdWsId = Ws-Of-Phase $BdPhaseObj.id
        $bdPd = Get-PhaseDir $BdProj.Slug $BdPhaseObj.id
        $bdFolder = Get-BindFolderFiles $bdPd $bdWsId
        $bdTreeList = @(Get-BindTrees $BdProj $BdCfg $BdPhaseObj)
        $bdStored = @()
        foreach ($bdTr in $bdTreeList) {
            $bdHd = Invoke-BindGit $bdTr.dir @('rev-parse', '--verify', '-q', 'HEAD')
            $bdBase = if ($bdHd.Code -eq 0 -and $bdHd.Text.Trim()) { $bdHd.Text.Trim() } else { $BindEmptyTree }
            $bdFiles = Get-BindTreeFiles $bdTr.dir $bdBase (Test-Quarantine $BdCfg)
            $bdStored += [pscustomobject]@{
                name   = $bdTr.name
                dir    = $bdTr.dir
                base   = $bdBase
                count  = $bdFiles.Count
                digest = (Get-BindDigest $bdFiles)
                files  = $(if ($bdFiles.Count -le $BindCap) { $bdFiles } else { $null })
            }
        }
        $bdProduced = Get-BindProduced $bdPd $BdProj.Root $bdTreeList
        $bdOut.folder   = $bdFolder
        $bdOut.trees    = $bdStored
        $bdOut.produced = $bdProduced
    }
    catch {
        $bdOut.folder   = @{}
        $bdOut.trees    = @()
        $bdOut.produced = @{}
        $bdOut.error    = $_.Exception.Message
    }
    return $bdOut
}

function New-BindMove {
    param([string]$BdWhere, [string]$BdWhat, [string]$BdHow)
    return [pscustomobject]@{ where = $BdWhere; path = $BdWhat; how = $BdHow }
}

function Format-BindMoved {
    # The one formatter for both renderings, so a stored entry is never re-split to print it:
    # stored '<where>:<path> (<how>)' (bindingCheck.moved), printed '<where>: <path> (<how>)'.
    param($BdItem, [switch]$BdStored)
    if ($BdStored) { return "$($BdItem.where):$($BdItem.path) ($($BdItem.how))" }
    return "$($BdItem.where): $($BdItem.path) ($($BdItem.how))"
}

function Compare-Binding {
    # Re-takes the bound scope - each STORED tree against its STORED base, so the enact gate's
    # commit moves nothing - and returns what moved, exemptions dropped. A binding that
    # failed at verify, or a comparison that fails now, comes back as 'error', never as an empty
    # list: silence would read exactly like a phase that has no binding at all. Never throws.
    param($BdOld, $BdProj, $BdPhaseObj)
    $bdRes = [pscustomobject]@{ moved = @(); error = $null; notTaken = $false }
    $bdErr = Get-Prop $BdOld 'error' $null
    if ($bdErr) { $bdRes.error = [string]$bdErr; $bdRes.notTaken = $true; return $bdRes }
    try {
        $bdMoved = New-Object System.Collections.Generic.List[object]
        $bdWsId = Ws-Of-Phase $BdPhaseObj.id
        $bdPd = Get-PhaseDir $BdProj.Slug $BdPhaseObj.id
        # An unreadable config masks: not knowing whether a project is quarantined is not 'it is not'.
        $bdCmpCfg = Read-ProjectConfig $BdProj.ConfigPath
        $bdMaskErr = ($null -eq $bdCmpCfg) -or (Test-Quarantine $bdCmpCfg)

        $bdOldF = Get-BindMap (Get-Prop $BdOld 'folder' $null)
        $bdNowF = Get-BindFolderFiles $bdPd $bdWsId
        foreach ($bdK in @($bdOldF.Keys | Sort-Object)) {
            if ($BindFolderExempt -contains $bdK) { continue }
            if (-not $bdNowF.ContainsKey($bdK)) { $bdMoved.Add((New-BindMove 'phase folder' $bdK 'removed')) }
            elseif ($bdNowF[$bdK] -ne $bdOldF[$bdK]) { $bdMoved.Add((New-BindMove 'phase folder' $bdK 'changed')) }
        }
        foreach ($bdK in @($bdNowF.Keys | Sort-Object)) {
            if ($bdOldF.ContainsKey($bdK) -or $BindFolderExempt -contains $bdK) { continue }
            if ($bdK -match $BindFolderArtifact) { $bdMoved.Add((New-BindMove 'phase folder' $bdK 'new')) }
        }

        $bdOldTrees = @(Get-Prop $BdOld 'trees' @())
        foreach ($bdTr in $bdOldTrees) {
            $bdTn = [string](Get-Prop $bdTr 'name' '')
            $bdTreeDir = [string](Get-Prop $bdTr 'dir' '')
            $bdTreeBase = [string](Get-Prop $bdTr 'base' '')
            $bdNowT = Get-BindTreeFiles $bdTreeDir $bdTreeBase $bdMaskErr
            $bdOldFiles = Get-Prop $bdTr 'files' $null
            if ($null -eq $bdOldFiles) {
                # Over the cap at verify: only the digest was stored, so exemptions cannot apply.
                if ((Get-BindDigest $bdNowT) -ne [string](Get-Prop $bdTr 'digest' '')) {
                    $bdMoved.Add((New-BindMove $bdTn "($(Get-Prop $bdTr 'count' 0) paths bound, over the $BindCap cap - not itemised)" 'changed'))
                }
                continue
            }
            $bdOldT = Get-BindMap $bdOldFiles
            foreach ($bdK in @(@($bdOldT.Keys) + @($bdNowT.Keys) | Sort-Object -Unique)) {
                if ($bdTn -eq $BindProjectTree -and (Test-BindExempt $bdK $bdWsId)) { continue }
                $bdO = $null; $bdN = $null
                if ($bdOldT.ContainsKey($bdK)) { $bdO = [string]$bdOldT[$bdK] }
                if ($bdNowT.ContainsKey($bdK)) { $bdN = [string]$bdNowT[$bdK] }
                if ($bdO -eq $bdN) { continue }
                if ($bdTn -eq $BindProjectTree -and $bdK -eq 'keel.json' -and $null -eq $bdO -and $null -ne $bdN -and (Test-BindVersionAckOnly $bdTreeDir $bdTreeBase)) { continue }
                $bdHow = 'changed'
                if ($null -eq $bdO) { $bdHow = 'new since PASS' } elseif ($null -eq $bdN) { $bdHow = 'reverted since PASS' }
                $bdMoved.Add((New-BindMove $bdTn $bdK $bdHow))
            }
        }

        $bdOldP = Get-BindMap (Get-Prop $BdOld 'produced' $null)
        $bdNowP = Get-BindProduced $bdPd $BdProj.Root $bdOldTrees
        foreach ($bdK in @(@($bdOldP.Keys) + @($bdNowP.Keys) | Sort-Object -Unique)) {
            $bdO = $null; $bdN = $null
            if ($bdOldP.ContainsKey($bdK)) { $bdO = $bdOldP[$bdK] }
            if ($bdNowP.ContainsKey($bdK)) { $bdN = $bdNowP[$bdK] }
            if ($bdO -ne $bdN) { $bdMoved.Add((New-BindMove 'Produced' $bdK 'changed')) }
        }
        $bdRes.moved = $bdMoved.ToArray()
    }
    catch { $bdRes.error = $_.Exception.Message }
    return $bdRes
}

function Write-BindGateLines {
    # What a comparing gate prints, before its own 'gate ... =' line. Nothing when nothing moved.
    param([string]$BdPhaseId, $BdOld, $BdCheck)
    if ($BdCheck.error) {
        if ($BdCheck.notTaken) { Say "WARNING: could not compare $BdPhaseId's verify binding - it was not taken at verify ($($BdCheck.error)). This gate's verdict is recorded regardless." }
        else { Say "WARNING: could not compare $BdPhaseId's verify binding: $($BdCheck.error). This gate's verdict is recorded regardless." }
        return
    }
    $bdM = @($BdCheck.moved)
    if ($bdM.Count -eq 0) { return }
    Say "WARNING: $BdPhaseId's verify $(Get-Prop $BdOld 'boundTo' '?') (recorded $(Format-StateStamp (Get-Prop $BdOld 'takenAt' $null))) no longer matches what it verified. $($bdM.Count) path(s) moved since:"
    foreach ($bdI in @($bdM | Select-Object -First 10)) { Say "  $(Format-BindMoved $bdI)" }
    if ($bdM.Count -gt 10) { Say "  ... and $($bdM.Count - 10) more" }
    Say "  If that was a repair, run another verify round before relying on the verdict (keel-run-phase gate 5). This gate's verdict is recorded regardless."
}

function Write-BindStatusLine {
    # One line per in-flight phase whose binding moved or could not be compared. Silent
    # otherwise (P16), and no git call at all for a phase with no binding. Wholly inside a
    # try/catch so a defect here cannot cut status short - session start reads everything below.
    param($BdProj, $BdPhaseObj)
    try {
        $bdOld = Get-Prop (Get-Prop (Get-Prop $BdPhaseObj 'gates' $null) 'verify' $null) 'binding' $null
        if ($null -eq $bdOld) { return }
        $bdChk = Compare-Binding $bdOld $BdProj $BdPhaseObj
        if ($bdChk.error) {
            $bdWhy = [string]$bdChk.error
            if ($bdChk.notTaken) { $bdWhy = "it was not taken at verify ($($bdChk.error))" }
            Say "  WARNING: $($BdPhaseObj.id) verify binding could not be compared: $bdWhy."
            return
        }
        $bdM = @($bdChk.moved)
        if ($bdM.Count -eq 0) { return }
        Say "  WARNING: $($BdPhaseObj.id) verify $(Get-Prop $bdOld 'boundTo' '?') no longer matches what it verified: $($bdM.Count) path(s) moved since $(Format-StateStamp (Get-Prop $bdOld 'takenAt' $null)), first $($bdM[0].where): $($bdM[0].path)."
    }
    catch {
        Say "  WARNING: $(Get-Prop $BdPhaseObj 'id' '?') verify binding could not be compared: $($_.Exception.Message)."
    }
}

# ------------------------------------------------------------- dependencies --
# A phase may declare that it needs other phases, or whole workstreams, delivered before it can
# start: 'add-phase -Needs' and 'revise-phase -Needs', in every kind of project. 'status' does not
# name a phase as next while a need is unmet, says what it waits on, and flags needed work that was
# abandoned (the need can never be met) or revised after the need was declared. Keel records a
# need someone declared and never infers one from a scope or an order.
#
# A need is { id, at }: a phase id or a workstream id, and when the need was declared. A phase id
# stands for that phase and each phase its hand-over chain continues into, so it is met when the
# last of them is delivered; a workstream id is met when the workstream is DELIVERED. The needs of
# a finished phase (delivered, abandoned, handed over) hold nothing back, so they form no cycle.

function Get-NeedIndex {
    # Every phase by id, and the phase ids of each workstream, read once per question.
    param($NiState)
    $niOut = @{ Phase = @{}; Ws = @{} }
    foreach ($niP in @(Get-Phases $NiState)) {
        $niOut.Phase[[string]$niP.id] = $niP
        $niW = [string](Get-Prop $niP 'ws' '')
        if (-not $niOut.Ws.ContainsKey($niW)) { $niOut.Ws[$niW] = New-Object System.Collections.Generic.List[string] }
        $niOut.Ws[$niW].Add([string]$niP.id)
    }
    return $niOut
}

function Test-NeedFinished {
    param($TfP)
    return (@('delivered', 'abandoned', 'handed-over') -contains [string](Get-Prop $TfP 'stage' ''))
}

function Get-NeedChain {
    # A phase and each phase its hand-over chain continues into, in order. Missing is the id of a
    # link that names no phase, if one does.
    param($NcIndex, [string]$NcId)
    $ncOut = @{ Phases = (New-Object System.Collections.Generic.List[object]); Missing = $null }
    $ncSeen = @{}
    $ncCur = $NcId
    while ($ncCur -and -not $ncSeen.ContainsKey($ncCur)) {
        $ncSeen[$ncCur] = $true
        if (-not $NcIndex.Phase.ContainsKey($ncCur)) { $ncOut.Missing = $ncCur; break }
        $ncP = $NcIndex.Phase[$ncCur]
        $ncOut.Phases.Add($ncP)
        if ([string](Get-Prop $ncP 'stage' '') -ne 'handed-over') { break }
        $ncCur = [string](Get-Prop $ncP 'handedOverTo' '')
        if (-not $ncCur) { $ncOut.Missing = '?' }
    }
    return $ncOut
}

function Get-NeedTargets {
    # The phase ids one need points at, for the cycle check: a phase id, its hand-over chain; a
    # workstream id, every phase of it, and the phase being added when it belongs to it.
    param($NtIndex, [string]$NtId, [string]$NtNewId, [string]$NtNewWs)
    $ntOut = New-Object System.Collections.Generic.List[string]
    if ($NtId -match '^W\d+$') {
        if ($NtIndex.Ws.ContainsKey($NtId)) { foreach ($ntI in $NtIndex.Ws[$NtId]) { $ntOut.Add($ntI) } }
        if ($NtNewId -and $NtNewWs -eq $NtId -and -not $ntOut.Contains($NtNewId)) { $ntOut.Add($NtNewId) }
    }
    else {
        foreach ($ntP in (Get-NeedChain $NtIndex $NtId).Phases) { $ntOut.Add([string]$ntP.id) }
    }
    return @($ntOut)
}

function Get-NeedIds {
    # The ids a phase needs, in declared order.
    param($NdP)
    return @(@(Get-Prop $NdP 'needs' @()) | ForEach-Object { [string](Get-Prop $_ 'id' '') } | Where-Object { $_ })
}

function Find-NeedPath {
    # A path of needs from one phase back to itself, as 'W5.3 -> W4.1 -> W5.3', or $null. The
    # phase's own needs are the ids given, since they are what is about to be written.
    param($FpIndex, [string]$FpId, [string]$FpWs, [string[]]$FpNeedIds, [bool]$FpIsNew)
    $fpNewId = if ($FpIsNew) { $FpId } else { '' }
    $fpPrev = @{}
    $fpQueue = New-Object System.Collections.Generic.Queue[string]
    $fpQueue.Enqueue($FpId)
    $fpPrev[$FpId] = ''
    while ($fpQueue.Count -gt 0) {
        $fpCur = $fpQueue.Dequeue()
        if ($fpCur -eq $FpId) { $fpIds = @($FpNeedIds) }
        else {
            $fpP = $FpIndex.Phase[$fpCur]
            if ($null -eq $fpP -or (Test-NeedFinished $fpP)) { continue }
            $fpIds = @(Get-NeedIds $fpP)
        }
        foreach ($fpNeed in $fpIds) {
            foreach ($fpT in @(Get-NeedTargets $FpIndex $fpNeed $fpNewId $FpWs)) {
                if ($fpT -eq $FpId) {
                    $fpPath = New-Object System.Collections.Generic.List[string]
                    $fpPath.Add($FpId)
                    $fpBack = $fpCur
                    while ($fpBack -ne $FpId) { $fpPath.Insert(0, $fpBack); $fpBack = $fpPrev[$fpBack] }
                    $fpPath.Insert(0, $FpId)
                    return ($fpPath -join ' -> ')
                }
                if ($fpPrev.ContainsKey($fpT)) { continue }
                $fpPrev[$fpT] = $fpCur
                $fpQueue.Enqueue($fpT)
            }
        }
    }
    return $null
}

function Read-NeedsParam {
    # -Needs as the list to store, or a refusal before anything is written. 'none' is no needs.
    param($RnState, [string]$RnPhaseId, [string]$RnWsId, [string]$RnRaw, [bool]$RnIsNew, [string]$RnSlug)
    if ($RnRaw.Trim() -eq 'none') { return @() }
    $rnIds = New-Object System.Collections.Generic.List[string]
    foreach ($rnI in @(Split-Csv $RnRaw)) { if (-not $rnIds.Contains($rnI)) { $rnIds.Add($rnI) } }
    if ($rnIds.Count -eq 0) { Fail 90 "-Needs names no id. Give phase or workstream ids, comma-separated, or none for no needs. Nothing was written." }
    $rnPull = if (Test-SharedProgress $RnSlug) { ' If someone else added it, pull first.' } else { '' }
    $rnIndex = Get-NeedIndex $RnState
    foreach ($rnI in $rnIds) {
        if ($rnI -cnotmatch '^W\d+$' -and $rnI -cnotmatch '^W\d+\.\d+[a-z]?$') {
            Fail 90 "-Needs '$rnI' is not a phase or workstream id. Expected W<n>.<p> for a phase (e.g. W4.2 or W4.5b) or W<n> for a whole workstream (e.g. W4). Nothing was written."
        }
        if ($rnI -ceq $RnPhaseId) { Fail 90 "Phase '$RnPhaseId' cannot need itself. Nothing was written." }
        if ($rnI -ceq $RnWsId) { Fail 90 "Phase '$RnPhaseId' cannot need its own workstream $RnWsId`: it is part of it, so the need could never be met. Order the phases of one workstream by run order. Nothing was written." }
        if ($rnI -match '^W\d+$') {
            $rnNode = Find-Node $RnState $rnI
            if ($null -eq $rnNode -or [string](Get-Prop $rnNode 'role' '') -ne 'workstream') { Fail 94 "-Needs '$rnI' names no workstream on this copy.$rnPull Nothing was written." }
        }
        elseif (-not $rnIndex.Phase.ContainsKey($rnI)) { Fail 94 "-Needs '$rnI' names no phase on this copy.$rnPull Nothing was written." }
    }
    $rnPath = Find-NeedPath $rnIndex $RnPhaseId $RnWsId @($rnIds) $RnIsNew
    if ($rnPath) { Fail 90 "-Needs would close a cycle of needs: $rnPath. No phase in it could ever be named as next. Nothing was written." }
    $rnAt = Now
    return @($rnIds | ForEach-Object { [pscustomobject]@{ id = $_; at = $rnAt } })
}

function Get-NeedState {
    # Where one need stands: met, never (the needed work was abandoned), missing (an id naming
    # nothing on this copy) or waiting, with the text 'status' prints, and whether the needed work
    # was revised after the need was declared, which only a waiting need reports.
    param($NsIndex, $NsState, [string]$NsSlug, $NsNeed)
    $nsId = [string](Get-Prop $NsNeed 'id' '')
    $nsAt = Get-SpTicks (Get-Prop $NsNeed 'at' $null)
    $nsShared = $NsSlug -and (Test-SharedProgress $NsSlug)
    $nsOut = [pscustomobject]@{ Kind = 'waiting'; Text = $nsId; Revised = $false }
    if ($nsId -match '^W\d+$') {
        $nsNode = Find-Node $NsState $nsId
        if ($null -eq $nsNode) { $nsOut.Kind = 'missing'; return $nsOut }
        $nsSt = [string](Get-Prop $nsNode 'status' '')
        if ($nsSt -eq 'DELIVERED') { $nsOut.Kind = 'met'; return $nsOut }
        if ($nsSt -eq 'ABANDONED') { $nsOut.Kind = 'never'; $nsOut.Text = "workstream $nsId"; return $nsOut }
        $nsOpen = New-Object System.Collections.Generic.List[string]
        $nsWsPhases = @()
        if ($NsIndex.Ws.ContainsKey($nsId)) { $nsWsPhases = @($NsIndex.Ws[$nsId] | ForEach-Object { $NsIndex.Phase[$_] }) }
        foreach ($nsP in @($nsWsPhases | Sort-Object -Property @{ Expression = { $x = Get-Prop $_ 'runOrder' -1; if ($x -lt 0) { 9999 } else { $x } } }, id)) {
            # A phase added since the need counts as a revision; a hand-over's successor does not,
            # since it continues work the workstream already had.
            if ($nsAt -gt 0 -and -not (Get-Prop $nsP 'continues' $null) -and (Get-SpTicks (Get-Prop $nsP 'created' $null)) -gt $nsAt) { $nsOut.Revised = $true }
            if (Test-NeedFinished $nsP) { continue }
            $nsOwn = ''
            if ($nsShared -and (Get-Prop $nsP 'owner' '')) { $nsOwn = ", owned by $(Get-SpPersonText $NsSlug ([string]$nsP.owner))" }
            $nsOpen.Add("$($nsP.id) $(Get-Prop $nsP 'stage' '?')$nsOwn")
        }
        if ($nsAt -gt 0 -and (Get-SpTicks (Get-Prop $nsNode 'revisedAt' $null)) -gt $nsAt) { $nsOut.Revised = $true }
        $nsList = if ($nsOpen.Count -gt 0) { "open: $($nsOpen -join '; ')" } else { 'no open phases; met once the workstream is closed' }
        $nsOut.Text = "$nsId (workstream $nsSt; $nsList)"
        return $nsOut
    }
    $nsChain = Get-NeedChain $NsIndex $nsId
    # ToArray, not @(): Windows PowerShell 5.1 throws 'Argument types do not match' wrapping this list.
    $nsLinks = $nsChain.Phases.ToArray()
    if ($nsChain.Missing -or $nsLinks.Count -eq 0) {
        $nsOut.Kind = 'missing'
        if ($nsLinks.Count -gt 0) { $nsOut.Text = "$nsId, handed over to $($nsChain.Missing)" }
        return $nsOut
    }
    $nsText = (@($nsLinks | ForEach-Object { [string]$_.id })) -join ', handed over to '
    $nsLast = $nsLinks[$nsLinks.Count - 1]
    $nsLastSt = [string](Get-Prop $nsLast 'stage' '')
    if ($nsLastSt -eq 'delivered') { $nsOut.Kind = 'met'; return $nsOut }
    if ($nsLastSt -eq 'abandoned') { $nsOut.Kind = 'never'; $nsOut.Text = $nsText; return $nsOut }
    foreach ($nsP in $nsLinks) {
        if ($nsAt -gt 0 -and (Get-SpTicks (Get-Prop $nsP 'revisedAt' $null)) -gt $nsAt) { $nsOut.Revised = $true }
    }
    $nsOwn = ''
    if ($nsShared -and (Get-Prop $nsLast 'owner' '')) { $nsOwn = ", owned by $(Get-SpPersonText $NsSlug ([string]$nsLast.owner))" }
    $nsOut.Text = "$nsText ($nsLastSt$nsOwn)"
    return $nsOut
}

function Get-HeldPhases {
    # Each phase given that has a need not met, by id: the list of { Need; State }. A phase in it is
    # never named as next.
    param($HpState, [string]$HpSlug, $HpPhases)
    $hpOut = @{}
    $hpIndex = $null
    foreach ($hpP in @($HpPhases)) {
        $hpNeeds = @(Get-Prop $hpP 'needs' @())
        if ($hpNeeds.Count -eq 0) { continue }
        if ($null -eq $hpIndex) { $hpIndex = Get-NeedIndex $HpState }
        $hpList = New-Object System.Collections.Generic.List[object]
        foreach ($hpN in $hpNeeds) {
            $hpSt = Get-NeedState $hpIndex $HpState $HpSlug $hpN
            if ($hpSt.Kind -ne 'met') { $hpList.Add([pscustomobject]@{ Need = $hpN; State = $hpSt }) }
        }
        if ($hpList.Count -gt 0) { $hpOut[[string]$hpP.id] = $hpList }
    }
    return $hpOut
}

function Get-NeedCycles {
    # The groups of unfinished phases whose needs form a cycle, each { Ids } sorted (an object, so a
    # single group cannot unroll into its ids on the way out). Only a
    # merge makes one: a single writer is refused at 90.
    param($NyState)
    $nyIndex = Get-NeedIndex $NyState
    $nyStarts = @(@(Get-Phases $NyState) | Where-Object { @(Get-NeedIds $_).Count -gt 0 -and -not (Test-NeedFinished $_) })
    if ($nyStarts.Count -eq 0) { return @() }
    $nyReach = @{}
    foreach ($nyS in $nyStarts) {
        $nySeen = @{}
        $nyQueue = New-Object System.Collections.Generic.Queue[string]
        $nyQueue.Enqueue([string]$nyS.id)
        while ($nyQueue.Count -gt 0) {
            $nyP = $nyIndex.Phase[$nyQueue.Dequeue()]
            if ($null -eq $nyP -or (Test-NeedFinished $nyP)) { continue }
            foreach ($nyNeed in @(Get-NeedIds $nyP)) {
                foreach ($nyT in @(Get-NeedTargets $nyIndex $nyNeed '' '')) {
                    if ($nySeen.ContainsKey($nyT)) { continue }
                    $nySeen[$nyT] = $true
                    $nyQueue.Enqueue($nyT)
                }
            }
        }
        $nyReach[[string]$nyS.id] = $nySeen
    }
    $nyGroups = [ordered]@{}
    foreach ($nyA in @($nyReach.Keys | Sort-Object)) {
        if (-not $nyReach[$nyA].ContainsKey($nyA)) { continue }
        $nyMembers = @(@($nyReach.Keys) | Where-Object { $nyReach[$nyA].ContainsKey($_) -and $nyReach[$_].ContainsKey($nyA) } | Sort-Object)
        $nyGroups[$nyMembers -join '|'] = [pscustomobject]@{ Ids = $nyMembers }
    }
    return @($nyGroups.Values)
}

function Get-RevisionSig {
    # What a revise must change for the phase or workstream to count as revised, for the warning a
    # phase needing it gets: never a prompt path, and never a need re-declared unchanged.
    param($RsObj, [string]$RsKind)
    if ($RsKind -eq 'node') { return "$(Get-Prop $RsObj 'title' '')`n$((@(Get-Prop $RsObj 'goals' @())) -join ',')" }
    $rsParts = @(
        [string](Get-Prop $RsObj 'scope' ''), [string](Get-Prop $RsObj 'actor' ''),
        ((@(Get-Prop $RsObj 'repos' @())) -join ','), [string](Get-Prop $RsObj 'due' ''),
        [string](Get-Prop $RsObj 'runOrder' -1), [string](Get-Prop $RsObj 'owner' ''),
        ((@(Get-NeedIds $RsObj)) -join ',')
    )
    return ($rsParts -join "`n")
}

# ------------------------------------------------------------------ reports --

function Get-PhaseLineExtras {
    # What a phase line adds in a project that shares its progress, for 'status' and 'tree': a
    # handed-over phase's successor after its stage, and the owner of a phase not yet finished.
    # A per-machine project gets two empty strings, so its lines are what they always were.
    param($ExP, [string]$ExSlug)
    $exOut = @{ Stage = ''; Owner = '' }
    if (-not $ExSlug -or -not (Test-SharedProgress $ExSlug)) { return $exOut }
    $exSt = [string](Get-Prop $ExP 'stage' '')
    if ($exSt -eq 'handed-over') { $exOut.Stage = " -> $(Get-Prop $ExP 'handedOverTo' '?')" }
    $exId = [string](Get-Prop $ExP 'owner' '')
    if ($exId -and @('delivered', 'abandoned', 'handed-over') -notcontains $exSt) { $exOut.Owner = "  owner: $(Get-SpPersonText $ExSlug $exId)" }
    return $exOut
}

function Format-PhaseLine {
    param($P, [string]$FlSlug = '')
    $flEx = Get-PhaseLineExtras $P $FlSlug
    $wait = ''
    if ((Get-Prop $P 'stage' '') -eq 'waiting') {
        $wait = "  waiting-on: $(Get-Prop $P 'waitingOn' '?') review: $(Get-Prop $P 'reviewOn' '?')"
    }
    $dueText = Get-Prop $P 'due' ''
    if ($dueText) { $dueText = "  due: $dueText" }
    $ro = Get-Prop $P 'runOrder' -1
    $roText = if ($ro -lt 0) { 'NO-ORDER' } else { "#$ro" }
    return ("  {0,-9} {1,-9} {2,-9} {3,-15}{4}{5}{6}" -f $P.id, $roText, (Get-Prop $P 'actor' '?'), ([string](Get-Prop $P 'stage' '?') + $flEx.Stage), $dueText, $wait, $flEx.Owner)
}

function Get-Signals {
    param([string]$Slug, [string]$FilterKind)
    if (-not (Test-Path -LiteralPath $SignalsHome)) { return @() }
    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $SignalsHome -Filter 'S*.json' -File -ErrorAction SilentlyContinue)) {
        try { $s = Read-Json $f.FullName } catch { continue }
        if ($Slug        -and $s.project -ne $Slug) { continue }
        if ($FilterKind  -and $s.kind    -ne $FilterKind) { continue }
        $out += $s
    }
    return @($out | Sort-Object -Property id)
}

# THE ONE IMPLEMENTATION OF 'DUE', 'SCHEDULED' AND 'UNSCHEDULED'. Both the row suffix and the
# two counts in the 'signals' listing call this, and
# scripts/keel-session-start.ps1 asks that verb for the answer rather than re-deriving the
# dates. A second copy of a selection rule is the duplication charter P10 forbids, and
# nothing mechanical would catch one - which is why the rule is stated here, at the single
# implementation, rather than in the two places that would have carried the copies.
#
# THIS RETURNS A READING AND WRITES NOTHING, and no caller may turn it into a terminal
# verdict. A date arriving RE-RAISES a signal; it never resolves one. That is the constraint
# the whole mechanism is shaped by: a design that lets elapsed time END a signal is a failed
# design. Nothing below reaches state, resolvedAs, resolution or resolvedAt.
#
# AN UNPARSEABLE STORED DATE READS AS 'scheduled', NEVER 'due'. Assert-Date refuses one on
# the way in, but a reader does not assume the writer, and the conservative direction is the
# one that cannot fabricate a due date out of a garbled field. It must also not THROW: this
# runs inside a listing verb, where an exception would take out every row.
function Get-ReviewState {
    param($Judgement, [datetime]$Today)
    $on = Get-Prop $Judgement 'reviewOn' ''
    if ($on -ne '') {
        $parsed = $null
        try { $parsed = [datetime]::ParseExact($on, 'yyyy-MM-dd', $null) } catch { return 'scheduled' }
        if ($parsed -le $Today) { return 'due' }
        return 'scheduled'
    }
    if ((Get-Prop $Judgement 'as' '') -eq 'DEPRIORITISED') { return 'unscheduled' }
    return ''
}

# PER SIGNAL, ON THE LAST JUDGEMENT, and both halves are load-bearing. The trail is
# append-ordered, so the most recent verdict is the operative one: a signal deprioritised
# without a date and later re-judged WITH one is scheduled, not unscheduled. Counting per
# JUDGEMENT instead would leave the superseded dateless entry standing, so a signal that had
# been re-judged with a date would still be counted unscheduled. The two methods diverge for
# every signal re-judged after a dateless deferral, which is how the mechanism is used rather
# than an edge case of it.
#
# NO COUNT OF THE STORE BELONGS IN THIS COMMENT. A count stated here, or a claim that the two
# methods give the same answer, goes false at the next re-judgement and nothing mechanical
# reads it. What holds this function to the LAST
# judgement is row P25 of scripts/test-signal-judgement.ps1, which fails if the index below
# moves to the first.
#
# A CONSEQUENCE WORTH MEETING HERE RATHER THAN IN A LISTING: the row suffix is per
# judgement while this count is per signal, so a signal re-judged with a date still shows
# its OLD row reading UNSCHEDULED while this reports it scheduled. That is correct. The
# trail is a history and the count is a current reading, and erasing the first would hide
# exactly what the trail exists to keep.
function Get-SignalReviewState {
    param($Signal, [datetime]$Today)
    $jgs = @(Get-Prop $Signal 'judgements' @())
    if ($jgs.Count -eq 0) { return '' }
    return (Get-ReviewState -Judgement $jgs[$jgs.Count - 1] -Today $Today)
}

# --------------------------------------------------- signals leave the machine --
# A signal is the ONE artifact that crosses machines (charter P26). Everything below
# supports that crossing, and every one of them is refusable rather than advisory.

# Quarantine projects file evidence BY REFERENCE ONLY. Pasted command output is
# almost always multi-line or long; a reference is a path plus a short description.
# This is a heuristic, but it is an EXIT CODE rather than a warning, because the
# thing it guards has no undo once pushed.
$EvidenceRefMaxChars = 240

function Read-ProjectConfig {
    param([string]$ConfigPath)
    try { return (Read-Json $ConfigPath) } catch { return $null }
}

# gh writes progress and even SUCCESS messages to stderr. Under
# $ErrorActionPreference = 'Stop', a 2>&1 redirect turns those into terminating
# errors, so a call that worked reports as a crash and the success line never runs:
# `gh issue close` closes the issue AND produces a NativeCommandError. Native calls go
# through here so the EXIT CODE decides.
#
# AND gh RETURNS UTF-8, WHICH POWERSHELL DOES NOT DECODE AS UTF-8 BY DEFAULT. Windows
# PowerShell decodes a native command's stdout using [Console]::OutputEncoding, which under
# `powershell.exe -NoProfile` can be codepage 437 - on the machine measured,
# `[Console]::OutputEncoding.CodePage` returned 437. So an em dash arrives as three CP437
# characters and is then PERSISTED that way. Nothing raises: the call exits 0, the success
# line prints, and `signals` renders the row correctly because the same console re-encodes
# CP437 symmetrically on the way out - so the corruption is invisible on the machine that
# caused it and visible everywhere else.
#
# Reproduced directly: gh's own output for an issue title holding ONE `e2 80 94` produced a
# record holding ZERO, and TWO `ce 93 c3 87 c3 b6` - `e2 80 94` decoded as CP437 and
# re-encoded as UTF-8. A wrong answer that raises nothing, at the point where text is
# written down for good.
#
# Set here rather than in the one verb that exposed it, for the same reason the
# ErrorActionPreference dance is here: this is the single door every native call goes
# through, and the next verb to read free text from gh should not have to rediscover this.
# Restored in the finally, and both halves are guarded - [Console]::OutputEncoding throws
# where there is no console, and a wrapper that dies on that would be worse than the bug.
#
# TWO OPTIONAL SETTINGS, off by default, so every call written before them behaves
# exactly as it did:
#   -NativeInput       lines piped to the command's stdin. PowerShell encodes a pipe into a
#                      native command with $OutputEncoding, which was us-ascii under
#                      powershell.exe -NoProfile where measured, so it is set to UTF-8 for the call:
#                      'git hash-object --stdin-paths' given a non-ASCII path exits 128
#                      under us-ascii and returns the right blob id under UTF-8.
#                      [Console]::InputEncoding is set as well: the writer on the pipe is
#                      built from it, and at an inherited console input code page of 65001
#                      it carries a preamble, so the first path reaches git behind a
#                      byte-order mark and git dies on line one - 'exit 128, 0 of N hashed'
#                      at every N. A child of a shell at 65001 fails with both other
#                      encodings set and hashes once this is set to UTF8Encoding($false); a
#                      child of a shell at 437 hashes either way.
#   -NativeSplitStderr stdout only in .Output and .Text, for output that is parsed as data - git's
#                      line-ending warnings would otherwise land inside a -z name list. stderr goes
#                      to .StdErr, by $_.Exception.Message because ToString() on the ErrorRecord of
#                      a blank line yields the type name. Kept rather than discarded, so a stored
#                      error can say why a call failed.
# Both live here and not in a second helper, because this is the single door every native
# call goes through.
#
# A TOOL THAT DOES NOT RESOLVE RETURNS A FAILED RESULT THAT SAYS SO, with NotFound set. Left to
# '& $Exe', a missing git raises CommandNotFoundException, which ends the script at exit 1 - a code
# the header above does not document - and drops the rest of the verb's output, so 'status' lost
# every line after the one that needed git. NotFound lets a caller name the missing tool. The check
# comes before any encoding is touched, so the early return has nothing to restore.
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments, [string[]]$NativeInput, [switch]$NativeSplitStderr)
    if ($null -eq (Get-Command $Exe -ErrorAction SilentlyContinue)) {
        $nvMissing = "$Exe was not found on PATH"
        return [pscustomobject]@{ Output = @(); Code = -1; Text = $nvMissing; StdErr = @($nvMissing); NotFound = $true }
    }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $prevEnc = $null
    try {
        $prevEnc = [Console]::OutputEncoding
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    }
    catch { $prevEnc = $null }
    # $global: and not a local: a function-local $OutputEncoding is NOT the one PowerShell
    # encodes the pipe with - with it, hash-object still exits 128 on a non-ASCII path.
    $prevPipeEnc = $global:OutputEncoding
    $prevInEnc = $null
    try {
        if ($null -ne $NativeInput) {
            $global:OutputEncoding = New-Object System.Text.UTF8Encoding($false)
            try {
                $prevInEnc = [Console]::InputEncoding
                [Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
            }
            catch { $prevInEnc = $null }
            $raw = $NativeInput | & $Exe @Arguments 2>&1
        }
        else { $raw = & $Exe @Arguments 2>&1 }
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
        $global:OutputEncoding = $prevPipeEnc
        if ($null -ne $prevInEnc) { try { [Console]::InputEncoding = $prevInEnc } catch { } }
        if ($null -ne $prevEnc) { try { [Console]::OutputEncoding = $prevEnc } catch { } }
    }
    $errText = @()
    if ($NativeSplitStderr) {
        $errText = @($raw | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { $_.Exception.Message })
        $raw = @($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    }
    $outText = @($raw | ForEach-Object { $_.ToString() })
    return [pscustomobject]@{ Output = $outText; Code = $code; Text = ($outText -join "`n"); StdErr = $errText; NotFound = $false }
}

function Test-Quarantine {
    param($Cfg)
    if ($null -eq $Cfg) { return $false }
    return [bool](Get-Prop $Cfg 'quarantine' $false)
}

# One format for a state timestamp, wherever one is written down or compared.
#
# WHY THIS EXISTS. ConvertFrom-Json does not agree with itself across hosts about what
# an ISO-8601 string in a JSON document is. With the identical input
# '{"updated":"2026-08-26T16:42:44"}': Windows PowerShell
# 5.1.26100.9278 returns System.String and interpolates 2026-08-26T16:42:44, while
# PowerShell 7.6.5 returns System.DateTime and interpolates 08/26/2026 16:42:44 - the
# host's US short format. Every skill specifies powershell.exe, so 5.1 is the normal case
# and the defect fires only under pwsh, where a handoff is written carrying the US form.
#
# Such a file is worse off than mis-ranked. The reader below captures (\S+) and then
# requires end-of-line; the US rendering contains a SPACE, so the pattern cannot match
# it at all and the file is never a candidate. The same pattern returns False
# against 'State revision: 08/26/2026 16:42:44' and True against the ISO form. So the
# file is invisible, not merely out-ranked.
#
# WHAT IT BREAKS, and why one helper rather than two inline copies. The handoff verb
# writes this value into 'State revision:', and Write-HandoffLine compares a stamp read
# back OUT of a file - always a string - against the same property read fresh. A string
# on the left coerces the right operand to string, so under pwsh the comparison is
# against the US rendering, can never equal an ISO stamp, and a current handoff reports
# STALE forever. Both sites are the same fact, so they get one home (charter P10).
function Format-StateStamp {
    param($StampValue)
    if ($null -eq $StampValue) { return '' }
    if ($StampValue -is [datetime]) { return $StampValue.ToString('yyyy-MM-ddTHH:mm:ss') }
    return [string]$StampValue
}

# Where a handoff lives. This is the ONLY wrapper write that lands inside a git repo,
# so the location is decided by the project's own declaration rather than by convention
# (charter P23): the wrapper cannot inspect whether -Next or -Detail quotes something
# identifying, and a quarantined project must not have it land in a tracked folder.
# Locals are Ho-prefixed because $Proj and $Cfg are both live names elsewhere in this
# script and a function param of the same name shadows them.
function Get-HandoffDir {
    param($HoProj, $HoCfg)
    if (Test-Quarantine $HoCfg) {
        return (Join-Path (Join-Path (Join-Path $KeelHome 'quarantine') $HoProj.Slug) 'handoffs')
    }
    return (Join-Path (Join-Path $HoProj.Root 'plan') 'handoffs')
}

# Reports commits that are present locally and absent from the remote - work that has
# never left this machine.
#
# WHY status, AND NOT THE RECORD GATE OR A HOOK. status is where every session
# resumes, it already prints an unpushed count for SIGNALS a few lines below, and the
# failure this answers is later sessions not noticing commits that were never pushed - a
# later-session detection problem that a rule addressed to the committing session does
# not reach. A hook is refused by charter P14, which caps plugin hooks at two and
# requires them to be cheap.
#
# WHY ls-remote AND NEVER refs/remotes/origin/*. The tracking ref is a cache updated by
# fetch: it reports whatever the last fetch saw, which is why it can say 'nothing to
# push' while the remote is behind. Only ls-remote asks the remote. A check of this must
# reject a cache-reading implementation: force the cache to agree with local HEAD, so
# that a wrong implementation cannot pass.
#
# WHAT ls-remote ACTUALLY DOES, measured against a local bare repository and
# through Invoke-Native, because two of these three are not what a reader expects:
#   branch present on the remote   exit 0, one line: sha TAB ref
#   branch ABSENT from the remote  exit 0, and NOTHING on stdout
#   origin path does not exist     exit 128, stderr only
# The middle row is why the empty case is handled BELOW the exit code and never folded
# into it: a zero exit does not mean there was something to compare against.
#
# THE PRINTED LINE NEVER EMBEDS $res.Text. On the failing call, Invoke-Native's
# Text carries the literal System.Management.Automation.RemoteException, because 2>&1
# yields ErrorRecords and ToString() on the ones wrapping blank stderr lines injects that
# class name. The exit code is the only thing read out of a failed call. The text also
# carries the remote URL.
#
# FOUR SILENT CASES, each for a reason, because charter P16 makes silence a success and
# a line that fires on a working repository trains the reader to skip it:
#   git: false in keel.json   not a git project; ZERO calls of any kind are made
#   no origin configured      every project measured declared git: true, and most had
#                             no origin at all. An audible line there is permanent noise
#                             about a repository working exactly as intended.
#   detached HEAD             no branch whose remote counterpart could be behind
#   no commits yet            nothing can be unpushed
# The one AUDIBLE failure is a remote that IS configured and cannot be reached. That one
# must never read as clean: fail open and say so.
#
# ONE local call answers three questions - is this a repo, does it have any commits, and
# what is HEAD - because rev-parse takes both arguments at once and exits 128 on a
# non-repo AND on a repo with no commits. symbolic-ref was the obvious choice and is
# WRONG here: it returns 'main' at exit 0 in a repository with no commits at all, so a
# flow built on it prints an unpushed claim about a repo that has never had a commit.
#
# CALL BUDGET, measured: rev-parse 83-108 ms (local) and ls-remote 1573-1784 ms - the ONLY
# network call. rev-list --count 90-110 ms runs only when the remote sha differs from local
# HEAD, and config --get only when ls-remote failed. So this code makes one local process
# plus one round trip in the clean case, and nothing here makes a second remote call.
#
# THAT IS NOT THE SAME AS FOUR PROCESSES NOT APPEARING. Measured with GIT_TRACE: against
# an https remote, one status shows FOUR git invocations - rev-parse, ls-remote, and 'git
# config --null --list' TWICE, the pair spawned by the credential helper behind ls-remote
# and not by anything above. Against a local bare repository the same trace shows two.
# Still exactly one ls-remote either way, but a reader counting processes should know
# where the other two come from.
#
# Locals carry an 'up' prefix for the reason Write-HandoffLine's carry 'Ho': PowerShell
# variable names are case-insensitive and this script's param() block declares
# [string]$Branch, so a local called $branch IS that parameter, and
# check-suite-docs.ps1 section 6 refuses the commit.
#
# THE READING IS TAKEN ONCE AND PRINTED WHERE IT BELONGS. Get-UnpushedReading does the work and
# returns the lines this has always printed, in the same order and words, so a project that keeps
# its progress on this machine prints exactly what it did. A project that shares its progress
# through its repo also needs the reverse reading - a colleague's pushed work this copy lacks - and
# 'status' prints that at the TOP, before anything a reader might act on; so the reading is taken
# there, kept in $script:UpReading, and the bottom line reuses it rather than making a second
# ls-remote. In a shared project the reading also says when it could not be taken (NotChecked),
# because silence there reads as "this copy is up to date".
$script:UpReading = $null
function Write-UnpushedCommitsLine {
    param($UpProj, $UpCfg)
    $upR = $script:UpReading
    if ($null -eq $upR) { $upR = Get-UnpushedReading $UpProj $UpCfg $false }
    foreach ($upLine in @($upR.Lines)) { Say $upLine }
}

function Get-UnpushedReading {
    param($UpProj, $UpCfg, [bool]$UpShared)
    $upOut = [pscustomobject]@{ Lines = New-Object System.Collections.Generic.List[string]; NotPulled = $null; Behind = 0; NotChecked = $null }

    if (-not (Get-Prop $UpCfg 'git' $false)) { return $upOut }

    $upRoot = $UpProj.Root

    $upRp = Invoke-Native -Exe 'git' -Arguments @('-C', $upRoot, 'rev-parse', 'HEAD', '--symbolic-full-name', 'HEAD')
    # Fail open, as for an unreachable remote, but say the reading did not happen: silence here
    # reads as "nothing unpushed".
    if ($upRp.NotFound) {
        $upOut.Lines.Add("  git NOT FOUND on PATH, so whether this project's commits have reached the remote 'origin' was NOT checked. Install Git for Windows, or put git on PATH.")
        $upOut.NotChecked = 'git not found'
        return $upOut
    }
    if ($upRp.Code -ne 0) { return $upOut }

    $upLines = @($upRp.Output | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($upLines.Count -lt 2) { return $upOut }
    $upLocalSha = $upLines[0]
    $upRef      = $upLines[1]
    if ($upRef -notlike 'refs/heads/*') {
        # Only a shared project hears about it: a detached HEAD cannot strand work on this machine,
        # but it does leave a colleague's pushed work unread. Only where there is an origin to read.
        if ($UpShared) {
            $upUrl0 = Invoke-Native -Exe 'git' -Arguments @('-C', $upRoot, 'config', '--get', 'remote.origin.url')
            if ($upUrl0.Code -eq 0) { $upOut.NotChecked = 'a detached HEAD has no branch to compare' }
        }
        return $upOut
    }
    $upBranch = $upRef.Substring('refs/heads/'.Length)

    # THE OUTWARD GUARD, site 5 of 5 - the only one that is not a gh call, and the
    # one reached from 'status', the verb every session in every project runs first.
    # Its behaviour is DERIVED under four constraints rather than designed, because
    # the guard's design was made for the four gh sites:
    #
    #   1. PLACEMENT is here, immediately before the ls-remote. There is no resolver
    #      pair to sit after, so the gh sites' ordering argument does not apply and
    #      must not be transplanted.
    #   2. SEMANTICS ARE PRESERVED: 'status' continues at exit 0 exactly as it
    #      does when ls-remote fails, and no other line of its output changes.
    #      This returns, which is what the ls-remote failure path already does.
    #   3. THE MESSAGE MUST NOT CLAIM THE REMOTE WAS UNREACHABLE. The existing
    #      "COULD NOT REACH the remote 'origin'" string asserts a reading that was
    #      attempted and failed; under the guard nothing was attempted at all, so
    #      that string must NOT appear here. A guard that lies about its own reason
    #      trains the reader to distrust it, and the same principle applies to this
    #      different false claim - which is why the assurance clause below is about the reading and
    #      not about gh, a program this site never resolves.
    #   4. IT NAMES THE COMMAND IT DECLINED, as the four gh sites do, because that
    #      is what makes the guard testable without a network at all.
    $upBlocked = Test-OutwardBlocked
    if ($null -ne $upBlocked) {
        $upOut.Lines.Add("  " + (Get-OutwardBlockedMessage -OwReason $upBlocked `
            -OwCommands @("git -C $upRoot ls-remote origin $upRef") `
            -OwAssurance 'No reading of the remote was attempted, so this says NOTHING about whether local commits have been pushed.'))
        if ($UpShared) {
            $upUrl1 = Invoke-Native -Exe 'git' -Arguments @('-C', $upRoot, 'config', '--get', 'remote.origin.url')
            if ($upUrl1.Code -eq 0) { $upOut.NotChecked = $upBlocked }
        }
        return $upOut
    }

    # GIT_TERMINAL_PROMPT=0 so a remote that wants credentials FAILS instead of blocking
    # the most-run verb in the suite on a prompt nobody is watching. Restored either way.
    # An unmeasured mitigation, stated as one: it stops git prompting on the terminal,
    # and a GUI credential helper is not something that could be provoked to test it.
    $upPrevPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        $upLs = Invoke-Native -Exe 'git' -Arguments @('-C', $upRoot, 'ls-remote', 'origin', $upRef)
    }
    finally {
        if ($null -eq $upPrevPrompt) { Remove-Item Env:\GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue }
        else { $env:GIT_TERMINAL_PROMPT = $upPrevPrompt }
    }

    if ($upLs.Code -ne 0) {
        # Only NOW is it worth asking whether there is a remote at all - the answer costs
        # a process and is needed on this path only.
        $upUrl = Invoke-Native -Exe 'git' -Arguments @('-C', $upRoot, 'config', '--get', 'remote.origin.url')
        if ($upUrl.Code -ne 0) { return $upOut }
        $upOut.Lines.Add("  COULD NOT REACH the remote 'origin' (git ls-remote exit $($upLs.Code)). This says NOTHING about whether local commits have been pushed - it is not a clean reading.")
        $upOut.NotChecked = "the remote 'origin' could not be reached"
        return $upOut
    }

    $upRemoteSha = ''
    if (-not [string]::IsNullOrWhiteSpace($upLs.Text)) { $upRemoteSha = (($upLs.Text.Trim()) -split '\s+')[0] }

    if ($upRemoteSha -eq '') {
        $upAll = Invoke-Native -Exe 'git' -Arguments @('-C', $upRoot, 'rev-list', '--count', 'HEAD')
        $upAllN = if ($upAll.Code -eq 0) { $upAll.Text.Trim() } else { 'an unknown number of' }
        $upOut.Lines.Add("  branch '$upBranch' is NOT on the remote 'origin': all $upAllN local commit(s) on it exist only on this machine.")
        return $upOut
    }

    if ($upRemoteSha -eq $upLocalSha) { return $upOut }

    $upShort = if ($upRemoteSha.Length -ge 7) { $upRemoteSha.Substring(0, 7) } else { $upRemoteSha }

    $upCount = Invoke-Native -Exe 'git' -Arguments @('-C', $upRoot, 'rev-list', '--count', "$upRemoteSha..HEAD")
    if ($upCount.Code -ne 0) {
        # The remote's sha is not in this clone. A shared project says so at the top, as work
        # this copy has not pulled, which is the reading that matters there; the line below would
        # repeat it in other words.
        if ($UpShared) { $upOut.NotPulled = "$upShort on '$upBranch'" }
        else { $upOut.Lines.Add("  the remote 'origin' holds $upShort on '$upBranch', which is not in this clone, so the unpushed count could not be computed. Fetch, then re-run.") }
        return $upOut
    }

    $upN = 0
    if (-not [int]::TryParse($upCount.Text.Trim(), [ref]$upN)) { $upN = 0 }
    if ($upN -gt 0) {
        # The RANGE and not only the count. The range is what makes charter P6's preview
        # exact for a push, and it costs nothing: the remote sha is already in hand from the
        # call that produced the count.
        $upOut.Lines.Add("  $upN commit(s) on '$upBranch' have NOT reached the remote 'origin' ($upShort..HEAD), read live from git ls-remote. They exist only on this machine.")
    }

    # The reverse count, a shared project's only: commits the remote holds that HEAD does not
    # reach, read locally, since the remote's sha is already in this clone (fetched, not merged).
    if ($UpShared) {
        $upBehind = Invoke-Native -Exe 'git' -Arguments @('-C', $upRoot, 'rev-list', '--count', "HEAD..$upRemoteSha")
        $upB = 0
        if ($upBehind.Code -eq 0 -and [int]::TryParse($upBehind.Text.Trim(), [ref]$upB)) { $upOut.Behind = $upB }
    }
    return $upOut
}

# The top of 'status' in a project that shares its progress: whether this copy lacks pushed work,
# whether the reading could be taken at all, and how many progress files here are not committed.
# Each line begins WARNING:, so keel-session-start.ps1 forwards it to a resuming session. Silent
# when there is nothing to say (charter P16).
function Write-SpRemoteLines {
    param($SrProj, $SrCfg)
    $script:UpReading = Get-UnpushedReading $SrProj $SrCfg $true
    $srR = $script:UpReading
    if ($srR.NotPulled) { Say "  WARNING: the remote 'origin' holds work this copy has not pulled ($($srR.NotPulled)). Pull before acting on what follows." }
    if ($srR.Behind -gt 0) { Say "  WARNING: this copy is $($srR.Behind) commit(s) behind 'origin'. Pull before acting on what follows." }
    if ($srR.NotChecked) { Say "  WARNING: whether this copy is behind 'origin' was NOT checked ($($srR.NotChecked)), so what follows may lack others' pushed work." }

    if (-not (Get-Prop $SrCfg 'git' $false)) { return }
    # --untracked-files=all, because plain porcelain lists a new folder as ONE path however many
    # files it holds. A file in a SUBFOLDER of a phase's artifacts folder is not counted: by the
    # layout only top-level files are artifacts, and a subfolder there can only hold scratch that
    # belongs in the per-machine phase folder. Nothing stops a commit from taking such a file, so
    # this count is not a promise that one will not be committed.
    $srSt = Invoke-Native -Exe 'git' -Arguments @('-C', $SrProj.Root, 'status', '--porcelain', '--untracked-files=all', '--', 'progress') -NativeSplitStderr
    if ($srSt.NotFound) { Say '  WARNING: whether progress files here are committed was NOT checked (git not found).'; return }
    if ($srSt.Code -ne 0) { return }
    $srN = @($srSt.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Where-Object {
        $srPath = ([string]$_).Substring([Math]::Min(3, ([string]$_).Length)).Trim('"')
        $srPath -notmatch '^progress/phases/[^/]+/artifacts/[^/]+/'
    }).Count
    if ($srN -gt 0) { Say "  WARNING: $srN progress file(s) written here are not committed, so nobody else can see them." }
}

# Reports the handoff the LAST session wrote for this one, and whether state has moved
# past it. Project-level and not attached to a phase, deliberately: the boundaries this
# repairs are the ones where there is no next phase to hang a brief on.
#
# A FUNCTION and not an inline block because 'status' has two exits - it returns early
# on a project with no phases declared, which is itself one of the boundaries this is
# for. Inline, a quarantined project with a handoff and no phases would report nothing
# at all.
function Write-HandoffLine {
    param($HoProj, $HoState)
    $hoDir = Get-HandoffDir $HoProj (Read-ProjectConfig $HoProj.ConfigPath)
    if (-not (Test-Path -LiteralPath $hoDir)) { return }
    if (Test-SharedProgress $HoProj.Slug) { Write-SpHandoffLines $HoProj $HoState $hoDir; return }

    $hoBest  = $null
    $hoStamp = ''
    foreach ($hoFile in @(Get-ChildItem -LiteralPath $hoDir -Filter '*.md' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc)) {
        $hoText = Get-Content -LiteralPath $hoFile.FullName -Raw -ErrorAction SilentlyContinue
        # An empty file reads back as nothing without throwing,
        # so the null-check comes before the match, not after.
        if ([string]::IsNullOrWhiteSpace($hoText)) { continue }
        # A file with no parseable stamp is ignored, which is what stops a hand-written
        # note being read as keel-written.
        #
        # [ \t\r]* and not [ \t]*: these files are written CRLF, and under (?m) the .NET
        # '$' anchors before the \n with the \r still unconsumed, so a class that omits
        # \r can never reach the anchor and status silently reports no handoff at all -
        # the file on disk and correct, and status printing nothing, with no error and no
        # exit code.
        if ($hoText -match '(?m)^State revision:[ \t]*(\S+)[ \t\r]*$') {
            # Stamps are ISO-8601 - Format-StateStamp above is what makes that true on
            # either host - so a string comparison IS a chronological one.
            #
            # -ge, over an enumeration ordered by LastWriteTimeUtc, so an exact tie
            # resolves to the file written LAST. A tie is not an edge case here: the
            # handoff verb deliberately writes no state, so two handoffs written in one
            # session ALWAYS carry the identical stamp, and a revised -Next derives a new
            # slug and writes a SECOND file rather than replacing the first. Enumerating
            # by Name and comparing with -gt would let a tie fall to the alphabetically
            # first name, which is the newer file only by accident.
            if ($Matches[1] -ge $hoStamp) { $hoStamp = $Matches[1]; $hoBest = $hoFile }
        }
    }
    if ($null -eq $hoBest) { return }

    $hoRel = $hoBest.FullName
    if ($hoRel.StartsWith($HoProj.Root)) { $hoRel = $hoRel.Substring($HoProj.Root.Length).TrimStart('\', '/') }
    Say "  handoff: $hoRel"

    # Derived at read time and never stored: a stored staleness flag would be the second
    # authority this check exists to catch (charter P10, P11).
    # Wording avoids the tokens scripts/keel-session-start.ps1 filters status output on.
    # That file is the pattern's one home and this comment deliberately does not copy it
    # - read the -match line there. A match here would start printing in
    # every session in the project, an unmandated behaviour change (P16).
    $hoLive = Format-StateStamp (Get-Prop $HoState 'updated' '')
    if ($hoStamp -ne $hoLive) {
        Say "           STALE - written at state revision $hoStamp; state has since moved to $hoLive."
    }
}

# A shared project's handoffs. Several people write them, from machines that may sit in different
# time zones, so the newest is chosen by INSTANT: as text, a later stamp from a zone behind this
# one sorts first. A stamp with no offset, from before the project shared its progress, is read as
# this machine's local time. The newest is named with its author, read from its Author: line; when
# this machine's person wrote a different newest one of their own, that is named too, since it is
# usually the one their next session continues. Each is STALE when the revision - the newest 'at'
# under progress/ - is a later instant than its stamp. Same wording rule as above: no token
# keel-session-start.ps1 filters on.
function Write-SpHandoffLines {
    param($HsProj, $HsState, [string]$HsDir)
    $hsLiveText = Format-StateStamp (Get-Prop $HsState 'updated' '')
    $hsLive = Get-SpInstant $hsLiveText
    $hsMe = Get-SpMe $HsProj.Slug
    $hsMeId = if ($null -ne $hsMe) { [string](Get-Prop $hsMe 'id' '') } else { '' }
    $hsBest = $null
    $hsMine = $null
    foreach ($hsFile in @(Get-ChildItem -LiteralPath $HsDir -Filter '*.md' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc)) {
        $hsText = Get-Content -LiteralPath $hsFile.FullName -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($hsText)) { continue }
        if ($hsText -notmatch '(?m)^State revision:[ \t]*(\S+)[ \t\r]*$') { continue }
        $hsStamp = $Matches[1]
        $hsI = Get-SpInstant $hsStamp
        if ($null -eq $hsI) { continue }
        $hsAName = ''
        $hsAId = ''
        if ($hsText -match '(?m)^Author:[ \t]*(.*?)[ \t]*\((p-[0-9a-f]{4})\)[ \t\r]*$') { $hsAName = $Matches[1]; $hsAId = $Matches[2] }
        $hsEntry = [pscustomobject]@{ File = $hsFile; Stamp = $hsStamp; I = $hsI; AName = $hsAName; AId = $hsAId }
        # -ge over files ordered by write time, so a tie goes to the file written last, as above.
        if ($null -eq $hsBest -or $hsI -ge $hsBest.I) { $hsBest = $hsEntry }
        if ($hsMeId -and $hsAId -ceq $hsMeId -and ($null -eq $hsMine -or $hsI -ge $hsMine.I)) { $hsMine = $hsEntry }
    }
    if ($null -eq $hsBest) { return }

    # The leading comma keeps each row a pair: @(@(a, b)) would flatten into two rows.
    $hsRows = @(, @('handoff', $hsBest))
    if ($null -ne $hsMine -and $hsMine.File.FullName -ne $hsBest.File.FullName) { $hsRows += , @('your last handoff', $hsMine) }
    foreach ($hsRow in $hsRows) {
        $hsE = $hsRow[1]
        $hsRel = $hsE.File.FullName
        if ($hsRel.StartsWith($HsProj.Root)) { $hsRel = $hsRel.Substring($HsProj.Root.Length).TrimStart('\', '/') }
        $hsBy = if ($hsE.AId) { "  (by $($hsE.AName), $($hsE.AId))" } else { '  (author not recorded)' }
        if ($hsRow[0] -eq 'handoff') { Say "  handoff: $hsRel$hsBy" } else { Say "  your last handoff: $hsRel" }
        if ($null -ne $hsLive -and $hsLive -gt $hsE.I) {
            Say "           STALE - written at state revision $($hsE.Stamp); state has since moved to $hsLiveText."
        }
    }
}

# gh can be installed at "C:\Program Files\GitHub CLI\gh.exe" without being on PATH.
# Resolving by PATH alone would then report it missing.
function Resolve-Gh {
    $cmd = Get-Command 'gh' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
        (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI\gh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
    )) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

# ---------------------------------------------------------------------------
# THE OUTWARD-ACT GUARD.
#
# A fixture that overrides $env:USERPROFILE into the temp directory sandboxes
# STATE - $KeelHome is built from USERPROFILE at the top of this file, so state,
# signals and quarantine all move together - and sandboxes NOTHING ELSE. A remote
# slug derived from $PSScriptRoot would be the REAL checkout's, so a scratch-home run
# would reach the real keel repository. The destination is therefore
# $SignalsTargetFile, under $KeelHome, so a scratch home has none unless its fixture
# sets one, and with none nothing is sent. The guard stays: a fixture that DOES set a
# destination is still a sandboxed run. An AST parse of this whole file finds FIVE
# process invocations across FOUR verbs that leave this machine - the four gh calls in
# signals-push, adopt-signal and resolve-signal -CloseIssue (two of them), and
# the git ls-remote in Get-UnpushedReading reached from 'status'. 'gh'
# never appears as a command name here, because Invoke-Native applies the call
# operator to a variable, so a name-based search cannot enumerate this surface.
#
# THE DETECTION RULE HAS ONE HOME (charter P10). This function is it; the five
# call sites ask it and report what it says. A run is sandboxed when $KeelHome
# resolves inside $env:TEMP, compared as FULL paths, ordinal and
# case-insensitive. On a default Windows install TEMP is <USERPROFILE>\AppData\Local\Temp,
# so the real <USERPROFILE>\.keel resolves OUTSIDE TEMP and this returns $null for
# every ordinary session. The containment
# runs one way only - TEMP is inside USERPROFILE, never the reverse.
#
# THE OVERRIDE IS ONE VARIABLE WITH THREE STATES, not two variables (P12):
#   absent  - automatic; the containment test decides
#   allow   - outward acts permitted wherever the state home resolves
#   block   - outward acts refused wherever the state home resolves
# Any other value is treated as absent and SAID SO on stderr rather than guessed
# at. KEEL_OUTWARD is read and never written, so it needs none of the
# save-and-restore GIT_TERMINAL_PROMPT gets in Get-UnpushedReading.
#
# IT FAILS OPEN IF TEMP CANNOT BE RESOLVED, and that is deliberate but is the
# weakest point here, so it is stated rather than buried: with no readable TEMP
# there is no containment test to run, and refusing every outward act on a
# machine whose TEMP is unset would break ordinary use to defend a fixture.
# KEEL_OUTWARD=block is always available and is checked BEFORE this path.
#
# WHERE THE CALLS SIT, and it is easy to get backwards. Each gh site calls this
# AFTER Resolve-Gh and Get-SignalsDestination have both succeeded. Placed before
# them, the message could not truthfully say gh was found, and the guarded path
# would be indistinguishable - to a reader AND to a test - from the genuinely
# unresolvable one, which is exactly what a test asserting that message's absence
# needs in order to be able to fire at all.
#
# signals-push is the one site that goes further down, and for the opposite
# reason: its guard sits AFTER the preview branch's exit 0. A preview makes no
# outward call, and this guard may change only WHY the outward half is skipped,
# never WHETHER the verb proceeds. Guarding at the pre-flight would flip a
# local-only path from proceed-at-0 to refuse-at-90.
#
# A GUARD INSIDE Invoke-Native IS REJECTED, on a measurement and not on taste:
# signals-push -Apply does not Fail 90 on a gh error, it prints 'gh exited <n>',
# continues the loop and exits 99 - so a guard there would change that verb's
# exit code AND put the words 'gh exited' in front of a reader when gh never
# ran, which is the same false statement the guard's own message is written to
# avoid, arriving by another route. A backstop there IN ADDITION to these five is
# rejected under P13: a second enforcement mechanism for one rule, with no cited
# failure behind it. What would make it correct is a cited instance of a sixth
# outward call site being added to this wrapper without the guard.
function Test-OutwardBlocked {
    $owOverride = $env:KEEL_OUTWARD
    if (-not [string]::IsNullOrWhiteSpace($owOverride)) {
        $owTrimmed = $owOverride.Trim()
        if ($owTrimmed -eq 'allow') { return $null }
        if ($owTrimmed -eq 'block') { return "KEEL_OUTWARD is set to 'block'" }
        [Console]::Error.WriteLine("KEEL-STATE: KEEL_OUTWARD='$owTrimmed' is neither 'allow' nor 'block'; ignoring it and deciding automatically.")
    }

    if ([string]::IsNullOrWhiteSpace($env:TEMP)) { return $null }

    $owHome = ''
    $owTemp = ''
    try {
        $owHome = [System.IO.Path]::GetFullPath($KeelHome)
        $owTemp = [System.IO.Path]::GetFullPath($env:TEMP)
    }
    catch {
        return $null
    }

    $owTempTrim = $owTemp.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $owPrefix   = $owTempTrim + [System.IO.Path]::DirectorySeparatorChar
    if ($owHome.StartsWith($owPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "this run's state home resolves inside the temp directory, so it is treated as a sandboxed run"
    }
    return $null
}

# The message has one home too, for the same reason the rule does: four call
# sites wording the same refusal four ways is how three of them drift.
#
# THREE THINGS EVERY MESSAGE CARRIES, and each earns its place. The GUARD as the
# reason, in the first clause, because a guard that lies about its own
# reason trains the reader to distrust it. An explicit denial of the nearest
# WRONG cause, which is what $OwAssurance carries: a reader who has just been
# refused reaches for the nearest explanation, and at the gh sites that is 'gh is
# missing' while at site 5 it is 'the remote is down'. Both are false under the
# guard, and both have an existing string in this file that says them. And the
# LITERAL COMMAND that would have run, which is what makes the guard testable at
# all - the suite reads the message rather than watching the network.
#
# $OwAssurance differs by site and MUST: site 5 resolves neither gh nor a slug,
# so the gh sites' 'gh WAS found and a destination WAS chosen' would itself be a
# false claim there. That is the same principle pointed at a different
# false statement.
function Get-OutwardBlockedMessage {
    param([string]$OwReason, [string[]]$OwCommands, [string]$OwAssurance)

    $owList = @($OwCommands) -join ', then '
    return "Outward acts are blocked: $OwReason. $OwAssurance Would have run: $owList. Set KEEL_OUTWARD=allow to permit outward acts from this state home."
}

# WHERE A SIGNAL IS SENT (charter P26).
#
# The destination is ONLY what a person chose: -Repo on one call, or the value stored by
# 'signals-target'. Taken from the 'origin' of the checkout this wrapper sits in, it would,
# once keel is public, publish the project name, machine name and written detail of anyone
# who cloned it and pushed a report on the public repo. With neither there is no
# destination and nothing is sent. This function never runs git and never reads 'origin' -
# do not add a fallback here, it is exactly the plausible wrong implementation to avoid.
$NoDestinationText = 'No report destination is chosen, so nothing was sent. Choose one with: keel-state.ps1 signals-target -Repo owner/name (or pass -Repo owner/name on this call).'

# owner: 1-39 letters, digits or hyphens, not starting with a hyphen. name: letters, digits,
# '.', '_' or '-', and never '.' or '..' alone.
function Test-RepoSlug {
    param([string]$SlugText)
    if ([string]::IsNullOrWhiteSpace($SlugText)) { return $false }
    if ($SlugText -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}/([A-Za-z0-9._-]{1,100})$') { return $false }
    $slugName = $Matches[1]
    if ($slugName -eq '.' -or $slugName -eq '..') { return $false }
    return $true
}

# '' for a missing, empty or unreadable file. Get-Content -Raw on a zero-byte file returns
# $null without throwing, and 'status' reads this every session, so a
# truncated file must read as no destination rather than crash the most-run verb.
function Read-SignalsTargetRaw {
    if (-not (Test-Path -LiteralPath $SignalsTargetFile -PathType Leaf)) { return '' }
    $stRaw = $null
    try { $stRaw = Get-Content -Raw -LiteralPath $SignalsTargetFile } catch { return '' }
    if ($null -eq $stRaw) { return '' }
    return ([string]$stRaw).Trim()
}

function Get-SignalsDestination {
    if (-not [string]::IsNullOrWhiteSpace($Repo)) { return $Repo.Trim() }
    $stValue = Read-SignalsTargetRaw
    if (Test-RepoSlug $stValue) { return $stValue }
    return $null
}

# Removes a temp file and CANNOT throw. Both outward sites write the local record of an
# issue BEFORE the cleanup: a cleanup between the POST and the record write that throws -
# an 8.3 short path has done it - loses the record of an issue that already exists. So the
# record is written first, and the cleanup goes through here: a leaked temp file is a
# smaller harm than an unrecorded issue.
function Remove-KeelTempFile {
    param([string]$RtPath)
    try {
        if (Test-Path -LiteralPath $RtPath) { Remove-Item -LiteralPath $RtPath -Force -ErrorAction Stop }
    }
    catch {
        [Console]::Error.WriteLine("KEEL-STATE: could not remove temp file '$RtPath' ($($_.Exception.Message)). It is harmless; delete it by hand.")
    }
}

# The preview and -Apply build the title the same way: a preview printing the raw detail
# while -Apply truncates to 240 would show, as the last check before content leaves the
# machine, something the act does not produce. ONE builder, called by both branches, so
# they cannot diverge (P6, P10).
$IssueTitleMaxChars = 240

function Format-IssueTitle {
    param($Sig)
    $t = "[signal:$($Sig.kind)] $($Sig.detail)"
    if ($t.Length -gt $IssueTitleMaxChars) { $t = $t.Substring(0, $IssueTitleMaxChars - 3) + '...' }
    return $t
}

function Format-IssueBody {
    param($Sig)
    $lines = @()
    $lines += "**Signal $($Sig.id)** filed from project ``$($Sig.project)``, phase ``$($Sig.phase)``."
    $lines += ''
    $lines += "| | |"
    $lines += "|---|---|"
    $lines += "| Kind | ``$($Sig.kind)`` |"
    $lines += "| Filed | $($Sig.created) |"
    $lines += "| Machine | $(Get-Prop $Sig 'machine' 'unknown') |"
    $lines += "| keel version | $(Get-Prop $Sig 'keelVersion' 'unknown') |"
    $lines += "| Evidence mode | $(Get-Prop $Sig 'evidenceMode' 'literal') |"
    $lines += ''
    $lines += '### What happened'
    $lines += ''
    $lines += $Sig.detail
    $lines += ''
    $lines += '### Evidence'
    $lines += ''
    $lines += '```'
    $lines += $Sig.evidence
    $lines += '```'
    $lines += ''
    $lines += '---'
    $lines += ''
    $lines += 'Filed by `keel-state.ps1`. A signal is a REPORT, not a change (charter P25): promotion is'
    $lines += 'decided in keel with the other projects in view. `unsafe` and `refusal` act at n=1;'
    $lines += '`gap` and `friction` wait for a second project or an argued exception.'
    return ($lines -join "`n")
}

function Next-SignalId {
    Ensure-Dir $SignalsHome | Out-Null
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $SignalsHome -Filter 'S*.json' -File -ErrorAction SilentlyContinue)) {
        if ($f.BaseName -match '^S(\d+)$') { $v = [int]$Matches[1]; if ($v -gt $n) { $n = $v } }
    }
    return ('S{0:D4}' -f ($n + 1))
}

# A new signal takes its id by MOVING a fully written record onto S<n>.json. A move onto a name
# that exists throws and leaves that file alone, so two filings at once cannot take one id, and
# no reader ever sees an empty or half-written signal file. The temporary name does not match
# S*.json. The record holds its own id and later writers build its path from that field, so the
# id is set again on every try. Returns the id taken.
function Save-NewSignal {
    param($SigObj)
    Ensure-Dir $SignalsHome | Out-Null
    for ($nsTry = 0; $nsTry -lt 50; $nsTry++) {
        $nsId = Next-SignalId
        Set-Prop $SigObj 'id' $nsId
        $nsTmp = Join-Path $SignalsHome ('.new-' + [guid]::NewGuid().ToString('N') + '.tmp')
        Write-Json $nsTmp $SigObj
        try {
            [System.IO.File]::Move($nsTmp, (Join-Path $SignalsHome "$nsId.json"))
            $script:WrittenList.Add("$nsId.json")
            return $nsId
        }
        catch [System.IO.IOException] {
            Remove-Item -LiteralPath $nsTmp -Force -ErrorAction SilentlyContinue
        }
    }
    Fail 89 "Fifty signal ids in a row were taken by other filings while this one was being written. $(Get-WrittenNote) Re-run the command."
}

# ===================================================================== main ==

if ([string]::IsNullOrWhiteSpace($Command)) {
    Write-Output "keel-state.ps1 - the only writer of keel project state."
    Write-Output ""
    Write-Output "  Project:    init-project  resolve  status  tree  list  goal-coverage"
    Write-Output "              ack-keel-version  handoff  share-progress  join"
    Write-Output "  Repos:      add-repo  repos"
    Write-Output "  Structure:  add-goal  set-goal-status  add-epic  add-workstream  add-phase"
    Write-Output "              revise-epic  revise-workstream  revise-phase"
    Write-Output "  Execution:  set-stage  set-waiting  clear-waiting  record-verdict"
    Write-Output "              new-iteration  lift-cap  note-friction  open-question  abandon  hand-over"
    Write-Output "              close"
    Write-Output "  Signals:    signal  signals  signals-target  signals-push  adopt-signal  judge-signal"
    Write-Output "              resolve-signal"
    Write-Output ""
    Write-Output "  'revise-phase -Correction' appends a dated note to a DELIVERED phase; its scope stays."
    Write-Output "  'add-phase -Needs <ids>' and 'revise-phase -Needs <ids|none>' declare the phases (W4.2) or"
    Write-Output "  workstreams (W4) a phase needs delivered first; status names it next only once they are."
    Write-Output "  'abandon -Ws' records a workstream that never ran, with a reason. It is one-way."
    Write-Output ""
    Write-Output "  A verify PASS or INCONCLUSIVE records a fingerprint of what it verified. The human,"
    Write-Output "  enact and record gates, and 'status', WARN when it has moved - they never refuse."
    Write-Output ""
    Write-Output "  A signal is local until 'signals-push' (preview) and 'signals-push -Apply' (creates"
    Write-Output "  GitHub issues on the repo chosen with 'signals-target -Repo owner/name', stored in"
    Write-Output "  ~/.keel/signals-target.txt). With none chosen NOTHING is sent and signals stay on"
    Write-Output "  this machine; -Repo owner/name overrides for one call. 'signals-target' alone prints"
    Write-Output "  the choice and -Clear removes it. Quarantined projects may file evidence BY REFERENCE"
    Write-Output "  ONLY - a path plus a short description, never pasted content."
    Write-Output "  'adopt-signal' is the return half: it brings an issue filed by ANOTHER keel instance"
    Write-Output "  into this machine's store, so 'signals' and 'resolve-signal' work on it unchanged."
    Write-Output "  'lift-cap' raises ONE phase's iteration cap on the operator's own words; the default"
    Write-Output "  cap is $IterationCap and nothing else changes it."
    Write-Output ""
    Write-Output "  'share-progress' moves a project's progress from this machine into its repo, under"
    Write-Output "  progress/, once; it commits nothing. 'join' registers this machine as a person in such"
    Write-Output "  a project, -As <person id> as one already listed, -As <id> -Clear to take it off one."
    Write-Output "  There every phase has one owner (add-phase -Owner, default you; revise-phase -Owner while"
    Write-Output "  planned), and anyone else's work on it exits 88. 'hand-over -Phase X -To <person id>"
    Write-Output "  -Detail <why>' ends a started phase and creates its successor (Xb) for that person."
    exit 0
}

# A per-call -Repo is shape-checked BEFORE any verb runs. Only the signal
# verbs read it, and resolve-signal writes its local resolution before it reaches GitHub, so a
# check inside Get-SignalsDestination would refuse after a write. 'signals-target' keeps its own
# message, and an empty -Repo still means "not given" everywhere else.
if ($Command -ne 'signals-target' -and -not [string]::IsNullOrWhiteSpace($Repo) -and -not (Test-RepoSlug $Repo.Trim())) {
    Fail 90 "-Repo '$Repo' is not owner/name (for example octo-org/keel-reports). Nothing was written and nothing was sent."
}

# The finally lets go of every write lock on every way out, exit and Fail included: PowerShell runs
# it when a script exits from inside the try, and keeps the exit code.
try {
switch ($Command) {

# --------------------------------------------------------------------------- #
'init-project' {
    Require-Param $Title 'Title'

    $root = $Path
    if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $root)) { Fail 90 "-Path '$root' does not exist." }
    $root = (Resolve-Path -LiteralPath $root).Path
    $slug = Split-Path -Leaf $root

    # Before the existence check, so a second init-project of the same folder waits and then
    # meets the file the first one wrote.
    Enter-WriteLock (Get-StatePath $slug) "project '$slug'"
    $cfgPath = Join-Path $root 'keel.json'
    if (Test-Path -LiteralPath $cfgPath) {
        Fail 90 "'$cfgPath' already exists. A project is initialised once; edit the file to change its settings."
    }

    # A project inside a project would make P20's upward walk ambiguous.
    $outer = Resolve-Project -StartPath (Split-Path -Parent $root)
    if ($null -ne $outer) {
        Fail 93 "'$($outer.Root)' is already a keel project, so this folder would nest inside it. Projects are siblings, never nested (charter P20)."
    }

    $trackerKind = if ([string]::IsNullOrWhiteSpace($Tracker)) { 'none' } else { $Tracker.ToLower() }
    Assert-Enum $trackerKind $TrackerKinds 'Tracker'

    $version = Get-KeelVersion

    $cfg = [pscustomobject]@{
        '$schema'    = 'keel/project'
        name         = $slug
        title        = $Title
        created      = (Today)
        git          = (-not $NoGit.IsPresent)
        tracker      = [pscustomobject]@{ kind = $trackerKind; ref = $null }
        quarantine   = $Quarantine.IsPresent
        repos        = [pscustomobject]@{}
        keelVersion  = $version
    }
    Write-Json $cfgPath $cfg

    $state = [pscustomobject]@{
        schema         = 1
        project        = $slug
        root           = $root
        title          = $Title
        created        = (Now)
        updated        = (Now)
        plannedUnder   = $version
        # Retained for state-shape stability and written by no other verb. NOTHING
        # PRINTS IT - see the 'list' row for why. Do not add a reader for it without
        # first adding a writer that can give it a second value; a field with one
        # possible value read out loud is a reader that looks like it varies and
        # cannot.
        status         = 'active'
        goals          = @()
        nodes          = @()
        phases         = @()
    }
    Write-State $slug $state

    if ($Quarantine.IsPresent) { Ensure-Dir (Join-Path (Join-Path $KeelHome 'quarantine') $slug) | Out-Null }

    Say "Initialised project '$slug' at '$root'."
    Say "  config: $cfgPath"
    Say "  state:  $(Get-StatePath $slug)"
    Say "  tracker: $trackerKind   git: $(-not $NoGit.IsPresent)   quarantine: $($Quarantine.IsPresent)"
    Say "Next: add-goal for each goal, then add-epic / add-workstream / add-phase."
    exit 0
}

# --------------------------------------------------------------------------- #
# Repos. A project may span several, and they do NOT all have to live inside the
# project folder: a repo that already exists elsewhere (with its own remote, CI and
# tooling) is referenced where it is, never moved or copied.
'add-repo' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Name 'Name'
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        Fail 90 "-Name '$Name' is not a usable repo name. It becomes part of 'changes-<name>.patch', so keep it to letters, digits, dot, dash and underscore."
    }
    Require-Param $RepoPath 'RepoPath'

    # keel.json shares its project's lock with state.json.
    Enter-WriteLock (Get-StatePath $proj.Slug) "project '$($proj.Slug)'"
    Save-ReadSha $proj.ConfigPath
    $cfg = Read-ProjectConfig $proj.ConfigPath
    if ($null -eq $cfg) { Fail 90 "Could not read '$($proj.ConfigPath)'." }

    $repoReg = Get-Prop $cfg 'repos' $null
    if ($null -eq $repoReg) { $repoReg = [pscustomobject]@{}; Set-Prop $cfg 'repos' $repoReg }
    if ($null -ne $repoReg.PSObject.Properties[$Name]) {
        Fail 90 "Repo '$Name' is already declared in keel.json. Edit that file to change it."
    }

    $resolved = $RepoPath
    if (-not [System.IO.Path]::IsPathRooted($RepoPath)) { $resolved = Join-Path $proj.Root $RepoPath }

    if (-not (Test-Path -LiteralPath $resolved)) {
        Fail 94 "'$resolved' does not exist. Declare a repo that is on disk - a declared repo with no path is a phase that cannot produce its patch."
    }

    # A relative path inside the project is the common case. An absolute path, or a relative
    # one that climbs out of the project, points at a repo this project references but does
    # not own. The separator is load-bearing: without it '../proj-old' reads as inside
    # a project at '...\proj'. This sets what add-repo writes; 'repos' reads the stored flag,
    # so a repo already declared keeps its label.
    $external = [System.IO.Path]::IsPathRooted($RepoPath)
    if (-not $external) {
        $rootFull = [System.IO.Path]::GetFullPath($proj.Root).TrimEnd('\')
        $repoFull = [System.IO.Path]::GetFullPath($resolved).TrimEnd('\')
        $external = -not (($repoFull -ieq $rootFull) -or $repoFull.StartsWith("$rootFull\", [System.StringComparison]::OrdinalIgnoreCase))
    }

    Set-Prop $repoReg $Name ([pscustomobject]@{
        path     = $RepoPath
        branch   = $(if ($Branch) { $Branch } else { $null })
        external = $external
        note     = $(if ($Detail) { $Detail } else { $null })
    })
    Write-GuardedJson $proj.ConfigPath $cfg

    Say "Declared repo '$Name' -> $resolved$(if ($external) { '  [EXTERNAL - referenced, not owned]' } else { '' })"
    if ($external) {
        Say '  Keel does not own this repo. It is never moved, and nothing is written to it without a preview.'
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'repos' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    $cfg  = Read-ProjectConfig $proj.ConfigPath
    $repoReg = Get-Prop $cfg 'repos' $null
    $names = @()
    if ($null -ne $repoReg) { $names = @($repoReg.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) }

    if ($names.Count -eq 0) {
        Say "No repos declared for '$($proj.Slug)'. Declare one with: add-repo -Name <n> -RepoPath <relative-or-absolute>"
        exit 0
    }

    Say "$($names.Count) repo(s) declared for '$($proj.Slug)'. Measured now, not recalled:"
    $problems = 0
    foreach ($n in $names) {
        $r = $repoReg.$n
        $declared = Get-Prop $r 'path' ''
        $resolved = $declared
        if (-not [System.IO.Path]::IsPathRooted($declared)) { $resolved = Join-Path $proj.Root $declared }

        $exists = Test-Path -LiteralPath $resolved
        $isGit  = $exists -and (Test-Path -LiteralPath (Join-Path $resolved '.git'))
        # symbolic-ref, not rev-parse --abbrev-ref: the latter FAILS on a repo with no
        # commits yet, which would make this report nothing at all rather than saying it
        # could not tell. A branch check that goes quiet is worse than one that says "unknown".
        $actual = ''
        $rpGitMissing = $false
        if ($isGit) {
            $res = Invoke-Native -Exe 'git' -Arguments @('-C', $resolved, 'symbolic-ref', '--short', 'HEAD')
            if ($res.NotFound) { $rpGitMissing = $true }
            elseif ($res.Code -eq 0) { $actual = $res.Text.Trim() }
            else {
                $det = Invoke-Native -Exe 'git' -Arguments @('-C', $resolved, 'rev-parse', '--short', 'HEAD')
                $actual = if ($det.Code -eq 0) { 'DETACHED at ' + $det.Text.Trim() } else { 'unknown' }
            }
        }
        $want = Get-Prop $r 'branch' ''
        $tag  = if ((Get-Prop $r 'external' $false)) { 'EXTERNAL' } else { 'in-project' }

        Write-Output ("  {0,-18} {1,-11} {2}" -f $n, $tag, $resolved)
        if (-not $exists) { Write-Output "                     MISSING - the path does not exist"; $problems++ }
        elseif (-not $isGit) { Write-Output "                     not a git repo (no .git)"; $problems++ }
        # Before the mismatch arm, so a declared branch is never compared with one nobody read.
        elseif ($rpGitMissing) { Write-Output "                     branch: NOT read - git was not found on PATH"; $problems++ }
        elseif ($want -and $actual -and ($want -ne $actual)) {
            Write-Output "                     BRANCH MISMATCH: declared '$want', checked out '$actual'"; $problems++
        }
        elseif ($actual -eq 'unknown') { Write-Output "                     branch: could not be determined"; $problems++ }
        else { Write-Output ("                     branch: {0}{1}" -f $actual, $(if ($want) { " (declared $want)" } else { ' (none declared)' })) }
        $note = Get-Prop $r 'note' ''
        if ($note) { Write-Output "                     note: $note" }
    }
    if ($problems -gt 0) { Say "$problems repo(s) need attention before a phase declares them." }
    exit 0
}

# --------------------------------------------------------------------------- #
# Registers this machine in a project that shares its progress: as a new person, named once from
# the project repo's git config user.name, or with -As as a person already listed. -As <id> -Clear
# takes this machine off that person file, which is how a machine two person files list after a
# merge is put right; it reuses -Clear rather than adding a verb. Writes only progress/people/.
# Deliberately NOT through Read-State -ForWrite, whose person check would refuse the one machine
# this verb exists for: it reads the people files itself, under the same lock.
'join' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    if (-not (Test-SharedProgress $proj.Slug)) {
        Fail 90 "Project '$($proj.Slug)' keeps its progress on this machine, so there is nobody to join. 'join' is for a project that shares its progress through its repo (share-progress)."
    }
    Enter-WriteLock (Get-StatePath $proj.Slug) "project '$($proj.Slug)'"
    [void](Read-SharedState $proj.Slug)
    $jnCtx = $script:SpCtx[$proj.Slug]
    $jnDir = Join-Path $jnCtx.Dir 'people'
    $jnMachine = $env:COMPUTERNAME
    $jnMine = @($jnCtx.People | Where-Object { @(Get-Prop $_ 'machines' @()) -contains $jnMachine })
    $jnAt = [string](Add-SpOffset (Now))

    $jnTarget = $null
    if ($As) {
        $jnFound = @($jnCtx.People | Where-Object { [string](Get-Prop $_ 'id' '') -ceq $As })
        if ($jnFound.Count -eq 0) {
            Fail 90 "No person file under progress/people/ has the id '$As'. The ids there: $(@($jnCtx.People | ForEach-Object { $_.id }) -join ', '). Nothing was written."
        }
        $jnTarget = $jnFound[0]
    }

    if ($Clear) {
        if ($null -eq $jnTarget) { Fail 90 "-Clear takes this machine off ONE person file: name it with -As <person id>. Nothing was written." }
        $jnHad = @(Get-Prop $jnTarget 'machines' @())
        $jnLeft = @($jnHad | Where-Object { $_ -ne $jnMachine })
        if ($jnLeft.Count -eq $jnHad.Count) {
            Fail 90 "Person '$As' does not list this machine ('$jnMachine'), so there is nothing to take off. Nothing was written."
        }
        $jnFile = Join-Path $jnDir "$As.json"
        Assert-SpUnread $jnCtx $jnFile
        Write-SpFile $jnFile (New-SpPersonObj $As ([string](Get-Prop $jnTarget 'name' '')) $jnLeft $jnAt $false)
        Say "Took this machine ('$jnMachine') off person $As ($(Get-Prop $jnTarget 'name' '?'))."
        Say "  Commit progress/people/$As.json and push it, so the others see it too."
        exit 0
    }

    if ($jnMine.Count -gt 0) {
        Fail 90 "This machine ('$jnMachine') is already listed by $(($jnMine | ForEach-Object { "$($_.id) ($(Get-Prop $_ 'name' '?'))" }) -join ' and '). Nothing was written. To move it, take it off first: join -As <person id> -Clear."
    }

    if ($null -ne $jnTarget) {
        $jnFile = Join-Path $jnDir "$As.json"
        Assert-SpUnread $jnCtx $jnFile
        Write-SpFile $jnFile (New-SpPersonObj $As ([string](Get-Prop $jnTarget 'name' '')) @(@(Get-Prop $jnTarget 'machines' @()) + @($jnMachine)) $jnAt $false)
        Say "Added this machine ('$jnMachine') to person $As ($(Get-Prop $jnTarget 'name' '?'))."
        Say "  Commit progress/people/$As.json and push it, so the others see it too."
        exit 0
    }

    $jnName = Get-SpGitName $proj.Root
    if ([string]::IsNullOrWhiteSpace($jnName)) {
        Fail 95 "git config user.name is not set for '$($proj.Root)', and a new person is named from it, once. Set it, then re-run: git -C `"$($proj.Root)`" config user.name `"<your name>`". Nothing was written."
    }
    $jnId = New-SpPersonId $jnDir
    Write-SpFile (Join-Path $jnDir "$jnId.json") (New-SpPersonObj $jnId $jnName @($jnMachine) $jnAt $false)
    Say "Registered this machine ('$jnMachine') as person $jnId ($jnName) in '$($proj.Slug)'."
    Say "  Every write from this machine now names $jnId as its author. Commit progress/people/$jnId.json and push it."
    exit 0
}

# --------------------------------------------------------------------------- #
# The one-time switch from progress kept on this machine to progress kept in the project repo
# (charter P15, as amended). Writes progress/ from state.json, every file marked as exported and
# naming the exporter as its author, since state.json records no author and on a one-person
# project the exporter is the only person who wrote it; folds every closed or abandoned
# workstream; copies each phase folder's top-level files into progress/phases/<id>/artifacts/
# (its subfolders are this machine's scratch and stay); writes "progress": "repo" into keel.json;
# and renames state.json LAST, to state.json.shared-<date>, so an older keel finds no state and
# refuses (exit 91) rather than writing to a copy nobody reads. Commits nothing and pushes
# nothing: the person reviews and commits, and that commit is previewed like any other (P6).
'share-progress' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    $shCfg = Read-ProjectConfig $proj.ConfigPath
    if ($null -eq $shCfg) { Fail 90 "Could not read '$($proj.ConfigPath)'." }
    if ((Test-SharedProgress $proj.Slug) -or [string](Get-Prop $shCfg 'progress' '') -eq 'repo') {
        Fail 90 "Project '$($proj.Slug)' already shares its progress: keel.json says `"progress`": `"repo`". There is nothing to export."
    }
    if (Test-Quarantine $shCfg) {
        Fail 90 "Project '$($proj.Slug)' has quarantine on, so it cannot share its progress: progress files are committed, and nothing can check that a friction note, a question, a scope or a gate artifact quotes nothing identifying (charter P23). Its progress stays on this machine."
    }
    if (-not [bool](Get-Prop $shCfg 'git' $false)) {
        Fail 90 "Project '$($proj.Slug)' says git: false in keel.json. Shared progress travels with the project repo, so it needs one."
    }
    $shSt = Invoke-Native -Exe 'git' -Arguments @('-C', $proj.Root, 'status', '--porcelain') -NativeSplitStderr
    if ($shSt.NotFound) { Fail 90 'git was not found on PATH, so whether the project repo is clean could not be read. Nothing was written.' }
    if ($shSt.Code -ne 0) { Fail 90 "'$($proj.Root)' is not a git work tree (git status exit $($shSt.Code)). Shared progress travels with the project repo, so it needs one." }
    if (@($shSt.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        Fail 90 "The project repo has uncommitted changes. Commit them or put them aside first, so the export's own changes can be reviewed alone. Nothing was written."
    }
    $shName = Get-SpGitName $proj.Root
    if ([string]::IsNullOrWhiteSpace($shName)) {
        Fail 95 "git config user.name is not set for '$($proj.Root)', and the exporter is registered as a person named from it. Set it, then re-run: git -C `"$($proj.Root)`" config user.name `"<your name>`". Nothing was written."
    }
    $shDir = Join-Path $proj.Root 'progress'
    if (Test-Path -LiteralPath $shDir) {
        Fail 90 "'$shDir' already exists, and the export writes that folder from nothing. Nothing was written."
    }

    $state = Read-State $proj.Slug -ForWrite
    $shStatePath = Get-StatePath $proj.Slug
    Save-ReadSha $proj.ConfigPath

    $script:SpRoots[$proj.Slug] = $proj.Root
    $script:SpCtx[$proj.Slug] = New-SpContext $shDir
    $shDone = $false
    try {
        $shAt = [string](Add-SpOffset (Now))
        $shPid = New-SpPersonId (Join-Path $shDir 'people')
        Write-SpFile (Join-Path (Join-Path $shDir 'people') "$shPid.json") (New-SpPersonObj $shPid $shName @($env:COMPUTERNAME) $shAt $true)
        $shCount = 1 + (Write-SharedState $proj.Slug $state -SpExport -SpExporter $shPid)

        $shArt = 0
        foreach ($shP in @(Get-Phases $state)) {
            $shSrc = Join-Path (Join-Path (Join-Path $ProjectsHome $proj.Slug) 'phases') $shP.id
            if (-not (Test-Path -LiteralPath $shSrc -PathType Container)) { continue }
            $shDest = Join-Path (Join-Path (Join-Path $shDir 'phases') $shP.id) 'artifacts'
            foreach ($shF in @(Get-ChildItem -LiteralPath $shSrc -File)) {
                Ensure-Dir $shDest | Out-Null
                Copy-Item -LiteralPath $shF.FullName -Destination (Join-Path $shDest $shF.Name)
                $shArt++
            }
        }

        Set-Prop $shCfg 'progress' 'repo'
        Write-GuardedJson $proj.ConfigPath $shCfg

        Assert-Unchanged $shStatePath
        $shRenamed = "state.json.shared-$(Today)"
        $shN = 2
        while (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $shStatePath) $shRenamed)) { $shRenamed = "state.json.shared-$(Today)-$shN"; $shN++ }
        Rename-Item -LiteralPath $shStatePath -NewName $shRenamed
        $shDone = $true
    }
    finally {
        if (-not $shDone -and (Test-Path -LiteralPath $shDir)) { Remove-Item -LiteralPath $shDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Say "Exported '$($proj.Slug)' into its repo: $shCount progress file(s) and $shArt artifact(s) under progress/."
    Say "  This machine is person $shPid ($shName); every exported file names $shPid and says source: export."
    Say "  keel.json now says `"progress`": `"repo`". This machine's state.json is kept as $shRenamed, so an older keel finds no state here and refuses."
    Say '  Nothing was committed or pushed. Review progress/ and keel.json, then commit them together.'
    exit 0
}

# --------------------------------------------------------------------------- #
'resolve' {
    $p = Resolve-Project -StartPath $Path
    if ($null -eq $p) { Fail 91 "No keel project found by walking up from '$(if ($Path) { $Path } else { (Get-Location).Path })'." }
    if ($Json) { [pscustomobject]@{ slug = $p.Slug; root = $p.Root } | ConvertTo-Json -Compress }
    else { Say "project '$($p.Slug)' at '$($p.Root)'" }
    exit 0
}

# --------------------------------------------------------------------------- #
'list' {
    if (-not (Test-Path -LiteralPath $ProjectsHome)) { Say 'No keel projects yet.'; exit 0 }
    $dirs = @(Get-ChildItem -LiteralPath $ProjectsHome -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) { Say 'No keel projects yet.'; exit 0 }
    # The stored root is written once, at init-project. A project folder that is moved,
    # renamed or deleted would keep printing here as though it were still where it was
    # registered, at exit 0 with no warning of any kind, unless this re-measures it. Charter
    # P7: a claim about live state is re-measured at the moment it matters, and this verb is
    # the moment it matters.
    $lsTotal   = 0
    $lsMissing = 0
    foreach ($d in $dirs) {
        $sp = Join-Path $d.FullName 'state.json'
        if (-not (Test-Path -LiteralPath $sp)) {
            # A project that shares its progress keeps only scratch here, and the state.json it
            # had, renamed by share-progress; that file still records where the project lives. A
            # clone of a shared project that never exported from this machine has no such file
            # and is not listed: nothing on this machine records it.
            $lsShared = @(Get-ChildItem -LiteralPath $d.FullName -Filter 'state.json.shared-*' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc)
            if ($lsShared.Count -eq 0) { continue }
            $s = $null
            try { $s = Read-Json $lsShared[$lsShared.Count - 1].FullName } catch { $s = $null }
            if ($null -eq $s) { continue }
            $lsRoot = Get-Prop $s 'root' ''
            $lsTotal++
            $lsMark = ''
            if ([string]::IsNullOrWhiteSpace($lsRoot) -or -not (Test-Path -LiteralPath $lsRoot)) {
                $lsMark = '   [PATH MISSING]'
                $lsMissing++
            }
            Write-Output ("{0,-22} shared: its progress is in its repo   {1}{2}" -f $s.project, $lsRoot, $lsMark)
            continue
        }
        $s = Read-Json $sp
        $ph = @(Get-Phases $s)
        $delivered = @($ph | Where-Object { $_.stage -eq 'delivered' }).Count
        $lsRoot = Get-Prop $s 'root' ''
        $lsTotal++

        # The marker has to READ the path, not merely appear. A marker on every row is
        # indistinguishable from one that never fires, which is why a check of it must
        # assert the marked set EQUALS the set that fails this test, and run it against a store
        # where every root exists and require no marker at all.
        $lsMark = ''
        if ([string]::IsNullOrWhiteSpace($lsRoot) -or -not (Test-Path -LiteralPath $lsRoot)) {
            $lsMark = '   [PATH MISSING]'
            $lsMissing++
        }

        # NO project-level 'status' column here, and this is the one site where that is
        # explained. The field is written once - the literal 'active' in init-project -
        # and by no other verb, so a column printing it could only ever read 'active',
        # for every project, forever: a reader that looks like it varies and cannot.
        # Printing it would make the row LESS honest than omitting it, which is the same
        # reader-honesty call made for the stale root path a few lines below.
        #
        # The first whitespace-delimited token of this row is the project name, and
        # scripts/test-quarantine.ps1 -RealProjects reads it that way; removing a LATER
        # column does not move it.
        Write-Output ("{0,-22} {1}/{2} phases delivered   {3}{4}" -f $s.project, $delivered, $ph.Count, $lsRoot, $lsMark)
    }

    # Silent when every root is where it says it is (charter P16 - a clean run prints
    # nothing extra), so this line appearing at all is the finding.
    if ($lsMissing -gt 0) {
        Write-Output ''
        Say "$lsMissing of $lsTotal recorded root(s) do not exist on disk - marked [PATH MISSING] above."
        Say "  A project is resolved by walking up from the working directory (charter P20), so a project that MOVED still works from its new folder and only this stored path is stale. A project that was deleted is gone and this row is its last trace."
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'handoff' {
    # The brief for the NEXT session at a boundary where keel has no phase to point at.
    # Measured on a scratch project: status prints its 'brief:' line in
    # exactly ONE of four boundary states - next phase named AND promptPath set - and
    # nothing at all when a project has nothing decomposed yet, when the next phase
    # carries no prompt (every express workstream, by design), or when nothing is
    # pending, which is the close-out boundary.
    #
    # Deliberately writes NO state. If it did, 'updated' would advance as a side effect
    # of writing the handoff and every handoff would be born stale - which is the one
    # thing the drift check in 'status' must never do.
    $proj  = Resolve-ProjectOrFail -StartPath $Path
    $state = Read-State $proj.Slug

    # Not Require-Param, which fails 90. 95 is the established code for a mandatory
    # answer not supplied, and each half of a handoff is mandatory for its own reason.
    if ([string]::IsNullOrWhiteSpace($Next)) {
        Fail 95 "-Next is required: say what the next session should do. A handoff that names no next step is a status report, and 'status' already exists."
    }
    if ([string]::IsNullOrWhiteSpace($Detail)) {
        Fail 95 "-Detail is required: say what you measured that makes that the next step. Without it the next session inherits a conclusion it can neither re-derive nor overturn (charter P7)."
    }

    $cfg   = Read-ProjectConfig $proj.ConfigPath
    $hoDir = Get-HandoffDir $proj $cfg

    # Derived from -Next rather than carried by a new parameter: a new required parameter
    # is what charter P24 forbids, and a derived name keeps the naming fact in one home
    # (P10).
    $hoSlug = ($Next.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($hoSlug.Length -gt 48) { $hoSlug = $hoSlug.Substring(0, 48).Trim('-') }
    if ([string]::IsNullOrWhiteSpace($hoSlug)) { $hoSlug = 'handoff' }

    # The state's own 'updated' timestamp, never a second counter (charter P10), put
    # through Format-StateStamp so the line written here is ISO-8601 on either host -
    # see that function for why.
    $hoStamp = Format-StateStamp (Get-Prop $state 'updated' '')
    $hoPath  = Join-Path $hoDir "$hoSlug.md"

    # In a project that shares its progress several people write handoffs, so each is named for
    # its author's person id - two people ending with the same -Next no longer overwrite each other -
    # and says who wrote it and from where. The author is the writer every other write here names,
    # so a machine no person file lists is refused at 95, and one two list at 90, writing nothing.
    $hoAuthorLines = @()
    if (Test-SharedProgress $proj.Slug) {
        $hoPid = Get-SpWriter $proj.Slug
        $hoPerson = @($script:SpCtx[$proj.Slug].People | Where-Object { [string](Get-Prop $_ 'id' '') -ceq $hoPid })
        $hoAuthorName = if ($hoPerson.Count -gt 0) { [string](Get-Prop $hoPerson[0] 'name' '?') } else { '?' }
        $hoPath = Join-Path $hoDir "$hoPid-$hoSlug.md"
        $hoAuthorLines = @("Author: $hoAuthorName ($hoPid)", "Machine: $env:COMPUTERNAME")
    }

    $hoBody = @(
        "# Handoff - $hoSlug"
        ''
        "Written: $(Now)"
        "State revision: $hoStamp"
        $hoAuthorLines
        "Project: $($proj.Slug)"
        ''
        '## Next'
        ''
        $Next
        ''
        '## Why this is next'
        ''
        $Detail
        ''
        '---'
        'Written by keel-state.ps1 handoff. status compares the state revision above against'
        'live state and says so when they have diverged. The state file outranks this file on'
        'any disagreement (charter P10).'
    ) -join "`r`n"

    Write-TextNoBom $hoPath $hoBody
    Say "Handoff written: $hoPath"
    Say "  state revision: $hoStamp"
    Say "  'status' reports this path from now on, and marks it STALE once a later state write moves past that revision."
    exit 0
}

# --------------------------------------------------------------------------- #
'status' {
    $proj  = Resolve-ProjectOrFail -StartPath $Path
    $state = Read-State $proj.Slug
    # Read once here rather than at each of the two Write-UnpushedCommitsLine call sites
    # below - a status invocation reaches at most one of them.
    $cfg   = Read-ProjectConfig $proj.ConfigPath

    # -Phase is OPTIONAL for status, and is validated HERE rather than at its point of use
    # near the end of this block. Two early returns sit below - the -Json dump
    # and the no-phases-declared exit - and a validation placed after them refuses on one path
    # of three while the other two accept a malformed id and ignore it. A parameter that
    # refuses a typo in one invocation and returns 0 for it in another teaches the caller the
    # typo was fine: a script scoping a query with '-Json -Phase' cannot tell a valid scope
    # from a typo, and reads a whole-project dump as though it were one phase.
    #
    # Guarded on 'if ($Phase)', so an ABSENT -Phase reaches nothing new. That guard is the
    # whole of the regression surface: keel-session-start.ps1 runs 'status -Brief' with no
    # -Phase in every session.
    #
    # Both halves, not just the format check. Assert-PhaseId refuses a malformed id at exit
    # 90; Get-PhaseOrFail refuses a well-formed but undeclared one at exit 94. The full path
    # produces both, and validating here is what makes all three paths agree.
    #
    # BELOW Resolve-ProjectOrFail deliberately. Get-PhaseOrFail needs $state, so no earlier
    # position is possible - and a malformed -Phase run outside any project exits
    # 91 'no project resolved' rather than 90, which moving this above the resolve would
    # silently change on a path no check covers.
    if ($Phase) {
        Assert-PhaseId $Phase
        $qPhase = Get-PhaseOrFail $state $Phase
    }

    if ($Json) { $state | ConvertTo-Json -Depth 14; exit 0 }

    $phases = @(Get-Phases $state)
    $nodes  = @(Get-Nodes $state)
    $goalList = @(Get-GoalList $state)

    # No [active] bracket closes this line, for the reason written beside the 'list' row
    # above - the field has one possible value.
    Say "$($state.project) - $($state.title)"
    Say "  root: $($proj.Root)"

    # P24 - drift between the keel that planned this and the keel now running.
    $running = Get-KeelVersion
    $planned = Get-Prop $state 'plannedUnder' 'unknown'
    if ($running -ne $planned) {
        Say "  WARNING: planned under keel $planned, running keel $running. Contracts may have moved (charter P24)."
        Say "           Check the CHANGELOG between them, then: ack-keel-version -Detail '<what you checked>'"
    }

    # ---- a project that shares its progress: what this copy may lack, then what a merge broke.
    # First, because every line below is computed from what this copy holds. Nothing here runs for
    # a project that keeps its progress on this machine.
    $stShared = Test-SharedProgress $proj.Slug
    $stMerge = $null
    $stMe = $null
    if ($stShared) {
        Write-SpRemoteLines $proj $cfg
        $stMerge = Get-SpMergeProblems $proj.Slug $state
        foreach ($stLine in @($stMerge.Lines)) { Say "  WARNING: after a merge, $stLine" }
        $stMe = Get-SpMe $proj.Slug
    }

    if (-not $Brief) {
        Say "  goals: $($goalList.Count)   nodes: $($nodes.Count)   phases: $($phases.Count)"
    }

    # ---- goal coverage (P22)
    $claimed = @()
    foreach ($n in $nodes) {
        if (Test-WsClaiming $n) { $claimed += @(Get-Prop $n 'goals' @()) }
    }
    $claimed = @($claimed | Sort-Object -Unique)
    $unclaimed = @($goalList | Where-Object { $claimed -notcontains $_.id -and (Get-Prop $_ 'status' 'OPEN') -ne 'UNADDRESSED' })
    if ($unclaimed.Count -gt 0) {
        Say "  WARNING: $($unclaimed.Count) goal(s) with no workstream and not marked UNADDRESSED: $(($unclaimed | ForEach-Object { $_.id }) -join ', ')"
    }

    # A project with goals but nothing decomposed is a real session boundary - it is
    # where keel-plan-project ends - so the handoff reports here too, before the exit.
    if ($phases.Count -eq 0) { Say '  No phases declared yet.'; Write-HandoffLine $proj $state; Write-UnpushedCommitsLine $proj $cfg; exit 0 }

    # ---- phase table
    Write-Output ''
    Write-Output ("  {0,-9} {1,-9} {2,-9} {3,-15}" -f 'PHASE', 'ORDER', 'ACTOR', 'STAGE')
    foreach ($p in @($phases | Sort-Object -Property @{ Expression = { $x = Get-Prop $_ 'runOrder' -1; if ($x -lt 0) { 9999 } else { $x } } }, id)) {
        Write-Output (Format-PhaseLine $p $proj.Slug)
    }
    Write-Output ''

    # ---- what runs next, by DECLARED order only
    $pending = @($phases | Where-Object { @('delivered', 'abandoned', 'handed-over') -notcontains (Get-Prop $_ 'stage' '') })
    $noOrder =@($pending | Where-Object { (Get-Prop $_ 'runOrder' -1) -lt 0 })
    if ($noOrder.Count -gt 0) {
        Say "  WARNING: $($noOrder.Count) pending phase(s) have no declared run order: $(($noOrder | ForEach-Object { $_.id }) -join ', ')"
        Say '           Run order is declared data. This script will not guess it.'
    }
    # In a project that shares its progress, next is THIS person's: the phases they own. Everyone
    # else's goes on the 'others:' line below. A machine no person file lists, or two list, has no
    # person to be, so it is shown the whole project's next, and told so. A phase in a run-order
    # clash after a merge is never named (see Get-SpMergeProblems).
    $stPool = $pending
    $stMine = $stShared -and ($null -ne $stMe)
    if ($stMine) {
        $stPool = @($pending | Where-Object { [string](Get-Prop $_ 'owner' '') -ceq [string](Get-Prop $stMe 'id' '') })
    }
    elseif ($stShared) {
        Say "  note: next: is over everyone's phases - this machine is not registered in this project (join), or is listed twice."
    }
    # A phase with a need not yet met is held back: never named as next, here or on 'others:'.
    $stHeld = Get-HeldPhases $state $proj.Slug $pending
    $ordered = @($stPool | Where-Object { (Get-Prop $_ 'runOrder' -1) -ge 0 } | Sort-Object -Property @{ Expression = { Get-Prop $_ 'runOrder' -1 } })
    $runnable = @($ordered | Where-Object { (Get-Prop $_ 'stage' '') -ne 'waiting' -and -not $stHeld.ContainsKey([string]$_.id) })
    $stHeldOrdered = @($ordered | Where-Object { $stHeld.ContainsKey([string]$_.id) }).Count -gt 0
    $stClashNext = $false
    if ($stShared -and $runnable.Count -gt 0) {
        $stLow0 = Get-Prop $runnable[0] 'runOrder' -1
        $stTied0 = @($runnable | Where-Object { (Get-Prop $_ 'runOrder' -1) -eq $stLow0 })
        $stClashNext = ($stTied0.Count -eq 1) -and $stMerge.Clash.ContainsKey([string]$runnable[0].id)
    }
    if ($stClashNext) {
        $stC = $stMerge.Clash[[string]$runnable[0].id]
        Say "  next: none named - $($runnable[0].id) shares run order $($stC.Order) in $($stC.Ws) with $($stC.Others -join ', ') after a merge (see the warning above)."
    }
    elseif ($runnable.Count -gt 0) {
        # Run order is unique per WORKSTREAM (add-phase / revise-phase, exit 92), so two
        # workstreams can each hold a phase at the same order and this state cannot express
        # which of them runs first. When the lowest runnable tier holds more than one phase,
        # decline to name a winner rather than sorting one and announcing it.
        $lowOrder = Get-Prop $runnable[0] 'runOrder' -1
        $tiedLow  = @($runnable | Where-Object { (Get-Prop $_ 'runOrder' -1) -eq $lowOrder } | Sort-Object -Property id)
        $tiedWs   = @($tiedLow | ForEach-Object { Get-Prop $_ 'ws' '' } | Sort-Object -Unique)
        if ($tiedLow.Count -gt 1) {
            Say "  WARNING: next is ambiguous - $($tiedLow.Count) phases share the lowest run order $lowOrder, across $($tiedWs.Count) workstream(s)."
            Say '           Run order is unique per workstream, so this state cannot say which workstream runs first.'
            Say "           Read this project's declared cross-workstream order and run that. Candidates:"
            foreach ($cand in $tiedLow) { Say "             $($cand.id)  ($(Get-Prop $cand 'scope' ''))" }
        }
        else {
            Say "  next: $($runnable[0].id)  ($($runnable[0].scope))"
            # The fresh-session brief this phase already points at, written by add-phase and
            # revise-phase. Printed so a session opening cold does not re-derive what was
            # already written down.
            # Printed ONLY when set: an unset promptPath must add no line at all, or every
            # project that never used prompts gains a permanent empty row.
            $briefPath = Get-Prop $runnable[0] 'promptPath' ''
            if ($briefPath) {
                # Resolved against the project root recorded in state, never the current
                # directory - status is routinely run from a subfolder of the project.
                $briefFull = Join-Path $proj.Root $briefPath
                if (Test-Path -LiteralPath $briefFull) {
                    Say "        brief: $briefPath"
                }
                else {
                    # Deliberately not worded as a warning: scripts/keel-session-start.ps1
                    # filters status output on a token set defined on its -match line -
                    # that file is the pattern's one home and this comment does not copy it.
                    # A warning here would start printing in every session the hook runs in.
                    Say "        brief: $briefPath  (MISSING - no file at this path)"
                }
            }

            # The advisor question ledger, which open-question writes - and keel-run-phase
            # gate 6 and the orchestrator's gate table both REQUIRE it to be shown to the
            # human before they approve. State that is recorded and mandated must also be
            # readable by the instrument that demands it.
            #
            # The count only, and only for the phase a resuming session is about to open.
            # The entries themselves need -Phase, so the unscoped view does not grow with
            # the size of the ledger.
            #
            # Conditional on purpose (P16): a line that always fires trains the reader to
            # skip it, and a phase with no questions is the common case.
            #
            # WORDING IS LOAD-BEARING. scripts/keel-session-start.ps1 consumes this
            # command's stdout and decides what every session running that hook prints,
            # by matching the token set on its own -match line. The radius
            # is measured beside the ledger line below and is not restated here. That file is
            # the pattern's one home; this comment names it rather than copying it, so the
            # pattern keeps one home (charter P10).
            # A line matching any of those tokens would silently change SessionStart output
            # for every project. Measured clear of all of them before shipping, with
            # known-matching status lines as the positive control. Note -match is
            # case-insensitive, and that THIS ledger's own noun is one word away from one
            # of the tokens - the near miss is real and is why the wording is checked and
            # not eyeballed. Re-measure against that file if reworded.
            $nextLedger = @(Get-Prop $runnable[0] 'questions' @())
            if ($nextLedger.Count -gt 0) {
                Say "        questions: $($nextLedger.Count) recorded - re-surfaced at the human gate. Read them: status -Phase $($runnable[0].id)"
            }

            # The friction ledger, which note-friction and new-iteration write, and which
            # keel-close-workstream calls the close's entire evidence base. Same shape
            # as the question ledger above ON PURPOSE: two ledgers rendered two different
            # ways is a second thing for every future reader to learn (charter P10).
            #
            # The count only, and only for the phase a resuming session is about to open.
            # The entries themselves need -Phase, so the unscoped view does not grow with
            # the size of the ledger - and a project's ledger can run to well over a hundred
            # items, so that is not a hypothetical bound.
            #
            # Conditional on purpose (P16): a line that always fires trains the reader to
            # skip it, and the silence is also what makes the check discriminate - a line
            # that fired unconditionally would pass a count test and fail the empty-phase
            # test.
            #
            # WORDING IS LOAD-BEARING, exactly as for the question line above and for the
            # same reason: scripts/keel-session-start.ps1 consumes this command's stdout
            # and decides what every session running that hook prints. When measured, that
            # was sessions in the keel repo only - the hook was registered once, in that
            # repo's .claude/settings.json, scoped by CLAUDE_PROJECT_DIR, and no user-level
            # settings file or plugin declared it. The comment above defers to this one,
            # the one site where the measurement behind that radius is written down.
            #
            # That file is the one home of the token set it matches on, and this comment
            # does not copy it. Measured clear of every token before shipping, with
            # known-matching status lines as the positive control. Re-measure against that
            # file if reworded.
            #
            # Counts and a pointer ONLY - never entry text. Friction detail is free prose
            # written by earlier sessions and cannot be measured clear of that file's
            # tokens; the per-phase listing that does render it is unreachable from session
            # start, and that asymmetry is what makes this safe.
            $nextFriction = @(Get-Prop $runnable[0] 'friction' @())
            if ($nextFriction.Count -gt 0) {
                Say "        friction: $($nextFriction.Count) recorded - routed at close-out. Read them: status -Phase $($runnable[0].id)"
            }
        }
    }
    elseif ($stMine -and $stHeldOrdered) { Say '  next: nothing runnable - every pending phase you own is waiting or waits on other work (see the waits on lines below).' }
    elseif ($stMine -and $ordered.Count -gt 0) { Say '  next: nothing runnable - every pending phase you own is waiting.' }
    elseif ($stMine) { Say '  next: nothing pending that you own.' }
    elseif ($stHeldOrdered) { Say '  next: nothing runnable - every pending phase is waiting or waits on other work (see the waits on lines below).' }
    elseif ($ordered.Count -gt 0) { Say '  next: nothing runnable - every pending phase is waiting.' }
    else { Say '  next: nothing pending.' }

    # ---- everyone else's next, in a project that shares its progress: one line, each other person
    # who owns a pending phase, by name, by the same rule. Silent when nobody else does.
    if ($stMine) {
        $stOthers = New-Object System.Collections.Generic.List[string]
        $stMeId = [string](Get-Prop $stMe 'id' '')
        foreach ($stPe in @($script:SpCtx[$proj.Slug].People | Sort-Object -Property @{ Expression = { [string](Get-Prop $_ 'name' '') } }, id)) {
            $stPeId = [string](Get-Prop $stPe 'id' '')
            if ($stPeId -ceq $stMeId) { continue }
            $stTheirs = @($pending | Where-Object { [string](Get-Prop $_ 'owner' '') -ceq $stPeId })
            if ($stTheirs.Count -eq 0) { continue }
            $stOthers.Add("$(Get-Prop $stPe 'name' '?') ($stPeId): $(Get-SpNextText $stTheirs $stMerge.Clash $stHeld)")
        }
        if ($stOthers.Count -gt 0) { Say "  others: $($stOthers -join '; ')" }
    }

    # ---- what each held phase waits on, in table order, everyone's: one line per need not met.
    # A need on work abandoned can never be met, and needed work revised after the need was declared
    # may no longer give what was needed; both lines start 'WARNING:', so keel-session-start.ps1
    # forwards them to a resuming session. Silent when no phase has a need not met.
    foreach ($stHp in @($pending | Where-Object { $stHeld.ContainsKey([string]$_.id) } | Sort-Object -Property @{ Expression = { $x = Get-Prop $_ 'runOrder' -1; if ($x -lt 0) { 9999 } else { $x } } }, id)) {
        $stHpId = [string]$stHp.id
        foreach ($stHn in $stHeld[$stHpId]) {
            $stHnId = [string](Get-Prop $stHn.Need 'id' '')
            switch ($stHn.State.Kind) {
                'waiting' {
                    Say "  $stHpId waits on $($stHn.State.Text)"
                    if ($stHn.State.Revised) {
                        Say "  WARNING: $stHpId needs $stHnId, which was revised after the need was declared ($(Get-Prop $stHn.Need 'at' '?')). Check the need still holds, then re-declare it with revise-phase -Needs."
                    }
                }
                'never' {
                    $stRest = @(@(Get-NeedIds $stHp) | Where-Object { $_ -ne $stHnId })
                    $stRestText = if ($stRest.Count -gt 0) { $stRest -join ',' } else { 'none' }
                    Say "  WARNING: $stHpId needs $($stHn.State.Text), which was abandoned, so the need can never be met. Re-declare $stHpId's needs without it: revise-phase -Phase $stHpId -Needs $stRestText."
                }
                default { Say "  $stHpId waits on $($stHn.State.Text), which names no phase or workstream on this copy." }
            }
        }
    }

    # ---- the handoff the LAST session wrote for this one
    Write-HandoffLine $proj $state

    # ---- escalations
    $esc = @($phases | Where-Object { (Get-Prop $_ 'stage' '') -eq 'escalated' })
    if ($esc.Count -gt 0) {
        Say "  STOP: $($esc.Count) phase(s) escalated after hitting the iteration cap: $(($esc | ForEach-Object { $_.id }) -join ', ')"
        Say '        Surface this to the human before doing anything else. Do not quietly retry.'
    }

    # ---- a verify verdict whose bound material has moved
    # One line per in-flight phase, printed with or without -Brief. Each line starts
    # 'WARNING:', so scripts/keel-session-start.ps1 forwards it - deliberately: a resuming session
    # is the one that must see it. Silent, and no git call, for a phase with no binding (P16).
    foreach ($bindPh in @($phases | Where-Object { @('delivered', 'abandoned', 'handed-over') -notcontains (Get-Prop $_ 'stage' '') })) {
        Write-BindStatusLine $proj $bindPh
    }

    # ---- time (P19)
    $today = (Get-Date).Date
    $overdue = @($phases | Where-Object {
        $d = Get-Prop $_ 'due' ''
        # An abandoned phase is never overdue: its due date can no longer be met or missed,
        # and listing it forever teaches the reader to skip this line.
        $d -and (Get-Prop $_ 'stage' '') -notin @('delivered', 'abandoned', 'handed-over') -and ([datetime]::ParseExact($d, 'yyyy-MM-dd', $null) -lt $today)
    })
    if ($overdue.Count -gt 0) {
        Say "  OVERDUE: $(($overdue | ForEach-Object { "$($_.id) (due $(Get-Prop $_ 'due' ''))" }) -join ', ')"
    }
    $dueReview = @($phases | Where-Object {
        (Get-Prop $_ 'stage' '') -eq 'waiting' -and (Get-Prop $_ 'reviewOn' '') -and
        ([datetime]::ParseExact((Get-Prop $_ 'reviewOn' ''), 'yyyy-MM-dd', $null) -le $today)
    })
    if ($dueReview.Count -gt 0) {
        Say "  CHASE: $(($dueReview | ForEach-Object { "$($_.id) waiting on $(Get-Prop $_ 'waitingOn' '?') since review date $(Get-Prop $_ 'reviewOn' '')" }) -join '; ')"
    }

    # ---- N/A census - how many gates have been waived
    $naCount = 0
    foreach ($p in $phases) {
        $gateObj = Get-Prop $p 'gates' $null
        if ($null -ne $gateObj) {
            foreach ($gp in @($gateObj.PSObject.Properties)) {
                if ((Get-Prop $gp.Value 'verdict' '') -eq 'N/A') { $naCount++ }
            }
        }
    }
    if ($naCount -gt 0) { Say "  N/A census: $naCount gate(s) waived across this project." }

    # ---- commits that have never left this machine
    # Immediately above the signals block on purpose: both answer "has this left the
    # machine", one for code and one for signals, and they belong next to each other.
    Write-UnpushedCommitsLine $proj $cfg

    # ---- open signals filed from this project (P16: only when non-zero)
    # The count alone is not enough. OPEN and UNPUSHED are independent, and the operator's
    # question is always "has this left the machine" - so the line answers it in both
    # directions rather than printing a number that invites the wrong inference.
    $open = @(Get-Signals -Slug $proj.Slug -FilterKind '' | Where-Object { $_.state -eq 'OPEN' })
    if ($open.Count -gt 0) {
        $unpushedOpen = @($open | Where-Object { $null -eq (Get-Prop $_ 'issue' $null) })
        if ($unpushedOpen.Count -gt 0) {
            # Name signals-push only when it can work. With no destination it refuses,
            # and keel-session-start.ps1 forwards this line every session, so a pointer at a
            # command that cannot run would be a dead end printed forever.
            $sigLead = "  $($open.Count) open signal(s) filed from this project and not yet triaged in keel; $($unpushedOpen.Count) NOT yet pushed - those exist only on this machine."
            if ($null -ne (Get-SignalsDestination)) {
                Say "$sigLead Run: keel-state.ps1 signals-push"
            }
            else {
                Say "$sigLead No report destination is chosen, so they stay here; to send them, choose one: keel-state.ps1 signals-target -Repo owner/name"
            }
        }
        else {
            Say "  $($open.Count) open signal(s) filed from this project and not yet triaged in keel; all pushed as GitHub issues."
        }
    }

    # ---- the advisor question ledger in full, scoped to one phase
    #
    # -Phase is OPTIONAL here and is bound by the shared param() block. Reading it here adds
    # a reader, not a parameter: every invocation without it keeps its exact behaviour and
    # no in-flight project is stranded, which is what makes this a widening rather than a
    # tightening (charter P24).
    #
    # ADDITIVE, not short-circuiting like -Json above. A session runs this at the human
    # gate, where it must still see STOP:, OVERDUE:, CHASE: and the P24 drift warning
    # printed above - status is the resume mechanism and those lines are why. Suppressing
    # them to render a tidier ledger would trade the gate for the presentation of it.
    #
    # Silent when the phase has none (P16). That silence is also what makes the check
    # discriminate: a stub that always rendered a heading would pass a count test and fail
    # this one.
    #
    # CAUTION, if this output is ever routed anywhere new. These lines echo recorded
    # question and answer text VERBATIM, so they can contain any substring at all -
    # including the tokens scripts/keel-session-start.ps1 filters status stdout on (that
    # file is the pattern's one home and it is not copied here). Recorded entries
    # already do. That is safe ONLY because session-start invokes 'status -Brief' and never
    # passes -Phase, so nothing below is reachable from it. The chrome around the entries is
    # measured clear; the entries themselves cannot be, and must not be assumed to be.
    if ($Phase) {
        # Validated and looked up at the top of this block, above the early returns.
        # Not re-asserted here: one home for the check, or the two copies drift (charter P10).
        $ledger = @(Get-Prop $qPhase 'questions' @())
        if ($ledger.Count -gt 0) {
            Write-Output ''
            Say "  questions on $($qPhase.id) - $($ledger.Count) recorded, re-surfaced at the human gate:"
            $qNum = 0
            foreach ($q in $ledger) {
                $qNum++
                Say "    $qNum. [$(Get-Prop $q 'at' '?')] $(Get-Prop $q 'question' '?')"
                $qAnswer = Get-Prop $q 'answer' ''
                if ($qAnswer) { Say "       -> answered by $(Get-Prop $q 'resolvedBy' 'agent'): $qAnswer" }
                else          { Say '       -> OPEN, no answer recorded.' }
            }
        }

        # The friction ledger for this phase, the one keel-close-workstream Step 2 names
        # instead of dumping the whole state as JSON. Kind and timestamp on the numbered
        # line, detail beneath it. Silent when the phase has none, like the question ledger
        # above (P16).
        #
        # CAUTION, identical to the block above and for the identical reason. These lines
        # echo recorded friction detail VERBATIM, so they can contain any substring at all,
        # including the tokens scripts/keel-session-start.ps1 filters status stdout on
        # (that file is the pattern's one home and it is not copied here). Recorded friction
        # details already do, and the number grows as sessions record more. That is safe
        # ONLY because session-start invokes 'status -Brief' and never passes -Phase, so
        # nothing here is reachable from it. The chrome around the entries is measured
        # clear; the entries themselves cannot be, and must not be assumed to be.
        $fLedger = @(Get-Prop $qPhase 'friction' @())
        if ($fLedger.Count -gt 0) {
            Write-Output ''
            Say "  friction on $($qPhase.id) - $($fLedger.Count) recorded, routed at close-out:"
            $fNum = 0
            foreach ($fr in $fLedger) {
                $fNum++
                Say "    $fNum. [$(Get-Prop $fr 'at' '?')] $(Get-Prop $fr 'kind' '?')"
                $fDetail = Get-Prop $fr 'detail' ''
                if ($fDetail) { Say "       -> $fDetail" }
                else          { Say '       -> no detail recorded.' }
            }
        }

        # Corrections to a delivered phase. The same CAUTION as the two blocks above:
        # verbatim text, safe only because session-start never passes -Phase. Silent when none.
        $cLedger = @(Get-Prop $qPhase 'corrections' @())
        if ($cLedger.Count -gt 0) {
            Write-Output ''
            Say "  corrections on $($qPhase.id) - $($cLedger.Count) recorded:"
            $cNum = 0
            foreach ($cItem in $cLedger) {
                $cNum++
                Say "    $cNum. [$(Get-Prop $cItem 'at' '?')] $(Get-Prop $cItem 'text' '?')"
            }
        }
    }

    exit 0
}

# --------------------------------------------------------------------------- #
'tree' {
    $proj  = Resolve-ProjectOrFail -StartPath $Path
    $state = Read-State $proj.Slug
    $nodes = @(Get-Nodes $state)

    Say "$($state.project) - $($state.title)"
    # The read-time check after a merge, as 'status' prints it: a tree drawn from a broken whole
    # says so above the tree.
    if (Test-SharedProgress $proj.Slug) {
        foreach ($trLine in @((Get-SpMergeProblems $proj.Slug $state).Lines)) { Say "  WARNING: after a merge, $trLine" }
    }
    foreach ($g in @(Get-GoalList $state)) {
        $mark = if ((Get-Prop $g 'status' 'OPEN') -eq 'UNADDRESSED') { '  [UNADDRESSED]' } else { '' }
        Write-Output ("  {0}  {1}{2}" -f $g.id, $g.text, $mark)
    }
    Write-Output ''

    function Show-Node {
        param($State, $NodeId, [int]$Depth)
        $pad = '  ' + ('   ' * $Depth)
        foreach ($n in @(Get-Nodes $State | Where-Object { (Get-Prop $_ 'parent' '') -eq $NodeId })) {
            $gl = @(Get-Prop $n 'goals' @())
            $gs = if ($gl.Count -gt 0) { '  -> ' + ($gl -join ',') } else { '' }
            $stMark = ''
            if ($n.role -eq 'workstream') {
                $stVal = Get-Prop $n 'status' ''
                if ($stVal) {
                    # closedAt stays as history on a workstream closed and later abandoned, so it
                    # is not the date of this status.
                    $closed = if ($stVal -eq 'ABANDONED') { Get-Prop $n 'abandonedAt' '' } else { Get-Prop $n 'closedAt' '' }
                    $when   = if ($closed) { ' ' + ($closed -split 'T')[0] } else { '' }
                    $stMark = "  [$stVal$when]"
                }
            }
            Write-Output ("{0}{1} [{2}] {3}{4}{5}" -f $pad, $n.id, $n.role, $n.title, $gs, $stMark)
            if ($n.role -eq 'workstream' -and (Get-Prop $n 'status' '') -eq 'ABANDONED') {
                Write-Output ("{0}     abandoned: {1}" -f $pad, (Get-Prop $n 'abandonedReason' ''))
            }
            if ($n.role -eq 'epic') {
                Write-Output ("{0}     groups: {1}" -f $pad, (Get-Prop $n 'groups' ''))
                Show-Node -State $State -NodeId $n.id -Depth ($Depth + 1)
            }
            else {
                foreach ($p in @(Get-Phases $State | Where-Object { $_.ws -eq $n.id } | Sort-Object -Property @{ Expression = { Get-Prop $_ 'runOrder' -1 } })) {
                    $trEx = Get-PhaseLineExtras $p $proj.Slug
                    $trNeedIds = @(Get-NeedIds $p)
                    $trNeeds = if ($trNeedIds.Count -gt 0) { "  needs: $($trNeedIds -join ', ')" } else { '' }
                    Write-Output ("{0}   {1} [phase] {2}  actor:{3}  {4}{5}{6}{7}" -f $pad, $p.id, $p.scope, (Get-Prop $p 'actor' '?'), (Get-Prop $p 'stage' '?'), $trEx.Stage, $trNeeds, $trEx.Owner)
                    foreach ($cItem in @(Get-Prop $p 'corrections' @())) {
                        Write-Output ("{0}      correction {1}: {2}" -f $pad, ((Get-Prop $cItem 'at' '') -split 'T')[0], (Get-Prop $cItem 'text' ''))
                    }
                }
            }
        }
    }
    Show-Node -State $state -NodeId '' -Depth 0
    exit 0
}

# --------------------------------------------------------------------------- #
'goal-coverage' {
    $proj  = Resolve-ProjectOrFail -StartPath $Path
    $state = Read-State $proj.Slug
    $nodes = @(Get-Nodes $state)

    foreach ($g in @(Get-GoalList $state)) {
        $claimants = @($nodes | Where-Object { (Test-WsClaiming $_) -and @(Get-Prop $_ 'goals' @()) -contains $g.id })
        $goalStatus = Get-Prop $g 'status' 'OPEN'
        if ($claimants.Count -gt 0) {
            Write-Output ("{0}  CLAIMED by {1}: {2}" -f $g.id, $claimants.Count, (($claimants | ForEach-Object { $_.id }) -join ', '))
        }
        elseif ($goalStatus -eq 'UNADDRESSED') {
            Write-Output ("{0}  UNADDRESSED (declared): {1}" -f $g.id, (Get-Prop $g 'statusReason' ''))
        }
        else {
            Write-Output ("{0}  UNCLAIMED - no workstream points at this and it is not marked UNADDRESSED (charter P22)" -f $g.id)
        }
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'add-goal' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Id 'Id'; Assert-GoalId $Id
    Require-Param $Text 'Text'
    $state = Read-State $proj.Slug -ForWrite
    $dupe = @(@(Get-GoalList $state) | Where-Object { $_.id -eq $Id })
    if ($dupe.Count -gt 0) { Fail 90 "Goal '$Id' already exists." }

    $g = [pscustomobject]@{ id = $Id; text = $Text; status = 'OPEN'; created = (Now) }
    $arr = @(Get-GoalList $state); $arr += $g; Set-Prop $state 'goals' $arr
    Write-State $proj.Slug $state
    Say "Added goal $Id."
    exit 0
}

# --------------------------------------------------------------------------- #
# P22 says a goal is claimed OR marked UNADDRESSED, and 'status' and 'goal-coverage'
# both report against that token, so something must be able to write it. Without it
# the only way to clear the warning would be to invent a workstream for a goal
# correctly not being worked yet - worse than the warning, and it trains the reader
# to skim the line (P16). The reason is mandatory: an undeclared UNADDRESSED is the
# silence P22 exists to break.
'set-goal-status' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Id 'Id'; Assert-GoalId $Id
    Require-Param $Status 'Status'
    $wanted = $Status.ToUpper()
    Assert-Enum $wanted $GoalStatuses 'Status'

    $state = Read-State $proj.Slug -ForWrite
    $arr = @(Get-GoalList $state)
    $target = @($arr | Where-Object { $_.id -eq $Id })
    if ($target.Count -eq 0) { Fail 98 "Goal '$Id' does not exist in this project. Add it with add-goal first." }
    $g = $target[0]

    if ($wanted -eq 'UNADDRESSED') {
        if ([string]::IsNullOrWhiteSpace($Detail)) {
            Fail 95 "-Detail is required to mark a goal UNADDRESSED. Say WHY no workstream claims it - 'the workstream that would decompose it (W1.3) has not run' is an answer; silence is what P22 exists to break."
        }
        # A goal a workstream already points at is claimed, and goal-coverage would
        # report CLAIMED regardless - so the mark would be a lie sitting in state.
        $claimants = @(@(Get-Nodes $state) | Where-Object { (Test-WsClaiming $_) -and @(Get-Prop $_ 'goals' @()) -contains $Id })
        if ($claimants.Count -gt 0) {
            Fail 98 ("Goal '$Id' is already claimed by " + (($claimants | ForEach-Object { $_.id }) -join ', ') + ". A claimed goal is not unaddressed (charter P22).")
        }
    }

    Set-Prop $g 'status' $wanted
    if ($wanted -eq 'UNADDRESSED') { Set-Prop $g 'statusReason' $Detail }
    else                           { Set-Prop $g 'statusReason' $null }
    Set-Prop $g 'statusSetAt' (Now)
    Set-Prop $state 'goals' $arr
    Write-State $proj.Slug $state

    if ($wanted -eq 'UNADDRESSED') { Say "Goal $Id marked UNADDRESSED: $Detail" }
    else                           { Say "Goal $Id set back to OPEN. It now needs a workstream to claim it (charter P22)." }
    exit 0
}

# --------------------------------------------------------------------------- #
# P24's drift warning needs a way to be answered: 'plannedUnder' is written once at
# init-project, so without this verb the moment keel ships any release every project
# warns on every session, forever. An always-on warning is not a warning - and
# this is the one that matters most, because a REAL contract move would then
# arrive indistinguishable from the noise (P16).
#
# This does not silence the check, it ANSWERS it: the reason is mandatory and the
# ack is kept, so 'what did we conclude last time keel moved under this project'
# has an answer. The next version bump warns again, which is the point - each move
# gets reviewed once.
'ack-keel-version' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    # 95, not Require-Param's 90: this is a mandatory ANSWER, not a malformed argument.
    if ([string]::IsNullOrWhiteSpace($Detail)) {
        Fail 95 "-Detail is required. Say what you checked between the two versions - 'read the CHANGELOG, all widenings, nothing affects this project' is an answer. An ack with no reason is the warning silenced rather than answered."
    }

    $state   = Read-State $proj.Slug -ForWrite
    $running = Get-KeelVersion
    $planned = Get-Prop $state 'plannedUnder' 'unknown'
    if ($running -eq $planned) {
        Say "Already stamped at keel $running - there is no drift to acknowledge."
        exit 0
    }

    # keel.json carries the same version for a human reading the folder; leaving the
    # two to disagree would be a second authority that rots (P10). Read, and checked unchanged,
    # BEFORE the state is written: a refusal after the state write would leave the two
    # disagreeing, and a re-run would then find no drift to acknowledge and never repair it.
    Save-ReadSha $proj.ConfigPath
    $cfg = Read-ProjectConfig $proj.ConfigPath

    $acks = @(Get-Prop $state 'versionAcks' @())
    $acks += [pscustomobject]@{ from = $planned; to = $running; detail = $Detail; at = (Now) }
    Set-Prop $state 'versionAcks' $acks
    Set-Prop $state 'plannedUnder' $running
    Assert-Unchanged $proj.ConfigPath
    Write-State $proj.Slug $state

    if ($null -ne $cfg) {
        Set-Prop $cfg 'keelVersion' $running
        Write-GuardedJson $proj.ConfigPath $cfg
    }

    Say "Acknowledged keel $planned -> $running for '$($proj.Slug)': $Detail"
    Say "  The next keel version will warn again. That is the check working, not repeating itself."
    exit 0
}

# --------------------------------------------------------------------------- #
'add-epic' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Id 'Id'; Assert-EpicId $Id
    Require-Param $Title 'Title'
    Require-Param $Groups 'Groups'   # P17 - an epic must say what it groups

    $state = Read-State $proj.Slug -ForWrite
    if ($null -ne (Find-Node $state $Id)) { Fail 90 "Node '$Id' already exists." }
    if ($Groups.Trim() -eq $Title.Trim()) {
        Fail 93 "-Groups restates the title. It must say what this epic GROUPS, so each rung of the nesting justifies itself (charter P17)."
    }
    [void](Assert-Parent $state $Parent 'epic')

    $goalIds = @(Split-Csv $Goals)
    if ($goalIds.Count -gt 0) { Assert-GoalsExist $state $goalIds }

    $n = [pscustomobject]@{
        id = $Id; role = 'epic'; title = $Title
        parent = $(if ([string]::IsNullOrWhiteSpace($Parent) -or $Parent -eq 'root') { '' } else { $Parent })
        groups = $Groups; goals = $goalIds; created = (Now)
    }
    $arr = @(Get-Nodes $state); $arr += $n; Set-Prop $state 'nodes' $arr
    Write-State $proj.Slug $state
    Say "Added epic $Id under '$(if ($n.parent) { $n.parent } else { 'root' })'."
    exit 0
}

# --------------------------------------------------------------------------- #
# The second rank of the per-role verb grid: 'add-*' writes a node, 'revise-*' corrects
# one BEFORE anything beneath it is delivered. Shaped on 'revise-phase', which is the
# verb a reader will compare these against - matching its structure is worth more than
# any improvement on it. Neither exists to redo delivered work: that is a new phase, and
# Assert-NoDeliveredBeneath is the one place both say so. The exception is an epic's
# groups line alone, which stays revisable after delivery (see that helper).
'revise-epic' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Id 'Id'; Assert-EpicId $Id

    $state  = Read-State $proj.Slug -ForWrite
    $reNode = Find-Node $state $Id
    if ($null -eq $reNode) { Fail 94 "Epic '$Id' does not exist." }
    if ($reNode.role -ne 'epic') { Fail 93 "'$Id' is a $($reNode.role), not an epic (charter P17)." }

    if (-not $Title -and -not $Groups -and -not $Goals) {
        Fail 90 "Supply at least one of -Title, -Groups or -Goals for 'revise-epic'. A revise that changes nothing has asked for nothing."
    }

    # Only -Title and -Goals are locked after delivery. -Groups alone describes what the
    # epic holds, which grows as its ledger does.
    if ($Title -or $Goals) { Assert-NoDeliveredBeneath $state $Id 'epic' }

    # P17, applied to the RESULTING pair and not to what was passed in. Revising only the
    # title, to a string that happens to equal the STORED groups line, must refuse: a
    # guard that inspects only the supplied arguments lets the invariant break through
    # the one door it is not watching.
    $reNewTitle  = if ($Title)  { $Title }  else { Get-Prop $reNode 'title'  '' }
    $reNewGroups = if ($Groups) { $Groups } else { Get-Prop $reNode 'groups' '' }
    if ($reNewTitle.Trim() -eq $reNewGroups.Trim()) {
        Fail 93 "The resulting -Groups would restate the resulting -Title. It must say what this epic GROUPS, so each rung of the nesting justifies itself (charter P17)."
    }

    # NO mandatory-goal rule here: 'add-epic' has none, and adding one would tighten a
    # contract an in-flight project already satisfies (charter P24). And NO UNADDRESSED
    # clearing: 'goal-coverage', the status coverage warning and the exit-98 guard all
    # filter on role 'workstream', so an epic's -Goals link is not a claim to any reader,
    # and clearing there would CREATE a two-authority disagreement (P10) rather than
    # close one. The measurement behind that is recorded in full under 'add-workstream'.
    if ($Goals) {
        $reGoalIds = @(Split-Csv $Goals)
        if ($reGoalIds.Count -gt 0) { Assert-GoalsExist $state $reGoalIds }
        Set-Prop $reNode 'goals' $reGoalIds
    }
    if ($Title)  { Set-Prop $reNode 'title'  $Title }
    if ($Groups) { Set-Prop $reNode 'groups' $Groups }

    Write-State $proj.Slug $state
    Say "Revised epic $Id."
    exit 0
}

# --------------------------------------------------------------------------- #
'add-workstream' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Id 'Id'; Assert-WsId $Id
    Require-Param $Title 'Title'

    $state = Read-State $proj.Slug -ForWrite
    if ($null -ne (Find-Node $state $Id)) { Fail 90 "Node '$Id' already exists." }
    [void](Assert-Parent $state $Parent 'workstream')

    $goalIds = @(Split-Csv $Goals)
    if ($goalIds.Count -eq 0) {
        Fail 98 "-Goals is required for a workstream: at least one goal id, e.g. -Goals G1,G2. Coverage is a query, not a feeling (charter P22)."
    }
    Assert-GoalsExist $state $goalIds

    # P22's invariant is guarded in BOTH directions. 'set-goal-status' refuses to mark a
    # CLAIMED goal UNADDRESSED (Fail 98), and this clears the label the other way. Without
    # it, a goal marked UNADDRESSED and then claimed keeps that label forever - 'tree'
    # prints [UNADDRESSED] from the stored field while 'goal-coverage' computes CLAIMED
    # from the same state file. Two authorities for one fact (P10), permanent, and cleared
    # by hand on every project.
    # The three fields written here are exactly the three 'set-goal-status -Status OPEN'
    # writes, so a goal cleared here is indistinguishable from one cleared by hand.
    # Epics are deliberately NOT covered: 'goal-coverage', the 'status' coverage warning and
    # the exit-98 guard all filter on role 'workstream', so an epic's -Goals link is not a
    # claim to any reader. Measured - clearing it there would CREATE a disagreement, not
    # close one: 'tree' would print no label while 'goal-coverage' printed UNCLAIMED.
    $goalArr = @(Get-GoalList $state)
    $cleared = @()
    foreach ($gid in $goalIds) {
        $gTarget = @($goalArr | Where-Object { $_.id -eq $gid })
        if ($gTarget.Count -eq 0) { continue }
        if ((Get-Prop $gTarget[0] 'status' 'OPEN') -ne 'UNADDRESSED') { continue }
        Set-Prop $gTarget[0] 'status'       'OPEN'
        Set-Prop $gTarget[0] 'statusReason' $null
        Set-Prop $gTarget[0] 'statusSetAt'  (Now)
        $cleared += $gid
    }
    if ($cleared.Count -gt 0) { Set-Prop $state 'goals' $goalArr }

    $n = [pscustomobject]@{
        id = $Id; role = 'workstream'; title = $Title
        parent = $(if ([string]::IsNullOrWhiteSpace($Parent) -or $Parent -eq 'root') { '' } else { $Parent })
        goals = $goalIds; status = 'PLANNED'; created = (Now)
    }
    $arr = @(Get-Nodes $state); $arr += $n; Set-Prop $state 'nodes' $arr
    Write-State $proj.Slug $state
    Say "Added workstream $Id -> $($goalIds -join ',')."
    # P16 - conditional on purpose. A line that always fires trains the reader to skip it,
    # and the test of this fails if it announces itself when nothing was cleared.
    if ($cleared.Count -gt 0) {
        Say "  Cleared UNADDRESSED on $($cleared -join ', ') - now claimed by $Id (charter P22)."
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'revise-workstream' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Id 'Id'; Assert-WsId $Id

    $state  = Read-State $proj.Slug -ForWrite
    $rwNode = Find-Node $state $Id
    if ($null -eq $rwNode) { Fail 94 "Workstream '$Id' does not exist." }
    if ($rwNode.role -ne 'workstream') { Fail 93 "'$Id' is a $($rwNode.role), not a workstream (charter P17)." }
    Assert-WsNotAbandoned $rwNode

    if (-not $Title -and -not $Goals) {
        Fail 90 "Supply at least one of -Title or -Goals for 'revise-workstream'. A revise that changes nothing has asked for nothing."
    }

    Assert-NoDeliveredBeneath $state $Id 'workstream'

    $rwSigBefore = Get-RevisionSig $rwNode 'node'
    $rwCleared = @()
    if ($Goals) {
        $rwGoalIds = @(Split-Csv $Goals)
        if ($rwGoalIds.Count -eq 0) {
            Fail 98 "-Goals resolved to no goal at all. A workstream declares at least one; coverage is a query, not a feeling (charter P22)."
        }
        Assert-GoalsExist $state $rwGoalIds

        # The same three fields 'add-workstream' writes, and for its reason: a goal
        # cleared here must be indistinguishable from one cleared there, or 'tree' and
        # 'goal-coverage' end up disagreeing about one fact (P10).
        $rwGoalArr = @(Get-GoalList $state)
        foreach ($gid in $rwGoalIds) {
            $rwTarget = @($rwGoalArr | Where-Object { $_.id -eq $gid })
            if ($rwTarget.Count -eq 0) { continue }
            if ((Get-Prop $rwTarget[0] 'status' 'OPEN') -ne 'UNADDRESSED') { continue }
            Set-Prop $rwTarget[0] 'status'       'OPEN'
            Set-Prop $rwTarget[0] 'statusReason' $null
            Set-Prop $rwTarget[0] 'statusSetAt'  (Now)
            $rwCleared += $gid
        }
        if ($rwCleared.Count -gt 0) { Set-Prop $state 'goals' $rwGoalArr }
        Set-Prop $rwNode 'goals' $rwGoalIds
    }
    if ($Title) { Set-Prop $rwNode 'title' $Title }
    # Revised, for the warning a phase needing this workstream gets, only on a real change.
    if ((Get-RevisionSig $rwNode 'node') -cne $rwSigBefore) { Set-Prop $rwNode 'revisedAt' (Now) }

    Write-State $proj.Slug $state
    Say "Revised workstream $Id."
    # P16 - conditional on purpose. A line that always fires trains the reader to skip it.
    if ($rwCleared.Count -gt 0) {
        Say "  Cleared UNADDRESSED on $($rwCleared -join ', ') - now claimed by $Id (charter P22)."
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'add-phase' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    Require-Param $Scope 'Scope'
    Require-Param $Actor 'Actor'; Assert-Enum $Actor $Actors 'Actor'

    $state = Read-State $proj.Slug -ForWrite
    $wsId   = Ws-Of-Phase $Phase
    # NOTE: never name a script-scope local after a param. PowerShell variable names are
    # case-insensitive, so '$ws' IS the [string]$Ws parameter and would silently coerce
    # this object to a string, losing every property. Cost the first test run of this script.
    $wsNode = Find-Node $state $wsId
    if ($null -eq $wsNode) { Fail 94 "Workstream '$wsId' does not exist. A phase's id carries its workstream." }
    if ($wsNode.role -ne 'workstream') { Fail 93 "'$wsId' is a $($wsNode.role). Only a workstream may contain phases (charter P17)." }
    Assert-WsNotAbandoned $wsNode
    if ($null -ne (Find-Phase $state $Phase)) { Fail 90 "Phase '$Phase' already exists." }
    # The owner: a person id, the writer when none is given. Stored explicitly, so the file says it.
    $apShared = Test-SharedProgress $proj.Slug
    $apOwnerId = $null
    if ($Owner -and -not $apShared) { Fail 90 "-Owner is for a project that shares its progress; '$($proj.Slug)' keeps its progress on this machine, so its phases have no owner. Nothing was written." }
    if ($apShared) {
        if ($Owner) { Assert-SpPerson $proj.Slug $Owner 'Owner'; $apOwnerId = $Owner }
        else { $apOwnerId = Get-SpWriter $proj.Slug }
    }

    # A handed-over phase is set aside: the phase that continues it takes its place in the order.
    if ($RunOrder -ge 0) {
        $clash = @(Get-Phases $state | Where-Object { $_.ws -eq $wsId -and (Get-Prop $_ 'runOrder' -1) -eq $RunOrder -and (Get-Prop $_ 'stage' '') -ne 'handed-over' })
        if ($clash.Count -gt 0) {
            Fail 92 "Run order $RunOrder is already taken in $wsId by '$($clash[0].id)'. Move it first with revise-phase; two phases sharing an order makes 'what runs next' arbitrary while status answers it confidently."
        }
    }
    if ($Due) { Assert-Date $Due 'Due' }

    $repoNames = @(Split-Csv $Repos)
    Assert-ReposDeclared -Proj $proj -RepoNames $repoNames
    $apNeeds = @()
    if ($PSBoundParameters.ContainsKey('Needs')) { $apNeeds = @(Read-NeedsParam $state $Phase $wsId $Needs $true $proj.Slug) }

    $p = [pscustomobject]@{
        id = $Phase; ws = $wsId; scope = $Scope; actor = $Actor
        runOrder = $RunOrder
        repos = $repoNames
        due = $(if ($Due) { $Due } else { $null })
        promptPath = $(if ($PromptPath) { $PromptPath } else { $null })
        stage = 'planned'
        waitingOn = $null; reviewOn = $null
        iterations = 0
        gates = [pscustomobject]@{}
        friction = @(); questions = @()
        created = (Now)
    }
    if ($apShared) { Set-Prop $p 'owner' $apOwnerId }
    # Stored only when there is one, so a per-machine phase with no needs is what it always was.
    if ($apNeeds.Count -gt 0) { Set-Prop $p 'needs' $apNeeds }
    $arr = @(Get-Phases $state); $arr += $p; Set-Prop $state 'phases' $arr
    Write-State $proj.Slug $state
    Ensure-Dir (Get-PhaseDir $proj.Slug $Phase) | Out-Null

    $apOwnerNote = if ($apShared) { ", owner: $(Get-SpPersonText $proj.Slug $apOwnerId)" } else { '' }
    $apNeedsNote = if ($apNeeds.Count -gt 0) { ", needs: $((@($apNeeds | ForEach-Object { $_.id })) -join ', ')" } else { '' }
    Say "Added phase $Phase (actor: $Actor, order: $(if ($RunOrder -ge 0) { $RunOrder } else { 'NOT DECLARED' })$apOwnerNote$apNeedsNote)."
    if ($RunOrder -lt 0) { Say '  NOTE: no run order declared. status will refuse to guess what runs next.' }
    exit 0
}

# --------------------------------------------------------------------------- #
'revise-phase' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    Assert-WsNotAbandoned (Find-Node $state $p.ws)

    # A correction is the one write a delivered phase accepts. It appends
    # and exits here, so it can reach none of the writes below, and the scope is never touched: the
    # wrong text stays visible beside its correction. Above the refusal because it is the exception
    # to it, and a call also naming another parameter is refused whole rather than half-applied.
    # On a handed-over phase too, from anyone: it is finished, like a delivered one.
    $rpStage = [string](Get-Prop $p 'stage' '')
    if ($PSBoundParameters.ContainsKey('Correction')) {
        Require-Param $Correction 'Correction'
        if (@('delivered', 'handed-over') -notcontains $rpStage) {
            if ($rpStage -ne 'planned') { Assert-PhaseOwner $proj.Slug $p 'revise' }
            Fail 90 "Phase '$Phase' is not delivered, so its scope is still yours to change: use -Scope. -Correction is for a delivered or handed-over phase."
        }
        if ($Scope -or $Actor -or $Repos -or $Due -or $PromptPath -or $Owner -or $Needs -or $RunOrder -ge 0) {
            Fail 90 "-Correction stands alone. Phase '$Phase' is $rpStage and every other revise-phase parameter still refuses; nothing was stored."
        }
        $corrLog = @(Get-Prop $p 'corrections' @())
        $corrLog += [pscustomobject]@{ at = (Now); text = $Correction }
        Set-Prop $p 'corrections' $corrLog
        Write-State $proj.Slug $state
        Say "Correction appended to $Phase. ($($corrLog.Count) recorded; the scope is unchanged.)"
        exit 0
    }

    Assert-PhaseOpen $proj.Slug $p
    if ($rpStage -eq 'delivered') {
        Fail 90 "Phase '$Phase' is delivered. Its record cites evidence that exists and checks that were run. If delivered work needs redoing, that is a NEW phase whose scope says what it supersedes."
    }
    # While planned, anyone may revise it, its owner included: no work exists yet for a new owner to
    # inherit. Once it has started, only its owner.
    if ($rpStage -ne 'planned') { Assert-PhaseOwner $proj.Slug $p 'revise' }
    if ($Owner) {
        if (-not (Test-SharedProgress $proj.Slug)) { Fail 90 "-Owner is for a project that shares its progress; '$($proj.Slug)' keeps its progress on this machine, so its phases have no owner. Nothing was written." }
        if ($rpStage -ne 'planned') { Fail 90 "Phase '$Phase' is $rpStage, so its owner can no longer change: work has started under them. If they cannot finish it, hand it over: keel-state.ps1 hand-over -Phase $Phase -To <person id> -Detail `"<why>`". Nothing was written." }
        Assert-SpPerson $proj.Slug $Owner 'Owner'
    }
    $rpNeeds = $null
    if ($PSBoundParameters.ContainsKey('Needs')) { $rpNeeds = @(Read-NeedsParam $state $Phase ([string]$p.ws) $Needs $false $proj.Slug) }
    $rpSigBefore = Get-RevisionSig $p 'phase'

    if ($Owner) { Set-Prop $p 'owner' $Owner }
    if ($Scope) { Set-Prop $p 'scope' $Scope }
    if ($Actor) { Assert-Enum $Actor $Actors 'Actor'; Set-Prop $p 'actor' $Actor }
    if ($Repos) {
        $revNames = @(Split-Csv $Repos)
        Assert-ReposDeclared -Proj $proj -RepoNames $revNames
        Set-Prop $p 'repos' $revNames
    }
    if ($Due)   { Assert-Date $Due 'Due'; Set-Prop $p 'due' $Due }
    if ($PromptPath) { Set-Prop $p 'promptPath' $PromptPath }
    if ($RunOrder -ge 0) {
        $clash = @(Get-Phases $state | Where-Object { $_.ws -eq $p.ws -and $_.id -ne $p.id -and (Get-Prop $_ 'runOrder' -1) -eq $RunOrder -and (Get-Prop $_ 'stage' '') -ne 'handed-over' })
        if ($clash.Count -gt 0) { Fail 92 "Run order $RunOrder is already taken in $($p.ws) by '$($clash[0].id)'." }
        Set-Prop $p 'runOrder' $RunOrder
    }
    # The list is replaced whole, each need dated now; 'none' leaves no key, as add-phase does.
    if ($null -ne $rpNeeds) {
        if ($rpNeeds.Count -gt 0) { Set-Prop $p 'needs' $rpNeeds }
        elseif ($null -ne $p.PSObject.Properties['needs']) { $p.PSObject.Properties.Remove('needs') }
    }
    # Revised, for the warning a phase needing this one gets, only when what it is to deliver
    # changed: never by a prompt path alone, or by a revise that sets what was already there.
    if ((Get-RevisionSig $p 'phase') -cne $rpSigBefore) { Set-Prop $p 'revisedAt' (Now) }

    Write-State $proj.Slug $state
    Say "Revised $Phase."
    if ($null -ne $rpNeeds) {
        $rpNeedsText = if ($rpNeeds.Count -gt 0) { (@($rpNeeds | ForEach-Object { $_.id })) -join ', ' } else { 'none' }
        Say "  needs: $rpNeedsText"
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'set-stage' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    Require-Param $Stage 'Stage'; Assert-Enum $Stage $Stages 'Stage'
    if ($Stage -eq 'waiting') { Fail 90 "Use 'set-waiting' for the waiting stage - it needs -WaitingOn and -ReviewOn (charter P19)." }

    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    Assert-PhaseOpen $proj.Slug $p
    Assert-PhaseOwner $proj.Slug $p 'set-stage'
    if ((Get-Prop $p 'stage' '') -eq 'delivered' -and $Stage -ne 'delivered') {
        Fail 90 "Phase '$Phase' is delivered and cannot move backwards."
    }
    Assert-WsNotAbandoned (Find-Node $state $p.ws)
    Set-Prop $p 'stage' $Stage
    if ($Stage -ne 'waiting') { Set-Prop $p 'waitingOn' $null; Set-Prop $p 'reviewOn' $null }
    Write-State $proj.Slug $state
    Say "$Phase -> $Stage"
    exit 0
}

# --------------------------------------------------------------------------- #
'set-waiting' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    if ([string]::IsNullOrWhiteSpace($WaitingOn)) {
        Fail 95 "-WaitingOn is required: name who or what this waits on. 'them' is not a name (charter P19)."
    }
    if ([string]::IsNullOrWhiteSpace($ReviewOn)) {
        Fail 95 "-ReviewOn is required: the date this gets re-checked. A wait with no review date is an abandoned phase wearing a status (charter P19)."
    }
    Assert-Date $ReviewOn 'ReviewOn'

    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    Assert-PhaseOpen $proj.Slug $p
    Assert-PhaseOwner $proj.Slug $p 'set-waiting'
    if ((Get-Prop $p 'stage' '') -eq 'delivered') { Fail 90 "Phase '$Phase' is delivered." }
    Assert-WsNotAbandoned (Find-Node $state $p.ws)

    Set-Prop $p 'stage' 'waiting'
    Set-Prop $p 'waitingOn' $WaitingOn
    Set-Prop $p 'reviewOn' $ReviewOn
    Write-State $proj.Slug $state
    Say "$Phase is waiting on '$WaitingOn', review $ReviewOn."
    exit 0
}

# --------------------------------------------------------------------------- #
'clear-waiting' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    Assert-PhaseOpen $proj.Slug $p
    Assert-PhaseOwner $proj.Slug $p 'clear-waiting'
    if ((Get-Prop $p 'stage' '') -ne 'waiting') { Fail 90 "Phase '$Phase' is not waiting (stage: $(Get-Prop $p 'stage' '?'))." }

    # THE STAGE COMES BACK FROM THE GATES, by record-verdict's own rule. Writing 'planned'
    # here would make a phase that went waiting mid-implementation come back reading as
    # never started. record-verdict is the authority
    # for a phase's stage - it derives it from the gate just recorded, and holds it only
    # while the phase is in $StickyStages, waiting among them - so releasing the wait applies that same rule to the
    # latest recorded gate. That needs no stored "stage before the wait", is right even for
    # a phase whose wait began before this rule existed, and moves with any verdict recorded DURING
    # the wait, which a stored copy would not. What it cannot recover is a stage set by
    # hand with no verdict behind it: 'escalated', or 'grounding' before the first gate.
    $cwStage  = 'planned'
    $cwLatest = $null
    $cwGates  = Get-Prop $p 'gates' $null
    if ($null -ne $cwGates) {
        foreach ($cwG in @($cwGates.PSObject.Properties)) {
            # Format-StateStamp, not a [string] cast: pwsh 7 parses the stored stamp into a
            # DateTime, whose string form does not sort by time across a year boundary.
            if ($null -eq $cwLatest -or (Format-StateStamp (Get-Prop $cwG.Value 'at' $null)) -gt (Format-StateStamp (Get-Prop $cwLatest.Value 'at' $null))) { $cwLatest = $cwG }
        }
    }
    if ($null -ne $cwLatest) {
        $cwVerdict = Get-Prop $cwLatest.Value 'verdict' ''
        $cwStage = if ($PassingVerdicts -contains $cwVerdict) { $GatePassStage[$cwLatest.Name] } else { $GateHoldStage[$cwLatest.Name] }
    }
    Set-Prop $p 'stage' $cwStage
    Set-Prop $p 'waitingOn' $null
    Set-Prop $p 'reviewOn' $null
    Write-State $proj.Slug $state
    if ($null -ne $cwLatest) {
        Say "$Phase is no longer waiting; stage $cwStage, from its latest recorded gate '$($cwLatest.Name)' = $cwVerdict."
    }
    else {
        Say "$Phase is no longer waiting; stage planned, no gate recorded yet."
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'record-verdict' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    Require-Param $Gate 'Gate'
    if ($GateOrder -notcontains $Gate) { Fail 90 "-Gate '$Gate' is not a gate. Expected one of: $($GateOrder -join ', ')." }
    Require-Param $Verdict 'Verdict'
    Assert-Enum $Verdict $GateVerdicts[$Gate] "Verdict (for gate '$Gate')"

    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    Assert-PhaseOpen $proj.Slug $p
    Assert-PhaseOwner $proj.Slug $p 'record a verdict on'
    if ((Get-Prop $p 'stage' '') -eq 'delivered') { Fail 90 "Phase '$Phase' is delivered; its gates are closed." }
    # Both before the stage logic, whose record-gate DONE branch is tested ahead of
    # $StickyStages: left to it, a direct call would deliver an abandoned phase at exit 0.
    # This is that one call. Beneath a live workstream set-stage is still a hand route to
    # the same place.
    if ($Gate -eq 'record' -and $Verdict -eq 'DONE' -and (Get-Prop $p 'stage' '') -eq 'abandoned') {
        Fail 90 "Phase '$Phase' is abandoned and cannot be delivered: $(Get-Prop $p 'abandonedReason' ''). Work that did happen takes a new phase."
    }
    Assert-WsNotAbandoned (Find-Node $state $p.ws)

    # P21 - the enact gate refuses to record without both answers, BEFORE the act.
    if ($Gate -eq 'enact' -and @('DONE', 'DEFERRED') -contains $Verdict) {
        if ([string]::IsNullOrWhiteSpace($Reversible)) {
            Fail 95 "-Reversible none|partial|full is required to record 'enact'. Declared before the act, not discovered after (charter P21)."
        }
        Assert-Enum $Reversible.ToLower() $ReversibleVals 'Reversible'
        if ([string]::IsNullOrWhiteSpace($Observable)) {
            Fail 95 "-Observable yes|no is required to record 'enact'. An irreversible act whose outcome is unobservable holds until it can be observed."
        }
        Assert-Enum $Observable.ToLower() $ObservableVals 'Observable'
        if ($Reversible.ToLower() -eq 'none' -and $Observable.ToLower() -eq 'no' -and $Verdict -eq 'DONE') {
            Fail 95 "Refusing DONE: this act is irreversible AND its outcome is currently unobservable. Record DEFERRED and hold until it can be observed (charter P21)."
        }
    }

    # P3, second fact.
    Test-Contract -State $state -PhaseObj $p -GateName $Gate -VerdictValue $Verdict -Slug $proj.Slug -TcCfg (Read-ProjectConfig $proj.ConfigPath)

    $gates = Get-Prop $p 'gates' $null
    if ($null -eq $gates) { $gates = [pscustomobject]@{}; Set-Prop $p 'gates' $gates }

    $entry = [pscustomobject]@{
        verdict  = $Verdict
        at       = (Now)
        artifact = $(if ($Artifact) { $Artifact } else { $GateArtifacts[$Gate] })
    }
    if ($Gate -eq 'enact') {
        Set-Prop $entry 'reversible' $(if ($Reversible) { $Reversible.ToLower() } else { $null })
        Set-Prop $entry 'observable' $(if ($Observable) { $Observable.ToLower() } else { $null })
    }

    # The verify binding (helpers under 'verify binding'). verify PASS or
    # INCONCLUSIVE stores it; FAIL stores none, and because this entry replaces the
    # gate's old one wholesale, a FAIL after a PASS drops the old binding. human, enact and record
    # compare against it and store 'bindingCheck', ANY verdict. Both run after Test-Contract,
    # so a contract refusal is exactly what it was, and neither can refuse or change the exit
    # code: New-Binding and Compare-Binding never throw, and this try/catch is the second guard.
    # A phase with no 'binding' - verified before bindings existed - runs nothing here.
    $bindNote  = $null
    $bindOld   = $null
    $bindCheck = $null
    try {
        if ($Gate -eq 'verify' -and @('PASS', 'INCONCLUSIVE') -contains $Verdict) {
            $bindNew = New-Binding $proj (Read-ProjectConfig $proj.ConfigPath) $p $Verdict
            Set-Prop $entry 'binding' $bindNew
            if ($bindNew.error) {
                $bindNote = "note: $Phase's verify verdict is recorded, but its binding could not be taken: $($bindNew.error). Later gates will say so."
            }
        }
        elseif ($BindGates -contains $Gate) {
            $bindOld = Get-Prop (Get-Prop $gates 'verify' $null) 'binding' $null
            if ($null -ne $bindOld) {
                $bindCheck = Compare-Binding $bindOld $proj $p
                $bindMovedAll = @($bindCheck.moved)
                $bindErrText = $null
                if ($bindCheck.error) {
                    $bindErrText = [string]$bindCheck.error
                    if ($bindCheck.notTaken) { $bindErrText = "it was not taken at verify ($($bindCheck.error))" }
                }
                # count is null when the comparison could not run, so a failure can never store
                # the value that means "nothing moved".
                Set-Prop $entry 'bindingCheck' ([pscustomobject]@{
                    at    = (Now)
                    count = $(if ($bindCheck.error) { $null } else { $bindMovedAll.Count })
                    moved = @($bindMovedAll | Select-Object -First 10 | ForEach-Object { Format-BindMoved $_ -BdStored })
                    error = $bindErrText
                })
            }
        }
    }
    catch {
        $bindCheck = $null
        if ($Gate -eq 'verify') {
            Set-Prop $entry 'binding' ([pscustomobject]@{ takenAt = (Now); boundTo = $Verdict; folder = @{}; trees = @(); produced = @{}; error = $_.Exception.Message })
            $bindNote = "note: $Phase's verify verdict is recorded, but its binding could not be taken: $($_.Exception.Message). Later gates will say so."
        }
        else {
            $bindNote = "WARNING: could not compare $Phase's verify binding: $($_.Exception.Message). This gate's verdict is recorded regardless."
        }
    }

    Set-Prop $gates $Gate $entry

    # A gate added to $GateOrder without a stage mapping would silently write a null
    # stage, so refuse rather than corrupt the field (charter P4).
    if (-not $GatePassStage.ContainsKey($Gate) -or -not $GateHoldStage.ContainsKey($Gate)) {
        Fail 90 "Gate '$Gate' has no stage mapping. Every gate needs a row in GatePassStage and GateHoldStage."
    }

    # The stage is derived from the gate just recorded, so it cannot drift from the
    # recorded verdicts (charter P10 - one authority per fact). With one call to
    # set-stage at gate 1 as the only writer, every phase would report 'grounding'
    # for its whole life.
    $curStage = Get-Prop $p 'stage' ''
    if ($Gate -eq 'record' -and $Verdict -eq 'DONE') {
        Set-Prop $p 'stage' 'delivered'
    }
    elseif ($StickyStages -contains $curStage) {
        # Hold. See $StickyStages.
    }
    elseif ($PassingVerdicts -contains $Verdict) {
        Set-Prop $p 'stage' $GatePassStage[$Gate]
    }
    else {
        Set-Prop $p 'stage' $GateHoldStage[$Gate]
    }

    Write-State $proj.Slug $state

    # The binding warning lines, before the gate line. Guarded on their own: the
    # verdict is already written, and a printing defect must not turn exit 0 into exit 1.
    try {
        if ($bindNote) { Say $bindNote }
        elseif ($null -ne $bindCheck) { Write-BindGateLines $Phase $bindOld $bindCheck }
    }
    catch {
        try { Say "WARNING: could not print $Phase's binding comparison: $($_.Exception.Message)" } catch { }
    }

    Say "$Phase gate '$Gate' = $Verdict (recorded $(Now))."
    if ($Gate -eq 'record' -and $Verdict -eq 'DONE') { Say "$Phase is DELIVERED." }
    exit 0
}

# --------------------------------------------------------------------------- #
'new-iteration' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    Require-Param $Trigger 'Trigger'
    Assert-Enum $Trigger @('verify', 'human', 'enact', 'plan') 'Trigger'
    Require-Param $Detail 'Detail'

    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    Assert-PhaseOpen $proj.Slug $p
    Assert-PhaseOwner $proj.Slug $p 'loop on'
    Assert-WsNotAbandoned (Find-Node $state $p.ws)
    $n = [int](Get-Prop $p 'iterations' 0)
    $capLifts = @(Get-Prop $p 'capLifts' @())
    $effCap = Get-EffectiveCap $p
    $capText = "cap $effCap"
    if ($capLifts.Count -gt 0) { $capText = "cap ${effCap}: $IterationCap plus $($effCap - $IterationCap) lifted" }

    if ($n -ge $effCap) {
        # Nothing is incremented and nothing is created. P4.
        $capErr = [Console]::Error
        $capErr.WriteLine("KEEL-STATE: CAP-REACHED. $Phase has already looped $n times ($capText). Nothing was incremented. Run set-stage -Stage escalated and hand the accumulated feedback to the human. The cap is this script's verdict, not your memory of how many times you have looped.")

        # What each round found, not only how many there were: the entries this verb
        # wrote below, plus every lift. Ordered by ROUND, never by 'at' - 'at' has one-second
        # resolution, a call takes about half a second, and Sort-Object on 5.1 is not stable.
        # Round k sorts at 2k, a lift recorded after round k at 2k+1, and
        # the second key is the entry's position in its own list, so no two keys tie.
        $capHist = @()
        $fPos = 0
        foreach ($fr in @(Get-Prop $p 'friction' @())) {
            $fPos++
            $frDetail = [string](Get-Prop $fr 'detail' '')
            if ((Get-Prop $fr 'kind' '') -eq 'rework' -and $frDetail -match '^iteration (\d+) triggered by ') {
                $capHist += [pscustomobject]@{ Key = 2 * [int]$Matches[1]; Pos = $fPos; At = (Get-Prop $fr 'at' '?'); Text = $frDetail }
            }
        }
        $lPos = 0
        foreach ($lift in $capLifts) {
            $lPos++
            $after = [int](Get-Prop $lift 'afterIteration' 0)
            $capHist += [pscustomobject]@{ Key = 2 * $after + 1; Pos = $lPos; At = (Get-Prop $lift 'at' '?'); Text = "cap lifted by $(Get-Prop $lift 'rounds' '?') round(s) after round $after on the operator's words: $(Get-Prop $lift 'words' '')" }
        }
        $capErr.WriteLine("KEEL-STATE:   rounds recorded on $Phase, oldest first:")
        if ($capHist.Count -eq 0) { $capErr.WriteLine('KEEL-STATE:     (none recorded)') }
        foreach ($h in @($capHist | Sort-Object -Property Key, Pos)) {
            $capErr.WriteLine("KEEL-STATE:     [$($h.At)] $($h.Text)")
        }
        exit 2
    }

    Set-Prop $p 'iterations' ($n + 1)
    $log = @(Get-Prop $p 'friction' @())
    $log += [pscustomobject]@{ kind = 'rework'; detail = "iteration $($n + 1) triggered by $Trigger`: $Detail"; at = (Now) }
    Set-Prop $p 'friction' $log

    Write-State $proj.Slug $state
    $liftNote = ''
    if ($capLifts.Count -gt 0) { $liftNote = "; cap $IterationCap plus $($effCap - $IterationCap) lifted" }
    Say "$Phase iteration $($n + 1) of $effCap (trigger: $Trigger$liftNote)."
    exit 0
}

# --------------------------------------------------------------------------- #
# The operator lifts ONE phase's cap, on the record. The wrapper cannot verify that
# -Detail holds the operator's words rather than a session's - like confirmEveryAct, that is
# honoured by prose. What this buys is that a lift is dated and visible, rather than a
# counter that silently disagrees with what happened. It consumes no round and changes no stage.
'lift-cap' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    if ([string]::IsNullOrWhiteSpace($Rounds)) { Fail 95 "-Rounds is required for 'lift-cap': how many extra rounds the operator authorised." }
    if ([string]::IsNullOrWhiteSpace($Detail)) { Fail 95 "-Detail is required for 'lift-cap': the operator's own words authorising the rounds. A lift with no words is not on the record." }
    # 1..999. The upper bound only keeps the [int] conversion below from overflowing.
    if ($Rounds -notmatch '^[1-9][0-9]{0,2}$') { Fail 90 "-Rounds '$Rounds' is not a whole number from 1 to 999." }

    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    Assert-PhaseOpen $proj.Slug $p
    Assert-PhaseOwner $proj.Slug $p 'lift the cap of'
    Assert-WsNotAbandoned (Find-Node $state $p.ws)
    $liftStage = Get-Prop $p 'stage' ''
    if (@('delivered', 'abandoned', 'handed-over') -contains $liftStage) { Fail 90 "$Phase is $liftStage. A lift there changes nothing, and would be a misleading record." }

    $used = [int](Get-Prop $p 'iterations' 0)
    $capLifts = @(Get-Prop $p 'capLifts' @())
    $capLifts += [pscustomobject]@{ rounds = [int]$Rounds; afterIteration = $used; words = $Detail; at = (Now) }
    Set-Prop $p 'capLifts' $capLifts
    Write-State $proj.Slug $state

    $effCap = Get-EffectiveCap $p
    Say "$Phase cap lifted by $Rounds round(s) on the record: cap $effCap ($IterationCap plus $($effCap - $IterationCap) lifted), $used used."
    Say "  operator's words: $Detail"
    Say "  A new-iteration refused at the cap recorded nothing: issue it again. An escalated phase resumes at its next record-verdict."
    exit 0
}

# --------------------------------------------------------------------------- #
'note-friction' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    Require-Param $Kind 'Kind'; Assert-Enum $Kind $FrictionKinds 'Kind'
    Require-Param $Detail 'Detail'

    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    $log = @(Get-Prop $p 'friction' @())
    $log += [pscustomobject]@{ kind = $Kind; detail = $Detail; at = (Now) }
    Set-Prop $p 'friction' $log
    Write-State $proj.Slug $state
    Say "Noted $Kind on $Phase. ($($log.Count) friction item(s) recorded for this phase.)"
    exit 0
}

# --------------------------------------------------------------------------- #
'open-question' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    Require-Param $Question 'Question'

    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    $qs = @(Get-Prop $p 'questions' @())
    $qs += [pscustomobject]@{
        question = $Question
        answer   = $(if ($Answer) { $Answer } else { $null })
        resolvedBy = $(if ($Answer) { 'agent' } else { $null })
        at = (Now)
    }
    Set-Prop $p 'questions' $qs
    Write-State $proj.Slug $state
    if ($Answer) { Say "Logged an auto-resolved question on $Phase. It will be re-surfaced at the human gate." }
    else { Say "Logged an open question on $Phase." }
    exit 0
}

# --------------------------------------------------------------------------- #
'abandon' {
    $proj = Resolve-ProjectOrFail -StartPath $Path

    # A workstream that never ran. A workstream already DELIVERED with no delivered phase
    # is accepted, because that state occurs: 'close' could write nothing else.
    # Absorbed-into goes in the reason; nothing would read a field of its own.
    if ($Ws) {
        if ($Phase) { Fail 90 "Name -Ws or -Phase for 'abandon', not both." }
        Assert-WsId $Ws 'Ws'
        Require-Param $Detail 'Detail'
        $state = Read-State $proj.Slug -ForWrite
        $node = Find-Node $state $Ws
        if ($null -eq $node) { Fail 94 "Workstream '$Ws' does not exist." }
        if ($node.role -ne 'workstream') { Fail 93 "'$Ws' is a $($node.role), not a workstream." }
        Assert-WsNotAbandoned $node
        $beneath = @(Get-Phases $state | Where-Object { $_.ws -eq $Ws })
        # A handed-over phase ran, as a delivered one did, so it refuses the same way.
        $beneathDelivered = @($beneath | Where-Object { @('delivered', 'handed-over') -contains (Get-Prop $_ 'stage' '') })
        if ($beneathDelivered.Count -gt 0) {
            Fail 90 "$Ws has delivered or handed-over phase(s) and so did run: $(($beneathDelivered | ForEach-Object { $_.id }) -join ', '). A finished phase's description takes 'revise-phase -Correction'."
        }
        $beneathOpen = @($beneath | Where-Object { (Get-Prop $_ 'stage' '') -ne 'abandoned' })
        if ($beneathOpen.Count -gt 0) {
            Fail 90 "$Ws still has $($beneathOpen.Count) open phase(s): $(($beneathOpen | ForEach-Object { $_.id }) -join ', '). Abandon each with -Phase first, so each keeps its own reason."
        }
        Set-Prop $node 'status' 'ABANDONED'
        Set-Prop $node 'abandonedReason' $Detail
        Set-Prop $node 'abandonedAt' (Now)
        Write-State $proj.Slug $state
        Say "$Ws abandoned: $Detail"
        Say "  goal-coverage no longer counts it, and this cannot be undone: new work takes a new workstream."
        exit 0
    }

    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    Require-Param $Detail 'Detail'
    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    Assert-PhaseOpen $proj.Slug $p
    if ((Get-Prop $p 'stage' '') -eq 'delivered') { Fail 90 "Phase '$Phase' is delivered and cannot be abandoned." }
    if ((Get-Prop $p 'stage' '') -ne 'planned') { Assert-PhaseOwner $proj.Slug $p 'abandon' }
    Assert-WsNotAbandoned (Find-Node $state $p.ws)
    Set-Prop $p 'stage' 'abandoned'
    Set-Prop $p 'abandonedReason' $Detail
    Write-State $proj.Slug $state
    Say "$Phase abandoned: $Detail"
    exit 0
}

# --------------------------------------------------------------------------- #
# A started phase whose owner cannot finish it is not reassigned in place: it ends as 'handed-over'
# and a successor continues it, owned by the person named, at the same run order, from grounding.
# Anyone may run it, since the owner may be the one who left. A shared project only.
'hand-over' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Phase 'Phase'; Assert-PhaseId $Phase
    if (-not (Test-SharedProgress $proj.Slug)) {
        Fail 90 "hand-over is for a project that shares its progress: it hands a phase to another person, and '$($proj.Slug)' keeps its progress on this machine. Nothing was written."
    }
    Require-Param $To 'To'
    Require-Param $Detail 'Detail'
    $state = Read-State $proj.Slug -ForWrite
    $p = Get-PhaseOrFail $state $Phase
    Assert-WsNotAbandoned (Find-Node $state $p.ws)
    $hoStage = [string](Get-Prop $p 'stage' '')
    if ($hoStage -eq 'planned') { Fail 90 "Phase '$Phase' is planned: no work has started, so change its owner instead: keel-state.ps1 revise-phase -Phase $Phase -Owner <person id>. Nothing was written." }
    if ($hoStage -eq 'handed-over') { Fail 90 "Phase '$Phase' was already handed over: $(Get-Prop $p 'handedOverTo' '?') continues it. Hand that one over instead. Nothing was written." }
    if (@('delivered', 'abandoned') -contains $hoStage) { Fail 90 "Phase '$Phase' is $hoStage, so it is finished and there is nothing to hand over. Nothing was written." }
    Assert-SpPerson $proj.Slug $To 'To'

    # The successor's id: the first free letter after this phase's own, so W5.2 is continued by
    # W5.2b, and W5.2b by W5.2c. Folded phases are in state, so their ids count as taken.
    $hoBase = [regex]::Match($Phase, '^W\d+\.\d+').Value
    $hoFrom = if ($Phase -cmatch '[a-z]$') { [int][char]$Phase[$Phase.Length - 1] } else { [int][char]'a' }
    $hoSucc = $null
    for ($hoC = $hoFrom + 1; $hoC -le [int][char]'z'; $hoC++) {
        $hoCand = $hoBase + [string][char]$hoC
        if ($null -eq (Find-Phase $state $hoCand)) { $hoSucc = $hoCand; break }
    }
    if (-not $hoSucc) { Fail 90 "Phase '$Phase' has no free successor id: every letter after its own up to z is taken under $hoBase. Plan the rest as a new phase with add-phase. Nothing was written." }

    $hoNew = [pscustomobject]@{
        id = $hoSucc; ws = $p.ws; scope = $p.scope; actor = (Get-Prop $p 'actor' 'agent')
        runOrder = (Get-Prop $p 'runOrder' -1)
        repos = @(Get-Prop $p 'repos' @())
        due = (Get-Prop $p 'due' $null)
        promptPath = (Get-Prop $p 'promptPath' $null)
        stage = 'planned'
        waitingOn = $null; reviewOn = $null
        iterations = 0
        gates = [pscustomobject]@{}
        friction = @(); questions = @()
        created = (Now)
        owner = $To
        needs = @(Get-Prop $p 'needs' @())
        continues = $Phase
    }
    Set-Prop $p 'stage' 'handed-over'
    Set-Prop $p 'handedOverTo' $hoSucc
    Set-Prop $p 'handOverReason' $Detail
    Set-Prop $p 'waitingOn' $null
    Set-Prop $p 'reviewOn' $null
    $arr = @(Get-Phases $state); $arr += $hoNew; Set-Prop $state 'phases' $arr
    Write-State $proj.Slug $state
    Ensure-Dir (Get-PhaseDir $proj.Slug $hoSucc) | Out-Null

    $hoOrder = Get-Prop $p 'runOrder' -1
    Say "$Phase handed over to $(Get-SpPersonText $proj.Slug $To): $hoSucc continues it from grounding, at run order $(if ($hoOrder -ge 0) { $hoOrder } else { 'NOT DECLARED' }). Reason: $Detail"
    Say "  $Phase is finished. Its artifacts are evidence for $hoSucc to re-measure, never to inherit."
    Say "  Commit and push now, so the new owner sees $hoSucc."
    exit 0
}

# --------------------------------------------------------------------------- #
'close' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Ws 'Ws'; Assert-WsId $Ws 'Ws'
    $state = Read-State $proj.Slug -ForWrite
    $node = Find-Node $state $Ws
    if ($null -eq $node) { Fail 94 "Workstream '$Ws' does not exist." }
    if ($node.role -ne 'workstream') { Fail 93 "'$Ws' is a $($node.role), not a workstream." }
    Assert-WsNotAbandoned $node

    # A handed-over phase is done: its successor carries the work, and is counted in its own right.
    $open = @(Get-Phases $state | Where-Object { $_.ws -eq $Ws -and @('delivered', 'abandoned', 'handed-over') -notcontains (Get-Prop $_ 'stage' '') })
    if ($open.Count -gt 0) {
        Fail 90 "$Ws still has $($open.Count) phase(s) not finished (delivered, handed over or abandoned): $(($open | ForEach-Object { $_.id }) -join ', ')."
    }
    Set-Prop $node 'status' 'DELIVERED'
    Set-Prop $node 'closedAt' (Now)
    Write-State $proj.Slug $state
    Say "$Ws closed. Run keel-close-workstream to route its friction."
    exit 0
}

# --------------------------------------------------------------------------- #
# Signals - the project -> keel improvement queue. Cross-project by design.
# --------------------------------------------------------------------------- #
'signal' {
    $proj = Resolve-ProjectOrFail -StartPath $Path
    Require-Param $Kind 'Kind'; Assert-Enum $Kind $SignalKinds 'Kind'
    Require-Param $Detail 'Detail'

    if ([string]::IsNullOrWhiteSpace($Phase)) {
        Fail 97 "-Phase is required. A signal cites the moment it came from; a signal with no phase behind it is a wish (charter P25)."
    }
    Assert-PhaseId $Phase
    if ([string]::IsNullOrWhiteSpace($Evidence)) {
        Fail 97 "-Evidence is required: the command and its actual output, or a path. A paraphrase is not evidence (charter P25)."
    }

    $state = Read-State $proj.Slug
    [void](Get-PhaseOrFail $state $Phase)

    # P26 - a signal crosses machines, so a quarantine project's evidence must be a
    # REFERENCE, never content. Refused, not warned: a push has no undo.
    $cfg = Read-ProjectConfig $proj.ConfigPath
    $evidenceMode = 'literal'
    if (Test-Quarantine $cfg) {
        $evidenceMode = 'reference'
        $multiline = ($Evidence -match "`n") -or ($Evidence -match "`r")
        if ($multiline -or $Evidence.Length -gt $EvidenceRefMaxChars) {
            Fail 97 ("Project '$($proj.Slug)' has quarantine on, so a signal's evidence must be a REFERENCE, not content: a local path plus a short description, on one line, at most $EvidenceRefMaxChars characters. You supplied $($Evidence.Length) characters" + $(if ($multiline) { ' across multiple lines' } else { '' }) + ". A signal leaves this machine; pasted output from a quarantined project cannot be unsent (charter P23, P26).")
        }
    }

    $sid = Next-SignalId
    $sig = [pscustomobject]@{
        id = $sid
        project = $proj.Slug
        phase = $Phase
        kind = $Kind
        detail = $Detail
        evidence = $Evidence
        evidenceMode = $evidenceMode
        machine = $env:COMPUTERNAME
        keelVersion = (Get-KeelVersion)
        created = (Now)
        state = 'OPEN'
        issue = $null
        issueUrl = $null
        pushedAt = $null
        # The two halves of the outward act 'resolve-signal -CloseIssue' performs, recorded
        # separately as each lands so a failed one can be retried without repeating the other.
        issueCommentedAt = $null
        issueClosedAt = $null
        resolvedAs = $null
        resolution = $null
        resolvedAt = $null
    }
    $sid = Save-NewSignal $sig
    Say "Filed signal $sid ($Kind) from $($proj.Slug) $Phase. Evidence mode: $evidenceMode."
    Say '  This does NOT change keel. It is triaged in a keel session (charter P25).'
    if ($null -ne (Get-SignalsDestination)) {
        Say '  It is LOCAL until pushed. Run: keel-state.ps1 signals-push   (preview, then -Apply)'
    }
    else {
        Say '  It is LOCAL. No report destination is chosen, so it stays on this machine: keel-state.ps1 signals-target -Repo owner/name'
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'signals-target' {
    # Where this machine's signals go. One value per machine, in one file
    # under the state home, written only here (charter P15). Bare prints it; -Repo sets it;
    # -Clear removes it. Nothing here touches the network.
    $stRepoGiven = $PSBoundParameters.ContainsKey('Repo')
    if ($stRepoGiven -and $Clear) { Fail 90 "Pass -Repo owner/name OR -Clear, not both." }

    if ($Clear) {
        if (Test-Path -LiteralPath $SignalsTargetFile) {
            Remove-Item -LiteralPath $SignalsTargetFile -Force
            Say 'Report destination cleared. Signals now stay on this machine until one is chosen.'
        }
        else { Say 'No report destination was set. Nothing changed.' }
        exit 0
    }

    if ($stRepoGiven) {
        # ContainsKey and not a truthiness test: an EMPTY -Repo must refuse, not fall through
        # to the bare branch and report success.
        $stNew = ([string]$Repo).Trim()
        if (-not (Test-RepoSlug $stNew)) {
            Fail 90 "-Repo '$Repo' is not owner/name (for example octo-org/keel-reports). Nothing was changed."
        }
        Ensure-Dir $KeelHome | Out-Null
        Write-TextNoBom $SignalsTargetFile $stNew
        Say "Report destination set: $stNew. 'signals-push -Apply' will create issues there."
        Say "  Stored in $SignalsTargetFile. Change it with -Repo, remove it with -Clear."
        exit 0
    }

    $stShown = Read-SignalsTargetRaw
    if ($stShown -eq '') {
        Say 'No report destination is chosen. Signals stay on this machine until one is: keel-state.ps1 signals-target -Repo owner/name'
    }
    elseif (Test-RepoSlug $stShown) {
        Say "Report destination: $stShown  (stored in $SignalsTargetFile)"
    }
    else {
        Say "The stored destination in $SignalsTargetFile is not owner/name, so it is ignored and nothing is sent. Set it with -Repo owner/name, or remove it with -Clear."
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'signals-push' {
    # Preview by default; -Apply performs the outward write (charter P6).
    #
    # THE DESTINATION IS CHECKED FIRST, before gh is looked for. With none
    # chosen there is nothing a preview could truthfully say ("would become issues on X" has
    # no X), and exit 90 is the code the earlier no-remote refusal returned here, so no
    # caller sees a new code.
    $slug = Get-SignalsDestination
    if ([string]::IsNullOrWhiteSpace($slug)) { Fail 90 $NoDestinationText }
    $gh = Resolve-Gh
    if ($null -eq $gh) {
        Fail 90 'GitHub CLI not found. Looked on PATH and in the standard install locations. Install it, or pass -Repo and push by hand.'
    }

    # With -Apply the store lock is taken before any signal is read, so a judgement or a
    # resolution made meanwhile waits rather than being written over. The preview writes nothing.
    if ($Apply) { Enter-WriteLock $SignalsHome 'the signal store' }
    $pending = @(Get-Signals -Slug '' -FilterKind '' | Where-Object { $_.state -eq 'OPEN' -and $null -eq (Get-Prop $_ 'issue' $null) })

    # -Id scopes the push to ONE signal. Without it the pending set is every unpushed open
    # signal on the machine, across every project - so an operator asking to push one would
    # have to push all or none, and a confirmation naming two signals can cover a third from
    # a project the human has not read.
    #
    # THIS RUNS BEFORE THE 'Nothing to push' EARLY RETURN, and that ordering is the point.
    # Placed after it, 'signals-push -Id <id>' against a fully-pushed store would print
    # 'Nothing to push' and exit 0 - reporting success for a push that did not happen and
    # never naming the signal asked for. Refusals mirror resolve-signal in this same file
    # rather than inventing codes: bad shape / immutable -> 90, unknown -> 94.
    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        if ($Id -notmatch '^S\d{4}$') { Fail 90 "-Id '$Id' is not a signal id. Expected S<nnnn>, e.g. S0007." }
        $sigPath = Join-Path $SignalsHome "$Id.json"
        if (-not (Test-Path -LiteralPath $sigPath)) { Fail 94 "Signal '$Id' does not exist." }
        $sigOne = Read-Json $sigPath
        # An empty or truncated file parses to $null without throwing, so the crash would
        # otherwise land on the first property access below.
        if ($null -eq $sigOne) { Fail 96 "Signal '$Id' did not parse to an object. The file at '$sigPath' is empty or truncated." }
        if ($sigOne.state -ne 'OPEN') { Fail 90 "Signal '$Id' is $($sigOne.state), not OPEN. Only an open signal is pushed." }
        $alreadyIssue = Get-Prop $sigOne 'issue' $null
        if ($null -ne $alreadyIssue) {
            Fail 90 "Signal '$Id' was already pushed as issue #$alreadyIssue on $(Get-Prop $sigOne 'pushedAt' 'an unrecorded date'). A signal is pushed once."
        }
        $pending = @($sigOne)
    }

    if ($pending.Count -eq 0) { Say 'Nothing to push - every open signal already has an issue.'; exit 0 }

    if (-not $Apply) {
        Say "PREVIEW ONLY. $($pending.Count) signal(s) would become issues on $slug. Re-run with -Apply to create them."
        foreach ($s in $pending) {
            $rawLen  = "[signal:$($s.kind)] $($s.detail)".Length
            $shownTitle = Format-IssueTitle $s
            Write-Output ''
            Write-Output "--- $($s.id) ------------------------------------------------------------"
            Write-Output "TITLE: $shownTitle"
            if ($rawLen -gt $IssueTitleMaxChars) {
                Write-Output "       (title truncated to $IssueTitleMaxChars chars from $rawLen - the full text is in the body below)"
            }
            Write-Output "BODY:"
            Write-Output (Format-IssueBody $s)
        }
        Write-Output ''
        Say 'Read the bodies above. Anything from a quarantined project must be a reference, not content.'
        exit 0
    }

    # THE OUTWARD GUARD, and it sits HERE rather than at the pre-flight above.
    # Everything before this line is local: the preview exits 0 without sending a
    # byte, so guarding it would flip a local-only path from proceed to refuse,
    # which the guard must never do - it changes only WHY the outward half
    # is skipped. Everything after this line is the loop that creates issues.
    # It is still after Resolve-Gh and Get-SignalsDestination, so the message below
    # can truthfully say both succeeded.
    $owBlocked = Test-OutwardBlocked
    if ($null -ne $owBlocked) {
        Fail 90 (Get-OutwardBlockedMessage -OwReason $owBlocked `
            -OwCommands @("gh api --method POST repos/$slug/issues") `
            -OwAssurance 'gh WAS found and a destination WAS chosen - this refusal says nothing about either. Nothing was pushed and no signal record was written.')
    }

    $failed = 0
    foreach ($s in $pending) {
        $issueTitle = Format-IssueTitle $s
        $body = Format-IssueBody $s

        # THE TITLE TRAVELS IN A FILE, NOT AS A NATIVE ARGUMENT. Do not "simplify" this
        # back to 'issue','create','--title',$issueTitle. Measured against a .NET receiver
        # parsed by CommandLineToArgvW - the same rules gh's Go runtime uses:
        #   raw --title      : 1/5 titles survive under Windows PowerShell 5.1, 5/5 under pwsh 7.6.3
        #   escaped --title  : 5/5 under 5.1, 1/5 under 7.6.3 (7.x escapes natively, so
        #                      pre-escaping arrives literal) - it would have to be host-conditional
        #   gh api --input   : 5/5 under BOTH
        # 5.1 does not escape a double quote inside a splatted native argument, so a title
        # quoting a status line is split at every quoted word and gh sees stray positionals.
        # A trailing backslash is worse: it escapes the closing quote and swallows the next
        # flag. This vector removes the class by construction - every element below is a
        # flag name, the repo slug, or a temp path, and none of those can contain a quote.
        # gh issue create has no --title-file (checked against gh 2.97.0), which is why this
        # is the api verb rather than the issue verb.
        $payload = [ordered]@{ title = $issueTitle; body = $body }
        $tmp = Join-Path $env:TEMP ("keel-signal-" + $s.id + ".json")
        Write-TextNoBom $tmp ($payload | ConvertTo-Json -Depth 6)

        # --jq keeps gh to two lines. Not cosmetic: the API response echoes the issue BODY,
        # and signal evidence prose can itself contain a github.com/.../issues/<n> URL, which
        # a last-match-wins regex over the whole response would report as the new issue.
        $res = Invoke-Native -Exe $gh -Arguments @('api','--method','POST',"repos/$slug/issues",'--input',$tmp,'--jq','.number,.html_url')

        # THE RECORD IS WRITTEN STRAIGHT AFTER THE POST, BEFORE THE TEMP FILE IS TOUCHED. A
        # cleanup placed here that threw would leave a live issue with no local record of it.
        # Do not move Remove-KeelTempFile above this block.
        if ($res.Code -eq 0) {
            $num = $null
            $urlText = ''
            foreach ($ln in $res.Output) {
                $t = $ln.Trim()
                if ($null -eq $num -and $t -match '^\d+$') { $num = [int]$t }
                elseif ($urlText -eq '' -and $t -match '^https://\S+$') { $urlText = $t }
            }

            Set-Prop $s 'issue' $num
            Set-Prop $s 'issueUrl' $urlText
            Set-Prop $s 'pushedAt' (Now)
            Write-SignalFields (Join-Path $SignalsHome "$($s.id).json") $s @('issue', 'issueUrl', 'pushedAt')
            Say "$($s.id) -> issue #$num  $urlText"
        }

        Remove-KeelTempFile $tmp

        if ($res.Code -ne 0) {
            # One line naming the signal and why - not gh's usage wall, which buries the
            # cause in forty lines of flags. The full text is reproducible by re-running.
            $why = ''
            foreach ($ln in $res.Output) { if (-not [string]::IsNullOrWhiteSpace($ln)) { $why = $ln.Trim(); break } }
            if ($why.Length -gt 160) { $why = $why.Substring(0, 157) + '...' }
            if ([string]::IsNullOrWhiteSpace($why)) { $why = 'no output' }
            [Console]::Error.WriteLine("KEEL-STATE: $($s.id) NOT pushed: gh exited $($res.Code) - $why")
            $failed++
            continue
        }
    }
    # A push that did not happen must not report success to whatever called this. Bare exit:
    # each failure already printed its own line, and a summary line would be a second one.
    if ($failed -gt 0) { exit 99 }
    exit 0
}

# --------------------------------------------------------------------------- #
'adopt-signal' {
    # THE RETURN HALF OF P26. 'signals-push' sends a signal out as a GitHub issue; this
    # brings one back. Without it a signal filed on another machine could be READ here as
    # an issue and not recorded, resolved or closed through the wrapper, because
    # 'resolve-signal' looks its argument up in $SignalsHome and refuses at 94 when there is
    # no file. The only route left would be gh by hand, which is the
    # write-around-the-wrapper P4 and P15 exist to stop - and it closes an issue while keel
    # holds no record of the verdict.
    #
    # THIS ADOPTS INTO THE LOCAL STORE rather than teaching 'resolve-signal' about issues.
    # A second resolution path would have no local record to write a verdict
    # into, which is P3's "the file outranks the conversation" with the file removed. One new
    # verb, zero changes to the four existing ones.
    #
    # THE ORIGIN FIELDS ARE SUPPLIED, NOT PARSED, and that is a measurement rather than a
    # preference. An issue filed by hand need not match Format-IssueBody's shape - one has
    # been seen with no table, machine and version inline, and a date the generated line
    # does not carry. A parser written against the generated shape returns NOTHING on such
    # a case; one written against that prose breaks on the next generated one. Both fail by
    # returning an empty answer without raising - and here that silent-wrong-answer would
    # sit directly in front of a terminal, irreversible resolution. The operator triaging
    # has read the issue.
    Require-Param $Project 'Project'
    Require-Param $Phase   'Phase'
    Require-Param $Kind    'Kind'
    Assert-Enum   $Kind $SignalKinds 'Kind'
    if ($Issue -le 0) {
        Fail 90 "-Issue is required for 'adopt-signal' and must be a positive GitHub issue number, e.g. -Issue 12."
    }
    # Every argument is judged BEFORE the network call. A malformed -Id refused after the fetch
    # is still refused and still writes nothing, but it spends a round trip to say so.
    if ($Id -and $Id -notmatch '^S\d{4}$') {
        Fail 90 "-Id '$Id' is not a signal id. On 'adopt-signal' it is OPTIONAL and records the id this signal carries on the machine that FILED it, e.g. -Id S0007."
    }

    # -Phase is stored as TEXT and never looked up. The originating phase does not exist in any
    # state file on this machine, so Get-PhaseOrFail cannot apply. That exemption is the one
    # guard this verb loosens, and it loosens it for a record type that did not exist before -
    # nothing already stored changes meaning (charter P24). Get-PhaseOrFail itself is untouched.

    # Destination first, as in signals-push: with none chosen this verb
    # has no repo to read the issue from, and it never derives one from a checkout.
    $adSlug = Get-SignalsDestination
    if ([string]::IsNullOrWhiteSpace($adSlug)) { Fail 90 $NoDestinationText }
    $adGh = Resolve-Gh
    if ($null -eq $adGh) {
        Fail 90 'GitHub CLI not found. Looked on PATH and in the standard install locations. Install it, or adopt the issue from a shell where gh resolves.'
    }

    # THE OUTWARD GUARD, at this verb's pre-flight and after both resolvers. Unlike
    # signals-push this verb has no local-only branch to protect: every path from
    # here reaches the issue view below, so the pre-flight IS the outward point.
    $adBlocked = Test-OutwardBlocked
    if ($null -ne $adBlocked) {
        Fail 90 (Get-OutwardBlockedMessage -OwReason $adBlocked `
            -OwCommands @("gh issue view $Issue --repo $adSlug") `
            -OwAssurance 'gh WAS found and a destination WAS chosen - this refusal says nothing about either. No local record was written.')
    }

    # The store lock first, so the scan below and the write at the end are one step: two
    # adoptions of one issue at once would otherwise both pass the scan.
    Enter-WriteLock $SignalsHome 'the signal store'

    # REFUSE A SECOND RECORD FOR ONE ISSUE, BEFORE the network call. This covers two cases with
    # one test: re-adopting an issue already adopted, and adopting an issue keel ITSELF pushed
    # from a local signal - which would otherwise let two different resolutions be written for
    # one issue, with nothing to say which is keel's answer.
    foreach ($adExisting in @(Get-Signals -Slug '' -FilterKind '')) {
        if ((Get-Prop $adExisting 'issue' $null) -eq $Issue) {
            Fail 90 "Issue #$Issue is already held here as signal $($adExisting.id) (project $($adExisting.project), state $($adExisting.state)). One issue, one local record - adopting it again would let two resolutions be written for it."
        }
    }

    # Read through Invoke-Native so the EXIT CODE decides. gh writes progress and even success
    # text to stderr, and a bare 2>&1 under $ErrorActionPreference = 'Stop' turns that into a
    # terminating error on a call that worked. A nonexistent number exits 1 with a GraphQL
    # resolution error, so the exit code carries it.
    $adFetch = Invoke-Native -Exe $adGh -Arguments @('issue','view',"$Issue",'--repo',$adSlug,'--json','number,title,state,url')
    if ($adFetch.Code -ne 0) {
        Fail 90 "Could not read issue #$Issue on $($adSlug): gh exited $($adFetch.Code). Nothing was written. gh said: $($adFetch.Text)"
    }
    $adIssue = $null
    try { $adIssue = $adFetch.Text | ConvertFrom-Json } catch { $adIssue = $null }
    # An empty response parses to $null WITHOUT throwing, so the try/catch above is not enough
    # and the crash would land later on the first property access.
    if ($null -eq $adIssue -or $null -eq (Get-Prop $adIssue 'number' $null)) {
        Fail 90 "Issue #$Issue on $($adSlug) returned no readable JSON. Nothing was written. gh said: $($adFetch.Text)"
    }

    $adTitle = [string](Get-Prop $adIssue 'title' '')
    $adState = [string](Get-Prop $adIssue 'state' 'UNKNOWN')
    $adUrl   = [string](Get-Prop $adIssue 'url' '')

    # The local id comes from THIS machine's counter, and that is settled by measurement rather
    # than by choosing: an originating id can already be occupied here, by another project's
    # signal with a terminal resolution recorded. Writing a
    # foreign signal under the origin's id would overwrite a recorded terminal resolution
    # through a door resolve-signal's own guard does not watch. The correspondence is kept in
    # 'origin' instead, and the ISSUE NUMBER is the common key across machines (P26).
    $adId = Next-SignalId

    # EVIDENCE IS A REFERENCE, NOT A COPY. An issue body is editable on GitHub, so a copy taken
    # now diverges from it silently and nothing detects that - one fact, two homes (P10).
    # Reference-mode evidence is also what P26 already requires of a quarantined project, so
    # this is keel's established shape for the problem rather than a new one.
    $adSig = [pscustomobject]@{
        id = $adId
        project = $Project
        phase = $Phase
        kind = $Kind
        detail = $adTitle
        evidence = "$adUrl - GitHub issue #$Issue on $adSlug, filed from another keel instance. The report body is on the issue."
        evidenceMode = 'reference'
        machine = $env:COMPUTERNAME
        keelVersion = (Get-KeelVersion)
        created = (Now)
        state = 'OPEN'
        # Set from birth. This is what excludes an adopted record from 'signals-push', whose
        # pending set is OPEN signals with no issue - no new code causes that, and a test
        # measures it rather than assuming it.
        issue = $Issue
        issueUrl = $adUrl
        pushedAt = $null
        issueCommentedAt = $null
        issueClosedAt = $null
        resolvedAs = $null
        resolution = $null
        resolvedAt = $null
        # The block that makes the record foreign. No stored record has it, so every existing
        # row renders exactly as it does today (charter P24).
        origin = [pscustomobject]@{
            id = $null
            machine = $null
            project = $Project
            phase = $Phase
            issueTitle = $adTitle
            issueState = $adState
            adoptedAt = (Now)
        }
    }
    if ($Id) { $adSig.origin.id = $Id }
    if ($Name) { $adSig.origin.machine = $Name }

    $adId = Save-NewSignal $adSig
    Say "Adopted issue #$Issue as $adId ($Kind) from $Project $Phase. The issue is $adState on $adSlug."
    Say "  This record is FOREIGN: it was filed on another machine and is marked '<' in 'signals'."
    Say "  It is excluded from 'signals-push' - it already has an issue and was never pushed from here."
    Say "  Triage it as any other signal: keel-state.ps1 resolve-signal -Id $adId -As <PROMOTED|REJECTED|UNREPRODUCIBLE> -Detail '<why>' -CloseIssue"
    Say "  A PROMOTED verdict also needs -Addresses defect|instance. 'instance' leaves it OPEN and does not close the issue."
    exit 0
}

# --------------------------------------------------------------------------- #
'judge-signal' {
    # A SIGNAL READ, BELIEVED AND CONSCIOUSLY NOT SCHEDULED NEEDS A REPRESENTATION. Without
    # this verb its state is OPEN - byte-identical to a signal nobody has ever opened - so a
    # planner can re-judge signals that were already judged, invisibly, because the queue
    # carries no judgement for a planner to read.
    #
    # WHY A NEW VERB AND NOT A WIDENING OF resolve-signal. Charter P12 defaults to no
    # new verb, so this is the answer that had to be argued rather than the one that
    # needed a case. THREE things in that verb turn on -As: its own enum, the issue-close
    # retry guard which compares -As against the stored resolvedAs, and the -Addresses
    # requirement firing on PROMOTED. A fourth value would have to be made legal on all
    # three, and would then appear in that verb's own refusal text beside three verdicts
    # that END a signal - a mandatory answer whose name asserts something the code does
    # not do. adopt-signal was ADDED rather than teaching resolve-signal about issues, for
    # exactly this trade. What that bought THERE was one new verb and zero changes to the
    # four existing ones. It does NOT buy that here, and the difference is worth stating
    # rather than borrowing the slogan: adding this verb also changed resolve-signal's
    # terminal branch and the signals renderer. What it does buy is the thing charter P24
    # actually asks for - no existing INVOCATION changes behaviour and no stored record is
    # migrated, because both additions are read through Get-Prop with a default.
    #
    # NOTHING HERE CAN EXPRESS A VERDICT DERIVED FROM ELAPSED TIME OR ELAPSED
    # WORKSTREAMS, and that is a constraint rather than an omission. A sunset under which
    # a signal became REJECTED at the close of the next workstream touching a named path
    # was tried: both of its sunsets fired, and BOTH signals were still live when
    # re-measured, so the device would have marked two real defects declined. The operator
    # overruled it. A third value along the lines of LAPSED is FORBIDDEN, not merely
    # unnecessary: a design that lets the sunset be expressed is a failed design.
    $proj = Resolve-ProjectOrFail -StartPath $Path

    Require-Param $Id 'Id'
    if ($Id -notmatch '^S\d{4}$') { Fail 90 "-Id '$Id' is not a signal id. Expected S<nnnn>, e.g. S0007." }

    # -Phase REFUSES AT 97 AND NOT 95, and the code is chosen rather than defaulted. 95
    # is 'a mandatory answer was not supplied' and was the first choice - but the
    # 'signal' verb already answers a missing -Phase on this same store with 97, and the
    # sentence it prints there makes the same argument: deprioritisation is an act with an
    # author. One omission, one code. Note the neighbouring
    # -As and -Detail refuse at 90 for the mirror reason: resolve-signal refuses those
    # two through Require-Param at 90, and two verbs writing one record type must not
    # answer the same omission with two different codes.
    if ([string]::IsNullOrWhiteSpace($Phase)) {
        Fail 97 "-Phase is required. A judgement is an act with an AUTHOR: it records which phase read this signal and reached a verdict, which is exactly what distinguishes it from an inference drawn from elapsed workstreams (charter P25)."
    }
    Assert-PhaseId $Phase

    Require-Param $As 'As'
    # THE SET IS CLOSED AT TWO AND WRITTEN INLINE, matching resolve-signal, which writes
    # its own three-value set inline. $AddressesVals is a constant because TWO verbs now
    # share it; this set has one consumer, so a constant for it would be a new named
    # thing where the established local pattern does the job (charter P12).
    #
    # WHAT THESE TWO VALUES MEAN IS DEFINED IN EXACTLY ONE PLACE: the lines this verb
    # PRINTS - the success line below, and the legend the signals verb prints, which
    # agree with each other. Do not restate either meaning here, and do not quote it:
    # a copy is a second authority (charter P10), and it is the copy that goes stale.
    #
    # DEPRIORITISED exists because a signal deprioritised must be told apart from one disproved.
    # CONFIRMED exists because triage is not only about deferrals: in the triage passes
    # measured, most verdicts were not deferrals, so a trail able to record only deferrals
    # would leave the majority of a triage pass unrecorded. Both of those say why a value EXISTS, not
    # what it MEANS, which is why they stay.
    #
    # A GLOSS OF CONFIRMED WRITTEN HERE ONCE DISAGREED with the printed one - it declined to
    # make a scheduling call where the printed line does make one, so the two selected
    # different verdicts for the same signal. The copy diverged from the original inside the
    # change that created both, which is why neither meaning is restated here.
    $judgedAs = $As.ToUpper()
    Assert-Enum $judgedAs @('DEPRIORITISED', 'CONFIRMED') 'As'

    # -ReviewOn IS REQUIRED ON DEPRIORITISED AND PERMITTED ON CONFIRMED, and the asymmetry
    # is the same one resolve-signal already carries for -Addresses: required on PROMOTED,
    # refused on the two verdicts with no fix whose scope could be named. Here the two
    # verdicts assert OPPOSITE things about scheduling. For DEPRIORITISED the absence of a
    # return date IS the defect - the verdict says nothing is carrying this signal, and
    # without a date nothing ever will. For CONFIRMED the verdict says the queue is already
    # carrying it, so a date is a useful annotation rather than a missing answer.
    #
    # THE CITED FAILURE charter P24 asks for, because this TIGHTENS a contract: a batch of
    # DEPRIORITISED judgements, none scheduling a return and none moved since. Such a
    # verdict is indistinguishable in its CONSEQUENCES from dropping the signal quietly -
    # the record is honest and nothing acts on it.
    #
    # THE MIGRATION IS A READ, NOT A WRITE. No stored record is touched: existing judgements
    # keep the keys they have, and a DEPRIORITISED judgement with no reviewOn reads as
    # UNSCHEDULED rather than as due - see Get-ReviewState. Backfilling a date onto a verdict
    # nobody re-read is forbidden outright.
    #
    # 95 AND NOT 90, and the code is chosen rather than defaulted. set-waiting already answers
    # this exact omission - a missing -ReviewOn - with 95, and the rule the neighbouring
    # refusals above are built on decides the tie: two verbs writing one record type must not
    # answer the same omission with two different codes. Routing it through Require-Param
    # would be one line shorter and would refuse at 90, making a missing review date
    # indistinguishable from a malformed -Id.
    if ($judgedAs -eq 'DEPRIORITISED' -and [string]::IsNullOrWhiteSpace($ReviewOn)) {
        Fail 95 "-ReviewOn is required for a DEPRIORITISED judgement: the date this signal gets looked at again. A deferral with no return date is a signal dropped quietly, which is what this verdict exists NOT to be (CHARTER.md P5)."
    }
    # Validated whichever verdict it accompanies, so a bad date on a CONFIRMED judgement is
    # refused too. A review date in the PAST is deliberately accepted, exactly as set-waiting
    # accepts one: refusing it would be a new refusal with no cited failure (charter P13), and
    # the failure mode is self-correcting - a past date makes the judgement due immediately,
    # which is visible rather than silent.
    if (-not [string]::IsNullOrWhiteSpace($ReviewOn)) { Assert-Date $ReviewOn 'ReviewOn' }

    Require-Param $Detail 'Detail'

    # -Addresses is OPTIONAL here, and validated against the EXISTING constant rather
    # than a new one, so a triage that reaches a provisional classification can record
    # it before any fix exists.
    $judgedAddresses = ''
    if (-not [string]::IsNullOrWhiteSpace($Addresses)) {
        Assert-Enum $Addresses.ToLower() $AddressesVals 'Addresses'
        $judgedAddresses = $Addresses.ToLower()
    }

    # THE PHASE IS VALIDATED, NOT MERELY STORED AS TEXT - the one place this verb is
    # stricter than an existing one. adopt-signal deliberately stores its -Phase as text
    # and never looks it up, because the originating phase exists on another machine.
    # Here the judging phase is local by construction: triage happens in a keel session,
    # in a keel project. So Get-PhaseOrFail applies exactly as it does on 'signal', and
    # the consequence is that this verb refuses at 91 outside a project folder. That is
    # a new refusal on a NEW verb, so no existing invocation changes (charter P24).
    $jgState = Read-State $proj.Slug
    [void](Get-PhaseOrFail $jgState $Phase)

    $jgPath = Join-Path $SignalsHome "$Id.json"
    Enter-WriteLock $SignalsHome 'the signal store'
    if (-not (Test-Path -LiteralPath $jgPath)) { Fail 94 "Signal '$Id' does not exist." }
    Save-ReadSha $jgPath
    $jgSig = Read-Json $jgPath
    # An empty or truncated file parses to $null without throwing, so the crash would
    # otherwise land on the first property access below.
    if ($null -eq $jgSig) { Fail 96 "Signal '$Id' did not parse to an object. The file at '$jgPath' is empty or truncated." }

    # A TERMINAL SIGNAL IS REFUSED. It already carries its verdict, and annotating one
    # would stand a judgement beside a settled answer - two authorities on one question
    # (charter P10). Note what is NOT refused: a trail collected while the signal was
    # open still prints after it resolves. What cannot happen is a new judgement
    # arriving afterwards.
    if ($jgSig.state -ne 'OPEN') {
        Fail 90 "Signal '$Id' is $($jgSig.state), not OPEN. A judgement records that an OPEN signal was read and believed; one that has reached a terminal verdict already carries its answer."
    }

    # THE @() RE-WRAP IS LOAD-BEARING. ConvertFrom-Json unrolls a
    # one-element JSON array to a bare object, so a second call would otherwise be
    # appending to a scalar and .Count would throw under strict mode.
    #
    # IT APPENDS RATHER THAN REPLACES, built the way resolve-signal's instanceFixes
    # branch is built and for the same reason. A judgement can happen to the same signal
    # more than once - triage passes look at overlapping populations - so a scalar
    # judgedAs/judgedAt/judgedBy triple would silently overwrite the first, which is the
    # failure that branch's own comment records.
    #
    # DEPTH 3 FROM THE RECORD ROOT, deliberately: test-outward-guard.ps1's %TEMP%
    # fixture round-trips a whole signal record through ConvertTo-Json -Depth 14 at
    # every push, and a value nesting deeper than that would be truncated there.
    # instanceFixes already passes through that same fixture at the same depth.
    $jgTrail = @(Get-Prop $jgSig 'judgements' @())
    $jgAt = (Now)
    # AN ORDERED MAP RATHER THAN ONE LITERAL PER COMBINATION. One literal per combination,
    # chosen by an if, needs two literals for one optional key, four for two and eight for
    # three, and every copy has to be kept in step by hand. [ordered] preserves insertion
    # order through the [pscustomobject] cast, so the stored key order is at, phase, as,
    # addresses?, reviewOn?, detail - and a record carrying NEITHER optional key serialises
    # byte-identically to the one-literal form (verified under Windows PowerShell 5.1: both
    # forms give {"at":..,"phase":..,"as":..,"detail":..}).
    #
    # EACH OPTIONAL KEY IS WRITTEN ONLY WHEN AN ANSWER WAS SUPPLIED: an empty 'addresses' is
    # not a fact about the judgement, and a later query filtering on the field would have to
    # strip it. The same reasoning governs 'reviewOn', which is absent rather than empty on
    # a CONFIRMED judgement given no date.
    $jgOrdered = [ordered]@{ at = $jgAt; phase = $Phase; as = $judgedAs }
    if ($judgedAddresses -ne '') { $jgOrdered['addresses'] = $judgedAddresses }
    if (-not [string]::IsNullOrWhiteSpace($ReviewOn)) { $jgOrdered['reviewOn'] = $ReviewOn }
    $jgOrdered['detail'] = $Detail
    $jgEntry = [pscustomobject]$jgOrdered
    $jgTrail += $jgEntry
    Set-Prop $jgSig 'judgements' $jgTrail
    Write-GuardedJson $jgPath $jgSig

    Say "Signal $Id judged $judgedAs by $Phase. It STAYS OPEN: $Detail"
    Say "  $($jgTrail.Count) judgement(s) now recorded. This is NOT a terminal verdict, and no issue is closed."
    if ($judgedAs -eq 'DEPRIORITISED') {
        Say '  DEPRIORITISED = judged real and consciously not scheduled. A later triage reads this instead of re-deriving it.'
    }
    else {
        Say '  CONFIRMED = judged real and still queued. Re-judge it only where the surface it names has moved.'
    }
    # ECHOED FOR BOTH VERDICTS, because the date is STORED for both. Echoed only inside the
    # DEPRIORITISED branch, it would give an operator who dated a CONFIRMED judgement no
    # confirmation of the value they had just written down - a silent write is the one
    # thing this verb's own success lines exist to prevent.
    if (-not [string]::IsNullOrWhiteSpace($ReviewOn)) {
        Say "  Review on $ReviewOn. This does NOT close anything: the date re-raises the signal, it never resolves it (CHARTER.md P5)."
    }
    exit 0
}

# --------------------------------------------------------------------------- #
'signals' {
    $filterKind = ''
    if ($Kind) { Assert-Enum $Kind $SignalKinds 'Kind'; $filterKind = $Kind }

    # -Id SCOPES THE LISTING TO ONE SIGNAL. A flag this arm did not read would be inert
    # rather than merely unfiltered: 'signals -Id <id>' would print every row, byte for byte
    # what 'signals' prints, and accept a malformed id at exit 0 - while that is the command
    # a reader reaches for to observe one signal. Scoping rather than refusing the flag,
    # because the command a reader reaches for to look at one signal should show that signal.
    #
    # THE REFUSALS MIRROR signals-push -Id in this same file, message for message: bad shape
    # -> 90, no record -> 94. The id is looked up in the store directly rather than in the
    # filtered population, so an id that exists but is excluded by -Kind or -Project is not
    # reported as missing - it yields an empty listing, which is what the filters asked for.
    #
    # CHARTER P24: refusing a malformed id is a TIGHTENING, and it shipped with its cited
    # failure rather than on its own. Nothing is migrated because nothing is stored: this
    # changes what a call prints, not any record. A well-formed id prints its one signal,
    # which is what the caller asked for.
    $sigOnlyId = ''
    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        if ($Id -notmatch '^S\d{4}$') { Fail 90 "-Id '$Id' is not a signal id. Expected S<nnnn>, e.g. S0007." }
        if (-not (Test-Path -LiteralPath (Join-Path $SignalsHome "$Id.json"))) { Fail 94 "Signal '$Id' does not exist." }
        $sigOnlyId = $Id
    }
    $all = @(Get-Signals -Slug $Project -FilterKind $filterKind)
    if ($sigOnlyId -ne '') { $all = @($all | Where-Object { $_.id -eq $sigOnlyId }) }
    $open = @($all | Where-Object { $_.state -eq 'OPEN' })

    if ($all.Count -eq 0) { Say 'No signals.'; exit 0 }

    # COMPUTED BEFORE ANY EARLY EXIT, because all three modes print these two numbers and
    # two of the three exit before the row loop. -Cluster is the mode that matters most
    # here: it is the command scripts/keel-session-start.ps1 NAMES in its nudge, so an
    # operator told that N deferrals are due lands in a listing that would otherwise show
    # neither the due count nor a single UNSCHEDULED marker - the nudge would advertise a
    # figure its own suggested command could not display.
    $sigToday  = [datetime]::ParseExact((Get-Date -Format 'yyyy-MM-dd'), 'yyyy-MM-dd', $null)
    $jgDue     = @($open | Where-Object { (Get-SignalReviewState -Signal $_ -Today $sigToday) -eq 'due' })
    $jgUnsched = @($open | Where-Object { (Get-SignalReviewState -Signal $_ -Today $sigToday) -eq 'unscheduled' })

    # WORDING IS LOAD-BEARING. scripts/keel-session-start.ps1 reads the number out of this
    # line with the pattern '(\d+)\s+deprioritised signal\(s\) DUE', so the digits, the word
    # 'deprioritised', the '(s)' and the upper-case DUE all have a reader outside this file.
    # Two files kept in step by nothing but a test, which is why this comment sits at every
    # site that prints the line. scripts/test-signal-judgement.ps1 guards it from both ends:
    # its row P26 runs the hook itself against a scratch store and fails if the hook's parse
    # stops reading this line, and its Get-ReviewCounts reads the line with a LONGER pattern
    # that begins with the hook's, so a wording change after the word DUE fails the suite's
    # count rows while leaving the hook untouched.
    #
    # PRINTED IN EVERY MODE, so the operator meets the same two numbers wherever they look
    # and the hook always has a line to parse. A zero here is a real reading - it says the
    # queue is scheduled - which is not the same fact as a missing line.
    $sigReviewLine = "$($jgDue.Count) deprioritised signal(s) DUE for review; $($jgUnsched.Count) unscheduled (no return date)."

    if ($Cluster) {
        # P25 promotes a DEFECT seen by two projects. Kind is a bucket, not a defect:
        # three unrelated gaps from two projects is n=1 three times, and reading that as
        # 'ACTS - n=2 reached' would be a triage instrument returning a verdict its data
        # does not support. Whether two signals are the SAME defect is a judgement
        # no clustering on 'kind' can make, so it is handed back rather than guessed.
        Say "Clustered by kind. Kind is a bucket, not a defect - promotion under P25 is judged per DEFECT."
        $needsJudging = $false
        foreach ($k in $SignalKinds) {
            $ofKind = @($open | Where-Object { $_.kind -eq $k })
            if ($ofKind.Count -eq 0) { continue }
            $projects = @($ofKind | ForEach-Object { $_.project } | Sort-Object -Unique)
            $acts = if (@('unsafe', 'refusal') -contains $k) { 'ACTS at n=1 - this kind never waits' }
                    elseif ($projects.Count -lt 2) { 'holds - one project, so every signal here is n=1' }
                    else { $needsJudging = $true; 'JUDGE PER DEFECT - see below' }
            Write-Output ("  {0,-10} {1,2} open across {2} project(s): {3}   [{4}]" -f $k, $ofKind.Count, $projects.Count, ($projects -join ', '), $acts)
        }
        if ($needsJudging) {
            Write-Output ''
            Say "More than one project filed that kind, which is NOT the same as one defect reaching n=2."
            Say "Read them with 'signals' and decide per defect: two signals describing the SAME defect"
            Say "promote; unrelated ones are still n=1 each and need an argued exception (charter P25)."
        }
        Write-Output ''
        Say $sigReviewLine
        exit 0
    }

    # Push state is shown, not merely stored. With a bare '*' on every OPEN row and no
    # issue number, a signal pushed days ago and one that had never left this machine
    # would render identically, and an operator would be told a signal was local when it
    # had already been pushed.
    # The MARK and the NUMBER both carry it: a mark alone says "these differ" without
    # saying the thing the operator actually needs, which is the issue number.
    $unpushedOpen = @($open | Where-Object { $null -eq (Get-Prop $_ 'issue' $null) })

    # -Brief IS THE MACHINE-READABLE FACE, for scripts/keel-session-start.ps1. It prints the
    # two summary lines and NO rows and NO legend, which is what makes it cheap enough to run
    # in every session the hook runs it in: the rows run to hundreds of lines and the hook needs two
    # numbers. It is placed after -Cluster so the two switches cannot interleave.
    if ($Brief) {
        Say "$($open.Count) open of $($all.Count) total; $($unpushedOpen.Count) open signal(s) not yet pushed."
        Say $sigReviewLine
        exit 0
    }

    foreach ($s in $all) {
        $issueNum = Get-Prop $s 'issue' $null
        # FOREIGN IS TESTED FIRST, and it has to be. An adopted record is open and carries an
        # issue, so without this branch it renders '*' - identical to a signal filed here and
        # pushed, which is the one thing a triaging operator must not confuse it with. The test
        # is Get-Prop on a property no stored record has, and Get-Prop returns its default for
        # a missing property, so every existing row takes the branch it takes today (P24).
        $isForeign = $null -ne (Get-Prop $s 'origin' $null)
        $mark = if ($isForeign) { '<' } elseif ($s.state -ne 'OPEN') { ' ' } elseif ($null -eq $issueNum) { '!' } else { '*' }
        $pushCol = if ($null -eq $issueNum) { 'LOCAL' } else { "#$issueNum" }
        Write-Output ("{0}{1}  {2,-6} {3,-9} {4,-16} {5,-9} {6}" -f $mark, $s.id, $pushCol, $s.kind, $s.project, $s.phase, $s.detail)
        # THE TRAIL PRINTS WHATEVER THE STATE, and the terminal line prints under it.
        # Rendering the trail only while the record is OPEN would erase every instance fix
        # from the listing at the exact moment the defect was finally resolved - so a later
        # reader would see a clean single resolution and could not tell that the defect had
        # taken several attempts. Existing rows are untouched: Get-Prop returns
        # its default for a property no stored record has (charter P24), so a record with
        # no trail prints exactly what it printed before.
        foreach ($fx in @(Get-Prop $s 'instanceFixes' @())) {
            Write-Output ("      INSTANCE FIXED {0}: {1}" -f (Get-Prop $fx 'at' '?'), (Get-Prop $fx 'detail' ''))
        }
        # THE JUDGEMENT TRAIL SITS AFTER THE INSTANCE-FIX TRAIL AND BEFORE THE TERMINAL
        # LINE, and the order is a decision rather than an accident. The terminal line
        # stays last because every stored record that has one already prints it there,
        # and moving it would change a rendered row - the P24 violation this whole
        # change is shaped to avoid. INSTANCE FIXED keeps its position because it is the
        # trail stored records actually carry, so appending after it leaves those rows
        # byte-identical. Both trail lines
        # carry their own 'at', so a reader needing true chronology has it on the line.
        #
        # THE VERDICT COMES BEFORE THE TIMESTAMP so that a reader scanning a long
        # listing meets the word that matters at a fixed column - the same reason
        # INSTANCE FIXED leads its own line.
        #
        # EVERY EXISTING ROW IS UNTOUCHED because this reads through Get-Prop with a
        # default, and Get-Prop returns that default for a property no stored record
        # has. That was measured, not predicted: the records in the store that carry no
        # instanceFixes already take exactly this branch on every listing (charter P24).
        foreach ($jg in @(Get-Prop $s 'judgements' @())) {
            $jgScope = Get-Prop $jg 'addresses' ''
            $jgSuffix = if ($jgScope -ne '') { " ($jgScope)" } else { '' }
            # THE REVIEW SUFFIX IS APPENDED, NEVER INSERTED, so every column to its left stays
            # where it is and a judgement carrying no date renders exactly what it rendered
            # before. It reads its state from Get-ReviewState rather than re-testing the
            # fields, because the count below reads the same rule and two copies of it would
            # be free to disagree.
            $jgOn = Get-Prop $jg 'reviewOn' ''
            $jgReview = switch (Get-ReviewState -Judgement $jg -Today $sigToday) {
                'due'         { " review $jgOn DUE" }
                'scheduled'   { " review $jgOn" }
                'unscheduled' { ' UNSCHEDULED' }
                default       { '' }
            }
            Write-Output ("      JUDGED {0} {1} {2}{3}{4}: {5}" -f (Get-Prop $jg 'as' '?'), (Get-Prop $jg 'at' '?'), (Get-Prop $jg 'phase' '?'), $jgSuffix, $jgReview, (Get-Prop $jg 'detail' ''))
        }
        if ($s.state -ne 'OPEN') {
            # The scope suffix is OPTIONAL and appears only where the record carries the
            # key, which older records do not. Guarded on non-empty rather than on presence,
            # so a record written by some future path that does store '' still renders the
            # plain line.
            $rsScope = Get-Prop $s 'addresses' ''
            $rsSuffix = if ($rsScope -ne '') { " ($rsScope)" } else { '' }
            Write-Output ("      {0}{1}: {2}" -f $s.state, $rsSuffix, (Get-Prop $s 'resolution' ''))
        }
    }
    Write-Output ''
    Write-Output "  ! = open, LOCAL - never pushed, exists only on this machine"
    Write-Output "  * = open, pushed as the issue number shown"
    Write-Output "  < = FOREIGN - filed on another machine, adopted here from the issue shown"
    Write-Output "  INSTANCE FIXED = an occurrence was repaired while the DEFECT still stood"
    Write-Output "  JUDGED = read and judged with NO terminal verdict - the signal is still open"
    Write-Output "  DEPRIORITISED = judged real and consciously not scheduled; CONFIRMED = judged real, still queued"
    Write-Output "  UNSCHEDULED = deprioritised with no return date; 'review <date>' = when it is read again; DUE = that date has arrived"
    Say "$($open.Count) open of $($all.Count) total; $($unpushedOpen.Count) open signal(s) not yet pushed."
    Say $sigReviewLine
    exit 0
}

# --------------------------------------------------------------------------- #
'resolve-signal' {
    Require-Param $Id 'Id'
    if ($Id -notmatch '^S\d{4}$') { Fail 90 "-Id '$Id' is not a signal id. Expected S<nnnn>, e.g. S0007." }
    Require-Param $As 'As'
    Assert-Enum $As.ToUpper() @('PROMOTED', 'REJECTED', 'UNREPRODUCIBLE') 'As'
    Require-Param $Detail 'Detail'
    $asUpper = $As.ToUpper()

    $sp = Join-Path $SignalsHome "$Id.json"
    Enter-WriteLock $SignalsHome 'the signal store'
    if (-not (Test-Path -LiteralPath $sp)) { Fail 94 "Signal '$Id' does not exist." }
    Save-ReadSha $sp
    $sig = Read-Json $sp

    # THE TERMINAL STATE IS STILL WRITTEN BEFORE gh IS CALLED. That ordering is deliberate -
    # the resolution is keel's own record and must survive a network that is not there. A
    # guard that refused EVERY second call would leave a resolution whose issue-close half
    # failed as a resolved signal, an open issue, and no supported route between them.
    #
    # The guard is NARROWED, NOT REMOVED, and the difference matters. Deleting it
    # would let a second call silently overwrite a recorded resolution, which is worse than
    # the defect it repairs. A second call is admitted only when ALL FOUR hold: -CloseIssue
    # was given, the recorded verdict matches the one supplied, an issue exists, and keel has
    # no record of having closed it. Each failure keeps its own message so the caller is told
    # which limb refused (charter P4 - fix the input, do not argue with the exit code).
    $isRetry = $false
    if ($sig.state -ne 'OPEN') {
        $already = "Signal '$Id' is already $($sig.state). Signals reach a terminal state once."
        if (-not $CloseIssue) {
            Fail 90 "$already Re-run with -CloseIssue to re-attempt ONLY the GitHub issue close."
        }
        if ((Get-Prop $sig 'resolvedAs' '') -ne $asUpper) {
            Fail 90 "$already It was resolved as $(Get-Prop $sig 'resolvedAs' 'nothing'), not $asUpper. A retry re-attempts the close; it does not change the verdict."
        }
        if ($null -eq (Get-Prop $sig 'issue' $null)) {
            Fail 90 "$already It has no GitHub issue, so there is nothing to close."
        }
        $closedOn = Get-Prop $sig 'issueClosedAt' $null
        if ($null -ne $closedOn) {
            Fail 90 "$already Its issue #$(Get-Prop $sig 'issue' '?') was closed on $closedOn. There is nothing left to retry."
        }
        $isRetry = $true
    }

    # A SIGNAL'S TITLE NAMES A DEFECT AND ITS EVIDENCE NAMES ONE INSTANCE OF IT, so this asks
    # which of the two a fix addressed. Without the question, a fix aimed at the instance
    # closes the issue and leaves the defect standing, permanently, because a resolved
    # signal is terminal and no later session has a reason to look again.
    #
    # THE NUMBER THAT MAKES IT MORE THAN BOOKKEEPING. A defect filed as 'nothing detects a
    # working-tree line-ending divergence from .gitattributes' carried ONE file as its
    # evidence. Repairing that file and closing the issue would have recorded the defect as
    # fixed; the detector that shipped instead found NINETEEN divergent files on its first
    # run, and the defect recurred after that.
    #
    # WHY exit 95 AND NOT 90. 95 is 'a mandatory answer was not supplied', which is exactly
    # this: the wrapper cannot judge whether the answer is TRUE, only that it was given.
    # The precedent is P21's -Reversible and -Observable on record-verdict, which refuse at
    # 95 for the same reason and are the shape this deliberately copies.
    #
    # WHY ONLY ON PROMOTED. A REJECTED or UNREPRODUCIBLE signal has no fix whose scope
    # could be described, so requiring the answer there would be ceremony - and charter P13
    # records what happens to ceremony. Supplying it anyway is refused rather than ignored,
    # because a silently-dropped answer reads to the caller as an accepted one.
    #
    # WHY THIS SITS BELOW THE RETRY GUARD AND NOT ABOVE IT. Placed above, it fires on every
    # -As PROMOTED call including the issue-close retry against an ALREADY-TERMINAL
    # record - which is a stored record being re-read through a changed contract, exactly
    # what charter P24 forbids. On a terminal scratch signal, the check placed above refuses
    # that retry at 95, telling the caller to resolve a signal already PROMOTED, where this
    # placement reaches the retry guard and names the real situation. A retry re-attempts
    # only the close and cannot amend the verdict, so it needs no answer about a fix.
    $addressesLower = ''
    if (-not $isRetry) {
        if ($asUpper -eq 'PROMOTED') {
            if ([string]::IsNullOrWhiteSpace($Addresses)) {
                Fail 95 ("-Addresses defect|instance is required to resolve '$Id' as PROMOTED. Say what the fix addressed. " +
                         "'defect' means the class is fixed and the signal becomes terminal, as a PROMOTED always did. " +
                         "'instance' means one occurrence is fixed, the defect stands, and the signal STAYS OPEN. " +
                         "A fix to the one file a signal names can leave the same defect in other files.")
            }
            Assert-Enum $Addresses.ToLower() $AddressesVals 'Addresses'
            $addressesLower = $Addresses.ToLower()
            if ($addressesLower -eq 'instance' -and $CloseIssue) {
                Fail 90 ("-CloseIssue cannot accompany -Addresses instance. The defect stands, so its issue stays open - " +
                         "closing it would report a defect as fixed while it stands. Re-run with -Addresses defect when the " +
                         "class itself is fixed, and the close happens then.")
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Addresses)) {
            Fail 90 "-Addresses is only meaningful with -As PROMOTED. A $asUpper signal has no fix whose scope could be named."
        }
    }

    if ($isRetry) {
        Say "Signal $Id is already $($sig.state); re-attempting the GitHub issue close only."
        if (-not [string]::IsNullOrWhiteSpace($Addresses)) {
            Say '  -Addresses is IGNORED on a retry: a retry re-attempts the close and does not amend a terminal resolution.'
        }
        if ($Detail -ne (Get-Prop $sig 'resolution' '')) {
            Say '  -Detail differs from the recorded resolution and is IGNORED: a retry does not amend a terminal resolution.'
        }
    }
    elseif ($addressesLower -eq 'instance') {
        # THE THREE TERMINAL FIELDS ARE NOT WRITTEN, and that is the whole design rather
        # than a shortcut. The retry guard above hangs off state -ne 'OPEN', so a record
        # left OPEN skips it - and if an instance fix had written resolvedAs, resolution
        # and resolvedAt, the NEXT resolution would overwrite them with no refusal and no
        # warning. The comment on that guard says a silent overwrite is 'worse than the
        # defect it repairs', so an implementation that reused those fields would re-create
        # that silent overwrite by a side door while fixing the instance case. Leaving them
        # null means there is no terminal verdict for a second call to destroy, and
        # 'resolvedAs' keeps one meaning: this signal is terminal.
        #
        # IT APPENDS RATHER THAN REPLACES. A defect can be chipped at more than once, and
        # a second instance fix must not erase the first - the trail is the evidence that
        # the defect outlived them.
        #
        # THE @() RE-WRAP IS LOAD-BEARING. ConvertFrom-Json unrolls a
        # one-element JSON array to a bare object, so a second call would otherwise be
        # appending to a scalar and .Count would throw under strict mode.
        $fixes = @(Get-Prop $sig 'instanceFixes' @())
        $fixes += [pscustomobject]@{ at = (Now); detail = $Detail }
        Set-Prop $sig 'instanceFixes' $fixes
        Write-GuardedJson $sp $sig
        Say "Signal $Id -> PROMOTED, but an INSTANCE only: $Detail"
        Say "  The signal STAYS OPEN and its issue is not closed. The defect this instance belongs to is unfixed."
        Say "  $($fixes.Count) instance fix(es) now recorded. Resolve with -Addresses defect once the class itself is fixed."
        exit 0
    }
    else {
        Set-Prop $sig 'state' $asUpper
        Set-Prop $sig 'resolvedAs' $asUpper
        Set-Prop $sig 'resolution' $Detail
        Set-Prop $sig 'resolvedAt' (Now)
        # THE ANSWER -Addresses MAKES MANDATORY IS PERSISTED. A wrapper that spends an exit 95
        # and an exit 90 enforcing an answer it then discards keeps the defect-versus-instance
        # distinction in this verb's control flow and nowhere in the stored record - and a
        # check asserting the state and the closed issue cannot see that, since both are
        # true. A mandatory question answered and then discarded is worse than not asking,
        # because the refusal tells the caller the answer is being recorded.
        #
        # WRITTEN ONLY WHEN NON-EMPTY. -Addresses is refused at 90 for a non-PROMOTED
        # verdict, so the value here is 'defect' or the empty string, and an empty
        # 'addresses' is not a fact about the resolution - resolvedAs already says the
        # verdict was REJECTED, and a scope answer is meaningless where there is no fix.
        # Storing '' would put a non-fact on every future REJECTED record for a later
        # query to strip, which is the shape of the defect this repairs.
        #
        # THE 'instance' BRANCH ABOVE NEEDS NOTHING: an instanceFixes entry already
        # MEANS addresses = instance, and writing the word beside it would be one fact
        # with two homes (charter P10).
        if ($addressesLower -ne '') { Set-Prop $sig 'addresses' $addressesLower }
        Write-GuardedJson $sp $sig
        Say "Signal $Id -> $($asUpper): $Detail"
    }

    $issueNum = Get-Prop $sig 'issue' $null
    if ($null -ne $issueNum) {
        if ($CloseIssue) {
            $slug = Get-SignalsDestination
            $gh = $null
            if (-not [string]::IsNullOrWhiteSpace($slug)) { $gh = Resolve-Gh }
            if ([string]::IsNullOrWhiteSpace($slug)) {
                # No destination chosen. The local resolution above is already
                # written, so this verb still exits 0 - it only says the issue was left alone.
                Say "  Issue #$issueNum NOT closed: $NoDestinationText The local resolution IS recorded; re-run with -CloseIssue once a destination is chosen."
            }
            elseif ($null -eq $gh) {
                Say "  Issue #$issueNum NOT closed: gh could not be resolved. Close it by hand, or re-run with -CloseIssue once it resolves."
            }
            elseif ($null -ne (Test-OutwardBlocked)) {
                # THE OUTWARD GUARD GETS ITS OWN BRANCH, and hanging it on a condition
                # above instead would be the bug. Those branches say no destination
                # was chosen or gh could not be resolved - and under the guard BOTH resolved,
                # so sharing one would assert the exact false reason the guard's message
                # exists to avoid. 'GitHub CLI not found' lives solely in signals-push and
                # adopt-signal.
                #
                # THE VERB'S OUTCOME IS PRESERVED: this takes the SAME continue path as the
                # branch above, at exit 0, and the local resolution was already written
                # further up. The verb refusing here would be the contract change nobody
                # asked for.
                #
                # BOTH declined commands are named, not one. This block guards two calls -
                # the comment POST and the issue close - and a message naming only the
                # first would leave the second untested while looking covered.
                $owResolveBlocked = Test-OutwardBlocked
                Say ("  Issue #$issueNum NOT closed: " + (Get-OutwardBlockedMessage -OwReason $owResolveBlocked `
                    -OwCommands @("gh api --method POST repos/$slug/issues/$issueNum/comments", "gh issue close $issueNum --repo $slug") `
                    -OwAssurance 'gh WAS found and a destination WAS chosen - this says nothing about either. The local resolution IS recorded.'))
            }
            else {
                # THE COMMENT TRAVELS IN A FILE, NOT AS A NATIVE ARGUMENT. Same defect and the
                # same fix as 'signals-push' above, whose comment block carries the
                # measurement. Measured against a compiled argument-counting receiver: a
                # -Detail quoting a heading - which charter P8 actively produces - arrived as
                # EIGHT arguments instead of seven, the quotes stripped, the comment truncated
                # at the first quoted word and the remainder delivered to gh as a stray
                # positional. gh issue close has no --body-file or --comment-file (checked
                # against gh 2.97.0), which is why the comment goes through the api verb.
                #
                # THE CLOSE ITSELF STAYS ON THE issue VERB. Once the comment is gone its
                # arguments are an integer, two literal flag names and the repo slug, none of
                # which can carry a double quote or a trailing backslash - the two shapes the
                # signals-push measurement identified. Swapping it for a second api call would
                # drop gh's own state_reason handling for no measured gain (charter P12).
                #
                # COMMENT FIRST, CLOSE SECOND, and each half recorded as it lands. Closing
                # first would strand a failed comment permanently: the retry above requires the
                # issue to be un-closed, so the resolution's reasoning could never be added
                # afterwards. Recording each half is also what lets a retry skip a comment that
                # already posted, so a retry cannot duplicate one, and what lets a completed
                # close refuse a retry without a network call - the offline case the retry
                # exists for.
                $commentOk = $true
                if ($null -eq (Get-Prop $sig 'issueCommentedAt' $null)) {
                    $commentBody = "Resolved as $($asUpper): $(Get-Prop $sig 'resolution' '')"
                    $tmp = Join-Path $env:TEMP ("keel-resolve-" + $Id + ".json")
                    Write-TextNoBom $tmp ([ordered]@{ body = $commentBody } | ConvertTo-Json -Depth 6)
                    # --jq for the same reason as signals-push: the response echoes the body
                    # back, and signal prose can itself contain a github.com issues URL.
                    $res = Invoke-Native -Exe $gh -Arguments @('api','--method','POST',"repos/$slug/issues/$issueNum/comments",'--input',$tmp,'--jq','.html_url')
                    # Record first, then clean up through the helper that cannot throw - the
                    # same order and the same reason as signals-push.
                    if ($res.Code -eq 0) {
                        Set-Prop $sig 'issueCommentedAt' (Now)
                        Write-SignalFields $sp $sig @('issueCommentedAt')
                    }
                    Remove-KeelTempFile $tmp
                    if ($res.Code -ne 0) {
                        $commentOk = $false
                        Say "  Issue #$issueNum NOT closed: the closing comment could not be posted - $($res.Text)"
                        Say '  Nothing was closed. Re-run the same command with -CloseIssue to retry.'
                    }
                }
                if ($commentOk) {
                    $res = Invoke-Native -Exe $gh -Arguments @('issue','close',"$issueNum",'--repo',$slug)
                    if ($res.Code -eq 0) {
                        Set-Prop $sig 'issueClosedAt' (Now)
                        Write-SignalFields $sp $sig @('issueClosedAt')
                        Say "  Closed issue #$issueNum on $slug."
                    }
                    else {
                        Say "  Issue #$issueNum NOT closed: $($res.Text)"
                        Say '  The closing comment is posted. Re-run the same command with -CloseIssue to retry the close.'
                    }
                }
            }
        }
        else {
            Say "  Issue #$issueNum is still OPEN on GitHub. Re-run with -CloseIssue to close it, or close it by hand."
        }
    }
    exit 0
}

# --------------------------------------------------------------------------- #
default {
    Fail 90 "Unknown command '$Command'. Run with no arguments for the verb list."
}

}
}
finally { Exit-WriteLocks }
