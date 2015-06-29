Param
(
    # Name of Service to Check
    [Parameter(Mandatory=$true)]
    [string]$Name
)

$srv = Get-Service -Name $Name

if ($srv.Status -ne 'Running')
{
    $sensu_status = 2
    $output = "Serivce Check FAIL: The $($Name) service is not running."
}
else
{
    $sensu_status = 0
    $output = "Serivce Check OK: The $($Name) service is running."
}

$metricObject = @{
    service_display_name = $srv.DisplayName
    dependant_services = $srv.DependentServices | Select-Object -ExpandProperty Name
    required_services = $srv.RequiredServices | Select-Object -ExpandProperty Name
    service_status = $srv.Status.ToString()
    output = $output
    status = $sensu_status
}

return $metricObject
