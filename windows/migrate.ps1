#Requires -Version 7.0
<#
.SYNOPSIS
  Moves program data (browser profiles) to another machine: export into a folder here, import from it there.
.DESCRIPTION
  migrate.ps1 export [<folder>]               checklist of the programs with data here (Space toggles, Enter exports)
  migrate.ps1 export [<folder>] chrome brave  export these without asking
  migrate.ps1 import [<folder>]               checklist of the programs in the export, then asks before replacing
  migrate.ps1 import [<folder>] firefox       import these (still asks, unless --yes)
  migrate.ps1 --list [<folder>]               every program and its data here (and in the export <folder>)
  <folder> defaults to C:\!dlab-migrate; a first argument that is a program name is a program, not a folder
  --dry-run (with export / import) shows what would be copied / replaced and changes nothing
  --yes (with import) replaces without asking
  --zip (with export) also packs the folder into one file inside it, <folder>\<folder>-<computer>-<date>.zip
        (not next to it: a normal user cannot create files in C:\); earlier .zip files there are not packed
        (copying one file to a USB stick / network drive is much faster than thousands of small ones);
        import, --list: <folder> can be such a .zip (unpacked into a temp folder for the import)

  The export folder holds manifest.json (when, from which computer, which profiles) and one folder per program
  in that program's own layout (chrome\, brave\, firefox\), readable without this script. Exporting again into
  the same folder replaces only the programs exported this time.
  Never exported: caches, saved passwords, cookies. Import replaces the program's data here completely: its other
  profiles, saved passwords and cookies here are gone (sign in again). Close the programs first.

  Programs are the scripts migrate\NN-name.ps1 (line 1 is the description; actions status, export, import:
  see scripts\migrate-lib.ps1). dlab commands: dlab-migrate-export, dlab-migrate-import, dlab-migrate-list.
#>
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $Arguments
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\lib.ps1')
. (Join-Path $PSScriptRoot 'scripts\migrate-lib.ps1')

$ProgramsDir   = Join-Path $PSScriptRoot 'migrate'
$ManifestName  = 'manifest.json'
$AssumeYes     = $false
$Zip           = $false
$DefaultFolder = 'C:\!dlab-migrate'
$Usage         = 'usage: migrate.ps1 export [<folder>] [program ...] [--zip] | import [<folder> | <file>.zip] [program ...] | --list [<folder> | <file>.zip] (see --help)'


######
###### PROGRAMS
######

function Get-Programs {
    foreach ($file in Get-ChildItem -Path $ProgramsDir -Filter '*.ps1' | Where-Object Name -match '^\d\d-' | Sort-Object Name) {
        $label = (Get-Content -Path $file.FullName -TotalCount 1) -replace '^#\s*', ''
        [pscustomobject] @{ Name = $file.BaseName -replace '^\d\d-', ''; Label = $label; Path = $file.FullName }
    }
}

function Get-Program([object[]] $Catalogue, [string] $Name) {
    $Catalogue | Where-Object Name -eq $Name | Select-Object -First 1
}

# Status object of a program (Code, Text, Profiles, Source, Process; see migrate-lib.ps1).
function Get-ProgramState($Program) {
    & $Program.Path status
}

# The names as the catalogue spells them; stops on an unknown one.
function Resolve-ProgramNames([object[]] $Catalogue, [string[]] $Names) {
    foreach ($name in $Names) {
        $program = Get-Program $Catalogue $name
        if (-not $program) { Stop-Install "unknown program: $name (available: $($Catalogue.Name -join ' '))" }
        $program.Name
    }
}

# Stops when one of the programs is running (each program checks again before it copies).
function Assert-Closed([hashtable] $States, [string[]] $Names) {
    $running = @($Names | Where-Object { Get-Process -Name $States[$_].Process -ErrorAction SilentlyContinue })
    if ($running) { Stop-Install "close first (also in the tray): $($running -join ', ')" }
}


######
###### EXPORT FOLDER
######

function Resolve-Folder([string] $Path) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Test-ZipFile([string] $Path) {
    $Path -like '*.zip' -and (Test-Path -LiteralPath $Path -PathType Leaf)
}

# The manifest of an export folder, or of an export .zip (read without unpacking).
function Read-Manifest([string] $Folder) {
    if (Test-ZipFile $Folder) {
        $archive = [IO.Compression.ZipFile]::OpenRead($Folder)
        try {
            $entry = $archive.GetEntry($ManifestName)
            if (-not $entry) { return $null }
            $reader = [IO.StreamReader]::new($entry.Open())
            try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        finally {
            $archive.Dispose()
        }
    }
    else {
        $path = Join-Path $Folder $ManifestName
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $json = Get-Content -Raw -LiteralPath $path
    }
    $manifest = $json | ConvertFrom-Json -AsHashtable
    if (-not $manifest.programs) { $manifest.programs = [ordered] @{} }
    $manifest
}

function Save-Manifest([string] $Folder, $Manifest) {
    $Manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Folder $ManifestName) -Encoding utf8NoBOM
}

