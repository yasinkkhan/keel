<#
    test-history-ids.ps1 - the verification suite for the history check, section 18 of
    check-suite-docs.ps1.

    WHAT IT COVERS. The check refuses keel's own record ids - workstream and phase ids
    numbered 10 or more, signal ids, issue numbers, trap numbers and dated measurements -
    in the contents and paths of every file in the repository: the staged ones at the
    commit gate, every tracked one at push. An allowlist lets the product's own example
    values through. Each behaviour below has a control that must behave DIFFERENTLY,
    because a refusal that refuses everything is indistinguishable from one that reads the
    patterns:

      - each of the five kinds, staged in a skill file, refuses and names file and line;
        the same file holding only allowlisted examples and placeholders passes
      - the commit gate reads the STAGED blob: an id only in the working tree passes, the
        same change staged refuses
      - the scope is every path: the same text in a script, in another folder, in
        CHANGELOG.md, in a nested scripts/ folder elsewhere or in a lookalike name refuses;
        the same file without the id passes
      - README.md and DESIGN-CHARTER.md each refuse an id staged and tracked, and pass
        with it removed
      - an HTML character reference such as &#9472; passes and an issue number in the same
        file refuses; a CSS hex colour passes, in a page and in a skill file, and an issue
        number beside it refuses
      - '#' and six digits passes and '#' and five digits refuses
      - a path holding an id refuses at both gates; the same content under a clean name
        passes
      - at push, an id in a tracked script that is not staged refuses; reverted, it passes
      - each allowlisted example passes alone; an id one digit away from each refuses
      - a single-digit workstream id passes and a two-digit one refuses; a letter right
        before a signal id stops the match and a space does not
      - a binary file is skipped; the same bytes without the NUL are not

    A row's result carries the exit code and, where the check printed it, the number of
    lines or paths it refused. -List prints every row with that result, passing rows too.

    HOW IT REACHES THE CHECK ALONE. Every other validator section fails in a scratch
    repository, so the suite copies the validator into <scratch>\repo\scripts\ (untracked,
    so neither gate reads it) and runs that copy with -HistoryOnly, which runs section 18
    and the verdict only. -AgainstValidator <path> runs the same cases against another
    copy - the way to show the suite can fail: point it at a copy whose patterns never
    match and the refusal rows must fail.

    ISOLATION, VERIFIED BEFORE ANYTHING IS WRITTEN. The scratch root must resolve inside
    the system temp directory. Git variables a hook may export are cleared first, and the
    suite refuses to run unless git resolves the scratch repository as its own top level -
    otherwise a run from inside a hook could commit into the repository being pushed.

    FIXTURE IDS ARE ASSEMBLED AT RUN TIME. This file is under scripts/, so the real check
    reads it; a literal id here would make every commit and push of this repository refuse
    it. Only the allowlisted examples appear literally.

    IT PRINTS NO PATH. Section 19 copies this suite's output into the validator's notes on
    a failure, and the scratch paths sit under the home folder. A failure line carries the
    row name and the exit code, a failed git step names only its subcommand, and the suite
    never relays a child's output.

    Run it:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-history-ids.ps1
      ... -AgainstValidator <path>   run the cases against another validator file
      ... -List                      print every row, passing ones included

    Exit 0 = every case behaved. Exit 1 = at least one did not.

    Windows PowerShell 5.1 compatible. ASCII only.
#>

[CmdletBinding()]
param(
    [string]$AgainstValidator = '',
    [switch]$Quiet,
    [switch]$List
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Every local in this file is Hi-prefixed, so none can collide with a parameter name.
$HiRepoRoot  = Split-Path -Parent $PSScriptRoot
$HiValidator = Join-Path $HiRepoRoot 'scripts\check-suite-docs.ps1'
if (-not [string]::IsNullOrWhiteSpace($AgainstValidator)) {
    $HiValidator = (Resolve-Path -LiteralPath $AgainstValidator).Path
}

$script:HiResults = @()

# Adds to a script-scope list and returns nothing: a function that both printed and
# returned a value would hand its caller an array of every line it emitted.
function Add-Result {
    param([string]$HiName, [bool]$HiOk, [string]$HiWhy)
    $script:HiResults += [pscustomobject]@{ Name = $HiName; Ok = $HiOk; Why = $HiWhy }
}

# A native tool's success text can arrive on stderr, and 2>&1 under 'Stop' turns it into
# a terminating error, so every native call sets Continue and lets the EXIT CODE decide.
function Invoke-HiGit {
    param([string[]]$HiGitArgs)
    $HiPrev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & git -C $script:HiRepo @HiGitArgs 2>$null
        $HiGitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $HiPrev }
    if ($HiGitCode -ne 0) { throw "fixture: git $($HiGitArgs[0]) failed (exit $HiGitCode)" }
}

