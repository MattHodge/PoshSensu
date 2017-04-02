Function Import-JsonConfig
{
<#
    .Synopsis
        Loads the JSON Config File for PoshSensu.

    .Description
        Loads the JSON Config File for PoshSensu.

    .Parameter ConfigPath
        Full path to the configuration JSON file.

    .Example
        Import-JsonConfig -ConfigPath C:\PoshSensu\poshsensu_config.json

    .Notes
        NAME:      Import-JsonConfig
        AUTHOR:    Matthew Hodgkins
        WEBSITE:   http://www.hodgkins.net.au

#>
    [CmdletBinding()]
    Param
    (
        # Configuration File Path
        [Parameter(Mandatory = $true)]
        $ConfigPath
    )

    $Config = Get-Content -Path $ConfigPath | Out-String | ConvertFrom-Json

    # If checks directory is '.\Checks', this needs to be searched in the module path.
    if ($Config.checks_directory -eq '.\Checks')
    {
        $Config.checks_directory = Join-Path -Path $here -ChildPath 'Checks'
    }

    $checksFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Config.checks_directory)

    if (-not(Test-Path -Path $checksFullPath))
    {
        throw "Configuration File Error: check_path in the configuration file does not exist ($checksFullPath)."
    }

    # If check groups is empty, make an empty array as we will have some checks to add from the additional config files
    if ([string]::IsNullOrEmpty($Config.check_groups))
    {
        $Config.check_groups = @()
    }

    # Folder containing check group additional configuration files

    # Check if value is not null or empty
    if (-not([string]::IsNullOrEmpty($Config.check_groups_path)))
    {
        if (Test-Path -Path $Config.check_groups_path)
        {
            # Get only the json files
            $additionalChecks = Get-ChildItem -Path $Config.check_groups_path -Include "*.json" -Recurse

            # Loop through each and add to check groups
            ForEach ($ac in $additionalChecks)
            {
                Write-Verbose "Adding CheckGroup configuration file $($Config.check_groups_path)"
                $cg = Get-Content -Path $ac.FullName | Out-String | ConvertFrom-Json
                $Config.check_groups += $cg
            }
        }
        else
        {
            throw "Configuration File Error: check_groups_path in the configuration file does not exist ($($Config.check_groups_path))"
        }
    }

    # Sort the checks by max exeuction time so they can be started first
    $Config.check_groups = $Config.check_groups | Sort-Object -Property max_execution_time

    # Add the date when the configuration file was last written
    Add-Member -InputObject $Config –NotePropertyName last_config_update –NotePropertyValue (Get-Item -Path $ConfigPath).LastWriteTime

    Return $Config
}

function Start-BackgroundCollectionJob
{
    [CmdletBinding()]
    Param
    (
        # Job Name
        [Parameter(Mandatory=$true)]
        $Name,
    
        # Specifies the arguments (parameter values) for the script.
        $ArgumentList,

        # Specifies the commands to run in the background job. Enclose the commands in braces ( { } ) to create a script block. 
        $ScriptBlock,

        # Specifies commands that run before the job starts. Enclose the commands in braces ( { } ) to create a script block.
        $InitializationScript
    )
    
    $Config = Import-JsonConfig -ConfigPath $configPath

    $loggingDefaults = @{
        'Path' = Join-Path -ChildPath $Config.logging_filename -Path $Config.logging_directory
        'MaxFileSizeMB' = $Config.logging_max_file_size_mb
        'ModuleName' = $MyInvocation.MyCommand.Name
        'ShowLevel' = $Config.logging_level
    }

    # Remove any jobs with the same name as the one that is going to be created
    Remove-Job -Name $Name -Force -ErrorAction SilentlyContinue

    $job = Start-Job -Name $Name -ArgumentList $ArgumentList -ScriptBlock $ScriptBlock -InitializationScript $InitializationScript

    Write-PSLog @loggingDefaults -Method DEBUG -Message "Started Background job '$($Name)'"

    return $job

}

