#Requires -Version 5.1
<#
.SYNOPSIS
  Installs MesloLGS NF (the Nerd Font recommended by Powerlevel10k) for the current user.
.DESCRIPTION
  MesloLGS NF is downloaded. Fonts that may not be redistributed (e.g. Consolas NF) are not in the repo: they come
  from Bitwarden (install step bitwarden-store, action "font").
  No admin rights needed. Safe to re-run: fonts already installed are skipped.
  From WSL:
    powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ~/.dotfiles/windows/fonts/install-nerd-font.ps1)"
#>
$ErrorActionPreference = 'Stop'

$baseUrl = 'https://github.com/romkatv/powerlevel10k-media/raw/master'
$fonts   = @('MesloLGS NF Regular.ttf', 'MesloLGS NF Bold.ttf', 'MesloLGS NF Italic.ttf', 'MesloLGS NF Bold Italic.ttf')
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

foreach ($font in $fonts) {
    $target  = Join-Path $fontDir $font
    $regName = '{0} (TrueType)' -f [IO.Path]::GetFileNameWithoutExtension($font)
    $registered = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue

    if ((Test-Path $target) -and $registered) {
        Write-Host "ok       $font"
        continue
    }

    Invoke-WebRequest -Uri ("$baseUrl/" + [Uri]::EscapeDataString($font)) -OutFile $target -UseBasicParsing
    New-ItemProperty -Path $regPath -Name $regName -Value $target -PropertyType String -Force | Out-Null
    Write-Host "install  $font"
}

Write-Host ''
Write-Host 'Done. Restart Windows Terminal / VS Code to use the fonts.'
Write-Host 'Consolas NF (the default face in Windows Terminal) comes from Bitwarden: install.ps1 bitwarden-store; see README.md.'
