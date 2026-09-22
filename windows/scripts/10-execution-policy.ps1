# Execution policy: allow local scripts for the current user (RemoteSigned) when they are blocked.
. (Join-Path $PSScriptRoot 'lib.ps1')

$policy = Get-ExecutionPolicy
if ($policy -notin 'Restricted', 'AllSigned') {
    Write-Ok "$policy"
    return
}
if ($DotfilesDryRun) {
    Write-Would "set RemoteSigned for the current user (now: $policy)"
    return
}
try {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Ok "was $policy, now RemoteSigned for the current user"
}
catch {
    Write-Warn "cannot change execution policy ($policy): $($_.Exception.Message)"
}
