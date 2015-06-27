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

    $checksFullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Config.checks_directory)

    if (-not(Test-Path -Path $checksFullPath))
    {
        throw "Configuration File Error: check_path in the configuration file does not exist ($checksFullPath)."
    }

    # Sort the checks by max exeuction time so they can be started first
    $Config.check_groups = $Config.check_groups | Sort-Object -Property max_execution_time

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

function Test-BackgroundCollectionJob
{
    [CmdletBinding()]
    Param
    (
        # Job Name
        [Parameter(Mandatory=$true)]
        $Job
    )

    $Config = Import-JsonConfig -ConfigPath $configPath

    $loggingDefaults = @{
        'Path' = Join-Path -ChildPath $Config.logging_filename -Path $Config.logging_directory
        'MaxFileSizeMB' = $Config.logging_max_file_size_mb
        'ModuleName' = $MyInvocation.MyCommand.Name
        'ShowLevel' = $Config.logging_level
    }

    if (($job.State -eq 'Running') -and ($job.HasMoreData -eq $true))
    {
        # Turn the result into a PSObject (is currently a Deserialized.System.Collections.Hashtable)
        $jobResults = $job | Receive-Job

        # Check if the results are not null (even though HasMoreData is true, sometimes there may not be data)
        if ($jobResults -ne $null)
        {
            return $jobResults | ConvertTo-Json | ConvertFrom-Json
        }
        else
        {
            return $false
        }
    }
    elseif ($job.State -eq 'Failed')
    {
        Write-PSLog @loggingDefaults -Method WARN -Message "Fail running background job for check group '$($checkgroup.group_name)'"
        Write-PSLog @loggingDefaults -Method WARN -Message "  Reason: $($job.ChildJobs[0].JobStateInfo.Reason)" 
        return $false
    }
    # Job had to be stopped
    elseif ($job.State -eq 'Stopped')
    {
        Write-PSLog @loggingDefaults -Method WARN -Message "Background job stopped for some reason '$($checkgroup.group_name)'. There is something that is breaking the infinate loop that should have occured."
        return $false
    }
    else
    {
        Write-PSLog @loggingDefaults -Method WARN -Message "Job group '$($checkgroup.group_name)' finished with unknown state. Please verify your check scripts manually."
        Write-PSLog @loggingDefaults -Method WARN -Message "  Unexpceted Job State: $($job.State)"
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
function Merge-HashtablesAndObjects
{
    [CmdletBinding()]
    Param
    (
        # An array of hashtables or PSobjects to merge.
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        $InputObjects,

        # Array of properties to exclude
        [Parameter(
            Position=1, 
            Mandatory=$false, 
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $ExcludeProperties,

        # Overrides memebers when adding objects
        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [Switch]
        $Force
    )

    Begin
    {
        $returnObject = New-Object PSObject -Property @{}
    }
    Process
    {
        ForEach($o in $InputObjects)
        {
            if ($o -is [System.Collections.Hashtable])
            {
                $o.GetEnumerator() | Where-Object { $_.Key -notin $ExcludeProperties } |  ForEach-Object { 
                    Add-Member -InputObject $returnObject -MemberType NoteProperty -Name $_.Key -Value $_.Value -Force:$Force
                }
                
            }
            if ($o -is [System.Management.Automation.PSCustomObject])
            {
                 $properties = (Get-Member -InputObject $o -MemberType Properties).Name | Where-Object { $_ -notin $ExcludeProperties } 

                 ForEach ($p in $properties)
                 {
                    Add-Member -InputObject $returnObject -MemberType NoteProperty -Name $p -Value $o.$p -Force:$Force
                 }

            }
        }
    }
    End
    {
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

    $Config = Import-JsonConfig -ConfigPath $configPath

    $loggingDefaults = @{
        'Path' = Join-Path -ChildPath $Config.logging_filename -Path $Config.logging_directory
        'MaxFileSizeMB' = $Config.logging_max_file_size_mb
        'ModuleName' = $MyInvocation.MyCommand.Name
        'ShowLevel' = $Config.logging_level
    }

    # If there is no data, do nothing. No good putting it in the Begin or process blocks
    if (!$Data)
    {
        return
    }
    else
    {           
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