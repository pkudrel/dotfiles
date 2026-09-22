# Shared helpers for install.ps1, admin.ps1, features.ps1 and their steps. Dot-source it, don't run it.

$WindowsDir  = Split-Path $PSScriptRoot -Parent

# One backup folder per run: install.ps1 sets DOTFILES_BACKUP_DIR for all its steps.
$BackupDir = if ($env:DOTFILES_BACKUP_DIR) { $env:DOTFILES_BACKUP_DIR }
             else { Join-Path $HOME ".dotfiles-backup\$(Get-Date -Format 'yyyyMMdd-HHmmss')" }

# Per-machine state (feature selection), same place as on Ubuntu.
$DotfilesConfigDir = Join-Path $HOME '.config\dotfiles'

# This machine's files inside the repo folder, never committed (/local/ in .gitignore): files from the
# Bitwarden-store step (e.g. .gitconfig.user) and its temp downloads.
$DotfilesLocalDir = Join-Path (Split-Path $WindowsDir -Parent) 'local'

# Dry run (install.ps1 -DryRun, features.ps1 --dry-run): steps report what they would change and change nothing.
$DotfilesDryRun = [bool] $env:DOTFILES_DRY_RUN


######
###### OUTPUT
######

function Write-Step([string] $Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string] $Message)   { Write-Host " ok $Message" -ForegroundColor Green }
function Write-Warn([string] $Message) { Write-Host " !! $Message" -ForegroundColor Yellow }
function Write-Would([string] $Message) { Write-Host " -- would $Message" -ForegroundColor Magenta }
function Stop-Install([string] $Message) { throw $Message }


######
###### CHECKS
######