<#
    .Synopsis
        Tests the state of a background collection job.

    .Description
        Tests the state of a background collection job and returns the job results as JSON if there is data. If there is no data or there is an error, returns false.

    .Parameter Job
        A PSRemotingJob object

    .Example
        Test-BackgroundCollectionJob -Job $job

        Tests a job in the variable $job

    .Notes
        NAME:      Test-BackgroundCollectionJob
        AUTHOR:    Matthew Hodgkins
        WEBSITE:   http://www.hodgkins.net.au

#>
function Test-BackgroundCollectionJob
{
    [CmdletBinding()]
    Param
    (
        # Job Name
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.Job]
        $Job
    )

    $Config = Import-JsonConfig -ConfigPath $configPath

    $loggingDefaults = @{
        'Path' = Join-Path -ChildPath $Config.logging_filename -Path $Config.logging_directory
        'MaxFileSizeMB' = $Config.logging_max_file_size_mb
        'ModuleName' = $MyInvocation.MyCommand.Name
        'ShowLevel' = $Config.logging_level
    }

    $testedJob = $Job | Get-Job

    if (($testedJob.State -eq 'Running') -and ($testedJob.HasMoreData -eq $true))
    {
        $jobResults = $testedJob | Receive-Job
        Write-PSLog @loggingDefaults -Method DEBUG -Message "Backgound Running and Has Data ::: Check group: $($testedJob.Name)"
            
        # Check if the results are not null (even though HasMoreData is true, sometimes there may not be data)
        if ([string]::IsNullOrEmpty($jobResults))
        {
            return $false
        }
        else
        {
            # Convert to and from JSON as the data is a serialized object
            return $jobResults | ConvertTo-Json | ConvertFrom-Json
        }
    }
    elseif ($testedJob.State -eq 'Failed')
    {
        Write-PSLog @loggingDefaults -Method WARN -Message "Failed Backgound Job ::: Check group: $($testedJob.Name) Reason: $($testedJob.ChildJobs[0].JobStateInfo.Reason)"
        return $false
    }
    # Job had to be stopped
    elseif ($testedJob.State -eq 'Stopped')
    {
        Write-PSLog @loggingDefaults -Method WARN -Message "Stopped Backgound Job ::: Check group: $($testedJob.Name) Reason: There is something that is breaking the infinate loop that should have occured."
        return $false
    }
    else
    {
        Write-PSLog @loggingDefaults -Method WARN -Message "Unexpected Result From Backgound Job ::: Check group: $($testedJob.Name) Job State: $($testedJob.State) Extra Help: Please verify your check scripts manually"
        return $false
    }  
}

<#
.Synopsis
   Merges an array of HashTables or PSObjects into a single object.
.DESCRIPTION
   Merges an array of HashTables or PSObjects into a single object, with the ability to filter properties.
.EXAMPLE
   Merge-HashtablesAndObjects -InputObjects $lah,$ChecksToValidate -ExcludeProperties checks

   Merges the $lah HashTable and $ChecksToValidate PSObject into a single PSObject.
