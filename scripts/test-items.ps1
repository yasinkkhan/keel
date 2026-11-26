<#
    test-items.ps1 - the suite for the item store: 'send', 'answer-item', 'items' and the two status
    blocks that show work one project sends another on this machine.

    WHY THIS EXISTS. A session writes only in the project it works in, so work it finds for another
    project is sent as an item: one record in a store under the state home, never written into the
    receiving project's folder or state. The receiving project's status shows each item until it is
    answered there, accepted into a plan item or declined with a reason, and the sending project's
    status shows each item still waiting. This suite runs the three verbs against scratch projects.

    WHAT IT COVERS. Each case beside a control on the same fixture that must behave differently:
      a  send writes one record with every field and prints its id, while both projects' folders
         and per-machine folders hash the same before and after / the same hash instrument sees a
         planted write
      b  the receiver's status prints the received block / a third project's prints neither block
      c  the sender's status prints the sent block / once every item is answered neither prints
      d  accepted into an unfinished workstream, an unfinished phase and a delivered phase, each
         ACCEPTED with 'into' / an item not yet answered is SENT with no 'into'
      e  declined with a reason records DECLINED and the reason / an accepted item has none
      f  every refusal of send and answer-item, each asserting its code, its message and that
         nothing was written / a success of each verb on the same store, and a quarantined
         project's one-line reference sent
      g  items lists both directions with their answers, items -Id prints the detail, an unknown id
         exits 94 / a project with no items prints the none line
      h  a receiver exported with share-progress is sent to and its status shows the block, and a
         handed-over phase is refused as a landing place, and a receiver with no phases yet shows
         the block / a folder with no state file is refused at 91, the phase that continues the
         handed-over one is accepted, and the receiver with no phases shows no block before a send
      i  with the item store's lock held past the wait, send exits 89 and writes nothing / after
         release it sends; and two writers released together for 20 rounds give 40 distinct ids
      j  harness: every child resolves gh to a fake that logs and exits 7, and it is never called
    Rows named HARNESS- check the fixtures and pass whatever wrapper runs; a row named <letter>-case-
    needs the verbs to pass, and a <letter>-control- row may pass without them. Every refusal row
    asserts its message as well as its code, and every row asserting that something is not printed
    also asserts exit 0 and a line its fixture prints.

    ISOLATION. The wrapper derives its whole state home from $env:USERPROFILE, so every call runs with
    USERPROFILE at a scratch home under the system temp directory, and the suite refuses to run if
    that does not resolve inside it. HOME and GIT_CONFIG_GLOBAL point at scratch, GIT_CONFIG_NOSYSTEM
    is set, every GIT_ variable a git hook exports is cleared, COMPUTERNAME is fixed and KEEL_OUTWARD
    is 'block'. A fake gh.cmd sits first on PATH for every child.

    THE LOCK NAME is computed here as the wrapper's Get-WriteLockName computes it: the prefix
    'Global\keel-write-' and the SHA-256 of the lowercased full path. A DECLARED coupling, as in
    scripts/test-concurrent-writes.ps1: change one and change the other, or the held-lock case holds a
    lock nobody waits for and fails.

    Run it:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-items.ps1
      ... -List                    every row, passing rows included
      ... -AgainstWrapper <path>   every call against another keel-state.ps1, in the repo's layout
                                   (as 'git archive' unpacks it); a wrapper without the three verbs
                                   must fail every case row. Human-invoked, not on the push path.

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

# Every local in this file is It-prefixed: PowerShell variable names are case-insensitive, and a
# local whose name matches a param() name IS that parameter.
$ItRepoRoot = Split-Path -Parent $PSScriptRoot
$ItWrapper  = Join-Path $ItRepoRoot 'plugins\keel-workflow\skills\keel-orchestrator\wrappers\keel-state.ps1'
if (-not [string]::IsNullOrWhiteSpace($AgainstWrapper)) {
    if (-not (Test-Path -LiteralPath $AgainstWrapper -PathType Leaf)) {
        [Console]::Error.WriteLine("test-items: -AgainstWrapper '$AgainstWrapper' is not a file.")
        exit 1
    }
    $ItWrapper = (Resolve-Path -LiteralPath $AgainstWrapper).Path
}
$ItMachine = 'KIT-SUITE'
$ItLockPrefix = 'Global\keel-write-'

$script:ItRows = @()

# A function returns everything it emits, so the rows go to a script-scope list and this returns
# nothing.
function Add-ItRow {
    param([string]$ItName, [bool]$ItOk, [string]$ItWhy)
    $script:ItRows += [pscustomobject]@{ Name = $ItName; Ok = $ItOk; Why = $ItWhy }
}

# One wrapper call in its own powershell.exe. Stderr arrives as ErrorRecords under 2>&1, and
# ToString() on one wrapping a blank line yields a literal RemoteException name, so each is read
# through its Exception.Message. The exit code decides, never the stream.
function Invoke-ItK {
    param([string]$ItHome, [string[]]$ItArgs)
    $itPrevProfile = $env:USERPROFILE
    $itPrevMachine = $env:COMPUTERNAME
    $itPrevPref = $ErrorActionPreference
    $env:USERPROFILE = $ItHome
    $env:COMPUTERNAME = $ItMachine
    $ErrorActionPreference = 'Continue'
    $itLines = @()
    $itCode = 0
    try {
        $itLines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ItWrapper @ItArgs 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
        })
        $itCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $itPrevPref
        $env:USERPROFILE = $itPrevProfile
        $env:COMPUTERNAME = $itPrevMachine
    }
    return [pscustomobject]@{ Code = $itCode; Text = (@($itLines) -join "`n") }
}

# A fixture step made with a verb every keel has. A failure stops the run, which is reported as a
# failure, never as a short green list.
function Assert-ItK {
    param([string]$ItHome, [string[]]$ItArgs)
    $itR = Invoke-ItK $ItHome $ItArgs
    if ($itR.Code -ne 0) { throw "fixture step '$($ItArgs -join ' ')' failed (exit $($itR.Code)): $($itR.Text)" }
    return $itR
}

function Invoke-ItGit {
    param([string]$ItDir, [string[]]$ItArgs)
    $itPrevPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $itOut = @(& git -C $ItDir @ItArgs 2>&1 | ForEach-Object { $_.ToString() })
        $itCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $itPrevPref }
    if ($itCode -ne 0) { throw "git $($ItArgs -join ' ') failed in '$ItDir' (exit $itCode): $($itOut -join ' ')" }
}

