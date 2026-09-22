# Remove OneDrive: uninstall, block it by policy, drop it from the Explorer sidebar.
# opt-in: runs only when named (admin.ps1 onedrive)
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

$policyKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
$sidebarKey = 'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'

if ($DryRun) {
    Write-Ok 'would uninstall OneDrive, set policy DisableFileSyncNGSC=1 and hide it in the Explorer sidebar'
    return
}

Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
if ((Test-Command winget) -and (Test-WingetPackage 'Microsoft.OneDrive')) {
    winget uninstall --id Microsoft.OneDrive @WingetCommonArgs
    Write-Ok 'OneDrive uninstalled (winget)'
}
else {
    $setup = "$env:SystemRoot\System32\OneDriveSetup.exe"
    if (Test-Path $setup) {
        & $setup /uninstall
        Write-Ok 'OneDrive uninstalled (OneDriveSetup.exe)'
    }
    else {
        Write-Ok 'OneDrive not installed'
    }
}

New-Item -Path $policyKey -Force | Out-Null
Set-ItemProperty -Path $policyKey -Name DisableFileSyncNGSC -Value 1 -Type DWord
Write-Ok 'policy DisableFileSyncNGSC = 1'

New-Item -Path $sidebarKey -Force | Out-Null
Set-ItemProperty -Path $sidebarKey -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord
Write-Ok 'OneDrive hidden in the Explorer sidebar (after Explorer restarts)'
