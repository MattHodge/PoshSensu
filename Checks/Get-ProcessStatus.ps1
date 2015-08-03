<#
.Synopsis
   Used to return the status of processes - if they are running or not and how many there are.
.DESCRIPTION
   Provide a process name and if you want it to be running or not. You can also provide an expected process count.
.EXAMPLE
   Get-ProcessStatus -ProcessName w3wp -ProcessRunning $true -ProcessCount 5

   Checks if the w3wp process is running and there are 5 instances of it
.EXAMPLE
   Get-ProcessStatus -ProcessName atom -ProcessRunning $false

   Checks to see if the atom process is not running. If it is running the check will fail.
#>
function Get-ProcessStatus
{

    Param
    (
        # The name of the process to check for
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ProcessName,

        # True to check if the process is running. False to check the process is not running
        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [boolean]
        $ProcessRunning = $true,

        # To count the amount of processes that are running
        [Parameter(Mandatory=$false)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(1,99999)]
        [int]
        $ProcessCount
    )

    $metricObject = @{}
    
    $process = Get-Process -ProcessName $ProcessName -ErrorAction SilentlyContinue

    # If user wants there to be a process running
    if ($ProcessRunning)
    {
        if ($process)
        {
            $metricObject.status = 0
            $metricObject.output = "Process Check OK: $($ProcessName) is running."
            $returnProcDetails = $true
        }
        else
        {
            $metricObject.status = 2
            $metricObject.output = "Process Check FAIL: $($ProcessName) is not running."
            $returnProcDetails = $false
        }
    }
    # If the user doesn't want there to be a process running
    else
    {
        if($process)
        {
            $metricObject.status = 2
            $returnProcDetails = $true
            $metricObject.output = "Process Check FAIL: $($ProcessName) is running and it shouldn't be."
        }
        else
        {
            $metricObject.status = 0
            $returnProcDetails = $false
            $metricObject.output = "Process Check OK: $($ProcessName) is not running and it shouldn't be."
        }
    }

    # If user is interested in process count
    if($ProcessCount)
    {
        # If the process count matches
        if ($process.Length -eq $ProcessCount)
        {
            $metricObject.status = 0
            $metricObject.output = "Process Check OK: There are $($ProcessCount) process named $($ProcessName) running."
            $returnProcDetails = $true
        }
        # If the process count doesn't match
        else
        {
            $metricObject.status = 2
            $returnProcDetails = $true
            $metricObject.output = "Process Check FAIL: There are $($process.Length) process named $($ProcessName) running when there should be $($ProcessCount)."
        }
    }

    
    $processCounter = 0
    # If returning proc details, loop through each of them and return them
    ForEach ($p in $process)
    {
        $metricObject."pid_$($p.Id)_processname" = $p.ProcessName
        $metricObject."pid_$($p.Id)_handles" = $p.Handles
        $metricObject."pid_$($p.Id)_path" = $p.Path
        $metricObject."pid_$($p.Id)_company" = $p.Company
        $metricObject."pid_$($p.Id)_fileversion" = $p.FileVersion
        $processCounter ++
    }

    $metricObject.total_proc_count = $processCounter

    return $metricObject
}
