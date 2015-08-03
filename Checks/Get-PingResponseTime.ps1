<#
.Synopsis
   Used to test ping response time to a server
.DESCRIPTION
   Provide a ComputerName (Host or IP Address), and a WarningThreshold and ErrorThreshold in ms to test a machine.
.EXAMPLE
   Get-PingResponseTime -ComputerName 8.8.8.8 -WarningThreshold 50 -ErrorThreshold 70

   Perform a ping test to the google DNS server.
#>
function Get-PingResponseTime
{

    Param
    (
        # Name or IP address of the remote host to perform a ping test
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName,

        # Warning Threshold For Ping Response Time (ms)
        [Parameter(Mandatory=$true)]
        [int]
        $WarningThreshold,

        # Error Threshold For Ping Response Time (ms)
        [Parameter(Mandatory=$true)]
        [int]
        $ErrorThreshold
    )

    $metricObject = @{}
    
    $preTest = Test-Connection -ComputerName $ComputerName -Quiet -Count 2 -ErrorVariable pingfail -ErrorAction SilentlyContinue

    # Verify we can ping the machine first
    if ($preTest)
    {
        $results = Test-Connection -ComputerName $ComputerName -ErrorAction SilentlyContinue

        $totalPingTime = 0
        $pingCount = 0

        # Get an Average Ping Time
        ForEach ($r in $results)
        {
            $totalPingTime = $TotalPingTime + $r.ResponseTime
            $metricObject."ping_$($pingCount)" = "$($r.ResponseTime)ms"
            $pingCount++
        }

        $avgPingTime = $totalPingTime / $results.Count

        $metricObject.avg_ping_time = "$($avgPingTime)ms"

        if ($avgPingTime -ge $ErrorThreshold)
        {
            $sensu_status = 2
            $output = "Ping response time over Error Threshold of $($ErrorThreshold)ms - Currently $($avgPingTime)ms"
        }
        elseif ($avgPingTime -gt $WarningThreshold)
        {
            $sensu_status = 1
            $output = "Ping response time over Over Warning Threshold of $($WarningThreshold)ms - Currently $($avgPingTime)ms"
        }
        else
        {
            $sensu_status = 0
            $output = "Ping response time OK - $($avgPingTime)ms"
        }
    }
    else
    {
        $sensu_status = 2
        $output = "No ping response from $($ComputerName)! Cannot ping server"
    }

    $metricObject.output = $output
    $metricObject.status = $sensu_status
    $metricObject.computer_pinged = $ComputerName
    
    
    return $metricObject
}
