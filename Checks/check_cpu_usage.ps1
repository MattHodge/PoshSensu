Param
(
    # Warning Threshold 
    [Parameter(Mandatory=$false)]
    [int]
    $WarningThreshold = 80,

    # Error Threshold 
    [Parameter(Mandatory=$false)]
    [int]
    $ErrorThreshold = 90
)

$cpu = Get-WmiObject win32_processor

if ($cpu.LoadPercentage -ge $ErrorThreshold)
{
    $sensu_status = 2
    $output = "CPU Load Percentage Over Error Threshold of $($ErrorThreshold)% - Currently $($cpu.LoadPercentage)%"
}
elseif ($cpu.LoadPercentage -gt $WarningThreshold)
{
    $sensu_status = 1
    $output = "CPU Load Percentage Over Warning Threshold of $($WarningThreshold)% - Currently $($cpu.LoadPercentage)%"
}
else
{
    $sensu_status = 0
    $output = "CPU Load Percentage OK - $($cpu.LoadPercentage)%"
}

$metricObject = @{
    cpu_name = $cpu.Name
    cpu_cores = $cpu.NumberOfCores
    cpu_logicalprocessors = $cpu.NumberOfLogicalProcessors
    output = $output
    status = $sensu_status
}

return $metricObject
