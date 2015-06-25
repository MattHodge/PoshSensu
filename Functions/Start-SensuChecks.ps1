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

    # Create array hold background jobs
    $backgroundJobs = @()

    # $Config.check_groups is ordered by max_execution_time
    ForEach ($checkgroup in $Config.check_groups)
    {   
        Write-Verbose "-----------------------------"
        Write-Verbose "Verifiying Checks for ""$($checkgroup.group_name)"":"
        Write-Verbose "-----------------------------"

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
            # Using this instead of Resolve-Path so any warnings can provide the full path to the expected check location
            $checkScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path -Path $Config.checks_directory -ChildPath $check.command))
        
            # Check if the check actually exists
            if (Test-Path -Path $checkScriptPath)
            {
                $jobToBeRun++

                Write-Verbose "[✔] Added Check to Job:"
                Write-Verbose "[✔] Check Name: $($check.Name)"
                Write-Verbose "[✔] Check Path: $($checkScriptPath)"
                Write-Verbose "-----------------------------"

                # Build the command to run the collect and check the output
                # An Example:
                # $returnObject.my_check_name = . "C:\Sensu\Checks\my_check.ps1" -Name Value

                $jobCommands += 'try {'
                $jobCommands += '$returnObject.' + "$($check.Name)" + " = . ""$($checkScriptPath)"" $($check.arguments)"
                $jobCommands += '}'
                $jobCommands += 'catch { }'
                $jobCommands += "Write-Verbose ""The check $($check.Name) took " + '$($stopwatch.Elapsed.Milliseconds)' + " milliseconds to execute."""
                $jobCommands += '[System.GC]::Collect()'
            }
            else
            {
                Write-Warning "[X] Check Load Error: Unable to find check. Not adding to the job."
                Write-Warning "[X] Check Name: $($check.Name)"
                Write-Warning "[X] Check Path: $($checkScriptPath)"
                Write-Warning "-----------------------------"
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
            
            Write-Verbose "[✔] Creating background job for check group ""$($checkgroup.group_name)"""
            Write-Verbose ""

            # Split the array into new lines and create a script block        
            $scriptBlock = [Scriptblock]::Create($jobCommands -join "`r`n")

            # Start background job
            $backgroundJobs += Start-BackgroundCollectionJob -Name "$($checkgroup.group_name)" -ScriptBlock $scriptBlock
        }
        else
        {
            Write-Verbose "[X] Check group ""$($checkgroup.group_name)"" has no valid checks. Not creating background job."
            Write-Verbose ""
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

            # Build array of results to send
            $checkResults = @()

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
                        Write-Verbose "[✔] Check ""$($check.name)"" has a result! Merging data from the configuration file with the check result."

                        # Merge all the data about the job and return it
                        $finalCheckResult = Merge-HashtablesAndObjects -InputObjects $jobResult.($check.name),$ChecksToValidate,$check -ExcludeProperties 'checks' | ConvertTo-Json -Compress
                        Write-Verbose "Check Result:"
                        Write-Verbose $finalCheckResult

                        $checkResults += $finalCheckResult 
                    }
                    else
                    {
                        Write-Warning "[X] Check ""$($check.name)"" does not have a result! Verify the test script exists or it returns a result when run manually."
                    }
                }
            }

            $checkResults | Send-DataTCP -ComputerName $Config.sensu_socket_ip -Port $Config.sensu_socket_port

        }

        $stopwatch.Stop()
        Write-Verbose "Total Execution Time For ($($backgroundJobs.Length)) background jobs: $($stopwatch.Elapsed.TotalSeconds)"

        # Sleep for the smallest ttl minus how long this run took
        $lowestTTL = ($Config.check_groups.ttl | Sort-Object)[0]
        $sleepTime = ($lowestTTL - $stopwatch.Elapsed.TotalSeconds)
        Write-Verbose "All processing finished. Sleeping for $($sleepTime) seconds"
        Start-Sleep -Seconds ($lowestTTL - $stopwatch.Elapsed.TotalSeconds)
    }
    
}