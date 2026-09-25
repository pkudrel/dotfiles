#Requires -Version 7.0
<#
.SYNOPSIS
  Optional features on top of install.ps1: pick them from a checklist, install them, keep them updated.
.DESCRIPTION
  features.ps1                 checklist (arrows move, Space toggles, Enter installs)
  features.ps1 dotnet node     install these without asking and remember them
  features.ps1 --update        install/update the remembered features (install.ps1 runs this)
  features.ps1 --list          show every feature and its state
  --dry-run (with any of the above) shows what would be installed/updated and changes nothing

  Features are the lines of features\winget.txt plus the scripts features\NN-name.ps1 (for tools not in winget;
  line 1 is the description, actions "status" (exit 0 installed, 1 not installed, 2 not available) and "install").
  After every install/update of a feature, features\settings\<name>.ps1 (when there is one) sets the program up;
  a failing settings file is a warning, the feature still counts as installed.
  The selection is stored per machine in ~\.config\dotfiles\features (not in the repo).
  Unticking a feature only stops updating it; nothing is uninstalled.
#>
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $Arguments
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\lib.ps1')

$FeaturesDir   = Join-Path $PSScriptRoot 'features'
$SettingsDir   = Join-Path $FeaturesDir 'settings'
$SelectionFile = Join-Path $DotfilesConfigDir 'features'


######
###### FEATURE CATALOGUE
######

function Get-Features {
    foreach ($line in Read-ListFile (Join-Path $FeaturesDir 'winget.txt')) {
        $name, $id, $label, $note = ($line -split '\|', 4).ForEach({ $_.Trim() })
        [pscustomobject] @{ Name = $name; Label = $label; Kind = 'winget'; Id = $id; Note = $note; Path = $null }
    }
    foreach ($file in Get-ChildItem -Path $FeaturesDir -Filter '*.ps1' | Where-Object Name -match '^\d\d-' | Sort-Object Name) {
        $label = (Get-Content -Path $file.FullName -TotalCount 1) -replace '^#\s*', ''
        [pscustomobject] @{ Name = $file.BaseName -replace '^\d\d-', ''; Label = $label; Kind = 'script'; Id = $null; Note = $null; Path = $file.FullName }
    }
}

# Installed winget ids from a single "winget export", read once per run: one "winget list --id" per feature
# took seconds each. $null until the first call; when the export fails, each feature falls back to Test-WingetPackage.
$WingetInstalled = $null
$WingetExportFailed = $false

function Test-WingetFeature([string] $Id) {
    if ($null -eq $script:WingetInstalled -and -not $script:WingetExportFailed) {
        Write-Step 'checking installed features (winget export)'
        $file = Join-Path ([IO.Path]::GetTempPath()) "dotfiles-winget-export-$PID.json"
        try {
            # The exit code is not checked: winget also reports packages it cannot match to a source, the file is still written.
            winget export --output $file --source winget --accept-source-agreements --disable-interactivity *> $null
            $export = Get-Content -Raw -Path $file | ConvertFrom-Json
            $script:WingetInstalled = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($packageId in $export.Sources.Packages.PackageIdentifier) { [void] $script:WingetInstalled.Add($packageId) }
        }
        catch {
            Write-Warn "winget export failed ($($_.Exception.Message)), checking one package at a time"
            $script:WingetExportFailed = $true
        }
        finally {
            Remove-Item -Path $file -ErrorAction SilentlyContinue
        }
    }
    if ($script:WingetExportFailed) { return Test-WingetPackage $Id }
    $script:WingetInstalled.Contains($Id)
}

# State of a feature: Code 0 installed, 1 not installed, 2 not available on this machine; Text for display.
function Get-FeatureState($Feature) {
    if ($Feature.Kind -eq 'winget') {
        if (-not (Test-Command winget)) { return [pscustomobject] @{ Code = 2; Text = 'winget missing' } }
        if (Test-WingetFeature $Feature.Id) { return [pscustomobject] @{ Code = 0; Text = 'installed' } }
        return [pscustomobject] @{ Code = 1; Text = 'not installed' }
    }
    $text = (& $Feature.Path status 2>&1 | Out-String).Trim()
    [pscustomobject] @{ Code = $LASTEXITCODE; Text = $text }
}


######
###### SELECTION
######

function Get-Remembered {
    if (-not (Test-Path $SelectionFile)) { return @() }
    @(Read-ListFile $SelectionFile)
}

function Save-Selection([string[]] $Names) {
    New-Item -ItemType Directory -Force -Path (Split-Path $SelectionFile -Parent) | Out-Null
    Set-Content -Path $SelectionFile -Value ($Names -join "`n") -Encoding utf8NoBOM
    Write-Ok "remembered features: $(if ($Names) { $Names -join ' ' } else { 'none' }) ($SelectionFile)"
}

function Get-Feature([object[]] $Catalogue, [string] $Name) {
    $Catalogue | Where-Object Name -eq $Name | Select-Object -First 1
}

# The given names that can be installed here; warns about the others.
function Select-Available([object[]] $Catalogue, [string[]] $Names) {
    foreach ($name in $Names) {
        $state = Get-FeatureState (Get-Feature $Catalogue $name)
        if ($state.Code -eq 2) { Write-Warn "${name}: not available on this machine ($($state.Text)), not remembered" }
        else { $name }
    }
}


######
###### ACTIONS
######