function Invoke-HiCheck {
    param([string]$HiMode)
    $HiPrev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $HiLines = @()
    $HiCode = 0
    try {
        $HiLines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:HiCopy $HiMode -HistoryOnly 2>&1 |
                   ForEach-Object { $_.ToString() }
        $HiCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $HiPrev }
    return [pscustomobject]@{ Code = $HiCode; Text = (@($HiLines) -join "`n") }
}

# The number of lines or paths the check says it refused, read out of its ran line, or -1
# when that line is absent. Escaped and anchored on the leading ', ', so 1 cannot read 11.
function Get-HiRefusedCount {
    param([string]$HiText)
    $HiM = [regex]::Match($HiText, ', ([0-9]+) line\(s\) or path\(s\) refused')
    if (-not $HiM.Success) { return -1 }
    return [int]$HiM.Groups[1].Value
}

function Set-HiFile {
    param([string]$HiName, [string]$HiContent)
    $HiFull = Join-Path $script:HiRepo $HiName
    $HiDir = Split-Path -Parent $HiFull
    if (-not (Test-Path -LiteralPath $HiDir)) { New-Item -ItemType Directory -Path $HiDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($HiFull, $HiContent, (New-Object System.Text.UTF8Encoding($false)))
}

function Remove-HiFile {
    param([string]$HiName)
    $HiFull = Join-Path $script:HiRepo $HiName
    if (Test-Path -LiteralPath $HiFull) { Remove-Item -LiteralPath $HiFull -Force }
}

# Back to the base commit: the index and every tracked file. Untracked files a row
# created are removed by that row, because git clean would also remove the validator copy.
function Reset-HiRepo {
    Invoke-HiGit @('reset', '-q', '--hard')
}

# ---------------------------------------------------------------------------
# The cases
# ---------------------------------------------------------------------------
function Invoke-Cases {
    # Fixture ids, assembled so that the real check never reads one in this file.
    $HiPhase  = 'W' + '41.1'
    $HiSig    = 'S' + '0101'
    $HiTrap   = 'tr' + 'ap 13'
    $HiIssue  = 'issue #' + '88'
    $HiHash   = '#' + '88'
    $HiBareWs = 'W' + '65'
    $HiLabel  = 'CONTROL-w' + '462-x'
    $HiMeas   = 'Meas' + 'ured 2026-09-07'
    $HiSkill  = 'plugins/keel-x/skills/s/SKILL.md'
    $HiSkillRx = 'plugins/keel-x/skills/s/SKILL\.md line 2 '
    $HiTool   = 'scripts/tool.ps1'
    $HiBadPath = 'scripts/W' + '47-notes.ps1'
    $HiSixHash  = '#' + '123456'
    $HiFiveHash = '#' + '12345'
    $HiColours = ':root { --ink:#10222C; --surface:#183039; --soft:#94AAB3; --line:#26414C; }'
    $HiEntities = '<p>&#9472;&#9472; &#x2500; &#9660;</p>'

    # The base commit: one clean file in each place a row writes to. Nine tracked paths.
    Set-HiFile $HiSkill "# skill`nclean line`n"
    Set-HiFile $HiTool "line one`nline two`nline three`n"
    Set-HiFile 'CHANGELOG.md' "# changelog`nclean line`n"
    Set-HiFile 'docs/notes.md' "# notes`nclean line`n"
    Set-HiFile 'scriptsx/tool.ps1' "line one`n"
    Set-HiFile 'plugins.md' "line one`n"
    Set-HiFile 'README.md' "# readme`nclean line`n"
    Set-HiFile 'DESIGN-CHARTER.md' "# charter`nclean line`n"
    Set-HiFile 'page.html' "<p>page</p>`n"
    Invoke-HiGit @('add', '--', $HiSkill, $HiTool, 'CHANGELOG.md', 'docs/notes.md', 'scriptsx/tool.ps1', 'plugins.md',
                   'README.md', 'DESIGN-CHARTER.md', 'page.html')
    Invoke-HiGit @('commit', '-q', '-m', 'base')

    # --- HARNESS CONTROL ---------------------------------------------------
    Set-HiFile $HiSkill "# skill`nclean line`nanother clean line`n"
    Invoke-HiGit @('add', '--', $HiSkill)
    $HiH = Invoke-HiCheck '-CommitGate'
    Add-Result 'HARNESS-CONTROL-validator-copy-runs' (($HiH.Code -eq 0) -and ($HiH.Text -match 'history ids: 1 staged path')) `
               "exit $($HiH.Code), wanted 0 and the ran line for 1 staged path"
    Reset-HiRepo

    # --- Group 1: each kind, staged in a skill file, refuses and names file and line ---
    $HiKinds = @(
        @{ Row = 'phase-id';        Token = $HiPhase;  Kind = 'workstream or phase id' },
        @{ Row = 'signal-id';       Token = $HiSig;    Kind = 'signal id' },
        @{ Row = 'trap-number';     Token = $HiTrap;   Kind = 'trap number' },
        @{ Row = 'issue-number';    Token = $HiIssue;  Kind = 'issue number' },
        @{ Row = 'hash-number';     Token = $HiHash;   Kind = 'issue number' },
        @{ Row = 'bare-workstream'; Token = $HiBareWs; Kind = 'workstream or phase id' },
        @{ Row = 'label-form';      Token = $HiLabel;  Kind = 'workstream or phase id' },
        @{ Row = 'measured-date';   Token = $HiMeas;   Kind = 'dated measurement' }
    )
    foreach ($HiK in $HiKinds) {
        Set-HiFile $HiSkill "# skill`nhas $($HiK.Token) here`n"
        Invoke-HiGit @('add', '--', $HiSkill)
        $HiR = Invoke-HiCheck '-CommitGate'
        $HiOk = ($HiR.Code -ne 0) -and ($HiR.Text -match $HiSkillRx) -and ($HiR.Text -match [regex]::Escape("($($HiK.Kind))"))
        Add-Result "G1-staged-$($HiK.Row)-refused" $HiOk `
                   "exit $($HiR.Code) - wanted non-zero, the skill file at line 2, and the kind '$($HiK.Kind)'"
        Reset-HiRepo
    }

    Set-HiFile $HiSkill "# skill`nallowed S0007 S9999 issue #12 -Issue 12 Measured 2026-08-17 W4.2 W1.1 W<n>.<p> P25 D4`n"
    Invoke-HiGit @('add', '--', $HiSkill)
    $HiR = Invoke-HiCheck '-CommitGate'
    Add-Result 'G1-control-allowlisted-and-placeholders-pass' (($HiR.Code -eq 0) -and ($HiR.Text -match ' 5 allowlisted example')) `
               "exit $($HiR.Code), wanted 0 and 5 allowlisted examples seen"
    Reset-HiRepo

    # --- the commit gate reads the staged blob, not the working tree -------------
    Set-HiFile $HiSkill "# skill`nclean line`nanother clean line`n"
    Invoke-HiGit @('add', '--', $HiSkill)
    Set-HiFile $HiSkill "# skill`nhas $HiPhase here`n"
    $HiR = Invoke-HiCheck '-CommitGate'
    Add-Result 'STAGED-working-tree-only-passes' ($HiR.Code -eq 0) `
               "exit $($HiR.Code), wanted 0 - the id is in the working tree only, and the commit carries the staged blob"
    Invoke-HiGit @('add', '--', $HiSkill)
    $HiR = Invoke-HiCheck '-CommitGate'
    Add-Result 'STAGED-control-same-change-staged-refused' (($HiR.Code -ne 0) -and ($HiR.Text -match $HiSkillRx)) `
               "exit $($HiR.Code), wanted non-zero naming the skill file at line 2"
    Reset-HiRepo

    # --- scope at the commit gate: every staged path ------------------------------
    # Each refusal is paired with the same path holding the same shape of text and no id,
    # which differs from the base blob so that it is really staged and really read.
    $HiLine  = "# doc`nhas $HiPhase and $HiSig here`n"
    $HiClean = "# doc`nhas no id here`n"
    foreach ($HiOut in @(@{ Row = 'SCOPE-staged-docs-folder';           Path = 'docs/notes.md' },
                         @{ Row = 'SCOPE-staged-changelog';             Path = 'CHANGELOG.md' },
                         @{ Row = 'SCOPE-staged-nested-scripts-folder'; Path = 'docs/scripts/x.md' },
                         @{ Row = 'SCOPE-staged-scripts-file';          Path = $HiTool })) {
        $HiAt = [regex]::Escape($HiOut.Path) + ' line 2 '
        Set-HiFile $HiOut.Path $HiLine
        Invoke-HiGit @('add', '--', $HiOut.Path)
        $HiR = Invoke-HiCheck '-CommitGate'
        $HiN = Get-HiRefusedCount $HiR.Text
        Add-Result "$($HiOut.Row)-refused" (($HiR.Code -ne 0) -and ($HiR.Text -match $HiAt) -and ($HiN -eq 1)) `
                   "exit $($HiR.Code), refused $HiN - wanted non-zero, 1 refused, naming $($HiOut.Path) line 2"
        Reset-HiRepo
        Set-HiFile $HiOut.Path $HiClean
        Invoke-HiGit @('add', '--', $HiOut.Path)
        $HiR = Invoke-HiCheck '-CommitGate'
        $HiN = Get-HiRefusedCount $HiR.Text
        Add-Result "SCOPE-control-$($HiOut.Row.Substring(6))-clean-passes" (($HiR.Code -eq 0) -and ($HiR.Text -match 'history ids: 1 staged path') -and ($HiN -eq 0)) `
                   "exit $($HiR.Code), refused $HiN - wanted 0 with 1 staged path read and 0 refused"
        Reset-HiRepo
        Remove-HiFile 'docs/scripts/x.md'
    }

    # --- the documents, per file, at both gates -----------------------------------
    foreach ($HiDoc in @('README.md', 'DESIGN-CHARTER.md')) {
        $HiAt = [regex]::Escape($HiDoc) + ' line 2 '
        Set-HiFile $HiDoc "# doc`nhas $HiPhase here`n"
        Invoke-HiGit @('add', '--', $HiDoc)
        $HiR = Invoke-HiCheck '-CommitGate'
        $HiN = Get-HiRefusedCount $HiR.Text
        Add-Result "DOC-staged-$HiDoc-refused" (($HiR.Code -ne 0) -and ($HiR.Text -match $HiAt) -and ($HiN -eq 1)) `
                   "exit $($HiR.Code), refused $HiN - wanted non-zero, 1 refused, naming $HiDoc line 2"
        Reset-HiRepo

        Set-HiFile $HiDoc "# doc`nclean line, changed`n"
        Invoke-HiGit @('add', '--', $HiDoc)
        $HiR = Invoke-HiCheck '-CommitGate'
        $HiN = Get-HiRefusedCount $HiR.Text
        Add-Result "DOC-control-staged-$HiDoc-clean-passes" (($HiR.Code -eq 0) -and ($HiR.Text -match 'history ids: 1 staged path') -and ($HiN -eq 0)) `
                   "exit $($HiR.Code), refused $HiN - wanted 0 with 1 staged path read and 0 refused"
        Reset-HiRepo

        Set-HiFile $HiDoc "# doc`nhas $HiPhase here`n"
        $HiR = Invoke-HiCheck '-Strict'
        $HiN = Get-HiRefusedCount $HiR.Text
        Add-Result "DOC-strict-$HiDoc-refused" (($HiR.Code -ne 0) -and ($HiR.Text -match $HiAt) -and ($HiN -eq 1)) `
                   "exit $($HiR.Code), refused $HiN - wanted non-zero, 1 refused, naming $HiDoc line 2"
        Reset-HiRepo

        $HiR = Invoke-HiCheck '-Strict'
        $HiN = Get-HiRefusedCount $HiR.Text
        Add-Result "DOC-control-strict-$HiDoc-reverted-passes" (($HiR.Code -eq 0) -and ($HiR.Text -match 'history ids: 9 tracked path') -and ($HiN -eq 0)) `
                   "exit $($HiR.Code), refused $HiN - wanted 0 with 9 tracked paths read and 0 refused"
    }

    # --- HTML character references and CSS colours are not issue numbers -----------
    Set-HiFile 'page.html' "$HiEntities`n"
    $HiR = Invoke-HiCheck '-Strict'
    $HiN = Get-HiRefusedCount $HiR.Text
    Add-Result 'ENTITY-html-character-references-pass' (($HiR.Code -eq 0) -and ($HiN -eq 0)) `
               "exit $($HiR.Code), refused $HiN - wanted 0 and 0 refused"
    Set-HiFile 'page.html' "$HiEntities`n<p>see $HiHash</p>`n"
    $HiR = Invoke-HiCheck '-Strict'
    $HiN = Get-HiRefusedCount $HiR.Text
    Add-Result 'ENTITY-control-same-file-issue-number-refused' (($HiR.Code -ne 0) -and ($HiR.Text -match 'page\.html line 2 ') -and ($HiN -eq 1)) `
               "exit $($HiR.Code), refused $HiN - wanted non-zero, 1 refused, naming page.html line 2"
    Reset-HiRepo

    Set-HiFile 'page.html' "$HiColours`n"
    $HiR = Invoke-HiCheck '-Strict'
    $HiN = Get-HiRefusedCount $HiR.Text
    Add-Result 'COLOUR-css-hex-colours-pass' (($HiR.Code -eq 0) -and ($HiN -eq 0)) `
               "exit $($HiR.Code), refused $HiN - wanted 0 and 0 refused"
    Set-HiFile 'page.html' "$HiColours /* $HiHash */`n"
    $HiR = Invoke-HiCheck '-Strict'
    $HiN = Get-HiRefusedCount $HiR.Text
    Add-Result 'COLOUR-control-issue-number-beside-colours-refused' (($HiR.Code -ne 0) -and ($HiR.Text -match 'page\.html line 1 ') -and ($HiN -eq 1)) `
               "exit $($HiR.Code), refused $HiN - wanted non-zero, 1 refused, naming page.html line 1"
    Reset-HiRepo

    Set-HiFile $HiSkill "# skill`n$HiColours`n"
    $HiR = Invoke-HiCheck '-Strict'
    $HiN = Get-HiRefusedCount $HiR.Text
    Add-Result 'COLOUR-in-plugins-pass' (($HiR.Code -eq 0) -and ($HiN -eq 0)) `
               "exit $($HiR.Code), refused $HiN - wanted 0 and 0 refused for colours in a skill file"
    Reset-HiRepo

    # --- a staged PATH holding an id refuses -------------------------------------
    Set-HiFile $HiBadPath "clean content`n"
    Invoke-HiGit @('add', '--', $HiBadPath)
    $HiR = Invoke-HiCheck '-CommitGate'
    Add-Result 'PATH-staged-path-refused' (($HiR.Code -ne 0) -and ($HiR.Text -match 'a staged path holds ')) `
               "exit $($HiR.Code), wanted non-zero and the staged path refusal"
    Reset-HiRepo
    Remove-HiFile $HiBadPath

    Set-HiFile 'scripts/notes.ps1' "clean content`n"
    Invoke-HiGit @('add', '--', 'scripts/notes.ps1')
    $HiR = Invoke-HiCheck '-CommitGate'
    Add-Result 'PATH-control-staged-clean-name-passes' ($HiR.Code -eq 0) "exit $($HiR.Code), wanted 0"
    Reset-HiRepo
    Remove-HiFile 'scripts/notes.ps1'

    # --- binary files are skipped -------------------------------------------------
    [System.IO.File]::WriteAllBytes((Join-Path $script:HiRepo 'plugins\keel-x\blob.dat'),
        [byte[]](@(97, 98, 0, 99) + [System.Text.Encoding]::ASCII.GetBytes(" $HiPhase`n")))
    Invoke-HiGit @('add', '--', 'plugins/keel-x/blob.dat')
    $HiR = Invoke-HiCheck '-CommitGate'
    Add-Result 'BINARY-staged-file-with-nul-skipped' ($HiR.Code -eq 0) "exit $($HiR.Code), wanted 0"
    [System.IO.File]::WriteAllBytes((Join-Path $script:HiRepo 'plugins\keel-x\blob.dat'),
        [byte[]](@(97, 98, 99) + [System.Text.Encoding]::ASCII.GetBytes(" $HiPhase`n")))
    Invoke-HiGit @('add', '--', 'plugins/keel-x/blob.dat')
    $HiR = Invoke-HiCheck '-CommitGate'
    Add-Result 'BINARY-control-same-bytes-without-nul-refused' (($HiR.Code -ne 0) -and ($HiR.Text -match 'blob\.dat line 1 ')) `
               "exit $($HiR.Code), wanted non-zero naming blob.dat line 1"
    Reset-HiRepo
    Remove-HiFile 'plugins/keel-x/blob.dat'

    # --- Group 2: at push, a tracked script that is not staged --------------------
    $HiThree = "line one`nline two`nhas $HiPhase, $HiSig and $HiTrap here`n"
    Set-HiFile $HiTool $HiThree
    $HiR = Invoke-HiCheck '-Strict'
    Add-Result 'G2-strict-unstaged-tracked-script-refused' (($HiR.Code -ne 0) -and ($HiR.Text -match 'scripts/tool\.ps1 line 3 ')) `
               "exit $($HiR.Code), wanted non-zero naming scripts/tool.ps1 line 3"
    Reset-HiRepo

    $HiR = Invoke-HiCheck '-Strict'
    $HiN = Get-HiRefusedCount $HiR.Text
    Add-Result 'G2-control-strict-reverted-passes' (($HiR.Code -eq 0) -and ($HiR.Text -match 'history ids: 9 tracked path') -and ($HiN -eq 0)) `
               "exit $($HiR.Code), refused $HiN - wanted 0 and the ran line for 9 tracked paths"

    # The same text in a tracked file outside the two code folders refuses at push too;
    # each is paired with the same file holding the same shape of text and no id.
    $HiThreeClean = "line one`nline two`nhas no id here`n"
    foreach ($HiLook in @(@{ Row = 'G2-strict-same-text-in-changelog'; Ctl = 'SCOPE-control-strict-changelog';        Path = 'CHANGELOG.md' },
                          @{ Row = 'SCOPE-strict-lookalike-folder';    Ctl = 'SCOPE-control-strict-lookalike-folder'; Path = 'scriptsx/tool.ps1' },
                          @{ Row = 'SCOPE-strict-lookalike-file';      Ctl = 'SCOPE-control-strict-lookalike-file';   Path = 'plugins.md' })) {
        $HiAt = '(^|\s)' + [regex]::Escape($HiLook.Path) + ' line 3 '
        Set-HiFile $HiLook.Path $HiThree
        $HiR = Invoke-HiCheck '-Strict'
        $HiN = Get-HiRefusedCount $HiR.Text
        Add-Result "$($HiLook.Row)-refused" (($HiR.Code -ne 0) -and ($HiR.Text -match $HiAt) -and ($HiN -eq 1)) `
                   "exit $($HiR.Code), refused $HiN - wanted non-zero, 1 refused, naming $($HiLook.Path) line 3"
        Reset-HiRepo
        Set-HiFile $HiLook.Path $HiThreeClean
        $HiR = Invoke-HiCheck '-Strict'
        $HiN = Get-HiRefusedCount $HiR.Text
        Add-Result "$($HiLook.Ctl)-clean-passes" (($HiR.Code -eq 0) -and ($HiN -eq 0)) `
                   "exit $($HiR.Code), refused $HiN - wanted 0 and 0 refused"
        Reset-HiRepo
    }

    # --- Group 3: each allowlisted example passes; one digit away refuses ----------
    $HiAllowed = @(
        @{ Row = 'S0007';               Ok = 'S0007';               Away = ('S' + '0008') },
        @{ Row = 'S9999';               Ok = 'S9999';               Away = ('S' + '9998') },
        @{ Row = 'issue-hash-12';       Ok = 'issue #12';           Away = ('issue #' + '13') },
        @{ Row = 'Issue-12';            Ok = '-Issue 12';           Away = ('-Iss' + 'ue 13') },
        @{ Row = 'Measured-2026-08-17'; Ok = 'Measured 2026-08-17'; Away = ('Meas' + 'ured 2026-08-18') }
    )
    foreach ($HiA in $HiAllowed) {
        Set-HiFile $HiTool "x $($HiA.Ok) x`n"
        $HiR = Invoke-HiCheck '-Strict'
        Add-Result "G3-allowlisted-$($HiA.Row)-passes" (($HiR.Code -eq 0) -and ($HiR.Text -match ' 1 allowlisted example')) `
                   "exit $($HiR.Code), wanted 0 and 1 allowlisted example seen"
        Reset-HiRepo
    }
    foreach ($HiA in $HiAllowed) {
        Set-HiFile $HiTool "x $($HiA.Away) x`n"
        $HiR = Invoke-HiCheck '-Strict'
        Add-Result "G3-one-digit-away-$($HiA.Row)-refused" (($HiR.Code -ne 0) -and ($HiR.Text -match 'scripts/tool\.ps1 line 1 ')) `
                   "exit $($HiR.Code), wanted non-zero naming scripts/tool.ps1 line 1"
        Reset-HiRepo
    }

    # --- boundaries ------------------------------------------------------------
    foreach ($HiBd in @(@{ Row = 'BOUND-single-digit-placeholder-passes'; Text = 'W9.9';               Refuse = $false },
                        @{ Row = 'BOUND-control-two-digit-refused';       Text = ('W' + '19.9');       Refuse = $true },
                        @{ Row = 'BOUND-letter-before-not-matched';       Text = ('AB' + $HiSig);      Refuse = $false },
                        @{ Row = 'BOUND-control-space-before-refused';    Text = ('AB ' + $HiSig);     Refuse = $true },
                        @{ Row = 'BOUND-six-digit-hash-passes';           Text = $HiSixHash;           Refuse = $false },
                        @{ Row = 'BOUND-control-five-digit-hash-refused'; Text = $HiFiveHash;          Refuse = $true })) {
        Set-HiFile $HiTool "x $($HiBd.Text) x`n"
        $HiR = Invoke-HiCheck '-Strict'
        $HiRefused = ($HiR.Code -ne 0) -and ($HiR.Text -match 'scripts/tool\.ps1 line 1 ')
        $HiWantText = if ($HiBd.Refuse) { 'refused' } else { 'passed' }
        Add-Result $HiBd.Row ($HiRefused -eq [bool]$HiBd.Refuse) "exit $($HiR.Code), refused $(Get-HiRefusedCount $HiR.Text) - wanted the line $HiWantText"
        Reset-HiRepo
    }

    # --- at push, a tracked PATH holding an id refuses ---------------------------
    Set-HiFile $HiBadPath "clean content`n"
    Invoke-HiGit @('add', '--', $HiBadPath)
    Invoke-HiGit @('commit', '-q', '-m', 'add a file')
    $HiR = Invoke-HiCheck '-Strict'
    Add-Result 'PATH-strict-tracked-path-refused' (($HiR.Code -ne 0) -and ($HiR.Text -match 'a tracked path holds ')) `
               "exit $($HiR.Code), wanted non-zero and the tracked path refusal"

    Invoke-HiGit @('mv', '--', $HiBadPath, 'scripts/notes-renamed.ps1')
    Invoke-HiGit @('commit', '-q', '-m', 'rename a file')
    $HiR = Invoke-HiCheck '-Strict'
    Add-Result 'PATH-control-strict-renamed-passes' ($HiR.Code -eq 0) "exit $($HiR.Code), wanted 0"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $HiValidator -PathType Leaf)) {
    [Console]::Error.WriteLine("test-history-ids: the validator file to test does not exist.")
    exit 1
}

# Variables a git hook may export would point every scratch git call at the repository
# being committed or pushed. Clear them for this process and its children.
foreach ($HiVar in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
                     'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_COMMON_DIR', 'GIT_PREFIX', 'GIT_NAMESPACE')) {
    Remove-Item -LiteralPath "Env:\$HiVar" -ErrorAction SilentlyContinue
}

$HiTempBase = [System.IO.Path]::GetTempPath()
$HiTempRoot = Join-Path $HiTempBase ("keel-history-ids-suite-" + [System.Guid]::NewGuid().ToString('N').Substring(0, 12))

# The scratch root must resolve INSIDE the system temp directory before anything is written.
$HiTempBaseFull = (Get-Item -LiteralPath $HiTempBase).FullName.TrimEnd('\', '/')
New-Item -ItemType Directory -Path $HiTempRoot -Force | Out-Null
$HiTempRootFull = (Get-Item -LiteralPath $HiTempRoot).FullName.TrimEnd('\', '/')
if (-not $HiTempRootFull.StartsWith("$HiTempBaseFull$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine("test-history-ids: refusing to run - scratch root does not resolve inside the temp directory.")
    exit 1
}

$script:HiRepo = Join-Path $HiTempRootFull 'repo'
$script:HiCopy = Join-Path $script:HiRepo 'scripts\check-suite-docs.ps1'

$HiFailed = 0
try {
    New-Item -ItemType Directory -Path (Join-Path $script:HiRepo 'scripts') -Force | Out-Null

    $HiPrev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $null = & git -c init.defaultBranch=main init -q $script:HiRepo 2>$null
    $HiInitRepo = $LASTEXITCODE
    $HiTop = @(& git -C $script:HiRepo rev-parse --show-toplevel 2>$null)
    $ErrorActionPreference = $HiPrev
    if ($HiInitRepo -ne 0) { throw "fixture: git init failed (exit $HiInitRepo)" }

    # Refuse unless git sees the scratch repository as its own top level. Compared on the
    # unique tail of the path rather than the whole of it, because TEMP can be spelled in a
    # short 8.3 form that git reports in its long form.
    $HiTail = ((Split-Path -Leaf $HiTempRootFull) + '/repo')
    $HiTopText = ''
    if ($HiTop.Count -gt 0) { $HiTopText = ([string]$HiTop[0]).Replace('\', '/').TrimEnd('/') }
    if (-not $HiTopText.EndsWith($HiTail, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "fixture: git does not resolve the scratch repository as its own top level - refusing to run any case"
    }

    Invoke-HiGit @('config', 'user.email', 'suite@example.invalid')
    Invoke-HiGit @('config', 'user.name', 'history ids suite')
    Invoke-HiGit @('config', 'core.autocrlf', 'false')
    Copy-Item -LiteralPath $HiValidator -Destination $script:HiCopy -Force

    Invoke-Cases

    if (-not $Quiet) { Write-Output ''; Write-Output "== history ids check: $([System.IO.Path]::GetFileName($HiValidator))" }

    $HiHarnessOk = $null
    foreach ($HiResult in @($script:HiResults)) {
        if (-not $HiResult.Ok) {
            $HiFailed++
            if (-not $Quiet) { Write-Output ("  FAIL  {0,-56} {1}" -f $HiResult.Name, $HiResult.Why) }
        }
        elseif ($List) { Write-Output ("  ok    {0,-56} {1}" -f $HiResult.Name, $HiResult.Why) }
        if ($HiResult.Name -eq 'HARNESS-CONTROL-validator-copy-runs') { $HiHarnessOk = $HiResult.Ok }
    }
    if ($HiHarnessOk -ne $true) {
        Write-Output ''
        Write-Output '  HARNESS CONTROL FAILED: the validator copy did not run the check on a clean staged file.'
        Write-Output '  The suite is not reaching the mechanism. No other row in this run means anything.'
    }
}
catch {
    # Our own throws start 'fixture:' and carry no path; anything else is reported by its
    # type only, since a PowerShell error message usually quotes a scratch path.
    $HiFailed++
    $HiWhy = $_.Exception.GetType().Name
    if ($_.Exception.Message.StartsWith('fixture:')) { $HiWhy = $_.Exception.Message }
    Write-Output ("  FAIL  the suite could not finish: {0}" -f $HiWhy)
}
finally {
    if (Test-Path -LiteralPath $HiTempRoot) {
        try { Remove-Item -LiteralPath $HiTempRoot -Recurse -Force -ErrorAction Stop } catch { }
    }
}

Write-Output ''
Write-Output ("test-history-ids: {0} case(s), {1} failure(s)." -f @($script:HiResults).Count, $HiFailed)
if ($HiFailed -gt 0) { exit 1 }
exit 0
