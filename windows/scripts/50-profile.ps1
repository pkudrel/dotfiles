# PowerShell profile: Documents\PowerShell\profile.ps1 becomes a short loader for windows\powershell\profile.ps1.
# An existing, different file is backed up first.
. (Join-Path $PSScriptRoot 'lib.ps1')

$repoProfile = Join-Path $WindowsDir 'powershell\profile.ps1'
$userProfile = $PROFILE.CurrentUserAllHosts
$quotedRepoProfile = $repoProfile.Replace("'", "''")

$loader = @"
# Created by windows\scripts\50-profile.ps1 from the dotfiles repo.
# Edit the profile in the repo, not here. Machine-only settings: profile.local.ps1 in this folder.
`$dotfilesProfile = '$quotedRepoProfile'
if (Test-Path `$dotfilesProfile) { . `$dotfilesProfile }
else { Write-Warning "dotfiles profile not found: `$dotfilesProfile" }
"@

if (-not $DotfilesDryRun) {
    New-Item -ItemType Directory -Force -Path (Split-Path $userProfile -Parent) | Out-Null
}

if (Test-Path $userProfile) {
    $current = "$(Get-Content -Raw -Path $userProfile)"
    if ($current.TrimEnd() -eq $loader.TrimEnd()) {
        Write-Ok "loader already set: $userProfile"
    }
    elseif ($DotfilesDryRun) {
        Write-Would "back up $userProfile and replace it with the loader for $repoProfile$(if ($current -match 'devbox') { ' (it now loads the old devbox profile)' })"
    }
    else {
        if ($current -match 'devbox') {
            Write-Warn "replacing the old devbox profile loader (the devbox clone itself is left alone)"
        }
        Backup-Item $userProfile
        Set-Content -Path $userProfile -Value $loader -Encoding utf8
        Write-Ok "loader written: $userProfile (loads $repoProfile)"
    }
}
elseif ($DotfilesDryRun) {
    Write-Would "create $userProfile (loader for $repoProfile)"
}
else {
    Set-Content -Path $userProfile -Value $loader -Encoding utf8
    Write-Ok "loader written: $userProfile (loads $repoProfile)"
}

$hostProfile = $PROFILE.CurrentUserCurrentHost
if (Test-Path $hostProfile) {
    Write-Warn "$hostProfile also exists and runs after this profile; empty or remove it if it holds old settings"
}
