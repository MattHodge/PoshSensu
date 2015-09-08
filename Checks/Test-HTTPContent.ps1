<#
.Synopsis
   Used to test for HTTP content on a web page
.DESCRIPTION
   Provide a Uri (URL) and content to match on a page.
.EXAMPLE
   Test-HTTPContent -Uri 'https://10.1.1.140' -IgnoreSSLErrors -ContentToMatch 'asdasd'

   Test to see if 'asdasd' is located on a page. Also ignores any SSL errors.
#>
function Test-HTTPContent
{

    Param
    (
        # Name or IP address of the remote host to perform a ping test
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        # RegEx for content to match
        [Parameter(Mandatory=$true)]
        [string]
        $ContentToMatch,

        # Ignore any SSL errors - default is false
        [Parameter(Mandatory=$false)]
        [switch]
        $IgnoreSSLErrors=$false
    )

    if ($IgnoreSSLErrors)
    {
        Add-Type @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class TrustAllCertsPolicy : ICertificatePolicy {
                public bool CheckValidationResult(
                    ServicePoint srvPoint, X509Certificate certificate,
                    WebRequest request, int certificateProblem) {
                    return true;
                }
            }
"@
        
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    }

    $metricObject = @{}
    
    try 
    {
        $content = Invoke-WebRequest -UseBasicParsing -Uri $Uri -ErrorAction Stop
        $metricObject.statuscode = $content.StatusCode
        $metricObject.statusdescription = $content.StatusDescription
        $metricObject.rawcontentlength = $content.RawContentLength

        # If content matches and it is supposed to
        if ($content.Content -match $ContentToMatch)
        {
            $sensu_status = 0
            $output = "Match FOUND on page $($Uri)"
        }
        else
        {
            $sensu_status = 2
            $output = "Match NOT FOUND on page $($Uri)"
            $metricObject.rawcontent = $content.RawContent
        }
    }
    catch
    {
        $sensu_status = 2
        $output = "Error trying to access page $($Uri)"
    }

    $metricObject.output = $output
    $metricObject.status = $sensu_status
    $metricObject.uri_tested = $Uri
    
    
    return $metricObject
}