function Set-ItFile {
    param([string]$ItFile, [string]$ItText)
    $itParent = Split-Path -Parent $ItFile
    if (-not (Test-Path -LiteralPath $itParent)) { New-Item -ItemType Directory -Path $itParent -Force | Out-Null }
    [System.IO.File]::WriteAllText($ItFile, $ItText, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-ItSha {
    param([byte[]]$ItBytes)
    $itAlg = [System.Security.Cryptography.SHA256]::Create()
    try { return (-join ($itAlg.ComputeHash($ItBytes) | ForEach-Object { $_.ToString('x2') })) }
    finally { $itAlg.Dispose() }
}

# One hash over every file under a folder, each by its relative path and its bytes. '' when the
# folder is absent, so two absent folders never read as two equal readings.
function Get-ItTreeHash {
    param([string]$ItDir)
    if (-not (Test-Path -LiteralPath $ItDir)) { return '' }
    $itBase = (Get-Item -LiteralPath $ItDir).FullName
    $itParts = New-Object System.Collections.Generic.List[string]
    foreach ($itF in @(Get-ChildItem -LiteralPath $ItDir -Recurse -File -Force | Sort-Object FullName)) {
        $itParts.Add($itF.FullName.Substring($itBase.Length) + ':' + (Get-ItSha ([System.IO.File]::ReadAllBytes($itF.FullName))))
    }
    $itParts.Add("files=$($itParts.Count)")
    return (Get-ItSha ([System.Text.Encoding]::UTF8.GetBytes(($itParts -join "`n"))))
}

function Get-ItFileHash {
    param([string]$ItFile)
    if (-not (Test-Path -LiteralPath $ItFile)) { return '' }
    return (Get-ItSha ([System.IO.File]::ReadAllBytes($ItFile)))
}

function Get-ItStore { param([string]$ItHome) return (Join-Path $ItHome '.keel\items') }

function Get-ItCount {
    param([string]$ItHome)
    $itStore = Get-ItStore $ItHome
    if (-not (Test-Path -LiteralPath $itStore)) { return 0 }
    return @(Get-ChildItem -LiteralPath $itStore -Filter 'I*.json' -File | Where-Object { $_.BaseName -match '^I\d{4}$' }).Count
}

# One item record, or $null when there is none.
function Get-ItItem {
    param([string]$ItHome, [string]$ItItemId)
    if ($ItItemId -notmatch '^I\d{4}$') { return $null }
    $itFile = Join-Path (Get-ItStore $ItHome) "$ItItemId.json"
    if (-not (Test-Path -LiteralPath $itFile)) { return $null }
    try { return (Get-Content -LiteralPath $itFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-ItField {
    param($ItObj, [string]$ItField)
    if ($null -eq $ItObj) { return $null }
    $itP = $ItObj.PSObject.Properties[$ItField]
    if ($null -eq $itP) { return $null }
    return $itP.Value
}

function Get-ItSentId {
    param([string]$ItText)
    if ($ItText -match 'Sent item (I\d{4})') { return $Matches[1] }
    return 'I0000'
}

function Test-ItHas { param([string]$ItText, [string]$ItPart) return $ItText.Contains($ItPart) }

function Get-ItBrief { param($ItR) return "exit $($ItR.Code); printed: [$($ItR.Text)]" }

# Must equal the wrapper's Get-WriteLockName. See the header.
function Get-ItLockName {
    param([string]$ItTarget)
    $itFull = [System.IO.Path]::GetFullPath($ItTarget).ToLowerInvariant()
    return ($ItLockPrefix + (Get-ItSha ([System.Text.Encoding]::UTF8.GetBytes($itFull))))
}

function New-ItProject {
    param([string]$ItHome, [string]$ItDir, [string]$ItTitle, [switch]$ItQuarantine, [switch]$ItGit)
    New-Item -ItemType Directory -Path $ItDir -Force | Out-Null
    if ($ItGit) {
        Invoke-ItGit $ItDir @('init', '-q', '-b', 'main')
        Invoke-ItGit $ItDir @('config', 'user.name', 'Items Suite')
        Invoke-ItGit $ItDir @('config', 'user.email', 'suite@example.invalid')
        Invoke-ItGit $ItDir @('config', 'core.autocrlf', 'false')
    }
    $itInit = @('init-project', '-Path', $ItDir, '-Title', $ItTitle)
    if (-not $ItGit) { $itInit += '-NoGit' }
    if ($ItQuarantine) { $itInit += '-Quarantine' }
    [void](Assert-ItK $ItHome $itInit)
    [void](Assert-ItK $ItHome @('add-goal', '-Path', $ItDir, '-Id', 'G1', '-Text', 'fixture goal'))
    [void](Assert-ItK $ItHome @('add-workstream', '-Path', $ItDir, '-Id', 'W1', '-Title', 'fixture workstream', '-Parent', 'root', '-Goals', 'G1', '-Express'))
}

function Add-ItPhase {
    param([string]$ItHome, [string]$ItDir, [string]$ItWs, [string]$ItPhase)
    if ($ItWs -ne 'W1') {
        [void](Assert-ItK $ItHome @('add-workstream', '-Path', $ItDir, '-Id', $ItWs, '-Title', "fixture $ItWs", '-Parent', 'root', '-Goals', 'G1', '-Express'))
    }
    [void](Assert-ItK $ItHome @('add-phase', '-Path', $ItDir, '-Phase', $ItPhase, '-Scope', 'fixture phase', '-Actor', 'agent', '-RunOrder', '1'))
}

# Drives one phase of a per-machine project through all eight gates, each with the artifact the
# wrapper's contract asks for, so it is 'delivered' the way any phase is.
function Complete-ItPhase {
    param([string]$ItHome, [string]$ItDir, [string]$ItSlug, [string]$ItPhase)
    $itPd = Join-Path $ItHome ".keel\projects\$ItSlug\phases\$ItPhase"
    Set-ItFile (Join-Path $itPd 'grounding.md') "Measured: a fixture`nNot read: nothing else`n"
    [void](Assert-ItK $ItHome @('record-verdict', '-Path', $ItDir, '-Phase', $ItPhase, '-Gate', 'ground', '-Verdict', 'DONE'))
    Set-ItFile (Join-Path $itPd 'investigation.md') "Positive control: a fixture`n"
    [void](Assert-ItK $ItHome @('record-verdict', '-Path', $ItDir, '-Phase', $ItPhase, '-Gate', 'investigate', '-Verdict', 'DONE'))
    Set-ItFile (Join-Path $itPd 'plan.md') "# plan`n`n## Changes`n`n- one fixture change`n"
    [void](Assert-ItK $ItHome @('record-verdict', '-Path', $ItDir, '-Phase', $ItPhase, '-Gate', 'plan', '-Verdict', 'APPROVED'))
    Set-ItFile (Join-Path $itPd 'act-log.md') "Done by: claude`nDone on: 2026-01-01`nProduced: nothing`n"
    [void](Assert-ItK $ItHome @('record-verdict', '-Path', $ItDir, '-Phase', $ItPhase, '-Gate', 'implement', '-Verdict', 'DONE'))
    Set-ItFile (Join-Path $itPd 'verify-report.md') "| $ItPhase-C1 | PASS | run-by: suite |`n`nPositive control: a fixture`n"
    [void](Assert-ItK $ItHome @('record-verdict', '-Path', $ItDir, '-Phase', $ItPhase, '-Gate', 'verify', '-Verdict', 'PASS'))
    [void](Assert-ItK $ItHome @('record-verdict', '-Path', $ItDir, '-Phase', $ItPhase, '-Gate', 'human', '-Verdict', 'APPROVED'))
    [void](Assert-ItK $ItHome @('record-verdict', '-Path', $ItDir, '-Phase', $ItPhase, '-Gate', 'enact', '-Verdict', 'N/A'))
    Set-ItFile (Join-Path $itPd 'delivery-record.md') "$ItPhase delivered.`n`nDocs impact: none`nRemaining phases: unchanged`n"
    [void](Assert-ItK $ItHome @('record-verdict', '-Path', $ItDir, '-Phase', $ItPhase, '-Gate', 'record', '-Verdict', 'DONE'))
}

function Get-ItPhaseStage {
    param([string]$ItHome, [string]$ItSlug, [string]$ItPhase)
    $itSp = Join-Path $ItHome ".keel\projects\$ItSlug\state.json"
    $itState = Get-Content -LiteralPath $itSp -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $itState) { return '' }
    # phases is an ARRAY: indexed, never walked as an object's properties.
    $itPh = @($itState.phases | Where-Object { $_.id -eq $ItPhase })
    if ($itPh.Count -ne 1) { return '' }
    return [string]$itPh[0].stage
}

# A refusal: its code, a part of its message, and nothing written - the store's record count, and
# the named item's bytes when one is named.
function Test-ItRefusal {
    param([string]$ItName, [string]$ItHome, [string[]]$ItArgs, [int]$ItCode, [string]$ItMsg, [string]$ItWatchId = '')
    $itCount0 = Get-ItCount $ItHome
    $itWatch = ''
    if ($ItWatchId) { $itWatch = Get-ItFileHash (Join-Path (Get-ItStore $ItHome) "$ItWatchId.json") }
    $itR = Invoke-ItK $ItHome $ItArgs
    $itCount1 = Get-ItCount $ItHome
    $itSame = $true
    if ($ItWatchId) { $itSame = ($itWatch -ne '' -and $itWatch -eq (Get-ItFileHash (Join-Path (Get-ItStore $ItHome) "$ItWatchId.json"))) }
    Add-ItRow $ItName (($itR.Code -eq $ItCode) -and (Test-ItHas $itR.Text $ItMsg) -and ($itCount1 -eq $itCount0) -and $itSame) `
        "wanted exit $ItCode with '$ItMsg' and nothing written; $(Get-ItBrief $itR); records $itCount0 -> $itCount1; watched item unchanged: $itSame"
}

function Start-ItChild {
    param([string]$ItScript)
    $itEnc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ItScript))
    $itPsi = New-Object System.Diagnostics.ProcessStartInfo
    $itPsi.FileName = 'powershell.exe'
    $itPsi.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $itEnc"
    $itPsi.UseShellExecute = $false
    $itPsi.RedirectStandardOutput = $true
    $itPsi.RedirectStandardError = $true
    $itPsi.CreateNoWindow = $true
    $itProc = [System.Diagnostics.Process]::Start($itPsi)
    return [pscustomobject]@{ Proc = $itProc; Out = $itProc.StandardOutput.ReadToEndAsync(); Err = $itProc.StandardError.ReadToEndAsync() }
}

function Complete-ItChild {
    param($ItChild)
    if (-not $ItChild.Proc.WaitForExit(600000)) { try { $ItChild.Proc.Kill() } catch { }; throw 'A writer child did not finish in time.' }
    $ItChild.Proc.WaitForExit()
    return [pscustomobject]@{ Code = $ItChild.Proc.ExitCode; Out = $ItChild.Out.Result; Err = $ItChild.Err.Result }
}

# A child that sends $ItRounds items in-process, each after the parent's go, so two children send
# together. Each round prints one ROW line with its exit code, the id it printed and its times.
function Get-ItWriterScript {
    param([string]$ItHome, [string]$ItFrom, [string]$ItSide, [int]$ItRounds, [string]$ItReady, [string]$ItGo)
    return @"
`$ErrorActionPreference = 'Continue'
`$env:USERPROFILE = '$ItHome'
`$env:COMPUTERNAME = '$ItMachine'
`$rdy = [System.Threading.EventWaitHandle]::OpenExisting('$ItReady')
`$go  = [System.Threading.EventWaitHandle]::OpenExisting('$ItGo')
for (`$i = 1; `$i -le $ItRounds; `$i++) {
    [void]`$rdy.Set()
    if (-not `$go.WaitOne(120000)) { [Console]::Out.WriteLine('NOGO'); exit 3 }
    `$global:LASTEXITCODE = -1
    `$t0 = [DateTime]::UtcNow.Ticks
    `$o = & '$script:ItWrapper' send -Path '$ItFrom' -To projr -Title "concurrent $ItSide `$i" -Detail "a reference for round `$i of side $ItSide" 2>`$null | Out-String
    `$c = `$LASTEXITCODE
    `$t1 = [DateTime]::UtcNow.Ticks
    `$sid = 'none'
    if (`$o -match 'Sent item (I[0-9]{4})') { `$sid = `$Matches[1] }
    [Console]::Out.WriteLine("ROW code=`$c id=`$sid t0=`$t0 t1=`$t1")
}
exit 0
"@
}

function ConvertFrom-ItRows {
    param([string]$ItOut)
    $itRowsOut = @()
    foreach ($itL in @($ItOut -split "`r?`n")) {
        if ($itL -match '^ROW code=(-?\d+) id=(\S+) t0=(\d+) t1=(\d+)') {
            $itRowsOut += [pscustomobject]@{ Code = [int]$Matches[1]; Id = $Matches[2]; T0 = [long]$Matches[3]; T1 = [long]$Matches[4] }
        }
    }
    return $itRowsOut
}

# ---------------------------------------------------------------------------
# The cases
# ---------------------------------------------------------------------------
function Invoke-ItCases {
    param([string]$ItRoot, [string]$ItFakeDir, [string]$ItFakeLog)

    $itHome = Join-Path $ItRoot 'home'
    New-Item -ItemType Directory -Path $itHome -Force | Out-Null
    $itProjects = Join-Path $itHome '.keel\projects'

    # --- j, first half: every child resolves gh to the fake.
    $itProbe = @(& powershell.exe -NoProfile -Command '(Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source' 2>$null)
    $itProbeText = ((@($itProbe) -join '') -replace '\s', '')
    $itFakeCmd = Join-Path $ItFakeDir 'gh.cmd'
    Add-ItRow 'HARNESS-fake-gh-first-on-path' ($itProbeText -eq $itFakeCmd) "a child resolves gh to [$itProbeText], wanted [$itFakeCmd]"

    # --- fixtures. A sends to B for a to g; Q (quarantine on) sends to R; R sends to S; T is never a
    # party to any send.
    $itA = Join-Path $ItRoot 'a\proja'
    $itB = Join-Path $ItRoot 'b\projb'
    $itQ = Join-Path $ItRoot 'q\projq'
    $itR = Join-Path $ItRoot 'r\projr'
    $itT = Join-Path $ItRoot 't\projt'
    $itS = Join-Path $ItRoot 's\projs'
    New-ItProject $itHome $itA 'items fixture A'
    Add-ItPhase $itHome $itA 'W1' 'W1.1'
    New-ItProject $itHome $itB 'items fixture B'
    Add-ItPhase $itHome $itB 'W1' 'W1.1'
    Add-ItPhase $itHome $itB 'W2' 'W2.1'
    Complete-ItPhase $itHome $itB 'projb' 'W2.1'
    Add-ItPhase $itHome $itB 'W3' 'W3.1'
    # A workstream is abandoned once each of its phases is.
    [void](Assert-ItK $itHome @('abandon', '-Path', $itB, '-Phase', 'W3.1', '-Detail', 'fixture: never ran'))
    [void](Assert-ItK $itHome @('abandon', '-Path', $itB, '-Ws', 'W3', '-Detail', 'fixture: never ran'))
    Add-ItPhase $itHome $itB 'W4' 'W4.1'
    [void](Assert-ItK $itHome @('abandon', '-Path', $itB, '-Phase', 'W4.1', '-Detail', 'fixture: never ran'))
    New-ItProject $itHome $itQ 'items fixture Q' -ItQuarantine
    Add-ItPhase $itHome $itQ 'W1' 'W1.1'
    New-ItProject $itHome $itR 'items fixture R'
    Add-ItPhase $itHome $itR 'W1' 'W1.1'
    New-ItProject $itHome $itT 'items fixture T'
    Add-ItPhase $itHome $itT 'W1' 'W1.1'

    # --- HARNESS: the fixtures' state is in the scratch home, and status reads it.
    $itHs = Invoke-ItK $itHome @('status', '-Path', $itA)
    $itStateA = Join-Path $itProjects 'proja\state.json'
    Add-ItRow 'HARNESS-state-in-scratch-home' (($itHs.Code -eq 0) -and (Test-Path -LiteralPath $itStateA)) "status exit $($itHs.Code); state file present: $(Test-Path -LiteralPath $itStateA)"
    $itW21 = Get-ItPhaseStage $itHome 'projb' 'W2.1'
    $itW31 = Get-ItPhaseStage $itHome 'projb' 'W3.1'
    $itW41 = Get-ItPhaseStage $itHome 'projb' 'W4.1'
    Add-ItRow 'HARNESS-receiver-fixture-stages' (($itW21 -eq 'delivered') -and ($itW31 -eq 'abandoned') -and ($itW41 -eq 'abandoned')) "W2.1 '$itW21', W3.1 '$itW31', W4.1 '$itW41'; wanted delivered, abandoned, abandoned"

    # --- a: send writes one record, prints its id, and touches neither project.
    $itTitle1 = 'Follow-up: point the monthly report at the ledger export'
    $itDetail1 = "Replace the line 'reads totals from the old CSV' in the report spec`nwith 'reads totals from the ledger export'."
    $itHa0 = Get-ItTreeHash $itA; $itHb0 = Get-ItTreeHash $itB
    $itHpa0 = Get-ItTreeHash (Join-Path $itProjects 'proja'); $itHpb0 = Get-ItTreeHash (Join-Path $itProjects 'projb')
    $itC0 = Get-ItCount $itHome
    $itS1 = Invoke-ItK $itHome @('send', '-Path', $itA, '-To', 'projb', '-Title', $itTitle1, '-Detail', $itDetail1, '-Phase', 'W1.1')
    $itI1 = Get-ItSentId $itS1.Text
    Add-ItRow 'a-case-send-prints-id' (($itS1.Code -eq 0) -and ($itI1 -ne 'I0000')) (Get-ItBrief $itS1)
    $itRec1 = Get-ItItem $itHome $itI1
    $itNames1 = ''
    if ($null -ne $itRec1) { $itNames1 = (@($itRec1.PSObject.Properties | ForEach-Object { $_.Name }) -join ',') }
    $itWantNames = 'id,from,fromPhase,to,title,detail,created,keelVersion,state,answeredAt,into,reason'
    $itRecOk = ($null -ne $itRec1) -and ($itNames1 -eq $itWantNames) -and
        ((Get-ItField $itRec1 'from') -eq 'proja') -and ((Get-ItField $itRec1 'fromPhase') -eq 'W1.1') -and
        ((Get-ItField $itRec1 'to') -eq 'projb') -and ((Get-ItField $itRec1 'title') -eq $itTitle1) -and
        ((Get-ItField $itRec1 'detail') -eq $itDetail1) -and ((Get-ItField $itRec1 'state') -eq 'SENT') -and
        (-not [string]::IsNullOrWhiteSpace([string](Get-ItField $itRec1 'created'))) -and
        (-not [string]::IsNullOrWhiteSpace([string](Get-ItField $itRec1 'keelVersion'))) -and
        ($null -eq (Get-ItField $itRec1 'answeredAt')) -and ($null -eq (Get-ItField $itRec1 'into')) -and ($null -eq (Get-ItField $itRec1 'reason'))
    Add-ItRow 'a-case-one-record-with-every-field' ($itRecOk -and ((Get-ItCount $itHome) -eq $itC0 + 1)) "records $itC0 -> $(Get-ItCount $itHome); fields [$itNames1]"
    $itHa1 = Get-ItTreeHash $itA; $itHb1 = Get-ItTreeHash $itB
    $itHpa1 = Get-ItTreeHash (Join-Path $itProjects 'proja'); $itHpb1 = Get-ItTreeHash (Join-Path $itProjects 'projb')
    $itUnchanged = ($itS1.Code -eq 0) -and ($itHa0 -ne '') -and ($itHa0 -eq $itHa1) -and ($itHb0 -eq $itHb1) -and ($itHpa0 -ne '') -and ($itHpa0 -eq $itHpa1) -and ($itHpb0 -eq $itHpb1)
    Add-ItRow 'a-case-both-projects-unchanged' $itUnchanged "send exit $($itS1.Code); folder A same $($itHa0 -eq $itHa1), B same $($itHb0 -eq $itHb1), per-machine A same $($itHpa0 -eq $itHpa1), B same $($itHpb0 -eq $itHpb1)"
    $itCopy = Join-Path $ItRoot 'copy\projb'
    Copy-Item -LiteralPath $itB -Destination $itCopy -Recurse
    $itHc0 = Get-ItTreeHash $itCopy
    Set-ItFile (Join-Path $itCopy 'plan\spec.md') "a planted write`n"
    $itHc1 = Get-ItTreeHash $itCopy
    Add-ItRow 'a-control-hash-sees-a-write' (($itHc0 -eq $itHb0) -and ($itHc1 -ne $itHc0)) "copy hashed equal to B: $($itHc0 -eq $itHb0); after a planted write differs: $($itHc1 -ne $itHc0)"

    # --- b: the receiver's status shows the block; a third project's shows neither.
    $itStB = Invoke-ItK $itHome @('status', '-Path', $itB)
    Add-ItRow 'b-case-receiver-status-block' (($itStB.Code -eq 0) -and (Test-ItHas $itStB.Text '1 item(s) received and not yet answered:') -and (Test-ItHas $itStB.Text "$itI1 from proja: $itTitle1") -and (Test-ItHas $itStB.Text 'Read: keel-state.ps1 items -Id <id>')) (Get-ItBrief $itStB)
    $itStT = Invoke-ItK $itHome @('status', '-Path', $itT)
    Add-ItRow 'b-control-third-project-silent' (($itStT.Code -eq 0) -and (Test-ItHas $itStT.Text 'root:') -and -not (Test-ItHas $itStT.Text 'item(s) received') -and -not (Test-ItHas $itStT.Text 'item(s) sent')) (Get-ItBrief $itStT)

    # --- c, case: the sender's status shows the sent block.
    $itStA = Invoke-ItK $itHome @('status', '-Path', $itA)
    Add-ItRow 'c-case-sender-status-block' (($itStA.Code -eq 0) -and (Test-ItHas $itStA.Text '1 item(s) sent and not yet answered:') -and (Test-ItHas $itStA.Text "$itI1 to projb: $itTitle1")) (Get-ItBrief $itStA)

    # --- d: accepted into an unfinished workstream, an unfinished phase and a delivered phase.
    $itI2 = Get-ItSentId (Invoke-ItK $itHome @('send', '-Path', $itA, '-To', 'projb', '-Title', 'second follow-up', '-Detail', 'the second piece of work')).Text
    $itI3 = Get-ItSentId (Invoke-ItK $itHome @('send', '-Path', $itA, '-To', 'projb', '-Title', 'third follow-up', '-Detail', 'work that is already done')).Text
    $itI4 = Get-ItSentId (Invoke-ItK $itHome @('send', '-Path', $itA, '-To', 'projb', '-Title', 'fourth follow-up', '-Detail', 'work B does not take')).Text
    $itPre1 = Get-ItItem $itHome $itI1
    Add-ItRow 'd-control-unanswered-item-is-sent' (($null -ne $itPre1) -and ((Get-ItField $itPre1 'state') -eq 'SENT') -and ($null -eq (Get-ItField $itPre1 'into'))) "item $itI1 state [$(Get-ItField $itPre1 'state')], into [$(Get-ItField $itPre1 'into')]"
    foreach ($itAcc in @(
        [pscustomobject]@{ Name = 'd-case-accepted-into-unfinished-workstream'; Item = $itI1; Into = 'W1' },
        [pscustomobject]@{ Name = 'd-case-accepted-into-unfinished-phase';      Item = $itI2; Into = 'W1.1' },
        [pscustomobject]@{ Name = 'd-case-accepted-into-delivered-phase';       Item = $itI3; Into = 'W2.1' })) {
        $itAr = Invoke-ItK $itHome @('answer-item', '-Path', $itB, '-Id', $itAcc.Item, '-As', 'accepted', '-Into', $itAcc.Into)
        $itAfter = Get-ItItem $itHome $itAcc.Item
        Add-ItRow $itAcc.Name (($itAr.Code -eq 0) -and (Test-ItHas $itAr.Text "ACCEPTED into $($itAcc.Into)") -and ((Get-ItField $itAfter 'state') -eq 'ACCEPTED') -and ((Get-ItField $itAfter 'into') -eq $itAcc.Into) -and (-not [string]::IsNullOrWhiteSpace([string](Get-ItField $itAfter 'answeredAt')))) `
            "$(Get-ItBrief $itAr); stored state [$(Get-ItField $itAfter 'state')], into [$(Get-ItField $itAfter 'into')]"
    }

    # --- e: declined with a reason.
    $itReason = 'Already tracked in this project as a ticket of its own.'
    $itDr = Invoke-ItK $itHome @('answer-item', '-Path', $itB, '-Id', $itI4, '-As', 'declined', '-Detail', $itReason)
    $itRec4 = Get-ItItem $itHome $itI4
    Add-ItRow 'e-case-declined-records-reason' (($itDr.Code -eq 0) -and ((Get-ItField $itRec4 'state') -eq 'DECLINED') -and ((Get-ItField $itRec4 'reason') -eq $itReason) -and ($null -eq (Get-ItField $itRec4 'into'))) `
        "$(Get-ItBrief $itDr); stored state [$(Get-ItField $itRec4 'state')], reason [$(Get-ItField $itRec4 'reason')]"
    $itRec1b = Get-ItItem $itHome $itI1
    Add-ItRow 'e-control-accepted-has-no-reason' (($null -ne $itRec1b) -and ((Get-ItField $itRec1b 'state') -eq 'ACCEPTED') -and ($null -eq (Get-ItField $itRec1b 'reason'))) "item $itI1 state [$(Get-ItField $itRec1b 'state')], reason [$(Get-ItField $itRec1b 'reason')]"

    # --- c, control: every item A sent to B is answered, so neither status prints its block.
    $itStA2 = Invoke-ItK $itHome @('status', '-Path', $itA)
    Add-ItRow 'c-control-answered-sender-silent' (($itStA2.Code -eq 0) -and (Test-ItHas $itStA2.Text 'root:') -and -not (Test-ItHas $itStA2.Text 'item(s) sent')) (Get-ItBrief $itStA2)
    $itStB2 = Invoke-ItK $itHome @('status', '-Path', $itB)
    Add-ItRow 'c-control-answered-receiver-silent' (($itStB2.Code -eq 0) -and (Test-ItHas $itStB2.Text 'root:') -and -not (Test-ItHas $itStB2.Text 'item(s) received')) (Get-ItBrief $itStB2)

    # --- f: the refusals, each beside a success on the same store.
    $itLong = 'x' * 101
    Test-ItRefusal 'f-case-send-without-to-90' $itHome @('send', '-Path', $itA, '-Title', 't', '-Detail', 'd') 90 "-To is required for 'send'"
    Test-ItRefusal 'f-case-send-without-title-90' $itHome @('send', '-Path', $itA, '-To', 'projb', '-Detail', 'd') 90 "-Title is required for 'send'"
    Test-ItRefusal 'f-case-send-without-detail-90' $itHome @('send', '-Path', $itA, '-To', 'projb', '-Title', 't') 90 "-Detail is required for 'send'"
    Test-ItRefusal 'f-case-send-title-over-100-90' $itHome @('send', '-Path', $itA, '-To', 'projb', '-Title', $itLong, '-Detail', 'd') 90 '-Title must be one line of 1 to 100 characters'
    Test-ItRefusal 'f-case-send-title-line-break-90' $itHome @('send', '-Path', $itA, '-To', 'projb', '-Title', "two`nlines", '-Detail', 'd') 90 '-Title must be one line of 1 to 100 characters'
    Test-ItRefusal 'f-case-send-unknown-project-91' $itHome @('send', '-Path', $itA, '-To', 'nosuch', '-Title', 't', '-Detail', 'd') 91 "No project 'nosuch' is known on this machine"
    Test-ItRefusal 'f-case-send-to-itself-90' $itHome @('send', '-Path', $itA, '-To', 'proja', '-Title', 't', '-Detail', 'd') 90 "-To 'proja' is this project"
    Test-ItRefusal 'f-case-send-unknown-phase-94' $itHome @('send', '-Path', $itA, '-To', 'projb', '-Title', 't', '-Detail', 'd', '-Phase', 'W9.9') 94 "Phase 'W9.9' is not declared"
    Test-ItRefusal 'f-case-quarantine-two-line-detail-97' $itHome @('send', '-Path', $itQ, '-To', 'projr', '-Title', 't', '-Detail', "line one`nline two") 97 "has quarantine on, so an item's detail must be a REFERENCE"
    Test-ItRefusal 'f-case-quarantine-detail-over-240-97' $itHome @('send', '-Path', $itQ, '-To', 'projr', '-Title', 't', '-Detail', ('y' * 241)) 97 "has quarantine on, so an item's detail must be a REFERENCE"
    $itQc0 = Get-ItCount $itHome
    $itQs = Invoke-ItK $itHome @('send', '-Path', $itQ, '-To', 'projr', '-Title', 'a quarantined follow-up', '-Detail', 'C:\notes\follow-up.md - the report follow-up, one line')
    Add-ItRow 'f-control-quarantine-reference-sent' (($itQs.Code -eq 0) -and ((Get-ItCount $itHome) -eq $itQc0 + 1)) "$(Get-ItBrief $itQs); records $itQc0 -> $(Get-ItCount $itHome)"
    $itFc0 = Get-ItCount $itHome
    $itF5 = Invoke-ItK $itHome @('send', '-Path', $itA, '-To', 'projb', '-Title', 'fifth follow-up', '-Detail', 'the item the answer refusals use')
    $itI5 = Get-ItSentId $itF5.Text
    Add-ItRow 'f-control-send-succeeds-on-the-same-store' (($itF5.Code -eq 0) -and ((Get-ItCount $itHome) -eq $itFc0 + 1)) "$(Get-ItBrief $itF5); records $itFc0 -> $(Get-ItCount $itHome)"

    Test-ItRefusal 'f-case-answer-unknown-id-94' $itHome @('answer-item', '-Path', $itB, '-Id', 'I0999', '-As', 'declined', '-Detail', 'x') 94 "Item 'I0999' does not exist on this machine"
    Test-ItRefusal 'f-case-answer-malformed-id-90' $itHome @('answer-item', '-Path', $itB, '-Id', 'x1', '-As', 'declined', '-Detail', 'x') 90 "-Id 'x1' is not an item id"
    Test-ItRefusal 'f-case-answer-not-the-receiver-90' $itHome @('answer-item', '-Path', $itA, '-Id', $itI5, '-As', 'declined', '-Detail', 'x') 90 "was sent to 'projb', not to this project 'proja'" $itI5
    Test-ItRefusal 'f-case-answer-already-answered-90' $itHome @('answer-item', '-Path', $itB, '-Id', $itI1, '-As', 'declined', '-Detail', 'x') 90 'is already ACCEPTED into W1' $itI1
    Test-ItRefusal 'f-case-answer-as-neither-value-90' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'maybe', '-Detail', 'x') 90 "-As 'maybe' is not valid" $itI5
    Test-ItRefusal 'f-case-answer-accepted-without-into-90' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'accepted') 90 '-Into is required to accept an item' $itI5
    Test-ItRefusal 'f-case-answer-into-malformed-90' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'accepted', '-Into', 'E1') 90 "-Into 'E1' is not a workstream or phase id" $itI5
    Test-ItRefusal 'f-case-answer-into-no-workstream-94' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'accepted', '-Into', 'W9') 94 "-Into 'W9' names no workstream" $itI5
    Test-ItRefusal 'f-case-answer-into-no-phase-94' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'accepted', '-Into', 'W9.9') 94 "-Into 'W9.9' names no phase" $itI5
    Test-ItRefusal 'f-case-answer-into-abandoned-workstream-90' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'accepted', '-Into', 'W3') 90 "-Into 'W3' is ABANDONED" $itI5
    Test-ItRefusal 'f-case-answer-into-abandoned-phase-90' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'accepted', '-Into', 'W4.1') 90 "-Into 'W4.1' is abandoned" $itI5
    Test-ItRefusal 'f-case-answer-into-phase-under-abandoned-workstream-90' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'accepted', '-Into', 'W3.1') 90 'under the ABANDONED workstream W3' $itI5
    Test-ItRefusal 'f-case-answer-declined-without-detail-95' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'declined') 95 '-Detail is required to decline an item' $itI5
    Test-ItRefusal 'f-case-answer-into-on-declined-90' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'declined', '-Detail', 'x', '-Into', 'W1') 90 'a declined item lands nowhere' $itI5
    Test-ItRefusal 'f-case-answer-detail-on-accepted-90' $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'accepted', '-Into', 'W1', '-Detail', 'x') 90 '-Detail is the reason an item is declined' $itI5
    $itA5 = Invoke-ItK $itHome @('answer-item', '-Path', $itB, '-Id', $itI5, '-As', 'accepted', '-Into', 'W1.1')
    Add-ItRow 'f-control-answer-succeeds-on-the-same-store' (($itA5.Code -eq 0) -and ((Get-ItField (Get-ItItem $itHome $itI5) 'state') -eq 'ACCEPTED')) (Get-ItBrief $itA5)

    # A record that does not parse, in a second home so it never meets the main store's ids.
    $itH2 = Join-Path $ItRoot 'home2'
    Set-ItFile (Join-Path $itH2 '.keel\items\I0001.json') '{ not json'
    $itBadHash = Get-ItFileHash (Join-Path $itH2 '.keel\items\I0001.json')
    $itU1 = Invoke-ItK $itH2 @('answer-item', '-Path', $itB, '-Id', 'I0001', '-As', 'declined', '-Detail', 'x')
    Add-ItRow 'f-case-answer-unparseable-item-96' (($itU1.Code -eq 96) -and (Test-ItHas $itU1.Text "Item 'I0001' did not parse to an object") -and ($itBadHash -eq (Get-ItFileHash (Join-Path $itH2 '.keel\items\I0001.json')))) (Get-ItBrief $itU1)
    $itU2 = Invoke-ItK $itH2 @('items', '-Path', $itB, '-Id', 'I0001')
    Add-ItRow 'f-case-items-unparseable-item-96' (($itU2.Code -eq 96) -and (Test-ItHas $itU2.Text "Item 'I0001' did not parse to an object")) (Get-ItBrief $itU2)
    $itU3 = Invoke-ItK $itH2 @('items', '-Path', $itB)
    Add-ItRow 'f-control-listing-skips-an-unparseable-item' (($itU3.Code -eq 0) -and (Test-ItHas $itU3.Text "No items sent from or to 'projb' on this machine.")) (Get-ItBrief $itU3)

    # --- g: the listing in both directions, one item in full, an unknown id.
    $itLb = Invoke-ItK $itHome @('items', '-Path', $itB)
    Add-ItRow 'g-case-receiver-listing' (($itLb.Code -eq 0) -and (Test-ItHas $itLb.Text "$itI1  from proja") -and (Test-ItHas $itLb.Text 'ACCEPTED') -and (Test-ItHas $itLb.Text 'DECLINED') -and (Test-ItHas $itLb.Text 'into W2.1')) (Get-ItBrief $itLb)
    $itLa = Invoke-ItK $itHome @('items', '-Path', $itA)
    Add-ItRow 'g-case-sender-listing' (($itLa.Code -eq 0) -and (Test-ItHas $itLa.Text "$itI4  to projb") -and (Test-ItHas $itLa.Text "reason: $itReason") -and (Test-ItHas $itLa.Text 'into W1')) (Get-ItBrief $itLa)
    $itLi = Invoke-ItK $itHome @('items', '-Path', $itA, '-Id', $itI1)
    Add-ItRow 'g-case-items-id-prints-the-detail' (($itLi.Code -eq 0) -and (Test-ItHas $itLi.Text "Replace the line 'reads totals from the old CSV' in the report spec") -and (Test-ItHas $itLi.Text "with 'reads totals from the ledger export'.") -and (Test-ItHas $itLi.Text 'accepted into W1')) (Get-ItBrief $itLi)
    $itLu = Invoke-ItK $itHome @('items', '-Path', $itA, '-Id', 'I0999')
    Add-ItRow 'g-case-items-unknown-id-94' (($itLu.Code -eq 94) -and (Test-ItHas $itLu.Text "Item 'I0999' does not exist on this machine")) (Get-ItBrief $itLu)
    $itLm = Invoke-ItK $itHome @('items', '-Path', $itA, '-Id', 'x1')
    Add-ItRow 'g-case-items-malformed-id-90' (($itLm.Code -eq 90) -and (Test-ItHas $itLm.Text "-Id 'x1' is not an item id")) (Get-ItBrief $itLm)
    $itLt = Invoke-ItK $itHome @('items', '-Path', $itT)
    Add-ItRow 'g-control-third-project-none-line' (($itLt.Code -eq 0) -and (Test-ItHas $itLt.Text "No items sent from or to 'projt' on this machine.") -and ($itLt.Text -notmatch 'I\d{4}')) (Get-ItBrief $itLt)

    # --- h: a receiver exported with share-progress, with a handed-over phase; a folder with no state.
    New-ItProject $itHome $itS 'items fixture S' -ItGit
    Invoke-ItGit $itS @('add', '-A')
    Invoke-ItGit $itS @('commit', '-q', '-m', 'project')
    [void](Assert-ItK $itHome @('share-progress', '-Path', $itS))
    [void](Assert-ItK $itHome @('add-phase', '-Path', $itS, '-Phase', 'W1.1', '-Scope', 'fixture phase', '-Actor', 'agent', '-RunOrder', '1'))
    [void](Assert-ItK $itHome @('set-stage', '-Path', $itS, '-Phase', 'W1.1', '-Stage', 'grounding'))
    $itPeople = @(Get-ChildItem -LiteralPath (Join-Path $itS 'progress\people') -Filter '*.json' -File)
    if ($itPeople.Count -ne 1) { throw "fixture S holds $($itPeople.Count) person file(s), wanted 1" }
    [void](Assert-ItK $itHome @('hand-over', '-Path', $itS, '-Phase', 'W1.1', '-To', $itPeople[0].BaseName, '-Detail', 'fixture: handed over'))
    $itSdir = Join-Path $itProjects 'projs'
    $itShared = @(Get-ChildItem -LiteralPath $itSdir -Filter 'state.json.shared-*' -File -ErrorAction SilentlyContinue).Count
    Add-ItRow 'HARNESS-shared-fixture-exported' (($itShared -ge 1) -and -not (Test-Path -LiteralPath (Join-Path $itSdir 'state.json'))) "state.json.shared-* files: $itShared; state.json present: $(Test-Path -LiteralPath (Join-Path $itSdir 'state.json'))"
    $itSs = Invoke-ItK $itHome @('send', '-Path', $itR, '-To', 'projs', '-Title', 'work for the shared project', '-Detail', 'a follow-up for S')
    $itIs = Get-ItSentId $itSs.Text
    Add-ItRow 'h-case-send-to-a-shared-receiver' (($itSs.Code -eq 0) -and ($itIs -ne 'I0000') -and ((Get-ItField (Get-ItItem $itHome $itIs) 'to') -eq 'projs')) (Get-ItBrief $itSs)
    $itStS = Invoke-ItK $itHome @('status', '-Path', $itS)
    Add-ItRow 'h-case-shared-receiver-status-block' (($itStS.Code -eq 0) -and (Test-ItHas $itStS.Text '1 item(s) received and not yet answered:') -and (Test-ItHas $itStS.Text "$itIs from projr: work for the shared project")) (Get-ItBrief $itStS)
    New-Item -ItemType Directory -Path (Join-Path $itProjects 'ghost\phases') -Force | Out-Null
    Test-ItRefusal 'h-control-folder-with-no-state-91' $itHome @('send', '-Path', $itR, '-To', 'ghost', '-Title', 't', '-Detail', 'd') 91 "No project 'ghost' is known on this machine"
    Test-ItRefusal 'f-case-answer-into-handed-over-phase-90' $itHome @('answer-item', '-Path', $itS, '-Id', $itIs, '-As', 'accepted', '-Into', 'W1.1') 90 "-Into 'W1.1' was handed over and is finished: W1.1b continues it" $itIs
    $itAs = Invoke-ItK $itHome @('answer-item', '-Path', $itS, '-Id', $itIs, '-As', 'accepted', '-Into', 'W1.1b')
    Add-ItRow 'h-control-accepted-into-the-successor' (($itAs.Code -eq 0) -and ((Get-ItField (Get-ItItem $itHome $itIs) 'into') -eq 'W1.1b')) (Get-ItBrief $itAs)

    # A receiver with no phases yet, whose status stops early: the block prints there too.
    $itN = Join-Path $ItRoot 'n\projn'
    New-Item -ItemType Directory -Path $itN -Force | Out-Null
    [void](Assert-ItK $itHome @('init-project', '-Path', $itN, '-Title', 'items fixture N', '-NoGit'))
    $itStN0 = Invoke-ItK $itHome @('status', '-Path', $itN)
    Add-ItRow 'h-control-no-phases-before-a-send-silent' (($itStN0.Code -eq 0) -and (Test-ItHas $itStN0.Text 'No phases declared yet.') -and -not (Test-ItHas $itStN0.Text 'item(s) received')) (Get-ItBrief $itStN0)
    $itSn = Invoke-ItK $itHome @('send', '-Path', $itR, '-To', 'projn', '-Title', 'work for a new project', '-Detail', 'a follow-up for N')
    $itIn = Get-ItSentId $itSn.Text
    $itStN1 = Invoke-ItK $itHome @('status', '-Path', $itN)
    Add-ItRow 'h-case-no-phases-receiver-status-block' (($itSn.Code -eq 0) -and ($itStN1.Code -eq 0) -and (Test-ItHas $itStN1.Text 'No phases declared yet.') -and (Test-ItHas $itStN1.Text "$itIn from projr: work for a new project")) (Get-ItBrief $itStN1)

    # --- i: the item store's lock, held past the wait; then two writers at once.
    $itLockName = Get-ItLockName (Get-ItStore $itHome)
    $itMx = New-Object System.Threading.Mutex($false, $itLockName)
    [void]$itMx.WaitOne(0)
    $itHeld0 = Get-ItCount $itHome
    $itClock = [System.Diagnostics.Stopwatch]::StartNew()
    try { $itHeld = Invoke-ItK $itHome @('send', '-Path', $itQ, '-To', 'projr', '-Title', 'held', '-Detail', 'sent while the lock is held') }
    finally { $itMx.ReleaseMutex(); $itMx.Dispose() }
    $itClock.Stop()
    $itHeld1 = Get-ItCount $itHome
    Add-ItRow 'i-case-held-lock-89-nothing-written' (($itHeld.Code -eq 89) -and (Test-ItHas $itHeld.Text 'is writing the item store') -and ($itHeld1 -eq $itHeld0)) "$(Get-ItBrief $itHeld); records $itHeld0 -> $itHeld1; took $([int]$itClock.Elapsed.TotalSeconds)s"
    $itRel = Invoke-ItK $itHome @('send', '-Path', $itQ, '-To', 'projr', '-Title', 'released', '-Detail', 'sent once the lock is free')
    Add-ItRow 'i-control-after-release-sent' (($itRel.Code -eq 0) -and ((Get-ItCount $itHome) -eq $itHeld1 + 1)) "$(Get-ItBrief $itRel); records $itHeld1 -> $(Get-ItCount $itHome)"

    $itRounds = 20
    $itTag = [guid]::NewGuid().ToString('N').Substring(0, 10)
    $itEvNames = @("keel-it-$itTag-ra", "keel-it-$itTag-rb", "keel-it-$itTag-ga", "keel-it-$itTag-gb")
    $itEvs = @{}
    foreach ($itEn in $itEvNames) { $itEvs[$itEn] = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $itEn) }
    $itCc0 = Get-ItCount $itHome
    try {
        $itCa = Start-ItChild (Get-ItWriterScript $itHome $itQ 'A' $itRounds $itEvNames[0] $itEvNames[2])
        $itCb = Start-ItChild (Get-ItWriterScript $itHome $itQ 'B' $itRounds $itEvNames[1] $itEvNames[3])
        for ($itRn = 1; $itRn -le $itRounds; $itRn++) {
            if (-not $itEvs[$itEvNames[0]].WaitOne(120000) -or -not $itEvs[$itEvNames[1]].WaitOne(120000)) { throw "a writer never became ready in round $itRn" }
            [void]$itEvs[$itEvNames[2]].Set(); [void]$itEvs[$itEvNames[3]].Set()
        }
        $itRa = Complete-ItChild $itCa
        $itRb = Complete-ItChild $itCb
    }
    finally { foreach ($itEv in $itEvs.Values) { $itEv.Dispose() } }
    $itAll = @(@(ConvertFrom-ItRows $itRa.Out) + @(ConvertFrom-ItRows $itRb.Out))
    $itOk0 = @($itAll | Where-Object { $_.Code -eq 0 }).Count
    $itIds = @($itAll | Where-Object { $_.Id -match '^I\d{4}$' } | ForEach-Object { $_.Id } | Sort-Object -Unique).Count
    $itCc1 = Get-ItCount $itHome
    $itRowsA = @(ConvertFrom-ItRows $itRa.Out); $itRowsB = @(ConvertFrom-ItRows $itRb.Out)
    $itOverlap = 0
    for ($itK = 0; $itK -lt [Math]::Min($itRowsA.Count, $itRowsB.Count); $itK++) {
        if ($itRowsA[$itK].T0 -lt $itRowsB[$itK].T1 -and $itRowsB[$itK].T0 -lt $itRowsA[$itK].T1) { $itOverlap++ }
    }
    $itWant = 2 * $itRounds
    Add-ItRow 'i-case-two-writers-distinct-ids' (($itAll.Count -eq $itWant) -and ($itOk0 -eq $itWant) -and ($itIds -eq $itWant) -and ($itCc1 -eq $itCc0 + $itWant)) `
        "rounds reported $($itAll.Count) of $itWant; exit 0: $itOk0; distinct ids: $itIds; records $itCc0 -> $itCc1; rounds that overlapped (reported, not scored): $itOverlap"

    # --- j, second half: no row reached gh.
    Add-ItRow 'HARNESS-fake-gh-never-called' (-not (Test-Path -LiteralPath $ItFakeLog)) "fake gh log present: $(Test-Path -LiteralPath $ItFakeLog)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$ItTempBase = [System.IO.Path]::GetTempPath()
$ItRoot = Join-Path $ItTempBase ('keel-items-suite-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 12))

# The scratch root must resolve INSIDE the system temp directory before anything is written.
$ItTempBaseFull = (Get-Item -LiteralPath $ItTempBase).FullName.TrimEnd('\', '/')
New-Item -ItemType Directory -Path $ItRoot -Force | Out-Null
$ItRootFull = (Get-Item -LiteralPath $ItRoot).FullName.TrimEnd('\', '/')
if (-not $ItRootFull.StartsWith("$ItTempBaseFull$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine("test-items: refusing to run - scratch root '$ItRootFull' does not resolve inside '$ItTempBaseFull'.")
    exit 1
}
$ItRoot = $ItRootFull

# No git identity, repository or hook variable from the caller reaches a fixture.
foreach ($ItVar in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'GIT_*' })) { Remove-Item -LiteralPath "Env:$($ItVar.Name)" }
$ItGitGlobal = Join-Path $ItRoot 'gitglobal'
Set-ItFile $ItGitGlobal ''
$env:GIT_CONFIG_GLOBAL = $ItGitGlobal
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:HOME = $ItRoot
$env:KEEL_OUTWARD = 'block'

# The fake gh, first on PATH for every child. It logs each call and refuses.
$ItFakeDir = Join-Path $ItRoot 'fake-gh'
$ItFakeLog = Join-Path $ItRoot 'fake-gh.log'
New-Item -ItemType Directory -Path $ItFakeDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $ItFakeDir 'gh.cmd') -Encoding ASCII -Value @(
    '@echo off',
    ('echo %*>>"' + $ItFakeLog + '"'),
    'echo fake gh: test-items.ps1 never calls GitHub 1>&2',
    'exit /b 7')
$ItPrevPath = $env:PATH
$env:PATH = $ItFakeDir + ';' + $ItPrevPath

$ItFailed = 0
$ItAbort = ''
try {
    try { Invoke-ItCases -ItRoot $ItRoot -ItFakeDir $ItFakeDir -ItFakeLog $ItFakeLog }
    catch { $ItAbort = $_.Exception.Message }

    Write-Output ''
    Write-Output "== item store: $ItWrapper"
    foreach ($ItRow in @($script:ItRows)) {
        if (-not $ItRow.Ok) { $ItFailed++ }
        if ($List -or -not $ItRow.Ok) {
            Write-Output ("  {0}  {1,-56} {2}" -f $(if ($ItRow.Ok) { 'PASS' } else { 'FAIL' }), $ItRow.Name, $ItRow.Why)
        }
    }
    if ($ItAbort) {
        # A fixture step that failed stops the run; it is a failure, never a short green list.
        $ItFailed++
        Write-Output "  FAIL  fixture step: $ItAbort"
    }
}
finally {
    $env:PATH = $ItPrevPath
    if (Test-Path -LiteralPath $ItRoot) {
        try { Remove-Item -LiteralPath $ItRoot -Recurse -Force -ErrorAction Stop } catch { }
    }
}

Write-Output ''
Write-Output ("test-items: {0} case(s), {1} failure(s)." -f @($script:ItRows).Count, $ItFailed)
if ($ItFailed -gt 0) { exit 1 }
exit 0
