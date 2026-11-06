<#
    keel-release.ps1 - cuts a keel release: moves the 'release' branch to main and tags it.

    Users and work machines install keel from the 'release' branch, so that branch moves only
    when a release is cut, and each release is also tagged v<version>, the version being the
    marketplace manifest's own. Development stays on main. Moving a branch other people update
    from is an outward act, so this previews by default and changes a ref only with -Apply.

    It works on the repo the shell is standing in (git rev-parse --show-toplevel), not on the
    folder this file is stored in. Run it from the repo root as
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/keel-release.ps1 [-Apply]
    or, to release from another clone of keel, cd into that clone and pass this file's path.

    It refuses, before any ref changes, each with its own message and exit code:
      9  not inside a git repo whose top level holds keel's .claude-plugin/marketplace.json,
         or that manifest's version is not N.N.N
      2  the working tree is not clean (untracked files included)
      3  the current branch is not main (a detached HEAD included)
      4  the remote's main could not be read, or is not this HEAD. The remote is read live
         with git ls-remote; the local origin/main is a cache and is never consulted.
      5  the tag v<version> already exists, here or on the remote
      7  the remote's release branch is not an ancestor of HEAD, so it would not fast-forward
      6  scripts/check-suite-docs.ps1 -Strict failed (run last, because it is the slow one)
    With -Apply, after every check passes:
      8  the push failed. Nothing was created locally before it, so nothing is left behind.
    0 is a clean preview, or a release that landed.

    -Apply pushes the branch and the tag in ONE atomic push, as HEAD:refs/heads/release and
    HEAD:refs/tags/v<version>. That makes a lightweight tag, so git ls-remote prints the commit's
    own sha for it, the same as for main and release; an annotated tag would print the tag
    object's sha instead. No local ref is made before the push, so a run killed mid-push leaves
    nothing here, and a retry after a push that did land is refused at 5 by the remote tag. The
    pre-push hook, where one is active, runs -Strict again on that push.

    Windows PowerShell 5.1 compatible. ASCII only.
#>

param([switch]$Apply)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Stop-Release([int]$Code, [string]$Message) {
    # Write-Error under Stop would throw before exit and turn every refusal into exit 1.
    [Console]::Error.WriteLine("keel-release: REFUSED - $Message")
    exit $Code
}

# Every git call goes through here. Its exit code lands in $script:GitExit, and stderr is left
# to reach the console on its own: redirecting a native tool's stderr under Stop turns its
# progress lines into terminating errors.
$script:GitExit = 0
function Invoke-Git {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = @(& git @args)
        $script:GitExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $saved
    }
    return $out
}

# --- 9: which repo, and which version ---------------------------------------------------------

$topLines = @(Invoke-Git rev-parse --show-toplevel)
if ($script:GitExit -ne 0 -or $topLines.Count -eq 0) {
    Stop-Release 9 'not inside a git repo. cd into a keel clone first.'
}
$top = ($topLines[0]).Trim()
$manifestPath = Join-Path $top '.claude-plugin\marketplace.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Stop-Release 9 "no .claude-plugin\marketplace.json at the top of $top, so this is not a keel repo."
}
# An empty file parses to $null without throwing, so the null check is not redundant.
try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { $manifest = $null }
if ($null -eq $manifest -or $null -eq $manifest.PSObject.Properties['name'] -or
    $null -eq $manifest.PSObject.Properties['version']) {
    Stop-Release 9 "$manifestPath is empty or unreadable, or has no name or version."
}
if ([string]$manifest.name -ne 'keel') {
    Stop-Release 9 "the marketplace at $top is named '$($manifest.name)', not 'keel'."
}
$version = [string]$manifest.version
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    Stop-Release 9 "the marketplace version '$version' is not of the form N.N.N."
}
$tag = "v$version"
Set-Location -LiteralPath $top

# --- 2: a clean tree --------------------------------------------------------------------------

$dirty = @(Invoke-Git status --porcelain)
if ($script:GitExit -ne 0) { Stop-Release 2 'git status failed, so whether the tree is clean is unknown.' }
if ($dirty.Count -gt 0) {
    Stop-Release 2 ("the working tree is not clean ({0} path(s) changed or untracked). Commit or remove them first." -f $dirty.Count)
}

# --- 3: on main -------------------------------------------------------------------------------

$branchLines = @(Invoke-Git symbolic-ref --short -q HEAD)
$branch = ''
if ($script:GitExit -eq 0 -and $branchLines.Count -gt 0) { $branch = ($branchLines[0]).Trim() }
if ($branch -ne 'main') {
    if ($branch -eq '') { $branch = '(detached HEAD)' }
    Stop-Release 3 "the current branch is $branch. A release is cut from main only."
}

