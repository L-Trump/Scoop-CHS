# Usage: scoop prefix <应用名>
# Summary: 返回应用的主目录
param($app)

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"

reset_aliases

if(!$app) { my_usage; exit 1 }

$app_path = versiondir $app 'current' $false
if(!(Test-Path $app_path)) {
    $app_path = versiondir $app 'current' $true
}

if(Test-Path $app_path) {
    Write-Output $app_path
} else {
    abort "未找到 '$app' 的路径."
}

exit 0
