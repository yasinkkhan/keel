<#
    test-plugins-gate.ps1 - the verification suite for scripts/keel-plugins-gate.ps1.

    WHY THIS IS IN THE REPO (charter P11). A suite that lives in a scratch directory is
    gone with the session, and a claim that cannot be re-checked mechanically does not
    ship. This file is that suite, committed, so the next person can re-run it instead
    of rebuilding it.

    Run it:
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-plugins-gate.ps1
      ... -AgainstHead     also runs the same cases against git HEAD's gate, which MUST
                           fail substantially more. A suite that scores the same on both
                           is not measuring the change and is not evidence.
      ... -AgainstGate <p> the same comparison against any gate you name, wherever it
                           lives. This is what makes "does location change the verdict?"
                           answerable without hand-building a second harness.

    THE CASE LIST IS BUILT PER GATE, NOT ONCE. Every path a case carries - the
    charter it points the Read tool at, the plugins/ target it tries to write - is
    derived from the ROOT of the gate under test, via New-CaseSet -RootPath. That is not
    tidiness. A list built once from this repo's own root and replayed against a
    relocated copy asks the copy about a charter it can never resolve, and charges it a
    failure earned by its LOCATION rather than its BEHAVIOUR: two byte-identical gates
    can then score differently, and a change of nothing at all can clear the
    discrimination bar this mode exists to enforce.

    Exit 0 = every case behaved. Exit 1 = at least one did not.

    FOUR HARNESS TRAPS THIS FILE IS BUILT AROUND. Each one makes a harness report a
    clean sweep while testing NOTHING. The gate fails OPEN, so a payload it cannot read
    is indistinguishable from one it allows, and each of these is caught only by a
    control expected to FAIL:

      1. `cmd /c "type f | powershell -File s"` does not deliver stdin: every probe
         returns 0, including one known to block. Here the JSON is piped straight from
         PowerShell to the native powershell.exe, which does deliver it.
      2. A Windows path in hand-written JSON needs DOUBLED backslashes; single ones make
         ConvertFrom-Json throw and the gate exit 0. Every payload here is built with
         ConvertTo-Json and re-parsed with ConvertFrom-Json before it is sent.
      3. A payload file written -Encoding UTF8 carries a BOM in PS 5.1, which
         ConvertFrom-Json rejects. Nothing here is written to disk at all.
      4. Quoted command strings passed between powershell.exe processes get split at the
         quotes in PS 5.1, silently dropping exactly the quoted cases that matter. This
         suite is one self-contained script.

    ALWAYS INCLUDE A CONTROL THAT MUST FAIL. Group 5 opens with an Edit-tool payload into
    plugins/ that must exit 2; if that row is not 2, no other row in the file means
    anything, and the suite says so and stops.

    GROUP 8 READS WHAT THE GATE PRINTS. A suite whose every row asserts an exit code or a
    count cannot see a refusal message that renders wrong - for example markdown
    backticks consumed by a double-quoted here-string, one of them turning into a
    literal TAB inside the word 'tail'. Its two limbs are asserted against a JOINED
    STRING, not against the captured collection, for a measured reason recorded beside
    the join in Invoke-Case: '-notmatch' against a collection filters rather than
    negates, and would make the absence limb permanently unable to fire.

    GROUP 9 SENDS THE PAYLOAD'S cwd, and so does every other row: the gate arms by a
    shell command only where cwd reaches its own charter. A row naming no folder gets
    the root of the gate under test, stamped at the end of New-CaseSet.

    Windows PowerShell 5.1 compatible. ASCII only.
#>

[CmdletBinding()]
param(
    [switch]$AgainstHead,
    [string]$AgainstGate = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot    = Split-Path -Parent $PSScriptRoot
$GatePath    = Join-Path $PSScriptRoot 'keel-plugins-gate.ps1'

# A synthetic session id, so a live session's marker is never touched. The gate strips
# everything outside [A-Za-z0-9_-], and this survives that unchanged.
$SuiteSession = 'keel-gate-suite'
$MarkerDir    = Join-Path (Join-Path $env:USERPROFILE '.keel') 'markers'
$MarkerFile   = Join-Path $MarkerDir "charter-$SuiteSession.marker"

# The charter path, the plugins/ target and the two negative-charter paths are NOT
# script-scope constants here. They are built inside New-CaseSet from the root of
# whichever gate is under test - see the header note. Constants here would make the
# comparison mode dishonest, so they are deliberately absent rather than kept "for
# convenience": a script-scope charter path is the defect.

# The gate lives at <root>\scripts\keel-plugins-gate.ps1 and resolves its charter as
# parent-of(its own directory). So the root a case list must be built against is the
# grandparent of the gate file, and that is the ONLY relationship this suite assumes
# about where a gate sits.
function Get-GateRoot {
    param([string]$GateFile)
    return (Split-Path -Parent (Split-Path -Parent $GateFile))
}

function Remove-Marker {
    if (Test-Path -LiteralPath $MarkerFile) { Remove-Item -LiteralPath $MarkerFile -Force }
}

function New-Case {
    param(
        [string]$Name,
        [string]$Group,
        [string]$Tool,
        [hashtable]$ToolInput,
        [int]$ExpectExit,
        [object]$ExpectArm = $null,   # $true / $false / $null = do not assert
        [switch]$PreArm,
        # Assertions over what the gate PRINTS. Empty = do not assert, which is every
        # row but two. See group 8.
        [string]$StderrMustMatch = '',
        [string]$StderrMustNotMatch = '',
        # The session's folder as the hook payload states it. Empty = the root of the gate
        # under test, stamped at the end of New-CaseSet. See group 9.
        [object]$Cwd = '',
        [switch]$OmitCwd,
        # The folder the gate process itself runs in. Empty = wherever the suite is. A bare
        # 'C:' resolves against this, so that row only means something run from the root.
        [string]$RunFrom = '',
        # A second payload, sent before the marker is cleared: a Write to this target, whose
        # exit code must match. This is what proves a marker does or does not open the gate.
        [string]$ThenWriteTo = '',
        [int]$ThenWriteExit = -1
    )
    return [pscustomobject]@{
        Name               = $Name
        Group              = $Group
        Tool               = $Tool
        ToolInput          = $ToolInput
        ExpectExit         = $ExpectExit
        ExpectArm          = $ExpectArm
        PreArm             = [bool]$PreArm
        # Always present, never absent: Set-StrictMode -Version Latest is on, and reading
        # a property off an object that does not carry it throws.
        StderrMustMatch    = $StderrMustMatch
        StderrMustNotMatch = $StderrMustNotMatch
        Cwd                = $Cwd
        OmitCwd            = [bool]$OmitCwd
        RunFrom            = $RunFrom
        ThenWriteTo        = $ThenWriteTo
        ThenWriteExit      = $ThenWriteExit
    }
}

function Invoke-Case {
    param([object]$Case, [string]$Gate)

    Remove-Marker
    if ($Case.PreArm) {
        if (-not (Test-Path -LiteralPath $MarkerDir)) { New-Item -ItemType Directory -Path $MarkerDir -Force | Out-Null }
        Set-Content -LiteralPath $MarkerFile -Value 'prearmed' -Encoding ASCII
    }

    $payload = [pscustomobject]@{
        session_id = $SuiteSession
        tool_name  = $Case.Tool
        tool_input = [pscustomobject]$Case.ToolInput
    }
    if (-not $Case.OmitCwd) { $payload | Add-Member -NotePropertyName 'cwd' -NotePropertyValue $Case.Cwd }
    $json = $payload | ConvertTo-Json -Depth 8 -Compress

    # The header's second harness trap: prove the payload parses BEFORE sending it. A
    # payload the gate cannot read exits 0, which is indistinguishable from one it allowed.
    $reparsed = $null
    try { $reparsed = $json | ConvertFrom-Json } catch { $reparsed = $null }
    if ($null -eq $reparsed) {
        return [pscustomobject]@{ Ok = $false; Exit = -1; Armed = $false; Why = 'payload did not re-parse' }
    }

    # Native stderr under 'Stop' becomes a terminating error, and the gate writes its
    # block message to stderr. Let the EXIT CODE decide.
    $code = 0
    $captured = @()
    $prevPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # CAPTURED rather than discarded, so a row may assert what the gate PRINTS.
        # $LASTEXITCODE is unaffected by the capture - measured at 2 on a blocked
        # payload with the value read exactly as it is below.
        if ($Case.RunFrom) { Push-Location -LiteralPath $Case.RunFrom }
        try {
            $captured = @($json | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Gate 2>&1)
            $code = $LASTEXITCODE
        }
        finally { if ($Case.RunFrom) { Pop-Location } }
    }
    finally { $ErrorActionPreference = $prevPreference }

    # ONE STRING, and Exception.Message rather than ToString(). Both halves are measured
    # and both are load-bearing:
    #
    #   - ToString() on the ErrorRecords wrapping BLANK stderr lines yields the literal
    #     'System.Management.Automation.RemoteException', so a naive join carries that
    #     text beside the message the gate actually writes. An assertion spanning a line,
    #     or counting anything, would be measuring harness noise.
    #   - '-notmatch' against a COLLECTION filters rather than negates: it returns $true
    #     with the forbidden character present. An absence assertion made against the
    #     array would ship permanently unable to fire, which is the exact shape of the
    #     defect group 8 exists to catch.
    $stderrLines = foreach ($item in $captured) {
        if ($item -is [System.Management.Automation.ErrorRecord]) { $item.Exception.Message }
        else { [string]$item }
    }
    $stderrText = (@($stderrLines) -join "`n")

    $armed = Test-Path -LiteralPath $MarkerFile
    if ($Case.PreArm) { $armed = $false }   # pre-armed: arming is not what this row tests

    # The following write, while whatever the first call left behind is still on disk.
    $writeCode = -1
    if (-not [string]::IsNullOrEmpty($Case.ThenWriteTo)) {
        $writeJson = [pscustomobject]@{
            session_id = $SuiteSession
            tool_name  = 'Write'
            tool_input = [pscustomobject]@{ file_path = $Case.ThenWriteTo }
        } | ConvertTo-Json -Depth 8 -Compress
        $ErrorActionPreference = 'Continue'
        try {
            $null = @($writeJson | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Gate 2>&1)
            $writeCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $prevPreference }
    }
    Remove-Marker

    $ok  = ($code -eq $Case.ExpectExit)
    $why = ''
    if (-not $ok) { $why = "exit $code, wanted $($Case.ExpectExit)" }
    if ($ok -and -not [string]::IsNullOrEmpty($Case.ThenWriteTo) -and $writeCode -ne $Case.ThenWriteExit) {
        $ok  = $false
        $why = "the following write exited $writeCode, wanted $($Case.ThenWriteExit)"
    }
    if ($ok -and $null -ne $Case.ExpectArm) {
        if ($armed -ne [bool]$Case.ExpectArm) {
            $ok  = $false
            $why = "armed=$armed, wanted $($Case.ExpectArm)"
        }
    }
    # [regex]::IsMatch on the JOINED string, negated explicitly for the must-not limb.
    # Not '-match'/'-notmatch' against $captured - see the note above the join.
    if ($ok -and -not [string]::IsNullOrEmpty($Case.StderrMustMatch)) {
        if (-not [regex]::IsMatch($stderrText, $Case.StderrMustMatch)) {
            $ok  = $false
            $why = "stderr did not contain /$($Case.StderrMustMatch)/"
        }
    }
    if ($ok -and -not [string]::IsNullOrEmpty($Case.StderrMustNotMatch)) {
        if ([regex]::IsMatch($stderrText, $Case.StderrMustNotMatch)) {
            $ok  = $false
            $why = "stderr contained /$($Case.StderrMustNotMatch)/, which it must not"
        }
    }
    return [pscustomobject]@{ Ok = $ok; Exit = $code; Armed = $armed; Why = $why }
}

