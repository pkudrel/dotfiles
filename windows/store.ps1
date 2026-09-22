#Requires -Version 7.0
<#
.SYNOPSIS
  Changes the Bitwarden secure note "Bitwarden-store" (the private files that install step bitwarden-store restores).
.DESCRIPTION
  store.ps1 list                  attachments, the manifest lines that use them, and what does not match
  store.ps1 add <file>            new attachment + its manifest line (the manifest opens in the editor)
  store.ps1 replace <file>        new version of an attachment (the attachment name is the file name)
  store.ps1 remove <name>         removes an attachment and its manifest lines (asks first)
  store.ps1 manifest-edit         edit _manifest.txt (checked before it is saved)

  One master password prompt per command (Enter cancels). A replaced or removed attachment is kept as
  "<name>.prev" (one step back). After add, replace, remove and manifest-edit this machine is updated
  (the bitwarden-store step), in the same session. Editor: $env:EDITOR, else VS Code, else Notepad.
  dlab commands: dlab-store-list, -add, -replace, -remove, -manifest-edit.
#>
param(
    [Parameter(Position = 0)] [string] $Command,
    [Parameter(Position = 1)] [string] $Target
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\lib.ps1')
. (Join-Path $PSScriptRoot 'scripts\store-lib.ps1')

$usage = 'usage: store.ps1 list | add <file> | replace <file> | remove <name> | manifest-edit'
if ($Command -notin 'list', 'add', 'replace', 'remove', 'manifest-edit') { Stop-Install $usage }
if ($Command -in 'add', 'replace', 'remove' -and -not $Target) { Stop-Install $usage }

# add / replace: the local file, checked before the password prompt.
if ($Command -in 'add', 'replace') {
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { Stop-Install "file not found: $Target" }
    $file = (Resolve-Path -LiteralPath $Target).Path
    $name = Split-Path $file -Leaf
    if ($name -eq $StoreManifest -or $name -like '*.prev') {
        Stop-Install "$name is reserved (${StoreManifest}: dlab-store-manifest-edit; *.prev: previous versions)"
    }
}


######
###### COMMANDS
######

function Invoke-List {
    $manifestPath = Get-StoreFile $StoreManifest
    $manifest = if ($manifestPath) { Read-StoreManifest $manifestPath }
    $entries = if ($manifest) { $manifest.Entries } else { @() }

    $all = @($Store.Item.attachments) | Where-Object { $_ } | Sort-Object fileName
    Write-Step "${StoreItemName}: $($all.Count) attachment(s)"
    foreach ($attachment in $all) {
        $size = if ($attachment.sizeName) { $attachment.sizeName } else { "$($attachment.size) B" }
        $uses = @($entries | Where-Object Attachment -eq $attachment.fileName |
            ForEach-Object {
                $options = @(if ($_.Host) { 'host=' + ($_.Host -join ',') }; if ($_.When -ne 'always') { "when=$($_.When)" }; if ($_.Mode) { "mode=$($_.Mode)" })
                (@($_.System, $_.Action, $_.Param) + $options | Where-Object { $_ }) -join ' '
            })
        $note = if ($attachment.fileName -eq $StoreManifest) { '(manifest)' }
                elseif ($attachment.fileName -like '*.prev') { '(previous version)' }
                elseif ($Store.Duplicates.ContainsKey($attachment.fileName)) { '(DUPLICATE NAME: remove the extra one in Bitwarden)' }
                elseif (-not $uses) { '(not used by the manifest)' }
                else { $uses -join '; ' }
        Write-Host ('  {0,-28} {1,10}  {2}' -f $attachment.fileName, $size, $note)
    }
    if (-not $manifestPath) { Write-Warn "no $StoreManifest yet: dlab-store-manifest-edit" }
    foreach ($entry in $entries | Where-Object { -not $Store.Attachments.ContainsKey($_.Attachment) -and -not $Store.Duplicates.ContainsKey($_.Attachment) }) {
        Write-Warn "manifest line $($entry.Number) uses a missing attachment: $($entry.Attachment)"
    }
    if ($manifest) { $manifest.Problems | ForEach-Object { Write-Warn "manifest: $_" } }
}

# The manifest to edit: a copy of the current one, or the template when there is none.
function New-ManifestDraft {
    $draft = Join-Path (New-StoreTempDir) $StoreManifest
    $current = Get-StoreFile $StoreManifest
    if ($current) { Copy-Item -LiteralPath $current -Destination $draft } else { Set-Content -LiteralPath $draft -Value $StoreTemplate }
    $draft
}

# Saves an edited manifest (the old one stays as _manifest.txt.prev). $true when it changed.
function Save-Manifest([string] $Draft) {
    if (Set-StoreFile $StoreManifest $Draft) { Write-Ok "$StoreManifest saved"; return $true }
    Write-Ok "$StoreManifest unchanged"
    $false
}

function Invoke-Add {
    Assert-StoreName $name
    if ($Store.Attachments.ContainsKey($name)) { Stop-Install "$StoreItemName already has ${name}: dlab-store-replace $Target" }
    $draft = New-ManifestDraft
    Add-Content -LiteralPath $draft -Value "$name | $StoreSystem | copy | "
    Write-Step "complete the line for $name in $StoreManifest (action params: the target path), save and close the editor"
    if (-not (Edit-StoreManifest $draft)) { Write-Warn 'cancelled, nothing saved'; return $false }
    if (-not ((Read-StoreManifest $draft).Entries | Where-Object Attachment -eq $name)) {
        Write-Warn "no manifest line uses ${name}: it is stored but not restored anywhere"
    }
    Add-StoreAttachment $file $name
    Write-Ok "$name added to $StoreItemName"
    [void] (Save-Manifest $draft)
    $true
}

function Invoke-Replace {
    Assert-StoreName $name
    if (-not $Store.Attachments.ContainsKey($name)) {
        if (-not $Store.Attachments.ContainsKey("$name.prev")) {
            Stop-Install "$StoreItemName has no attachment $name (new file: dlab-store-add $Target)"
        }
        # An earlier replace stopped after the delete: only the upload is missing.
        Add-StoreAttachment $file $name
        Write-Ok "$name uploaded (the earlier replace had stopped; previous version: $name.prev)"
        return $true
    }
    if (-not (Set-StoreFile $name $file)) { Write-Ok "$name unchanged (same content)"; return $false }
    Write-Ok "$name replaced (previous version: $name.prev)"
    $true
}

function Invoke-Remove {
    $name = $Target
    if ($name -eq $StoreManifest) { Stop-Install "$StoreManifest cannot be removed (edit it: dlab-store-manifest-edit)" }
    Assert-StoreName $name
    if (-not $Store.Attachments.ContainsKey($name)) { Stop-Install "$StoreItemName has no attachment $name (see dlab-store-list)" }
    $manifestPath = Get-StoreFile $StoreManifest
    $lines = if ($manifestPath) { @(Get-ManifestLinesFor $manifestPath $name) } else { @() }
    Write-Step "remove $name from $StoreItemName (kept as $name.prev)"
    if ($lines) { Write-Host '  and these manifest lines:'; $lines | ForEach-Object { Write-Host "    $_" } }
    if ((Read-Host 'Continue? (y/N)') -notmatch '^(y|yes)$') { Write-Warn 'cancelled, nothing changed'; return $false }

    [void] (Set-StoreFile $name '')
    Write-Ok "$name removed (previous version: $name.prev)"
    if ($lines) {
        $draft = Join-Path (New-StoreTempDir) $StoreManifest
        Get-Content -LiteralPath $manifestPath | Where-Object { $_ -notin $lines } | Set-Content -LiteralPath $draft
        [void] (Save-Manifest $draft)
    }
    $true
}

function Invoke-ManifestEdit {
    $draft = New-ManifestDraft
    if (-not (Edit-StoreManifest $draft)) { Write-Warn 'cancelled, nothing saved'; return $false }
    Save-Manifest $draft
}


######
###### RUN
######

if (-not (Open-BitwardenSession)) {
    Write-Warn 'cancelled (no master password)'
    return
}
try {
    Start-StoreTemp
    if (-not (Update-StoreItem)) {
        if ($Command -notin 'add', 'manifest-edit' -or -not (New-StoreItem)) {
            Write-Warn "Bitwarden has no item '$StoreItemName'; nothing done"
            return
        }
    }
    $changed = switch ($Command) {
        'list'          { Invoke-List; $false }
        'add'           { Invoke-Add }
        'replace'       { Invoke-Replace }
        'remove'        { Invoke-Remove }
        'manifest-edit' { Invoke-ManifestEdit }
    }
    if ($changed -eq $true) {
        Write-Step 'updating this machine (bitwarden-store)'
        Invoke-StoreRestore
    }
}
finally {
    Stop-Store
}
