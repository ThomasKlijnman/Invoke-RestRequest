# 1. Initialize cache, once per session
Initialize-RestRequestCache

# 2. First call => fetch data from API, store in cache (1 hour TTL)
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

# 3. Second call => fetch data from cache via cacheKey
$params = @{
    AccessToken = $token
    Method      = "GET"
    Uri         = "/users"
    UseCache    = $true
    CacheKey    = "all_user"
    VerboseMode = $true
}
$users = Invoke-RestRequest @params

# 4. Force new data => bypass current cache, and refill with cacheKey
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

# 5. Manage cache
Get-RestRequestCacheInfo                  		# See what is in cache
Remove-RestRequestCache -CacheKey "all_user" 	# Remove specific entry
Remove-RestRequestCache                    	# Clear all cache