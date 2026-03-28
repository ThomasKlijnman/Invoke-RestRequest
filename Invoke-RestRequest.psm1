<#
.NOTES
    Author: < Thomas@klijnman.nl >
    Created: 10/06/2025
    Updated: 28/03/2026
    Version: 1.3.0
    GitHub: https://github.com/ThomasKlijnman/Invoke-RestRequest

    Special Thanks to: https://github.com/zh54321 for his original inspiration on this module.

.DESCRIPTION
    A generic PowerShell module to simplify making requests to REST based API's and support for retries, pagination, and error handling.

#>

#region Invoke REST Request
function Invoke-RestRequest {
    <#
    .SYNOPSIS
    Generic REST API wrapper with retry, pagination, caching and advanced request handling.

    .DESCRIPTION
    Invoke-RestRequest is a flexible wrapper around Invoke-RestMethod designed for working 
    with REST APIs such as Microsoft Graph and custom endpoints. It supports features like automatic pagination, retry logic with exponential backoff, and optional caching of responses to improve performance.

    See cmdlet parameters for detailed usage instructions.
    #>

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
        [switch]$SkipCertificateCheck, # For use to skip any TLS certificate validation; only supported to be used in Powershell 7+.

        # Optional parameters for Invoke-RestMethod
        [hashtable]$IrmCustomParameters, # Additional Boolean only parameters to pass to IRM. 
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
        [string]$ProvidedBaseUri,  # Parameter for custom base URI for custom REST API endpoints.

        # Cache-related parameters (OPTIONAL, default disabled)
        [switch]$UseCache,           # Enable caching for this request
        [string]$CacheKey,           # Unique cache identifier
        [switch]$SkipCache,          # Bypass cache for this request (force fresh data)
        [int]$CacheTtlSeconds       # TTL in seconds (optional)
    )
    
    
    # Default base URI for the Microsoft Graph API
    $BaseUri = "https://graph.microsoft.com/$ApiVersion"

    # Use provided base URI if available, otherwise use the default base URI
    $FullUri = if ($ProvidedBaseUri) { "$ProvidedBaseUri$Uri" } else { "$BaseUri$Uri" }
    
    # If Skip Cert
    if ($SkipCertificateCheck) {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        } else {
            Write-Host "PowerShell version is major version: $($PSVersionTable.PSVersion.Major), skipping certificate check switch."
        }
    }

    
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

    # Attempt to retrieve cached result if caching is enabled and cache key is provided
    if ($UseCache -and -not $SkipCache -and $CacheKey) {
        $cachedResult = Get-RestRequestCache -CacheKey $CacheKey
        if ($null -ne $cachedResult) {
            if ($VerboseMode) { Write-Host "[*] Returning cached result for key: $CacheKey" }
            
            # Return cached result in the requested format
            if ($RawJson) {
                return $cachedResult | ConvertTo-Json -Depth $JsonDepthResponse
            }
            else {
                return $cachedResult
            }
        }
    }

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

            # Store the results in cache if caching is enabled and a cache key is provided
            if ($UseCache -and $CacheKey) {
                Set-RestRequestCache -CacheKey $CacheKey -Value $Results -TtlSeconds $CacheTtlSeconds
                if ($VerboseMode) { Write-Host "[*] Cached result with key: $CacheKey" }
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
#endregion 

#region Initialize Cache
function Initialize-RestRequestCache {
    <#
    .SYNOPSIS
        Initializes the REST request cache for the current PowerShell session.

    .DESCRIPTION
        Creates a global, session-scoped hashtable used to cache REST API responses.
        This cache improves performance by preventing repeated API calls for the same data.

        The cache is stored in a global variable named '__RestRequestCache' and persists
        for the duration of the PowerShell session.

        This function is safe to call multiple times. If the cache already exists,
        the function will not overwrite existing cached entries.
    #>

    if (-not (Get-Variable -Name '__RestRequestCache' -Scope Global -ErrorAction SilentlyContinue)) {
        $global:__RestRequestCache = @{}
        Write-Verbose "REST Request cache initialized."
    }
}
#endregion

#region Get Cache
function Get-RestRequestCache {
    <#
    .SYNOPSIS
        Retrieves a cached REST response from the session cache.

    .DESCRIPTION
        Returns a cached value based on the provided cache key. If the cache entry
        has expired (based on TTL), it will automatically be removed and $null returned.

        Optionally returns metadata such as creation time and expiration time.

    .PARAMETER CacheKey
        The unique identifier used to store and retrieve cached data.

    .PARAMETER IncludeMetadata
        Returns the full cache entry including metadata (CreatedAt, ExpiresAt, Value).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CacheKey,

        [switch]$IncludeMetadata
    )

    if (-not (Get-Variable -Name '__RestRequestCache' -Scope Global -ErrorAction SilentlyContinue)) {
        return $null
    }

    $cacheEntry = $global:__RestRequestCache[$CacheKey]

    if ($null -eq $cacheEntry) {
        return $null
    }

    # Check if TTL has expired
    if ($cacheEntry.ExpiresAt -and (Get-Date) -gt $cacheEntry.ExpiresAt) {
        $global:__RestRequestCache.Remove($CacheKey)
        Write-Verbose "Cache entry '$CacheKey' has expired and was removed."
        return $null
    }

    if ($IncludeMetadata) {
        return $cacheEntry
    }

    return $cacheEntry.Value
}
#endregion

