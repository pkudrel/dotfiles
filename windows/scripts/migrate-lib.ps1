# Helpers for the program definitions in windows\migrate\ (used by migrate.ps1). Dot-source it after lib.ps1.
#
# A definition is called as "<file> <action> <folder>", <folder> being this program's folder inside the export
# (<export>\<name>). Actions:
#   status          object: Code (0 data here, 1 no data), Text, Profiles (names), Source (path here), Process
#   export <folder> copy the data here into <folder> (replaced); returns the profile names
#   import <folder> replace the data here with <folder>
# The program must not be running for export / import (checked here too).


######
###### COMMON
######

# Progress bar (Write-Progress) for thousands of small files: redrawn at most every 200 ms, drawing it for
# every file would slow the copy down. Percent from the file count, not bytes (profiles are mostly small files).
$ProgressClock = [Diagnostics.Stopwatch]::StartNew()

function Show-Progress([string] $Activity, [int] $Done, [int] $Total) {
    if ($Done -lt $Total -and $ProgressClock.ElapsedMilliseconds -lt 200) { return }
    $ProgressClock.Restart()
    $shown = [Math]::Min($Done, $Total)
    $percent = if ($Total) { [int] (100 * $shown / $Total) } else { 100 }
    Write-Progress -Activity $Activity -Status ('{0:N0} / {1:N0} files ({2}%)' -f $shown, $Total, $percent) -PercentComplete $percent
}

function Complete-Progress([string] $Activity) {
    Write-Progress -Activity $Activity -Completed
}

function Test-AnyMask([string] $Name, [string[]] $Masks) {
    foreach ($mask in $Masks) { if ($Name -like $mask) { return $true } }
    $false
}

