# PowerShell 7 profile, managed in ~\.dotfiles\windows\powershell.
# Loaded from Documents\PowerShell\profile.ps1 by one line:
#   . "$HOME\.dotfiles\windows\powershell\profile.ps1"
# Machine-only settings: Documents\PowerShell\profile.local.ps1 (not in the repo), loaded last.

######
###### INSTALL (modules and tools this profile uses)
######

# Oh My Posh
# INSTALL: winget install JanDeDobbeleer.OhMyPosh -s winget
# UPGRADE: winget upgrade JanDeDobbeleer.OhMyPosh -s winget

## posh-git
# Install-Module posh-git -Scope CurrentUser -Force

## Terminal-Icons
# Install-Module Terminal-Icons -Scope CurrentUser -Force

## DockerCompletion
# Install-Module DockerCompletion -Scope CurrentUser -Force


######
###### ENCODING
######

[Console]::InputEncoding =
[Console]::OutputEncoding =
    [System.Text.UTF8Encoding]::new()


######
###### GLOBALS
######

$profileStopwatch =
    [System.Diagnostics.Stopwatch]::StartNew()

# ~\.dotfiles\windows
$dotfilesWindowsDir =
    Split-Path $PSScriptRoot -Parent

$cacheDir =
    Join-Path $env:LOCALAPPDATA "PowerShell\Cache"

if (-not (Test-Path $cacheDir)) {
    New-Item `
        -Path $cacheDir `
        -ItemType Directory `
        -Force |
        Out-Null
}

$profileTimings =
    [System.Collections.Generic.List[string]]::new()

# Modules that failed to load (warned once) and lazy completers already triggered.
$global:ProfileFailedModules =
    [System.Collections.Generic.HashSet[string]]::new()

$global:ProfileLazyLoaded =
    [System.Collections.Generic.HashSet[string]]::new()


######
###### HELPERS
######

# Imports a module by name (PowerShell picks the highest version) into the global scope, so it also works
# from a completer or an idle event. A missing or broken module warns once and returns $false.
function Import-ProfileModule {
    param (
        [Parameter(Mandatory)]
        [string] $Name
    )

    if (Get-Module $Name) {
        return $true
    }

    if ($global:ProfileFailedModules.Contains($Name)) {
        return $false
    }

    try {
        Import-Module `
            $Name `
            -Global `
            -ErrorAction Stop

        return $true
    }
    catch {
        [void] $global:ProfileFailedModules.Add($Name)

        Write-Warning "Module '$Name' not loaded (Install-Module $Name -Scope CurrentUser): $($_.Exception.Message)"

        return $false
    }
}


