# bitwarden-store: shared code of the restore step (scripts\85-bitwarden-store.ps1) and the store commands (store.ps1).
# The secure note "bitwarden-store" holds the files as attachments; its attachment _manifest.txt says what to do with
# each (actions: copy, font, unzip). The repo knows only the actions; which files exist is known only to Bitwarden.
# Dot-source after lib.ps1. Same rules as ubuntu/scripts/store-lib.sh.

$StoreItemName = 'bitwarden-store'
$StoreManifest = '_manifest.txt'
$StoreFormat   = '1'
$StoreSystem   = 'windows'
$StoreMaxBytes = 100MB   # Bitwarden's limit per attachment

$StoreTemplate = @'
# bitwarden-store manifest (see README.md, "Private files")
format: 1

# attachment    | system  | action | action params          | extra
'@

# State of the open store: the item, its attachments by name, downloads, temp folder.
$Store = @{ Item = $null; Attachments = @{}; Duplicates = @{}; Downloaded = @{}; Tmp = $null }
$StoreSummary = [ordered] @{ ok = 0; updated = 0; skipped = 0; errors = 0 }

function Write-StoreError([string] $Message) {
    $StoreSummary.errors++
    Write-Warn $Message
}


######
###### SESSION AND TEMP FOLDER
######

# Temp folder for downloads and uploads: ~/.dotfiles/local/tmp/bw-<guid> (/local/ is in .gitignore).
# Leftovers of a run that was killed before its clean-up (e.g. power off) are removed first.
function Start-StoreTemp {
    $root = Join-Path $DotfilesLocalDir 'tmp'
    Get-ChildItem -Path $root -Filter 'bw-*' -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $Store.Tmp = Join-Path $root "bw-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Force -Path $Store.Tmp | Out-Null
}

