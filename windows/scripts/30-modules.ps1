# PowerShell modules used by the profile: posh-git, Terminal-Icons, DockerCompletion.
. (Join-Path $PSScriptRoot 'lib.ps1')

foreach ($name in 'posh-git', 'Terminal-Icons', 'DockerCompletion') {
    if (Get-Module -ListAvailable -Name $name) {
        Write-Ok "$name present"
    }
    elseif ($DotfilesDryRun) {
        Write-Would "install module $name"
    }
    else {
        Install-Module -Name $name -Scope CurrentUser -Force
        Write-Ok "$name installed"
    }
}