# ---------------------------------------------------------------------------
# The cases. Drawn from shapes found by independent verification passes rather than
# invented, so the suite covers shapes that actually occurred.
#
# BUILT PER GATE. Every path below hangs off $RootPath, so the identical case list can
# be asked of a gate wherever it sits. The four path variables are set at the top of
# this function under the names every case body uses.
#
# The body is deliberately NOT re-indented into the function: re-indenting a few
# hundred lines buries any real change in a diff, and a suite nobody can review is the
# failure mode this file exists to prevent.
#
# It prints nothing and returns only the array: a function that both prints and
# returns hands the caller every emitted line plus the value.
# ---------------------------------------------------------------------------
function New-CaseSet {
param([string]$RootPath)

$CharterFile  = Join-Path $RootPath 'DESIGN-CHARTER.md'
$PluginTarget = Join-Path $RootPath 'plugins\keel-workflow\.claude-plugin\plugin.json'

# ANOTHER repo's charter, and an OLD one beside this one's. Both are negative cases:
# neither may arm the gate under test. Derived from $RootPath rather than written out,
# so this suite carries no user path. Neither path needs to exist; the gate compares
# resolved strings and never opens the file - a gate in a mirrored layout arms on a
# charter path with nothing at the end of it.
$OtherCharter = Join-Path (Split-Path -Parent $RootPath) 'SOMETHING-ELSE\DESIGN-CHARTER.md'
$OldCharter   = Join-Path $RootPath 'OLD-DESIGN-CHARTER.md'

$Cases = @()

# --- Group 1: must NOT arm ---------------------------------------------------
# Everything a verifier found arming the gate, plus legitimate reads in a spelling
# outside the canonical set, which do not arm under it. The second kind must be seen
# not to arm rather than silently drift.
$noArm = @(
    @{ n = 'grep-pipe-head';        c = 'grep -n P25 DESIGN-CHARTER.md | head -20' },
    @{ n = 'echo-and-cat';          c = 'echo see DESIGN-CHARTER.md && cat README.md' },
    @{ n = 'semicolon-grep';        c = 'cat README.md ; grep P25 DESIGN-CHARTER.md' },
    @{ n = 'newline-sep';           c = "cat README.md`ngrep P25 DESIGN-CHARTER.md" },
    @{ n = 'crlf-sep';              c = "cat README.md`r`ngrep P25 DESIGN-CHARTER.md" },
    @{ n = 'bare-grep';             c = 'grep -n P25 DESIGN-CHARTER.md' },
    @{ n = 'echo-quoted-semi';      c = 'echo "note: reminders; cat DESIGN-CHARTER.md later"' },
    @{ n = 'commit-quoted-semi';    c = 'git commit -m "docs: notes; cat DESIGN-CHARTER.md later"' },
    @{ n = 'commit-type-verb';      c = 'git commit -m "docs: type up DESIGN-CHARTER.md notes"' },
    @{ n = 'commit-multiline';      c = "git commit -m `"docs: gate`n`ncat DESIGN-CHARTER.md is how you arm it`"" },
    @{ n = 'heredoc-quoted';        c = "cat > note.md <<'XEOFX'`ncat DESIGN-CHARTER.md later`nXEOFX" },
    @{ n = 'heredoc-bare';          c = "cat > note.md <<XEOFX`nhead -20 DESIGN-CHARTER.md later`nXEOFX" },
    @{ n = 'sed-search-quoted';     c = "sed -n '/DESIGN-CHARTER.md/p' README.md" },
    @{ n = 'sed-search-unquoted';   c = 'sed -n /DESIGN-CHARTER.md/p README.md' },
    @{ n = 'awk-search-quoted';     c = "awk '/DESIGN-CHARTER.md/' README.md" },
    @{ n = 'awk-search-unquoted';   c = 'awk /DESIGN-CHARTER.md/ README.md' },
    @{ n = 'awk-print-other';       c = 'awk /DESIGN-CHARTER.md/{print FILENAME} README.md CHANGELOG.md' },
    @{ n = 'other-repo-charter';    c = ('cat ' + $OtherCharter) },
    @{ n = 'unc-path';              c = 'cat \\srv\share\DESIGN-CHARTER.md' },
    @{ n = 'substring-name';        c = 'cat OLD-DESIGN-CHARTER.md.bak' },
    @{ n = 'redirect-devnull';      c = 'cat DESIGN-CHARTER.md > /dev/null' },
    @{ n = 'uppercase-verb';        c = 'CAT design-charter.md' },
    @{ n = 'cd-and-cat';            c = 'cd x && cat DESIGN-CHARTER.md' },
    @{ n = 'echo-nl-cat';           c = "echo hi`ncat DESIGN-CHARTER.md" },
    @{ n = 'cat-readme-and-cat';    c = 'cat README.md && cat DESIGN-CHARTER.md' },
    @{ n = 'sed-quoted-range';      c = "sed -n '1,500p' DESIGN-CHARTER.md" },
    @{ n = 'cat-quoted-name';       c = 'cat "DESIGN-CHARTER.md"' },
    @{ n = 'subshell-paren';        c = '(cat DESIGN-CHARTER.md)' },
    @{ n = 'brace-group';           c = '{ cat DESIGN-CHARTER.md; }' },
    @{ n = 'envvar-prefix';         c = 'FOO=1 cat DESIGN-CHARTER.md' },
    @{ n = 'command-builtin';       c = 'command cat DESIGN-CHARTER.md' },
    @{ n = 'verb-prefix-token';     c = 'catalog DESIGN-CHARTER.md' },
    @{ n = 'verb-suffix-token';     c = 'mytype DESIGN-CHARTER.md' },
    @{ n = 'backslash-cont';        c = "cat \`n  DESIGN-CHARTER.md" },
    @{ n = 'trailing-semicolon';    c = 'cat DESIGN-CHARTER.md;' },
    @{ n = 'narrowed-gc';           c = 'gc DESIGN-CHARTER.md' },
    @{ n = 'narrowed-head-500';     c = 'head -500 DESIGN-CHARTER.md' },
    @{ n = 'narrowed-tail-n5';      c = 'tail -n 5 DESIGN-CHARTER.md' },
    @{ n = 'narrowed-sed-range';    c = 'sed -n 1,500p DESIGN-CHARTER.md' },
    @{ n = 'narrowed-cat-pipe';     c = 'cat DESIGN-CHARTER.md | tail -30' },
    @{ n = 'narrowed-more-in';      c = 'more < DESIGN-CHARTER.md' },
    @{ n = 'narrowed-double-dash';  c = 'cat -- DESIGN-CHARTER.md' },
    @{ n = 'narrowed-dollar-paren'; c = 'cat $(echo DESIGN-CHARTER.md)' },
    @{ n = 'narrowed-twice';        c = 'cat DESIGN-CHARTER.md DESIGN-CHARTER.md' },
    @{ n = 'gc-quoted-winpath';     c = ('Get-Content "' + $CharterFile + '"') }
)
foreach ($item in $noArm) {
    $Cases += New-Case -Name $item.n -Group '1-noarm' -Tool 'Bash' -ToolInput @{ command = $item.c } -ExpectExit 0 -ExpectArm $false
}

# --- Group 2: the canonical set MUST arm, each member on its own ------------
# Tested individually and not as a set. A member that does not arm is a FALSE BLOCK,
# and a suite that only asserts "something in the set works" would not see it.
$mustArm = @(
    @{ n = 'canon-cat';             c = 'cat DESIGN-CHARTER.md' },
    @{ n = 'canon-cat-dotslash';    c = 'cat ./DESIGN-CHARTER.md' },
    @{ n = 'canon-getcontent';      c = 'Get-Content DESIGN-CHARTER.md' },
    @{ n = 'canon-getcontent-raw';  c = 'Get-Content -Raw DESIGN-CHARTER.md' },
    @{ n = 'canon-type';            c = 'type DESIGN-CHARTER.md' },
    @{ n = 'canon-surround-space';  c = '   cat DESIGN-CHARTER.md   ' },
    @{ n = 'canon-leading-nl';      c = "`ncat DESIGN-CHARTER.md" },
    @{ n = 'canon-leading-tab';     c = "`tcat DESIGN-CHARTER.md" },
    @{ n = 'canon-leading-cr';      c = "`rcat DESIGN-CHARTER.md" }
)
foreach ($item in $mustArm) {
    $Cases += New-Case -Name $item.n -Group '2-arm' -Tool 'Bash' -ToolInput @{ command = $item.c } -ExpectExit 0 -ExpectArm $true
}
# PowerShell tool, same canonical command - the gate must not care which shell tool.
$Cases += New-Case -Name 'canon-via-PowerShell-tool' -Group '2-arm' -Tool 'PowerShell' -ToolInput @{ command = 'Get-Content -Raw DESIGN-CHARTER.md' } -ExpectExit 0 -ExpectArm $true

# --- Group 3: the Read branch ------------------------------------------------
# The positive control is read-full-arms: without it, every "does not arm" row below
# is also satisfied by a harness that is simply not reaching the gate.
$Cases += New-Case -Name 'read-full-ARMS-control' -Group '3-read' -Tool 'Read' -ToolInput @{ file_path = $CharterFile } -ExpectExit 0 -ExpectArm $true
$Cases += New-Case -Name 'read-limit'             -Group '3-read' -Tool 'Read' -ToolInput @{ file_path = $CharterFile; limit = 5 } -ExpectExit 0 -ExpectArm $false
$Cases += New-Case -Name 'read-offset'            -Group '3-read' -Tool 'Read' -ToolInput @{ file_path = $CharterFile; offset = 100 } -ExpectExit 0 -ExpectArm $false
$Cases += New-Case -Name 'read-limit-and-offset'  -Group '3-read' -Tool 'Read' -ToolInput @{ file_path = $CharterFile; limit = 50; offset = 10 } -ExpectExit 0 -ExpectArm $false
$Cases += New-Case -Name 'read-old-charter'       -Group '3-read' -Tool 'Read' -ToolInput @{ file_path = $OldCharter } -ExpectExit 0 -ExpectArm $false
$Cases += New-Case -Name 'read-other-repo'        -Group '3-read' -Tool 'Read' -ToolInput @{ file_path = $OtherCharter } -ExpectExit 0 -ExpectArm $false
$Cases += New-Case -Name 'read-unresolvable-path' -Group '3-read' -Tool 'Read' -ToolInput @{ file_path = 'C:\<<>>|bad\DESIGN-CHARTER.md' } -ExpectExit 0 -ExpectArm $false
# Writing the charter is not reading it. Only the Read tool arms.
$Cases += New-Case -Name 'edit-charter-no-arm'    -Group '3-read' -Tool 'Edit'  -ToolInput @{ file_path = $CharterFile } -ExpectExit 0 -ExpectArm $false
$Cases += New-Case -Name 'write-charter-no-arm'   -Group '3-read' -Tool 'Write' -ToolInput @{ file_path = $CharterFile } -ExpectExit 0 -ExpectArm $false

# --- Group 4: arm and write in ONE call is impossible -------------------------
# Each row must BLOCK (exit 2) and must leave no marker behind. The control is the
# write half alone, which proves the write scan is live rather than silently skipped.
$armWrite = @(
    @{ n = 'canon-then-rm';   c = 'cat DESIGN-CHARTER.md && rm -rf plugins/keel-workflow' },
    @{ n = 'awk-then-rm';     c = 'awk /DESIGN-CHARTER.md/ README.md && rm -rf plugins/keel-workflow' },
    @{ n = 'canon-then-redir'; c = 'cat DESIGN-CHARTER.md ; echo x > plugins/keel-workflow/x.md' },
    @{ n = 'type-then-sed-i'; c = 'type DESIGN-CHARTER.md && sed -i s/a/b/ plugins/keel-workflow/.claude-plugin/plugin.json' },
    @{ n = 'canon-then-cp';   c = 'cat ./DESIGN-CHARTER.md && cp x plugins/keel-workflow/y' }
)
foreach ($item in $armWrite) {
    $Cases += New-Case -Name $item.n -Group '4-armwrite' -Tool 'Bash' -ToolInput @{ command = $item.c } -ExpectExit 2 -ExpectArm $false
}
$Cases += New-Case -Name 'CONTROL-write-half-alone' -Group '4-armwrite' -Tool 'Bash' -ToolInput @{ command = 'rm -rf plugins/keel-workflow' } -ExpectExit 2 -ExpectArm $false

# --- Group 5: a write into plugins/ is blocked --------------------------------
# The first row is the HARNESS CONTROL. If it is not 2, nothing else here means
# anything, and the summary says so rather than printing a green sweep.
$Cases += New-Case -Name 'HARNESS-CONTROL-edit-into-plugins' -Group '5-block' -Tool 'Edit'       -ToolInput @{ file_path = $PluginTarget } -ExpectExit 2
$Cases += New-Case -Name 'bash-rm-plugins'                   -Group '5-block' -Tool 'Bash'       -ToolInput @{ command = 'rm -rf plugins/keel-workflow/skills/x' } -ExpectExit 2
$Cases += New-Case -Name 'bash-rm-outside'                   -Group '5-block' -Tool 'Bash'       -ToolInput @{ command = 'rm -rf scripts/x' } -ExpectExit 0
$Cases += New-Case -Name 'bash-rm-plugins-ARMED'             -Group '5-block' -Tool 'Bash'       -ToolInput @{ command = 'rm -rf plugins/keel-workflow/skills/x' } -ExpectExit 0 -PreArm
$Cases += New-Case -Name 'ps-setcontent-in'                  -Group '5-block' -Tool 'PowerShell' -ToolInput @{ command = 'Set-Content -LiteralPath plugins/keel-workflow/x.json -Value 1' } -ExpectExit 2
$Cases += New-Case -Name 'ps-setcontent-out'                 -Group '5-block' -Tool 'PowerShell' -ToolInput @{ command = 'Set-Content -LiteralPath scripts/x.json -Value 1' } -ExpectExit 0
$Cases += New-Case -Name 'sed-i-plugins'                     -Group '5-block' -Tool 'Bash'       -ToolInput @{ command = 'sed -i s/a/b/ plugins/keel-workflow/.claude-plugin/plugin.json' } -ExpectExit 2
$Cases += New-Case -Name 'redirect-plugins'                  -Group '5-block' -Tool 'Bash'       -ToolInput @{ command = 'echo x > plugins/keel-workflow/x.md' } -ExpectExit 2
$Cases += New-Case -Name 'write-tool-in'                     -Group '5-block' -Tool 'Write'      -ToolInput @{ file_path = (Join-Path $RootPath 'plugins\keel-workflow\SKILL.md') } -ExpectExit 2
$Cases += New-Case -Name 'write-tool-out'                    -Group '5-block' -Tool 'Write'      -ToolInput @{ file_path = (Join-Path $RootPath 'scripts\x.ps1') } -ExpectExit 0
$Cases += New-Case -Name 'backslash-continued-rm'            -Group '5-block' -Tool 'Bash'       -ToolInput @{ command = "rm -rf \`n  plugins/keel-workflow" } -ExpectExit 2
$Cases += New-Case -Name 'multiedit-in-plugins'              -Group '5-block' -Tool 'MultiEdit'  -ToolInput @{ file_path = $PluginTarget } -ExpectExit 2
$Cases += New-Case -Name 'notebookedit-in-plugins'           -Group '5-block' -Tool 'NotebookEdit' -ToolInput @{ file_path = $PluginTarget } -ExpectExit 2

# --- Group 6: the verb half of the git/patch element -------------------------
# These rows fail against a gate whose verb group carries `patch` as a bare
# alternative. A suite written only after a fix is green either way and proves nothing,
# so rows like these belong in the file before the gate changes.
#
# WHAT THEY GUARD. With `patch` as a bare alternative in the verb group of the last
# element of $WriteIntoPlugins, the \b-delimited word `patch` inside the FILENAME
# changes-keel.patch satisfies the verb half. That filename is not incidental -
# keel-run-phase mandates changes-<repo>.patch as the implement-gate artifact for every
# agent phase with a declared repo, so the gate would manufacture its own trigger token
# and then refuse with a reason that was false, sending the reader to the charter when
# nothing was being written at all.
#
# WHY THE CONTROLS OUTNUMBER THE DEFECT ROWS SIX TO ONE. Changing a pattern with only the
# bug's own cases for company is how a fix shows all-green while silently breaking
# something else - a gate made unarmable by any command, say. The controls are the cases
# that have to KEEP working, and they must pass against BOTH gates. A repair that passes
# every case its author wrote can still fail cases a fresh verifier writes, and this
# ratio is what catches it.
$patchAllowed = @(
    @{ n = 'patch-artifact-then-plugins'; c = "git diff > changes-keel.patch`nls plugins/keel-workflow" },
    @{ n = 'patch-artifact-wrapper-call'; c = "keel-state.ps1 signal -Evidence 'changes-keel.patch was named'`nand plugins/keel-workflow was read" },
    @{ n = 'patch-artifact-under-path';   c = "ls .keel/phases/W4.2/changes-keel.patch`ngrep x plugins/a" },
    @{ n = 'patch-artifact-quoted';       c = "git diff > `"changes-keel.patch`"`nls plugins/a" },

    # The same word as an ordinary English noun. The (?<!\.) lookbehind stops the
    # ARTIFACT FILENAME and does nothing about the noun. Because every keel-state.ps1
    # invocation here names the guarded directory on its own line, and the character
    # class excludes only | ; and &, any command that mentions a diff in prose and also
    # calls the wrapper would be refused - on the same line or a later one. These rows
    # fail against a gate without the noun rule.
    @{ n = 'patch-noun-same-line';        c = "echo 'regenerated the patch file under plugins/keel-workflow'" },
    @{ n = 'patch-noun-later-line';       c = "echo 'the patch was clean'`ncat plugins/keel-workflow/SKILL.md" },

    # THIS ROW PINS A SHAPE THE NOUN RULE DELIBERATELY RELEASES, and it is the only row in
    # this file whose job is to hold an under-block in place rather than to stop one. The
    # rule distinguishes the verb from the noun by what PRECEDES it and adds a second limb
    # keyed on what FOLLOWS - a flag, or an input redirect. An invocation with NEITHER,
    # whose first token trails an ordinary word, therefore reads as prose and is allowed
    # through.
    #
    # It is a known cost of that rule, and the limb's own controls all carry a flag or a
    # redirect - so without this row the one shape the gate's own comment claims to cover
    # would be the one shape nothing tested. Against a gate without the noun rule ("old")
    # and the gate as it stands ("now"):
    #
    #     sudo patch plugins/a            old 2, now 0   <- this row
    #     env patch plugins/a             old 2, now 0
    #     xargs patch plugins/a           old 2, now 0
    #     patch plugins/a                 old 2, now 2
    #     sudo patch -p1 plugins/a        old 2, now 2   <- CONTROL-patch-wordprefix-flag
    #     time patch < fix.diff plugins/a old 2, now 2   <- CONTROL-patch-wordprefix-redirect
    #
    # So it discriminates: it passes here and FAILS under -AgainstGate against a gate
    # without the noun rule, which is what a row needs to count as evidence. If a later
    # repair closes this hole the row will start failing - that is the row doing its job,
    # and the fix is to move it to $patchBlocked with the measurement redone, not to
    # delete it.
    @{ n = 'CONTROL-patch-wordprefix-flagless'; c = 'sudo patch plugins/a' }
)
foreach ($item in $patchAllowed) {
    $Cases += New-Case -Name $item.n -Group '6-verbhalf' -Tool 'Bash' -ToolInput @{ command = $item.c } -ExpectExit 0
}

# ONE CONTROL PER CHARACTER THAT CAN PRECEDE A COMMAND, and that enumeration is the
# point of the group rather than a flourish. A repair that inverts the test into a
# whitelist of allowed preceding characters can pass a matrix its author writes and
# still leak on several of these twenty - `bash -c "patch ..."` among them, which is the
# ordinary way a nested shell command is written - because a self-authored matrix tests
# the shapes its author already had in mind. These rows exist so the next repair cannot
# make that trade silently: each must return 2 against BOTH gates, and a row that starts
# returning 0 is a hole.
$patchBlocked = @(
    @{ n = 'CONTROL-patch-pos0';          c = 'patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-space';         c = 'cd x && patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-tab';           c = "cd x &&`tpatch -p1 plugins/a" },
    @{ n = 'CONTROL-patch-newline';       c = "cd x`npatch -p1 plugins/a" },
    @{ n = 'CONTROL-patch-semicolon';     c = 'cd x;patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-pipe';          c = 'true|patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-ampersand';     c = 'true&patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-paren';         c = '(patch -p1 plugins/a)' },
    @{ n = 'CONTROL-patch-brace';         c = '{ patch -p1 plugins/a; }' },
    @{ n = 'CONTROL-patch-dblquote';      c = 'bash -c "patch -p1 plugins/a"' },
    @{ n = 'CONTROL-patch-singlequote';   c = "sh -c 'patch -p1 plugins/a'" },
    @{ n = 'CONTROL-patch-backtick';      c = 'echo `patch -p1 plugins/a`' },
    @{ n = 'CONTROL-patch-slash';         c = '/usr/bin/patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-backslash';     c = 'C:\tools\patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-dotslash';      c = './patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-equals';        c = 'CMD=patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-dollarparen';   c = 'echo $(patch -p1 plugins/a)' },
    @{ n = 'CONTROL-patch-hyphen';        c = 'run --patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-comma';         c = 'try a,patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-colon';         c = 'do:patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-pscommand';     c = 'powershell -Command "patch -p1 plugins/a"' },
    @{ n = 'CONTROL-patch-artifact-input'; c = 'patch -p1 < changes-keel.patch plugins/a' },
    @{ n = 'CONTROL-git-apply-blocks';    c = 'git apply x.diff plugins/a' },
    @{ n = 'CONTROL-git-apply-in-bash-c'; c = 'bash -c "git apply d plugins/a"' },
    @{ n = 'CONTROL-git-checkout-blocks'; c = 'git checkout HEAD -- plugins/a' },
    @{ n = 'CONTROL-git-restore-blocks';  c = 'git restore plugins/a' },

    # The noun rule's OWN controls, and they guard the half of the fix that is not obvious.
    # The repair distinguishes the verb from the noun by what PRECEDES it: prose is a
    # word followed by whitespace, and not one of Group 6's twenty preceding characters
    # is. That rule alone releases a real invocation whose first token happens to follow
    # an ordinary word - `sudo`, `xargs`, `env`, `time` - so the fix carries a second
    # limb keyed on what FOLLOWS: a flag, or an input redirect. These three rows are the
    # only thing standing between that limb and a later repair that drops it silently,
    # which is this group's six-to-one control ratio doing its job again.
    @{ n = 'CONTROL-patch-wordprefix-flag';     c = 'sudo patch -p1 plugins/a' },
    @{ n = 'CONTROL-patch-wordprefix-longflag'; c = 'env patch --dry-run plugins/a' },
    @{ n = 'CONTROL-patch-wordprefix-redirect'; c = 'time patch < fix.diff plugins/a' }
)
foreach ($item in $patchBlocked) {
    $Cases += New-Case -Name $item.n -Group '6-verbhalf' -Tool 'Bash' -ToolInput @{ command = $item.c } -ExpectExit 2
}

# --- Group 7: write-shaped text QUOTED inside an argument ---------------------
# THIS GROUP PINS THE GATE'S CURRENT BEHAVIOUR. It does not accompany a change to the
# gate; the rows below record what the gate does now so that a future repair cannot move
# it by accident.
#
# WHAT THE quoted- ROWS PIN, AND WHY THEY EXPECT 2 RATHER THAN 0. The gate scans the raw
# command string, so write-shaped text sitting inside a QUOTED ARGUMENT of a command that
# writes nothing - `keel-state.ps1 note-friction -Detail "... rm -rf plugins/x ..."` - is
# refused exactly like the write it quotes. The cost is real and it is not lost time: a
# session that rewords the note to get past the gate silently edits the project's own
# evidence record.
#
# It is NOT fixed, deliberately, and the ten `quoted-` rows below therefore expect exit
# 2. Each of these repair shapes has a hole, including the shapes the limitation most
# obviously suggests:
#
#   skip quoted spans when the head is not a write verb
#           -> releases every nested shell: bash -c, sh -c, powershell -Command
#   subtract the -Detail / -Evidence span
#           -> command substitution inside the exempted value still executes
#   the same, with the value's character class tightened
#           -> the regex pairs the CLOSING quote of one argument with the OPENING quote
#              of the next, so it erases the guarded path itself; and after a bare `--`
#              the flag is an operand, so it erases a real write target
#   exempt the whole command when it is one keel-state.ps1 invocation
#           -> PowerShell (...) and @(...) execute and contain none of the excluded
#              characters; and the script is identified by BASENAME, so a keel-state.ps1
#              minted anywhere at all is exempt from then on
#
# THE SUITE WITHOUT THIS GROUP CATCHES ONLY THE FIRST OF THEM. Skipping quoted spans fails
# the four Group 6 nested-shell controls - patch-dblquote, patch-singlequote,
# patch-pscommand and git-apply-in-bash-c; prototypes of the other three failed no row
# the suite held before this group. So every hole in those three has to be found by an
# adversarial reader, and that is what this group is for: the nineteen under-block CONTROL-
# rows are such holes, written down, and each must return 2 against any gate. Of those
# nineteen, the last three are the only ones a prototype of the fourth shape failed, which is
# why they exist.
#
# FIVE OF THE NINETEEN WERE FLIPPED BY NONE OF THE FOUR PROTOTYPES, and they are not padding.
# Fourteen rows are the union the four prototypes opened; the other five -
# detail-then-real-write, real-write-then-detail, detail-redirect, semicolon-after-wrapper
# and newline-after-wrapper - are shapes every prototype happened to keep blocking. They are
# here because the next repair will not be one of these four, and a control set built only
# from the holes already found is a control set that tests the last bug.
#
# The arithmetic: ten quoted- rows, nineteen under-block CONTROL- rows, and TWO more
# CONTROL- rows that are the location pair - the same write inside the guarded folder and
# outside it. Ten plus nineteen plus two is the thirty-one, and twenty-one of them are
# named CONTROL-quoted-. The location pair is what says the gate still discriminates by
# PATH rather than refusing everything; without it none of the 2s above would mean
# anything.
#
# THE TEN quoted- ROWS ARE THE ONES THAT MUST FLIP if the matching is ever widened, and on
# the day they do, every CONTROL- row below must still hold. Moving one is not a licence
# to delete a control; it is the moment the controls start earning their keep.
#
# There is no subtractive repair available here, and that is why the group pins rather
# than fixes. The `patch` complaints Group 6 covers were fixed by REMOVING one thing from
# a pattern - a shape the gate's own comment argues cannot under-block, by construction -
# and that worked because `.patch` the filename and `patch` the noun differ in context.
# `rm -rf plugins/x` quoted inside a note is character-for-character identical to the
# real command, so there is nothing to subtract.
#
# THE DOCUMENTED WAY PAST IT, which the gate's own refusal message names: write the prose
# to a file with the Write tool, then pass it as -Detail with a command substitution that
# cats the file. Through the live hook it delivers the file verbatim except the trailing
# newline, at exit 0. A shell redirect will not do - the printf carrying the same text is
# refused for the same reason.
$quotedBlocked = @(
    # The ten quoted- rows: the documented limitation, pinned at the current verdict.
    @{ n = 'quoted-detail-rm';             c = 'keel-state.ps1 note-friction -Phase W4.2 -Kind gap -Detail "the gate refused because rm -rf plugins/keel-workflow appeared in this text"' },
    @{ n = 'quoted-detail-sed-i';          c = 'keel-state.ps1 note-friction -Phase W4.2 -Kind gap -Detail "I ran sed -i on plugins/keel-workflow/SKILL.md"' },
    @{ n = 'quoted-detail-full-wrapper';   c = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "plugins/keel-workflow/skills/keel-orchestrator/wrappers/keel-state.ps1" note-friction -Phase W4.2 -Kind gap -Detail "the call cp x plugins/keel-workflow/y was refused"' },
    @{ n = 'quoted-evidence-cp';           c = "keel-state.ps1 signal -Kind refusal -Evidence 'the call cp x plugins/keel-workflow/y was blocked'" },
    @{ n = 'quoted-detail-singlequoted';   c = "keel-state.ps1 note-friction -Kind gap -Detail 'rm -rf plugins/keel-workflow was the text'" },
    @{ n = 'quoted-detail-lowercase-flag'; c = 'keel-state.ps1 note-friction -Kind gap -detail "rm -rf plugins/keel-workflow was the text"' },
    @{ n = 'quoted-detail-setcontent';     c = 'keel-state.ps1 note-friction -Kind gap -Detail "Set-Content plugins/keel-workflow/x.json was refused"' },
    @{ n = 'quoted-detail-unquoted-value'; c = 'keel-state.ps1 note-friction -Kind gap -Detail rm -rf plugins/keel-workflow' },
    @{ n = 'quoted-scope-quotes-write';    c = 'keel-state.ps1 add-phase -Phase W9.1 -Scope "rm -rf plugins/keel-workflow"' },
    @{ n = 'quoted-detail-quotes-write';   c = 'keel-state.ps1 note-friction -Phase W4.2 -Kind gap -Detail "the gate refused because rm -rf plugins/keel-workflow was in the note"' },

    # The blocking half of the location pair. Its partner is in $quotedAllowed below, and
    # the two together are what say the gate discriminates by LOCATION rather than
    # refusing everything - without which none of the 2s above means anything.
    @{ n = 'CONTROL-quoted-write-inside-guarded'; c = 'rm -rf plugins/keel-workflow/skills/x' },

    # Sixteen under-block controls: holes in the first three repair shapes described above,
    # and shapes the next repair could open. Each must return 2 against ANY gate. A row
    # here returning 0 is a hole, not a release.
    @{ n = 'CONTROL-quoted-detail-then-real-write';  c = 'keel-state.ps1 note-friction -Kind gap -Detail "a harmless note" && rm -rf plugins/keel-workflow' },
    @{ n = 'CONTROL-quoted-real-write-then-detail';  c = 'rm -rf plugins/keel-workflow && keel-state.ps1 note-friction -Kind gap -Detail "a harmless note"' },
    @{ n = 'CONTROL-quoted-nested-shell';            c = 'bash -c "rm -rf plugins/keel-workflow"' },
    @{ n = 'CONTROL-quoted-detail-redirect';         c = 'keel-state.ps1 note-friction -Kind gap -Detail "note" > plugins/keel-workflow/x.md' },
    @{ n = 'CONTROL-quoted-detail-dollarparen';      c = 'keel-state.ps1 note-friction -Kind gap -Detail "note $(rm -rf plugins/keel-workflow)"' },
    @{ n = 'CONTROL-quoted-detail-backtick';         c = 'keel-state.ps1 note-friction -Kind gap -Detail "note `rm -rf plugins/keel-workflow`"' },
    @{ n = 'CONTROL-quoted-semicolon-after-wrapper'; c = 'keel-state.ps1 note-friction -Kind gap -Detail "a" ; rm -rf plugins/keel-workflow' },
    @{ n = 'CONTROL-quoted-newline-after-wrapper';   c = "keel-state.ps1 note-friction -Kind gap -Detail `"a`"`nrm -rf plugins/keel-workflow" },
    @{ n = 'CONTROL-quoted-quotepair-rm-prefix';     c = 'rm -rf "junk -Detail " plugins/keel-workflow/skills/x "other"' },
    @{ n = 'CONTROL-quoted-quotepair-single';        c = "rm -rf 'junk -Detail ' plugins/keel-workflow/skills/x 'other'" },
    @{ n = 'CONTROL-quoted-quotepair-evidence';      c = 'cp -r "src -Evidence " plugins/keel-workflow/skills "tail"' },
    @{ n = 'CONTROL-quoted-quotepair-sed';           c = 'sed -i "s/a/b/" "n -Detail " plugins/keel-workflow/skills/y.md "z.md"' },
    @{ n = 'CONTROL-quoted-dashdash-operand';        c = 'rm -rf -- junk -Detail "plugins/keel-workflow/skills/x"' },
    @{ n = 'CONTROL-quoted-dashdash-touch';          c = 'touch -- -Detail "plugins/keel-workflow/skills/new.md"' },
    @{ n = 'CONTROL-quoted-wrapper-name-substring';  c = 'evil-keel-state.ps1x note-friction -Detail "rm -rf plugins/keel-workflow"' },
    @{ n = 'CONTROL-quoted-pscommand-not-file';      c = 'powershell -NoProfile -Command "rm -rf plugins/keel-workflow"' },

    # THE LAST THREE ARE THE ONLY CONTROL ROWS A PROTOTYPE OF THE FOURTH SHAPE FAILED, and
    # that is why they are here. Every other row it failed is a quoted- release row, which
    # proves only that it releases the quoted text - which all four prototypes did. A
    # discrimination check satisfied by a release row flipping measures the release, not
    # the hole.
    @{ n = 'CONTROL-quoted-detail-bare-subexpression';   c = 'keel-state.ps1 note-friction -Kind gap -Detail "note (Remove-Item -Recurse -Force plugins\keel-workflow)"' },
    @{ n = 'CONTROL-quoted-detail-array-subexpression';  c = 'keel-state.ps1 note-friction -Kind gap -Detail "note @(Remove-Item -Recurse -Force plugins\keel-workflow)"' },
    @{ n = 'CONTROL-quoted-wrapper-minted-outside-repo'; c = 'C:/Windows/Temp/keel-state.ps1 note-friction -Kind gap -Detail "rm -rf plugins/keel-workflow"' }
)
foreach ($item in $quotedBlocked) {
    $Cases += New-Case -Name $item.n -Group '7-quotedarg' -Tool 'Bash' -ToolInput @{ command = $item.c } -ExpectExit 2
}

# The allowed half of the location pair. The same verb, the same shape, a path outside
# the guarded folder. If this row ever returns 2 the gate has stopped discriminating by
# location and every other row in this group is measuring nothing.
$quotedAllowed = @(
    @{ n = 'CONTROL-quoted-write-outside-guarded'; c = 'rm -rf scripts/x' }
)
foreach ($item in $quotedAllowed) {
    $Cases += New-Case -Name $item.n -Group '7-quotedarg' -Tool 'Bash' -ToolInput @{ command = $item.c } -ExpectExit 0
}

# ---------------------------------------------------------------------------
# GROUP 8 - the rows that read what the gate PRINTS.
#
# Every other row asserts an exit code, a case count or a failure count, and none reads a
# rendered line, so a refusal message can be wrong for as long as it exists without one
# row noticing. The message is a DOUBLE-QUOTED here-string; backtick is PowerShell's
# escape character, so markdown backticks in it are consumed, and the `t in the word
# 'tail' renders as a literal TAB. A message carrying them would read
# "not head, <TAB>ail, sed, more, gc or a grep" to a blocked session. A human running a
# route control by hand is not a mechanism; these rows are.
#
# TWO LIMBS, and the second is the one that needs care. The presence limb alone is
# enough to fail against a gate with that defect, so -AgainstHead does not exercise the
# absence limb at all; prove that limb separately by pointing it at a pattern known to
# be present and confirming this row FAILS.
$Cases += New-Case -Name 'MESSAGE-refusal-renders-clean' -Group '8-message' -Tool 'Edit' `
    -ToolInput @{ file_path = $PluginTarget } -ExpectExit 2 `
    -StderrMustMatch 'not head, tail, sed, more, gc or a grep' `
    -StderrMustNotMatch '\t'

# From another folder a bare file name means nothing, so the refusal names the charter
# of the gate under test in full. Built from $RootPath, so a copied gate must name its own.
$Cases += New-Case -Name 'MESSAGE-refusal-names-own-charter' -Group '8-message' -Tool 'Edit' `
    -ToolInput @{ file_path = $PluginTarget } -ExpectExit 2 `
    -StderrMustMatch ([regex]::Escape($CharterFile))

# ---------------------------------------------------------------------------
# GROUP 9 - a charter-read command arms only where it can read this charter.
#
# All five strings are relative, so a session in a sibling folder that runs
# `cat DESIGN-CHARTER.md` reads nothing; a gate that ignores cwd would arm and let its
# write under plugins/ through. Measured through a live session, which is why the arming
# rows here also send the following write: the marker is only the means, and whether the
# write gets through is the claim.
#
# BOTH DIRECTIONS FOR ALL FIVE COMMANDS. A gate that stopped arming altogether passes the
# sibling rows, and one that ignores cwd passes the root rows.
$siblingDir = Join-Path (Split-Path -Parent $RootPath) 'keel-records-sibling'
foreach ($item in $mustArm[0..4]) {
    $Cases += New-Case -Name ('cwd-sibling-' + $item.n) -Group '9-cwd' -Tool 'Bash' -ToolInput @{ command = $item.c } `
        -Cwd $siblingDir -ExpectExit 0 -ExpectArm $false -ThenWriteTo $PluginTarget -ThenWriteExit 2
    $Cases += New-Case -Name ('cwd-root-' + $item.n) -Group '9-cwd' -Tool 'Bash' -ToolInput @{ command = $item.c } `
        -Cwd $RootPath -ExpectExit 0 -ExpectArm $true -ThenWriteTo $PluginTarget -ThenWriteExit 0
}

# Folders that are not the charter's, and values that are not a folder at all. '<root>-other'
# is here because a prefix test is the easy way to get this wrong.
$noArmCwd = @(
    @{ n = 'cwd-repo-subfolder';  d = (Join-Path $RootPath 'scripts') },
    @{ n = 'cwd-prefix-sibling';  d = ($RootPath + '-other') },
    @{ n = 'cwd-blank';           d = '   ' },
    @{ n = 'cwd-relative';        d = '.' },
    @{ n = 'cwd-unresolvable';    d = 'C:\<<>>|bad' }
)
foreach ($item in $noArmCwd) {
    $Cases += New-Case -Name $item.n -Group '9-cwd' -Tool 'Bash' -ToolInput @{ command = 'cat DESIGN-CHARTER.md' } `
        -Cwd $item.d -ExpectExit 0 -ExpectArm $false
}
$Cases += New-Case -Name 'cwd-omitted' -Group '9-cwd' -Tool 'Bash' -ToolInput @{ command = 'cat DESIGN-CHARTER.md' } `
    -OmitCwd -ExpectExit 0 -ExpectArm $false

# Two values that can arm a gate whose cwd test is too loose, though no real payload carries
# either. A bare drive counts as rooted and resolves against the gate process, so this row
# runs it from the root; from anywhere else it passes whatever the gate does. A one-element
# array casts to the very string it holds.
$Cases += New-Case -Name 'cwd-drive-relative' -Group '9-cwd' -Tool 'Bash' -ToolInput @{ command = 'cat DESIGN-CHARTER.md' } `
    -Cwd ($RootPath.Substring(0, 2)) -RunFrom $RootPath -ExpectExit 0 -ExpectArm $false
$Cases += New-Case -Name 'cwd-array' -Group '9-cwd' -Tool 'Bash' -ToolInput @{ command = 'cat DESIGN-CHARTER.md' } `
    -Cwd @($RootPath) -ExpectExit 0 -ExpectArm $false

# The same folder spelled differently must still arm, or a working read is refused.
$armCwd = @(
    @{ n = 'cwd-forward-slashes';    d = ($RootPath -replace '\\', '/') },
    @{ n = 'cwd-trailing-backslash'; d = ($RootPath + '\') },
    @{ n = 'cwd-other-case';         d = $RootPath.ToUpperInvariant() }
)
foreach ($item in $armCwd) {
    $Cases += New-Case -Name $item.n -Group '9-cwd' -Tool 'Bash' -ToolInput @{ command = 'cat DESIGN-CHARTER.md' } `
        -Cwd $item.d -ExpectExit 0 -ExpectArm $true
}

# The Read tool names its target in full, so it arms from any folder. A session in a folder
# beside this repo depends on this.
$Cases += New-Case -Name 'read-from-sibling-ARMS' -Group '9-cwd' -Tool 'Read' -ToolInput @{ file_path = $CharterFile } `
    -Cwd $siblingDir -ExpectExit 0 -ExpectArm $true -ThenWriteTo $PluginTarget -ThenWriteExit 0

# A bad cwd must not skip the write scan by throwing into the outer catch.
$Cases += New-Case -Name 'write-scan-survives-bad-cwd' -Group '9-cwd' -Tool 'Bash' -ToolInput @{ command = 'rm -rf plugins/keel-workflow' } `
    -Cwd 'C:\<<>>|bad' -ExpectExit 2 -ExpectArm $false
$Cases += New-Case -Name 'write-scan-survives-no-cwd' -Group '9-cwd' -Tool 'Bash' -ToolInput @{ command = 'rm -rf plugins/keel-workflow' } `
    -OmitCwd -ExpectExit 2 -ExpectArm $false

# Every row that stated no folder runs in the root of the gate under test, so what it asserted
# before this group still holds, and a comparison gate is judged at its own root.
foreach ($stamped in $Cases) {
    if (-not $stamped.OmitCwd -and [string]::IsNullOrEmpty($stamped.Cwd)) { $stamped.Cwd = $RootPath }
}

return $Cases
}

# ---------------------------------------------------------------------------
function Invoke-Suite {
    param([string]$Gate, [string]$Label, [object[]]$Cases)

    if (-not $Quiet) { Write-Output ''; Write-Output "== $Label" }
    $failed      = @()
    $failedNames = @()
    $control     = $null

    foreach ($case in $Cases) {
        $result = Invoke-Case -Case $case -Gate $Gate
        if (-not $result.Ok) {
            $failed      += ("{0,-32} {1}" -f $case.Name, $result.Why)
            $failedNames += $case.Name
        }
        if ($case.Name -eq 'HARNESS-CONTROL-edit-into-plugins') { $control = $result.Ok }
        if (-not $Quiet -and -not $result.Ok) {
            Write-Output ("  FAIL  {0,-32} {1}" -f $case.Name, $result.Why)
        }
    }

    if ($control -ne $true) {
        Write-Output ''
        Write-Output '  HARNESS CONTROL FAILED: an Edit into plugins/ on an unmarked session did not exit 2.'
        Write-Output '  The suite is not reaching the gate. No other row in this run means anything.'
    }

    if (-not $Quiet) {
        Write-Output ("  {0} case(s), {1} failure(s)." -f $Cases.Count, $failed.Count)
    }

    # A PowerShell function returns EVERYTHING it emits. This one prints, so returning
    # the count as well would hand the caller an array of every line plus the number -
    # and an array is truthy, so the suite would report itself clean. Set a $script:
    # flag instead.
    #
    # The NAMES as well as the count: "both gates failed once" and "both gates failed the
    # SAME case" are different claims, and only the second one says location did not
    # change the verdict.
    $script:LastFailureCount = $failed.Count
    $script:LastFailureNames = $failedNames
}

# ---------------------------------------------------------------------------
# A comparison gate runs in a MIRRORED layout: <sandbox>\scripts\keel-plugins-gate.ps1.
#
# WHY THE MIRROR IS THE WHOLE FIX. The gate resolves its charter as parent-of(its own
# directory). Dropped loose into %TEMP% it would look for a charter in %TEMP%'s parent,
# while cases naming THIS repo's charter would leave read-full-ARMS-control unable to
# arm, and charge the comparison gate a failure earned by where it had been put.
#
# The mirror plus New-CaseSet -RootPath $sandboxRoot makes both halves agree: the gate
# resolves <sandbox>\DESIGN-CHARTER.md and the case asks about <sandbox>\DESIGN-CHARTER.md.
# Nothing is written at that path and nothing needs to be - the gate compares two
# resolved strings and never opens the file. That is measured, not assumed: a mirrored
# gate arms on a charter path with nothing at the end of it.
#
# It prints (through Invoke-Suite) and so must return nothing: a function returns
# everything it emits. The caller reads $script:LastFailureCount and
# $script:LastFailureNames, as with the working-tree run.
function Invoke-ComparisonRun {
    param(
        [string]$SandboxName,
        [string]$SourceGateFile,
        [string[]]$SourceGateText,
        [string]$Label
    )

    $sandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) $SandboxName
    try {
        if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }
        $sandboxScripts = Join-Path $sandboxRoot 'scripts'
        New-Item -ItemType Directory -Path $sandboxScripts -Force | Out-Null
        $sandboxGate = Join-Path $sandboxScripts 'keel-plugins-gate.ps1'

        if (-not [string]::IsNullOrWhiteSpace($SourceGateFile)) {
            # COPIED, not rewritten, so the sandbox gate is byte-identical to its
            # source and a caller comparing SHA256 gets the answer it expects.
            Copy-Item -LiteralPath $SourceGateFile -Destination $sandboxGate -Force
        }
        else {
            Set-Content -LiteralPath $sandboxGate -Value ($SourceGateText -join [Environment]::NewLine) -Encoding ASCII
        }

        Invoke-Suite -Gate $sandboxGate -Label $Label -Cases @(New-CaseSet -RootPath $sandboxRoot)
    }
    finally {
        # In a finally, and the whole tree: a run that throws must leave nothing for
        # git status or the commit gate to trip over.
        if (Test-Path -LiteralPath $sandboxRoot) { Remove-Item -LiteralPath $sandboxRoot -Recurse -Force }
    }
}

# SETS, not counts. "both gates failed once" and "both gates failed the SAME case" are
# different claims, and only the second one says location changed no verdict. Counts
# alone would call a swap - one case starting to fail as another stopped - a match.
#
# Prints, therefore returns nothing: a function returns everything it emits.
function Write-SetComparison {
    param([string[]]$WorkingNames, [string[]]$OtherNames, [string]$OtherLabel)

    $onlyWorking = @($WorkingNames | Where-Object { $OtherNames    -notcontains $_ })
    $onlyOther   = @($OtherNames   | Where-Object { $WorkingNames  -notcontains $_ })
    if ($onlyWorking.Count -eq 0 -and $onlyOther.Count -eq 0) {
        Write-Output '  Failure sets are IDENTICAL: location changed no verdict.'
        return
    }
    Write-Output '  FAILURE SETS DIFFER: the two gates disagree on which cases fail.'
    foreach ($nm in $onlyWorking) { Write-Output ("    only under the working tree: {0}" -f $nm) }
    foreach ($nm in $onlyOther)   { Write-Output ("    only under the {0}: {1}" -f $OtherLabel, $nm) }
}

$script:LastFailureCount = 0
$script:LastFailureNames = @()

# @(...) at the call site: a single-element array unrolls through return.
$WorkingCases = @(New-CaseSet -RootPath $RepoRoot)
Invoke-Suite -Gate $GatePath -Label "working tree: $GatePath" -Cases $WorkingCases
$wtFailures    = $script:LastFailureCount
$wtFailedNames = @($script:LastFailureNames)

$headFailures = -1
if ($AgainstHead) {
    Push-Location $RepoRoot
    try {
        # No bare 2>&1 on a native call - it would fold any stderr line into the text
        # being captured. Let the exit code decide.
        $prevPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $headText = & git show HEAD:scripts/keel-plugins-gate.ps1
        $gitCode  = $LASTEXITCODE
        $ErrorActionPreference = $prevPreference
        if ($gitCode -ne 0) { throw "git show HEAD:scripts/keel-plugins-gate.ps1 failed with exit $gitCode" }
    }
    finally { Pop-Location }

    Invoke-ComparisonRun -SandboxName 'keel-gate-suite-HEAD' -SourceGateText $headText -Label 'committed gate at HEAD (discrimination control)'
    $headFailures    = $script:LastFailureCount
    $headFailedNames = @($script:LastFailureNames)
}

$namedFailures = -1
if (-not [string]::IsNullOrWhiteSpace($AgainstGate)) {
    if (-not (Test-Path -LiteralPath $AgainstGate)) {
        throw "-AgainstGate: no gate file at $AgainstGate"
    }
    Invoke-ComparisonRun -SandboxName 'keel-gate-suite-NAMED' -SourceGateFile $AgainstGate -Label "named gate: $AgainstGate"
    $namedFailures    = $script:LastFailureCount
    $namedFailedNames = @($script:LastFailureNames)
}

Write-Output ''
# THIS LINE IS PARSED, not just read. check-suite-docs.ps1 lifts the case and failure
# counts out of it with a literal regex at both the commit gate and -Strict, and treats
# an unparseable summary as a Problem rather than a zero. Do not reword it.
Write-Output ("test-plugins-gate: {0} case(s), working tree {1} failure(s)." -f $WorkingCases.Count, $wtFailures)
if ($AgainstHead) {
    Write-Output ("                   HEAD {0} failure(s)." -f $headFailures)
    if ($headFailures -le $wtFailures) {
        Write-Output '  NOT EVIDENCE: the suite does not discriminate between the two gates.'
    }
    Write-SetComparison -WorkingNames $wtFailedNames -OtherNames $headFailedNames -OtherLabel 'committed gate'
}
if (-not [string]::IsNullOrWhiteSpace($AgainstGate)) {
    Write-Output ("                   named gate {0} failure(s)." -f $namedFailures)
    Write-SetComparison -WorkingNames $wtFailedNames -OtherNames $namedFailedNames -OtherLabel 'named gate'
}

if ($wtFailures -gt 0) { exit 1 }
exit 0
