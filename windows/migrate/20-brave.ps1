# Brave: all profiles (bookmarks, extensions, settings, history), no cache, passwords or cookies
param([string] $Action, [string] $Folder)
. (Join-Path $PSScriptRoot '..\scripts\lib.ps1')
. (Join-Path $PSScriptRoot '..\scripts\migrate-lib.ps1')

Invoke-ChromiumAction $Action $Folder -UserData (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data') -Process brave
