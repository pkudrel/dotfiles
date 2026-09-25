# Preinstalled apps from config\remove-apps.txt: removed for every user and from the image (new accounts do not get them).
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

# All Appx work runs in Windows PowerShell, the Appx module's home: in PowerShell 7 the module fails to load on some
# builds ("Class not registered"), also through -UseWindowsPowerShell. A removal also waits in the AppX deployment
# queue behind anything else in it (right after a fresh install: the Store updating the inbox apps) and has no
# timeout of its own, so each call is killed when it takes longer than this.
$timeoutSeconds = 180

function Invoke-WindowsPowerShell([string] $Script) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$ErrorActionPreference = 'Stop'; `$ProgressPreference = 'SilentlyContinue'`n$Script"))
    $errorFile  = New-TemporaryFile
    $outputFile = New-TemporaryFile
    try {
        $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded `
            -NoNewWindow -PassThru -RedirectStandardError $errorFile.FullName -RedirectStandardOutput $outputFile.FullName
        if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
            $process.Kill($true)
            throw "no answer after $timeoutSeconds s (AppX deployment busy, e.g. the Store updating apps)"
        }
        $process.WaitForExit()  # the exit code is set only after the parameterless wait
        if ($process.ExitCode -ne 0) {
            $message = "$(Get-Content -Path $errorFile.FullName -Raw)" -replace '\s+', ' '
            throw $(if ($message.Trim()) { $message.Trim() } else { "exit code $($process.ExitCode)" })
        }
        Get-Content -Path $outputFile.FullName -Raw
    }
    finally { Remove-Item -Path $errorFile.FullName, $outputFile.FullName -Force -ErrorAction SilentlyContinue }
}

$names = @(Read-ListFile (Join-Path $WindowsDir 'config\remove-apps.txt'))
Write-Host '    reading installed apps and the image (can take a minute)...'
$json = Invoke-WindowsPowerShell @'
@{
    Installed   = @(Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName)
    Provisioned = @(Get-AppxProvisionedPackage -Online | Select-Object DisplayName, PackageName)
} | ConvertTo-Json -Depth 3 -Compress
'@
$found = $json | ConvertFrom-Json
$installed   = @($found.Installed | Where-Object Name -in $names)
$provisioned = @($found.Provisioned | Where-Object DisplayName -in $names)

$failed = @()
foreach ($name in $names) {
    $packages = @($installed | Where-Object Name -eq $name)
    $images   = @($provisioned | Where-Object DisplayName -eq $name)
    if (-not $packages -and -not $images) { continue }
    $where = @(if ($packages) { 'installed' }; if ($images) { 'image' }) -join ' + '
    if ($DryRun) {
        Write-Ok "would remove $name ($where)"
        continue
    }
    Write-Host "    removing $name ($where)..."
    try {
        Invoke-WindowsPowerShell (@(
            foreach ($package in $packages) { "Remove-AppxPackage -Package '$($package.PackageFullName)' -AllUsers" }
            foreach ($image in $images) { "Remove-AppxProvisionedPackage -Online -PackageName '$($image.PackageName)' | Out-Null" }
        ) -join "`n") | Out-Null
        Write-Ok "removed $name ($where)"
    }
    catch {
        # One app that cannot go (in use, system, deployment busy) should not stop the others.
        Write-Warn "${name}: $($_.Exception.Message)"
        $failed += $name
    }
}
if ($failed) { Write-Warn "not removed: $($failed -join ', ') (sign out, or wait for Store updates, and run admin.ps1 remove-apps again)" }
elseif (-not $DryRun) { Write-Ok "no app from remove-apps.txt left ($($names.Count) on the list)" }