# Stub completer: nothing loads at startup. The first Tab after the command runs $Load (it imports the module,
# which registers its own completer in place of this stub) and passes that Tab on, so it already completes.
function Register-LazyCompleter {
    param (
        [Parameter(Mandatory)]
        [string] $CommandName,

        [Parameter(Mandatory)]
        [scriptblock] $Load
    )

    Register-ArgumentCompleter `
        -Native `
        -CommandName $CommandName `
        -ScriptBlock {
            param ($wordToComplete, $commandAst, $cursorPosition)

            # Second call means the real completer did not replace the stub: stop, no recursion.
            if (-not $global:ProfileLazyLoaded.Add($CommandName)) {
                return
            }

            if (-not (& $Load)) {
                return
            }

            (TabExpansion2 `
                -inputScript $commandAst.Extent.StartScriptPosition.GetFullScript() `
                -cursorColumn $cursorPosition).CompletionMatches
        }.GetNewClosure()
}


######
###### PSREADLINE
######

if ($host.Name -eq 'ConsoleHost') {

    # https://github.com/PowerShell/PSReadLine

    ## No profile:
    # pwsh -NoProfile

    ## Find installed versions:
    # Get-Module -ListAvailable PSReadLine

    ## INSTALL:
    # Install-Module PSReadLine -AllowPrerelease -Force

    ## UPGRADE:
    # Update-Module PSReadLine -AllowPrerelease -Force

    $sw =
        [System.Diagnostics.Stopwatch]::StartNew()

    Import-Module PSReadLine

    $sw.Stop()

    $profileTimings.Add(
        "PSReadLine $([Math]::Round($sw.Elapsed.TotalMilliseconds)) ms"
    )


    # First: -EditMode resets every key to that mode's defaults, so key handlers set before it are lost.
    Set-PSReadLineOption `
        -HistoryNoDuplicates `
        -EditMode Windows


    # Tab lists every completion under the line (arrows pick, Enter accepts, Esc cancels),
    # e.g. dlab-<Tab> shows all dlab commands; a single match completes at once.
    Set-PSReadLineKeyHandler `
        -Key Tab `
        -Function MenuComplete


    Set-PSReadLineOption `
        -PredictionSource History


    Set-PSReadLineOption `
        -PredictionViewStyle InlineView


    Set-PSReadLineOption `
        -ShowToolTips


    Set-PSReadLineKeyHandler `
        -Key UpArrow `
        -Function HistorySearchBackward


    Set-PSReadLineKeyHandler `
        -Key DownArrow `
        -Function HistorySearchForward


    Set-PSReadLineKeyHandler `
        -Chord "Ctrl+RightArrow" `
        -Function ForwardWord
}


######
###### OH MY POSH
######

$ompConfig =
    Join-Path $dotfilesWindowsDir "oh-my-posh\paradox.omp.json"

$ompCacheFile =
    Join-Path $cacheDir "oh-my-posh-init.ps1"

# The exe path found last time: no PATH search on every start.
$ompExePathFile =
    Join-Path $cacheDir "oh-my-posh-exe.txt"


$ompExePath =
    if (Test-Path $ompExePathFile) {
        Get-Content $ompExePathFile -TotalCount 1
    }

if (-not $ompExePath -or -not (Test-Path $ompExePath)) {

    $ompExePath =
        (Get-Command `
            oh-my-posh `
            -CommandType Application `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1).Source

    if ($ompExePath) {
        Set-Content `
            -Path $ompExePathFile `
            -Value $ompExePath `
            -Encoding UTF8
    }
}


if (-not $ompExePath) {

    Write-Warning "oh-my-posh not found, default prompt (winget install JanDeDobbeleer.OhMyPosh -s winget)."
}
else {

    $refreshOmpCache =
        -not (Test-Path $ompCacheFile)


    if (-not $refreshOmpCache) {

        $ompExe =
            Get-Item $ompExePath

        $ompCache =
            Get-Item $ompCacheFile


        #
        # Rebuild cache after Oh My Posh upgrade.
        #

        if ($ompExe.LastWriteTimeUtc -gt $ompCache.LastWriteTimeUtc) {
            $refreshOmpCache = $true
        }


        #
        # Rebuild cache when config changes.
        #

        if (Test-Path $ompConfig) {

            $ompConfigItem =
                Get-Item $ompConfig

            if ($ompConfigItem.LastWriteTimeUtc -gt $ompCache.LastWriteTimeUtc) {
                $refreshOmpCache = $true
            }
        }
    }


    if ($refreshOmpCache) {

        # init prints a fixed session id; the cache gets a new one per window, as a fresh init would.
        (& $ompExePath `
            init pwsh `
            --config $ompConfig) -replace
            '\$env:POSH_SESSION_ID = "[^"]*"',
            '$env:POSH_SESSION_ID = [guid]::NewGuid().ToString()' |
            Set-Content `
                -Path $ompCacheFile `
                -Encoding UTF8
    }


    $sw =
        [System.Diagnostics.Stopwatch]::StartNew()

    . $ompCacheFile

    $sw.Stop()

    $profileTimings.Add(
        "oh-my-posh $([Math]::Round($sw.Elapsed.TotalMilliseconds)) ms"
    )
}


