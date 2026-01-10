<#
.NOTES
    Author: < Thomas@klijnman.nl >
    Created: 10/06/2025
    Updated: 10/01/2026
    Version: 1.2.0
    GitHub: https://github.com/ThomasKlijnman/Invoke-RestRequest

    Special Thanks to: https://github.com/zh54321 for his inspiration on this module.

.DESCRIPTION
    A generic PowerShell module to simplify making requests to REST based API's and support for retries, pagination, and error handling.

#>

# region Invoke REST Request
function Invoke-RestRequest {
    [CmdletBinding()]
    param (
        # Mandatory parameters for authentication and request method
        [Parameter(Mandatory)]
        [string]$AccessToken,  # Bearer token for authentication. Advice to not store in plain text during usage.

        [Parameter(Mandatory)]
        [ValidateSet("GET", "POST", "PATCH", "PUT", "DELETE")]
        [string]$Method,  # HTTP method to use (GET, POST, PATCH, PUT, DELETE).

        [Parameter(Mandatory)]
        [string]$Uri,  # Relative URI (e.g. /users).

        # Optional parameters for request customization
        [hashtable]$Body,  # Request body as a PowerShell hashtable/object (will be converted to JSON).
        [int]$MaxRetries = 5,  # Specifies the maximum number of retry attempts for failed requests (Default: 5).
        [string]$ApiVersion = 'v1.0',  # Specifies the API version to target.
        [switch]$RawJson,  # If specified, returns the response as a raw JSON string instead of a PowerShell object.
        [string]$Proxy,  # Use a Proxy (e.g. -Proxy "http://127.0.0.1:8080").

        # Optional parameters for Invoke-RestMethod
        [hashtable]$IrmCustomParameters, # Additional Boolean only parameters to pass to IRM (e.g. SkipCertificateCheck, etc.) 
        [int]$IrmTimeout = 15, # Timeout in seconds for IRM (Default: 15 seconds).  
        [string]$IrmUserAgent = 'Rest API Client/1.0',  # Custom UserAgent string for the request.


        # Parameters for pagination and HTTP handling
        [switch]$DisablePagination,  # Prevents the function from automatically following @odata.nextLink for paginated results.
        [switch]$VerboseMode,  # Enables verbose logging to provide additional information about request processing.
        [switch]$Suppress404,  # Suppress 404 messages (e.g., if a queried User object is not found in the tenant).

        # For constructing the request
        [hashtable]$QueryParameters,  # Query parameters for more complex queries. (e.g. -QueryParameters @{ '$filter' = "startswith(displayName,'Alex')"} )
        [hashtable]$AdditionalHeaders,  # Add additional HTTP headers (e.g. for ConsistencyLevel).
        [int]$JsonDepthResponse = 10,  # Specifies the depth for JSON conversion (request). Useful for deeply nested objects in combination with -RawJson.

        # Optional base URI parameter
        [string]$ProvidedBaseUri  # Parameter for custom base URI for custom REST API endpoints.
    )
    
    # Default base URI for the Microsoft Graph API
    $BaseUri = "https://graph.microsoft.com/$ApiVersion"

    # Use provided base URI if available, otherwise use the default base URI
    $FullUri = if ($ProvidedBaseUri) { "$ProvidedBaseUri$Uri" } else { "$BaseUri$Uri" }


    #Add query parameters
    if ($QueryParameters) {
        $QueryString = ($QueryParameters.GetEnumerator() | 
            ForEach-Object { 
                "$($_.Key)=$([uri]::EscapeDataString($_.Value))" 
            }) -join '&'
        $FullUri = "$FullUri`?$QueryString"
    }
    

    #Define basic headers
    $Headers = @{
        Authorization  = "Bearer $AccessToken"
        'Content-Type' = 'application/json'
        'User-Agent'   = $IrmUserAgent
    }

    #Add custom headers if required
    if ($AdditionalHeaders) {
        $Headers += $AdditionalHeaders
    }

    $RetryCount = 0
    $Results = @()

    # Prepare Invoke-RestMethod parameters
    $irmParams = @{
        Uri             = $FullUri
        Method          = $Method
        Headers         = $Headers
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
    }

    # Add custom Invoke-RestMethod parameters
    if ($IrmCustomParameters) {
        foreach ($CustomParamKey in $IrmCustomParameters.Keys) {
            $irmParams[$CustomParamKey] = $IrmCustomParameters[$CustomParamKey]
        }
    }

    if ($Body) {
        $irmParams.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    if ($Proxy) {
        $irmParams.Proxy = $Proxy
    }

    do {
        try {
            if ($VerboseMode) { Write-Host "[*] Request [$Method]: $FullUri" }

            $Response = Invoke-RestMethod @irmParams

            if ($Response.PSObject.Properties.Name -contains 'value') {
                if ($Response.value.Count -eq 0) {
                    if ($VerboseMode) { Write-Host "[i] Empty 'value' array detected. Returning nothing." }
                    return
                } else {
                    $Results += $Response.value
                }
            } else {
                $Results += $Response
            }

            # Pagination handling
            while ($Response.'@odata.nextLink' -and -not $DisablePagination) {
                if ($VerboseMode) { Write-Host "[*] Following pagination link: $($Response.'@odata.nextLink')" }

                $irmParams.Uri = $Response.'@odata.nextLink'
                # Remove Body for paginated GET requests
                $irmParams.Remove('Body')

                $Response = Invoke-RestMethod @irmParams
                if ($Response.PSObject.Properties.Name -contains 'value') {
                    if ($Response.value.Count -eq 0) {
                        if ($VerboseMode) { Write-Host "[i] Empty 'value' array detected. Returning nothing." }
                        return
                    } else {
                        $Results += $Response.value
                    }
                } else {
                    $Results += $Response
                }
            }

            break
        }
        catch {
            $StatusCode = $_.Exception.Response.StatusCode.value__
            $StatusDesc = $_.Exception.Message
            # Map HTTP status code to a PowerShell ErrorCategory
            # Mappings based on:

            # Graph: https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/errors
            # SoftwareOne: https://docs.platform.softwareone.com/developer-resources/rest-api/errors-handling#common-errors
            # Azure Storage: https://learn.microsoft.com/en-us/rest/api/storageservices/common-rest-api-error-codes

            # PowerShell: https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.errorcategory

            switch ($StatusCode) {
                400 { $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidArgument }
                401 { $errorCategory = [System.Management.Automation.ErrorCategory]::AuthenticationError }
                403 { $errorCategory = [System.Management.Automation.ErrorCategory]::PermissionDenied }
                404 { $errorCategory = [System.Management.Automation.ErrorCategory]::ObjectNotFound }
                405 { $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidOperation }
                406 { $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidData }
                409 { $errorCategory = [System.Management.Automation.ErrorCategory]::ResourceExists }
                410 { $errorCategory = [System.Management.Automation.ErrorCategory]::ObjectNotFound }
                411 { $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidArgument }
                412 { $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidResult }
                413 { $errorCategory = [System.Management.Automation.ErrorCategory]::ResourceUnavailable }
                415 { $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidType }
                416 { $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidArgument }
                422 { $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidData }
                429 { $errorCategory = [System.Management.Automation.ErrorCategory]::LimitsExceeded }
                500 { $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidResult }
                501 { $errorCategory = [System.Management.Automation.ErrorCategory]::NotImplemented }
                502 { $errorCategory = [System.Management.Automation.ErrorCategory]::ProtocolError }
                503 { $errorCategory = [System.Management.Automation.ErrorCategory]::ResourceUnavailable }
                504 { $errorCategory = [System.Management.Automation.ErrorCategory]::OperationTimeout }
                507 { $errorCategory = [System.Management.Automation.ErrorCategory]::QuotaExceeded }
                509 { $errorCategory = [System.Management.Automation.ErrorCategory]::QuotaExceeded }
                default { $errorCategory = [System.Management.Automation.ErrorCategory]::NotSpecified }
            }

             if ($StatusCode -in @(429,500,502,503,504) -and $RetryCount -lt $MaxRetries) {
                $RetryAfter = $_.Exception.Response.Headers['Retry-After']
                if ($RetryAfter) {
                    Write-Host "[i] [$StatusCode] - Throttled. Retrying after $RetryAfter seconds..."
                    Start-Sleep -Seconds ([int]$RetryAfter)
                } elseif ($RetryCount -eq 0) {
                    Write-Host "[*] [$StatusCode] - Retrying immediately..."
                    Start-Sleep -Seconds 0
                } else {
                    $Backoff = [math]::Pow(2, $RetryCount)
                    Write-Host "[*] [$StatusCode] - Retrying in $Backoff seconds..."
                    Start-Sleep -Seconds $Backoff
                }
                $RetryCount++
            } else {
                if (-not ($StatusCode -eq 404 -and $Suppress404)) {
                    $msg = "[!] API request failed after $RetryCount retries. `nStatus: $StatusCode. `nMessage: $StatusDesc"
                    $exception = New-Object System.Exception($msg)   

                    $errorRecord = New-Object System.Management.Automation.ErrorRecord (
                        $exception,
                        "ApiRequestFailed",
                        $errorCategory,
                        $FullUri
                    )
                    
                    Write-Error $errorRecord
                }

                return
            }
        }
    } while ($RetryCount -le $MaxRetries)

    if ($RawJson) {
        return $Results | ConvertTo-Json -Depth $JsonDepthResponse
    }
    else {
        return $Results
    }
}
#endregion Invoke REST Request
