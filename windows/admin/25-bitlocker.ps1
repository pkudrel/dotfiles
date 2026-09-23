# BitLocker: C: must be protected; the Dev Drive (W:) is encrypted like C: and unlocks automatically.
# Asks whether to save the recovery keys of all BitLocker drives to Bitwarden (bw CLI; never to a file or the screen).
# Only this step: admin.ps1 bitlocker
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')


######
###### DRIVES
######

function Test-RecoveryPassword($Volume) {
    [bool] ($Volume.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword')
}

$system = Get-BitLockerVolume -MountPoint 'C:'
if ($system.ProtectionStatus -ne 'On') {
    Write-Warn 'C: is not protected by BitLocker: Settings → Privacy & security → Device encryption, then: admin.ps1 bitlocker'
    return
}
if (Test-RecoveryPassword $system) { Write-Ok "C: protected ($($system.EncryptionMethod), recovery key present)" }
else { Write-Warn 'C: is protected but has no recovery key (add one: manage-bde -protectors -add C: -RecoveryPassword)' }

$drive = "$($Options.DevDriveLetter):"
$data = Get-BitLockerVolume -MountPoint $drive -ErrorAction SilentlyContinue
if (-not $data) {
    Write-Ok "no $drive (Dev Drive not created), nothing to encrypt"
}
elseif ($data.VolumeStatus -eq 'FullyDecrypted') {
    if ($DryRun) {
        Write-Would "encrypt $drive ($($system.EncryptionMethod), used space only) and unlock it automatically"
    }
    else {
        # Out-Null: Enable-BitLocker returns the new recovery password, which must not reach the screen.
        Enable-BitLocker -MountPoint $drive -EncryptionMethod $system.EncryptionMethod -UsedSpaceOnly -RecoveryPasswordProtector | Out-Null
        Enable-BitLockerAutoUnlock -MountPoint $drive | Out-Null
        Write-Ok "$drive encrypting in the background, unlocks automatically; save its recovery key (below)"
    }
}
else {
    Write-Ok "$drive $($data.VolumeStatus) ($($data.EncryptionMethod))"
    if (-not $data.AutoUnlockEnabled) {
        if ($DryRun) { Write-Would "turn on automatic unlock for $drive" }
        else {
            Enable-BitLockerAutoUnlock -MountPoint $drive | Out-Null
            Write-Ok "$drive unlocks automatically"
        }
    }
}


######
###### RECOVERY KEYS → BITWARDEN
######

# Secure note "bitwarden-bitlocker-<computer>" (computer name in lower case), one hidden field per drive; created or updated.
function Save-RecoveryKeysToBitwarden {
    $volumes = @(Get-BitLockerVolume | Where-Object { Test-RecoveryPassword $_ } | Sort-Object MountPoint)
    if (-not $volumes) {
        Write-Warn 'no drive has a BitLocker recovery key'
        return
    }

    if (-not (Open-BitwardenSession)) {
        Write-Warn 'Bitwarden skipped, recovery keys not saved (later: admin.ps1 bitlocker)'
        return
    }
    try {
        $name = "bitwarden-bitlocker-$($env:COMPUTERNAME.ToLower())"
        $fields = foreach ($volume in $volumes) {
            foreach ($protector in $volume.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword') {
                [ordered] @{ name = "$($volume.MountPoint) $($protector.KeyProtectorId)"; value = $protector.RecoveryPassword; type = 1 }
            }
        }
        $notes = @(
            "Computer: $env:COMPUTERNAME"
            "Saved: $(Get-Date -Format 'yyyy-MM-dd HH:mm') by dotfiles windows\admin\25-bitlocker.ps1"
            'Field name = drive and key ID (the ID Windows shows on the BitLocker recovery screen).'
        ) -join "`n"

        $existing = Get-BitwardenItem $name
        if ($existing) {
            $existing | Add-Member -NotePropertyName notes -NotePropertyValue $notes -Force
            $existing | Add-Member -NotePropertyName fields -NotePropertyValue @($fields) -Force
            $existing | ConvertTo-Json -Depth 10 | bw encode | bw edit item $existing.id | Out-Null
            if ($LASTEXITCODE) { Stop-Install 'bw edit item failed' }
            Write-Ok "Bitwarden: updated '$name' ($(@($fields).Count) keys)"
        }
        else {
            $item = [ordered] @{
                organizationId = $null
                folderId       = $null
                type           = 2              # secure note
                name           = $name
                notes          = $notes
                favorite       = $false
                fields         = @($fields)
                secureNote     = @{ type = 0 }
                reprompt       = 1              # ask for the master password before showing it
            }
            $item | ConvertTo-Json -Depth 10 | bw encode | bw create item | Out-Null
            if ($LASTEXITCODE) { Stop-Install 'bw create item failed' }
            Write-Ok "Bitwarden: created '$name' ($(@($fields).Count) keys)"
        }
    }
    finally {
        Close-BitwardenSession
    }
}

if ($DryRun) {
    Write-Would 'ask whether to save the recovery keys to Bitwarden'
    return
}
$answer = Read-Host 'Save the BitLocker recovery keys of all drives to Bitwarden (bw CLI)? [y/N]'
if ($answer -match '^\s*[yt]') { Save-RecoveryKeysToBitwarden }
else { Write-Ok 'recovery keys not saved (later: admin.ps1 bitlocker); they must be kept somewhere safe' }
