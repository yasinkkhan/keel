<#
    test-ordered-plan.ps1 - the suite for the order between workstreams: 'order' on workstreams and
    on placed phases, the 'order' verb, needs on whole workstreams, the walk 'status' names next by,
    'tree's positions, and the same in a project that shares its progress through its repo.

    Runs in a scratch home ONLY. USERPROFILE and COMPUTERNAME are set for every wrapper call; HOME
    and GIT_CONFIG_GLOBAL point at an empty scratch file and GIT_CONFIG_NOSYSTEM is set, so no real
    git identity is read; KEEL_OUTWARD is 'block' throughout. The suite refuses to start (exit 90)
    unless its scratch home resolves inside %TEMP%, and after the run the real state home must hold
    no project of this run.

    Groups, each case paired with a control that must print differently:
      WALK     an ordered workstream with no phases is 'plan W<n>', one with every phase finished
               'close W<n>'; two workstreams at one run order are named by the order, with no
               ambiguity warning; a placed phase runs at its own position, then the workstreams in
               order, then 'close', then the next; a workstream need holds it; an unplaced workstream
               is warned about and never named; tree prints positions. Controls: the same fixture
               with no order prints what the baseline wrapper prints, and today's line.
      VERB     'order' with no arguments, ordered and not; every placing call leaves the orders of
               unfinished items distinct; -Before rewrites one record; -Set's refusals and its
               omitted-placed refusal; add-workstream's place beside its epic; workstream -Needs and
               its refusals; an epic moved as a block.
      SHARED   a bare remote and two clones, two people (and a third who owns nothing): the new keys
               and only them; a shared order, a need with no file and a cycle through a workstream's
               needs after a merge, each with a control; next, others and unowned by the walk; the
               warning when a keel older than this one drops a key or makes a hand-over; any person
               places work, while a phase keeps its owner.
      HOOK     scripts/keel-session-start.ps1 beside the wrapper prints nothing for a clean ordered
               project, and the unplaced warning when there is one.

    Modes, human-invoked and not on the push path:
      -AgainstWrapper <path>  every row against that wrapper copy, which must sit in a copy of the
                              repo's layout (its plugin folder and scripts/), as git archive makes.
      -RealProjects           read only: for every project under the real %USERPROFILE%\.keel\projects,
                              matched by name both ways with the folders found by their keel.json,
                              status -Path and tree -Path with the baseline wrapper and this one: exit
                              codes, lines and state.json SHA-256 before and after. Positive control: a
                              scratch project before and after one 'order -Set'.
    -BaseRef <rev> (default HEAD) is the wrapper the controls compare with; once this change is
    committed that compares the wrapper with itself, which the rows say, and every control also
    asserts today's line by its text. -OldRef <rev> (default v0.85.0) is a keel that predates the
    order, for the warning about a dropped key; the suite refuses at 90 if it knows 'order'.

    Summary line, parsed by check-suite-docs.ps1 (a declared coupling):
      test-ordered-plan: <n> case(s), <n> failure(s)
    Exit codes: 0 no failures; 1 failures; 5 a breach of the real state home; 6 the harness failed;
    90 refused to start. Windows PowerShell 5.1, ASCII only.
#>

param(
    [string]$AgainstWrapper = '',
    [string]$BaseRef = 'HEAD',
    [string]$OldRef = 'v0.85.0',
    [switch]$RealProjects,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$nl = [string][char]10

function Stop-Suite {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("test-ordered-plan: $Message")
    exit $Code
}

# ------------------------------------------------------------- the fence --
if ([string]::IsNullOrWhiteSpace($env:TEMP)) { Stop-Suite 90 'TEMP is not set, so the fence cannot be checked.' }
$tempFull = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\', '/')
$runTag = [guid]::NewGuid().ToString('N').Substring(0, 8)
$scratch = [System.IO.Path]::GetFullPath((Join-Path $tempFull ('keel-op-' + $runTag))).TrimEnd('\', '/')
if (-not $scratch.StartsWith($tempFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    Stop-Suite 90 'Refusing to run: the scratch home does not resolve inside the temp directory.'
}
if (Test-Path -LiteralPath $scratch) { Stop-Suite 90 'Refusing to run: the scratch home already exists.' }
New-Item -ItemType Directory -Path $scratch | Out-Null

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$wrapperRel = 'plugins\keel-workflow\skills\keel-orchestrator\wrappers\keel-state.ps1'
$wtWrapper = Join-Path $repoRoot $wrapperRel
if (-not (Test-Path -LiteralPath $wtWrapper)) { Stop-Suite 90 'The working-tree wrapper was not found under plugins/.' }
$utWrapper = $wtWrapper
if ($AgainstWrapper) {
    if (-not (Test-Path -LiteralPath $AgainstWrapper)) { Stop-Suite 90 '-AgainstWrapper names no file.' }
    $utWrapper = (Resolve-Path -LiteralPath $AgainstWrapper).Path
}
# The session-start hook that sits beside the wrapper under test, in the same repo layout.
$utRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $utWrapper)))))
$utHook = Join-Path $utRoot 'scripts\keel-session-start.ps1'

$realEnv = @{}
foreach ($evName in @('USERPROFILE', 'COMPUTERNAME', 'HOME', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'KEEL_OUTWARD')) {
    $realEnv[$evName] = [Environment]::GetEnvironmentVariable($evName, 'Process')
}
$realStateHome = Join-Path (Join-Path $realEnv['USERPROFILE'] '.keel') 'projects'
$realProjectsBefore = @()
if (Test-Path -LiteralPath $realStateHome) { $realProjectsBefore = @(Get-ChildItem -LiteralPath $realStateHome -Directory | ForEach-Object { $_.Name }) }

$gitEmpty = Join-Path $scratch 'gitconfig-empty'
[System.IO.File]::WriteAllText($gitEmpty, '')
$env:HOME = $scratch
$env:GIT_CONFIG_GLOBAL = $gitEmpty
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:KEEL_OUTWARD = 'block'

# ------------------------------------------------------------ results --
$script:CaseCount = 0
$script:FailCount = 0
$script:Added = @{}
function Add-Case {
    param([string]$CaseName, [bool]$Ok, [string]$Info)
    $script:CaseCount++
    $script:Added[$CaseName] = $true
    if ($Ok) { Write-Output "PASS  $CaseName - $Info" }
    else { $script:FailCount++; Write-Output "FAIL  $CaseName - $Info" }
}
function Set-RowsFailed {
    # A case whose setup was refused fails each of its rows not yet scored, with the reason, so a
    # wrapper without the feature scores failures instead of stopping the run.
    param([string[]]$FrNames, $FrError)
    $frMsg = if ($FrError -is [System.Management.Automation.ErrorRecord]) { $FrError.Exception.Message } else { [string]$FrError }
    foreach ($frN in $FrNames) { if (-not $script:Added.ContainsKey($frN)) { Add-Case $frN $false "setup or run failed: $frMsg" } }
}

# ------------------------------------------------------------ helpers --
function Get-Sha {
    param([byte[]]$ShaBytes)
    $shaAlg = [System.Security.Cryptography.SHA256]::Create()
    try { return (-join ($shaAlg.ComputeHash($ShaBytes) | ForEach-Object { $_.ToString('x2') })) }
    finally { $shaAlg.Dispose() }
}

function Invoke-K {
    # One wrapper call in its own powershell.exe, as one machine.
    param([string]$KHome, [string]$KMachine, [string[]]$KArgs, [string]$KWrapper = '')
    if (-not $KWrapper) { $KWrapper = $utWrapper }
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
    return [pscustomobject]@{ Code = $kCode; Out = ($kOut -join $nl); Err = ($kErr -join $nl); Lines = $kOut.ToArray() }
}

