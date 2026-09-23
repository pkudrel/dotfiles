# Files from the Bitwarden secure note "bitwarden-store" (licenses, fonts, git identity), as its attachment
# _manifest.txt says (code: store-lib.ps1). One master password prompt (Enter skips); changed files are overwritten;
# UAC only for folders that need admin. Change the store itself with store.ps1 (dlab-store-*).
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'store-lib.ps1')

if ($DotfilesDryRun -and -not (Test-Command bw)) {
    Write-Would "install the Bitwarden CLI and apply $StoreItemName"
    return
}
if (-not (Open-BitwardenSession)) {
    Write-Warn "Bitwarden skipped, $StoreItemName not applied (later: install.ps1 bitwarden-store or dlab-store-restore)"
    Test-GitIdentity
    return
}

try {
    Start-StoreTemp
    if (Update-StoreItem) {
        Invoke-StoreRestore
    }
    else {
        Write-Warn "Bitwarden has no item '$StoreItemName' (a secure note with the files and $StoreManifest attached); nothing done"
    }
}
finally {
    Stop-Store
}
Test-GitIdentity
