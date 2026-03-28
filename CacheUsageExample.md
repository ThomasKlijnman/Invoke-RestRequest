# - Initialize cache, once per session
Initialize-RestRequestCache

# - First call => fetch data from API, store in cache (1 hour TTL)
```powershell
$params = @{
    AccessToken      = $token
    Method           = "GET"
    Uri              = "/users"
    UseCache         = $true
    CacheKey         = "all_user"
    CacheTtlSeconds  = 3600
    VerboseMode      = $true
}
$users = Invoke-RestRequest @params
```

# - Second call => fetch data from cache via cacheKey
```powershell
$params = @{
    AccessToken = $token
    Method      = "GET"
    Uri         = "/users"
    UseCache    = $true
    CacheKey    = "all_user"
    VerboseMode = $true
}
$users = Invoke-RestRequest @params
```

# - Force new data => bypass current cache, and refill with cacheKey
```powershell
$params = @{
    AccessToken = $token
    Method      = "GET"
    Uri         = "/users"
    UseCache    = $true
    CacheKey    = "all_user"
    SkipCache   = $true
    VerboseMode = $true
}
$users = Invoke-RestRequest @params
```

# -  Manage cached keys
```powershell
Get-RestRequestCacheInfo                  		# See what is in cache
Remove-RestRequestCache -CacheKey "all_user" 	# Remove specific entry
Remove-RestRequestCache                    	# Clear all cache
```