function Invoke-G {
    param([string]$GDir, [string[]]$GArgs)
    $gPrior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = -1
    $gRaw = & git -C $GDir @GArgs 2>&1
    $gCode = $LASTEXITCODE
    $ErrorActionPreference = $gPrior
    $gText = (@($gRaw) | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" } }) -join $nl
    return [pscustomobject]@{ Code = $gCode; Out = $gText }
}
function Assert-G {
    param([string]$GDir, [string[]]$GArgs)
    $agRes = Invoke-G $GDir $GArgs
    if ($agRes.Code -ne 0) { throw "git '$($GArgs[0])' exited $($agRes.Code): $($agRes.Out)" }
    return $agRes
}

# A fixture: one project folder and the home and machine that write it.
function New-Fx {
    param([string]$FxLabel, [string]$FxHome, [string]$FxMachine = 'KOP-M', [switch]$FxGit, [string]$FxUser = 'Order Person')
    $fxDir = Join-Path $scratch "projects\$FxLabel$runTag"
    New-Item -ItemType Directory -Path $fxDir -Force | Out-Null
    $fxObj = [pscustomobject]@{ Dir = $fxDir; Home = $FxHome; Machine = $FxMachine; Slug = (Split-Path -Leaf $fxDir) }
    $fxInit = @('init-project', '-Title', "fixture $FxLabel")
    if ($FxGit) {
        Assert-G $fxDir @('init', '-q', '-b', 'main') | Out-Null
        foreach ($fxC in @(@('user.name', $FxUser), @('user.email', 'suite@example.invalid'), @('pull.rebase', 'false'), @('core.autocrlf', 'false'))) { Assert-G $fxDir @('config', $fxC[0], $fxC[1]) | Out-Null }
    }
    else { $fxInit += '-NoGit' }
    Invoke-X $fxObj $fxInit -XMust | Out-Null
    Invoke-X $fxObj @('add-goal', '-Id', 'G1', '-Text', 'the goal') -XMust | Out-Null
    return $fxObj
}

function Invoke-X {
    # A wrapper call on a fixture; -XMust throws on a non-zero exit, which fails the case's rows.
    param($XFx, [string[]]$XArgs, [switch]$XMust, [string]$XWrapper = '')
    $xRes = Invoke-K $XFx.Home $XFx.Machine (@($XArgs) + @('-Path', $XFx.Dir)) $XWrapper
    if ($XMust -and $xRes.Code -ne 0) { throw "'$($XArgs[0])' exited $($xRes.Code): $($xRes.Err) $($xRes.Out)" }
    return $xRes
}

function Get-StateFile { param($SfFx) return (Join-Path $SfFx.Home ".keel\projects\$($SfFx.Slug)\state.json") }
function Get-StateSha { param($SsFx) return (Get-Sha ([System.IO.File]::ReadAllBytes((Get-StateFile $SsFx)))) }
function Read-StateObj { param($RsFx) return ([System.IO.File]::ReadAllText((Get-StateFile $RsFx)) | ConvertFrom-Json) }

function Test-Line {
    # Whether the output holds this exact line.
    param($TlRes, [string]$TlLine)
    foreach ($tlL in @($TlRes.Lines)) { if ($tlL -ceq $TlLine) { return $true } }
    return $false
}
function Test-LineRe {
    param($TrRes, [string]$TrPattern)
    foreach ($trL in @($TrRes.Lines)) { if ($trL -cmatch $TrPattern) { return $true } }
    return $false
}
function Get-NextLine {
    param($GnRes)
    foreach ($gnL in @($GnRes.Lines)) { if ($gnL -like 'KEEL:   next:*') { return $gnL } }
    return '(no next: line)'
}
function Get-Comparable {
    # The lines two wrappers are compared on: the version-drift warning, which any version bump
    # prints, left out.
    param($GcRes)
    return ((@($GcRes.Lines) | Where-Object { $_ -notmatch 'planned under keel|Check the CHANGELOG between them' }) -join $nl)
}

$GateVerdict = [ordered]@{ ground = 'DONE'; investigate = 'DONE'; plan = 'APPROVED'; implement = 'DONE'; verify = 'PASS'; human = 'APPROVED'; enact = 'N/A'; record = 'DONE' }
function Complete-Phase {
    # Delivers a phase through all eight gates, its artifacts written as the gates require.
    param($CpFx, [string]$CpPhase)
    $cpDir = Join-Path $CpFx.Home ".keel\projects\$($CpFx.Slug)\phases\$CpPhase"
    if (Test-Path -LiteralPath (Join-Path $CpFx.Dir 'progress')) { $cpDir = Join-Path $CpFx.Dir "progress\phases\$CpPhase\artifacts" }
    New-Item -ItemType Directory -Path $cpDir -Force | Out-Null
    $cpEnc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $cpDir 'grounding.md'), "Measured: fixture$($nl)$($nl)Not read: nothing else$nl", $cpEnc)
    [System.IO.File]::WriteAllText((Join-Path $cpDir 'investigation.md'), "Positive control: fixture$nl", $cpEnc)
    [System.IO.File]::WriteAllText((Join-Path $cpDir 'plan.md'), "## Changes$($nl)$($nl)- the fixture file$nl", $cpEnc)
    [System.IO.File]::WriteAllText((Join-Path $cpDir 'act-log.md'), "Done by: claude$($nl)Done on: 2026-01-01$($nl)Produced: the fixture file$nl", $cpEnc)
    [System.IO.File]::WriteAllText((Join-Path $cpDir 'verify-report.md'), "| $CpPhase-C1 | PASS | run-by: agent |$($nl)$($nl)Positive control: fixture$nl", $cpEnc)
    [System.IO.File]::WriteAllText((Join-Path $cpDir 'delivery-record.md'), "# $($CpPhase.ToUpper()) delivered$($nl)$($nl)Docs impact: none$($nl)$($nl)Remaining phases: unchanged$nl", $cpEnc)
    foreach ($cpG in @($GateVerdict.Keys)) {
        Invoke-X $CpFx @('record-verdict', '-Phase', $CpPhase, '-Gate', $cpG, '-Verdict', $GateVerdict[$cpG]) -XMust | Out-Null
    }
}

function Add-Ws {
    param($AwFx, [string]$AwId, [string]$AwTitle, [string]$AwParent = 'root', [string[]]$AwMore = @())
    Invoke-X $AwFx (@('add-workstream', '-Id', $AwId, '-Title', $AwTitle, '-Parent', $AwParent, '-Goals', 'G1') + @($AwMore)) -XMust | Out-Null
}
function Add-Ph {
    param($ApFx, [string]$ApId, [int]$ApOrder)
    Invoke-X $ApFx @('add-phase', '-Phase', $ApId, '-Scope', "phase $ApId", '-Actor', 'agent', '-RunOrder', "$ApOrder") -XMust | Out-Null
}

# The baseline and older wrappers, each in a copy of the repo's layout so it reads its own version.
function Get-RefWrapper {
    param([string]$RwRef, [string]$RwLabel)
    $rwDir = Join-Path $scratch "ref-$RwLabel"
    New-Item -ItemType Directory -Path $rwDir -Force | Out-Null
    $rwTar = Join-Path $scratch "ref-$RwLabel.tar"
    $rwRes = Invoke-G $repoRoot @('archive', '--format=tar', '-o', $rwTar, $RwRef, 'plugins/keel-workflow', 'scripts')
    if ($rwRes.Code -ne 0) { return $null }
    $rwPrior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # The Windows tar, by its path: Git's own tar reads 'C:' in a path as a remote host.
    $rwTarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path -LiteralPath $rwTarExe) { & $rwTarExe -xf $rwTar -C $rwDir 2>&1 | Out-Null }
    else { & tar --force-local -xf $rwTar -C $rwDir 2>&1 | Out-Null }
    $rwCode = $LASTEXITCODE
    $ErrorActionPreference = $rwPrior
    $rwW = Join-Path $rwDir $wrapperRel
    if ($rwCode -ne 0 -or -not (Test-Path -LiteralPath $rwW)) { return $null }
    return $rwW
}
$baseWrapper = Get-RefWrapper $BaseRef 'base'
if ($null -eq $baseWrapper) { Stop-Suite 90 "-BaseRef '$BaseRef' could not be extracted." }
$baseSame = (Get-Sha ([System.IO.File]::ReadAllBytes($baseWrapper))) -eq (Get-Sha ([System.IO.File]::ReadAllBytes($utWrapper)))
$baseNote = if ($baseSame) { ' (the baseline is this wrapper, so that half compares it with itself)' } else { '' }
$oldWrapper = Get-RefWrapper $OldRef 'old'
if ($null -eq $oldWrapper) { Stop-Suite 90 "-OldRef '$OldRef' could not be extracted." }
if ([System.IO.File]::ReadAllText($oldWrapper) -match "(?m)^'order' \{") { Stop-Suite 90 "-OldRef '$OldRef' already knows 'order', so it cannot stand for an older keel." }


