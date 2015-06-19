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
        $jobCommands += '$returnObject = @{}'
        
        # Validates each check first
        ForEach ($check in $checkgroup.checks)
        {
            # Using this instead of Resolve-Path so any warnings can provide the full path to the expected check location
            $checkScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path -Path $Config.checks_directory -ChildPath $check.command))
        
            # Check if the check actually exists
            if (Test-Path -Path $checkScriptPath)
            {
                #$validatedChecks.($checkgroup.group_name) += $check

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
        if ($jobCommands -ne '$returnObject = @{}')
        {
            $jobCommands += 'return $returnObject'
            
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


    # Handle job timeouts / statuses
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    ForEach ($checkgroup in $Config.check_groups)
    { 
        Write-Verbose "Finding matching background job for $($checkgroup.group_name).. "
        ForEach ($job in $backgroundJobs)
        {   
            Write-Verbose "==> Checking Against $($job.Name).. "
            # Match up the job to the check_group
            if ($checkgroup.group_name -eq $job.Name) 
            {
                Write-Verbose "[✔] Match Found!"
                # Wait up until the groups max_execution_time minus the current time it has taken to process checks so far
                $job | Wait-Job -Timeout ($checkgroup.max_execution_time - $stopwatch.Elapsed.TotalSeconds) | Out-Null
                
                # Stop the job
                $job | Stop-Job

                if ($job.State -eq 'Completed')
                {
                    # Receive job results
                    $jobResults = $job | Receive-Job

                    # Remove the job
                    $job | Remove-Job -Force

                    # Process each check to add additional attributes
                    ForEach ($check in $checkgroup.checks)
                    {
                        # Process each returned object from the job
                        ForEach ($result in $jobResults)
                        {
                            # If there is a result for the check
                            if ($result.($check.name) -ne $null)
                            {
                                Write-Verbose "[✔] Check ""$($check.name)"" has a result! Merging data from the configuration file with the check result."

                                # Turn the result into a PSObject (is currently a Deserialized.System.Collections.Hashtable)
                                $resultObject = $result.($check.name) | ConvertTo-Json | ConvertFrom-Json

                                # Get all the properties of the result
                                $result_properties = (Get-Member -InputObject $resultObject -MemberType Properties).Name

                                # Join the results to the check configuration (builds the object with more properties to send on
                                ForEach ($property in $result_properties)
                                {
                                    Add-Member -InputObject $check -MemberType NoteProperty -Name $property -Value $result.($check.name).$property
                                }

                                # Get all the properties of the check group, execept for the checks
                                $group_properties = (Get-Member -InputObject $checkgroup -MemberType Properties | Where-Object { $_.Name -ne 'checks' } ).Name

                                # Join the results from the group
                                ForEach ($property in $group_properties)
                                {
                                    Add-Member -InputObject $check -MemberType NoteProperty -Name $property -Value $checkgroup.$property
                                }

                                Write-Output $check | ConvertTo-Json
                            }
                        }
                    }

                    #Write-Output $jobResults | ConvertTo-Json
                }
                elseif ($job.State -eq 'Failed')
                {
                    Write-Warning "[X] Fail running background job for check group ""$($checkgroup.group_name)"""
                    Write-warning "[X] Reason: $($job.ChildJobs[0].JobStateInfo.Reason)" 
                }
                # Job had to be stopped
                elseif ($job.State -eq 'Stopped')
                {
                    Write-Warning "[X] Maximum execution time for job group ""$($checkgroup.group_name)"" was exceeded. Will send any checks that completed through."
                    Write-warning "[X] max_execution_time: $($checkgroup.max_execution_time)" 
                }
                else
                {
                    Write-Warning "[X] Job group ""$($checkgroup.group_name)"" finished with unknown state. Please verify your check scripts manually."
                    Write-warning "[X] Unexpceted Job State: $($job.State)" 
                }                
            }
        }
    }

    $stopwatch.Stop()
    Write-Verbose "Total Execution Time For ($($backgroundJobs.Length)) background jobs: $($stopwatch.Elapsed.TotalSeconds)"
}