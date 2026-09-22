# Git: ~\.gitconfig includes windows\git\.gitconfig from the repo (which includes ~\.gitconfig.local last).
# No symlink (that needs admin or Developer Mode). Anything else in ~\.gitconfig stays and wins over the repo file.
. (Join-Path $PSScriptRoot 'lib.ps1')

$repoConfig = (Join-Path $WindowsDir 'git\.gitconfig').Replace('\', '/')
$userConfig = Join-Path $HOME '.gitconfig'

$include = @"
# Created by windows\scripts\60-git.ps1 from the dotfiles repo: shared settings come from the repo file.
# Settings below the include (e.g. written by git config --global, Sourcetree, GCM) are this machine's and win.
[include]
	path = $repoConfig
"@

if (-not (Test-Path $userConfig)) {
    if ($DotfilesDryRun) {
        Write-Would "create $userConfig (includes $repoConfig)"
        return
    }
    Set-Content -Path $userConfig -Value $include -Encoding utf8NoBOM
    Write-Ok "created $userConfig (includes $repoConfig)"
    return
}

$current = "$(Get-Content -Raw -Path $userConfig)"
if ($current.Contains("path = $repoConfig")) {
    Write-Ok "$userConfig already includes $repoConfig"
    return
}

# An include of another dotfiles clone (the repo was moved or cloned again elsewhere): point it at this one,
# instead of adding a second include that the old one, further down, would override.
$otherInclude = '(?m)^([ \t]*path[ \t]*=[ \t]*)(.+/windows/git/\.gitconfig)([ \t]*\r?)$'
if ($current -match $otherInclude) {
    $old = $Matches[2]
    if ($DotfilesDryRun) {
        Write-Would "back up $userConfig and change its include of $old to $repoConfig"
        return
    }
    Backup-Item $userConfig
    $updated = [regex]::Replace($current, $otherInclude, { param($m) $m.Groups[1].Value + $repoConfig + $m.Groups[3].Value }, 1)
    Set-Content -Path $userConfig -Value $updated -Encoding utf8NoBOM -NoNewline
    Write-Ok "include in $userConfig changed from $old to $repoConfig"
    return
}

if ($DotfilesDryRun) {
    Write-Would "back up $userConfig and add an include of $repoConfig at its top (its settings stay below)"
    return
}
Backup-Item $userConfig
Set-Content -Path $userConfig -Value ($include + "`n`n" + $current.TrimEnd() + "`n") -Encoding utf8NoBOM -NoNewline
Write-Ok "include added at the top of $userConfig; its existing settings are kept below"
