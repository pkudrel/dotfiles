#Requires -Version 7.0
<#
.SYNOPSIS
  Kept for the old README block: runs the profile-related steps of windows\install.ps1.
.DESCRIPTION
  Same as: install.ps1 execution-policy modules profile font (minus the skipped ones).
  For the whole setup run install.ps1 (and admin.ps1) instead.
.EXAMPLE
  pwsh -ExecutionPolicy Bypass -File "$HOME\.dotfiles\windows\powershell\install-profile.ps1"
#>
param(
    [switch] $SkipModules,
    [switch] $SkipOhMyPosh,
    [switch] $SkipFont
)

$ErrorActionPreference = 'Stop'

$steps = @('execution-policy', 'profile')
if (-not $SkipModules) { $steps += 'modules' }
if (-not $SkipFont) { $steps += 'font' }
if (-not $SkipOhMyPosh) {
    # Oh My Posh comes with the winget step now; install just that package here.
    winget install --id JanDeDobbeleer.OhMyPosh --exact --source winget --accept-package-agreements --accept-source-agreements
}

& (Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1') @steps
