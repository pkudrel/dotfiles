# Optional features: install/update the ones remembered on this machine (pick them with features.ps1).
. (Join-Path $PSScriptRoot 'lib.ps1')

$featureArgs = @('--update')
if ($DotfilesDryRun) { $featureArgs += '--dry-run' }
& (Join-Path $WindowsDir 'features.ps1') @featureArgs
