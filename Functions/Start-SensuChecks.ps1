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

    # $Config.check_groups is ordered by max_execution_time
    ForEach ($checkgroup in $Config.check_groups)
    {   
        Write-PSLog @loggingDefaults -Method DEBUG -Message "Verifiying Checks for $($checkgroup.group_name)"

        # Create the framework commands for the job
        $jobCommands = @()
        # Create endless loop
        $jobCommands += 'while ($true) {'
        # Create stopwatch to track how long all the jobs are taking
        $jobCommands += '$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()'
        $jobCommands += '$returnObject = @{}'

        # Create variable to keep track of if a check is actually added to a job
        $jobToBeRun = 0
                    
        # Validates each check first
        ForEach ($check in $checkgroup.checks)
        {   
            $checkPath = (Join-Path -Path $Config.checks_directory -ChildPath $check.command)
            # Using this instead of Resolve-Path so any warnings can provide the full path to the expected check location
            $checkScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($checkPath)
            Write-PSLog @loggingDefaults -Method DEBUG -Message "Looking for check at '$checkScriptPath'"
        
            # Check if the check actually exists
            if (Test-Path -Path $checkScriptPath)
            {
                $jobToBeRun++

                Write-PSLog @loggingDefaults -Method DEBUG -Message "Current count of jobs to be run in this check group: $jobToBeRun"
                Write-PSLog @loggingDefaults -Method DEBUG -Message "Added Check to Job:"
                Write-PSLog @loggingDefaults -Method DEBUG -Message "  Check Name: $($check.Name)"
                Write-PSLog @loggingDefaults -Method DEBUG -Message "  Check Path: $($checkScriptPath)"

                # Build the command to run the collect and check the output
                # An Example:
                # $returnObject.my_check_name = . "C:\Sensu\Checks\my_check.ps1" -Name Value

                # Build Logging Object
                $jobCommands += '$loggingDefaults = @{}'
                $jobCommands += '$loggingDefaults.Path = ' + "'$($loggingDefaults.Path)'"
                $jobCommands += '$loggingDefaults.MaxFileSizeMB = ' + "'$($loggingDefaults.MaxFileSizeMB)'"
                $jobCommands += '$loggingDefaults.ModuleName = ' + "'BackgroundJob_$($checkgroup.group_name)'"
                $jobCommands += '$loggingDefaults.ShowLevel = ' + "'$($loggingDefaults.ShowLevel)'"
                # Create a try / catch block
                $jobCommands += 'try {'
                $jobCommands += '$returnObject.' + "$($check.Name)" + " = . ""$($checkScriptPath)"" $($check.arguments)"
                $jobCommands += '}'
                # Make any errors log from the catch blog
                $jobCommands += 'catch { Write-PSLog @loggingDefaults -Method WARN -Message "$_" }'
                $jobCommands += "Write-PSLog @loggingDefaults -Method DEBUG -Message ""The check $($check.Name) took " + '$($stopwatch.Elapsed.Milliseconds)' + " milliseconds to execute."""
                $jobCommands += '[System.GC]::Collect()'
            }
            else
            {
                Write-PSLog @loggingDefaults -Method WARN -Message "Check Load Error: Unable to find check '$($check.Name)'. Not adding to the job"
            }
        }

        # If there are job commands for the group, create a background job
        if ($jobToBeRun -gt 0)
        {
            $jobCommands += 'Write-Output $returnObject'
            $jobCommands += '$stopwatch.Stop()'
            $jobCommands += 'Write-Verbose "Total time taken was $($stopwatch.Elapsed.Milliseconds) milliseconds."'
            $jobCommands += 'if ($stopwatch.Elapsed.Seconds -le ' + "$($checkgroup.ttl)" + ') { Start-Sleep -Seconds (' + "$($checkgroup.ttl)" + ' - $stopwatch.Elapsed.Seconds) } '
            $jobCommands += 'else { Write-Warning "Job took longer than ttl! Starting Immediately" }'
            $jobCommands += '}'
            
            Write-PSLog @loggingDefaults -Method INFO -Message "Creating background job for check group ""$($checkgroup.group_name)"""

            # Split the array into new lines and create a script block        
            $scriptBlock = [Scriptblock]::Create($jobCommands -join "`r`n")

            $modulePath = "$(Split-Path -Path $PSScriptRoot)\PoshSensu.psd1"
            $initScriptForJob = "Import-Module '$($modulePath)'"
            $initScriptForJob = [scriptblock]::Create($initScriptForJob)

            # Start background job
            $backgroundJobs += Start-BackgroundCollectionJob -Name "$($checkgroup.group_name)" -ScriptBlock $scriptBlock -InitializationScript $initScriptForJob
        }
        else
        {
            Write-PSLog @loggingDefaults -Method WARN -Message "Check group ""$($checkgroup.group_name)"" has no valid checks. Not creating background job."
        }
    }

    # Start infinate loop to read job info
    while($true)
    {
        # Handle job timeouts / statuses
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Process each background job that was started
        ForEach ($job in $backgroundJobs)
        {
            # Test the job and save the results
            $jobResult = Test-BackgroundCollectionJob -Job $job

            # If the job tests ok, process the results
            if ($jobResult -ne $false)
            {
                # Get a list of all the checks for this check group
                $ChecksToValidate = $Config.check_groups | Where-Object { $_.group_name -eq $job.Name }

                # Go through each check, trying to match it up with a result
                ForEach ($check in $ChecksToValidate.checks)
                {
                    # If there is a property on job result matching the check name
                    if (Get-Member -InputObject $jobResult -Name $check.name -MemberType Properties)
                    {
                        Write-PSLog @loggingDefaults -Method DEBUG -Message "Check ""$($check.name)"" has a result! Merging data from the configuration file with the check result."

                        # Merge all the data about the job and return it
                        $finalCheckResult = Merge-HashtablesAndObjects -InputObjects $jobResult.($check.name),$ChecksToValidate,$check -ExcludeProperties 'checks' | ConvertTo-Json -Compress
                        Write-PSLog @loggingDefaults -Method DEBUG -Message "Check Result:"
                        Write-PSLog @loggingDefaults -Method DEBUG -Message "  $finalCheckResult"

                        $finalCheckResult | Send-DataTCP -ComputerName $Config.sensu_socket_ip -Port $Config.sensu_socket_port
                    }
                    else
                    {
                        Write-PSLog @loggingDefaults -Method WARN -Message "Check ""$($check.name)"" does not have a result! Verify the test script exists or it returns a result when run manually."
                    }
                }
            }
        }

        $stopwatch.Stop()
        Write-PSLog @loggingDefaults -Method INFO -Message "Total Execution Time For ($($backgroundJobs.Length)) background jobs: $($stopwatch.Elapsed.TotalSeconds)"

        # Sleep for the smallest ttl minus how long this run took
        $lowestTTL = ($Config.check_groups.ttl | Sort-Object)[0]
        $sleepTime = ($lowestTTL - $stopwatch.Elapsed.TotalSeconds)
        Write-PSLog @loggingDefaults -Method DEBUG -Message "All processing finished. Sleeping for $($sleepTime) seconds"
        Start-Sleep -Seconds ($lowestTTL - $stopwatch.Elapsed.TotalSeconds)
    }
    
}