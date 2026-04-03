# Test .Count on $null, empty string, hashtable, and array
$testVars = @{
    Null = $null
    EmptyString = ''
    Array = @(1,2,3)
    EmptyArray = @()
    Hashtable = @{foo='bar'}
}
foreach ($key in $testVars.Keys) {
    $val = $testVars[$key]
    try {
        $count = @($val).Count
          Write-Host ("$key: Value=$($val) | @($val).Count = $count | Type: $($val.GetType().FullName)")
    } catch {
        Write-Host ("$key: ERROR - $($_.Exception.Message) | Type: $($val.GetType().FullName)") -ForegroundColor Red
    }
}