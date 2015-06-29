<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Start-SensuChecks
{
    [CmdletBinding()]
    Param
    (

    )

    $Config = Import-JsonConfig -ConfigPath $configPath

    $loggingDefaults = @{
        'Path' = Join-Path -ChildPath $Config.logging_filename -Path $Config.logging_directory
        'MaxFileSizeMB' = $Config.logging_max_file_size_mb
        'ModuleName' = $MyInvocation.MyCommand.Name
        'ShowLevel' = $Config.logging_level
    }

    # Create array hold background jobs
    $backgroundJobs = @()

    # Get list of valid checks
    $validChecks = Import-SensuChecks -Config $Config

    # Build the background jobs
    $bgJobsScriptBlocks = Format-SensuChecks -SensuChecks $validChecks

    $modulePath = "$(Split-Path -Path $PSScriptRoot)\PoshSensu.psd1"
    $initScriptForJob = "Import-Module '$($modulePath)'"
    $initScriptForJob = [scriptblock]::Create($initScriptForJob)

    ForEach ($bgJobScript in $bgJobsScriptBlocks.GetEnumerator())
    {
        Write-PSLog @loggingDefaults -Method INFO -Message "Creating Background Job ::: Check Group: $($bgJobScript.Key)"

        # Start background job. InitializationScript loads the PoshSensu module
        $backgroundJobs += Start-BackgroundCollectionJob -Name "$($bgJobScript.Key)" -ScriptBlock $bgJobScript.Value -InitializationScript $initScriptForJob
    }

    # Start infinate loop to read job info
    while($true)
    {
        # Handle job timeouts / statuses
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Create variable to track if this is the first run
        $firstRun = $true

        # Process each background job that was started
        ForEach ($job in $backgroundJobs)
        {
            # Test the job and save the results
            $jobResult = Test-BackgroundCollectionJob -Job $job

            # If the job tests ok, process the results
            if ($jobResult -ne $false)
            {
                # First run has occured
                $firstRun = $false

                # Get a list of all the checks for this check group
                $ChecksToValidate = $Config.check_groups | Where-Object { $_.group_name -eq $job.Name }

                # Go through each check, trying to match it up with a result
                ForEach ($check in $ChecksToValidate.checks)
                {
                    # If there is a property on job result matching the check name 
                    if (Get-Member -InputObject $jobResult -Name $check.name -MemberType Properties)
                    {
                        Write-PSLog @loggingDefaults -Method DEBUG -Message "Check Result Returned. Merging Data From Config File ::: Check Name: $($check.name)"

                        # Merge all the data about the job and return it
                        $finalCheckResult = Merge-HashtablesAndObjects -InputObjects $jobResult.($check.name),$ChecksToValidate,$check -ExcludeProperties 'checks' | ConvertTo-Json -Compress
                        Write-PSLog @loggingDefaults -Method DEBUG -Message "Check Result ::: Check Name: $($check.name) Result: $finalCheckResult"

                        $finalCheckResult | Send-DataTCP -ComputerName $Config.sensu_socket_ip -Port $Config.sensu_socket_port
                    }
                    else
                    {
                        Write-PSLog @loggingDefaults -Method WARN -Message "Check Has No Result ::: Check Name: $($check.name) Additonal Help: Verify the check by running it manually out side of PoshSensu"
                    }
                }
            }
        }

        $stopwatch.Stop()

        # If this is the first run and no data has come back yet, sleep for a second and try again
        if ($firstRun)
        {
            Start-Sleep -Seconds 2
            Write-PSLog @loggingDefaults -Method INFO -Message "No Data From Background Jobs ::: Details: No data has been returned from background jobs yet. Looping again quickly to see if any data has been returend yet."
        }
        # If this is not the first run, sleep until the next interval
        else
        {
            # Sleep for the lowest interval minus how long this run took
            $lowestInterval = ($Config.check_groups.interval | Sort-Object)[0]
            $sleepTime = ($lowestInterval - $stopwatch.Elapsed.TotalSeconds)
            Write-PSLog @loggingDefaults -Method INFO -Message "All Background Jobs Complete ::: Total Background Job(s): $($backgroundJobs.Length) Total Time Taken: $($stopwatch.Elapsed.Seconds)s Sleeping For: $($sleepTime)s"
            Start-Sleep -Seconds ($lowestInterval - $stopwatch.Elapsed.TotalSeconds)
        }
    }
    
}