function Get-DotfilesVersion {
    if (-not (Test-Command git)) { return $null }
    $version = git -C (Split-Path $WindowsDir -Parent) describe --tags --always 2>$null
    if ($LASTEXITCODE) { return $null }
    $version
}

# The whole export folder (every program in it) as <folder>\<folder>-<computer>-<date>.zip, file by file for the
# progress bar. Fastest: most of the time goes to reading thousands of small files, stronger compression gains little.
function New-ExportZip([string] $Folder) {
    $name = (@((Split-Path $Folder -Leaf), $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm')) | Where-Object { $_ }) -join '-'
    # Inside the folder, not next to it: in C:\ a normal user may create folders but not files.
    $zip = Join-Path $Folder "$name.zip"
    Write-Step "packing $Folder → $zip"
    $activity = "packing $(Split-Path $zip -Leaf)"
    # Zips of earlier exports lie in the folder itself: not packed again.
    $files = @([IO.Directory]::GetFiles($Folder, '*', [IO.SearchOption]::AllDirectories) |
        Where-Object { -not ($_ -like '*.zip' -and [IO.Path]::GetDirectoryName($_) -eq $Folder) })
    # Empty folders get their own entry (e.g. an empty profile subfolder), like ZipFile.CreateFromDirectory.
    $emptyDirs = @([IO.Directory]::GetDirectories($Folder, '*', [IO.SearchOption]::AllDirectories) |
        Where-Object { -not [IO.Directory]::EnumerateFileSystemEntries($_).GetEnumerator().MoveNext() })
    $archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $done = 0
        foreach ($file in $files) {
            $entryName = [IO.Path]::GetRelativePath($Folder, $file) -replace '\\', '/'
            [void] [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file, $entryName, [IO.Compression.CompressionLevel]::Fastest)
            $done++
            Show-Progress $activity $done $files.Count
        }
        foreach ($dir in $emptyDirs) {
            [void] $archive.CreateEntry(([IO.Path]::GetRelativePath($Folder, $dir) -replace '\\', '/') + '/')
        }
    }
    catch {
        $archive.Dispose()
        $archive = $null
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        throw
    }
    finally {
        if ($archive) { $archive.Dispose() }
        Complete-Progress $activity
    }
    Write-Ok "$zip ($('{0:N0}' -f $files.Count) files, $([Math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)) MB)"
    $zip
}

# Unpacks an export .zip into a new temp folder, file by file for the progress bar; returns the folder (the caller
# removes it). Entries pointing outside the folder (../) are refused.
function Expand-ExportZip([string] $Zip) {
    $temp = Join-Path ([IO.Path]::GetTempPath()) "dlab-migrate-$([guid]::NewGuid())"
    Write-Step "unpacking $Zip → $temp"
    $activity = "unpacking $(Split-Path $Zip -Leaf)"
    $root = [IO.Path]::GetFullPath($temp) + [IO.Path]::DirectorySeparatorChar
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $entries = $archive.Entries
        $done = 0
        foreach ($entry in $entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $temp $entry.FullName))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { Stop-Install "$Zip has an entry outside the folder: $($entry.FullName)" }
            if ($entry.FullName.EndsWith('/')) {
                [void] [IO.Directory]::CreateDirectory($target)
            }
            else {
                [void] [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            }
            $done++
            Show-Progress $activity $done $entries.Count
        }
    }
    finally {
        $archive.Dispose()
        Complete-Progress $activity
    }
    $temp
}

# "2 profiles, 2026-09-24 10:15 from DESKTOP-1" for a manifest entry.
function Get-EntryText($Entry) {
    "$(Get-ProfileCountText $Entry.profiles), $($Entry.exportedAt) from $($Entry.computer)"
}


######
###### ACTIONS
######

function Show-Programs([object[]] $Catalogue, [string] $Folder) {
    $manifest = if ($Folder) { Read-Manifest $Folder }
    if ($Folder -and -not $manifest) { Write-Warn "no $ManifestName in $Folder (not an export folder)" }
    foreach ($program in $Catalogue) {
        $state = Get-ProgramState $program
        $here = "$($state.Text)$(if ($state.Profiles) { " ($($state.Profiles -join ', '))" })"
        if ($manifest) {
            $entry = $manifest.programs[$program.Name]
            $exported = if ($entry) { "export: $(Get-EntryText $entry)" } else { 'export: -' }
            '  {0,-10} {1,-36} {2,-44} {3}' -f $program.Name, $here, $exported, $program.Label
        }
        else {
            '  {0,-10} {1,-36} {2}' -f $program.Name, $here, $program.Label
        }
    }
}

