# Remove OneDrive: uninstall, block it by policy, drop it from the Explorer sidebar.
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

$policyKey  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
$sidebarKey = 'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'

# OneDriveSetup.exe is on every Windows, also after the uninstall: OneDrive.exe tells whether it is installed.
$exe = @(@(
    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe"
    "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
) | Where-Object { Test-Path -Path $_ })

if (-not $exe) {
    Write-Ok 'OneDrive not installed'
}
elseif ($DryRun) {
    Write-Ok "would uninstall OneDrive ($($exe[0]))"
}
else {
    # Not winget: it refuses the per-user OneDrive when elevated ("cannot be uninstalled when running with
    # administrator privileges"). OneDriveSetup.exe uninstalls it for this user also from an elevated run.
    Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
    $setup = @(@(
        "$env:SystemRoot\System32\OneDriveSetup.exe"
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    ) | Where-Object { Test-Path -Path $_ })
    if (-not $setup) { Stop-Install 'OneDriveSetup.exe not found; uninstall OneDrive in Settings > Apps' }
    Start-Process -FilePath $setup[0] -ArgumentList '/uninstall' -Wait
    $left = @($exe | Where-Object { Test-Path -Path $_ })
    if ($left) { Write-Warn "OneDrive still installed ($($left[0])); uninstall it in Settings > Apps" }
    else { Write-Ok 'OneDrive uninstalled' }
}

$settings = @(
    @{ Key = $policyKey;  Name = 'DisableFileSyncNGSC';            Value = 1; Label = 'policy DisableFileSyncNGSC = 1' }
    @{ Key = $sidebarKey; Name = 'System.IsPinnedToNameSpaceTree'; Value = 0; Label = 'OneDrive hidden in the Explorer sidebar' }
)
foreach ($setting in $settings) {
    $current = (Get-ItemProperty -Path $setting.Key -Name $setting.Name -ErrorAction SilentlyContinue).($setting.Name)
    if ($current -eq $setting.Value) {
        Write-Ok $setting.Label
        continue
    }
    if ($DryRun) {
        Write-Ok "would set $($setting.Label)"
        continue
    }
    # New-Item -Force on an existing registry key would drop its other values.
    if (-not (Test-Path -Path $setting.Key)) { New-Item -Path $setting.Key -Force | Out-Null }
    Set-ItemProperty -Path $setting.Key -Name $setting.Name -Value $setting.Value -Type DWord
    Write-Ok "$($setting.Label) (Explorer: after it restarts)"
}
