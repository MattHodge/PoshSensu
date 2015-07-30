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

$mem = Get-CimInstance -ClassName Win32_OperatingSystem | Select FreePhysicalMemory,TotalVisibleMemorySize
$metricObject = @{}

# Get A Percent Value
$percentFree = ($mem.FreePhysicalMemory / $mem.TotalVisibleMemorySize) * 100

# Minus the percentage value from 100 (to get used percentage)
$percentUsed = 100 - $percentFree

# Round the Percentage for Text Output
$percentUsed = [math]::Round($percentUsed)

$totalMemory = [math]::Round($mem.TotalVisibleMemorySize / 1KB)
$freeMemory = [math]::Round($mem.FreePhysicalMemory / 1KB)
$usedMemory = $totalMemory - $freeMemory

# Return total and free memory as MB
$metricObject.total_memory_mb = "$($totalMemory)MB"
$metricObject.free_memory_mb = "$($freeMemory)MB"
$metricObject.used_memory_mb = "$($usedMemory)MB"

if ($percentUsed -ge $ErrorThreshold)
{
    $sensu_status = 2
    $output = "Memory Usage Percentage Over Error Threshold of $($ErrorThreshold)% - Currently $($percentUsed)% Memory Used ($($metricObject.used_memory_mb)/$($metricObject.total_memory_mb))"
}
elseif ($percentUsed -gt $WarningThreshold)
{
    $sensu_status = 1
    $output = "Memory Usage Percentage Over Warning Threshold of $($WarningThreshold)% - Currently $($percentUsed)% Memory Used ($($metricObject.used_memory_mb)/$($metricObject.total_memory_mb))"
}
else
{
    $sensu_status = 0
    $output = "Memory Usage Percentage OK - $($percentUsed)% Memory Used ($($metricObject.used_memory_mb)/$($metricObject.total_memory_mb))"
}

# Return results
$metricObject.output = $output
$metricObject.status = $sensu_status

return $metricObject