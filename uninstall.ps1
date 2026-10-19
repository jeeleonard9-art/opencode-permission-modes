#Requires -Version 5.1
<#
.SYNOPSIS
    Remove the OpenCode Permission Modes installed by install.ps1.

.DESCRIPTION
    Reads .opencode-permission-modes.manifest and, for each of the three modes:
      - restores the backup recorded at install time (if there is one), or
      - removes the file if it was installed into a clean config directory.

    opencode.json / opencode.jsonc are never modified, but the script warns when
    default_agent still points at a mode that no longer exists.

.PARAMETER ConfigDir
    Config directory. Defaults to ~/.config/opencode

.PARAMETER Yes
    Skip the confirmation prompt.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
#>
[CmdletBinding()]
param(
    [string]$ConfigDir = (Join-Path $HOME ".config\opencode"),
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$agentDir = Join-Path $ConfigDir "agent"
$manifestPath = Join-Path $ConfigDir ".opencode-permission-modes.manifest"
$modes = @("read-only.md", "auto-edit.md", "full-auto.md")

if (-not (Test-Path $agentDir)) {
    Write-Host "Nothing to do: $agentDir does not exist."
    exit 0
}

# agent file -> backup file, from the manifest install.ps1 wrote.
$prior = @{}
if (Test-Path $manifestPath) {
    foreach ($line in Get-Content $manifestPath) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2) { $prior[$parts[0].Trim()] = $parts[1].Trim() }
    }
}

function Find-NewestBackup([string]$name) {
    $candidates = @(Get-ChildItem $agentDir -Filter "$name.*.bak" -File -ErrorAction SilentlyContinue)
    $legacy = Join-Path $agentDir "$name.bak"
    if (Test-Path $legacy) { $candidates += Get-Item $legacy }
    if ($candidates.Count -eq 0) { return "" }
    return ($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name
}

$plan = @()
foreach ($mode in $modes) {
    $dst = Join-Path $agentDir $mode
    $exists = Test-Path $dst
    $backup = ""
    if ($prior.ContainsKey($mode)) {
        $backup = $prior[$mode]
    }
    elseif ($exists) {
        # No manifest (installed by an older version): fall back to the newest backup.
        $backup = Find-NewestBackup $mode
    }
    if ($backup -and -not (Test-Path (Join-Path $agentDir $backup))) { $backup = "" }

    if ($backup) {
        $plan += [pscustomobject]@{ File = $mode; Action = "restore"; Backup = $backup }
    }
    elseif ($exists) {
        $plan += [pscustomobject]@{ File = $mode; Action = "remove"; Backup = "" }
    }
}

if ($plan.Count -eq 0) {
    Write-Host "Nothing to undo in $agentDir."
    if (Test-Path $manifestPath) { Remove-Item $manifestPath -Force }
    exit 0
}

Write-Host ""
Write-Host "OpenCode Permission Modes - uninstall"
Write-Host "Config directory: $ConfigDir"
Write-Host ""
Write-Host "Planned changes:"
foreach ($item in $plan) {
    if ($item.Action -eq "restore") {
        Write-Host ("  restore " + $item.File + "  <-  " + $item.Backup)
    }
    else {
        Write-Host ("  remove  " + $item.File)
    }
}
Write-Host ""
Write-Host "opencode.json / opencode.jsonc will not be touched."
Write-Host ""

if (-not $Yes) {
    $answer = Read-Host "Proceed? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "Aborted. Nothing was changed."
        exit 1
    }
}

foreach ($item in $plan) {
    if ($item.Action -eq "restore") {
        Copy-Item (Join-Path $agentDir $item.Backup) (Join-Path $agentDir $item.File) -Force
        Remove-Item (Join-Path $agentDir $item.Backup) -Force
        Write-Host ("  restored " + $item.File) -ForegroundColor Green
    }
    else {
        Remove-Item (Join-Path $agentDir $item.File) -Force
        Write-Host ("  removed  " + $item.File) -ForegroundColor Green
    }
}

if (Test-Path $manifestPath) { Remove-Item $manifestPath -Force }

# The config file is the user's: only warn, never edit.
foreach ($cfgName in @("opencode.json", "opencode.jsonc")) {
    $cfg = Join-Path $ConfigDir $cfgName
    if (-not (Test-Path $cfg)) { continue }
    $text = Get-Content $cfg -Raw
    $match = [regex]::Match($text, '"default_agent"\s*:\s*"([^"]+)"')
    if ($match.Success -and $modes -contains ($match.Groups[1].Value + ".md")) {
        Write-Host ""
        Write-Host ("Warning: " + $cfgName + ' still has "default_agent": "' + $match.Groups[1].Value + '".') -ForegroundColor Yellow
        Write-Host "That mode no longer exists; OpenCode will fall back to its built-in default."
        Write-Host "Edit or remove default_agent in that file."
    }
    if ($text -match '"build"\s*:\s*\{\s*"disable"\s*:\s*true') {
        Write-Host ""
        Write-Host ("Note: " + $cfgName + " disables the built-in build agent.") -ForegroundColor Yellow
        Write-Host "With the three modes gone, you may want to remove that too."
    }
}

Write-Host ""
Write-Host "Done. Restart OpenCode to drop the modes from the picker." -ForegroundColor Cyan
Write-Host ""
