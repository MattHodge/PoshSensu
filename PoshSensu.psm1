Set-StrictMode -Version Latest
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Determine The Path Of The XML Config File
$configPath = [string](Split-Path -Parent $MyInvocation.MyCommand.Definition) + '\poshsensu_config.json'

$ps1s = Get-ChildItem -Path ("$here\Functions\") -Filter *.ps1

ForEach ($ps1 in $ps1s)
{
    Write-Verbose "Loading $($ps1.FullName)"
    . $ps1.FullName
}

$functionsToExport = @(
    'Start-SensuChecks'
)

Export-ModuleMember -Function $functionsToExport