#Requires -Version 7.0
<#
.SYNOPSIS
  Sets up (or refreshes) this Windows machine from the dotfiles repo. Safe to re-run, no admin rights needed.
.DESCRIPTION
  Runs windows\scripts\NN-*.ps1 in order. Arguments select steps whose name contains them.
  -DryRun shows what each step would change (packages to install, files to write) and changes nothing.
  Admin work (Dev Drive, drive letters, Hypervisor Platform, ...) is in admin.ps1, run before this one.
.EXAMPLE
  pwsh -File "$HOME\.dotfiles\windows\install.ps1"
.EXAMPLE
  pwsh -File "$HOME\.dotfiles\windows\install.ps1" winget terminal
.EXAMPLE
  pwsh -File "$HOME\.dotfiles\windows\install.ps1" -DryRun
#>
param(
    # Show what would change, change nothing.
    [switch] $DryRun,
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $Filter
)

$ErrorActionPreference = 'Stop'

$env:DOTFILES_BACKUP_DIR = Join-Path $HOME ".dotfiles-backup\$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$env:DOTFILES_DRY_RUN = if ($DryRun) { '1' } else { '' }
. (Join-Path $PSScriptRoot 'scripts\lib.ps1')

if (Test-Admin) {
    Stop-Install 'run as your normal user, not as administrator (admin work is in admin.ps1)'
}

$build = [Environment]::OSVersion.Version
Write-Step "Windows $($build.Major).$($build.Minor) build $($build.Build) / PowerShell $($PSVersionTable.PSVersion)"

if ($DryRun) { Write-Warn 'dry run: nothing is changed' }

try {
    $steps = @(Get-Steps -Directory (Join-Path $PSScriptRoot 'scripts') -Filter $Filter)
    for ($i = 0; $i -lt $steps.Count; $i++) {
        Write-Step "step $($i + 1)/$($steps.Count): $($steps[$i].Name)"
        & $steps[$i].FullName
    }
}
finally {
    Remove-Item Env:DOTFILES_BACKUP_DIR, Env:DOTFILES_DRY_RUN -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Ok $(if ($DryRun) { 'dry run done: nothing was changed' } else { 'done' })
if ($DryRun) { return }
if (Test-Path $BackupDir) {
    Write-Warn "replaced files were copied to $BackupDir"
}
if ($env:DOTFILES_SETUP) { return }   # setup.ps1 prints its own next steps

Write-Host @'

Next steps:
  - open a new pwsh tab (profile, PATH and font apply there)
  - admin steps, if not done yet (Dev Drive, Q:, Hypervisor Platform, ssh-agent service):
      pwsh -File "$HOME\.dotfiles\windows\admin.ps1"
  - optional tools (dotnet, node, uv, claude-code, sbx, sbxup, quickgestures, ...): dlab-features-select
'@
