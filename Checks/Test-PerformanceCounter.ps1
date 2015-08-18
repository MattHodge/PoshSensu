<#
.Synopsis
   Used to test a performance counter.
.DESCRIPTION
   Provide a performance counter and a WarningThreshold and ErrorThreshold to test the value. Test is performed 4 times and averaged.
.EXAMPLE
  Test-PerformanceCounter -Counter "\Memory\Available MBytes" -WarningThreshold 9800 -ErrorThreshold 10000

  Tests the memory a performance counter.
#>
function Test-PerformanceCounter 
{
    [CmdletBinding()]
    Param
    (
        # Performance Counter to Test
        [Parameter(Mandatory=$true)]
        $Counter,

        # Warning Threshold For The Counter
        [Parameter(Mandatory=$true)]
        [int]
        $WarningThreshold,

        # Error Threshold For The Counter
        [Parameter(Mandatory=$true)]
        [int]
        $ErrorThreshold
    )

    $metricObject = @{}

    $counterResult = Get-Counter -Counter $Counter -SampleInterval 1 -MaxSamples 4

    $totalValue = 0
    $testCount = 0

    ForEach ($cv in $counterResult.CounterSamples.CookedValue)
    {
        $totalValue += $cv
        $metricObject."cookedvalue_$($testCount)" = $cv
        $testCount++
    }

    $avgValue = $totalValue / $counterResult.CounterSamples.CookedValue.Length
    
    if ($avgValue -ge $ErrorThreshold)
    {
        $sensu_status = 2
        $output = "Counter ""$($Counter)"" over Error Threshold of $($ErrorThreshold) - Currently $($avgValue)"
    }
    elseif ($avgValue -gt $WarningThreshold)
    {
        $sensu_status = 1
        $output = "Counter ""$($Counter)"" over Warning Threshold of $($WarningThreshold) - Currently $($avgValue)"
    }
    else
    {
        $sensu_status = 0
        $output = "Counter ""$($Counter)"" OK - Currently $($avgValue)"
    }   

    $metricObject.counter_name = $Counter
    $metricObject.output = $output
    $metricObject.status = $sensu_status

    return $metricObject
}