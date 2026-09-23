#Requires -Version 7.0
<#
.SYNOPSIS
  First run on a new Windows 11 machine: admin steps, install steps, optional features, restart. Safe to re-run.
.DESCRIPTION
  1. checks winget
  2. admin.ps1   (one UAC prompt; Dev Drive W:, Q:, Hypervisor Platform, ssh-agent service)
  3. install.ps1 (packages, profile, git, font, Windows Terminal)
  4. features.ps1 checklist (dotnet, node, sbx, wsl, ...)
  5. what is left to do by hand, and a restart when one is needed
  Day to day use admin.ps1 / install.ps1 / dlab-* directly.
.EXAMPLE
  pwsh -ExecutionPolicy Bypass -File "$HOME\.dotfiles\windows\setup.ps1"
.EXAMPLE
  pwsh -File "$HOME\.dotfiles\windows\setup.ps1" -DryRun
#>
param(
    # Show what would change, change nothing.
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\lib.ps1')

if (Test-Admin) {
    Stop-Install 'run as your normal user, not as administrator (setup asks for administrator rights itself)'
}

$phases = 'winget', 'admin steps', 'install steps', 'optional features', 'finish'
function Write-Phase([int] $Number) {
    Write-Host ''
    Write-Host "######## $Number/$($phases.Count): $($phases[$Number - 1])" -ForegroundColor Cyan
}

$env:DOTFILES_SETUP = '1'
try {
    Write-Phase 1
    Assert-Winget
    Write-Ok "winget $(winget --version)"

    Write-Phase 2
    & (Join-Path $PSScriptRoot 'admin.ps1') -DryRun:$DryRun
    $rebootRequired = [bool] $global:DotfilesRebootRequired

    Write-Phase 3
    & (Join-Path $PSScriptRoot 'install.ps1') -DryRun:$DryRun

    Write-Phase 4
    $featureArgs = if ($DryRun) { @('--update', '--dry-run') } else { @() }
    try {
        & (Join-Path $PSScriptRoot 'features.ps1') @featureArgs
    }
    catch {
        # Cancelled checklist or a failed feature should not hide the rest of the setup.
        Write-Warn "features: $($_.Exception.Message) (pick them later: dlab-features-select)"
    }
    # The wsl feature needs a restart on a clean Windows.
    $rebootRequired = $rebootRequired -or [bool] $global:DotfilesRebootRequired
}
catch {
    # Just the message, not PowerShell's error view pointing at Stop-Install in lib.ps1.
    Write-Host ''
    Write-Host " !! setup stopped: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '    fix it and run setup.ps1 again (it is safe to re-run)'
    exit 1
}
finally {
    Remove-Item Env:DOTFILES_SETUP -ErrorAction SilentlyContinue
}

Write-Phase 5
Write-Host @'
    Left to do by hand (once per machine):
      [ ] Bitwarden: sign in, Settings → enable SSH agent (holds all secrets and the SSH keys)
      [ ] Google Drive: sign in;  Obsidian: open the vault
      [ ] Microsoft Store → Library → Get updates
      [ ] features you picked: follow what they printed (sbx login, claude, QuickGestures in Brave, ...)
      [ ] WSL (if you picked the wsl feature): start Ubuntu once from the Start menu, then README "New WSL" from "In the new Ubuntu"
    Later: dlab-help lists the dlab-* commands (in a new pwsh tab).

'@

if ($DryRun) {
    Write-Ok 'dry run done: nothing was changed'
    return
}
if (-not $rebootRequired) {
    Write-Ok 'setup done; open a new pwsh tab'
    return
}
$answer = Read-Host 'A restart is needed to finish (Hypervisor Platform / drive letters / WSL). Restart now? [y/N]'
if ($answer -match '^\s*[yt]') {
    Restart-Computer
}
else {
    Write-Warn 'restart later to finish (Restart-Computer)'
}