$headLines = @(Invoke-Git rev-parse HEAD)
if ($script:GitExit -ne 0 -or $headLines.Count -eq 0) { Stop-Release 3 'HEAD could not be read.' }
$head = ($headLines[0]).Trim()

# --- 4: main is on the remote, read live ------------------------------------------------------

$remoteMain = @(Invoke-Git ls-remote origin refs/heads/main)
if ($script:GitExit -ne 0) {
    Stop-Release 4 "the remote 'origin' could not be read (git ls-remote exit $($script:GitExit)), so whether main is pushed is unknown."
}
$remoteMainSha = ''
if ($remoteMain.Count -gt 0) { $remoteMainSha = (($remoteMain[0]) -split '\s+')[0] }
if ($remoteMainSha -ne $head) {
    if ($remoteMainSha -eq '') { $remoteMainSha = '(no main on the remote)' }
    Stop-Release 4 "main is not pushed: HEAD is $head, the remote's main is $remoteMainSha. Push main first."
}

# --- 5: the tag is new, here and there --------------------------------------------------------

$localTag = @(Invoke-Git tag -l $tag)
if ($script:GitExit -ne 0) { Stop-Release 5 'git tag -l failed, so whether the tag exists is unknown.' }
if ($localTag.Count -gt 0) {
    Stop-Release 5 "the tag $tag already exists in this clone. Bump the marketplace version for a new release."
}
$remoteTag = @(Invoke-Git ls-remote origin "refs/tags/$tag")
if ($script:GitExit -ne 0) { Stop-Release 5 "the remote's tags could not be read, so whether $tag exists is unknown." }
if ($remoteTag.Count -gt 0) {
    Stop-Release 5 "the tag $tag already exists on the remote: that version is already released. Bump the marketplace version for a new release."
}

# --- 7: release would fast-forward ------------------------------------------------------------

$remoteRelease = @(Invoke-Git ls-remote origin refs/heads/release)
if ($script:GitExit -ne 0) { Stop-Release 7 "the remote's release branch could not be read." }
$releaseFrom = ''
if ($remoteRelease.Count -gt 0) {
    $releaseFrom = (($remoteRelease[0]) -split '\s+')[0]
    $null = Invoke-Git merge-base --is-ancestor $releaseFrom $head
    if ($script:GitExit -ne 0) {
        Stop-Release 7 "the remote's release is at $releaseFrom, which is not an ancestor of HEAD $head (or is not in this clone). It would not fast-forward."
    }
}

# --- 6: the full validator --------------------------------------------------------------------

$checker = Join-Path $top 'scripts\check-suite-docs.ps1'
if (-not (Test-Path -LiteralPath $checker)) { Stop-Release 6 "no validator at $checker." }
Write-Output "keel-release: running check-suite-docs.ps1 -Strict (several minutes) ..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $checker -Strict | Out-Host
$strictExit = $LASTEXITCODE
if ($strictExit -ne 0) {
    Stop-Release 6 "check-suite-docs.ps1 -Strict exited $strictExit. Fix what it names before releasing."
}

# --- preview, then the release ----------------------------------------------------------------

$subjectLines = @(Invoke-Git log -1 --format=%s HEAD)
$subject = ''
if ($subjectLines.Count -gt 0) { $subject = $subjectLines[0] }
$moveText = 'created'
if ($releaseFrom -ne '') { $moveText = "moved from $releaseFrom" }
$pushArgs = @('push', '--atomic', 'origin', 'HEAD:refs/heads/release', "HEAD:refs/tags/$tag")

Write-Output ''
Write-Output "keel-release: version  $version"
Write-Output "keel-release: tag      $tag"
Write-Output "keel-release: commit   $head  $subject"
Write-Output "keel-release: release  $moveText to $head"
Write-Output ("keel-release: push     git {0}" -f ($pushArgs -join ' '))

if (-not $Apply) {
    Write-Output ''
    Write-Output 'keel-release: PREVIEW only - no ref was changed. Run again with -Apply to release.'
    exit 0
}

# The push is called directly rather than through Invoke-Git, so that its output, and the pre-push
# hook's where one runs, reaches the console line by line instead of being collected and dropped:
# a hook that refuses has to be read.
$savedPref = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & git @pushArgs | Out-Host
    $script:GitExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $savedPref
}
if ($script:GitExit -ne 0) {
    Stop-Release 8 "git push exited $($script:GitExit). Check the remote with: git ls-remote origin refs/heads/release refs/tags/$tag"
}

# The remote now holds the tag; make the matching local one so this clone agrees.
$null = Invoke-Git tag $tag $head

Write-Output ''
Write-Output 'keel-release: RELEASED. The remote now reads:'
$after = @(Invoke-Git ls-remote origin refs/heads/main refs/heads/release "refs/tags/$tag")
foreach ($line in $after) { Write-Output "  $line" }
exit 0
