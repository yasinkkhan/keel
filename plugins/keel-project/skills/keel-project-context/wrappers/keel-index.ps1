<#
    keel-index.ps1 - generates and drift-checks a keel project's document index.

    This is the retrieval layer. A keel project accumulates documentation as it runs -
    the charter, epic ledgers, workstream specs, delivery records, and whatever
    close-out routed into reference/. This script makes that findable by a future
    session without reading everything.

    Charter contracts:
      P8   anchors, never line numbers - the index stores HEADINGS, which survive edits
      P9   slow knowledge in files, fast knowledge from disk - the index is regenerated,
           never trusted stale
      P11  a generated artifact must be mechanically checkable, or it does not ship -
           hence the inputs hash and the nonzero exit on drift
      P20  the project is derived from the working directory, never stored
      P23  private/ and repos/ are never indexed; quarantine is never touched, and a
           project with quarantine on may not declare a docs root at all - see below
      P24  contracts widen, they do not tighten - a project that declares no docs root
           indexes exactly what it always did

    The optional docs root
      A project MAY declare one extra indexed tree in its keel.json:

          "docs": "docs"

      a path relative to the project root, so a project can name the folder whatever it
      likes. ABSENT MEANS NO DOC SET, and absent is the default. Files under it classify
      as kind 'docs'.

      A declared root is validated rather than trusted, because Get-Docs skips a root it
      cannot find in total silence - so an unvalidated typo would index nothing and report
      success. The value is RESOLVED to a real directory and the placement guards run against
      the CANONICAL relative path rather than the string as written: './plan' and 'plan.' are
      not the string 'plan' and both resolve to it. Two checks necessarily precede resolution
      and run on the raw value - the type check and IsPathRooted.

      Refused at exit 90, every site in Resolve-DocsRoot:
        - keel.json does not parse as JSON
        - 'docs' is present but is not a string
        - the value is an absolute path
        - it does not exist
        - it names a file rather than a directory
        - it is a junction, symlink or other reparse point
        - it resolves to the project root itself
        - it resolves outside the project
        - it resolves to or inside CHARTER.md, plan, record or reference, which would index
          every file under it twice
        - it resolves to or inside an $ExcludedDirs folder such as private or repos, which
          would index nothing
        - the project declares "quarantine": true

    Windows PowerShell 5.1 compatible. ASCII only.

      -Path <dir>   start the project walk here (default: current directory)
      -Write        rebuild reference/INDEX.md
      -Json         emit the index as JSON instead of writing
      (no flag)     CHECK only: exit 1 if the index is stale or missing

    Exit codes
      0   index is current (or was written)
      1   index is stale or missing - rebuild with -Write
      90  the declared docs root is invalid, or keel.json is unparseable
      91  no keel project resolved from -Path
#>

param(
    [string]$Path,
    [switch]$Write,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$BeginMark = '<!-- BEGIN GENERATED INDEX -->'
$EndMark   = '<!-- END GENERATED INDEX -->'
$HashMark  = 'Inputs hash:'

# Only these trees are documentation. repos/ is code, private/ is untracked scratch,
# and the quarantine does not live in the project folder at all.
#
# These four are ALWAYS indexed. A project may declare one more - a docs root - in its
# keel.json, which is why the effective root list is computed per project in main rather
# than being a constant. A project that declares nothing indexes exactly these four,
# byte for byte as it always did (charter P24).
#
# 'record' is in this list and STAYS. No keel verb writes there, but projects measured
# keep documents in the record folder - some named W<n>.<p>-delivery.md - and their
# indexes already render a '## record' section. Removing the root would de-index live
# documents in in-flight projects.
$BaseRoots    = @('CHARTER.md', 'plan', 'record', 'reference')
$ExcludedDirs = @('private', 'repos', '.git', 'node_modules')

# --------------------------------------------------------------------- helpers --

function Fail {
    param([int]$Code, [string]$Message)
    [Console]::Error.WriteLine("KEEL-INDEX: $Message")
    exit $Code
}

function Say { param([string]$Message) Write-Output "KEEL-INDEX: $Message" }

function Resolve-Project {
    param([string]$StartPath)
    $dir = $StartPath
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $dir)) { Fail 91 "-Path '$dir' does not exist." }
    $dir = (Resolve-Path -LiteralPath $dir).Path
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $dir 'keel.json')) {
            return [pscustomobject]@{ Slug = (Split-Path -Leaf $dir); Root = $dir }
        }
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { return $null }
        $dir = $parent
    }
}

