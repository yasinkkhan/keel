<#
    gen-suite-docs.ps1 - rebuilds every generated block in this repo's docs.

    Charter P11: anything generated has a gen-* that rebuilds it and a check-* that
    detects drift, and is never hand-edited. This is the gen half.

    Windows PowerShell 5.1 compatible. ASCII only.

      -Write   write the files. Without it, prints what would change and exits 1 on drift.
#>

param([switch]$Write)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$PluginsDir = Join-Path $RepoRoot 'plugins'
$ReadmePath = Join-Path $RepoRoot 'README.md'
$ArchPath   = Join-Path $RepoRoot 'ARCHITECTURE.html'

$BeginMark = '<!-- BEGIN GENERATED INVENTORY -->'
$EndMark   = '<!-- END GENERATED INVENTORY -->'
$HtmlBegin = '<!-- BEGIN GENERATED HTML INVENTORY -->'
$HtmlEnd   = '<!-- END GENERATED HTML INVENTORY -->'

function Get-PluginInventory {
    $rows = @()
    foreach ($d in @(Get-ChildItem -LiteralPath $PluginsDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $manifest = Join-Path $d.FullName '.claude-plugin\plugin.json'
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        # A malformed manifest must produce a visible row, not a crash inside the
        # checker that invokes this script. An EMPTY file does not throw here - it
        # parses to $null - so the null check is not redundant with the catch. A
        # truncated manifest is exactly what a botched edit leaves behind.
        try { $m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $m = $null }
        if ($null -eq $m -or $null -eq $m.PSObject.Properties['name']) {
            $rows += ("| ``{0}`` | INVALID MANIFEST | _empty or unreadable_ |" -f $d.Name)
            continue
        }

        $skillsDir = Join-Path $d.FullName 'skills'
        $skills = @()
        if (Test-Path -LiteralPath $skillsDir) {
            $skills = @(Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction SilentlyContinue |
                        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
                        ForEach-Object { $_.Name } | Sort-Object)
        }
        $skillText = if ($skills.Count -eq 0) { '_none yet_' } else { ($skills | ForEach-Object { "``$_``" }) -join ', ' }

        $rows += ("| ``{0}`` | {1} | {2} |" -f $m.name, $m.version, $skillText)
    }
    return @($rows)
}

function Build-InventoryBlock {
    $lines = @()
    $lines += $BeginMark
    $lines += '| Plugin | Version | Skills |'
    $lines += '|---|---|---|'
    $lines += (Get-PluginInventory)
    $lines += $EndMark
    return ($lines -join "`n")
}

# NOTE: this sets a script-scope flag instead of RETURNING one. A PowerShell function
# returns everything it emits, so a function that both Write-Outputs a message and
# returns $false hands back a two-element array - which is truthy. A caller reading
# that would report permanent inventory drift against a file that is already correct.
$script:Drift = $false

function Build-InventoryHtml {
    $rows = @()
    $rows += '  <div class="scroll">'
    $rows += '  <table>'
    $rows += '    <thead><tr><th>Plugin</th><th>Version</th><th>Skills</th></tr></thead>'
    $rows += '    <tbody>'
    foreach ($d in @(Get-ChildItem -LiteralPath $PluginsDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $manifest = Join-Path $d.FullName '.claude-plugin\plugin.json'
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        try { $m = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $m = $null }
        if ($null -eq $m -or $null -eq $m.PSObject.Properties['name']) {
            $rows += ('      <tr><td><code>{0}</code></td><td>INVALID MANIFEST</td><td><em>empty or unreadable</em></td></tr>' -f $d.Name)
            continue
        }
        $skillsDir = Join-Path $d.FullName 'skills'
        $skills = @()
        if (Test-Path -LiteralPath $skillsDir) {
            $skills = @(Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction SilentlyContinue |
                        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
                        ForEach-Object { $_.Name } | Sort-Object)
        }
        $skillText = if ($skills.Count -eq 0) { '<em>none yet</em>' } else { ($skills | ForEach-Object { "<code>$_</code>" }) -join ', ' }
        $rows += ('      <tr><td><code>{0}</code></td><td>{1}</td><td>{2}</td></tr>' -f $m.name, $m.version, $skillText)
    }
    $rows += '    </tbody>'
    $rows += '  </table>'
    $rows += '  </div>'
    return ($HtmlBegin + "`n" + ($rows -join "`n") + "`n  " + $HtmlEnd)
}

function Update-Marked {
    param([string]$FilePath, [string]$NewBlock, [string]$Begin = $BeginMark, [string]$End = $EndMark)

    $leaf = Split-Path -Leaf $FilePath

    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-Output "SKIP  $leaf does not exist yet."
        return
    }
    $content = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    $bi = $content.IndexOf($Begin)
    $ei = $content.IndexOf($End)
    if ($bi -lt 0 -or $ei -lt 0) {
        Write-Output "SKIP  $leaf has no generated-inventory markers."
        return
    }
    $before  = $content.Substring(0, $bi)
    $after   = $content.Substring($ei + $End.Length)
    $updated = $before + $NewBlock + $after

    if ($updated -eq $content) {
        Write-Output "OK    $leaf inventory is current."
        return
    }
    if ($Write) {
        # Keep the byte-order mark as the file had it. Set-Content -Encoding UTF8 adds one
        # under Windows PowerShell 5.1, which put an unexplained change on line 1 of a file
        # that had none. A file that has one keeps it: ARCHITECTURE.html declares no charset,
        # so the mark is what tells a browser it is UTF-8.
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $keepBom = ($fileBytes.Length -ge 3 -and $fileBytes[0] -eq 0xEF -and $fileBytes[1] -eq 0xBB -and $fileBytes[2] -eq 0xBF)
        [System.IO.File]::WriteAllText($FilePath, $updated, (New-Object System.Text.UTF8Encoding($keepBom)))
        Write-Output "WROTE $leaf inventory."
        return
    }
    Write-Output "DRIFT $leaf inventory is stale. Run: powershell -File scripts/gen-suite-docs.ps1 -Write"
    $script:Drift = $true
}

Update-Marked -FilePath $ReadmePath -NewBlock (Build-InventoryBlock)
Update-Marked -FilePath $ArchPath   -NewBlock (Build-InventoryHtml) -Begin $HtmlBegin -End $HtmlEnd

if ($script:Drift -and -not $Write) { exit 1 }
exit 0
