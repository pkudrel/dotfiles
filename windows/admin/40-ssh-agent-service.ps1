# Windows "OpenSSH Authentication Agent" service off: it claims the pipe the Bitwarden SSH agent serves.
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

$service = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Ok 'OpenSSH Authentication Agent not installed'
    return
}
if ($service.StartType -eq 'Disabled' -and $service.Status -ne 'Running') {
    Write-Ok 'OpenSSH Authentication Agent disabled (Bitwarden serves the SSH agent)'
    return
}
if ($DryRun) {
    Write-Ok "would stop and disable OpenSSH Authentication Agent (now: $($service.Status), $($service.StartType))"
    return
}
if ($service.Status -eq 'Running') { Stop-Service -Name ssh-agent -Force }
Set-Service -Name ssh-agent -StartupType Disabled
Write-Ok 'OpenSSH Authentication Agent stopped and disabled; restart Bitwarden if its SSH agent is off'
