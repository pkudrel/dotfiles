# Install the winget packages listed in packages\winget.txt (installed ones are skipped; upgrades: dlab-winget-upgradeall).
. (Join-Path $PSScriptRoot 'lib.ps1')

Assert-Winget

$packages = @(Read-ListFile (Join-Path $WindowsDir 'packages\winget.txt') | ForEach-Object { ConvertFrom-PackageLine $_ })
$total = $packages.Count
Write-Step "checking $total packages"

$missing = @()
for ($i = 0; $i -lt $total; $i++) {
    $package = $packages[$i]
    $counter = "[$($i + 1)/$total]"
    if (Test-WingetPackage -Id $package.Id -Command $package.Command) {
        Write-Ok "$counter $($package.Id) present"
    }
    else {
        Write-Warn "$counter $($package.Id) missing"
        $missing += $package
    }
}

if (-not $missing) {
    Write-Ok "all $total packages present"
}
elseif ($DotfilesDryRun) {
    Write-Would "install $($missing.Count) of $total packages: $($missing.Id -join ', ')"
}
else {
    for ($i = 0; $i -lt $missing.Count; $i++) {
        $package = $missing[$i]
        Write-Step "installing [$($i + 1)/$($missing.Count)] $($package.Id)"
        Install-WingetPackage -Id $package.Id -Override $package.Override
        Write-Ok "[$($i + 1)/$($missing.Count)] $($package.Id) installed"
    }
}
