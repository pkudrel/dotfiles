# WSL with Ubuntu 26.04 (the distro's own setup stays manual: README "New WSL")
param([string] $Action)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

$distro = 'Ubuntu-26.04'
$env:WSL_UTF8 = '1'   # plain UTF-8 output from wsl.exe instead of UTF-16

# On a clean Windows wsl.exe is only a stub: it prints a message instead of a list, which never matches the name.
function Test-Distro {
    $installed = @(wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $distro -in $installed
}

switch ($Action) {
    'status' {
        if ((Test-Command wsl.exe) -and (Test-Distro)) { "installed $distro"; exit 0 }
        'not installed'; exit 1
    }
    'install' {
        if (-not (Test-Command wsl.exe)) { Stop-Install 'wsl.exe not found (Windows 10 2004+ / Windows 11 needed)' }
        if (Test-Distro) {
            Write-Ok "WSL distro $distro installed"
            exit 0
        }
        # wsl.exe asks for UAC itself when it has to enable Virtual Machine Platform.
        Write-Step "installing WSL with $distro (wsl --install -d $distro --no-launch)"
        wsl.exe --install -d $distro --no-launch
        if ($LASTEXITCODE -notin 0, 3010) { Stop-Install "wsl --install -d $distro failed (exit code $LASTEXITCODE); list names: wsl --list --online" }
        if (Test-Distro) {
            Write-Ok "WSL distro $distro installed; start it once from the Start menu to create your user, then README ""New WSL"""
            exit 0
        }
        # Clean Windows: WSL itself was just enabled, the distro finishes after the restart.
        $global:DotfilesRebootRequired = $true
        Write-Warn "restart Windows to finish WSL; if $distro is not in the Start menu after it, run dlab-features-select wsl again"
        exit 0
    }
    default {
        Write-Host "usage: $(Split-Path $PSCommandPath -Leaf) status|install"
        exit 2
    }
}
