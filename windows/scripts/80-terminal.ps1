# Windows Terminal: settings.json from windows\terminal\settings.json (the whole file).
# When the machine's file differs, asks before replacing it; the old file is backed up first.
# Profiles Windows Terminal generates itself (WSL distros, Visual Studio shells, ...) come back on their own.
# Save this machine's settings into the repo: dlab-terminal-save.
param(
    # For tests: settings files to update instead of the Windows Terminal ones.
    [string[]] $SettingsPath
)
. (Join-Path $PSScriptRoot 'lib.ps1')

$repoSettings = Join-Path $WindowsDir 'terminal\settings.json'
if (-not (Test-Path $repoSettings)) {
    Write-Warn "no $repoSettings in the repo yet; save this machine's settings with dlab-terminal-save"
    return
}

if (-not $SettingsPath) {
    $SettingsPath = Get-TerminalSettingsPath
}

# File text with LF line endings and no trailing whitespace, so a CRLF/LF difference alone is not a change.
function Get-NormalizedText([string] $Path) { ((Get-Content -Raw -Path $Path) -replace "`r`n", "`n").TrimEnd() }

foreach ($path in $SettingsPath) {
    if (-not (Test-Path $path)) {
        if ($DotfilesDryRun) { Write-Would "create $path from the repo"; continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
        Copy-Item -Path $repoSettings -Destination $path
        Write-Ok "created $path"
        continue
    }
    if ((Get-NormalizedText $path) -ceq (Get-NormalizedText $repoSettings)) {
        Write-Ok "same as the repo: $path"
        continue
    }
    if ($DotfilesDryRun) {
        Write-Would "ask whether to replace $path with the repo version (they differ)"
        continue
    }
    if ([Console]::IsInputRedirected) {
        Write-Warn "differs from the repo, left as is (no terminal to ask): $path"
        continue
    }
    $answer = Read-Host "Windows Terminal settings differ from the repo. Replace $path with the repo version (a backup is kept)? [y/N]"
    if ($answer -notmatch '^\s*[yt]') {
        Write-Ok "left as is: $path (to keep this machine's version in the repo: dlab-terminal-save)"
        continue
    }
    Backup-Item $path
    Copy-Item -Path $repoSettings -Destination $path -Force
    Write-Ok "replaced: $path"
}
