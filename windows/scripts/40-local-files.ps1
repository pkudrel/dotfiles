# Machine-local files: copied from templates\ only when missing, never overwritten.
. (Join-Path $PSScriptRoot 'lib.ps1')

$templates  = Join-Path $WindowsDir 'templates'
$profileDir = Split-Path $PROFILE.CurrentUserAllHosts -Parent

Copy-IfMissing (Join-Path $templates 'profile.local.ps1.example') (Join-Path $profileDir 'profile.local.ps1')
Copy-IfMissing (Join-Path $templates 'gitconfig.local.example')   (Join-Path $HOME '.gitconfig.local')
if (-not $DotfilesDryRun) {
    New-Item -ItemType Directory -Force -Path $DotfilesConfigDir | Out-Null
}