# Files Copy-Tree will copy (same exclusions, junctions skipped like robocopy /XJ): the total of the progress bar.
function Get-TreeFileCount([string] $Source, [string[]] $SkipDirs = @(), [string[]] $SkipFiles = @()) {
    $skipNames = @($SkipDirs | Where-Object { -not $_.Contains('\') })
    $skipPaths = @($SkipDirs | Where-Object { $_.Contains('\') } | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $Source $_)) })
    $count = 0
    $pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $pending.Push([IO.DirectoryInfo]::new($Source))
    while ($pending.Count) {
        $dir = $pending.Pop()
        try {
            foreach ($file in $dir.EnumerateFiles()) {
                if (-not (Test-AnyMask $file.Name $SkipFiles)) { $count++ }
            }
            foreach ($sub in $dir.EnumerateDirectories()) {
                if ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ((Test-AnyMask $sub.Name $skipNames) -or $sub.FullName -in $skipPaths) { continue }
                $pending.Push($sub)
            }
        }
        catch [UnauthorizedAccessException], [IO.IOException] {
            # robocopy reports these folders itself.
        }
    }
    $count
}

# Copy a folder tree with robocopy, with a progress bar ($Activity). -Mirror also removes what is in $Destination
# but not in $Source. $SkipDirs: folder names (anywhere), or paths relative to $Source when they contain "\".
# $SkipFiles: file names / masks.
function Copy-Tree([string] $Source, [string] $Destination, [string[]] $SkipDirs = @(), [string[]] $SkipFiles = @(), [switch] $Mirror, [string] $Activity = 'copy') {
    $total = Get-TreeFileCount $Source $SkipDirs $SkipFiles
    # Without /NFL robocopy prints a line per copied file: counted for the progress bar.
    $robocopyArgs = @($Source, $Destination, $(if ($Mirror) { '/MIR' } else { '/E' }), '/R:1', '/W:1', '/XJ', '/NDL', '/NP', '/NJH', '/NJS')
    if ($SkipDirs) {
        $robocopyArgs += '/XD'
        $robocopyArgs += $SkipDirs | ForEach-Object { if ($_.Contains('\')) { Join-Path $Source $_ } else { $_ } }
    }
    if ($SkipFiles) {
        $robocopyArgs += '/XF'
        $robocopyArgs += $SkipFiles
    }
    $done = 0
    $tail = [Collections.Generic.Queue[string]]::new()  # last lines, shown when robocopy fails
    robocopy @robocopyArgs | ForEach-Object {
        if (-not $_.Trim()) { return }
        $tail.Enqueue($_)
        if ($tail.Count -gt 20) { [void] $tail.Dequeue() }
        $done++
        Show-Progress $Activity $done $total
    }
    $exitCode = $LASTEXITCODE
    Complete-Progress $Activity
    # robocopy: 0-7 success (files copied / extra files / mismatches), 8 and more failure.
    if ($exitCode -ge 8) {
        $tail | Write-Host
        Stop-Install "copy $Source → $Destination failed (robocopy exit code $exitCode)"
    }
    $global:LASTEXITCODE = 0
}

# Stops when the program is running: its database files are locked, and on exit it would write over what was copied.
function Assert-NotRunning([string[]] $Process) {
    $running = Get-Process -Name $Process -ErrorAction SilentlyContinue
    if ($running) { Stop-Install "$($Process -join ', ') is running: close it first (also in the tray)" }
}

# Empty folder at $Path (whatever was there is removed).
function Reset-Folder([string] $Path) {
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Get-StatusObject([int] $Code, [string] $Text, [string[]] $Profiles, [string] $Source, [string[]] $Process) {
    [pscustomobject] @{ Code = $Code; Text = $Text; Profiles = @($Profiles); Source = $Source; Process = $Process }
}

function Get-ProfileCountText([string[]] $Profiles) {
    "$($Profiles.Count) profile$(if ($Profiles.Count -ne 1) { 's' })"
}


######
###### CHROMIUM (Chrome, Brave, Edge, ...)
######

# Inside each profile folder: caches (rebuilt by the browser).
$ChromiumSkipDirs = @(
    'Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'GrShaderCache',
    'ShaderCache', 'blob_storage', 'Service Worker\CacheStorage', 'Service Worker\ScriptCache'
)
# Passwords and cookies (encrypted with this Windows user's key, useless on another machine).
$ChromiumSkipFiles = @(
    'Login Data', 'Login Data-journal', 'Login Data For Account', 'Login Data For Account-journal',
    'Cookies', 'Cookies-journal', 'Extension Cookies', 'Extension Cookies-journal',
    'Safe Browsing Cookies', 'Safe Browsing Cookies-journal'
)

# Profile folders of a "User Data" folder: those named in Local State (profile.info_cache) that exist,
# else the folders Default / Profile N.
function Get-ChromiumProfiles([string] $UserData) {
    if (-not (Test-Path -LiteralPath $UserData)) { return @() }
    $localState = Join-Path $UserData 'Local State'
    $names = @()
    if (Test-Path -LiteralPath $localState) {
        try {
            $state = Get-Content -Raw -LiteralPath $localState | ConvertFrom-Json -AsHashtable
            if ($state.profile -and $state.profile.info_cache) { $names = @($state.profile.info_cache.Keys) }
        }
        catch {
            Write-Warn "cannot read $localState ($($_.Exception.Message)), looking for profile folders"
        }
    }
    if (-not $names) {
        $names = @(Get-ChildItem -LiteralPath $UserData -Directory | Where-Object Name -match '^(Default|Profile \d+)$' | ForEach-Object Name)
    }
    @($names | Where-Object { Test-Path -LiteralPath (Join-Path $UserData $_) -PathType Container } | Sort-Object)
}

# Local State without os_crypt: the key there is encrypted for this Windows user; the browser makes a new one.
# System.Text.Json keeps every other value exactly as it was (ConvertFrom-Json would turn dates into DateTime).
function Copy-ChromiumLocalState([string] $Source, [string] $Destination) {
    $node = [System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -Raw -LiteralPath $Source))
    [void] $node.AsObject().Remove('os_crypt')
    Set-Content -LiteralPath $Destination -Value $node.ToJsonString() -Encoding utf8NoBOM -NoNewline
}

function Invoke-ChromiumAction([string] $Action, [string] $Folder, [string] $UserData, [string] $Process) {
    switch ($Action) {
        'status' {
            $profiles = Get-ChromiumProfiles $UserData
            if (-not $profiles) { return Get-StatusObject 1 'no profiles' @() $UserData $Process }
            return Get-StatusObject 0 (Get-ProfileCountText $profiles) $profiles $UserData $Process
        }
        'export' {
            Assert-NotRunning $Process
            $profiles = Get-ChromiumProfiles $UserData
            if (-not $profiles) { Stop-Install "no profiles in $UserData" }
            Reset-Folder $Folder
            $localState = Join-Path $UserData 'Local State'
            if (Test-Path -LiteralPath $localState) { Copy-ChromiumLocalState $localState (Join-Path $Folder 'Local State') }
            $position = 0
            foreach ($name in $profiles) {
                $position++
                $activity = "$(Split-Path $Folder -Leaf): $name ($position/$($profiles.Count))"
                Write-Host "    $activity" -ForegroundColor DarkGray
                Copy-Tree (Join-Path $UserData $name) (Join-Path $Folder $name) -SkipDirs $ChromiumSkipDirs -SkipFiles $ChromiumSkipFiles -Activity $activity
            }
            return $profiles
        }
        'import' {
            if (-not (Get-ChromiumProfiles $Folder)) { Stop-Install "no profiles in $Folder" }
            Assert-NotRunning $Process
            # The whole User Data folder becomes the export: other profiles, passwords, cookies and caches here are removed.
            Copy-Tree $Folder $UserData -Mirror -Activity "$(Split-Path $Folder -Leaf): import"
        }
        default { Stop-Install "unknown action: $Action (status | export <folder> | import <folder>)" }
    }
}


######
###### FIREFOX
######

# Inside each profile folder (the disk cache itself is under %LOCALAPPDATA%, not exported).
$FirefoxSkipDirs = @(
    'cache2', 'startupCache', 'thumbnails', 'shader-cache', 'crashes', 'minidumps', 'datareporting',
    'saved-telemetry-pings', 'storage\temporary'
)
# Passwords, cookies, Firefox account sign-in, the lock of a running Firefox.
$FirefoxSkipFiles = @(
    'logins.json', 'logins-backup.json', 'key4.db', 'cookies.sqlite', 'cookies.sqlite-wal', 'cookies.sqlite-shm',
    'signedInUser.json', 'parent.lock'
)

# Profiles in profiles.ini: Name, Path (relative, "\"), Relative.
function Get-FirefoxProfiles([string] $Root) {
    $ini = Join-Path $Root 'profiles.ini'
    if (-not (Test-Path -LiteralPath $ini)) { return @() }
    $current = $null
    $sections = @(foreach ($line in Get-Content -LiteralPath $ini) {
        $line = $line.Trim()
        if ($line -match '^\[(.+)\]$') {
            if ($current) { [pscustomobject] $current }
            $current = if ($Matches[1] -match '^Profile\d+$') { @{ Name = $null; Path = $null; Relative = $true } } else { $null }
        }
        elseif ($current -and $line -match '^(Name|Path|IsRelative)=(.*)$') {
            switch ($Matches[1]) {
                'Name'       { $current.Name = $Matches[2] }
                'Path'       { $current.Path = $Matches[2] -replace '/', '\' }
                'IsRelative' { $current.Relative = $Matches[2] -ne '0' }
            }
        }
    })
    if ($current) { $sections += [pscustomobject] $current }
    @($sections | Where-Object Path)
}

function Invoke-FirefoxAction([string] $Action, [string] $Folder, [string] $Root, [string] $Process) {
    switch ($Action) {
        'status' {
            $profiles = @(Get-FirefoxProfiles $Root | Where-Object { $_.Relative -and (Test-Path -LiteralPath (Join-Path $Root $_.Path)) })
            if (-not $profiles) { return Get-StatusObject 1 'no profiles' @() $Root $Process }
            return Get-StatusObject 0 (Get-ProfileCountText $profiles.Name) $profiles.Name $Root $Process
        }
        'export' {
            Assert-NotRunning $Process
            $all = Get-FirefoxProfiles $Root
            if (-not $all) { Stop-Install "no profiles in $(Join-Path $Root 'profiles.ini')" }
            Reset-Folder $Folder
            foreach ($file in 'profiles.ini', 'installs.ini') {
                $path = Join-Path $Root $file
                if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination (Join-Path $Folder $file) }
            }
            $position = 0
            $exported = foreach ($firefoxProfile in $all) {
                $position++
                $source = Join-Path $Root $firefoxProfile.Path
                if (-not $firefoxProfile.Relative) { Write-Warn "profile $($firefoxProfile.Name) is outside $Root ($($firefoxProfile.Path)), skipped"; continue }
                if (-not (Test-Path -LiteralPath $source)) { Write-Warn "profile $($firefoxProfile.Name): $source not found, skipped"; continue }
                $activity = "$(Split-Path $Folder -Leaf): $($firefoxProfile.Name) ($position/$($all.Count))"
                Write-Host "    $activity" -ForegroundColor DarkGray
                Copy-Tree $source (Join-Path $Folder $firefoxProfile.Path) -SkipDirs $FirefoxSkipDirs -SkipFiles $FirefoxSkipFiles -Activity $activity
                $firefoxProfile.Name
            }
            return @($exported)
        }
        'import' {
            if (-not (Test-Path -LiteralPath (Join-Path $Folder 'profiles.ini'))) { Stop-Install "no profiles.ini in $Folder" }
            Assert-NotRunning $Process
            # The whole Firefox folder becomes the export: other profiles, passwords and cookies here are removed.
            Copy-Tree $Folder $Root -Mirror -Activity "$(Split-Path $Folder -Leaf): import"
        }
        default { Stop-Install "unknown action: $Action (status | export <folder> | import <folder>)" }
    }
}
