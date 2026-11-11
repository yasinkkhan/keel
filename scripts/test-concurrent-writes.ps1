<#
    test-concurrent-writes.ps1 - the suite for the wrapper's write lock.

    What it proves: two keel commands writing the same thing on one machine at overlapping
    moments both land, or one is refused with exit 89 having written nothing. Never does a write
    vanish while its command reports success.

    Runs in a scratch state home ONLY. USERPROFILE is overridden into the temp directory for every
    child, KEEL_OUTWARD is set to 'block', and the suite refuses to start (exit 90) unless its
    scratch home resolves inside %TEMP%. Before the first wrapper write a child must report the
    scratch USERPROFILE and the block, and after the run the real state home must hold no project
    of this run and no real signal file may carry one of its tokens.

    Families, each run as -Pairs rounds (at least 20):
      STATE   'note-friction' on two phases of one project
      REPO    'add-repo' with two different names on one project (keel.json)
      SIGNAL  'signal' filings (the signal store and its ids)
    In each round two long-lived child processes call the wrapper in-process, released together by
    named events, each write carrying its own token. Afterwards the suite reads the store and
    reports for every write whether it is present and what it exited with (-List prints one row
    per write). Each family has a SEQUENTIAL control: the same number of writes one after another,
    which must all land.

    HELD: the suite holds the project's lock itself for longer than the wrapper's bounded wait. A
    write must exit 89, name the re-run, and leave state.json byte-identical; after the release
    the same write must land.

    PAUSED: a real wrapper writer is stopped while it holds the lock. The writer is a verify
    verdict on a phase with a declared repo, whose binding calls git; a fake git.cmd first on that
    child's PATH marks that it was reached, then waits for a release file and exits 1. The binding
    records that failure and the verb carries on to its write.
      CHANGED  while it waits, the suite rewrites state.json as a writer that takes no lock would.
               The verb must exit 89 and leave the file as that writer left it. Control: with no
               foreign write the verb exits 0 and its verdict is recorded.
      KILLED   while it waits, a second writer starts and waits too; the suite kills the first.
               The second must land, well within the bounded wait, after the kill. Control: the
               first is released instead; the second lands after the release.
    A writer killed in the middle of writing the file is not covered: that instant cannot be hit
    on purpose.

    The lock name is computed here the way the wrapper computes it in Get-WriteLockName: the
    prefix below plus the SHA-256 of the guarded path, full and lower-cased. A DECLARED coupling: if
    the two drift, HELD fails, because the suite then holds a lock nobody waits for.

    Modes:
      (none)                 the working-tree wrapper. What check-suite-docs.ps1 -Strict runs.
      -AgainstWrapper <path> the default cases against another copy of the wrapper.
      -AgainstHead           human-invoked, not on the push path: the wrapper at the repo's HEAD,
                             extracted byte for byte, must LOSE writes in the concurrent families
                             (so the suite can see a loss) and land every sequential one; then
                             MIXED runs a HEAD writer against a working-tree writer, beside a
                             HEAD-against-HEAD control, and is REPORTED rather than scored;
                             LIMIT then forces the one loss no lock on one side can stop, an
                             older copy that read before a newer one wrote and writes after it.
      -List                  also print one row per write.

    Summary line, parsed by check-suite-docs.ps1 (a declared coupling):
      test-concurrent-writes: <n> case(s), <n> failure(s), <n> inconclusive
    Exit codes: 0 no failures; 1 one or more failures; 5 a breach of the real state home;
    6 the harness failed; 90 refused to start.

    Prints no path. Windows PowerShell 5.1, ASCII only.
#>

