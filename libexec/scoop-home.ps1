# Usage: scoop home <应用名>
# Summary: 打开应用的主页
param($app)

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"

reset_aliases

if($app) {
    $manifest, $bucket = find_manifest $app
    if($manifest) {
        if([string]::isnullorempty($manifest.homepage)) {
            abort "无法在Manifest中找到 '$app' 的主页."
        }
        Start-Process $manifest.homepage
    }
    else {
        abort "无法找到 '$app' 的Manifest."
    }
} else { my_usage }

exit 0