# ================================================================ main ==
$script:Harness = $null
try {
$hM = Join-Path $scratch 'homes\M'
New-Item -ItemType Directory -Path $hM -Force | Out-Null

if (-not $RealProjects) {
# ================================================================ WALK ==
# (a) an ordered workstream with no phases is 'plan W<n>'
$rows = @('WALK-a-plan', 'WALK-a-control')
try {
    $fa = New-Fx 'wa' $hM; Add-Ws $fa 'W1' 'Alpha'
    $fac = New-Fx 'wac' $hM; Add-Ws $fac 'W1' 'Alpha'
    Invoke-X $fa @('order', '-Set', 'W1') -XMust | Out-Null
    $sa = Invoke-X $fa @('status'); $sac = Invoke-X $fac @('status'); $sacB = Invoke-X $fac @('status') -XWrapper $baseWrapper
    Add-Case $rows[0] (Test-Line $sa 'KEEL:   next: plan W1  (Alpha - no phases yet)') "ordered: $(Get-NextLine $sa)"
    Add-Case $rows[1] ((-not (Test-LineRe $sac 'next: plan')) -and (Test-Line $sac 'KEEL:   No phases declared yet.') -and ((Get-Comparable $sac) -ceq (Get-Comparable $sacB)) -and ($sa.Out -cne $sac.Out)) "no order: prints No phases declared yet. and the baseline's lines$baseNote"
} catch { Set-RowsFailed $rows $_ }

# (b) an ordered workstream whose phases are all finished is 'close W<n>'
$rows = @('WALK-b-close', 'WALK-b-control')
try {
    $fb = New-Fx 'wb' $hM; Add-Ws $fb 'W1' 'Alpha'; Add-Ph $fb 'W1.1' 1; Complete-Phase $fb 'W1.1'
    $fbc = New-Fx 'wbc' $hM; Add-Ws $fbc 'W1' 'Alpha'; Add-Ph $fbc 'W1.1' 1; Complete-Phase $fbc 'W1.1'
    Invoke-X $fb @('order', '-Set', 'W1') -XMust | Out-Null
    $sb = Invoke-X $fb @('status'); $sbc = Invoke-X $fbc @('status'); $sbcB = Invoke-X $fbc @('status') -XWrapper $baseWrapper
    Add-Case $rows[0] (Test-Line $sb 'KEEL:   next: close W1  (Alpha - every phase finished)') "ordered: $(Get-NextLine $sb)"
    Add-Case $rows[1] ((Test-Line $sbc 'KEEL:   next: nothing pending.') -and ((Get-Comparable $sbc) -ceq (Get-Comparable $sbcB)) -and ($sb.Out -cne $sbc.Out)) "no order: $(Get-NextLine $sbc)$baseNote"
} catch { Set-RowsFailed $rows $_ }

# (c) two workstreams at run order 1, ordered the higher id first: no ambiguity
$rows = @('WALK-c-named', 'WALK-c-control')
try {
    $fc = New-Fx 'wc' $hM; Add-Ws $fc 'W1' 'Alpha'; Add-Ws $fc 'W2' 'Beta'; Add-Ph $fc 'W1.1' 1; Add-Ph $fc 'W2.1' 1
    $fcc = New-Fx 'wcc' $hM; Add-Ws $fcc 'W1' 'Alpha'; Add-Ws $fcc 'W2' 'Beta'; Add-Ph $fcc 'W1.1' 1; Add-Ph $fcc 'W2.1' 1
    Invoke-X $fc @('order', '-Set', 'W2,W1') -XMust | Out-Null
    $sc = Invoke-X $fc @('status'); $scc = Invoke-X $fcc @('status'); $sccB = Invoke-X $fcc @('status') -XWrapper $baseWrapper
    Add-Case $rows[0] ((Test-Line $sc 'KEEL:   next: W2.1  (phase W2.1)') -and -not (Test-LineRe $sc 'next is ambiguous')) "ordered W2,W1: $(Get-NextLine $sc)"
    Add-Case $rows[1] ((Test-LineRe $scc '^KEEL:   WARNING: next is ambiguous - 2 phases share the lowest run order 1, across 2 workstream\(s\)\.$') -and ((Get-Comparable $scc) -ceq (Get-Comparable $sccB))) "no order: the ambiguity warning, as the baseline prints it$baseNote"
} catch { Set-RowsFailed $rows $_ }

# (d) W2.1 placed at 1, W1 at 2, W2 at 3
$rows = @('WALK-d-placed-first', 'WALK-d-then-W1', 'WALK-d-then-close-W1', 'WALK-d-then-W2', 'WALK-d-control')
try {
    $fd = New-Fx 'wd' $hM; Add-Ws $fd 'W1' 'Alpha'; Add-Ws $fd 'W2' 'Beta'; Add-Ph $fd 'W1.1' 1; Add-Ph $fd 'W2.1' 1; Add-Ph $fd 'W2.2' 2
    $fdc = New-Fx 'wdc' $hM; Add-Ws $fdc 'W1' 'Alpha'; Add-Ws $fdc 'W2' 'Beta'; Add-Ph $fdc 'W1.1' 1; Add-Ph $fdc 'W2.1' 1; Add-Ph $fdc 'W2.2' 2
    Invoke-X $fd @('order', '-Set', 'W2.1,W1,W2') -XMust | Out-Null
    Invoke-X $fdc @('order', '-Set', 'W1,W2') -XMust | Out-Null
    $sd1 = Invoke-X $fd @('status')
    Add-Case $rows[0] (Test-Line $sd1 'KEEL:   next: W2.1  (phase W2.1)') "W2.1 placed first: $(Get-NextLine $sd1)"
    Complete-Phase $fd 'W2.1'
    $sd2 = Invoke-X $fd @('status')
    Add-Case $rows[1] (Test-Line $sd2 'KEEL:   next: W1.1  (phase W1.1)') "W2.1 delivered: $(Get-NextLine $sd2)"
    Complete-Phase $fd 'W1.1'
    $sd3 = Invoke-X $fd @('status')
    Add-Case $rows[2] (Test-Line $sd3 'KEEL:   next: close W1  (Alpha - every phase finished)') "W1.1 delivered: $(Get-NextLine $sd3)"
    Invoke-X $fd @('close', '-Ws', 'W1') -XMust | Out-Null
    $sd4 = Invoke-X $fd @('status')
    Add-Case $rows[3] (Test-Line $sd4 'KEEL:   next: W2.2  (phase W2.2)') "W1 closed: $(Get-NextLine $sd4)"
    $sdc = Invoke-X $fdc @('status')
    Add-Case $rows[4] ((Test-Line $sdc 'KEEL:   next: W1.1  (phase W1.1)') -and ($sdc.Out -cne $sd1.Out)) "W2.1 not placed is walked inside W2, after W1: $(Get-NextLine $sdc)"
} catch { Set-RowsFailed $rows $_ }

# (e) a workstream need holds it
$rows = @('WALK-e-waits', 'WALK-e-control')
try {
    $fe = New-Fx 'we' $hM; Add-Ws $fe 'W2' 'Beta'; Add-Ph $fe 'W2.1' 1; Add-Ws $fe 'W3' 'Gamma' 'root' @('-Needs', 'W2'); Add-Ph $fe 'W3.1' 1
    $fec = New-Fx 'wec' $hM; Add-Ws $fec 'W2' 'Beta'; Add-Ph $fec 'W2.1' 1; Add-Ws $fec 'W3' 'Gamma'; Add-Ph $fec 'W3.1' 1
    Invoke-X $fe @('order', '-Set', 'W3,W2') -XMust | Out-Null
    Invoke-X $fec @('order', '-Set', 'W3,W2') -XMust | Out-Null
    $se = Invoke-X $fe @('status'); $sec = Invoke-X $fec @('status')
    Add-Case $rows[0] ((Test-Line $se 'KEEL:   W3 waits on W2 (workstream PLANNED; open: W2.1 planned)') -and (Test-Line $se 'KEEL:   next: W2.1  (phase W2.1)')) "W3 first and needing W2: $(Get-NextLine $se)"
    Add-Case $rows[1] ((Test-Line $sec 'KEEL:   next: W3.1  (phase W3.1)') -and -not (Test-LineRe $sec 'waits on')) "no need: $(Get-NextLine $sec)"
} catch { Set-RowsFailed $rows $_ }

# (f) an unplaced workstream in an ordered project is warned about and never named
$rows = @('WALK-f-unplaced', 'WALK-f-control')
try {
    $ff = New-Fx 'wf' $hM; Add-Ws $ff 'W1' 'Alpha'; Add-Ws $ff 'W2' 'Beta'; Add-Ph $ff 'W1.1' 1; Add-Ph $ff 'W2.1' 1
    Invoke-X $ff @('set-waiting', '-Phase', 'W1.1', '-WaitingOn', 'Fixture Person', '-ReviewOn', '2099-01-01') -XMust | Out-Null
    Invoke-X $ff @('order', '-Id', 'W1', '-First') -XMust | Out-Null
    $sf = Invoke-X $ff @('status')
    Add-Case $rows[0] ((Test-Line $sf 'KEEL:   WARNING: 1 open workstream(s) have no place in the order: W2. Place each with: order -Id <id> -After <id>') -and -not (Test-LineRe $sf '^KEEL:   next: W2\.1')) "W2 unplaced: $(Get-NextLine $sf)"
    Invoke-X $ff @('order', '-Id', 'W2', '-After', 'W1') -XMust | Out-Null
    $sfc = Invoke-X $ff @('status')
    Add-Case $rows[1] ((-not (Test-LineRe $sfc 'have no place in the order')) -and (Test-Line $sfc 'KEEL:   next: W2.1  (phase W2.1)')) "once placed: $(Get-NextLine $sfc)"
} catch { Set-RowsFailed $rows $_ }

# (g) tree prints positions
$rows = @('WALK-g-tree', 'WALK-g-control')
try {
    $fg = New-Fx 'wg' $hM
    Invoke-X $fg @('add-epic', '-Id', 'E1', '-Title', 'Epic one', '-Groups', 'the first two workstreams') -XMust | Out-Null
    Add-Ws $fg 'W1' 'Alpha' 'E1'; Add-Ws $fg 'W2' 'Beta' 'E1'; Add-Ws $fg 'W3' 'Gamma'; Add-Ph $fg 'W2.1' 1
    $fgc = New-Fx 'wgc' $hM
    Invoke-X $fgc @('add-epic', '-Id', 'E1', '-Title', 'Epic one', '-Groups', 'the first two workstreams') -XMust | Out-Null
    Add-Ws $fgc 'W1' 'Alpha' 'E1'; Add-Ws $fgc 'W2' 'Beta' 'E1'; Add-Ws $fgc 'W3' 'Gamma'; Add-Ph $fgc 'W2.1' 1
    Invoke-X $fg @('order', '-Set', 'W1,W2.1,W2,W3') -XMust | Out-Null
    $tg = Invoke-X $fg @('tree'); $tgc = Invoke-X $fgc @('tree'); $tgcB = Invoke-X $fgc @('tree') -XWrapper $baseWrapper
    $tgOk = (Test-LineRe $tg 'W1 \[workstream\] Alpha  -> G1  \[PLANNED\]  #1$') -and (Test-LineRe $tg 'W2\.1 \[phase\] phase W2\.1  actor:agent  planned  #2$') -and
            (Test-LineRe $tg 'W2 \[workstream\] Beta  -> G1  \[PLANNED\]  #3$') -and (Test-LineRe $tg 'W3 \[workstream\] Gamma  -> G1  \[PLANNED\]  #4$') -and
            (Test-LineRe $tg 'groups: the first two workstreams   order: from #1$')
    Add-Case $rows[0] $tgOk 'tree: #1 W1, #2 W2.1, #3 W2, #4 W3, and E1 order: from #1'
    Add-Case $rows[1] ((-not (Test-LineRe $tgc '#\d+$')) -and ((Get-Comparable $tgc) -ceq (Get-Comparable $tgcB)) -and ($tg.Out -cne $tgc.Out)) "no order: no position on any line, and the baseline's tree$baseNote"
} catch { Set-RowsFailed $rows $_ }


# ================================================================ VERB ==
function Get-OpenOrders {
    # The orders of unfinished workstreams and phases in a state file, as text, and whether two share
    # one. A hashtable, so a single entry does not unroll.
    param($GoState)
    $goVals = New-Object System.Collections.Generic.List[decimal]
    foreach ($goN in @($GoState.nodes)) {
        if ($goN.role -ne 'workstream' -or @('DELIVERED', 'ABANDONED') -contains [string]$goN.status) { continue }
        if ($null -ne $goN.PSObject.Properties['order'] -and $null -ne $goN.order) { $goVals.Add([decimal]$goN.order) }
    }
    foreach ($goP in @($GoState.phases)) {
        if (@('delivered', 'abandoned', 'handed-over') -contains [string]$goP.stage) { continue }
        if ($null -ne $goP.PSObject.Properties['order'] -and $null -ne $goP.order) { $goVals.Add([decimal]$goP.order) }
    }
    $goDistinct = @($goVals | Sort-Object -Unique).Count -eq $goVals.Count
    return @{ Count = $goVals.Count; Distinct = $goDistinct; Text = (($goVals | ForEach-Object { [string]$_ }) -join ',') }
}
function Get-ItemSigs {
    # Every node and phase of a state file, serialised, by id.
    param($IsState)
    $isOut = @{}
    foreach ($isN in @($IsState.nodes)) { $isOut["n|$($isN.id)"] = ($isN | ConvertTo-Json -Depth 10 -Compress) }
    foreach ($isP in @($IsState.phases)) { $isOut["p|$($isP.id)"] = ($isP | ConvertTo-Json -Depth 10 -Compress) }
    return $isOut
}

# (a) order with no arguments
$rows = @('VERB-a-listing', 'VERB-a-unordered')
try {
    $va = New-Fx 'va' $hM
    Invoke-X $va @('add-epic', '-Id', 'E1', '-Title', 'Epic one', '-Groups', 'the first workstream') -XMust | Out-Null
    Add-Ws $va 'W1' 'Alpha' 'E1'; Add-Ws $va 'W2' 'Beta'; Add-Ph $va 'W1.1' 1; Add-Ph $va 'W2.1' 1; Add-Ph $va 'W2.2' 2
    $vau = New-Fx 'vau' $hM; Add-Ws $vau 'W1' 'Alpha'
    $vauSha = Get-StateSha $vau
    $oau = Invoke-X $vau @('order')
    Invoke-X $va @('order', '-Set', 'W1,W2.2,W2') -XMust | Out-Null
    $oa = Invoke-X $va @('order')
    $oaOk = ($oa.Code -eq 0) -and (Test-Line $oa "KEEL: order of $($va.Slug) - 2 unfinished workstream(s), 1 placed phase(s)") -and
            (Test-LineRe $oa '^  #1   W1     Alpha\s+\(E1\)\s+next item: W1\.1$') -and
            (Test-LineRe $oa '^  #2   W2\.2   phase W2\.2\s+\(W2\)\s+next item: W2\.2$') -and
            (Test-LineRe $oa '^  #3   W2     Beta\s+\(root\)\s+next item: W2\.1$')
    Add-Case $rows[0] $oaOk "exit $($oa.Code): the header and one line per position, with id, title, parent and next item"
    Add-Case $rows[1] (($oau.Code -eq 0) -and (Test-Line $oau "KEEL: order of $($vau.Slug) - nothing is placed, so status names next as it always has. Adopt an order with: order -Set <ids in order>") -and ((Get-StateSha $vau) -eq $vauSha) -and ($oau.Out -cne $oa.Out)) "exit $($oau.Code): says nothing is placed, state.json unchanged"
} catch { Set-RowsFailed $rows $_ }

# (b) every placing call leaves the orders of unfinished items distinct
$rows = @('VERB-b-set', 'VERB-b-add-workstream', 'VERB-b-before', 'VERB-b-after', 'VERB-b-first', 'VERB-b-last', 'VERB-b-control')
try {
    $vb = New-Fx 'vb' $hM
    foreach ($vbW in @('W1', 'W2', 'W3')) { Add-Ws $vb $vbW "ws $vbW" }
    $vbCalls = @(
        @{ Row = $rows[0]; Args = @('order', '-Set', 'W1,W2,W3') },
        @{ Row = $rows[1]; Args = @('add-workstream', '-Id', 'W4', '-Title', 'ws W4', '-Parent', 'root', '-Goals', 'G1') },
        @{ Row = $rows[2]; Args = @('order', '-Id', 'W4', '-Before', 'W2') },
        @{ Row = $rows[3]; Args = @('order', '-Id', 'W1', '-After', 'W4') },
        @{ Row = $rows[4]; Args = @('order', '-Id', 'W3', '-First') },
        @{ Row = $rows[5]; Args = @('order', '-Id', 'W2', '-Last') }
    )
    foreach ($vbC in $vbCalls) {
        $vbR = Invoke-X $vb $vbC.Args
        $vbO = Get-OpenOrders (Read-StateObj $vb)
        Add-Case $vbC.Row (($vbR.Code -eq 0) -and $vbO.Distinct -and $vbO.Count -eq 4 - [int]($vbC.Row -eq $rows[0])) "exit $($vbR.Code); orders $($vbO.Text), distinct: $($vbO.Distinct)"
    }
    # The control: the same instrument on a state with two equal orders reports them.
    $vbPlant = Read-StateObj $vb
    $vbPlant.nodes[0].order = $vbPlant.nodes[1].order
    $vbPO = Get-OpenOrders $vbPlant
    Add-Case $rows[6] (-not $vbPO.Distinct) "a planted copy with two equal orders: distinct $($vbPO.Distinct) ($($vbPO.Text))"
} catch { Set-RowsFailed $rows $_ }

# (c) -Before rewrites W3's record only
$rows = @('VERB-c-one-record', 'VERB-c-control')
try {
    $vc = New-Fx 'vc' $hM
    foreach ($vcW in @('W1', 'W2', 'W3')) { Add-Ws $vc $vcW "ws $vcW" }
    Add-Ph $vc 'W1.1' 1; Add-Ph $vc 'W2.1' 1; Add-Ph $vc 'W3.1' 1
    Invoke-X $vc @('order', '-Set', 'W1,W2,W3') -XMust | Out-Null
    $vcBefore = Get-ItemSigs (Read-StateObj $vc)
    Invoke-X $vc @('order', '-Id', 'W3', '-Before', 'W2') -XMust | Out-Null
    $vcAfter = Get-ItemSigs (Read-StateObj $vc)
    $vcMoved = @(@($vcBefore.Keys) | Where-Object { $vcBefore[$_] -cne $vcAfter[$_] })
    Add-Case $rows[0] (($vcMoved.Count -eq 1) -and ($vcMoved[0] -eq 'n|W3') -and (@($vcAfter.Keys).Count -eq @($vcBefore.Keys).Count)) "records changed: $($vcMoved -join ', ')"
    $vcS = Invoke-X $vc @('order')
    Add-Case $rows[1] (($vcBefore['n|W3'] -cne $vcAfter['n|W3']) -and (Test-LineRe $vcS '^  #2   W3 ')) "W3's record changed and W3 is now #2"
} catch { Set-RowsFailed $rows $_ }

# (d) -Set's refusals
$rows = @('VERB-d-unknown-94', 'VERB-d-twice-90', 'VERB-d-control', 'VERB-d-omitted-90', 'VERB-d-omitted-control')
try {
    $vd = New-Fx 'vd' $hM
    foreach ($vdW in @('W1', 'W2', 'W3')) { Add-Ws $vd $vdW "ws $vdW" }
    $vdSha = Get-StateSha $vd
    $vdU = Invoke-X $vd @('order', '-Set', 'W1,W9')
    Add-Case $rows[0] (($vdU.Code -eq 94) -and ((Get-StateSha $vd) -eq $vdSha)) "exit $($vdU.Code), state.json unchanged: $((Get-StateSha $vd) -eq $vdSha)"
    $vdT = Invoke-X $vd @('order', '-Set', 'W1,W2,W1')
    Add-Case $rows[1] (($vdT.Code -eq 90) -and ((Get-StateSha $vd) -eq $vdSha)) "exit $($vdT.Code), state.json unchanged: $((Get-StateSha $vd) -eq $vdSha)"
    $vdOk = Invoke-X $vd @('order', '-Set', 'W3,W1,W2')
    $vdL = Invoke-X $vd @('order')
    Add-Case $rows[2] (($vdOk.Code -eq 0) -and (Test-LineRe $vdL '^  #1   W3 ') -and (Test-LineRe $vdL '^  #2   W1 ') -and (Test-LineRe $vdL '^  #3   W2 ')) "exit $($vdOk.Code), printed back W3, W1, W2"
    $vdSha2 = Get-StateSha $vd
    $vdO = Invoke-X $vd @('order', '-Set', 'W1,W2')
    Add-Case $rows[3] (($vdO.Code -eq 90) -and ($vdO.Err -match 'Missing: W3') -and ((Get-StateSha $vd) -eq $vdSha2)) "exit $($vdO.Code), names W3, state.json unchanged"
    $vdOc = Invoke-X $vd @('order', '-Set', 'W1,W2,W3')
    Add-Case $rows[4] ($vdOc.Code -eq 0) "listing every placed item: exit $($vdOc.Code)"
} catch { Set-RowsFailed $rows $_ }

# (e) add-workstream's place: after the last under its epic, last at the root; none when unordered
$rows = @('VERB-e-beside-epic', 'VERB-e-root-last', 'VERB-e-empty-epic-last', 'VERB-e-control')
try {
    $ve = New-Fx 've' $hM
    Invoke-X $ve @('add-epic', '-Id', 'E1', '-Title', 'Epic one', '-Groups', 'the first two') -XMust | Out-Null
    Invoke-X $ve @('add-epic', '-Id', 'E2', '-Title', 'Epic two', '-Groups', 'nothing yet') -XMust | Out-Null
    Add-Ws $ve 'W1' 'ws W1' 'E1'; Add-Ws $ve 'W2' 'ws W2' 'E1'; Add-Ws $ve 'W3' 'ws W3'
    Invoke-X $ve @('order', '-Set', 'W1,W2,W3') -XMust | Out-Null
    Add-Ws $ve 'W4' 'ws W4' 'E1'
    $veL = Invoke-X $ve @('order')
    Add-Case $rows[0] ((Test-LineRe $veL '^  #3   W4 ') -and (Test-LineRe $veL '^  #4   W3 ')) 'W4 under E1 placed after W2, before W3'
    Add-Ws $ve 'W5' 'ws W5'
    $veL2 = Invoke-X $ve @('order')
    Add-Case $rows[1] (Test-LineRe $veL2 '^  #5   W5 ') 'W5 at the root placed last'
    Add-Ws $ve 'W6' 'ws W6' 'E2'
    $veL3 = Invoke-X $ve @('order')
    Add-Case $rows[2] (Test-LineRe $veL3 '^  #6   W6 ') 'W6 under an epic with nothing placed placed last'
    $vec = New-Fx 'vec' $hM; Add-Ws $vec 'W1' 'ws W1'; Add-Ph $vec 'W1.1' 1; Add-Ws $vec 'W2' 'ws W2'
    $vecN = @((Read-StateObj $vec).nodes | Where-Object { $_.id -eq 'W2' })[0]
    $vecS = Invoke-X $vec @('status'); $vecSB = Invoke-X $vec @('status') -XWrapper $baseWrapper
    Add-Case $rows[3] (($null -eq $vecN.PSObject.Properties['order']) -and ((Get-Comparable $vecS) -ceq (Get-Comparable $vecSB))) "no order: W2 has no order key and status is the baseline's$baseNote"
} catch { Set-RowsFailed $rows $_ }

# (f) workstream -Needs and its refusals
$rows = @('VERB-f-self-90', 'VERB-f-own-phase-90', 'VERB-f-cycle-90', 'VERB-f-unknown-94', 'VERB-f-control', 'VERB-f-none-clears')
try {
    $vf = New-Fx 'vf' $hM
    foreach ($vfW in @('W1', 'W2', 'W3')) { Add-Ws $vf $vfW "ws $vfW" }
    Add-Ph $vf 'W1.1' 1; Add-Ph $vf 'W2.1' 1; Add-Ph $vf 'W3.1' 1
    $vfSha = Get-StateSha $vf
    $vfS = Invoke-X $vf @('revise-workstream', '-Id', 'W1', '-Needs', 'W1')
    Add-Case $rows[0] (($vfS.Code -eq 90) -and ($vfS.Err -match 'cannot need itself') -and ((Get-StateSha $vf) -eq $vfSha)) "W1 needs W1: exit $($vfS.Code), nothing written"
    $vfP = Invoke-X $vf @('revise-workstream', '-Id', 'W1', '-Needs', 'W1.1')
    Add-Case $rows[1] (($vfP.Code -eq 90) -and ($vfP.Err -match 'cannot need its own phase') -and ((Get-StateSha $vf) -eq $vfSha)) "W1 needs its own W1.1: exit $($vfP.Code), nothing written"
    Invoke-X $vf @('revise-workstream', '-Id', 'W1', '-Needs', 'W2') -XMust | Out-Null
    $vfSha2 = Get-StateSha $vf
    $vfC = Invoke-X $vf @('revise-workstream', '-Id', 'W2', '-Needs', 'W1')
    Add-Case $rows[2] (($vfC.Code -eq 90) -and ($vfC.Err -match 'cycle') -and ((Get-StateSha $vf) -eq $vfSha2)) "W2 needs W1 while W1 needs W2: exit $($vfC.Code), nothing written"
    $vfU = Invoke-X $vf @('add-workstream', '-Id', 'W4', '-Title', 'ws W4', '-Parent', 'root', '-Goals', 'G1', '-Needs', 'W9')
    Add-Case $rows[3] (($vfU.Code -eq 94) -and ((Get-StateSha $vf) -eq $vfSha2)) "needs W9: exit $($vfU.Code), nothing written"
    $vfSt = Invoke-X $vf @('status')
    Add-Case $rows[4] (Test-Line $vfSt 'KEEL:   W1 waits on W2 (workstream PLANNED; open: W2.1 planned)') 'the valid need W1 -> W2 exited 0 and status prints its waits line'
    $vfN = Invoke-X $vf @('revise-workstream', '-Id', 'W1', '-Needs', 'none')
    $vfSt2 = Invoke-X $vf @('status')
    Add-Case $rows[5] (($vfN.Code -eq 0) -and -not (Test-LineRe $vfSt2 'waits on')) "-Needs none: exit $($vfN.Code), no waits line"
} catch { Set-RowsFailed $rows $_ }

# (g) an epic moved as a block
$rows = @('VERB-g-block', 'VERB-g-control')
try {
    $vg = New-Fx 'vg' $hM
    Invoke-X $vg @('add-epic', '-Id', 'E1', '-Title', 'Epic one', '-Groups', 'two workstreams') -XMust | Out-Null
    Add-Ws $vg 'W1' 'ws W1' 'E1'; Add-Ws $vg 'W2' 'ws W2' 'E1'; Add-Ws $vg 'W3' 'ws W3'; Add-Ws $vg 'W4' 'ws W4'; Add-Ph $vg 'W1.5' 5
    $vgc = New-Fx 'vgc' $hM
    Invoke-X $vgc @('add-epic', '-Id', 'E1', '-Title', 'Epic one', '-Groups', 'two workstreams') -XMust | Out-Null
    Add-Ws $vgc 'W1' 'ws W1' 'E1'; Add-Ws $vgc 'W2' 'ws W2' 'E1'; Add-Ws $vgc 'W3' 'ws W3'; Add-Ws $vgc 'W4' 'ws W4'; Add-Ph $vgc 'W1.5' 5
    Invoke-X $vg @('order', '-Set', 'W3,W1,W1.5,W2,W4') -XMust | Out-Null
    Invoke-X $vgc @('order', '-Set', 'W3,W1,W1.5,W2,W4') -XMust | Out-Null
    $vgB = Get-ItemSigs (Read-StateObj $vg)
    Invoke-X $vg @('order', '-Id', 'E1', '-Before', 'W3') -XMust | Out-Null
    $vgA = Get-ItemSigs (Read-StateObj $vg)
    $vgMoved = @(@($vgB.Keys) | Where-Object { $vgB[$_] -cne $vgA[$_] } | Sort-Object)
    $vgL = Invoke-X $vg @('order')
    $vgOk = (($vgMoved -join ',') -eq 'n|W1,n|W2') -and (Test-LineRe $vgL '^  #1   W1 ') -and (Test-LineRe $vgL '^  #2   W2 ') -and (Test-LineRe $vgL '^  #3   W3 ') -and (Test-LineRe $vgL '^  #4   W1\.5 ') -and (Test-LineRe $vgL '^  #5   W4 ')
    Add-Case $rows[0] $vgOk "moved: $($vgMoved -join ', '); W1, W2 before W3 in their order, W1.5 kept after W3"
    $vgcB = Get-ItemSigs (Read-StateObj $vgc)
    Invoke-X $vgc @('order', '-Id', 'W1', '-Before', 'W3') -XMust | Out-Null
    $vgcA = Get-ItemSigs (Read-StateObj $vgc)
    $vgcMoved = @(@($vgcB.Keys) | Where-Object { $vgcB[$_] -cne $vgcA[$_] })
    Add-Case $rows[1] (($vgcMoved -join ',') -eq 'n|W1') "order -Id W1 moves W1 alone: $($vgcMoved -join ', ')"
} catch { Set-RowsFailed $rows $_ }


# ============================================================== SHARED ==
function Save-Commit {
    param([string]$CDir, [string]$CMessage)
    Assert-G $CDir @('add', '-A') | Out-Null
    $cRes = Invoke-G $CDir @('-c', 'user.name=Suite Committer', 'commit', '-q', '-m', $CMessage)
    if ($cRes.Code -ne 0 -and $cRes.Out -notmatch 'nothing to commit') { throw "commit failed: $($cRes.Out)" }
}
function Save-Push { param([string]$SuDir, [string]$SuMsg) Save-Commit $SuDir $SuMsg; Assert-G $SuDir @('push', '-q') | Out-Null }
function Sync-Pair {
    # Both sides commit what they wrote; the second pushes first, the first merges it with plain git
    # pull and pushes, and the second pulls that back.
    param([string]$SyFirst, [string]$SySecond, [string]$SyMsg)
    Save-Commit $SyFirst "$SyMsg (first)"
    Save-Commit $SySecond "$SyMsg (second)"
    Assert-G $SySecond @('push', '-q') | Out-Null
    Assert-G $SyFirst @('pull', '-q', '--no-edit') | Out-Null
    Assert-G $SyFirst @('push', '-q') | Out-Null
    Assert-G $SySecond @('pull', '-q', '--no-edit') | Out-Null
}
function Get-Keys { param([string]$GkFile) return @(([System.IO.File]::ReadAllText($GkFile) | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $_.Name }) }
function Get-KeyDiff {
    param([string[]]$KdAfter, [string[]]$KdBefore)
    return (@($KdAfter | Where-Object { $KdBefore -notcontains $_ } | Sort-Object) -join ',')
}

$rows = @('SHARED-a-node-order', 'SHARED-a-node-needs', 'SHARED-a-phase-order', 'SHARED-a-control',
          'SHARED-c-next-A', 'SHARED-c-next-B', 'SHARED-c-control',
          'SHARED-b-clean-merge', 'SHARED-b-order-clash', 'SHARED-b-order-clash-control',
          'SHARED-b-need-no-file', 'SHARED-b-need-no-file-control', 'SHARED-b-cycle', 'SHARED-b-cycle-control',
          'SHARED-e-anyone-places', 'SHARED-e-control-88',
          'SHARED-d-old-drop', 'SHARED-d-control', 'SHARED-d-old-hand-over', 'SHARED-d-hand-over-control')
try {
    $sRemote = Join-Path $scratch 'sremote.git'
    New-Item -ItemType Directory -Path $sRemote -Force | Out-Null
    Assert-G $sRemote @('init', '-q', '--bare', '-b', 'main') | Out-Null
    $hA = Join-Path $scratch 'homes\A'; $hB = Join-Path $scratch 'homes\B'; $hC = Join-Path $scratch 'homes\C'
    foreach ($hX in @($hA, $hB, $hC)) { New-Item -ItemType Directory -Path $hX -Force | Out-Null }
    $sA = New-Fx 'sh' $hA 'KOP-A' -FxGit -FxUser 'Order A'
    Assert-G $sA.Dir @('remote', 'add', 'origin', $sRemote) | Out-Null
    Add-Ws $sA 'W1' 'One'; Add-Ws $sA 'W2' 'Two'; Add-Ws $sA 'W3' 'Three'
    Add-Ph $sA 'W1.1' 1
    Save-Commit $sA.Dir 'project'
    Invoke-X $sA @('share-progress') -XMust | Out-Null
    Save-Commit $sA.Dir 'shared'
    Assert-G $sA.Dir @('push', '-q', '-u', 'origin', 'main') | Out-Null
    $sBDir = Join-Path $scratch "cloneB\$($sA.Slug)"
    New-Item -ItemType Directory -Path (Join-Path $scratch 'cloneB') -Force | Out-Null
    Assert-G (Join-Path $scratch 'cloneB') @('clone', '-q', $sRemote, $sA.Slug) | Out-Null
    foreach ($sbc in @(@('user.name', 'Order B'), @('user.email', 'suite@example.invalid'), @('pull.rebase', 'false'), @('core.autocrlf', 'false'))) { Assert-G $sBDir @('config', $sbc[0], $sbc[1]) | Out-Null }
    $sB = [pscustomobject]@{ Dir = $sBDir; Home = $hB; Machine = 'KOP-B'; Slug = $sA.Slug }
    $sjB = Invoke-X $sB @('join') -XMust
    $pidB = if ($sjB.Out -match 'as person (p-[0-9a-f]{4}) ') { $Matches[1] } else { throw 'join on B printed no person id.' }
    Add-Ph $sB 'W2.1' 1
    Save-Push $sB.Dir 'B joins and plans'
    Assert-G $sA.Dir @('pull', '-q', '--no-edit') | Out-Null
    $pidA = [string](@(Get-ChildItem -LiteralPath (Join-Path $sA.Dir 'progress\people') -Filter '*.json' | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json } | Where-Object { @($_.machines) -contains 'KOP-A' })[0].id)

    # ---- (c)'s control first, before anything is placed: next and others as the baseline prints them
    $sCtlA = Invoke-X $sA @('status'); $sCtlAB = Invoke-X $sA @('status') -XWrapper $baseWrapper
    $sCtlNext = @(@($sCtlA.Lines) | Where-Object { $_ -like 'KEEL:   next:*' -or $_ -like 'KEEL:   others:*' }) -join $nl
    $sCtlNextB = @(@($sCtlAB.Lines) | Where-Object { $_ -like 'KEEL:   next:*' -or $_ -like 'KEEL:   others:*' }) -join $nl

    # ---- (a) the new keys, and only them
    $kW1 = Join-Path $sA.Dir 'progress\nodes\W1.json'
    $kW2 = Join-Path $sA.Dir 'progress\nodes\W2.json'
    $kW3 = Join-Path $sA.Dir 'progress\nodes\W3.json'
    $k1Before = Get-Keys $kW1; $k2Before = Get-Keys $kW2; $k3Before = Get-Keys $kW3
    Invoke-X $sA @('order', '-Set', 'W1,W2,W3') -XMust | Out-Null
    $k1After = Get-Keys $kW1
    Invoke-X $sA @('revise-workstream', '-Id', 'W3', '-Needs', 'W2') -XMust | Out-Null
    $k3After = Get-Keys $kW3
    Invoke-X $sA @('add-phase', '-Phase', 'W1.2', '-Scope', 'phase W1.2', '-Actor', 'agent', '-RunOrder', '2') -XMust | Out-Null
    $kP = Join-Path $sA.Dir 'progress\phases\W1.2\phase.json'
    $kPBefore = Get-Keys $kP
    Invoke-X $sA @('order', '-Id', 'W1.2', '-Last') -XMust | Out-Null
    $kPAfter = Get-Keys $kP
    Add-Case $rows[0] ((Get-KeyDiff $k1After $k1Before) -eq 'order') "W1.json gained: $(Get-KeyDiff $k1After $k1Before)"
    Add-Case $rows[1] ((Get-KeyDiff $k3After $k3Before) -eq 'needs,order') "W3.json gained: $(Get-KeyDiff $k3After $k3Before)"
    Add-Case $rows[2] ((Get-KeyDiff $kPAfter $kPBefore) -eq 'order') "W1.2's phase.json gained: $(Get-KeyDiff $kPAfter $kPBefore)"
    Add-Case $rows[3] (((Get-KeyDiff $k2Before $k1Before) -eq '') -and ((Get-KeyDiff (Get-Keys $kW2) $k2Before) -eq 'order')) 'an unplaced node file holds the same keys as another, and W2 gained order alone'
    Invoke-X $sA @('revise-workstream', '-Id', 'W3', '-Needs', 'none') -XMust | Out-Null
    Save-Push $sA.Dir 'A places'
    Assert-G $sB.Dir @('pull', '-q', '--no-edit') | Out-Null

    # ---- (c) next, others and unowned by the walk
    $scA = Invoke-X $sA @('status'); $scB = Invoke-X $sB @('status')
    $scAOk = (Test-Line $scA 'KEEL:   next: W1.1  (phase W1.1)') -and (Test-Line $scA "KEEL:   others: Order B ($pidB): W2.1") -and (Test-Line $scA 'KEEL:   unowned: plan W3 (Three)')
    $scBOk = (Test-Line $scB 'KEEL:   next: W2.1  (phase W2.1)') -and (Test-Line $scB "KEEL:   others: Order A ($pidA): W1.1") -and (Test-Line $scB 'KEEL:   unowned: plan W3 (Three)')
    Add-Case $rows[4] $scAOk "A: $(Get-NextLine $scA)"
    Add-Case $rows[5] $scBOk "B: $(Get-NextLine $scB)"
    Add-Case $rows[6] (($sCtlNext -ceq $sCtlNextB) -and ($sCtlNext -cnotmatch 'unowned') -and ($scA.Out -cne $sCtlA.Out)) "no order: next and others as the baseline prints them$baseNote"

    # ---- (b) the read-time checks after a merge
    $sbClean = Invoke-X $sA @('status')
    Add-Case $rows[7] (-not (Test-LineRe $sbClean 'WARNING: after a merge')) 'a clean merge prints no after-a-merge line'
    Add-Ws $sA 'W4' 'Four'
    Add-Ws $sB 'W5' 'Five'
    Sync-Pair $sA.Dir $sB.Dir 'two workstreams placed last on both sides'
    $sbO = Invoke-X $sA @('status')
    Add-Case $rows[8] (Test-Line $sbO 'KEEL:   WARNING: after a merge, W4 and W5 share order 5, so neither is named as next. Move one with order -Id W5 -After W4.') 'W4 and W5 each placed at 5 on its side, after W1.2 at 4'
    Invoke-X $sB @('order', '-Id', 'W5', '-After', 'W4') -XMust | Out-Null
    Save-Push $sB.Dir 'B moves W5'
    Assert-G $sA.Dir @('pull', '-q', '--no-edit') | Out-Null
    $sbOc = Invoke-X $sA @('status')
    Add-Case $rows[9] (-not (Test-LineRe $sbOc 'share order')) 'once W5 is moved, no shared order'
    Add-Ws $sA 'W6' 'Six'
    Invoke-X $sA @('revise-workstream', '-Id', 'W2', '-Needs', 'W6') -XMust | Out-Null
    Assert-G $sA.Dir @('add', '--', 'progress/nodes/W2.json') | Out-Null
    Assert-G $sA.Dir @('-c', 'user.name=Suite Committer', 'commit', '-q', '-m', 'W2 needs W6, W6 left out') | Out-Null
    Assert-G $sA.Dir @('push', '-q') | Out-Null
    Assert-G $sB.Dir @('pull', '-q', '--no-edit') | Out-Null
    $sbN = Invoke-X $sB @('status')
    Add-Case $rows[10] (Test-Line $sbN 'KEEL:   WARNING: after a merge, workstream W2 needs W6, which has no file under progress/nodes/. Pull again, or have whoever wrote it commit and push that file.') 'a partial commit carried the need and not W6'
    Save-Push $sA.Dir 'the rest'
    Assert-G $sB.Dir @('pull', '-q', '--no-edit') | Out-Null
    $sbNc = Invoke-X $sB @('status')
    Add-Case $rows[11] (-not (Test-LineRe $sbNc 'which has no file under')) 'once W6 is pushed, no such line'
    Invoke-X $sA @('revise-workstream', '-Id', 'W4', '-Needs', 'W5') -XMust | Out-Null
    Invoke-X $sB @('revise-workstream', '-Id', 'W5', '-Needs', 'W4') -XMust | Out-Null
    $sbCyB = Invoke-X $sB @('status')
    Sync-Pair $sA.Dir $sB.Dir 'two needs, each valid alone'
    $sbCy = Invoke-X $sA @('status')
    Add-Case $rows[12] (Test-LineRe $sbCy '^KEEL:   WARNING: after a merge, W4 and W5 need each other in a cycle, so neither can be named as next\. Re-declare one workstream''s needs with revise-workstream -Id W4 -Needs <ids, or none>\.$') 'W4 needs W5 on one side, W5 needs W4 on the other'
    Add-Case $rows[13] (-not (Test-LineRe $sbCyB 'in a cycle')) 'before the merge, the one side alone shows no cycle'
    Invoke-X $sA @('revise-workstream', '-Id', 'W4', '-Needs', 'none') -XMust | Out-Null
    Invoke-X $sA @('revise-workstream', '-Id', 'W5', '-Needs', 'none') -XMust | Out-Null
    Save-Push $sA.Dir 'cycle cleared'
    Assert-G $sB.Dir @('pull', '-q', '--no-edit') | Out-Null

    # ---- (e) a person who owns nothing places work; a phase keeps its owner
    Invoke-X $sA @('set-stage', '-Phase', 'W1.2', '-Stage', 'grounding') -XMust | Out-Null
    Save-Push $sA.Dir 'A starts W1.2'
    $sC = [pscustomobject]@{ Dir = $sA.Dir; Home = $hC; Machine = 'KOP-C'; Slug = $sA.Slug }
    Invoke-X $sC @('join') -XMust | Out-Null
    $seP = Invoke-X $sC @('order', '-Id', 'W1.2', '-First')
    Add-Case $rows[14] ($seP.Code -eq 0) "C, owning nothing, moves A's started placed phase W1.2: exit $($seP.Code)"
    $seS = Invoke-X $sC @('set-stage', '-Phase', 'W1.2', '-Stage', 'investigating')
    Add-Case $rows[15] ($seS.Code -eq 88) "C sets W1.2's stage: exit $($seS.Code)"
    Save-Push $sA.Dir 'C joins and places'

    # ---- (d) a keel older than this one drops a key, or hands a placed phase over
    Invoke-X $sA @('add-goal', '-Id', 'G2', '-Text', 'another goal') -XWrapper $oldWrapper -XMust | Out-Null
    $sdC = Invoke-X $sA @('status')
    Add-Case $rows[17] (-not (Test-LineRe $sdC 'held order at an earlier commit')) 'an older keel writing a goal leaves every placed file intact: no warning'
    Invoke-X $sA @('revise-workstream', '-Id', 'W1', '-Title', 'One renamed') -XWrapper $oldWrapper -XMust | Out-Null
    $sdD = Invoke-X $sA @('status')
    Add-Case $rows[16] (Test-Line $sdD 'KEEL:   WARNING: progress/nodes/W1.json held order at an earlier commit and no longer does - a keel older than this one rewrote it. Place it again with: order -Id W1 -After <id>') 'an older keel renamed W1 and dropped its order'
    Save-Push $sA.Dir 'older keel'
    Add-Ph $sA 'W2.5' 5
    Invoke-X $sA @('order', '-Id', 'W2.5', '-Last') -XMust | Out-Null
    Invoke-X $sA @('set-stage', '-Phase', 'W2.5', '-Stage', 'grounding') -XMust | Out-Null
    Invoke-X $sA @('hand-over', '-Phase', 'W2.5', '-To', $pidB, '-Detail', 'fixture') -XMust | Out-Null
    $sdHc = Invoke-X $sA @('status')
    Add-Case $rows[19] ((-not (Test-LineRe $sdHc 'continues W2\.5, which held a place')) -and ($null -ne (Get-Content -Raw -LiteralPath (Join-Path $sA.Dir 'progress\phases\W2.5b\phase.json') | ConvertFrom-Json).PSObject.Properties['order'])) 'this keel hands W2.5 over and W2.5b keeps the place'
    Add-Ph $sA 'W2.6' 6
    Invoke-X $sA @('order', '-Id', 'W2.6', '-Last') -XMust | Out-Null
    Invoke-X $sA @('set-stage', '-Phase', 'W2.6', '-Stage', 'grounding') -XMust | Out-Null
    Invoke-X $sA @('hand-over', '-Phase', 'W2.6', '-To', $pidB, '-Detail', 'fixture') -XWrapper $oldWrapper -XMust | Out-Null
    $sdH = Invoke-X $sA @('status')
    Add-Case $rows[18] (Test-Line $sdH 'KEEL:   WARNING: W2.6b continues W2.6, which held a place in the order, but holds none itself - a keel older than this one handed it over. Place it again with: order -Id W2.6b -After <id>') 'an older keel handed W2.6 over without its place'
} catch { Set-RowsFailed $rows $_ }

# ================================================================ HOOK ==
function Invoke-Hook {
    # The session-start hook beside the wrapper under test, run in the fixture's folder.
    param($IhFx)
    if (-not (Test-Path -LiteralPath $utHook)) { throw 'no keel-session-start.ps1 beside the wrapper under test' }
    $env:USERPROFILE = $IhFx.Home
    $env:COMPUTERNAME = $IhFx.Machine
    $ihPrior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location -LiteralPath $IhFx.Dir
    try { $ihRaw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $utHook 2>$null }
    finally { Pop-Location; $ErrorActionPreference = $ihPrior }
    return @(@($ihRaw) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and [string]$_ -notmatch 're-pointed core\.hooksPath' } | ForEach-Object { [string]$_ })
}
$rows = @('HOOK-clean-silent', 'HOOK-unplaced-control')
try {
    $hk = New-Fx 'hk' $hM; Add-Ws $hk 'W1' 'Alpha'; Add-Ph $hk 'W1.1' 1
    Invoke-X $hk @('order', '-Set', 'W1') -XMust | Out-Null
    $hkc = New-Fx 'hkc' $hM; Add-Ws $hkc 'W1' 'Alpha'; Add-Ph $hkc 'W1.1' 1; Add-Ws $hkc 'W2' 'Beta'
    Invoke-X $hkc @('order', '-Set', 'W1') -XMust | Out-Null
    $hkOut = @(Invoke-Hook $hk); $hkcOut = @(Invoke-Hook $hkc)
    Add-Case $rows[0] ($hkOut.Count -eq 0) "an ordered project with nothing to warn of: $($hkOut.Count) line(s)"
    Add-Case $rows[1] (@($hkcOut | Where-Object { $_ -ceq 'KEEL:   WARNING: 1 open workstream(s) have no place in the order: W2. Place each with: order -Id <id> -After <id>' }).Count -eq 1) "one unplaced workstream: $($hkcOut.Count) line(s), the unplaced warning among them"
} catch { Set-RowsFailed $rows $_ }

