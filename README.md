## Still Work in Progress (WIP)
![PowerShell](https://img.shields.io/badge/PowerShell-7+-blue) ![Usage](https://img.shields.io/badge/usage_for-REST_API-blue) ![License](https://img.shields.io/github/license/thomasklijnman/Invoke-RestRequest)

## README for Invoke-RestRequest PowerShell Module

### Overview
Invoke-RestRequest is a PowerShell module designed to simplify making requests to REST-based APIs. This module clears the process of providing built-in support for retries, pagination, and error handling, making it somewhat easier to interact with these APIs.

### Features
- **Available Methods**: Compatible with any regular HTTP methods GET, POST, PATCH, PUT, and DELETE.
- **Retry Logic**: Retry failed request logic for backoff.
- **Pagination Handling**: Follow any pagination links for multi-page results.
- **Error Handling**: Def. mapping of HTTP status codes to PowerShell error categories.
- **Cache Management**: To push any responses or long request with static data during the run to a cache, to be retrieved later via a cache key and the possibility to expire the cache key during the run.
  - See [Cache example](CacheUsageExample.md) for example usages.
- **Customizable Requests**:
  - Define request bodies as PowerShell hashtables that automatically convert to JSON.
  - Add custom HTTP headers.
  - Specify query parameters for detailed queries.


### Parameters

| Parameter                  | Type       | Mandatory | Description                                                                                                       |
|----------------------------|------------|-----------|----------------------------------------------------------------------------------------------------------|
| `$AccessToken`             | string     | Yes       | Bearer token for authentication. Advice to not store in plain text during usage.                                  |
| `$Method`                  | string     | Yes       | HTTP method to use (GET, POST, PATCH, PUT, DELETE).                                                               |
| `$Uri`                     | string     | Yes       | Relative URI (e.g. /users).                                                                                       |
| `$Body`                    | hashtable  | No        | Request body as a PowerShell hashtable/object (will be converted to JSON).                                        |
| `$MaxRetries`              | int        | No        | Specifies the maximum number of retry attempts for failed requests (Default: 5).                                  |
| `$ApiVersion`              | string     | No        | Specifies the API version to target.                                                                              |
| `$RawJson`                 | switch     | No        | If specified, returns the response as a raw JSON string instead of a PowerShell object.                           |
| `$Proxy`                   | string     | No        | Use a Proxy (e.g. -Proxy "http://127.0.0.1:8080").                                                                |
| `$SkipCertificateCheck`    | switch     | No        | Parameter to skip any TLS certificate validation; only supported to be used in Powershell 7.                      |
| `$IrmCustomParameters`     | hashtable  | No        | Additional Boolean only parameters to pass to IRM                                                                 |
| `$IrmTimeout`              | int        | No        | Timeout in seconds for IRM (Default: 15 seconds).                                                                 |
| `$IrmUserAgent`            | string     | No        | Custom UserAgent string for IRM to pass.                                                                          |
| `$DisablePagination`       | switch     | No        | Prevents the function from automatically following @odata.nextLink for paginated results.                         |
| `$VerboseMode`             | switch     | No        | Enables verbose logging to provide additional information about request processing.                               |
| `$Suppress404`             | switch     | No        | Suppress 404 messages (e.g., if a queried User object is not found in the tenant).                                |
| `$QueryParameters`         | hashtable  | No        | Query parameters for more complex queries (e.g. @{ '$filter' = "startswith(displayName,'Alex')"}).                |
| `$AdditionalHeaders`       | hashtable  | No        | Add additional HTTP headers (e.g. for ConsistencyLevel).                                                          |
| `$JsonDepthResponse`       | int        | No        | Specifies the depth for JSON conversion (request). Useful for deeply nested objects in combination with -RawJson. |
| `$ProvidedBaseUri`         | string     | No        | Parameter for custom base URI for custom REST API endpoints.                                                      |
| `$UseCache`	             | switch     | No        | Enable caching for this request                                                                                   |
| `$CacheKey`	             | string     | No        | Unique cache identifier                                                                                           |
| `$SkipCache`	             | switch     | No        | Bypass cache for this request (force fresh data)                                                                  |
| `$CacheTtlSeconds`         | int        | No        | TTL in seconds (optional), to be used in combination with $CacheKey                                               |




### Error Handling

| Status Code | Error Category                                  | Description                                      |
|-------------|-------------------------------------------------|--------------------------------------------------|
| `400`       | InvalidArgument                                  | Bad request due to invalid argument.             |
| `401`       | AuthenticationError                             | Authentication failed due to invalid token.      |
| `403`       | PermissionDenied                                 | Access forbidden due to lack of permissions.     |
| `404`       | ObjectNotFound                                   | Resource not found.                              |
| `405`       | InvalidOperation                                  | Method not allowed.                              |
| `406`       | InvalidData                                      | Not acceptable data format.                      |
| `409`       | ResourceExists                                   | Conflict while trying to create a resource.     |
| `410`       | ObjectNotFound                                   | Resource no longer exists.                       |
| `411`       | InvalidArgument                                  | Content-Length required.                         |
| `412`       | InvalidResult                                    | Precondition failed.                             |
| `413`       | ResourceUnavailable                              | Request entity too large.                        |
| `415`       | InvalidType                                      | Unsupported media type.                          |
| `416`       | InvalidArgument                                  | Range not satisfiable.                           |
| `422`       | InvalidData                                      | Unprocessable entity.                            |
| `429`       | LimitsExceeded                                   | Too many requests – throttling.                  |
| `500`       | InvalidResult                                    | Internal server error.                           |
| `501`       | NotImplemented                                   | Not implemented.                                 |
| `502`       | ProtocolError                                   | Bad gateway.                                     |
| `503`       | ResourceUnavailable                              | Service unavailable.                             |
| `504`       | OperationTimeout                                 | Gateway timeout.                                 |
| `507`       | QuotaExceeded                                   | Insufficient storage.                            |
| `509`       | QuotaExceeded                                   | Bandwidth limit exceeded.                        |

