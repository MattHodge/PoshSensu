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
}
else
{
    $sensu_status = 0
}

$metricObject = @{
    service_display_name = $srv.DisplayName
    dependant_services = $srv.DependentServices | Select-Object -ExpandProperty Name
    required_services = $srv.RequiredServices | Select-Object -ExpandProperty Name
    output = $srv.Status.ToString()
    status = $sensu_status
}

return $metricObject
