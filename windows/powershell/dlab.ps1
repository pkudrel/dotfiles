# dlab-{area}-{action} commands for this dotfiles setup (PowerShell). List them with dlab-help (or dlab-<Tab>).
# Dot-sourced by profile.ps1.

$DlabDotfilesDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$DlabWindowsDir  = Join-Path $DlabDotfilesDir 'windows'
$DlabCommands    = [ordered] @{}


# Runs a script from windows\. A stop (Stop-Install throws) shows as one red line instead of
# PowerShell's error view pointing at lib.ps1; Get-Error still has the details. $LASTEXITCODE: 0 ok, 1 stopped.
function _dlab_run([string] $Script, [object[]] $Arguments) {
    try {
        & (Join-Path $DlabWindowsDir $Script) @Arguments
        $global:LASTEXITCODE = 0
    }
    catch {
        Write-Host " !! stopped: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '    details: Get-Error' -ForegroundColor DarkGray
        $global:LASTEXITCODE = 1
    }
}


$DlabCommands['dlab-dotfiles-update'] = 'get the latest dotfiles (git pull) and apply them (install.ps1)'
function dlab-dotfiles-update {
    # --ff-only: a rewritten GitHub history (or local commits) stops here instead of being merged.
    git -C $DlabDotfilesDir pull --ff-only
    if ($LASTEXITCODE) {
        Write-Warning 'dlab: git pull failed (history differs from GitHub?), nothing applied (see dlab-dotfiles-status)'
        return
    }
    _dlab_run 'install.ps1'
    if ($LASTEXITCODE) { return }
    Write-Host 'Open a new tab for profile changes.'
}

# Version of a git ref from the v* tags created by GitHub Actions: "0.1.8", "0.1.8 +2 commits", or nothing.
function _dlab_version([string] $Ref) {
    $described = git -C $DlabDotfilesDir describe --tags --match 'v[0-9]*' $Ref 2>$null
    if ($LASTEXITCODE -or -not $described) { return }
    if ($described -match '^v(.+)-(\d+)-g[0-9a-f]+$') {
        "$($Matches[1]) +$($Matches[2]) commit$(if ($Matches[2] -ne '1') { 's' })"
    }
    else {
        $described -replace '^v', ''
    }
}

$DlabCommands['dlab-dotfiles-status'] = 'compare with GitHub: versions, local changes, commits to pull / not pushed yet (fetches first)'
function dlab-dotfiles-status {
    git -C $DlabDotfilesDir fetch --quiet --tags
    if ($LASTEXITCODE) { Write-Warning 'dlab: fetch failed, showing the last known GitHub state' }
    git -C $DlabDotfilesDir status -sb

    $here = _dlab_version HEAD
    $latest = git -C $DlabDotfilesDir describe --tags --abbrev=0 --match 'v[0-9]*' '@{u}' 2>$null
    Write-Host "`nThis machine: $(if ($here) { $here } else { 'no version tag yet' })"
    if (-not $latest) {
        Write-Host 'GitHub:       no version tag yet (GitHub Actions creates them after a push to main)'
    }
    else {
        git -C $DlabDotfilesDir merge-base --is-ancestor $latest HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "GitHub:       $($latest -replace '^v', '')" }
        else { Write-Host "GitHub:       $($latest -replace '^v', '')  → update available: dlab-dotfiles-update" }
    }

    $incoming = git -C $DlabDotfilesDir log --oneline 'HEAD..@{u}' 2>$null
    $outgoing = git -C $DlabDotfilesDir log --oneline '@{u}..HEAD' 2>$null
    if ($incoming) { Write-Host "`nTo pull (dlab-dotfiles-update):"; $incoming | Write-Host }
    if ($outgoing) { Write-Host "`nNot pushed yet:"; $outgoing | Write-Host }
}

$DlabCommands['dlab-dotfiles-version'] = "version of this machine's dotfiles (local, no network; compare with GitHub: dlab-dotfiles-status)"
function dlab-dotfiles-version {
    $version = _dlab_version HEAD
    if (-not $version) {
        Write-Warning 'dlab: no version tag in this checkout yet (dlab-dotfiles-status fetches tags from GitHub)'
        return
    }
    $version
}

$DlabCommands['dlab-dotfiles-cd'] = 'go to the dotfiles repo'
function dlab-dotfiles-cd { Set-Location $DlabDotfilesDir }