function Invoke-Export([object[]] $Catalogue, [string] $Folder, [string[]] $Names) {
    $manifest = Read-Manifest $Folder
    if (-not $manifest -and (Test-Path -LiteralPath $Folder) -and (Get-ChildItem -LiteralPath $Folder -Force | Select-Object -First 1)) {
        Stop-Install "$Folder is not empty and has no ${ManifestName}: pick a new or empty folder"
    }
    $states = @{}
    foreach ($program in $Catalogue) { $states[$program.Name] = Get-ProgramState $program }

    if (-not $Names) {
        if ([Console]::IsInputRedirected) { Stop-Install 'no terminal: pass program names (see --list)' }
        $rows = foreach ($program in $Catalogue) {
            $state = $states[$program.Name]
            [pscustomobject] @{ Name = $program.Name; State = $state.Text; Label = $program.Label; Available = $state.Code -eq 0; Selected = $state.Code -eq 0 }
        }
        if (-not ($rows | Where-Object Available)) {
            Write-Warn 'no program has data to export on this machine'
            return
        }
        $choice = Select-FromChecklist $rows 'export'
        if ($choice.Cancelled) {
            Write-Warn 'export: cancelled, nothing changed'
            return
        }
        $Names = $choice.Names
    }
    $Names = @(foreach ($name in $Names) {
        if ($states[$name].Code -eq 0) { $name }
        else { Write-Warn "${name}: nothing to export ($($states[$name].Text)), skipped" }
    })
    if (-not $Names) {
        Write-Ok 'nothing to export'
        return
    }
    Assert-Closed $states $Names

    if ($DotfilesDryRun) {
        foreach ($name in $Names) {
            $state = $states[$name]
            Write-Would "export ${name}: $($state.Profiles -join ', ') from $($state.Source) → $(Join-Path $Folder $name)"
        }
        if ($Zip) { Write-Would "pack $Folder into $(Join-Path $Folder (Split-Path $Folder -Leaf))-<computer>-<date>.zip" }
        return
    }

    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    if (-not $manifest) { $manifest = [ordered] @{ programs = [ordered] @{} } }
    $failed = @()
    $position = 0
    foreach ($name in $Names) {
        $position++
        $target = Join-Path $Folder $name
        Write-Step "[$position/$($Names.Count)] export $name"
        try {
            $profiles = @(& (Get-Program $Catalogue $name).Path export $target)
            $manifest.programs[$name] = [ordered] @{
                exportedAt = Get-Date -Format 'yyyy-MM-dd HH:mm'
                computer   = $env:COMPUTERNAME
                user       = $env:USERNAME
                source     = $states[$name].Source
                profiles   = $profiles
            }
            Write-Ok "${name}: $(Get-ProfileCountText $profiles) ($($profiles -join ', ')) → $target"
        }
        catch {
            Write-Warn "export $name failed: $($_.Exception.Message)"
            # A half-copied folder must not be imported: out of the manifest.
            $manifest.programs.Remove($name)
            $failed += $name
        }
        $manifest.updatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $manifest.dotfiles = Get-DotfilesVersion
        Save-Manifest $Folder $manifest
    }
    if ($failed) { Stop-Install "failed exports: $($failed -join ' ')" }
    if ($Zip) {
        $zipFile = New-ExportZip $Folder
        Write-Ok "export done: copy $zipFile to the other machine, there: dlab-migrate-import <that .zip>"
        return
    }
    Write-Ok "export done: $Folder (copy it to the other machine, there: dlab-migrate-import$(if ($Folder -ne $DefaultFolder) { " <folder>" }))"
}

