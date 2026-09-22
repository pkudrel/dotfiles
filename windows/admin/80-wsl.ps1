# WSL with Ubuntu (the distro's own setup is ubuntu/install.sh, see README).
# opt-in: runs only when named (admin.ps1 wsl)
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

$distro = $Options.WslDistro
$env:WSL_UTF8 = '1'   # plain UTF-8 output from wsl.exe instead of UTF-16

$installed = @(wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($distro -in $installed) {
    Write-Ok "WSL distro $distro installed"
    return
}
if ($DryRun) {
    Write-Ok "would install WSL distro $distro (wsl --install -d $distro --no-launch)"
    return
}
wsl.exe --install -d $distro --no-launch
if ($LASTEXITCODE) { Stop-Install "wsl --install -d $distro failed (exit code $LASTEXITCODE); list names: wsl --list --online" }
$global:DotfilesRebootRequired = $true
Write-Ok "WSL distro $distro installed; after the restart start it once from the Start menu to create your user"
