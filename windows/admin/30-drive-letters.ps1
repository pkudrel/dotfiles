# Drive letters for folders from config\drive-letters.txt (e.g. Q: → %USERPROFILE%\!others). Permanent, after a restart.
param([switch] $DryRun, [hashtable] $Options)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')

# The same registry key as the old map-drive\MapDrive.reg: values "Q:" = "\??\C:\Users\...\!others".
$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\DOS Devices'

foreach ($line in Read-ListFile (Join-Path $WindowsDir 'config\drive-letters.txt')) {
    $letter, $folder = ($line -split '=', 2).ForEach({ $_.Trim() })
    $letter = $letter.TrimEnd(':').ToUpperInvariant()
    $folder = [Environment]::ExpandEnvironmentVariables($folder)
    $name   = "${letter}:"
    $value  = "\??\$folder"

    $current = (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name
    if ($current -eq $value) {
        Write-Ok "$name → $folder"
        continue
    }
    if (-not $current -and (Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue)) {
        Write-Warn "$name is used by a volume; $folder not mapped"
        continue
    }
    if ($DryRun) {
        Write-Ok "would map $name → $folder$(if ($current) { " (now: $current)" })"
        continue
    }
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    Set-ItemProperty -Path $key -Name $name -Value $value -Type String
    $global:DotfilesRebootRequired = $true
    Write-Ok "$name → $folder (after restart)"
}