# Locks bw and removes the temp folder; for a finally block.
function Stop-Store {
    Close-BitwardenSession
    if ($Store.Tmp) { Remove-Item -LiteralPath $Store.Tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# A fresh subfolder of the temp folder (the file name of an upload is its attachment name).
function New-StoreTempDir {
    $dir = Join-Path $Store.Tmp ([guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dir
}


######
###### ITEM AND ATTACHMENTS
######

# Reads the note (by id after a change, else by name). $true when it exists.
function Update-StoreItem {
    if ($Store.Item) {
        $Store.Item = bw get item $Store.Item.id | ConvertFrom-Json
        if ($LASTEXITCODE -or -not $Store.Item) { throw "bw get item $StoreItemName failed" }
    }
    else {
        $Store.Item = Get-BitwardenItem $StoreItemName
        if (-not $Store.Item) { return $false }
    }
    # Bitwarden allows two attachments with the same name; such a name cannot be used.
    $Store.Attachments = @{}
    $Store.Duplicates = @{}
    foreach ($group in @($Store.Item.attachments) | Where-Object { $_ } | Group-Object fileName) {
        if ($group.Count -gt 1) { $Store.Duplicates[$group.Name] = $group.Count }
        else { $Store.Attachments[$group.Name] = $group.Group[0] }
    }
    $true
}

# Creates the empty secure note (after asking). $true when it exists afterwards.
function New-StoreItem {
    $answer = Read-Host "Bitwarden has no item '$StoreItemName'. Create it (an empty secure note)? (y/N)"
    if ($answer -notmatch '^(y|yes)$') { return $false }
    $item = @{ type = 2; name = $StoreItemName; notes = $null; secureNote = @{ type = 0 }; favorite = $false }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($item | ConvertTo-Json -Compress)))
    $Store.Item = bw create item $encoded | ConvertFrom-Json
    if ($LASTEXITCODE -or -not $Store.Item) { throw "bw create item $StoreItemName failed" }
    Write-Ok "created $StoreItemName"
    Update-StoreItem
}

function Assert-StoreName([string] $Name) {
    if ($Store.Duplicates.ContainsKey($Name)) {
        throw "$StoreItemName has $($Store.Duplicates[$Name]) attachments named $Name; remove the extra ones in Bitwarden"
    }
}

# Downloads an attachment once (per attachment id) into the temp folder; its path, or $null when there is none.
function Get-StoreFile([string] $Name) {
    Assert-StoreName $Name
    $attachment = $Store.Attachments[$Name]
    if (-not $attachment) { return $null }
    if ($Store.Downloaded.ContainsKey($attachment.id)) { return $Store.Downloaded[$attachment.id] }
    $path = Join-Path (New-StoreTempDir) $Name
    bw get attachment $attachment.id --itemid $Store.Item.id --output $path | Out-Null
    if ($LASTEXITCODE -or -not (Test-Path -LiteralPath $path)) { throw "bw get attachment $Name failed" }
    $Store.Downloaded[$attachment.id] = $path
    $path
}

# Uploads $Path as the attachment $Name (bw names it after the file, so a copy with that name is uploaded).
function Add-StoreAttachment([string] $Path, [string] $Name) {
    if ((Get-Item -LiteralPath $Path).Length -gt $StoreMaxBytes) { throw "$Name is larger than 100 MB (Bitwarden's limit)" }
    $upload = Join-Path (New-StoreTempDir) $Name
    Copy-Item -LiteralPath $Path -Destination $upload
    bw create attachment --file $upload --itemid $Store.Item.id | Out-Null
    if ($LASTEXITCODE) { throw "bw create attachment $Name failed" }
    [void] (Update-StoreItem)
}

function Remove-StoreAttachment([string] $Name) {
    Assert-StoreName $Name
    bw delete attachment $Store.Attachments[$Name].id --itemid $Store.Item.id | Out-Null
    if ($LASTEXITCODE) { throw "bw delete attachment $Name failed" }
    [void] (Update-StoreItem)
}

# Replaces the attachment $Name with $NewPath and keeps the version it replaces as "$Name.prev" (one step back).
# $NewPath empty: removes $Name, still keeping "$Name.prev". $false when the content is the same (nothing done).
# Order: delete the old one, then upload the new one (never two attachments with the same name). If the upload
# fails, the old version is "$Name.prev" and the new file is still at $NewPath.
function Set-StoreFile([string] $Name, [string] $NewPath) {
    $current = Get-StoreFile $Name
    if ($NewPath -and $current -and (Test-SameFile $NewPath $current)) { return $false }
    if ($current) {
        if ($Store.Attachments.ContainsKey("$Name.prev")) { Remove-StoreAttachment "$Name.prev" }
        Add-StoreAttachment $current "$Name.prev"
        Remove-StoreAttachment $Name
    }
    if ($NewPath) {
        try {
            Add-StoreAttachment $NewPath $Name
        }
        catch {
            throw "$($_.Exception.Message). The previous version is $Name.prev in $StoreItemName; the new file is still at ${NewPath}: run the command again"
        }
    }
    $true
}


######
###### MANIFEST
######

# Parses a manifest file:   attachment | system | action | action params | extra
# Whole-line comments (#) and blank lines are ignored. Returns Format, Entries (all systems) and Problems.
function Read-StoreManifest([string] $Path) {
    $result = [pscustomobject] @{ Format = $null; Entries = @(); Problems = @() }
    $number = 0
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $number++
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -match '^format\s*:\s*(\S+)$') { $result.Format = $Matches[1]; continue }

        $problem = { param($Text) $result.Problems += "line ${number}: $Text ($line)" }
        $columns = @(($line -split '\|', 5).ForEach({ $_.Trim() }))
        while ($columns.Count -lt 5) { $columns += '' }
        $entry = [pscustomobject] @{
            Number = $number; Line = $line; Attachment = $columns[0]; System = $columns[1].ToLower()
            Action = $columns[2].ToLower(); Param = $columns[3]; Host = @(); When = 'always'; Mode = $null
        }
        if (-not $entry.Attachment -or -not $entry.Action) { & $problem 'incomplete line'; continue }
        if ($entry.System -notin 'windows', 'linux', 'all') { & $problem "unknown system '$($entry.System)'"; continue }
        if ($entry.Action -notin 'copy', 'font', 'unzip') { & $problem "unknown action '$($entry.Action)'"; continue }
        if ($entry.Action -eq 'copy' -and -not $entry.Param) { & $problem 'copy needs a target path'; continue }
        if ($entry.Action -eq 'unzip' -and -not $entry.Param) { & $problem 'unzip needs a target folder'; continue }
        if ($entry.Action -eq 'font' -and $entry.Param) { & $problem 'font takes no parameters'; continue }

        $bad = $null
        foreach ($option in $columns[4] -split '\s+' | Where-Object { $_ }) {
            $key, $value = $option -split '=', 2
            switch ($key.ToLower()) {
                'host' { $entry.Host = @($value -split ',' | Where-Object { $_ }) }
                'when' { if ($value -in 'always', 'missing') { $entry.When = $value } else { $bad = $option } }
                'mode' { if ($value -match '^[0-7]{3,4}$') { $entry.Mode = $value } else { $bad = $option } }
                default { $bad = $option }
            }
            if ($bad) { break }
        }
        if ($bad) { & $problem "bad option '$bad'"; continue }
        $result.Entries += $entry
    }
    if ($result.Format -ne $StoreFormat) {
        $found = if ($result.Format) { $result.Format } else { 'none' }
        $result.Problems = @("needs 'format: $StoreFormat' (found: $found)") + $result.Problems
    }
    $result
}

