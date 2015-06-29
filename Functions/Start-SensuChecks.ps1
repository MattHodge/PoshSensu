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
    
    <#
    # $Config.check_groups is ordered by max_execution_time
    ForEach ($checkgroup in $Config.check_groups)
    {   
        Write-PSLog @loggingDefaults -Method DEBUG -Message "Verifiying Checks ::: Group Name: $($checkgroup.group_name)"

        # Create the framework commands for the job
        $jobCommands = @()
        # Create endless loop
        $jobCommands += 'while ($true) {'
        # Create stopwatch to track how long all the jobs are taking
        $jobCommands += '$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()'
        $jobCommands += '$returnObject = @{}'
        # Build Logging Object
        $jobCommands += '$loggingDefaults = @{}'
        $jobCommands += '$loggingDefaults.Path = ''{0}''' -f $loggingDefaults.Path
        $jobCommands += '$loggingDefaults.MaxFileSizeMB = ''{0}''' -f $loggingDefaults.MaxFileSizeMB
        $jobCommands += '$loggingDefaults.ModuleName = ''Background Job [{0}]''' -f $checkgroup.group_name
        $jobCommands += '$loggingDefaults.ShowLevel = ''{0}''' -f $loggingDefaults.ShowLevel

        # Create variable to keep track of if a check is actually added to a job
        $jobToBeRun = 0

        # Scale the ttl back by 4.5% to ensure that the checks in the background job complete in time
        $scaledTTL = $checkgroup.ttl - ($checkgroup.ttl * 0.045)

        $jobCommands += 'Write-PSLog @loggingDefaults -Method DEBUG -Message "TTLs ::: Check Group: {0}s Check Group Scaled: {1}s"' -f $checkgroup.ttl,$scaledTTL
                    
        # Validates each check first
        ForEach ($check in $checkgroup.checks)
        {   
            $checkPath = (Join-Path -Path $Config.checks_directory -ChildPath $check.command)
            # Using this instead of Resolve-Path so any warnings can provide the full path to the expected check location
            $checkScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($checkPath)
            Write-PSLog @loggingDefaults -Method DEBUG -Message "Check Search Location ::: '$checkScriptPath'"
        
            # Check if the check actually exists
            if (Test-Path -Path $checkScriptPath)
            {
                $jobToBeRun++

                Write-PSLog @loggingDefaults -Method DEBUG -Message "Check Added ::: Number: $jobToBeRun Name: $($check.Name) Path: $($checkScriptPath)"

                # Build the command to run the collect and check the output
                # An Example:
                # $returnObject.my_check_name = . "C:\Sensu\Checks\my_check.ps1" -Name Value

                $jobCommands += 'try {' # Start of try block for the check
                $jobCommands += '$returnObject.{0} = . ''{1}'' {2}' -f $check.Name,$checkScriptPath,$check.arguments # Dot sources the check .ps1 and passes arguments
                $jobCommands += '}' # End of try block for the check
                $jobCommands += 'catch { Write-PSLog @loggingDefaults -Method WARN -Message "$_" }' # Log errors that occur in the check
                $jobCommands += 'Write-PSLog @loggingDefaults -Method DEBUG -Message "Check Complete ::: Name: {0} Execution Time: $($stopwatch.Elapsed.Milliseconds)ms"' -f $check.Name
                $jobCommands += '[System.GC]::Collect()'
            }
            else
            {
                Write-PSLog @loggingDefaults -Method WARN -Message "Check Not Found ::: Name: '$($check.Name)' Path: '$($checkScriptPath)'."
            }
        }

        # If there are job commands for the group, create a background job
        if ($jobToBeRun -gt 0)
        {          
            $jobCommands += 'Write-Output $returnObject' # 
            $jobCommands += '$stopwatch.Stop()'
            $jobCommands += 'Write-PSLog @loggingDefaults -Method DEBUG -Message "Check Group Complete ::: Total Execution Time: $($stopwatch.Elapsed.Milliseconds)ms"'
            $jobCommands += '$timeToSleep = {0} - $stopwatch.Elapsed.Seconds' -f $scaledTTL
            $jobCommands += 'if ($stopwatch.Elapsed.Seconds -lt {0}) {{ Start-Sleep -Seconds $timeToSleep ; Write-PSLog @loggingDefaults -Method DEBUG -Message "Sleeping Check Group :::  Sleep Time: $($timeToSleep)s" }}' -f $scaledTTL # Wait until the TTL has been reached for the check.
            $jobCommands += 'else { Write-Warning "Job Took Longer Than TTL! Starting It Again Immediately" }'
            $jobCommands += '}'
            
            Write-PSLog @loggingDefaults -Method INFO -Message "Creating Background Job ::: Check Group: $($checkgroup.group_name)"

            # Split the array into new lines and create a script block        
            $scriptBlock = [Scriptblock]::Create($jobCommands -join "`r`n")

            $modulePath = "$(Split-Path -Path $PSScriptRoot)\PoshSensu.psd1"
            $initScriptForJob = "Import-Module '$($modulePath)'"
            $initScriptForJob = [scriptblock]::Create($initScriptForJob)

            # Start background job. InitializationScript loads the PoshSensu module
            $backgroundJobs += Start-BackgroundCollectionJob -Name "$($checkgroup.group_name)" -ScriptBlock $scriptBlock -InitializationScript $initScriptForJob
        }
        else
        {
            Write-PSLog @loggingDefaults -Method WARN -Message "Group Has No Valid Checks ::: Check Group: $($checkgroup.group_name)"
        }
    }
    #>

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
        
        # Sleep for the smallest ttl minus how long this run took
        $lowestTTL = ($Config.check_groups.ttl | Sort-Object)[0]
        $sleepTime = ($lowestTTL - $stopwatch.Elapsed.TotalSeconds)
        Write-PSLog @loggingDefaults -Method INFO -Message "All Background Jobs Complete ::: Total Background Job(s): $($backgroundJobs.Length) Total Time Taken: $($stopwatch.Elapsed.Seconds)s Sleeping For: $($sleepTime)s"
        Start-Sleep -Seconds ($lowestTTL - $stopwatch.Elapsed.TotalSeconds)
    }
    
}