# Reads the project's OPTIONAL 'docs' key and returns it as a forward-slashed relative
# path, or $null when the project declares none. Absent is the case for every project
# that predates this key and it must stay free (charter P24).
#
# Every refusal here is exit 90 - the suite-wide "bad argument, invalid id, or something
# immutable" code from keel's exit-code contract, not a new code invented for this.
# A declared root that does not resolve MUST be loud, because Get-Docs skips a missing
# root in total silence: a project with no record folder still reports its other documents
# at exit 0 without a murmur. A typo would index nothing and pass.
#
# Locals are Dr-prefixed because $docs is a live local in main and PowerShell variable
# names are case-insensitive.
function Resolve-DocsRoot {
    param([string]$DrRoot)

    $drCfgPath = Join-Path $DrRoot 'keel.json'
    if (-not (Test-Path -LiteralPath $drCfgPath)) { return $null }

    $drRaw = Get-Content -LiteralPath $drCfgPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($drRaw)) { return $null }

    $drCfg = $null
    try { $drCfg = $drRaw | ConvertFrom-Json }
    catch { Fail 90 "keel.json is not valid JSON: $($_.Exception.Message)" }
    # An empty or whitespace file parses to $null WITHOUT throwing, so the catch above is
    # not enough on its own - the crash would land later, on the first property access.
    if ($null -eq $drCfg) { return $null }

    # .PSObject.Properties.Name throws under Set-StrictMode when the object has no
    # properties at all, so index the collection instead.
    $drProp = $drCfg.PSObject.Properties['docs']
    if ($null -eq $drProp -or $null -eq $drProp.Value) { return $null }
    if ($drProp.Value -isnot [string]) {
        Fail 90 "keel.json 'docs' must be a path string relative to the project root."
    }

    $drNorm = ("$($drProp.Value)" -replace '\\', '/').Trim().TrimEnd('/')
    if ($drNorm -eq '') { return $null }

    if ([System.IO.Path]::IsPathRooted($drNorm)) {
        Fail 90 "keel.json 'docs' must be a relative path INSIDE the project. Got '$($drProp.Value)'."
    }

    # The declared string is NOT trusted for comparison, because comparing strings is what
    # lets an alias through. Measured: with the guards run against the
    # trimmed string alone, './plan' and 'plan.' both cleared the always-indexed-root check
    # and then resolved to plan/ anyway, indexing every file under it TWICE - the precise
    # duplicate the check's own error message names. Resolve to a real directory first and
    # compare the canonical relative path.
    $drFull = Join-Path $DrRoot $drNorm
    if (-not (Test-Path -LiteralPath $drFull)) {
        Fail 90 "keel.json 'docs' names '$drNorm', which does not exist. A declared docs root that does not resolve would index nothing and report success."
    }
    $drItem = Get-Item -LiteralPath $drFull
    if ($drItem -isnot [System.IO.DirectoryInfo]) {
        Fail 90 "keel.json 'docs' names '$drNorm', which is a file. It must be a directory."
    }

    # A junction or symlink defeats every path comparison below it, because .FullName for a
    # reparse point is the LINK's path and not the target's - so the inside-the-project check
    # passes and Get-ChildItem -Recurse then walks straight through to wherever it points.
    # Measured, and creatable by an ordinary user with no admin
    # rights: a junction to a directory outside the project indexed a file living outside it,
    # writing that file's title and headings into reference/INDEX.md inside the repo (charter
    # P23 reached by a different door); and a junction to plan/ reproduced the double-index the
    # canonical-path check closes against string aliases. Refusing the reparse point
    # outright closes both without this script having to resolve link targets.
    if ($drItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Fail 90 "keel.json 'docs' names '$drNorm', which is a junction, symlink or other reparse point. Point it at a real directory inside the project."
    }

    $drRootFull = (Get-Item -LiteralPath $DrRoot).FullName.TrimEnd('\', '/')
    $drSep      = [System.IO.Path]::DirectorySeparatorChar
    if ($drItem.FullName.TrimEnd('\', '/') -eq $drRootFull) {
        Fail 90 "keel.json 'docs' resolves to the project root itself. Every document would be indexed twice. Name a folder inside it."
    }
    if (-not $drItem.FullName.StartsWith("$drRootFull$drSep", [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail 90 "keel.json 'docs' resolves to '$($drItem.FullName)', which is outside the project at '$drRootFull'."
    }
    $drRel = $drItem.FullName.Substring($drRootFull.Length + 1) -replace '\\', '/'

    foreach ($drBase in $BaseRoots) {
        if ($drRel -eq $drBase -or $drRel -like "$drBase/*") {
            Fail 90 "keel.json 'docs' resolves to '$drRel', which is or sits inside the always-indexed root '$drBase'. Every file under it would be indexed twice. Choose a folder outside it."
        }
    }

    # Get-Docs skips these on every path it walks, so a docs root at or inside one resolves,
    # passes the existence check, and then yields nothing - index-nothing-and-report-success,
    # which is exactly what the existence check above exists to prevent. Measured for
    # 'private' and 'repos', the two folders charter P23 names.
    foreach ($drSeg in $drRel.Split('/')) {
        if ($ExcludedDirs -contains $drSeg) {
            Fail 90 "keel.json 'docs' resolves to '$drRel', which is or sits inside the never-indexed folder '$drSeg'. It would index nothing and report success."
        }
    }

    # A docs page is prose ABOUT the project, and indexing it writes every page title and
    # every H2/H3 heading into reference/INDEX.md - which lives INSIDE the repo. Get-HandoffDir
    # redirects its write out of the tree for a quarantined project, but that precedent does
    # not transfer: here the leak is the index, not the folder, so redirecting the folder and
    # still indexing its headings would satisfy the letter of the precedent and violate
    # charter P23 exactly. Refuse at the point of declaration instead of at a commit.
    $drQ = $drCfg.PSObject.Properties['quarantine']
    if ($null -ne $drQ -and [bool]$drQ.Value) {
        Fail 90 "keel.json declares a 'docs' root and 'quarantine': true. Refused - the index writes every page title and heading into reference/INDEX.md, which is inside the repo (charter P23)."
    }

    # The CANONICAL relative path, not the declared string. Get-DocKind matches against the
    # relative paths Get-Docs produces, so returning the declared form would misclassify
    # every file under an aliased root as 'other'.
    return $drRel
}

function Get-DocKind {
    param([string]$Rel, [string]$DocsRoot)
    $r = $Rel -replace '\\', '/'
    if ($r -eq 'CHARTER.md')            { return 'charter' }
    # Before the plan/* arms deliberately: a declared docs root wins over the general
    # plan/* generalisation, the same way plan/epics/* already wins over it.
    #
    # StartsWith and NOT -like: the docs root is a real directory name chosen by the operator,
    # so it can legally contain the wildcard characters -like would interpret. Measured: a
    # directory genuinely named 'd[o]cs' was indexed but
    # rendered under '## other', because -like read '[o]' as a character class. Every other
    # arm here matches a literal keel-owned prefix, so this is the only one that can be fed
    # an operator-chosen string.
    if ($DocsRoot -and $r.StartsWith("$DocsRoot/", [System.StringComparison]::OrdinalIgnoreCase)) { return 'docs' }
    if ($r -like 'plan/epics/*')        { return 'epic' }
    if ($r -like 'plan/workstreams/*')  { return 'spec' }
    if ($r -like 'plan/prompts/*')      { return 'prompt' }
    if ($r -like 'plan/*')              { return 'plan' }
    if ($r -like 'record/*')            { return 'record' }
    if ($r -like 'reference/*')         { return 'reference' }
    return 'other'
}

function Get-Docs {
    param([string]$Root, [string[]]$IdxRoots)
    $out = @()
    foreach ($entry in $IdxRoots) {
        $full = Join-Path $Root $entry
        if (-not (Test-Path -LiteralPath $full)) { continue }
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $out += (Get-Item -LiteralPath $full)
            continue
        }
        foreach ($f in @(Get-ChildItem -LiteralPath $full -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)) {
            $rel = $f.FullName.Substring($Root.Length + 1) -replace '\\', '/'
            $skip = $false
            foreach ($x in $ExcludedDirs) { if ($rel -like "$x/*" -or $rel -like "*/$x/*") { $skip = $true } }
            if ($rel -eq 'reference/INDEX.md') { $skip = $true }   # never index the index
            if (-not $skip) { $out += $f }
        }
    }
    return @($out | Sort-Object -Property FullName)
}

function Get-DocFacts {
    param([System.IO.FileInfo]$File, [string]$Root, [string]$DocsRoot)

    $rel   = $File.FullName.Substring($Root.Length + 1) -replace '\\', '/'
    $lines = @(Get-Content -LiteralPath $File.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)

    $title = ''
    $headings = @()
    $inFence = $false
    foreach ($ln in $lines) {
        if ($ln -match '^\s*```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        if ($ln -match '^#\s+(.+?)\s*$')      { if (-not $title) { $title = $Matches[1] }; continue }
        if ($ln -match '^#{2,3}\s+(.+?)\s*$') { $headings += $Matches[1] }
    }
    if (-not $title) { $title = [System.IO.Path]::GetFileNameWithoutExtension($File.Name) }

    $hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.Substring(0, 12).ToLower()

    return [pscustomobject]@{
        rel      = $rel
        kind     = (Get-DocKind -Rel $rel -DocsRoot $DocsRoot)
        title    = $title
        headings = @($headings)
        bytes    = $File.Length
        hash     = $hash
        modified = $File.LastWriteTime.ToString('yyyy-MM-dd')
    }
}

function Get-InputsHash {
    param($Facts)
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in @($Facts | Sort-Object -Property rel)) {
        [void]$sb.Append($f.rel); [void]$sb.Append(':'); [void]$sb.Append($f.hash); [void]$sb.Append("`n")
    }
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $sha    = [System.Security.Cryptography.SHA256]::Create()
    $digest = $sha.ComputeHash($bytes)
    $sha.Dispose()
    return (($digest | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16)
}

function Build-IndexBody {
    param($Facts, [string]$Slug, [string]$InputsHash)

    $out = @()
    $out += "# Document index - $Slug"
    $out += ''
    # No runnable command here: the path to this script differs between a clone and an installed
    # copy, and this text is written into every project's tracked index.
    $out += '**GENERATED. Do not hand-edit** (charter P11). Rebuild it from the project folder with the'
    $out += 'command under "Rebuilding the index" in the keel-project-context skill, which gives the path'
    $out += 'to keel-index.ps1 for the copy of keel installed on this machine.'
    $out += ''
    $out += "$HashMark $InputsHash"
    $out += ''
    $out += 'Headings are ANCHORS, not line numbers, so they survive edits above them (charter P8).'
    $out += 'This index says what EXISTS and where. It never says what is currently TRUE - for that,'
    $out += 'read the document, or measure with keel-state.ps1.'
    $out += ''
    $out += $BeginMark

    $byKind = @{}
    foreach ($f in $Facts) {
        if (-not $byKind.ContainsKey($f.kind)) { $byKind[$f.kind] = @() }
        $byKind[$f.kind] += $f
    }
    # 'docs' sits second, right after the charter: the charter records what was DECIDED and
    # a docs page records what the project currently IS, and both orient a reader before the
    # phase-by-phase material does. A kind missing from this list is still counted in
    # $facts.Count and still folded into the inputs hash, but never rendered - counted and
    # invisible, which is the wrong-result-that-raises-nothing family.
    foreach ($kind in @('charter', 'docs', 'epic', 'spec', 'prompt', 'plan', 'record', 'reference', 'other')) {
        if (-not $byKind.ContainsKey($kind)) { continue }
        $out += ''
        $out += "## $kind"
        foreach ($f in @($byKind[$kind] | Sort-Object -Property rel)) {
            $out += ''
            $out += "### ``$($f.rel)``"
            $out += "$($f.title)  ($($f.bytes) bytes, modified $($f.modified), sha $($f.hash))"
            if ($f.headings.Count -gt 0) {
                foreach ($h in $f.headings) { $out += "- $h" }
            }
            else { $out += '- _(no sub-headings)_' }
        }
    }
    $out += ''
    $out += $EndMark
    return ($out -join "`n")
}

# ------------------------------------------------------------------------ main --

$proj = Resolve-Project -StartPath $Path
if ($null -eq $proj) {
    Fail 91 "No keel project found by walking up from '$(if ($Path) { $Path } else { (Get-Location).Path })'."
}

# Named $docsRoot and NOT $docs: $docs is taken two lines down, and PowerShell variable
# names are case-insensitive.
$docsRoot = Resolve-DocsRoot -DrRoot $proj.Root
$idxRoots = @($BaseRoots)
if ($docsRoot) { $idxRoots = @($BaseRoots + $docsRoot) }

$docs  = @(Get-Docs -Root $proj.Root -IdxRoots $idxRoots)
$facts = @()
foreach ($d in $docs) { $facts += (Get-DocFacts -File $d -Root $proj.Root -DocsRoot $docsRoot) }
$inputsHash = Get-InputsHash $facts

if ($Json) {
    [pscustomobject]@{ project = $proj.Slug; inputsHash = $inputsHash; documents = $facts } | ConvertTo-Json -Depth 8
    exit 0
}

$indexPath = Join-Path (Join-Path $proj.Root 'reference') 'INDEX.md'
$body      = Build-IndexBody -Facts $facts -Slug $proj.Slug -InputsHash $inputsHash

if ($Write) {
    $refDir = Split-Path -Parent $indexPath
    if (-not (Test-Path -LiteralPath $refDir)) { New-Item -ItemType Directory -Path $refDir -Force | Out-Null }
    # Build-IndexBody joins with LF, and Set-Content appends the PLATFORM terminator - CRLF
    # on Windows PowerShell 5.1 - so the sentinel it adds itself would be the one CRLF line
    # in a body that is LF by construction. The terminator is part of the payload, decided
    # here instead of by the host. Same repair and the same reasons as Write-Json in
    # keel-state.ps1 - they are written there, not restated here (charter P10).
    #
    # [IO.File] is NOT provider-aware: it resolves a relative path against the .NET current
    # directory, which is not PowerShell's location. Set-Content is, so this resolution is
    # part of not using it: with the location pushed elsewhere, the two diverge.
    # Resolve-Project already returns an absolute path, so this guards a path that does not
    # currently exist rather than repairing a live one.
    #
    # UTF8Encoding($true) emits the same BOM Set-Content -Encoding UTF8 does, so the only
    # byte this differs in from a Set-Content write is the stray CR.
    $idxFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($indexPath)
    $idxEncoder  = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($idxFullPath, ($body + "`n"), $idxEncoder)
    Say "Wrote $($facts.Count) document(s) to reference/INDEX.md  (inputs hash $inputsHash)"
    exit 0
}

# ---- check only
if (-not (Test-Path -LiteralPath $indexPath)) {
    Say "reference/INDEX.md does not exist. $($facts.Count) document(s) are unindexed."
    Say 'Rebuild with -Write.'
    exit 1
}

$existing = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8
$recorded = ''
if ($existing -match "$([regex]::Escape($HashMark))\s*([0-9a-f]{16})") { $recorded = $Matches[1] }

if ($recorded -ne $inputsHash) {
    Say "INDEX.md is STALE. Recorded inputs hash '$recorded', actual '$inputsHash'."
    Say "$($facts.Count) document(s) on disk. Rebuild with -Write before relying on the index."
    exit 1
}
Say "INDEX.md is current ($($facts.Count) documents, inputs hash $inputsHash)."
exit 0