# The manifest lines that name $Name as their attachment (raw text, for showing and removing).
function Get-ManifestLinesFor([string] $Path, [string] $Name) {
    Get-Content -LiteralPath $Path | Where-Object {
        $line = $_.Trim()
        $line -and -not $line.StartsWith('#') -and ($line -split '\|', 2)[0].Trim() -eq $Name
    }
}

# Opens $Path in the editor until it is a valid manifest. $true: valid; $false: the user cancelled.
# Editor: $env:EDITOR, else VS Code (code --wait), else Notepad.
function Edit-StoreManifest([string] $Path) {
    while ($true) {
        # Start-Process: the editor gets the console (a console editor such as vim works) and nothing it prints
        # ends up in this function's result.
        $editor, $editorArgs = if ($env:EDITOR) { $env:EDITOR -split '\s+' }
                               elseif (Test-Command code) { 'code', '--wait' }
                               else { 'notepad.exe' }
        Start-Process -FilePath $editor -ArgumentList (@($editorArgs) + "`"$Path`"") -Wait -NoNewWindow

        $manifest = Read-StoreManifest $Path
        if (-not $manifest.Problems) { return $true }
        Write-Warn "$StoreManifest has problems:"
        $manifest.Problems | ForEach-Object { Write-Host "    $_" }
        if ((Read-Host 'Edit again? (Y/n; n cancels, nothing is saved)') -match '^(n|no)$') { return $false }
    }
}


######
###### ACTIONS (restore)
######

# ~ at the start means the home folder; %VARIABLES% are expanded. An absolute path comes back normalized
# (on Windows ~/a/b → C:\Users\<you>\a\b); a relative one unchanged, for the caller to reject.
function Expand-StorePath([string] $Path) {
    if ($Path -match '^~([\\/]|$)') { $Path = $HOME + $Path.Substring(1) }
    $Path = [Environment]::ExpandEnvironmentVariables($Path)
    if ([IO.Path]::IsPathFullyQualified($Path)) { [IO.Path]::GetFullPath($Path) } else { $Path }
}

function Test-SameFile([string] $A, [string] $B) {
    (Test-Path -LiteralPath $B) -and (Get-FileHash -LiteralPath $A).Hash -eq (Get-FileHash -LiteralPath $B).Hash
}

# Copy $Source to $Target; when the folder needs admin (e.g. Program Files), copy in an elevated process.
function Copy-WithElevation([string] $Source, [string] $Target) {
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $Target -Parent) | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Target -Force
        return
    }
    catch [UnauthorizedAccessException] {
        # no write access here: copy elevated below
    }
    Write-Step "administrator rights to write $Target (UAC)"
    $quote = { "'" + $args[0].Replace("'", "''") + "'" }
    $command = "New-Item -ItemType Directory -Force -Path $(& $quote (Split-Path $Target -Parent)) | Out-Null; " +
        "Copy-Item -LiteralPath $(& $quote $Source) -Destination $(& $quote $Target) -Force"
    $process = Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -Wait -PassThru -WindowStyle Hidden `
        -ArgumentList '-NoProfile', '-Command', $command
    if ($process.ExitCode) { throw "copy to $Target failed (exit code $($process.ExitCode))" }
}

# copy <path>: the attachment goes to <path>, overwritten when different (when=missing: only when there is none).
function Invoke-StoreCopy($Entry, [string] $Source) {
    $target = Expand-StorePath $Entry.Param
    if (-not [IO.Path]::IsPathFullyQualified($target)) { Write-StoreError "copy: not an absolute path: $($Entry.Param)"; return }
    if ((Test-Path -LiteralPath $target) -and ($Entry.When -eq 'missing' -or (Test-SameFile $Source $target))) {
        $StoreSummary.ok++
        Write-Ok "$target up to date"
        return
    }
    if ($DotfilesDryRun) { Write-Would "write $target from $($Entry.Attachment)"; return }
    Copy-WithElevation $Source $target
    $StoreSummary.updated++
    Write-Ok "$target updated from $($Entry.Attachment)"
}

# font: the .ttf/.otf attachment is installed for the current user (Fonts folder + HKCU registry).
function Invoke-StoreFont($Entry, [string] $Source) {
    if ($Entry.Attachment -notmatch '\.(ttf|otf)$') { Write-StoreError "font: not a .ttf/.otf file: $($Entry.Attachment)"; return }
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $target  = Join-Path $fontDir $Entry.Attachment
    # Registered means any value points at the file, whatever its name (earlier installs used other names).
    $registered = (Test-Path $regPath) -and
        ($target -in @((Get-ItemProperty -Path $regPath).PSObject.Properties | ForEach-Object { "$($_.Value)" }))
    if ($registered -and (Test-SameFile $Source $target)) {
        $StoreSummary.ok++
        Write-Ok "font $($Entry.Attachment) installed"
        return
    }
    if ($DotfilesDryRun) { Write-Would "install font $($Entry.Attachment)"; return }
    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    try {
        Copy-Item -LiteralPath $Source -Destination $target -Force
    }
    catch {
        Write-StoreError "font $($Entry.Attachment): $($_.Exception.Message) (in use? close the apps using it, or sign out, and run again)"
        return
    }
    if (-not $registered) {
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        $kind = if ($target -match '\.otf$') { 'OpenType' } else { 'TrueType' }
        $regName = '{0} ({1})' -f [IO.Path]::GetFileNameWithoutExtension($target), $kind
        New-ItemProperty -Path $regPath -Name $regName -Value $target -PropertyType String -Force | Out-Null
    }
    $StoreSummary.updated++
    Write-Ok "font $($Entry.Attachment) installed (restart Windows Terminal / VS Code to use it)"
}


# unzip <folder>: the .zip attachment is unpacked into <folder>; files that differ are overwritten, the others and files
# that are not in the zip are left alone. when=missing: only when the folder does not exist yet.
function Invoke-StoreUnzip($Entry, [string] $Source) {
    if ($Entry.Attachment -notmatch '\.zip$') { Write-StoreError "unzip: not a .zip file: $($Entry.Attachment)"; return }
    $target = Expand-StorePath $Entry.Param
    if (-not [IO.Path]::IsPathFullyQualified($target)) { Write-StoreError "unzip: not an absolute path: $($Entry.Param)"; return }
    if ((Test-Path -LiteralPath $target) -and $Entry.When -eq 'missing') {
        $StoreSummary.ok++
        Write-Ok "$target up to date"
        return
    }
    # Unpacked into the temp folder first; .NET refuses entries that would land outside it. (Not Expand-Archive:
    # its progress bar hangs in some terminals, and it is much slower.)
    $unpacked = Join-Path (New-StoreTempDir) 'unzip'
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($Source, $unpacked)
    }
    catch {
        Write-StoreError "unzip: $($Entry.Attachment) could not be unpacked: $($_.Exception.Message)"
        return
    }
    $changed = @(foreach ($file in Get-ChildItem -LiteralPath $unpacked -Recurse -File -Force) {
        $destination = Join-Path $target ([IO.Path]::GetRelativePath($unpacked, $file.FullName))
        if (-not (Test-SameFile $file.FullName $destination)) { [pscustomobject] @{ Source = $file.FullName; Target = $destination } }
    })
    if (-not $changed) {
        $StoreSummary.ok++
        Write-Ok "$target up to date"
        return
    }
    if ($DotfilesDryRun) { Write-Would "update $($changed.Count) file(s) in $target from $($Entry.Attachment)"; return }
    foreach ($file in $changed) {
        New-Item -ItemType Directory -Force -Path (Split-Path $file.Target -Parent) | Out-Null
        Copy-Item -LiteralPath $file.Source -Destination $file.Target -Force
    }
    $StoreSummary.updated++
    Write-Ok "$target updated from $($Entry.Attachment) ($($changed.Count) file(s))"
}


######
###### RESTORE
######

# Applies the manifest for this system and computer (the session and the item must be open). Prints a summary.
function Invoke-StoreRestore {
    foreach ($key in @($StoreSummary.Keys)) { $StoreSummary[$key] = 0 }
    $manifestPath = Get-StoreFile $StoreManifest
    if (-not $manifestPath) {
        Write-Warn "$StoreItemName has no attachment $StoreManifest; nothing done (create it: dlab-store-manifest-edit)"
        return
    }
    $manifest = Read-StoreManifest $manifestPath
    if ($manifest.Format -ne $StoreFormat) {
        Write-StoreError "manifest: needs 'format: $StoreFormat' (found: $(if ($manifest.Format) { $manifest.Format } else { 'none' })); nothing done"
    }
    else {
        $manifest.Problems | ForEach-Object { Write-StoreError "manifest: $_" }
        foreach ($entry in $manifest.Entries) {
            if ($entry.System -notin $StoreSystem, 'all') { $StoreSummary.skipped++; continue }
            if ($entry.Host -and $env:COMPUTERNAME -notin $entry.Host) { $StoreSummary.skipped++; continue }
            try {
                $source = Get-StoreFile $entry.Attachment
                if (-not $source) { Write-StoreError "$StoreItemName has no attachment $($entry.Attachment) (manifest line $($entry.Number))"; continue }
                switch ($entry.Action) {
                    'copy' { Invoke-StoreCopy $entry $source }
                    'font'  { Invoke-StoreFont $entry $source }
                    'unzip' { Invoke-StoreUnzip $entry $source }
                }
            }
            catch {
                Write-StoreError "$($entry.Attachment): $($_.Exception.Message)"
            }
        }
    }
    $line = "${StoreItemName}: $($StoreSummary.ok) ok, $($StoreSummary.updated) updated, " +
        "$($StoreSummary.skipped) skipped (other system or computer), $($StoreSummary.errors) errors"
    if ($StoreSummary.errors) { Write-Warn $line } else { Write-Ok $line }
}

# The git name and e-mail are not in the repo (see git\.gitconfig): without the store, commits fail.
function Test-GitIdentity {
    if ((Test-Command git) -and -not (git config --get user.email)) {
        Write-Warn "git has no user.email: it comes from $StoreItemName (~/.dotfiles/local/.gitconfig.user); commits fail until then"
    }
}
