# Windows Hypervisor Platform: needed by Docker Sandboxes (sbx). Takes effect after a restart.
# Nothing to do when Hyper-V or Virtual Machine Platform is already on: sbx runs on those as well.
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

# CIM answers in a second; Get-WindowsOptionalFeature (DISM) sits silent for a minute or more.
# InstallState: 1 enabled, 2 disabled, 3 absent.
$names = 'HypervisorPlatform', 'Microsoft-Hyper-V-Hypervisor', 'VirtualMachinePlatform'
$features = Get-CimInstance -ClassName Win32_OptionalFeature | Where-Object Name -in $names
$enabled = @($features | Where-Object InstallState -eq 1 | ForEach-Object Name)
if ($enabled) {
    Write-Ok "hypervisor available ($($enabled -join ', '))"
    return
}
if ($DryRun) {
    Write-Ok 'would enable Hypervisor Platform (no hypervisor feature enabled yet)'
    return
}
# dism.exe rather than Enable-WindowsOptionalFeature: it shows a progress bar while it works.
Write-Step 'enabling Hypervisor Platform (takes a minute or two)'
dism.exe /Online /Enable-Feature /FeatureName:HypervisorPlatform /All /NoRestart
if ($LASTEXITCODE -notin 0, 3010) { Stop-Install "dism /Enable-Feature HypervisorPlatform failed (exit code $LASTEXITCODE)" }
$global:DotfilesRebootRequired = $true
Write-Ok 'Hypervisor Platform enabled (after restart)'