#>
Function Merge-HashtablesAndObjects {
    [CmdletBinding(DefaultParameterSetName='Name')]
    Param (
        #
        # Add parametersetname for recursive. We should accept a PSObject as 'baseobject' etc.
        #
        # An array of hashtables or PSobjects to merge.
        [Parameter(
            Position = 0,
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'Name')
        ]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        $InputObjects, #

        # Array of properties to exclude
        [Parameter(
            Position = 1, 
            Mandatory = $false, 
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName = 'Name')
        ]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $ExcludeProperties, #

        # Overrides memebers when adding objects
        [Parameter(
            Mandatory = $false,
            ParameterSetName = 'Name')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [Switch]
        $Force #
    )

    Begin {
        $returnObject = New-Object -TypeName PSObject
    }
    Process {
        $InputObjects | ForEach-Object {
            $cur_obj = $_
            $props = $null

            # Grab properties
            if ($cur_obj -is [System.Collections.Hashtable]) {
                $props = $cur_obj.keys
            } elseif ($cur_obj -is [System.Management.Automation.PSCustomObject]) {
                $props = (Get-Member -InputObject $cur_obj -MemberType Properties).Name
            }

            # Filter out unwanted props
            If($ExcludeProperties) {
                $props = $props | Where-Object { $ExcludeProperties -notcontains $_ }
            }

            $recurse_typenames = @()
            $recurse_typenames += 'System.Collections.HashTable'
            $recurse_typenames += 'System.Management.Automation.PSCustomObject'
			#$recurse_typenames += 'System.Object[]'

            # Merge
            $props | ForEach-Object {
                $cur_prop_name = $null
                $cur_prop_name = $_
                $cur_value = $null
                $cur_value = $cur_obj.$cur_prop_name
                
                $final_val = $null
                If($null -eq $cur_value -or "" -eq $cur_value) {
                } Else {
                    $cur_val_type_name = $null
                    $cur_val_type_name = $cur_value.PSObject.TypeNames[0]

                    If($recurse_typenames -contains $cur_val_type_name) {
                        $final_val = Merge-HashtablesAndObjects $cur_value # Returns PSObject
                    } Else {
                        $final_val = $cur_value
                    }
                }

                Add-Member -InputObject $returnObject -MemberType NoteProperty -Name $cur_prop_name -Value $final_val -Force:$Force
            }
        }
    }
    End {
		$json_output = convertto-json $returnObject -Depth 10 -Compress
		Write-PSLog @loggingDefaults -Method DEBUG -Message "Merge result: $json_output"
        return $returnObject
    }
}

<#
.Synopsis
   Sends data to ComputerName via TCP
.DESCRIPTION
   Sends data to ComputerName via TCP
.EXAMPLE
   "houston.servers.webfrontend.nic.intel.bytesreceived-sec 24 1434309804" | Send-DataTCP -ComputerName 10.10.10.162 -Port 2003

   Sends a Graphite Formated metric via TCP to 10.10.10.162 on port 2003
#>
function Send-DataTCP
{
    [CmdletBinding()]
    Param
    (
        [CmdletBinding()]
        # The data to send via TCP
        [Parameter(Mandatory=$true, 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   ValueFromRemainingArguments=$false, 
                   Position=0)]
        $Data,

        # The Host or IP Address to send the metrics to
        [Parameter(Mandatory=$true)]
        $ComputerName,

        # The port to send TCP data to
        [Parameter(Mandatory=$true)]
        $Port
    )

    # If there is no data, do nothing. No good putting it in the Begin or process blocks
    if (!$Data)
    {
        return
    }
    else
    {     
        $Config = Import-JsonConfig -ConfigPath $configPath

        $loggingDefaults = @{
            'Path' = Join-Path -ChildPath $Config.logging_filename -Path $Config.logging_directory
            'MaxFileSizeMB' = $Config.logging_max_file_size_mb
            'ModuleName' = $MyInvocation.MyCommand.Name
            'ShowLevel' = $Config.logging_level
        }

        try
        {
            $socket = New-Object System.Net.Sockets.TCPClient
            $socket.Connect($ComputerName, $Port)
            $stream = $socket.GetStream()
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.WriteLine($Data)
            $writer.Flush()
            Write-Verbose "Sent via TCP to $($ComputerName) on port $($Port)."
        }
        catch
        {
            Write-PSLog @loggingDefaults -Method ERROR -Message "$_"
        }
        finally
        {
            # Clean up - Checks if variable is set without throwing error.
            if (Test-Path variable:SCRIPT:writer)
            {
                $writer.Dispose()
            }
            if (Test-Path variable:SCRIPT:stream)
            {
                $stream.Dispose()
            }
            if (Test-Path variable:SCRIPT:socket)
            {
                $socket.Dispose()
            }

            [System.GC]::Collect()
        }
    }
}

<#
.Synopsis
   Returns a list of valid checks from the PoshSensu configuation file.
.DESCRIPTION
   Returns a list of valid checks from the PoshSensu configuation file by testing if the checks exist on the disk.
.EXAMPLE
   Import-SensuChecks -Config $Config
#>
function Import-SensuChecks
{
    [CmdletBinding()]
    Param
    (
        # The PSObject Containing PoshSensu Configuration 
        [Parameter(Mandatory=$true)]
        [PSCustomObject]
        $Config
    )

    $Config = Import-JsonConfig -ConfigPath $configPath

    $loggingDefaults = @{
        'Path' = Join-Path -ChildPath $Config.logging_filename -Path $Config.logging_directory
        'MaxFileSizeMB' = $Config.logging_max_file_size_mb
        'ModuleName' = $MyInvocation.MyCommand.Name
        'ShowLevel' = $Config.logging_level
    }

    $returnObject = @()

    # $Config.check_groups is ordered by max_execution_time
    ForEach ($checkgroup in $Config.check_groups)
    {   
        
        Write-PSLog @loggingDefaults -Method DEBUG -Message "Verifiying Checks ::: Group Name: $($checkgroup.group_name)"
                   
        # Validates each check first
        ForEach ($check in $checkgroup.checks)
        {              
            $checkPath = (Join-Path -Path $Config.checks_directory -ChildPath $check.command)
            # Using this instead of Resolve-Path so any warnings can provide the full path to the expected check location
            $checkScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($checkPath)
            Write-PSLog @loggingDefaults -Method DEBUG -Message "Looking For Check In ::: '$checkScriptPath'"
        
            # Check if the check actually exists
            if (Test-Path -Path $checkScriptPath)
            {

                $checkObject = New-Object PSObject -Property @{            
                        Group = $checkgroup.group_name           
                        TTL = $checkgroup.ttl
                        Interval = $checkgroup.interval
                        Name = $check.Name              
                        Path = $checkScriptPath
                        Arguments = $check.arguments
                }

                $returnObject += $checkObject

                Write-PSLog @loggingDefaults -Method DEBUG -Message "Check Added ::: Name: $($check.Name) Path: $($checkScriptPath)"
            }
            else
            {
                Write-PSLog @loggingDefaults -Method WARN -Message "Check Not Found ::: Name: '$($check.Name)' Path: '$($checkScriptPath)'."
            }
        }
    }

    return $returnObject
}

<#
.Synopsis
   Formats Sensu Checks into seperate code blocks to be run as background jobs.
.DESCRIPTION
   Pass in valid Sensu Checks from the Import-SensuChecks command into this command to format them into code blocks to be run as background jobs.
.EXAMPLE
   $backgroundJobs = Import-SensuChecks -Config $Config | Format-SensuChecks
#>
function Format-SensuChecks
{
    [CmdletBinding()]
    Param
    (
        # Valid Checks from Import-SensuChecks
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$false)
        ]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        $SensuChecks
    )

    $returnArray = @{}

    $Config = Import-JsonConfig -ConfigPath $configPath

    $loggingDefaults = @{
        'Path' = Join-Path -ChildPath $Config.logging_filename -Path $Config.logging_directory
        'MaxFileSizeMB' = $Config.logging_max_file_size_mb
        'ModuleName' = $MyInvocation.MyCommand.Name
        'ShowLevel' = $Config.logging_level
    }
    
    # Build an array of unique check groups
    $arrayOfGroups = @()

    ForEach ($cg in ($SensuChecks | Select-Object Group -Unique))
    {
        Write-Verbose "Found '$($cg.Group)' check group."

        # Add the unique groups to the array
        $arrayOfGroups += $cg.Group
        
        # Create an array under each checkgroup property
        $returnArray.($cg.Group) = @()
    }
        
    # Build the wrapper code for the start of each background job
    ForEach ($checkgroup in $arrayOfGroups)
    {
        # Only grab one of the tests from the group so we can access the Interval and TTL
        $SensuChecks | Where-Object { $_.Group -eq $checkgroup } | Get-Unique | ForEach-Object {

            Write-Verbose "Adding header code for '$($_.Group)' check group."

            # Create the pre-job steps
            $jobCommand =
            "
                # Create endless loop
                while (`$true) {
                
                    # Create stopwatch to track how long all the jobs are taking
                    `$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                    `$returnObject = @{}
                
                    # Build Logging Object
                    `$loggingDefaults = @{}
                    `$loggingDefaults.Path = '$($loggingDefaults.Path)'
                    `$loggingDefaults.MaxFileSizeMB = $($loggingDefaults.MaxFileSizeMB)
                    `$loggingDefaults.ModuleName = 'Background Job [$($_.Group)]'
                    `$loggingDefaults.ShowLevel = '$($loggingDefaults.ShowLevel)'

                    # Scale the interval back by 4.5% to ensure that the checks in the background job complete in time
                    `$scaledInterval = $($_.Interval) - ($($_.Interval) * 0.045)

                    `Write-PSLog @loggingDefaults -Method DEBUG -Message ""Intervals ::: Check Group: $($_.Interval)s Check Group Scaled: `$(`$scaledInterval)s""
            "
            
            # Add this command into the script block            
            $returnArray.($_.Group) += $jobCommand

        }
    }
        
    ForEach ($check in $SensuChecks)
    {
        # Build the wrapper for each check. Escape variables will be resolved in the background job.
        $jobCommand = 
        "
            try
            {
                # Check if this is a function being passed or a not by checking for the ~ character at the start of the arugment
                if (""$($check.Arguments[0])"" -eq ""~"")
                {
                    # Dot source the function
                    . ""$($check.Path)""

                    # Strip the ~ and any space infront of the argument
                    `$cleanedArg = ""$($check.Arguments)"" -replace ""^~\s+"",""""

                    # Execute the function and its paramaters
                    `$returnObject.$($check.Name) = Invoke-Expression -Command `$cleanedArg

                }
                else
                {
                    # Dot sources the check .ps1 and passes arguments
                    `$returnObject.$($check.Name) = . ""$($check.Path)"" $($check.Arguments)
                }
            }
            catch
            {
                Write-PSLog @loggingDefaults -Method WARN -Message ""`$_""
            }
            finally
            {
                Write-PSLog @loggingDefaults -Method DEBUG -Message ""Check Complete ::: Name: $($check.Name) Execution Time: `$(`$stopwatch.Elapsed.Milliseconds)ms""
            }
        "
        Write-Verbose "Adding check code to '$($check.Group)' check group for check '$($check.Name)'"
            
        # Add this command into the script block            
        $returnArray.($check.Group) += $jobCommand
    }

    # Build the wrapper code for the end of each background job
    ForEach ($checkgroup in $arrayOfGroups)
    {
        # Only grab one of the tests from the group so we can access the Interval
        $SensuChecks | Where-Object { $_.Group -eq $checkgroup } | Get-Unique | ForEach-Object {
            
            Write-Verbose "Adding footer code for '$($_.Group)' check group."

            $jobCommand =
            "
                    # Return all the data from the jobs
                    Write-Output `$returnObject

                    Write-PSLog @loggingDefaults -Method DEBUG -Message ""Check Group Complete ::: Total Execution Time: `$(`$stopwatch.Elapsed.Milliseconds)ms""

                    `$stopwatch.Stop()

                    # Figure out how long to sleep for
                    `$timeToSleep = `$scaledInterval - `$stopwatch.Elapsed.Seconds

                    if (`$stopwatch.Elapsed.Seconds -lt `$scaledInterval)
                    {
                        # Wait until the interval has been reached for the check.
                        Start-Sleep -Seconds `$timeToSleep
                        Write-PSLog @loggingDefaults -Method DEBUG -Message ""Sleeping Check Group :::  Sleep Time: `$(`$timeToSleep)s""
                    }
                    else
                    {
                        Write-Warning ""Job Took Longer Than Interval! Starting It Again Immediately""
                    }

                    [System.GC]::Collect()
                }# End while loop
            "

            # Add this command into the script block            
            $returnArray.($_.Group) += $jobCommand
        }
    }

    # Convert the value of each check group into a script block
    ForEach ($group in $returnArray.GetEnumerator().Name)
    {
        $returnArray.$group = [scriptblock]::Create($returnArray.$group)
    }

    return $returnArray

}