function Test-Command([string] $Name) {
    [bool] (Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function Test-Admin {
    if (-not $IsWindows) { return $false }
    $principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Re-read PATH from the registry, so tools installed by winget in this run are found.
function Update-SessionPath {
    $env:Path = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) -join ';'
}

# Lines of a list file without comments (#...) and blank lines, trimmed.
function Read-ListFile([string] $Path) {
    foreach ($line in Get-Content -Path $Path) {
        $line = ($line -replace '#.*$', '').Trim()
        if ($line) { $line }
    }
}

# Steps of a runner: files NN-*.ps1 in $Directory, optionally only those whose name contains one of $Filter.
# Steps with "# opt-in" in their first lines run only when a filter names them.
function Get-Steps([string] $Directory, [string[]] $Filter) {
    $all = Get-ChildItem -Path $Directory -Filter '*.ps1' | Where-Object Name -match '^\d\d-' | Sort-Object Name
    if (-not $Filter) {
        return $all | Where-Object { -not (Test-OptIn $_.FullName) }
    }
    $selected = $all | Where-Object {
        $name = $_.Name
        $Filter | Where-Object { $name -like "*$_*" }
    }
    if (-not $selected) { Stop-Install "no step matches: $($Filter -join ' ') (steps: $($all.BaseName -join ', '))" }
    $selected
}

function Test-OptIn([string] $Path) {
    [bool] (Get-Content -Path $Path -TotalCount 5 | Where-Object { $_ -match '^#\s*opt-in\b' })
}


######
###### FILES
######

# Copy $Path into $BackupDir (keeping its path below $HOME) before it is replaced; nothing when missing.
function Backup-Item([string] $Path) {
    if ($DotfilesDryRun -or -not (Test-Path -LiteralPath $Path)) { return }
    $full = (Resolve-Path -LiteralPath $Path).Path
    $relative = if ($full.StartsWith($HOME, [StringComparison]::OrdinalIgnoreCase)) {
        $full.Substring($HOME.Length).TrimStart('\', '/')
    }
    else {
        $full -replace ':', ''
    }
    $target = Join-Path $BackupDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item -LiteralPath $full -Destination $target -Recurse -Force
    Write-Warn "backed up $full → $target"
}

# Copy $Source to $Destination only when $Destination does not exist yet; never overwrite.
function Copy-IfMissing([string] $Source, [string] $Destination) {
    if (Test-Path -LiteralPath $Destination) {
        Write-Ok "exists, left untouched: $Destination"
        return
    }
    if ($DotfilesDryRun) {
        Write-Would "create $Destination"
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination
    Write-Ok "created $Destination"
}


######
###### WINDOWS TERMINAL
######

# settings.json of the installed Windows Terminal (Store version; Preview or unpackaged when that is what exists).
function Get-TerminalSettingsPath {
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    $existing = @($candidates | Where-Object { Test-Path $_ })
    if ($existing) { $existing } else { $candidates[0] }
}


######
###### BITWARDEN CLI
######

# Unlock the Bitwarden CLI for this process ($env:BW_SESSION); installs bw and logs in first when needed.
# $true when unlocked; $false when the master password prompt was left empty (Enter): the caller skips its Bitwarden work.
# The password is asked first, so skipping installs and logs in nothing. It goes through an environment
# variable, never a command line. Close with Close-BitwardenSession.
function Open-BitwardenSession {
    if ([Console]::IsInputRedirected) { Stop-Install 'the Bitwarden CLI needs a terminal to ask for the master password' }
    $password = Read-Host 'Bitwarden master password (unlocks the CLI; Enter = skip)' -AsSecureString
    if ($password.Length -eq 0) { return $false }

    if (-not (Test-Command bw)) {
        Write-Step 'installing the Bitwarden CLI (bw)'
        Install-WingetPackage Bitwarden.CLI | Out-Host  # to the screen: the caller only reads $true/$false
    }
    $env:BW_PASSWORD = [Net.NetworkCredential]::new('', $password).Password
    try {
        if ((bw status | ConvertFrom-Json).status -eq 'unauthenticated') {
            # EU vault: run "bw config server https://vault.bitwarden.eu" once before this.
            Write-Step 'Bitwarden CLI: log in (e-mail and 2FA; the master password is the one given above)'
            bw login --passwordenv BW_PASSWORD | Out-Null
            if ($LASTEXITCODE) { Stop-Install 'bw login failed' }
        }
        $session = bw unlock --passwordenv BW_PASSWORD --raw
    }
    finally {
        Remove-Item Env:BW_PASSWORD -ErrorAction SilentlyContinue
    }
    if ($LASTEXITCODE -or -not $session) { Stop-Install 'bw unlock failed' }
    $env:BW_SESSION = $session
    bw sync | Out-Null
    $true
}

function Close-BitwardenSession {
    if ($env:BW_SESSION) { bw lock | Out-Null }
    Remove-Item Env:BW_SESSION -ErrorAction SilentlyContinue
}

# The vault item with exactly this name, or $null.
function Get-BitwardenItem([string] $Name) {
    bw list items --search $Name | ConvertFrom-Json | Where-Object name -eq $Name | Select-Object -First 1
}


######
###### WINGET
######

# winget exit codes that mean "nothing to do", not failure.
$WingetNothingToDo = @(
    -1978335189  # 0x8A15002B: no applicable upgrade
    -1978335135  # 0x8A150061: package already installed
)

$WingetCommonArgs = @('--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')

function Assert-Winget {
    if (-not (Test-Command winget)) {
        Stop-Install 'winget not found. Microsoft Store → Library → Get updates (updates "App Installer"), then retry.'
    }
}

# One line of a package list: "<id>", optionally followed by "| override=<installer arguments>"
# and/or "| command=<exe>" (present when that command is on PATH, e.g. installed from the Store or an MSI).
function ConvertFrom-PackageLine([string] $Line) {
    $parts = $Line -split '\|'
    $package = [ordered] @{ Id = $parts[0].Trim(); Override = $null; Command = $null }
    foreach ($option in $parts | Select-Object -Skip 1) {
        if ($option.Trim() -match '^override=(.+)$') { $package.Override = $Matches[1].Trim() }
        elseif ($option.Trim() -match '^command=(.+)$') { $package.Command = $Matches[1].Trim() }
    }
    [pscustomobject] $package
}

function Test-WingetPackage([string] $Id, [string] $Command) {
    if ($Command -and (Test-Command $Command)) { return $true }
    winget list --id $Id @WingetCommonArgs *> $null
    $LASTEXITCODE -eq 0
}

function Install-WingetPackage([string] $Id, [string] $Override) {
    $installArgs = @('install', '--id', $Id) + $WingetCommonArgs + @('--accept-package-agreements')
    if ($Override) { $installArgs += @('--override', $Override) }
    winget @installArgs
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -notin $WingetNothingToDo) {
        Stop-Install "winget install $Id failed (exit code $LASTEXITCODE)"
    }
    Update-SessionPath
}

function Update-WingetPackage([string] $Id) {
    winget upgrade --id $Id @WingetCommonArgs --accept-package-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -notin $WingetNothingToDo) {
        Stop-Install "winget upgrade $Id failed (exit code $LASTEXITCODE)"
    }
    Update-SessionPath
}