function Invoke-Import([object[]] $Catalogue, [string] $Folder, [string[]] $Names) {
    $manifest = Read-Manifest $Folder
    if (-not $manifest) { Stop-Install "no $ManifestName in $Folder (not an export folder; made by dlab-migrate-export)" }
    $inExport = @($manifest.programs.Keys | Where-Object { Test-Path -LiteralPath (Join-Path $Folder $_) -PathType Container })
    foreach ($name in $inExport | Where-Object { -not (Get-Program $Catalogue $_) }) {
        Write-Warn "${name} is in the export, but there is no migrate\NN-$name.ps1 here: skipped"
    }

    if (-not $Names) {
        if ([Console]::IsInputRedirected) { Stop-Install 'no terminal: pass program names (see --list <folder>)' }
        $rows = foreach ($program in $Catalogue) {
            $present = $program.Name -in $inExport
            $state = if ($present) { Get-ProfileCountText $manifest.programs[$program.Name].profiles } else { 'not in export' }
            [pscustomobject] @{ Name = $program.Name; State = $state; Label = $program.Label; Available = $present; Selected = $present }
        }
        if (-not ($rows | Where-Object Available)) {
            Write-Warn "nothing in $Folder that can be imported"
            return
        }
        $choice = Select-FromChecklist $rows 'import'
        if ($choice.Cancelled) {
            Write-Warn 'import: cancelled, nothing changed'
            return
        }
        $Names = $choice.Names
    }
    foreach ($name in $Names | Where-Object { $_ -notin $inExport }) {
        Stop-Install "$name is not in the export $Folder (there: $(if ($inExport) { $inExport -join ' ' } else { 'nothing' }))"
    }
    if (-not $Names) {
        Write-Ok 'nothing to import'
        return
    }
    $states = @{}
    foreach ($name in $Names) { $states[$name] = Get-ProgramState (Get-Program $Catalogue $name) }
    Assert-Closed $states $Names

    Write-Step "import from $Folder"
    foreach ($name in $Names) {
        $entry = $manifest.programs[$name]
        $gone = @($states[$name].Profiles | Where-Object { $_ -notin $entry.profiles })
        Write-Host "  ${name}: $($states[$name].Source) ← $($entry.profiles -join ', ') ($($entry.exportedAt) from $($entry.computer))"
        if ($gone) { Write-Host "    profiles only here, removed: $($gone -join ', ')" -ForegroundColor Yellow }
    }
    Write-Warn 'all their data here is replaced: settings, profiles, saved passwords and cookies (sign in again afterwards)'

    if ($DotfilesDryRun) {
        foreach ($name in $Names) { Write-Would "replace $($states[$name].Source) with $(Join-Path $Folder $name)" }
        return
    }
    if (-not $AssumeYes) {
        if ([Console]::IsInputRedirected) { Stop-Install 'no terminal to ask: add --yes' }
        if ((Read-Host 'Type yes to replace') -ne 'yes') {
            Write-Warn 'import: cancelled, nothing changed'
            return
        }
    }

    $failed = @()
    $position = 0
    foreach ($name in $Names) {
        $position++
        Write-Step "[$position/$($Names.Count)] import $name"
        try {
            & (Get-Program $Catalogue $name).Path import (Join-Path $Folder $name)
            Write-Ok "${name}: $($states[$name].Source) replaced"
        }
        catch {
            Write-Warn "import $name failed: $($_.Exception.Message)"
            $failed += $name
        }
    }
    if ($failed) { Stop-Install "failed imports: $($failed -join ' ')" }
    Write-Ok 'import done: start the programs (saved passwords and cookies are not there: sign in again)'
}


######
###### MAIN
######

if ($Arguments -contains '--dry-run') {
    $DotfilesDryRun = $true
    Write-Warn 'dry run: nothing is changed'
}
if ($Arguments -contains '--yes') { $AssumeYes = $true }
if ($Arguments -contains '--zip') { $Zip = $true }
$Arguments = @($Arguments | Where-Object { $_ -notin '--dry-run', '--yes', '--zip' })

$catalogue = @(Get-Programs)
$first = if ($Arguments) { $Arguments[0] } else { '' }

switch -Regex ($first) {
    '^--list$' {
        Show-Programs $catalogue $(if ($Arguments.Count -gt 1) { Resolve-Folder $Arguments[1] } elseif (Test-Path -LiteralPath $DefaultFolder) { $DefaultFolder })
        break
    }
    '^(-h|--help)$' {
        Get-Help $PSCommandPath -Full | Out-String | Write-Host
        break
    }
    '^(export|import)$' {
        # The folder is optional: no second argument, or a program name there, means the default folder.
        $rest = @($Arguments | Select-Object -Skip 1)
        if ($rest -and -not (Get-Program $catalogue $rest[0])) {
            $folder = Resolve-Folder $rest[0]
            $rest = @($rest | Select-Object -Skip 1)
        }
        else {
            $folder = $DefaultFolder
        }
        if ($first -eq 'export') { Write-Step "export into $folder" }
        $names = @(Resolve-ProgramNames $catalogue $rest)
        if ($first -eq 'export') {
            if (Test-ZipFile $folder) { Stop-Install "export goes into a folder, not into $folder (--zip packs the folder afterwards)" }
            Invoke-Export $catalogue $folder $names
        }
        elseif (Test-ZipFile $folder) {
            $temp = Expand-ExportZip $folder
            try { Invoke-Import $catalogue $temp $names }
            finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
        }
        else {
            Invoke-Import $catalogue $folder $names
        }
        break
    }
    default {
        Stop-Install $Usage
    }
}
