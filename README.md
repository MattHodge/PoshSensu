# PoshSensu
PoshSensu is a PowerShell module to handle running PowerShell scripts as Sensu checks. The results are submitted to a Sensu client via the [client socket input](https://sensuapp.org/docs/latest/clients#client-socket-input) feature that the Sensu client provides.

## Why Did I Make This Module?
The Sensu client already handles executing PowerShell checks, so you may be wondering why I wrote a module for this. This is why:
![CPU Spikes when opening PowerShell](https://i.imgur.com/0WhOjUf.gif)

When a PowerShell process first loads, there is a fairly large CPU impact - usually spiking to around 20-30% for a second or two. When you are running 20-30 PowerShell checks every minute on your servers, this adds up to a lot of wasted CPU cycles.

This module aims to resolve this problem.

## Features
* Sends check results to Sensu Cleint via TCP to the the [client socket input](https://sensuapp.org/docs/latest/clients#client-socket-input) feature
* Easily to use json configuration file
* Allows setting different check groups that may have different max execution times, ttl's or execution intervals
* Automatic configuration file reloads allowing adding additional checks without having to restart any services
* Detailed logging (can be turned off)
* Runs checks using PowerShell Background Jobs
* Rotates its own log file

## Installation
1. Download the repository and place into a PowerShell Modules directory called PoshSensu. The module directories can be found by running `$env:PSModulePath` in PowerShell. For example, `C:\Program Files\WindowsPowerShell\Modules\PoshSensu`
1. Make sure the files are un-blocked by right clicking on them and going to properties
1. Modify the `poshsensu_config.json` configuration file. Instructions here.
1. Open PowerShell and ensure you set your Execution Policy to allow scripts be run. For example `Set-ExecutionPolicy RemoteSigned`.

## Installing as a Service
```
Start-Process -FilePath .\nssm.exe -ArgumentList 'install PoshSensu "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" "-command "& { Import-Module -Name PoshSensu ; Start-SensuChecks }"" ' -NoNewWindow -Wait
Start-Process -FilePath .\nssm.exe -ArgumentList 'set PoshSensu DependOnService "Sensu Client"' -NoNewWindow -Wait
Start-Process -FilePath .\nssm.exe -ArgumentList 'set PoshSensu Description "PoshSensu - The PowerShell check runner for Sensu."' -NoNewWindow -Wait
Start-Service -Name PoshSensu
```

### Modifying the Configuration File

The following section details each setting in the configuration file.

**NOTE:** When using json configuration files, backslashes need to be escaped, for example `\` would be `\\`.

#### Main Configuration
Key | Default Value | Description
--- | --- | ---
sensu_socket_ip | `localhost` | IP address or host name of the Sensu client where check results will be sent via TCP
sensu_socket_port | `3030` | TCP Port of the Sensu client socket input
logging_enabled | `true` | Enable or disable logging to a file
logging_level | `debug` | Level of logging to perform. Valid options are `debug`, `info`, `warn`, `error`
logging_directory | `C:\\opt\\sensu` | Directory to store the log file. The directory will be created if it doesn't exist
logging_filename | `poshsensu.log` | Name for the log file
logging_max_file_size_mb | `10` | The size of the log file before it is rotated
checks_directory | `.\\Checks` | The directory that contains the PowerShell checks. Use a full path here except when the Checks directory is located in the module directory
check_groups | `N/A` | Array of check groups

#### Check Group Configuration
A Check Group is a grouping of checks. Each check group is run in its own PowerShell instance using Background Jobs.

The reason there is multiple check groups it to allow you to bundle checks together that have the same check interval.

You can additionally add any other json key/value for the check group and it will get sent to the Sensu client. All key/values in the check group configuration section (including the defaults) are sent to the Sensu server.

The below values can be configured for a check group:

Key | Example Value | Description
--- | --- | ---
group_name | `quickchecks` | Name of the check group. Useful to find the group in the log file
max_execution_time | `30` | Used to determine the check group run order. Does not currently have any other function.
ttl | `120` | Sent to Sensu so it knows how often the check should be received. If no message is received in this time period, Sensu will throw a warning.
interval | `60` | How often each check in this group needs to be run
checks | `N/A` | Array of checks

#### Check Configuration
A check is the PowerShell script that will be run, with the results being sent to the Sensu client.

Key | Example Value | Description
--- | --- | ---
name | `service_bits` | Name of the check that will be sent to Sensu
type | `metric` | The check type, either `standard` or `metric`. Setting type to metric will cause OK (exit 0) check results to create events. I recommend keeping this on `metric`
command | `check_service.ps1` | The file name of the check to execute in PowerShell. These checks are located in the `checks_directory` configuration value configured previously.
arguments | `-Name BITS` | Any arguments that are required to run the PowerShell check. Useful when using parameters in your checks.

## How To Write a PowerShell Check

Writing checks for use with the Sensu PowerShell module is quiet simple. The only requirement is that they return a PSObject or Hash with the mandatory fields `output` and `status`

It is also a good idea to parameterize your checks so they are more useful across multiple servers.

Mandatory Field | Example Value | Description
--- | --- | ---
output | `Serivce Check OK: The lanmanworkstation service is running.` | This is where the result or an explanation of the check status is returned
status | `1` | A number which relates to Sensu status code. `0` for `OK`, `1` for `WARNING`, `2` for `CRITICAL` and `3` or greater to indicate `UNKNOWN`

The check can also return key/value which will get sent to the Sensu client. This is handy for providing some more details on the check, for example in the `check_service.ps1` check, I am also retrieving `DisplayName`, `DependentServices`, `RequiredServices` and `Status` properties from the service object in PowerShell and returning them. These details show up when the check has a problem:

![Sensu Check Details](http://i.imgur.com/Tvd7nIM.png)

Take a look at some [example checks](https://github.com/MattHodge/PoshSensu/tree/master/Checks) to give yourself an idea how checks work.