function Show-Features([object[]] $Catalogue) {
    $remembered = Get-Remembered
    foreach ($feature in $Catalogue) {
        $state = Get-FeatureState $feature
        $mark = if ($feature.Name -in $remembered) { ', remembered' } else { '' }
        '  {0,-17} {1,-28} {2}' -f $feature.Name, "$($state.Text)$mark", $feature.Label
    }
}

# features\settings\<name>.ps1: run after every install/update, so it must be safe to run again.
# A failure is only a warning.
function Invoke-FeatureSettings($Feature) {
    $path = Join-Path $SettingsDir "$($Feature.Name).ps1"
    if (-not (Test-Path $path)) { return }
    if ($DotfilesDryRun) {
        Write-Would "run settings $($Feature.Name) (features\settings\$($Feature.Name).ps1)"
        return
    }
    Write-Step "settings $($Feature.Name)"
    try {
        $global:LASTEXITCODE = 0
        & $path
        if ($LASTEXITCODE) { throw "exit code $LASTEXITCODE" }
        Write-Ok "settings $($Feature.Name)"
    }
    catch {
        Write-Warn "settings $($Feature.Name) failed: $($_.Exception.Message)"
    }
}

function Install-Features([object[]] $Catalogue, [string[]] $Names) {
    if (-not $Names) {
        Write-Ok 'no features to install'
        return
    }
    $failed = @()
    $position = 0
    foreach ($name in $Names) {
        $position++
        $counter = "[$position/$($Names.Count)]"
        $feature = Get-Feature $Catalogue $name
        if (-not $feature) {
            Write-Warn "unknown feature: $name"
            $failed += $name
            continue
        }
        $state = Get-FeatureState $feature
        if ($state.Code -eq 2) {
            Write-Warn "${name}: not available on this machine ($($state.Text)), skipped"
            continue
        }
        if ($DotfilesDryRun) {
            Write-Would "$counter $(if ($state.Code -eq 0) { 'update' } else { 'install' }) $name ($($state.Text))"
            Invoke-FeatureSettings $feature
            continue
        }
        Write-Step "$counter feature $name"
        try {
            if ($feature.Kind -eq 'winget') {
                if ($state.Code -eq 0) { Update-WingetPackage $feature.Id } else { Install-WingetPackage $feature.Id }
                Write-Ok "$name ($($feature.Id))$(if ($feature.Note) { "; $($feature.Note)" })"
            }
            else {
                & $feature.Path install
                if ($LASTEXITCODE) { throw "exit code $LASTEXITCODE" }
            }
        }
        catch {
            Write-Warn "feature $name failed: $($_.Exception.Message)"
            $failed += $name
            continue
        }
        Invoke-FeatureSettings $feature
    }
    if ($failed) { Stop-Install "failed features: $($failed -join ' ')" }
    if ($DotfilesDryRun) { return }
    Write-Ok "features done: $($Names -join ' ')"
}

# Checklist of all features. Pre-selected: installed features and remembered ones that are not installed yet.
# Features not available on this machine are shown as [-] and skipped by the cursor.
function Select-Features([object[]] $Catalogue) {
    if ([Console]::IsInputRedirected) { Stop-Install 'no terminal: pass feature names or --update' }
    $remembered = Get-Remembered
    $rows = foreach ($feature in $Catalogue) {
        $state = Get-FeatureState $feature
        [pscustomobject] @{
            Name      = $feature.Name
            State     = $state.Text
            Label     = $feature.Label
            Available = $state.Code -ne 2
            Selected  = ($state.Code -eq 0) -or ($state.Code -eq 1 -and $feature.Name -in $remembered)
        }
    }
    if (-not ($rows | Where-Object Available)) {
        Write-Warn 'no feature can be installed on this machine'
        return @()
    }
    $choice = Select-FromChecklist $rows 'install'
    if ($choice.Cancelled) {
        # Not an error: a plain message and exit 0 (setup.ps1 carries on with the next phase).
        Write-Warn 'features: cancelled, nothing changed (pick them later: dlab-features-select)'
        exit 0
    }
    $choice.Names
}


######
###### MAIN
######

if ($Arguments -contains '--dry-run') {
    $DotfilesDryRun = $true
    $Arguments = @($Arguments | Where-Object { $_ -ne '--dry-run' })
    Write-Warn 'dry run: nothing is changed'
}

$catalogue = @(Get-Features)
$first = if ($Arguments) { $Arguments[0] } else { '' }

switch -Regex ($first) {
    '^--list$' {
        Show-Features $catalogue
        break
    }
    '^--update$' {
        Install-Features $catalogue (Get-Remembered)
        break
    }
    '^(-h|--help)$' {
        Get-Help $PSCommandPath -Full | Out-String | Write-Host
        break
    }
    '^-' {
        Stop-Install "unknown option: $first (see --help)"
    }
    '^$' {
        $names = @(Select-Available $catalogue (Select-Features $catalogue))
        if (-not $DotfilesDryRun) { Save-Selection $names }
        Install-Features $catalogue $names
        break
    }
    default {
        foreach ($name in $Arguments) {
            if (-not (Get-Feature $catalogue $name)) {
                Stop-Install "unknown feature: $name (available: $($catalogue.Name -join ' '))"
            }
        }
        $wanted = @(Select-Available $catalogue $Arguments)
        $names = @(@(Get-Remembered) + $wanted | Select-Object -Unique)
        if (-not $DotfilesDryRun) { Save-Selection $names }
        Install-Features $catalogue $wanted
    }
}
