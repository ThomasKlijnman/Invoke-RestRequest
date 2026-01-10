# Module and usage examples

## Example 1: Get only one result by disabling pagination

```powershell
$AccessToken = "YOUR\_ACCESS\_TOKEN"
$QueryParameters = @{
    '$select' = "id,SignInActivity"
    '$top' = "1"
}
Invoke-RestRequest -AccessToken $AccessToken -Method GET -Uri "/users" -QueryParameters $QueryParameters -DisablePagination
```

## Example 2: Example 2: Catch errors to console
```powershell
$AccessToken = "YOUR\_ACCESS\_TOKEN"
try {
    Invoke-RestRequest -AccessToken $AccessToken -Method GET -Uri '/doesnotexist' -BetaAPI -ErrorAction Stop
} catch {
    $err = $_
    Write-Host "[!] Auth error occurred:"
    Write-Host "  Message     : $($err.Exception.Message)"
    Write-Host "  FullyQualifiedErrorId : $($err.FullyQualifiedErrorId)"
    Write-Host "  TargetURL: $($err.TargetObject)"
    Write-Host "  Category    : $($err.CategoryInfo.Category)"
    Write-Host "  Script Line : $($err.InvocationInfo.Line)"
}
```

## Examples REST API based vendors
- https://api.platform.softwareone.com/public/v1/accounts/buyers
- https://management.azure.com/subscriptions?api-version=2020-01-01
- https://api.github.com/repos/owner/repo/issues
- https://{CommvaulServerURL}/AlertsAndEvents/api/alerts