######
###### TAB COMPLETION (loaded on the first Tab)
######

# git: posh-git
Register-LazyCompleter git {
    Import-ProfileModule posh-git
}

# docker: DockerCompletion
Register-LazyCompleter docker {
    Import-ProfileModule DockerCompletion
}

# task: https://taskfile.dev/ (completion script cached, rebuilt after a Task update)
Register-LazyCompleter task {

    $taskCompletionFile =
        Join-Path $cacheDir "task-completion.ps1"


    $taskCommand =
        Get-Command `
            task `
            -CommandType Application `
            -ErrorAction SilentlyContinue


    if (-not $taskCommand) {
        return $false
    }


    $refreshTaskCompletion =
        -not (Test-Path $taskCompletionFile)


    if (-not $refreshTaskCompletion) {

        $taskExe =
            Get-Item $taskCommand.Source

        $completionFile =
            Get-Item $taskCompletionFile


        #
        # Rebuild after Task update.
        #

        if ($taskExe.LastWriteTimeUtc -gt $completionFile.LastWriteTimeUtc) {
            $refreshTaskCompletion = $true
        }
    }


    if ($refreshTaskCompletion) {

        & $taskCommand.Source `
            --completion powershell |
            Set-Content `
                -Path $taskCompletionFile `
                -Encoding UTF8
    }


    . $taskCompletionFile

    $true
}


######
###### IDLE LOAD (once, right after the first prompt is shown)
######

# Terminal-Icons (icons in ls/dir/gci). Load time or failure: $ProfileIdleTimings
# (the event runs in the background, so a warning from it would not reach the console).
$null =
    Register-EngineEvent `
        -SourceIdentifier PowerShell.OnIdle `
        -MaxTriggerCount 1 `
        -Action {
            $sw =
                [System.Diagnostics.Stopwatch]::StartNew()

            $loaded =
                Import-ProfileModule Terminal-Icons

            $sw.Stop()

            $global:ProfileIdleTimings =
                if ($loaded) {
                    "Terminal-Icons $([Math]::Round($sw.Elapsed.TotalMilliseconds)) ms"
                }
                else {
                    "Terminal-Icons not loaded (Install-Module Terminal-Icons -Scope CurrentUser)"
                }
        }


######
###### ALIASES AND COMMANDS
######

Set-Alias `
    t `
    task

# dlab-* commands (dlab-help lists them)
. (Join-Path $PSScriptRoot "dlab.ps1")


######
###### LOCAL PROFILE (this machine only, not in the repo)
######

$localProfile =
    Join-Path (Split-Path $PROFILE.CurrentUserAllHosts -Parent) "profile.local.ps1"

if (Test-Path $localProfile) {

    $sw =
        [System.Diagnostics.Stopwatch]::StartNew()

    . $localProfile

    $sw.Stop()

    $profileTimings.Add(
        "local $([Math]::Round($sw.Elapsed.TotalMilliseconds)) ms"
    )
}


######
###### PROFILE PATH AND TIMINGS
######

# The loaded profile as a Ctrl+click link (OSC 8) in Windows Terminal and VS Code, opening it in VS Code
# (vscode://file/...); plain text elsewhere.
$profileLink =
    if ($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode') {
        "`e]8;;vscode://file/$($PSCommandPath.Replace('\', '/'))`e\$PSCommandPath`e]8;;`e\"
    }
    else {
        $PSCommandPath
    }

$profileStopwatch.Stop()

$profileTimings.Add(
    "total $([Math]::Round($profileStopwatch.Elapsed.TotalMilliseconds)) ms"
)

$profileTimings.Add(
    "later: Terminal-Icons (idle), posh-git, DockerCompletion, task (Tab)"
)

Write-Host "Profile: $profileLink"
Write-Host "Profile: $($profileTimings -join ' | ')"
