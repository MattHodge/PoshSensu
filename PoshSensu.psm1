Set-StrictMode -Version Latest
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$ps1s = Get-ChildItem -Path ("$here\Functions\") -Filter *.ps1

ForEach ($ps1 in $ps1s)
{
    Write-Verbose "Loading $($ps1.FullName)"
    . $ps1.FullName
}

$functionsToExport = @(
    'Start-SensuChecks'
    'Write-PSLog'
)

Export-ModuleMember -Function $functionsToExport