param(
    [int]$Pairs = 20,
    [string]$AgainstWrapper = '',
    [switch]$AgainstHead,
    [switch]$List,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$LockPrefix = 'Global\keel-write-'
$LockWaitMs = 10000

function Stop-Suite {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("test-concurrent-writes: $Message")
    exit $Code
}

# ------------------------------------------------------------- the fence --
if ([string]::IsNullOrWhiteSpace($env:TEMP)) { Stop-Suite 90 'TEMP is not set, so the fence cannot be checked.' }
$tempFull = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\', '/')
$runTag = [guid]::NewGuid().ToString('N').Substring(0, 10)
$scratchFull = [System.IO.Path]::GetFullPath((Join-Path $tempFull ('keel-cw-' + $runTag))).TrimEnd('\', '/')
if (-not $scratchFull.StartsWith($tempFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    Stop-Suite 90 'Refusing to run: the scratch state home does not resolve inside the temp directory.'
}
if (Test-Path -LiteralPath $scratchFull) { Stop-Suite 90 'Refusing to run: the scratch state home already exists.' }
if ($Pairs -lt 20) { Stop-Suite 90 "-Pairs must be at least 20; got $Pairs." }
if ($AgainstHead -and $AgainstWrapper) { Stop-Suite 90 'Pass -AgainstHead or -AgainstWrapper, not both.' }

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$wtWrapper = Join-Path $repoRoot 'plugins\keel-workflow\skills\keel-orchestrator\wrappers\keel-state.ps1'
if (-not (Test-Path -LiteralPath $wtWrapper)) { Stop-Suite 90 'The working-tree wrapper was not found under plugins/.' }
$underTest = $wtWrapper
if ($AgainstWrapper) {
    if (-not (Test-Path -LiteralPath $AgainstWrapper)) { Stop-Suite 90 'The -AgainstWrapper path does not exist.' }
    $underTest = (Resolve-Path -LiteralPath $AgainstWrapper).Path
}

$realProfile = $env:USERPROFILE
$realOutward = $env:KEEL_OUTWARD
$realProjects = Join-Path (Join-Path $realProfile '.keel') 'projects'
$realSignals = Join-Path (Join-Path $realProfile '.keel') 'signals'
$tokenStem = 'KCW' + $runTag.ToUpper()
$slugs = New-Object System.Collections.Generic.List[string]
$fakeDirs = New-Object System.Collections.Generic.List[string]

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
function Add-Inconclusive {
    param([string]$CaseName, [string]$Info)
    $script:CaseCount++
    $script:InconCount++
    Write-Output "INCONCLUSIVE  $CaseName - $Info"
}

# ------------------------------------------------------------ helpers --
function Get-Sha {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return '' }
    $shaAlg = [System.Security.Cryptography.SHA256]::Create()
    try { return (-join ($shaAlg.ComputeHash([System.IO.File]::ReadAllBytes($FilePath)) | ForEach-Object { $_.ToString('x2') })) }
    finally { $shaAlg.Dispose() }
}

function Get-LockNameFor {
    # Must equal the wrapper's Get-WriteLockName. See the header.
    param([string]$Target)
    $full = [System.IO.Path]::GetFullPath($Target).ToLowerInvariant()
    $shaAlg = [System.Security.Cryptography.SHA256]::Create()
    try { $hex = -join ($shaAlg.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($full)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $shaAlg.Dispose() }
    return ($LockPrefix + $hex)
}

function Start-Child {
    # A powershell.exe child running an encoded script, with stdout and stderr read asynchronously.
    param([string]$Script)
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    return [pscustomobject]@{ Proc = $proc; Out = $proc.StandardOutput.ReadToEndAsync(); Err = $proc.StandardError.ReadToEndAsync() }
}

function Complete-Child {
    param($Child, [int]$TimeoutMs = 600000)
    if (-not $Child.Proc.WaitForExit($TimeoutMs)) { try { $Child.Proc.Kill() } catch { }; throw 'A child process did not finish in time.' }
    $Child.Proc.WaitForExit()
    return [pscustomobject]@{ Code = $Child.Proc.ExitCode; Out = $Child.Out.Result; Err = $Child.Err.Result }
}

function Wait-ForFile {
    param([string]$FilePath, [int]$TimeoutMs)
    $wfStop = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $wfStop) {
        if (Test-Path -LiteralPath $FilePath) { return $true }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

function Assert-ChildSeesScratch {
    $probe = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes('[Console]::Out.WriteLine($env:USERPROFILE + "|" + $env:KEEL_OUTWARD)'))
    $seen = & powershell.exe -NoProfile -EncodedCommand $probe
    if ("$seen".Trim() -ne ($scratchFull + '|block')) { throw 'Harness control failed before any write: a child does not see the scratch home and the outward block.' }
}

function New-ScratchProject {
    # Setup calls run in one child, in-process, each one's exit code checked. With -WithRepo the
    # project declares a repo and W1.1 binds it, so a verify verdict on W1.1 calls git.
    param([string]$Wrapper, [string]$Label, [switch]$WithRepo)
    $slug = ('kcw-' + $runTag + '-' + $Label).ToLower()
    $slugs.Add($slug)
    $dir = Join-Path (Join-Path $scratchFull 'work') $slug
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $calls = @(
        "init-project -Path '$dir' -Title 'suite $Label' -NoGit",
        "add-goal -Path '$dir' -Id G1 -Text 'suite goal'",
        "add-workstream -Path '$dir' -Id W1 -Title 'suite workstream' -Parent root -Goals G1",
        "add-phase -Path '$dir' -Phase W1.1 -Scope 'suite phase one' -Actor agent -RunOrder 1",
        "add-phase -Path '$dir' -Phase W1.2 -Scope 'suite phase two' -Actor agent -RunOrder 2"
    )
    if ($WithRepo) {
        $calls += "add-repo -Path '$dir' -Name bound -RepoPath ."
        $calls += "revise-phase -Path '$dir' -Phase W1.1 -Repos bound"
    }
    $setupText = "`$ErrorActionPreference = 'Continue'`r`n"
    foreach ($cl in $calls) {
        $setupText += "`$global:LASTEXITCODE = -1; & '$Wrapper' $cl | Out-Null; if (`$LASTEXITCODE -ne 0) { [Console]::Out.WriteLine('SETUPFAIL ' + `$LASTEXITCODE + ' $($cl.Split(' ')[0])'); exit 3 }`r`n"
    }
    $setupText += "exit 0`r`n"
    $setupRun = Complete-Child (Start-Child $setupText) 120000
    if ($setupRun.Code -ne 0) { throw "Setup of a scratch project failed: $("$($setupRun.Out)".Trim())" }
    $projHome = Join-Path (Join-Path (Join-Path $scratchFull '.keel') 'projects') $slug
    $sp = Join-Path $projHome 'state.json'
    if (-not (Test-Path -LiteralPath $sp)) { throw 'Harness control failed: no state.json in the scratch home after setup.' }
    if ($WithRepo) {
        $phaseDir = Join-Path (Join-Path $projHome 'phases') 'W1.1'
        New-Item -ItemType Directory -Path $phaseDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $phaseDir 'verify-report.md'), "| W1.1-C1 | PASS | run-by: agent |`r`n`r`nPositive control: suite fixture`r`n")
        [System.IO.File]::WriteAllText((Join-Path $phaseDir 'changes-bound.patch'), "suite fixture`r`n")
    }
    return [pscustomobject]@{ Dir = $dir; StatePath = $sp; ConfigPath = (Join-Path $dir 'keel.json') }
}

function Get-VerbLine {
    # The wrapper call one write makes, as PowerShell text for a child script. Tokens and paths
    # carry no quote character, so single quotes are safe.
    param([string]$Verb, [string]$Dir, [string]$PhaseId)
    switch ($Verb) {
        'friction' { return "note-friction -Path '$Dir' -Phase $PhaseId -Kind gap -Detail `$tok" }
        'repo'     { return "add-repo -Path '$Dir' -Name `$tok -RepoPath ." }
        'signal'   { return "signal -Path '$Dir' -Phase $PhaseId -Kind gap -Detail `$tok -Evidence 'suite evidence'" }
    }
    throw "Unknown verb $Verb"
}

function Get-WriterScript {
    # A child that makes $Rounds writes in-process. With event names it waits for the parent's go
    # before each write, so two children write together; without them it writes one after another.
    param([string]$Wrapper, [string]$Verb, [string]$Dir, [string]$PhaseId, [string]$TokenBase, [string]$Side, [int]$Rounds, [string]$ReadyName, [string]$GoName)
    $sync = if ($ReadyName) { '$true' } else { '$false' }
    $line = Get-VerbLine $Verb $Dir $PhaseId
    return @"
`$ErrorActionPreference = 'Continue'
`$sync = $sync
if (`$sync) {
    `$rdy = [System.Threading.EventWaitHandle]::OpenExisting('$ReadyName')
    `$go  = [System.Threading.EventWaitHandle]::OpenExisting('$GoName')
}
for (`$i = 1; `$i -le $Rounds; `$i++) {
    `$tok = '{0}-{1:D3}-{2}' -f '$TokenBase', `$i, '$Side'
    if (`$sync) { [void]`$rdy.Set(); if (-not `$go.WaitOne(120000)) { [Console]::Out.WriteLine('NOGO'); exit 3 } }
    `$global:LASTEXITCODE = -1
    `$t0 = [DateTime]::UtcNow.Ticks
    `$o = & '$Wrapper' $line 2>`$null | Out-String
    `$c = `$LASTEXITCODE
    `$t1 = [DateTime]::UtcNow.Ticks
    `$sid = ''
    if (`$o -match 'Filed signal (S[0-9]+)') { `$sid = `$Matches[1] }
    [Console]::Out.WriteLine("ROW tok=`$tok code=`$c t0=`$t0 t1=`$t1 sid=`$sid")
}
exit 0
"@
}

function ConvertFrom-Rows {
    param([string]$RowText)
    $rows = @()
    foreach ($ln in ($RowText -split "`r?`n")) {
        if ($ln -match '^ROW tok=(\S+) code=(-?[0-9]+) t0=([0-9]+) t1=([0-9]+) sid=(\S*)$') {
            $rows += [pscustomobject]@{ Token = $Matches[1]; Code = [int]$Matches[2]; T0 = [long]$Matches[3]; T1 = [long]$Matches[4]; Sid = $Matches[5] }
        }
    }
    return $rows
}

function Get-SignalFiles {
    $sigDir = Join-Path (Join-Path $scratchFull '.keel') 'signals'
    return @(Get-ChildItem -LiteralPath $sigDir -Filter 'S*.json' -File -ErrorAction SilentlyContinue)
}

function Get-PresentTokens {
    # Every token present in the store the verb writes, or $null if it cannot be read.
    param([string]$Verb, $Proj)
    $found = New-Object System.Collections.Generic.List[string]
    try {
        if ($Verb -eq 'friction') {
            $st = [System.IO.File]::ReadAllText($Proj.StatePath) | ConvertFrom-Json
            if ($null -eq $st) { return $null }
            foreach ($ph in @($st.phases)) {
                if ($null -eq $ph.PSObject.Properties['friction']) { continue }
                foreach ($f in @($ph.friction)) { $found.Add("$($f.detail)") }
            }
        }
        elseif ($Verb -eq 'repo') {
            $cf = [System.IO.File]::ReadAllText($Proj.ConfigPath) | ConvertFrom-Json
            if ($null -eq $cf) { return $null }
            foreach ($rp in @($cf.repos.PSObject.Properties)) { $found.Add($rp.Name) }
        }
        else {
            foreach ($sf in @(Get-SignalFiles)) {
                $sg = [System.IO.File]::ReadAllText($sf.FullName) | ConvertFrom-Json
                if ($null -ne $sg) { $found.Add("$($sg.detail)") }
            }
        }
    }
    catch { return $null }
    return ,$found.ToArray()
}

function Write-RowList {
    param([string]$Label, [string]$Side, $Rows, $Present)
    if (-not $List) { return }
    $rn = 0
    foreach ($rw in @($Rows)) {
        $rn++
        Write-Output ("WRITE family={0} side={1} round={2} exit={3} present={4}" -f $Label, $Side, $rn, $rw.Code, $(if ($Present -contains $rw.Token) { 'yes' } else { 'no' }))
    }
}

function Invoke-Family {
    # Concurrent: two synchronised children, A on W1.1 and B on W1.2. Leaves its counts in
    # $script:LastFamily rather than returning them, because it also prints.
    param([string]$Label, [string]$Verb, $Proj, [string]$WrapperA, [string]$WrapperB)
    $readyA = "keel-cw-$runTag-$Label-ra"; $readyB = "keel-cw-$runTag-$Label-rb"
    $goA = "keel-cw-$runTag-$Label-ga"; $goB = "keel-cw-$runTag-$Label-gb"
    $evs = @{}
    foreach ($en in @($readyA, $readyB, $goA, $goB)) { $evs[$en] = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, $en) }
    $tb = "$tokenStem-$Label"
    $ca = Start-Child (Get-WriterScript $WrapperA $Verb $Proj.Dir 'W1.1' $tb 'A' $Pairs $readyA $goA)
    $cb = Start-Child (Get-WriterScript $WrapperB $Verb $Proj.Dir 'W1.2' $tb 'B' $Pairs $readyB $goB)
    try {
        for ($r = 1; $r -le $Pairs; $r++) {
            if (-not $evs[$readyA].WaitOne(120000) -or -not $evs[$readyB].WaitOne(120000)) { throw "Family $Label : a writer never became ready in round $r." }
            [void]$evs[$goA].Set(); [void]$evs[$goB].Set()
        }
        $ra = Complete-Child $ca
        $rb = Complete-Child $cb
    }
    finally { foreach ($ev in $evs.Values) { $ev.Dispose() } }
    $rowsA = @(ConvertFrom-Rows $ra.Out); $rowsB = @(ConvertFrom-Rows $rb.Out)
    if ($rowsA.Count -ne $Pairs -or $rowsB.Count -ne $Pairs) { throw "Family $Label : expected $Pairs rows from each writer, got $($rowsA.Count) and $($rowsB.Count)." }
    $present = Get-PresentTokens $Verb $Proj
    if ($null -eq $present) { throw "Family $Label : the store could not be read after the run." }
    $overlap = 0
    for ($k = 0; $k -lt $Pairs; $k++) {
        if ($rowsA[$k].T0 -lt $rowsB[$k].T1 -and $rowsB[$k].T0 -lt $rowsA[$k].T1) { $overlap++ }
    }
    $sideCounts = @{}
    foreach ($side in @('A', 'B')) {
        $rows = if ($side -eq 'A') { $rowsA } else { $rowsB }
        Write-RowList $Label $side $rows $present
        $sideCounts[$side] = [pscustomobject]@{
            Exit0 = @($rows | Where-Object { $_.Code -eq 0 }).Count
            NonZero = @($rows | Where-Object { $_.Code -ne 0 }).Count
            Present = @($rows | Where-Object { $present -contains $_.Token }).Count
            LostExit0 = @($rows | Where-Object { $_.Code -eq 0 -and $present -notcontains $_.Token }).Count
            PresentNonZero = @($rows | Where-Object { $_.Code -ne 0 -and $present -contains $_.Token }).Count
            Refused89 = @($rows | Where-Object { $_.Code -eq 89 }).Count
        }
    }
    $okSids = @(@($rowsA) + @($rowsB) | Where-Object { $_.Code -eq 0 -and $_.Sid -ne '' } | ForEach-Object { $_.Sid })
    $shared = @($okSids | Group-Object | Where-Object { $_.Count -gt 1 }).Count
    $res = [pscustomobject]@{
        Label = $Label; Overlap = $overlap; Attempted = 2 * $Pairs
        Exit0 = $sideCounts['A'].Exit0 + $sideCounts['B'].Exit0
        NonZero = $sideCounts['A'].NonZero + $sideCounts['B'].NonZero
        Present = $sideCounts['A'].Present + $sideCounts['B'].Present
        LostExit0 = $sideCounts['A'].LostExit0 + $sideCounts['B'].LostExit0
        LostExit0A = $sideCounts['A'].LostExit0; LostExit0B = $sideCounts['B'].LostExit0
        Refused89B = $sideCounts['B'].Refused89
        PresentNonZero = $sideCounts['A'].PresentNonZero + $sideCounts['B'].PresentNonZero
        SharedIds = $shared
    }
    Write-Output ("{0}: pairs={1} overlapped={2} attempted={3} exit0={4} nonzero={5} present={6} lostWithExit0={7} lostWithExit0A={8} lostWithExit0B={9} presentButNonzero={10} sharedIds={11}" -f `
        $Label, $Pairs, $res.Overlap, $res.Attempted, $res.Exit0, $res.NonZero, $res.Present, $res.LostExit0, $res.LostExit0A, $res.LostExit0B, $res.PresentNonZero, $res.SharedIds)
    $script:LastFamily = $res
}

function Invoke-Sequential {
    param([string]$Label, [string]$Verb, $Proj, [string]$Wrapper)
    $tb = "$tokenStem-$Label"
    $c = Start-Child (Get-WriterScript $Wrapper $Verb $Proj.Dir 'W1.1' $tb 'S' (2 * $Pairs) '' '')
    $r = Complete-Child $c
    $rows = @(ConvertFrom-Rows $r.Out)
    $present = Get-PresentTokens $Verb $Proj
    if ($null -eq $present) { throw "Sequential $Label : the store could not be read after the run." }
    Write-RowList $Label 'S' $rows $present
    $res = [pscustomobject]@{
        Label = $Label; Attempted = $rows.Count
        Exit0 = @($rows | Where-Object { $_.Code -eq 0 }).Count
        Present = @($rows | Where-Object { $present -contains $_.Token }).Count
    }
    Write-Output ("{0}: attempted={1} exit0={2} present={3}" -f $Label, $res.Attempted, $res.Exit0, $res.Present)
    $script:LastSeq = $res
}

function New-FakeGit {
    # A git.cmd that marks it was reached, waits for go.flag, then fails. Every later call fails
    # at once. ping is the wait because timeout refuses a redirected input.
    $fgDir = Join-Path $scratchFull ('fakegit-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $fgDir -Force | Out-Null
    $fgLines = @(
        '@echo off',
        'if exist "%~dp0paused.flag" exit /b 1',
        'echo paused> "%~dp0paused.flag"',
        ':wait',
        'if exist "%~dp0go.flag" exit /b 1',
        'ping -n 2 127.0.0.1 >nul',
        'goto wait'
    )
    [System.IO.File]::WriteAllText((Join-Path $fgDir 'git.cmd'), (($fgLines -join "`r`n") + "`r`n"))
    $fakeDirs.Add($fgDir)
    return $fgDir
}

function Start-TimedWriter {
    # One wrapper call in a fresh process, printing when it started and ended. With $FakeGitDir the
    # fake git is first on its PATH.
    param([string]$Wrapper, [string]$CallText, [string]$FakeGitDir)
    $pathLine = ''
    if ($FakeGitDir) { $pathLine = "`$env:PATH = '$FakeGitDir;' + `$env:PATH; " }
    return Start-Child ($pathLine + "`$t0 = [DateTime]::UtcNow.Ticks; & '$Wrapper' $CallText | Out-Null; `$c = `$LASTEXITCODE; [Console]::Out.WriteLine('ROW t0=' + `$t0 + ' t1=' + [DateTime]::UtcNow.Ticks + ' code=' + `$c); exit 0")
}

function Read-TimedRow {
    param($Done)
    if ("$($Done.Out)" -match 'ROW t0=([0-9]+) t1=([0-9]+) code=(-?[0-9]+)') {
        return [pscustomobject]@{ T0 = [long]$Matches[1]; T1 = [long]$Matches[2]; Code = [int]$Matches[3]; Err = "$($Done.Err)" }
    }
    return [pscustomobject]@{ T0 = 0L; T1 = 0L; Code = -1; Err = "$($Done.Err)" }
}

function Get-VerifyVerdict {
    param([string]$StatePath)
    try {
        $vst = [System.IO.File]::ReadAllText($StatePath) | ConvertFrom-Json
        $vph = @($vst.phases | Where-Object { $_.id -eq 'W1.1' })
        if ($vph.Count -ne 1) { return '' }
        $vg = $vph[0].gates.PSObject.Properties['verify']
        if ($null -eq $vg) { return '' }
        return "$($vg.Value.verdict)"
    }
    catch { return '' }
}

function Get-HeadWrapper {
    # The wrapper and its plugin manifest at HEAD, byte for byte, laid out as the wrapper expects
    # so its version lookup resolves.
    $root = Join-Path $scratchFull 'headcopy\keel-workflow'
    $pairsList = @(
        @('plugins/keel-workflow/skills/keel-orchestrator/wrappers/keel-state.ps1', (Join-Path $root 'skills\keel-orchestrator\wrappers\keel-state.ps1')),
        @('plugins/keel-workflow/.claude-plugin/plugin.json', (Join-Path $root '.claude-plugin\plugin.json'))
    )
    foreach ($pr in $pairsList) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $pr[1]) -Force | Out-Null
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'git'
        $psi.Arguments = "-C `"$repoRoot`" cat-file blob HEAD:$($pr[0])"
        $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
        $gp = [System.Diagnostics.Process]::Start($psi)
        $fs = [System.IO.File]::Create($pr[1])
        try { $gp.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
        $gp.WaitForExit()
        if ($gp.ExitCode -ne 0) { throw "git could not read $($pr[0]) at HEAD." }
    }
    return $pairsList[0][1]
}

# ------------------------------------------------------------- the run --
$exitCode = 0
try {
    $env:USERPROFILE = $scratchFull
    $env:KEEL_OUTWARD = 'block'
    New-Item -ItemType Directory -Path $scratchFull -Force | Out-Null
    Assert-ChildSeesScratch

    $families = @(
        @{ Label = 'STATE'; Verb = 'friction' },
        @{ Label = 'REPO'; Verb = 'repo' },
        @{ Label = 'SIGNAL'; Verb = 'signal' }
    )

    if (-not $AgainstHead) {
        foreach ($fm in $families) {
            $pc = New-ScratchProject $underTest ($fm.Label + 'c')
            Invoke-Family $fm.Label $fm.Verb $pc $underTest $underTest
            $fr = $script:LastFamily
            Add-Case "$($fm.Label)-overlapped" ($fr.Overlap -ge 20) "$($fr.Overlap) of $Pairs rounds had both writes in flight at once"
            Add-Case "$($fm.Label)-no-silent-loss" ($fr.LostExit0 -eq 0) "$($fr.LostExit0) write(s) absent while their command exited 0"
            Add-Case "$($fm.Label)-every-write-landed" ($fr.NonZero -eq 0 -and $fr.Present -eq $fr.Attempted) "$($fr.Present) of $($fr.Attempted) present, $($fr.NonZero) refused"
            if ($fm.Verb -eq 'signal') {
                Add-Case 'SIGNAL-no-shared-id' ($fr.SharedIds -eq 0) "$($fr.SharedIds) id(s) printed by two successful filings"
                $misnamed = 0
                foreach ($sf in @(Get-SignalFiles)) {
                    $sgObj = [System.IO.File]::ReadAllText($sf.FullName) | ConvertFrom-Json
                    if ($null -eq $sgObj -or "$($sgObj.id)" -ne $sf.BaseName) { $misnamed++ }
                }
                Add-Case 'SIGNAL-file-name-is-id' ($misnamed -eq 0 -and @(Get-SignalFiles).Count -gt 0) "$misnamed of $(@(Get-SignalFiles).Count) signal file(s) hold an id other than their name"
            }
            $ps = New-ScratchProject $underTest ($fm.Label + 's')
            Invoke-Sequential ($fm.Label + '-SEQ') $fm.Verb $ps $underTest
            $sr = $script:LastSeq
            Add-Case "$($fm.Label)-sequential-control" ($sr.Attempted -eq 2 * $Pairs -and $sr.Exit0 -eq $sr.Attempted -and $sr.Present -eq $sr.Attempted) "$($sr.Present) of $($sr.Attempted) present, $($sr.Exit0) exited 0"
        }

        # ----------------------------------------------------------- HELD --
        $ph = New-ScratchProject $underTest 'held'
        $mx = New-Object System.Threading.Mutex($false, (Get-LockNameFor $ph.StatePath))
        [void]$mx.WaitOne()
        $shaBefore = Get-Sha $ph.StatePath
        $tokHeld = "$tokenStem-HELD-1"
        $heldCall = "note-friction -Path '$($ph.Dir)' -Phase W1.1 -Kind gap -Detail '$tokHeld'"
        $hr = Read-TimedRow (Complete-Child (Start-TimedWriter $underTest $heldCall '') 60000)
        $shaAfter = Get-Sha $ph.StatePath
        $mx.ReleaseMutex(); $mx.Dispose()
        $heldMs = [int](($hr.T1 - $hr.T0) / 10000)
        Add-Case 'HELD-exit-89' ($hr.Code -eq 89) "the write exited $($hr.Code) while the lock was held"
        Add-Case 'HELD-waited-the-bound' ($hr.T1 -gt 0 -and $heldMs -ge $LockWaitMs) "the write gave up after $heldMs ms"
        Add-Case 'HELD-names-the-rerun' ($hr.Err -match 're-run') 'the refusal message says to re-run'
        Add-Case 'HELD-state-unchanged' ($shaBefore -ne '' -and $shaBefore -eq $shaAfter) 'state.json SHA-256 equal before and after the refused write'
        $hr2 = Read-TimedRow (Complete-Child (Start-TimedWriter $underTest $heldCall '') 60000)
        $presentHeld = Get-PresentTokens 'friction' $ph
        Add-Case 'HELD-control-after-release' ($hr2.Code -eq 0 -and $null -ne $presentHeld -and $presentHeld -contains $tokHeld) "after the release the same write exited $($hr2.Code)"

        # --------------------------------------------------------- PAUSED --
        $verifyCall = { param($pj) "record-verdict -Path '$($pj.Dir)' -Phase W1.1 -Gate verify -Verdict PASS" }

        # CHANGED: a foreign write lands while the writer waits between its read and its write.
        $pcg = New-ScratchProject $underTest 'changed' -WithRepo
        $fg = New-FakeGit
        $wa = Start-TimedWriter $underTest (& $verifyCall $pcg) $fg
        if (-not (Wait-ForFile (Join-Path $fg 'paused.flag') 30000)) { throw 'PAUSED CHANGED: the writer never reached git.' }
        # The same JSON plus one trailing space: still valid, and a different file.
        $foreign = [byte[]]([System.IO.File]::ReadAllBytes($pcg.StatePath) + [byte]0x20)
        [System.IO.File]::WriteAllBytes($pcg.StatePath, $foreign)
        $shaForeign = Get-Sha $pcg.StatePath
        [System.IO.File]::WriteAllText((Join-Path $fg 'go.flag'), 'go')
        $war = Read-TimedRow (Complete-Child $wa 60000)
        Add-Case 'PAUSED-CHANGED-exit-89' ($war.Code -eq 89) "the write exited $($war.Code) after state.json changed under it"
        Add-Case 'PAUSED-CHANGED-names-the-rerun' ($war.Err -match 're-run') 'the refusal message says to re-run'
        Add-Case 'PAUSED-CHANGED-foreign-write-kept' ((Get-Sha $pcg.StatePath) -eq $shaForeign) 'state.json is byte-equal to what the foreign writer left'

        $pcc = New-ScratchProject $underTest 'changedctl' -WithRepo
        $fg = New-FakeGit
        $wc = Start-TimedWriter $underTest (& $verifyCall $pcc) $fg
        if (-not (Wait-ForFile (Join-Path $fg 'paused.flag') 30000)) { throw 'PAUSED CHANGED control: the writer never reached git.' }
        [System.IO.File]::WriteAllText((Join-Path $fg 'go.flag'), 'go')
        $wcr = Read-TimedRow (Complete-Child $wc 60000)
        $ctlVerdict = Get-VerifyVerdict $pcc.StatePath
        Add-Case 'PAUSED-CHANGED-control' ($wcr.Code -eq 0 -and $ctlVerdict -eq 'PASS') "with no foreign write the same verb exited $($wcr.Code) and recorded '$ctlVerdict'"

        # KILLED: the writer holding the lock is killed while a second one waits.
        $pk = New-ScratchProject $underTest 'killed' -WithRepo
        $fg = New-FakeGit
        $wk = Start-TimedWriter $underTest (& $verifyCall $pk) $fg
        if (-not (Wait-ForFile (Join-Path $fg 'paused.flag') 30000)) { throw 'PAUSED KILLED: the writer never reached git.' }
        $tokKilled = "$tokenStem-KILLED-1"
        $wn = Start-TimedWriter $underTest "note-friction -Path '$($pk.Dir)' -Phase W1.2 -Kind gap -Detail '$tokKilled'" ''
        Start-Sleep -Milliseconds 2500
        $killTicks = [DateTime]::UtcNow.Ticks
        $wk.Proc.Kill(); [void]$wk.Proc.WaitForExit(10000)
        $wnr = Read-TimedRow (Complete-Child $wn 60000)
        [System.IO.File]::WriteAllText((Join-Path $fg 'go.flag'), 'go')
        $presentKilled = Get-PresentTokens 'friction' $pk
        $afterKillMs = [int](($wnr.T1 - $killTicks) / 10000)
        Add-Case 'PAUSED-KILLED-next-write-landed' ($wnr.Code -eq 0 -and $null -ne $presentKilled -and $presentKilled -contains $tokKilled) "the waiting write exited $($wnr.Code) after the lock holder was killed"
        Add-Case 'PAUSED-KILLED-was-waiting' ($wnr.T1 -gt $killTicks) 'the waiting write finished after the kill, so it was waiting on the killed holder'
        Add-Case 'PAUSED-KILLED-within-the-wait' ($wnr.T1 -gt 0 -and $afterKillMs -lt $LockWaitMs) "it finished $afterKillMs ms after the kill, against a wait of $LockWaitMs ms"

        $pkc = New-ScratchProject $underTest 'killedctl' -WithRepo
        $fg = New-FakeGit
        $wkc = Start-TimedWriter $underTest (& $verifyCall $pkc) $fg
        if (-not (Wait-ForFile (Join-Path $fg 'paused.flag') 30000)) { throw 'PAUSED KILLED control: the writer never reached git.' }
        $tokLive = "$tokenStem-LIVE-1"
        $wl = Start-TimedWriter $underTest "note-friction -Path '$($pkc.Dir)' -Phase W1.2 -Kind gap -Detail '$tokLive'" ''
        Start-Sleep -Milliseconds 2500
        $goTicks = [DateTime]::UtcNow.Ticks
        [System.IO.File]::WriteAllText((Join-Path $fg 'go.flag'), 'go')
        $wkcr = Read-TimedRow (Complete-Child $wkc 60000)
        $wlr = Read-TimedRow (Complete-Child $wl 60000)
        $presentLive = Get-PresentTokens 'friction' $pkc
        Add-Case 'PAUSED-KILLED-control-live-holder-waits' ($wkcr.Code -eq 0 -and $wlr.Code -eq 0 -and $wlr.T1 -gt $goTicks -and $null -ne $presentLive -and $presentLive -contains $tokLive) "holder exited $($wkcr.Code); the second write exited $($wlr.Code), finishing $([int](($wlr.T1 - $goTicks) / 10000)) ms after the holder was released"
    }
    else {
        $headWrapper = Get-HeadWrapper
        $repoHead = $null
        foreach ($fm in $families) {
            $pc = New-ScratchProject $headWrapper ($fm.Label + 'hc')
            Invoke-Family ('HEAD-' + $fm.Label) $fm.Verb $pc $headWrapper $headWrapper
            $headRun = $script:LastFamily
            if ($fm.Label -eq 'STATE') {
                Add-Case 'HEAD-STATE-loses-a-write' ($headRun.LostExit0 -ge 1) "$($headRun.LostExit0) write(s) absent with exit 0 at HEAD; the suite can see a loss"
            }
            elseif ($fm.Label -eq 'REPO') { $repoHead = $headRun }
            else {
                Add-Case 'HEAD-REPO-or-SIGNAL-loses-a-write' (($repoHead.LostExit0 + $headRun.LostExit0 + $headRun.SharedIds) -ge 1) "REPO lost $($repoHead.LostExit0), SIGNAL lost $($headRun.LostExit0) with $($headRun.SharedIds) shared id(s), all with exit 0"
            }
            $ps = New-ScratchProject $headWrapper ($fm.Label + 'hs')
            Invoke-Sequential ('HEAD-' + $fm.Label + '-SEQ') $fm.Verb $ps $headWrapper
            $sr = $script:LastSeq
            Add-Case "HEAD-$($fm.Label)-sequential-control" ($sr.Attempted -eq 2 * $Pairs -and $sr.Exit0 -eq $sr.Attempted -and $sr.Present -eq $sr.Attempted) "$($sr.Present) of $($sr.Attempted) present at HEAD"
        }

        # MIXED: a HEAD writer (no lock) on W1.1 against the working-tree writer on W1.2.
        $pm = New-ScratchProject $wtWrapper 'mixed'
        Invoke-Family 'MIXED' 'friction' $pm $headWrapper $wtWrapper
        $mixed = $script:LastFamily
        $pmc = New-ScratchProject $headWrapper 'mixedctl'
        Invoke-Family 'MIXED-CONTROL' 'friction' $pmc $headWrapper $headWrapper
        $mixedCtl = $script:LastFamily
        # Reported, not scored. A writer that takes no lock can still overwrite a locked
        # writer's write when it read before that write and writes after it, so whether a race
        # run shows a loss on the working-tree side is chance. LIMIT below shows it on purpose.
        Write-Output ("REPORT  MIXED - working-tree writer: {0} write(s) absent with exit 0, {1} refused with 89; HEAD writer: {2} absent with exit 0; the HEAD+HEAD control lost {3}" -f `
            $mixed.LostExit0B, $mixed.Refused89B, $mixed.LostExit0A, $mixedCtl.LostExit0)

        # LIMIT: the overwrite, forced. A HEAD writer is stopped between its read and its write
        # by the fake git; a working-tree write lands meanwhile and exits 0; the HEAD writer is
        # released and writes back what it read. This case PASSES when the working-tree write
        # is lost: it pins the limit the CHANGELOG states (run one version of keel at a time),
        # and it fails the day an older copy can no longer write over a newer one.
        $pf = New-ScratchProject $headWrapper 'forced' -WithRepo
        $fgf = New-FakeGit
        $wh = Start-TimedWriter $headWrapper "record-verdict -Path '$($pf.Dir)' -Phase W1.1 -Gate verify -Verdict PASS" $fgf
        if (-not (Wait-ForFile (Join-Path $fgf 'paused.flag') 30000)) { throw 'LIMIT: the HEAD writer never reached git.' }
        $tokForced = "$tokenStem-FORCED-1"
        $wwr = Read-TimedRow (Complete-Child (Start-TimedWriter $wtWrapper "note-friction -Path '$($pf.Dir)' -Phase W1.2 -Kind gap -Detail '$tokForced'" '') 60000)
        [System.IO.File]::WriteAllText((Join-Path $fgf 'go.flag'), 'go')
        $whr = Read-TimedRow (Complete-Child $wh 60000)
        $presentForced = Get-PresentTokens 'friction' $pf
        $forcedLost = ($null -ne $presentForced -and $presentForced -notcontains $tokForced)
        Add-Case 'LIMIT-unlocked-writer-overwrites-after' ($wwr.Code -eq 0 -and $whr.Code -eq 0 -and $forcedLost) "working-tree write exited $($wwr.Code) and is $(if ($forcedLost) { 'absent' } else { 'present' }) after the HEAD writer that read before it exited $($whr.Code)"
    }
}
catch {
    Write-Output "HARNESS: FAILED - $($_.Exception.Message.Replace($scratchFull, '<scratch>'))"
    $exitCode = 6
}
finally {
    # Release any fake git still waiting, so no orphaned cmd.exe outlives the run.
    foreach ($fgd in $fakeDirs) {
        try { [System.IO.File]::WriteAllText((Join-Path $fgd 'go.flag'), 'go') } catch { }
    }
    Start-Sleep -Milliseconds 2500
    $env:USERPROFILE = $realProfile
    if ($null -eq $realOutward) { Remove-Item Env:\KEEL_OUTWARD -ErrorAction SilentlyContinue } else { $env:KEEL_OUTWARD = $realOutward }
    if (-not $Keep -and (Test-Path -LiteralPath $scratchFull) -and $scratchFull.StartsWith($tempFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $scratchFull -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The breach check: nothing of this run may exist in the real state home.
$breach = @($slugs | Where-Object { Test-Path -LiteralPath (Join-Path $realProjects $_) })
$leaked = 0
foreach ($rf in @(Get-ChildItem -LiteralPath $realSignals -Filter 'S*.json' -File -ErrorAction SilentlyContinue)) {
    if ([System.IO.File]::ReadAllText($rf.FullName).Contains($tokenStem)) { $leaked++ }
}
if ($breach.Count -gt 0 -or $leaked -gt 0) {
    Write-Output "BREACH: the real state home holds $($breach.Count) project(s) and $leaked signal file(s) of this run."
    exit 5
}
Write-Output 'FENCE: the real state home holds no project and no signal of this run.'
Write-Output ("test-concurrent-writes: {0} case(s), {1} failure(s), {2} inconclusive" -f $script:CaseCount, $script:FailCount, $script:InconCount)
if ($exitCode -ne 0) { exit $exitCode }
if ($script:FailCount -gt 0) { exit 1 }
exit 0