$DlabCommands['dlab-dotfiles-edit'] = 'open the dotfiles repo in VS Code'
function dlab-dotfiles-edit {
    if (Get-Command code -ErrorAction SilentlyContinue) { code $DlabDotfilesDir }
    else {
        Write-Warning "dlab: VS Code ('code') not found, going to the repo instead"
        Set-Location $DlabDotfilesDir
    }
}

$DlabCommands['dlab-features-select'] = 'pick optional features from a checklist (or pass names: dlab-features-select dotnet node)'
function dlab-features-select { _dlab_run 'features.ps1' $args }

$DlabCommands['dlab-features-list'] = 'state of every optional feature'
function dlab-features-list { _dlab_run 'features.ps1' '--list' }

$DlabCommands['dlab-features-update'] = 'install/update the remembered optional features'
function dlab-features-update { _dlab_run 'features.ps1' '--update' }

$DlabCommands['dlab-migrate-export'] = 'export browser profiles into a folder (dlab-migrate-export [<folder>] [chrome brave firefox]; folder C:\!dlab-migrate by default; checklist without names)'
function dlab-migrate-export { _dlab_run 'migrate.ps1' (@('export') + $args) }

$DlabCommands['dlab-migrate-import'] = 'replace the browser profiles here with an export (dlab-migrate-import [<folder>] [names]; folder C:\!dlab-migrate by default; asks first)'
function dlab-migrate-import { _dlab_run 'migrate.ps1' (@('import') + $args) }

$DlabCommands['dlab-migrate-list'] = 'programs that dlab-migrate-export knows and their data here (dlab-migrate-list [<folder>] compares with an export, C:\!dlab-migrate when it exists)'
function dlab-migrate-list { _dlab_run 'migrate.ps1' (@('--list') + $args) }

$DlabCommands['dlab-store-restore'] = 'put the files from bitwarden-store in place (install.ps1 bitwarden-store; asks for the master password)'
function dlab-store-restore { _dlab_run 'install.ps1' 'bitwarden-store' }

$DlabCommands['dlab-store-list'] = 'what is in bitwarden-store: attachments and the manifest lines that use them'
function dlab-store-list { _dlab_run 'store.ps1' @('list') }

$DlabCommands['dlab-store-add'] = 'add a file to bitwarden-store (dlab-store-add <file>; its manifest line is written in the editor)'
function dlab-store-add([string] $File) { _dlab_run 'store.ps1' @('add', $File) }

$DlabCommands['dlab-store-replace'] = 'new version of a file in bitwarden-store (dlab-store-replace <file>; the old one stays as <name>.prev)'
function dlab-store-replace([string] $File) { _dlab_run 'store.ps1' @('replace', $File) }

$DlabCommands['dlab-store-remove'] = 'remove a file and its manifest lines from bitwarden-store (dlab-store-remove <name>; asks first)'
function dlab-store-remove([string] $Name) { _dlab_run 'store.ps1' @('remove', $Name) }

$DlabCommands['dlab-store-manifest-edit'] = 'edit _manifest.txt of bitwarden-store (checked before it is saved)'
function dlab-store-manifest-edit { _dlab_run 'store.ps1' @('manifest-edit') }

$DlabCommands['dlab-terminal-save'] = "copy this machine's Windows Terminal settings.json into the repo (then commit it)"
function dlab-terminal-save {
    . (Join-Path $DlabWindowsDir 'scripts\lib.ps1')
    $source = Get-TerminalSettingsPath | Select-Object -First 1
    if (-not (Test-Path $source)) {
        Write-Warning "dlab: Windows Terminal settings not found ($source)"
        return
    }
    $target = Join-Path $DlabWindowsDir 'terminal\settings.json'
    Copy-Item -Path $source -Destination $target -Force
    Write-Host "Saved $source → $target"
    git -C $DlabDotfilesDir status --short -- $target
}

$DlabCommands['dlab-winget-upgradeall'] = 'upgrade all winget packages'
function dlab-winget-upgradeall {
    winget upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements @args
}

$DlabCommands['dlab-help'] = 'this list'
function dlab-help {
    foreach ($name in $DlabCommands.Keys | Sort-Object) {
        '  {0,-24} {1}' -f $name, $DlabCommands[$name]
    }
}