Write-Output 'NOT RUN  -RealProjects - human-invoked, read only over the real state home.'
}


# ======================================================== -RealProjects ==
if ($RealProjects) {
    Write-Output 'NOT RUN  WALK, VERB, SHARED, HOOK - -RealProjects runs the comparison alone.'
    $rpAllowed = 'planned under keel|Check the CHANGELOG between them|COULD NOT REACH|have NOT reached|is NOT on the remote|STALE - written at|was NOT checked'
    function Compare-Wrappers {
        # status and tree with the baseline wrapper, then this one: exit codes, lines (the allowed
        # ones set aside and quoted), and state.json's SHA-256 before and after.
        param([string]$CwHome, [string]$CwDir, [string]$CwState)
        $cwShaBefore = Get-Sha ([System.IO.File]::ReadAllBytes($CwState))
        $cwOut = New-Object System.Collections.Generic.List[string]
        $cwSame = $true
        foreach ($cwVerb in @('status', 'tree')) {
            $cwA = Invoke-K $CwHome $realEnv['COMPUTERNAME'] @($cwVerb, '-Path', $CwDir) $baseWrapper
            $cwB = Invoke-K $CwHome $realEnv['COMPUTERNAME'] @($cwVerb, '-Path', $CwDir) $utWrapper
            if ($cwA.Code -ne $cwB.Code) { $cwSame = $false; $cwOut.Add("$cwVerb exit $($cwA.Code) then $($cwB.Code)") }
            # The allowed lines leave both sides first, so the rest still line up and a line moved
            # out of place still counts; each allowed line one side printed and the other did not is
            # quoted.
            $cwAKeep = @(@($cwA.Lines) | Where-Object { $_ -notmatch $rpAllowed })
            $cwBKeep = @(@($cwB.Lines) | Where-Object { $_ -notmatch $rpAllowed })
            foreach ($cwD in @(Compare-Object -ReferenceObject @($cwAKeep) -DifferenceObject @($cwBKeep) -SyncWindow 0 -CaseSensitive)) {
                $cwSame = $false; $cwOut.Add("DIFFERS: $cwVerb $($cwD.SideIndicator) $($cwD.InputObject)")
            }
            $cwAAllowed = @(@($cwA.Lines) | Where-Object { $_ -match $rpAllowed })
            $cwBAllowed = @(@($cwB.Lines) | Where-Object { $_ -match $rpAllowed })
            foreach ($cwD in @(Compare-Object -ReferenceObject @($cwAAllowed) -DifferenceObject @($cwBAllowed) -CaseSensitive)) {
                $cwOut.Add("allowed: $cwVerb $($cwD.SideIndicator) $($cwD.InputObject)")
            }
        }
        $cwShaAfter = Get-Sha ([System.IO.File]::ReadAllBytes($CwState))
        if ($cwShaBefore -ne $cwShaAfter) { $cwSame = $false; $cwOut.Add('state.json SHA-256 moved') }
        return [pscustomobject]@{ Same = $cwSame; Notes = $cwOut.ToArray() }
    }
    $rpStates = @(Get-ChildItem -LiteralPath $realStateHome -Directory | Sort-Object Name)
    $rpRoot = Split-Path -Parent (Split-Path -Parent $repoRoot)
    $rpFolders = @{}
    foreach ($rpK in @(Get-ChildItem -LiteralPath (Split-Path -Parent $repoRoot) -Recurse -Depth 3 -Filter 'keel.json' -File -ErrorAction SilentlyContinue)) {
        $rpCfg = $null
        try { $rpCfg = [System.IO.File]::ReadAllText($rpK.FullName) | ConvertFrom-Json } catch { $rpCfg = $null }
        if ($null -eq $rpCfg -or $null -eq $rpCfg.PSObject.Properties['name']) { continue }
        $rpLeaf = Split-Path -Leaf $rpK.DirectoryName
        if (-not $rpFolders.ContainsKey($rpLeaf)) { $rpFolders[$rpLeaf] = $rpK.DirectoryName }
    }
    $rpNames = @($rpStates | ForEach-Object { $_.Name })
    $rpNoFolder = @($rpNames | Where-Object { -not $rpFolders.ContainsKey($_) })
    $rpNoState = @(@($rpFolders.Keys) | Where-Object { $rpNames -notcontains $_ } | Sort-Object)
    Add-Case 'REAL-census' ($rpNoFolder.Count -eq 0) "$($rpNames.Count) state folder(s): $($rpNames -join ', '); with no project folder: $($rpNoFolder -join ', '); folders with no state: $($rpNoState -join ', ')"
    foreach ($rpS in $rpStates) {
        if (-not $rpFolders.ContainsKey($rpS.Name)) { continue }
        $rpState = Join-Path $rpS.FullName 'state.json'
        if (-not (Test-Path -LiteralPath $rpState)) { Add-Case "REAL-$($rpS.Name)" $false 'no state.json'; continue }
        $rpCmp = Compare-Wrappers $realEnv['USERPROFILE'] $rpFolders[$rpS.Name] $rpState
        Add-Case "REAL-$($rpS.Name)" $rpCmp.Same ("$($rpFolders[$rpS.Name]); " + $(if ($rpCmp.Notes.Count -gt 0) { $rpCmp.Notes -join ' | ' } else { 'identical' }))
    }
    # The positive control: the same comparison on a scratch project after one 'order -Set'.
    $rpFx = New-Fx 'rp' $hM; Add-Ws $rpFx 'W1' 'Alpha'; Add-Ws $rpFx 'W2' 'Beta'; Add-Ph $rpFx 'W1.1' 1
    $rpBefore = Compare-Wrappers $hM $rpFx.Dir (Get-StateFile $rpFx)
    Invoke-X $rpFx @('order', '-Set', 'W2,W1') -XMust | Out-Null
    $rpAfter = Compare-Wrappers $hM $rpFx.Dir (Get-StateFile $rpFx)
    Add-Case 'REAL-control' ($rpBefore.Same -and -not $rpAfter.Same) "a scratch project compares equal before 'order -Set' ($($rpBefore.Same)) and differs after ($(-not $rpAfter.Same))"
}
}
catch {
    $script:Harness = $_
}
finally {
    foreach ($evName in @($realEnv.Keys)) { [Environment]::SetEnvironmentVariable($evName, $realEnv[$evName], 'Process') }
}

if ($null -ne $script:Harness) {
    Write-Output "test-ordered-plan: $($script:CaseCount) case(s), $($script:FailCount + 1) failure(s)"
    [Console]::Error.WriteLine("test-ordered-plan: the harness failed: $($script:Harness.Exception.Message)")
    exit 6
}

# The real state home must hold no project of this run.
$realProjectsAfter = @()
if (Test-Path -LiteralPath $realStateHome) { $realProjectsAfter = @(Get-ChildItem -LiteralPath $realStateHome -Directory | ForEach-Object { $_.Name }) }
$breach = @($realProjectsAfter | Where-Object { $realProjectsBefore -notcontains $_ -and $_ -like "*$runTag" })
if ($breach.Count -gt 0) {
    Write-Output "test-ordered-plan: $($script:CaseCount) case(s), $($script:FailCount + 1) failure(s)"
    [Console]::Error.WriteLine('test-ordered-plan: a project of this run appeared in the real state home.')
    exit 5
}
if (-not $Keep) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output "test-ordered-plan: $($script:CaseCount) case(s), $($script:FailCount) failure(s)"
if ($script:FailCount -gt 0) { exit 1 }
exit 0
