# Nerd Font MesloLGS NF for the current user (windows\fonts\install-nerd-font.ps1). Consolas NF comes from the bitwarden-store step.
. (Join-Path $PSScriptRoot 'lib.ps1')

if ($DotfilesDryRun) {
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $missing = @('MesloLGS NF Regular.ttf', 'MesloLGS NF Bold.ttf', 'MesloLGS NF Italic.ttf', 'MesloLGS NF Bold Italic.ttf') |
        Where-Object { -not (Test-Path (Join-Path $fontDir $_)) }
    if ($missing) { Write-Would "install $($missing -join ', ')" } else { Write-Ok 'MesloLGS NF present' }
    return
}
& (Join-Path $WindowsDir 'fonts\install-nerd-font.ps1')
