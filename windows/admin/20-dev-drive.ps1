# Dev Drive: a ReFS volume for code (W:, label Work, 195 GB taken from C:), trusted so Defender scans it in performance mode.
# Skips when the letter already is a Dev Drive. Asks before shrinking C:. Change size/letter: admin.ps1 -DevDriveSizeGB 250
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

$letter = $Options.DevDriveLetter
$drive  = "${letter}:"

# fsutil output: "This is a trusted developer volume." / "This is a developer volume." / "This is not a developer volume."
function Get-DevDriveState {
    $text = (fsutil devdrv query $drive 2>&1 | Out-String)
    if ($text -match 'is a trusted developer volume') { 'trusted' }
    elseif ($text -match 'is a developer volume') { 'untrusted' }
    else { 'none' }
}

function Set-DevDriveTrust {
    if ($DryRun) { Write-Ok "would trust $drive (fsutil devdrv trust $drive)"; return }
    fsutil devdrv trust $drive | Out-Null
    if ((Get-DevDriveState) -ne 'trusted') { Stop-Install "fsutil devdrv trust $drive did not take effect" }
    Write-Ok "$drive trusted"
}

$volume = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue
if ($volume) {
    switch (Get-DevDriveState) {
        'trusted'   { Write-Ok "$drive is a trusted Dev Drive ($($volume.FileSystemLabel), $([math]::Round($volume.Size / 1GB)) GB)" }
        'untrusted' { Set-DevDriveTrust }
        default     { Write-Warn "$drive is in use by a $($volume.FileSystem) volume that is not a Dev Drive; left alone" }
    }
    return
}

if ([Environment]::OSVersion.Version.Build -lt 22621) {
    Stop-Install 'Dev Drive needs Windows 11 22H2 (build 22621) or newer'
}

$size      = [int64] $Options.DevDriveSizeGB * 1GB
$system    = Get-Partition -DriveLetter C
$supported = Get-PartitionSupportedSize -DriveLetter C
$newCSize  = $system.Size - $size
$maxShrink = [math]::Floor(($system.Size - $supported.SizeMin) / 1GB)

if ($newCSize -lt $supported.SizeMin) {
    Stop-Install "C: can give at most $maxShrink GB now, $($Options.DevDriveSizeGB) GB asked (free space, or unmovable files such as the page file / hibernation / restore points)"
}

Write-Host @"

    Dev Drive plan:
      C:  $([math]::Round($system.Size / 1GB)) GB → $([math]::Round($newCSize / 1GB)) GB (it can give at most $maxShrink GB)
      ${drive} new ReFS Dev Drive, $($Options.DevDriveSizeGB) GB, label "$($Options.DevDriveLabel)", trusted

"@
$bitlocker = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
if ($bitlocker -and $bitlocker.ProtectionStatus -eq 'On') {
    Write-Warn 'BitLocker is on for C:: make sure its recovery key is saved (Microsoft account or printed) before resizing'
}
if ($DryRun) {
    Write-Ok 'dry run: C: not resized'
    return
}

$answer = Read-Host "Type yes to shrink C: and create $drive"
if ($answer -ne 'yes') {
    Write-Warn 'Dev Drive skipped (answer was not yes)'
    return
}

Resize-Partition -DriveLetter C -Size $newCSize
New-Partition -DiskNumber $system.DiskNumber -UseMaximumSize -DriveLetter $letter |
    Format-Volume -DevDrive -NewFileSystemLabel $Options.DevDriveLabel -Confirm:$false |
    Out-Null
Write-Ok "$drive created"
Set-DevDriveTrust
