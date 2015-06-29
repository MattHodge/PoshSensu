Import-Module .\PoshSensu.psd1 -Force

$json_prevalidatedSensuChecks = @"
[
    {
        "Arguments":  "-Name BITS",
        "TTL":  20,
        "Interval":  10,
        "Group":  "quickchecks",
        "Path":  "E:\\ProjectsGit\\PoshSensu\\Checks\\check_service.ps1",
        "Name":  "service_bits"
    },
    {
        "Arguments":  "-Name Spooler",
        "TTL":  20,
        "Interval":  10,
        "Group":  "quickchecks",
        "Path":  "E:\\ProjectsGit\\PoshSensu\\Checks\\check_service.ps1",
        "Name":  "service_spooler"
    },
    {
        "Arguments":  "-Name W32Time",
        "TTL":  40,
        "Interval":  20,
        "Group":  "slowchecks",
        "Path":  "E:\\ProjectsGit\\PoshSensu\\Checks\\check_service.ps1",
        "Name":  "service_w32time"
    }
]
"@

New-Variable -Scope Global -Name prevalidatedSensuChecks -Force -Value (ConvertFrom-Json -InputObject $json_prevalidatedSensuChecks)

InModuleScope PoshSensu {

    Describe "Format-SensuChecks" {
        
        $formatedChecks = Format-SensuChecks -SensuChecks $prevalidatedSensuChecks

        It "result should be a System.Collections.Hashtable" {
            $formatedChecks -is [System.Collections.Hashtable] | Should Be $true
        }
        It "result.slowchecks property is a System.Management.Automation.ScriptBlock" {
            $formatedChecks.slowchecks -is [System.Management.Automation.ScriptBlock] | Should Be $true
        }
        It "result.quickchecks property is a System.Management.Automation.ScriptBlock" {
            $formatedChecks.quickchecks -is [System.Management.Automation.ScriptBlock] | Should Be $true
        }
        It "result.quickchecks property contains a variable that hasn't been expanded called `$returnObject.service_bits" {
            $formatedChecks.quickchecks -match '\$returnObject\.service_bits' | Should be $true
        }
        It "result.quickchecks property contains a check for bits" {
            $formatedChecks.quickchecks -match '\"E:\\ProjectsGit\\PoshSensu\\Checks\\check_service.ps1\" -Name Bits' | Should be $true
        }
        It "result.quickchecks property contains a check for spooler" {
            $formatedChecks.quickchecks -match '\"E:\\ProjectsGit\\PoshSensu\\Checks\\check_service.ps1\" -Name Spooler' | Should be $true
        }
        It "result.slowchecks property contains a check for w32time" {
            $formatedChecks.slowchecks -match '\"E:\\ProjectsGit\\PoshSensu\\Checks\\check_service.ps1\" -Name W32Time' | Should be $true
        }
        It "result.quickchecks property does not contains a check for w32time" {
            $formatedChecks.quickchecks -match '\"E:\\ProjectsGit\\PoshSensu\\Checks\\check_service.ps1\" -Name W32Time' | Should be $false
        }
        It "result has 2 check groups" {
            $formatedChecks.GetEnumerator().Name.Length | Should be 2
        }
    }
}