#region Set Cache
function Set-RestRequestCache {
    <#
    .SYNOPSIS
        Stores a REST response in the session cache.

    .DESCRIPTION
        Adds or updates a cached entry using a unique cache key.
        Cached entries can optionally expire using a Time-To-Live (TTL) value.

        If no TTL is specified, the cache entry will persist for the entire session.

    .PARAMETER CacheKey
        The unique identifier used to store the cached value.

    .PARAMETER Value
        The data to cache. Typically the REST API response.

    .PARAMETER TtlSeconds
        Time-to-live in seconds. When expired, the cache entry is automatically removed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CacheKey,

        [Parameter(Mandatory)]
        $Value,

        [int]$TtlSeconds
    )

    Initialize-RestRequestCache

    $cacheEntry = @{
        Value     = $Value
        CreatedAt = Get-Date
        ExpiresAt = if ($TtlSeconds) { (Get-Date).AddSeconds($TtlSeconds) } else { $null }
    }

    if ($global:__RestRequestCache.ContainsKey($CacheKey)) {
        $global:__RestRequestCache[$CacheKey] = $cacheEntry
        Write-Verbose "Cache entry '$CacheKey' updated."
    } else {
        $global:__RestRequestCache.Add($CacheKey, $cacheEntry)
        Write-Verbose "Cache entry '$CacheKey' created."
    }
}
#endregion

#region Remove Cache
function Remove-RestRequestCache {
    <#
    .SYNOPSIS
        Removes cache entries from the REST request cache.

    .DESCRIPTION
        Removes a specific cache entry using a cache key, or clears the entire cache
        when no cache key is specified.

    .PARAMETER CacheKey
        Optional cache key to remove a specific entry.
        If omitted, all cache entries are removed.

    #>
    [CmdletBinding()]
    param(
        [string]$CacheKey
    )

    if (-not (Get-Variable -Name '__RestRequestCache' -Scope Global -ErrorAction SilentlyContinue)) {
        Write-Verbose "No cache to clear."
        return
    }

    if ($CacheKey) {
        $global:__RestRequestCache.Remove($CacheKey)
        Write-Verbose "Cache entry '$CacheKey' removed."
    } else {
        $global:__RestRequestCache.Clear()
        Write-Verbose "All cache entries cleared."
    }
}
#endregion

#region Get Cache Info
function Get-RestRequestCacheInfo {
    <#
    .SYNOPSIS
        Displays information about all cached REST entries.

    .DESCRIPTION
        Returns a list of cached entries including creation time,
        expiration time, and expiration status.

        Useful for debugging cache behavior.

    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Variable -Name '__RestRequestCache' -Scope Global -ErrorAction SilentlyContinue)) {
        Write-Host "Cache is not initialized."
        return
    }

    $global:__RestRequestCache.GetEnumerator() | ForEach-Object {
        [PSCustomObject]@{
            CacheKey  = $_.Key
            CreatedAt = $_.Value.CreatedAt
            ExpiresAt = $_.Value.ExpiresAt
            IsExpired = if ($_.Value.ExpiresAt) { (Get-Date) -gt $_.Value.ExpiresAt } else { $false }
        }
    }
}
#endregion


