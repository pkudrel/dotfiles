# Diagnostic data "Required"; ads, suggestions, Copilot, Recall and Bing in Start search off: registry values from
# config\privacy.txt. The telemetry service DiagTrack stopped and disabled.
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

$lines = @(Read-ListFile (Join-Path $WindowsDir 'config\privacy.txt'))
$changed = 0
foreach ($line in $lines) {
    $path, $name, $value = ($line -split '\|', 3).ForEach({ $_.Trim() })
    $value = [int] $value
    $current = (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
    if ($current -eq $value) { continue }
    $now = if ($null -ne $current) { " (now: $current)" } else { '' }
    if ($DryRun) {
        Write-Ok "would set $path\$name = $value$now"
        continue
    }
    if (-not (Test-Path -Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name $name -Value $value -Type DWord
    Write-Ok "$path\$name = $value$now"
    $changed++
}
if ($changed) { Write-Ok "$changed registry values set; some apply after sign-out" }
elseif (-not $DryRun) { Write-Ok "privacy settings in place ($($lines.Count) registry values)" }

$service = Get-Service -Name DiagTrack -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Ok 'DiagTrack (Connected User Experiences and Telemetry) not installed'
}
elseif ($service.StartType -eq 'Disabled' -and $service.Status -ne 'Running') {
    Write-Ok 'DiagTrack (Connected User Experiences and Telemetry) disabled'
}
elseif ($DryRun) {
    Write-Ok "would stop and disable DiagTrack (now: $($service.Status), $($service.StartType))"
}
else {
    if ($service.Status -eq 'Running') { Stop-Service -Name DiagTrack -Force }
    Set-Service -Name DiagTrack -StartupType Disabled
    Write-Ok 'DiagTrack (Connected User Experiences and Telemetry) stopped and disabled'
}
