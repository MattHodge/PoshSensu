Set-StrictMode -Version Latest
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Determine The Path Of The XML Config File
$configPath = [string](Split-Path -Parent $MyInvocation.MyCommand.Definition) + '\poshsensu_config.json'

# Load all .ps1 files
. $here\Functions\Internal.ps1

$ps1s = Get-ChildItem -Path ("$here\Functions\") -Filter *.ps1

ForEach ($ps1 in $ps1s)
{
    . $ps1.FullName
}

$functionsToExport = @(
    'Start-SensuChecks'
)

Export-ModuleMember -Function $functionsToExport