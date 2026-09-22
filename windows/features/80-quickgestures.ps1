# Mouse gestures for Brave: QuickGestures extension (GitHub release, loaded unpacked)
param([string] $Action)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

# Fixed folder: Brave keeps loading the extension from here, updates replace its content in place.
$installDir  = Join-Path $env:LOCALAPPDATA 'dotfiles\QuickGestures'
$versionFile = Join-Path $installDir '.dotfiles-version'
$releaseApi  = 'https://api.github.com/repos/deneblab/QuickGestures/releases/latest'

function Get-InstalledVersion {
    if (Test-Path $versionFile) { (Get-Content -Raw -Path $versionFile).Trim() }
}

switch ($Action) {
    'status' {
        $version = Get-InstalledVersion
        if ($version) { "installed $version"; exit 0 }
        'not installed'; exit 1
    }
    'install' {
        $release = Invoke-RestMethod -Uri $releaseApi
        $asset = $release.assets | Where-Object name -like 'quickgestures-*.zip' | Select-Object -First 1
        if (-not $asset) { Stop-Install "no quickgestures-*.zip in release $($release.tag_name)" }

        $installed = Get-InstalledVersion
        if ($installed -eq $release.tag_name) {
            Write-Ok "QuickGestures $installed is the latest ($installDir)"
            exit 0
        }

        $tmp = Join-Path ([IO.Path]::GetTempPath()) "quickgestures-$([guid]::NewGuid())"
        try {
            New-Item -ItemType Directory -Path $tmp | Out-Null
            $zip = Join-Path $tmp $asset.name
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip
            Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'x')
            if (-not (Test-Path (Join-Path $tmp 'x\manifest.json'))) { Stop-Install "$($asset.name) has no manifest.json at its root" }

            New-Item -ItemType Directory -Force -Path $installDir | Out-Null
            Get-ChildItem -Path $installDir -Force | Remove-Item -Recurse -Force
            Copy-Item -Path (Join-Path $tmp 'x\*') -Destination $installDir -Recurse -Force
            Set-Content -Path $versionFile -Value $release.tag_name -Encoding utf8NoBOM
        }
        finally {
            Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }

        if ($installed) {
            Write-Ok "QuickGestures $installed → $($release.tag_name); in brave://extensions click the reload icon on QuickGestures"
        }
        else {
            Write-Ok "QuickGestures $($release.tag_name) in $installDir"
            Write-Host '    Brave, once: brave://extensions → Developer mode on → Load unpacked → the folder above.'
            Write-Host '    Settings: QuickGestures options → Import Settings (export them from your other machine).'
        }
        exit 0
    }
    default {
        Write-Host "usage: $(Split-Path $PSCommandPath -Leaf) status|install"
        exit 2
    }
}
