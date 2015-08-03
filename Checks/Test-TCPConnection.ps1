function Test-TCPConnection
{
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ComputerName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [ValidateRange(1,65535)]
        [int]
        $Port
    )

    $test = New-Object System.Net.Sockets.TcpClient

    $metricObject = @{}

    Try
    {
        $test.Connect($ComputerName, $Port);
        $sensu_status = 0
        $output = "TCP connection successful to $($ComputerName):$($Port)"
    }
    Catch
    {
        $sensu_status = 2
        $output = "TCP connection failure to $($ComputerName):$($Port)"
    }
    Finally
    {
        $test.Dispose();
        $metricObject.status = $sensu_status
        $metricObject.output = $output
    }

    return $metricObject
}