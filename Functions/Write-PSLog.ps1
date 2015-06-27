function Write-PSLog
{
    [CmdletBinding()]
    Param
    (
        # The log message to write
        [Parameter(Mandatory=$true)]
        $Message,

        # The method to display the log message
        [Parameter(Mandatory=$false)]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")]
        [string]
        $Method,

        # The Path to write the log message
        [Parameter(Mandatory=$false)]
        [string]
        $Path = $null,

        # The maximum file size in MB of the log before it rolls over
        [Parameter(Mandatory=$false)]
        [string]
        $MaxFileSizeMB,

        # The Module or Function That Is Logging
        [Parameter(Mandatory=$true)]
        $ModuleName,

        # The level of logging to show. This is useful when you only want to log and show error logs for instance
        [Parameter(Mandatory=$false)]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")]
        $ShowLevel = 'DEBUG'
    )

    Begin
    {
        # Create Log Directory
        if ($Path -ne $null)
        {
            # Get the paths directory
            $pathDir = Split-Path -Path $Path -Parent

            if (-not(Test-Path -Path $pathDir))
            {
                New-Item -Path $pathDir -ItemType Directory -Force | Out-Null
            }
        }

        $Message = "$(Get-Date -Format s) [$([System.Diagnostics.Process]::GetCurrentProcess().Id)] - $($ModuleName) - $($Method) - $($Message)"
    }
    Process
    {
        # Set values for if the type of log will be actually shown
        if ($ShowLevel -ne $null)
        {
            switch ($ShowLevel)
            {
                'DEBUG' { 
                    $showDebug = $true
                    $showInfo = $true
                    $showWarn = $true
                    $showError = $true
                 } 
                'INFO' { 
                    $showDebug = $false
                    $showInfo = $true
                    $showWarn = $true
                    $showError = $true
                 } 
                'WARN' { 
                    $showDebug = $false
                    $showInfo = $false
                    $showWarn = $true
                    $showError = $true
                 }  
                'ERROR' { 
                    $showDebug = $false
                    $showInfo = $false
                    $showWarn = $false
                    $showError = $true
                 } 
            }
        }

        function Write-LogFile
        {
            [CmdletBinding()]
            Param
            (
                # The Path of the file to write
                [Parameter(Mandatory=$true)]
                $Path,
        
                # Maximum size of the log files
                [int]
                $MaxFileSizeMB,

                # The Module or Function That Is Logging
                [Parameter(Mandatory=$true)]
                $ModuleName,

                # The log message to write
                [Parameter(Mandatory=$true)]
                $Message,

                # The method to display the log message
                [Parameter(Mandatory=$false)]
                [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")]
                [string]
                $Method
            )
        
            # Move the old log file over
            if (Test-Path -Path $Path)
            {
                $logFile = Get-Item -Path $Path

                # Convert log size to MB
                $logFileSizeInMB = ($logFile.Length / 1mb)

                if ($logFileSizeInMB -ge $MaxFileSizeMB)
                {
                    Move-Item -Path $Path -Destination "$($Path).old" -Force
                }
            }

            try
            {
                # setup some convenience variables to keep each line shorter
                $mode = [System.IO.FileMode]::Append
                $access = [System.IO.FileAccess]::Write
                $sharing = [IO.FileShare]::Read

                # create the FileStream and StreamWriter objects
                $fs = New-Object IO.FileStream($Path, $mode, $access, $sharing)
                $sw = New-Object System.IO.StreamWriter($fs)

                # write something and remember to call to Dispose to clean up the resources
                $sw.WriteLine($Message)
            }
            finally
            {
                if ($sw -ne $NULL)
                {
                    $sw.Dispose()
                }
                if ($fs -ne $NULL)
                {
                    $fs.Dispose()
                }
            }
        }
        
        $splathForWriteLogFile = @{
            'Path' = $Path
            'MaxFileSizeMB' = $MaxFileSizeMB
            'ModuleName' = $ModuleName
            'Message' = $Message
            'Method' = $Method
        }

        switch ($Method)
        {
            'DEBUG' { 
                if ($showDebug)
                { 
                    Write-Verbose $Message
                    
                    if ($Path -ne $null)
                    { 
                        Write-LogFile @splathForWriteLogFile
                    }
                }
                
            } 
            'INFO' { 
                if ($showInfo)
                { 
                    Write-Output $Message
                    
                    if ($Path -ne $null)
                    { 
                        Write-LogFile @splathForWriteLogFile
                    }
                }
            } 
            'WARN' {
                if ($showWarn)
                { 
                    Write-Warning $Message
                    
                    if ($Path -ne $null)
                    { 
                        Write-LogFile @splathForWriteLogFile
                    }
                }
            } 
            'ERROR' {
                if ($showError)
                { 
                    Write-Error $Message
                    
                    if ($Path -ne $null)
                    { 
                        Write-LogFile @splathForWriteLogFile
                    }
                }
            } 
        }

    }
    End
    {
    }
}