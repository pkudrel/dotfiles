# Preinstalled apps from config\remove-apps.txt: removed for every user and from the image (new accounts do not get them).
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

# The Appx module does not always load in PowerShell 7; then it runs in Windows PowerShell (removal by full name
# works with the objects that come back from there).
try { Get-AppxPackage -Name 'Microsoft.WindowsStore' | Out-Null }
catch { Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue }

$names = @(Read-ListFile (Join-Path $WindowsDir 'config\remove-apps.txt'))
$installed   = @(Get-AppxPackage -AllUsers | Where-Object Name -in $names)
$provisioned = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -in $names)

$failed = @()
foreach ($name in $names) {
    $packages = @($installed | Where-Object Name -eq $name)
    $images   = @($provisioned | Where-Object DisplayName -eq $name)
    if (-not $packages -and -not $images) { continue }
    $where = @(if ($packages) { 'installed' }; if ($images) { 'image' }) -join ' + '
    if ($DryRun) {
        Write-Ok "would remove $name ($where)"
        continue
    }
    try {
        foreach ($package in $packages) { Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop }
        foreach ($image in $images) { Remove-AppxProvisionedPackage -Online -PackageName $image.PackageName -ErrorAction Stop | Out-Null }
        Write-Ok "removed $name ($where)"
    }
    catch {
        # One app that cannot go (in use, system) should not stop the others.
        Write-Warn "${name}: $($_.Exception.Message)"
        $failed += $name
    }
}
if ($failed) { Write-Warn "not removed: $($failed -join ', ') (sign out and run admin.ps1 remove-apps again)" }
elseif (-not $DryRun) { Write-Ok "no app from remove-apps.txt left ($($names.Count) on the list)" }
