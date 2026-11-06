<#
    keel-plugins-gate.ps1 - repo-local PreToolUse gate.

    Charter P14: this is a REPO-LOCAL hook, wired from .claude/settings.json, because
    it enforces a rule about THIS repo. It is not a plugin hook and must never become
    one - plugin hooks spawn a process in every session everywhere.

    What it does:
      * Reading DESIGN-CHARTER.md IN FULL drops a per-session marker.
      * A change to anything under plugins/** is BLOCKED unless that marker exists.

    Both halves accept EITHER a file-path tool OR a shell command (Bash / PowerShell),
    because a session reads and writes files both ways. The .claude/settings.json
    matcher must name every tool handled here or this code is never invoked for it;
    check-suite-docs.ps1 section 8 asserts that, because the two can drift apart
    silently.

    Both directions matter:
      * A charter read in full with `cat` must arm the gate. A gate that only
        recognises one way of reading is measuring which tool you used, not whether
        you read it.
      * `sed -i` on a file under plugins/ must be blocked. A block that tests the tool
        NAME against Edit/Write/MultiEdit lets every shell write through, because Bash
        is not on that list.

    This is NOT a new rung on charter P13's ladder. The rule already lives at the
    PreToolUse rung; the shell paths were a hole IN that rung, and closing a hole is
    not the same as escalating.

    ARMING IS EXACT, NOT INFERRED. See $CharterReadCommands below for why - it is the
    whole design of this file and the thing most likely to get "helpfully" relaxed.

    Fails OPEN on any parse problem: a broken gate must not brick the session.

    Windows PowerShell 5.1 compatible. ASCII only.
    PreToolUse contract: exit 2 blocks the call and feeds stderr back to Claude.
#>

$ErrorActionPreference = 'SilentlyContinue'

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $hook = $raw | ConvertFrom-Json
} catch { exit 0 }

# An empty or whitespace payload parses to $null WITHOUT throwing, so the catch above
# is not enough and the crash would land later, on the first property access.
if ($null -eq $hook) { exit 0 }

# THE CANONICAL SET. A shell command arms the gate if, and only if, the whole command
# after trimming is EXACTLY one of these strings. This is a set-membership test and
# NOT a pattern. Do not "improve" it into one.
#
# WHY EXACT: a mechanism that asks "does this command text look like a read of the
# charter?" can be made to answer yes in many distinct ways without reading anything.
# Pattern variants - same-run, segment-anchored, command-anchored plus a quote guard -
# each close one class and leave another: the last still leaves unquoted `sed`/`awk`
# search addresses and `OLD-DESIGN-CHARTER.md`.
#
# The deeper problem is not whether this can be done deliberately. It is that arming
# can happen while the charter never enters the session's context:
#     cat DESIGN-CHARTER.md > /dev/null
#     git commit -m "docs: notes; cat DESIGN-CHARTER.md later"
#     awk /DESIGN-CHARTER.md/ README.md
# A regex over an untokenised shell string CANNOT decide whether a file was read.
#
# Exact equality can, because it leaves no room in the string for anything else. A
# trailing `> /dev/null`, an `&& rm -rf plugins/x`, a separator inside a quoted commit
# message and a `.bak` suffix all make the string UNEQUAL. That is why this closes
# every such class at once instead of one at a time, and it is simpler than a pattern
# with two guards - membership instead.
#
# WHAT BREAKS IF YOU MAKE THIS A PATTERN AGAIN: those classes re-open together, and the
# next session cannot tell, because the gate fails open and a false arm is silent.
#
# THE SET SAYS WHAT WAS RUN, AND THE PAYLOAD'S cwd SAYS WHERE. All five strings are
# relative, so each reads THIS charter only when run from this repo's root. A session in
# a sibling folder that runs `cat DESIGN-CHARTER.md` reads nothing, and without the cwd
# test it would arm the gate and its Write under plugins/ would land. So a member of the
# set arms only where cwd joined to the file name resolves to this gate's own charter. A
# cwd that is missing, blank, relative, drive-relative, unresolvable or not a string does
# not arm. It compares strings and never opens the file, as the Read branch does.
#
# cwd IS WHERE THE COMMAND RUNS, NOT WHERE THE SESSION STARTED. Measured through live
# sessions, Bash tool and PowerShell tool each: after a `cd sub` or `Set-Location sub`,
# the next payload's cwd reads ...\sub, and pwd agrees. CLAUDE_PROJECT_DIR stays at the
# start folder, so that variable is the wrong instrument. If a version ever omits cwd,
# shell commands stop arming and the Read tool still does: the safe direction, and the
# refusal says so.
#
# Comparison is -ccontains (case-SENSITIVE). The case-insensitive -contains arms on
# `CAT design-charter.md`. .Trim() is applied first, which covers a leading space, tab,
# newline or CR - none of which changes what the command does.
#
# DELIBERATE COST: reading the charter must be its own command, in one of these exact
# spellings. `gc`, `head -500`, `tail -n 5`, `sed -n 1,500p`, `cat ... | tail`,
# `more <`, `cat --`, `cat $(echo ...)` and `cat ... > /dev/null` do not arm. Every one
# fails SAFE - the gate blocks, and one of the commands below arms it. A miss costs one
# command; a false arm costs the whole gate. The block message names all five so a
# working gate is not read as a broken one.
$CharterReadCommands = @(
    'cat DESIGN-CHARTER.md',
    'cat ./DESIGN-CHARTER.md',
    'Get-Content DESIGN-CHARTER.md',
    'Get-Content -Raw DESIGN-CHARTER.md',
    'type DESIGN-CHARTER.md'
)

# A write whose TARGET is under plugins/. Each pattern stops at a shell separator so
# one segment's verb cannot pair with another segment's path.
#
# This class deliberately does NOT exclude \r\n. A line break inside a command is
# usually a backslash continuation of the SAME command, and missing one of those would
# be a write into plugins/ that this gate waved through. The cost is that
# `rm -f /tmp/x` on one line and a mention of plugins/ on the next is blocked when it
# need not be. Over-blocking is recoverable in one read of the charter; under-blocking
# is the thing the gate exists to prevent. Aligning this class with the arming logic
# would be a regression in the direction with teeth.
#
# Known gaps, all failing in the BLOCKING direction: a relative `plugins/x` file_path
# is not caught while `./plugins/x` is, the `ni` and `sc` aliases are absent, and
# `mkdir -p plugins/new` is unblocked.
#
# WHY `patch` CARRIES A LOOKBEHIND AND THE OTHER VERBS DO NOT. As a bare alternative,
# `\b(...|patch)\b`, the \b-delimited word `patch` inside the FILENAME
# changes-keel.patch would satisfy the verb half. That filename is not incidental:
# keel-run-phase mandates changes-<repo>.patch as the implement-gate artifact for every
# agent phase with a declared repo, so the gate would manufacture its own trigger token
# and then refuse with a reason that was FALSE - sending the reader to the charter when
# nothing was being written at all.
#
# The repair is a SUBTRACTION, not a rewrite. `\bpatch\b` is kept exactly as it was and
# one thing is removed from it: a preceding dot. Nothing else about which strings match
# changes, so this cannot under-block relative to the bare form - by construction,
# rather than by anyone having enumerated the safe cases correctly.
#
# THE SHAPE MATTERS. Do not invert the test into a WHITELIST - for example
# `(?<![^\s|;&({/\\])patch\b`, requiring the preceding character to be whitespace, a
# separator, a bracket or a path separator. It reads as careful and can pass a matrix its
# author wrote, yet it leaks on 7 of the 20 characters that can precede a command:
#     bash -c "patch -p1 plugins/x"        sh -c 'patch -p1 plugins/x'
#     "patch" -p1 plugins/x                echo `patch -p1 plugins/x`
# and `=`, `,`, `:` and `-` leak too. On a gate whose failure directions are
# asymmetric, every character forgotten from a whitelist is a hole, and the author of
# the whitelist is the last person who will think of the character they forgot. Do not
# re-invert this.
#
# The three git alternatives are two-token forms, cannot occur inside a filename, and
# keep their original \b-delimited shape. Group 6 of test-plugins-gate.ps1 pins all of
# this, including one control per preceding character.
#
# THE BARE WORD IS ALSO NARROWED, and only that alternative; the git branch and the
# character class are untouched. The (?<!\.) lookbehind stops the artifact FILENAME. It
# does nothing about the same word as an ordinary English NOUN, and since every
# keel-state.ps1 call here names the guarded directory on its own line, any command
# mentioning a diff in prose would be refused for a reason that was false.
#
# The rule is what PRECEDES the word: prose is a word character followed by whitespace,
# and not one of the twenty preceding characters Group 6 enumerates is. That is a
# BLACKLIST of context, not the whitelist this comment forbids above - which is why it
# keeps all twenty controls blocking where the obvious "anchor it after ; & | or a
# newline" repair releases fourteen of them. Do not reach for that repair.
#
# The second limb keys on what FOLLOWS, and exists because the first alone releases a
# real invocation whose first token trails an ordinary word - sudo, env, xargs, time.
# A flag or an input redirect after the word means a command whatever preceded it.
# Three controls in Group 6 pin this limb; a repair that drops it must fail them.
$WriteIntoPlugins = @(
    '>>?\s*[''"]?[^\s''"|;&]*plugins[\\/]',
    '\bsed\b[^|;&]*?\s-i\b[^|;&]*?plugins[\\/]',
    '\bperl\b[^|;&]*?\s-i\b[^|;&]*?plugins[\\/]',
    '\b(cp|mv|rm|tee|install|touch|truncate|ln)\b[^|;&]*?plugins[\\/]',
    '\b(Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Copy-Item|Move-Item|Clear-Content|Rename-Item)\b[^|;&]*?plugins[\\/]',
    '(?:\b(?:git\s+apply|git\s+checkout|git\s+restore)\b|(?<!\.)(?:(?<!\w[ \t]+)\bpatch\b|\bpatch\b(?=[ \t]+(?:-+\w|<))))[^|;&]*?plugins[\\/]'
)

try {
    $toolName = ''
    if ($hook.PSObject.Properties['tool_name']) { $toolName = [string]$hook.tool_name }

    $sessionId = 'nosession'
    if ($hook.PSObject.Properties['session_id']) { $sessionId = [string]$hook.session_id }
    $sessionId = ($sessionId -replace '[^A-Za-z0-9_-]', '')
    if ([string]::IsNullOrWhiteSpace($sessionId)) { $sessionId = 'nosession' }

    $filePath      = ''
    $commandText   = ''
    $isPartialRead = $false
    if ($hook.PSObject.Properties['tool_input']) {
        # Index the property collection rather than reading .Name off it: under
        # Set-StrictMode an object with no properties throws.
        if ($hook.tool_input.PSObject.Properties['file_path']) { $filePath    = [string]$hook.tool_input.file_path }
        if ($hook.tool_input.PSObject.Properties['command'])   { $commandText = [string]$hook.tool_input.command }

        # A partial read is not a read. The Read tool takes `limit` and `offset`, and a
        # call using either sees part of the file - exactly like `head -20`, which is not
        # a member of the set above. Both branches must mean the same thing by "read",
        # because the charter's own opening paragraph requires it be read in full.
        if ($hook.tool_input.PSObject.Properties['limit']  -and $null -ne $hook.tool_input.limit)  { $isPartialRead = $true }
        if ($hook.tool_input.PSObject.Properties['offset'] -and $null -ne $hook.tool_input.offset) { $isPartialRead = $true }
    }
    if ([string]::IsNullOrWhiteSpace($filePath) -and [string]::IsNullOrWhiteSpace($commandText)) { exit 0 }

    $markerDir = Join-Path (Join-Path $env:USERPROFILE '.keel') 'markers'
    $marker    = Join-Path $markerDir "charter-$sessionId.marker"

    # This gate's own charter, for the shell arming branch and for the refusal, which must
    # name it in full because a bare file name means nothing from another folder.
    # If this fails, the shell branch cannot arm and the refusal falls back to the bare name.
    $ownCharter   = ''
    $charterShown = 'DESIGN-CHARTER.md'
    try {
        $ownCharter   = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'DESIGN-CHARTER.md'))
        $charterShown = $ownCharter
    } catch { $ownCharter = '' }

    # --- does this call READ this repo's charter, in full?
    $readsCharter = $false

    # The Read tool, on THIS repo's charter, resolved rather than pattern-matched. A
    # suffix match such as `$filePath -match 'DESIGN-CHARTER\.md$'` would arm on
    # OLD-DESIGN-CHARTER.md and on any OTHER repo's charter.
    #
    # The path comes from this script's own location: the gate lives at
    # <repo>\scripts\keel-plugins-gate.ps1, so the parent of $PSScriptRoot is the repo
    # root. No env var and no hardcoded path, so a second clone resolves its own
    # charter and the scripts stay path-neutral.
    #
    # Only the Read tool arms. An Edit or Write whose target happens to be the charter
    # is not a read of it.
    if ($toolName -eq 'Read' -and -not $isPartialRead -and -not [string]::IsNullOrWhiteSpace($filePath)) {
        # This resolution gets its OWN try/catch. If a malformed path threw past here
        # into the outer catch, the gate would exit 0 having skipped the write scan
        # below - turning a bad path into a bypass.
        try {
            $charterPath   = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'DESIGN-CHARTER.md'))
            $candidatePath = [System.IO.Path]::GetFullPath($filePath)
            if ([string]::Equals($candidatePath, $charterPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $readsCharter = $true
            }
        } catch { $readsCharter = $false }
    }

    if (-not $readsCharter -and -not [string]::IsNullOrWhiteSpace($commandText)) {
        if ($CharterReadCommands -ccontains $commandText.Trim()) {
            # Its own try/catch, for the reason the Read branch gives: a malformed cwd that
            # threw into the outer catch would exit 0 having skipped the write scan below.
            try {
                $sessionDir = ''
                if ($hook.PSObject.Properties['cwd'] -and $hook.cwd -is [string]) { $sessionDir = $hook.cwd }
                # A drive letter AND a separator, or a UNC start. IsPathRooted is not enough:
                # it calls a bare 'C:' rooted, which then resolves against this process.
                if (-not [string]::IsNullOrWhiteSpace($ownCharter) -and
                    $sessionDir -match '^([A-Za-z]:[\\/]|[\\/][\\/])') {
                    $reachedPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($sessionDir, 'DESIGN-CHARTER.md'))
                    if ([string]::Equals($reachedPath, $ownCharter, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $readsCharter = $true
                    }
                }
            } catch { $readsCharter = $false }
        }
    }

    # --- does this call change something under plugins/ ?
    $touchesPlugins = $false
    $howDetected    = ''

    if (@('Edit', 'Write', 'MultiEdit', 'NotebookEdit') -contains $toolName) {
        if (($filePath -replace '/', '\') -match '\\plugins\\') {
            $touchesPlugins = $true
            $howDetected    = "$toolName on $filePath"
        }
    }

    if (-not $touchesPlugins -and -not [string]::IsNullOrWhiteSpace($commandText)) {
        foreach ($pattern in $WriteIntoPlugins) {
            if ($commandText -match $pattern) {
                $touchesPlugins = $true
                $howDetected    = "a shell command that writes under plugins/"
                break
            }
        }
    }

    # --- ORDER MATTERS: the write scan is honoured BEFORE arming.
    #
    # If a pattern-based arming test were checked first:
    #     awk /DESIGN-CHARTER.md/ README.md && rm -rf plugins/keel-workflow   -> exit 0, ARMED
    #     rm -rf plugins/keel-workflow                                        -> exit 2
    # The arm branch would write the marker and return before the write patterns were
    # consulted, so ONE command could arm the gate and write through it in the same
    # call. The canonical set above already makes that unreachable from the command
    # branch, because such a string is not equal to any member. This ordering is the
    # correctness argument, and it must not rest on a string comparison happening to be
    # strict. Belt and braces, deliberately.
    if ($touchesPlugins) {
        if (Test-Path -LiteralPath $marker) { exit 0 }

        [Console]::Error.WriteLine(@"
BLOCKED by keel's repo-local charter gate.

You are about to change plugins/** without having read DESIGN-CHARTER.md in this
session. Read it in full first - not summarised, not recalled from a previous
session. It is what stops plausible-but-wrong changes, and it only works before
the change is designed.

  Detected: $howDetected

  Read: $charterShown

If nothing in that command actually writes under plugins/ - the text is only QUOTED,
as in a keel-state.ps1 note whose -Detail repeats a write command - this refusal is
still deliberate, and rewording the note to get past it is the wrong answer, because
that edits the project's own evidence. Take this route instead:

  1. Write the prose to a file with the Write tool. A shell redirect cannot create
     that file: the printf or echo carrying the same text is refused here too.
  2. Pass the file in by command substitution: -Detail "`$(cat <file>)".

Through this hook the route delivers the file verbatim, backticks and both quote
characters included, at exit 0. The one byte it loses is the trailing newline,
which command substitution strips.

The Read tool arms the gate from any folder - that path, the whole file, with no
limit or offset, since a partial read is not a read.

A shell command arms it only if it runs in the folder holding that charter, and the
WHOLE command is exactly one of these five:

  cat DESIGN-CHARTER.md
  cat ./DESIGN-CHARTER.md
  Get-Content DESIGN-CHARTER.md
  Get-Content -Raw DESIGN-CHARTER.md
  type DESIGN-CHARTER.md

Nothing else arms it - not 'cd x && cat DESIGN-CHARTER.md', not a quoted filename,
not head, tail, sed, more, gc or a grep, and not a redirect appended to
one of the five above. That is deliberate rather than an oversight: a gate
that infers "was this file read?" from the shape of the command text can be
made to answer yes in more than one way, each of them without the charter
ever entering the session. Exact equality leaves no room in the string for
anything else: the command either is one of the five or it is not.

Then answer the questions at the end of it in writing, and make the change.
"@)
        exit 2
    }

    if ($readsCharter) {
        if (-not (Test-Path -LiteralPath $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
        Set-Content -LiteralPath $marker -Value ((Get-Date).ToString('s')) -Encoding ASCII
        exit 0
    }

    exit 0
}
catch { exit 0 }
