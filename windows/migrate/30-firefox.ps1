# Firefox: all profiles (bookmarks, add-ons, settings, history), no cache, passwords, cookies or account sign-in
param([string] $Action, [string] $Folder)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')
. (Join-Path $PSScriptRoot '..\scripts\migrate-lib.ps1')

Invoke-FirefoxAction $Action $Folder -Root (Join-Path $env:APPDATA 'Mozilla\Firefox') -Process firefox
