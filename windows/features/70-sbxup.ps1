# Claude Code sandboxes: sbxup from deneblab/sbx-templates (not in winget; official installer)
param([string] $Action)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

$installer = 'https://raw.githubusercontent.com/deneblab/sbx-templates/main/install.ps1'

function Get-SbxupVersion { (& sbxup --version 2>$null | Out-String).Trim() }

switch ($Action) {
    'status' {
        if (Test-Command sbxup) { "installed $(Get-SbxupVersion)"; exit 0 }
        'not installed'; exit 1
    }
    'install' {
        if (Test-Command sbxup) {
            Write-Step "sbxup $(Get-SbxupVersion) present, updating"
            sbxup --self-update
            if ($LASTEXITCODE) { Stop-Install "sbxup --self-update failed (exit code $LASTEXITCODE)" }
        }
        else {
            # The official installer verifies the SHA-256 checksum and adds its folder to the user PATH.
            Write-Step "installing sbxup ($installer)"
            Invoke-RestMethod -Uri $installer | Invoke-Expression
            Update-SessionPath
            if (-not (Test-Command sbxup)) { Stop-Install 'sbxup not found on PATH after install' }
        }
        Write-Ok "sbxup $(Get-SbxupVersion); needs the sbx feature (and docker-desktop to build templates)"
        exit 0
    }
    default {
        Write-Host "usage: $(Split-Path $PSCommandPath -Leaf) status|install"
        exit 2
    }
}
