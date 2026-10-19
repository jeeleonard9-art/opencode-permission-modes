#Requires -Version 5.1
<#
.SYNOPSIS
    Install OpenCode Permission Modes (read-only / auto-edit / full-auto).

.DESCRIPTION
    Copies agent/*.md into the OpenCode config directory. Files that differ from
    the ones shipped here are backed up to *.bak first; files that are byte
    identical are left alone.

    If the config directory has no opencode.json / opencode.jsonc, an example
    config is created. An existing config is never overwritten.

    A small manifest (.opencode-permission-modes.manifest) records what was
    installed and which backup belongs to which file, so uninstall.ps1 can put
    your original files back.

.PARAMETER ConfigDir
    Config directory. Defaults to ~/.config/opencode

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -ConfigDir "D:\my-opencode"
#>
[CmdletBinding()]
param(
    [string]$ConfigDir = (Join-Path $HOME ".config\opencode")
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcAgent = Join-Path $repoRoot "agent"
$dstAgent = Join-Path $ConfigDir "agent"
$manifestPath = Join-Path $ConfigDir ".opencode-permission-modes.manifest"

if (-not (Test-Path $srcAgent)) {
    throw "Cannot find the agent directory: $srcAgent (run this script from the repo root)"
}

Write-Host ""
Write-Host "OpenCode Permission Modes"
Write-Host "Config directory: $ConfigDir"
Write-Host ""

New-Item -ItemType Directory -Path $dstAgent -Force | Out-Null

# Previous install: agent file -> backup file (kept across reinstalls).
$prior = @{}
if (Test-Path $manifestPath) {
    foreach ($line in Get-Content $manifestPath) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2) { $prior[$parts[0].Trim()] = $parts[1].Trim() }
    }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$installed = 0
$unchanged = 0
$entries = New-Object System.Collections.Generic.List[string]

foreach ($f in Get-ChildItem $srcAgent -Filter *.md | Sort-Object Name) {
    $dst = Join-Path $dstAgent $f.Name
    $backup = ""

    if (Test-Path $dst) {
        $sameHash = (Get-FileHash $dst -Algorithm SHA256).Hash -eq (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        if ($sameHash) {
            if ($prior.ContainsKey($f.Name)) { $backup = $prior[$f.Name] }
            $entries.Add($f.Name + "`t" + $backup)
            Write-Host ("  unchanged " + $f.Name)
            $unchanged++
            continue
        }
        $bak = "$dst.$stamp.bak"
        Copy-Item $dst $bak -Force
        $backup = Split-Path -Leaf $bak
        Write-Host ("  backup " + $f.Name + "  ->  " + $backup)
    }

    Copy-Item $f.FullName $dst -Force
    $entries.Add($f.Name + "`t" + $backup)
    Write-Host ("  installed " + $f.Name) -ForegroundColor Green
    $installed++
}

$manifest = @(
    "# opencode-permission-modes install manifest (v1)",
    "# <agent file> tab <backup file or empty>",
    "# Used by uninstall.ps1 to restore your originals. Safe to delete."
) + $entries
Set-Content -Path $manifestPath -Value $manifest -Encoding ASCII

$jsonPath = Join-Path $ConfigDir "opencode.json"
$jsoncPath = Join-Path $ConfigDir "opencode.jsonc"

if (-not (Test-Path $jsonPath) -and -not (Test-Path $jsoncPath)) {
    Copy-Item (Join-Path $repoRoot "examples\opencode.jsonc") $jsoncPath -Force
    Write-Host ""
    Write-Host "Created opencode.jsonc (defaults to auto-edit, hides build/plan)" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "Existing config detected, left untouched. To default to auto-edit and hide build/plan, add:" -ForegroundColor Yellow
    Write-Host '    "default_agent": "auto-edit",'
    Write-Host '    "agent": { "build": { "disable": true }, "plan": { "disable": true } }'
}

Write-Host ""
Write-Host "Done. Installed $installed mode(s), $unchanged unchanged." -ForegroundColor Cyan
Write-Host "Restart OpenCode, then switch modes with Ctrl + . in the agent picker." -ForegroundColor Cyan
Write-Host "To undo this later: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1"
Write-Host ""
