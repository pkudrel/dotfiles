#Requires -Version 7.0
<#
.SYNOPSIS
  One-off machine setup that needs administrator rights. Asks for elevation itself (one UAC prompt). Safe to re-run.
.DESCRIPTION
  Runs windows\admin\NN-*.ps1 in order: Hypervisor Platform, Dev Drive, BitLocker (+ recovery keys to Bitwarden),
  drive letters, ssh-agent service, preinstalled apps removed, privacy (telemetry, Copilot, Recall, Bing), OneDrive removed.
  Arguments select steps whose name contains them.
  WSL is an optional feature: dlab-features-select wsl.
  Run it before install.ps1 on a new machine, so W: exists when install.ps1 sets up Windows Terminal.
.EXAMPLE
  pwsh -File "$HOME\.dotfiles\windows\admin.ps1"
.EXAMPLE
  pwsh -File "$HOME\.dotfiles\windows\admin.ps1" -DryRun
.EXAMPLE
  pwsh -File "$HOME\.dotfiles\windows\admin.ps1" onedrive
#>
param(
    # Show what would change, change nothing.
    [switch] $DryRun,
    # Dev Drive: size taken from C:, drive letter and label.
    [int] $DevDriveSizeGB = 195,
    [string] $DevDriveLetter = 'W',
    [string] $DevDriveLabel = 'Work',
    # Set by the elevated relaunch: keep its window open at the end.
    [switch] $PauseAtEnd,
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $Filter
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\lib.ps1')

if (-not (Test-Admin)) {
    # Relaunch elevated with the same arguments, in a window that stays open until Enter.
    $forward = @('-NoProfile', '-File', $PSCommandPath, '-PauseAtEnd')
    foreach ($name in 'DevDriveSizeGB', 'DevDriveLetter', 'DevDriveLabel') {
        if ($PSBoundParameters.ContainsKey($name)) { $forward += @("-$name", "$($PSBoundParameters[$name])") }
    }
    if ($DryRun) { $forward += '-DryRun' }
    if ($Filter) { $forward += $Filter }
    Write-Step 'asking for administrator rights (UAC)'
    try {
        $process = Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $forward -Wait -PassThru
    }
    catch {
        Stop-Install "administrator rights not granted: $($_.Exception.Message)"
    }
    # The elevated run exits with 3010 (the Windows "restart required" code) when a step needs a restart.
    $global:DotfilesRebootRequired = $process.ExitCode -eq 3010
    switch ($process.ExitCode) {
        { $_ -in 0, 3010 } { break }
        -1073741510 { Stop-Install 'admin steps stopped: the elevated window was closed (or Ctrl+C) before they finished' }  # 0xC000013A
        default { Stop-Install "admin steps failed (exit code $_); see the elevated window" }
    }
    return
}

$options = @{
    DevDriveSizeGB = $DevDriveSizeGB
    DevDriveLetter = $DevDriveLetter.TrimEnd(':').ToUpperInvariant()
    DevDriveLabel  = $DevDriveLabel
}
$global:DotfilesRebootRequired = $false

try {
    if ($DryRun) { Write-Warn 'dry run: nothing is changed' }
    foreach ($step in Get-Steps -Directory (Join-Path $PSScriptRoot 'admin') -Filter $Filter) {
        Write-Step "step $($step.Name)"
        & $step.FullName -DryRun:$DryRun -Options $options
    }
    Write-Host ''
    Write-Ok 'done'
    if ($global:DotfilesRebootRequired) {
        Write-Warn 'restart Windows to finish (Restart-Computer)'
    }
}
catch {
    Write-Host ''
    Write-Warn "failed: $($_.Exception.Message)"
    throw
}
finally {
    if ($PauseAtEnd) { Read-Host 'Press Enter to close' | Out-Null }
}
if ($PauseAtEnd -and $global:DotfilesRebootRequired) { exit 3010 }
