#Requires -Version 5.1
<#
.SYNOPSIS
    Install OpenCode Permission Modes (read-only / auto-edit / full-auto).

.DESCRIPTION
    Copies agent/*.md into the OpenCode config directory. Existing files with the
    same name are backed up to *.bak first.

    If the config directory has no opencode.json / opencode.jsonc, an example
    config is created. If a config already exists, the script only prints the
    snippet to add manually - it never overwrites your file.

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

if (-not (Test-Path $srcAgent)) {
    throw "Cannot find the agent directory: $srcAgent (run this script from the repo root)"
}

Write-Host ""
Write-Host "OpenCode Permission Modes"
Write-Host "Config directory: $ConfigDir"
Write-Host ""

New-Item -ItemType Directory -Path $dstAgent -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$installed = 0
foreach ($f in Get-ChildItem $srcAgent -Filter *.md) {
    $dst = Join-Path $dstAgent $f.Name
    if (Test-Path $dst) {
        $bak = "$dst.$stamp.bak"
        Copy-Item $dst $bak -Force
        Write-Host ("  backup " + $f.Name + "  ->  " + (Split-Path -Leaf $bak))
    }
    Copy-Item $f.FullName $dst -Force
    Write-Host ("  installed " + $f.Name) -ForegroundColor Green
    $installed++
}

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
Write-Host "Done. Installed $installed mode(s)." -ForegroundColor Cyan
Write-Host "Restart OpenCode, then switch modes with Ctrl + . in the agent picker." -ForegroundColor Cyan
Write-Host ""
