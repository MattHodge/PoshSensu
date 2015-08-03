<#
.Synopsis
   Returns the usage percentage of a volume.
.DESCRIPTION
   Provide a disk identifier, either VolumeName, VolumeSerialNumber, DeviceID, Caption or Name and its value and the volume usage percentage will be returned along with other useful volume information.
.EXAMPLE
   Get-VolumePercentUsed -Identifier DeviceID -Value 'C:' -WarningThreshold 70 -ErrorThreshold 80

   Returns the volume usage percentage for the disk with the DeviceID 'C:' and returns an output on the Warning and Error thresholds specified.
.EXAMPLE
   Get-VolumePercentUsed -Identifier VolumeName -Value DATA

   Returns the volume usage percentage for the disk with the VolumeName 'DATA' and returns output on the default Warning (80) and Error (90) thresholds.
#>
function Get-VolumePercentUsed
{

    Param
    (
        # Warning Threshold 
        [Parameter(Mandatory=$false)]
        [int]
        $WarningThreshold = 80,

        # Error Threshold 
        [Parameter(Mandatory=$false)]
        [int]
        $ErrorThreshold = 90,

        # The property used to idenfitfy a Disk
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("VolumeName", "VolumeSerialNumber", "DeviceID", "Caption", "Name")]
        $Identifier,

        # The value of the property used to identify a disk
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        $Value
    )


    $disk = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.Description -eq 'Local Fixed Disk' } | Where-Object { $_.($Identifier) -eq $Value }

    $metricObject = @{}
    $metricObject.disk_identifier_passed = $Identifier
    $metricObject.disk_value_passed = $Value
    $metricObject.disk_name = $disk.Name
    $metricObject.disk_volumename = $disk.VolumeName
    $metricObject.disk_volume_serial = $disk.VolumeSerialNumber
    $metricObject.disk_device_id = $disk.DeviceID
    $metricObject.disk_caption = $disk.Caption
    $metricObject.disk_filesystem = $disk.FileSystem


    # Find % Free
    $freePercentage = ($disk.FreeSpace / $disk.Size) * 100
    $freePercentage = [math]::Round($freePercentage)
    $usagePercent = 100 - $freePercentage

    $metricObject.disk_percent_free = "$($freePercentage)%"
    $metricObject.disk_percent_used = "$($usagePercent)%"

    $totalsize = [math]::Round($disk.Size / 1GB)
    $freesize = [math]::Round($disk.FreeSpace / 1GB)
    $usedSize = $totalsize - $freesize

    $metricObject.disk_size_gb = "$($totalsize)GB"
    $metricObject.disk_free_gb = "$($freesize)GB"
    $metricObject.disk_used_gb = "$($usedSize)GB"

    if ($usagePercent -ge $ErrorThreshold)
    {
        $metricObject.status = 2
        $metricObject.output = "Disk Used Percentage Over Error Threshold of $($ErrorThreshold)% - Currently $($usagePercent)% Space Used ($($metricObject.disk_used_gb)/$($metricObject.disk_size_gb))"
    }
    elseif ($usagePercent -gt $WarningThreshold)
    {
        $metricObject.status = 1
        $metricObject.output = "Disk Used Percentage Over Warning Threshold of $($WarningThreshold)% - Currently $($usagePercent)% Space Used ($($metricObject.disk_used_gb)/$($metricObject.disk_size_gb))"
    }
    else
    {
        $metricObject.status = 0
        $metricObject.output = "Disk Used Percentage OK - $($usagePercent)% Space Used ($($metricObject.disk_used_gb)/$($metricObject.disk_size_gb))"
    }

    return $metricObject
}
