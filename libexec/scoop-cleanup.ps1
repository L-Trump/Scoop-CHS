# Usage: scoop cleanup <应用名> [选项]
# Summary: 清除应用的旧版本残留
# Help: 'scoop cleanup' 可以用来清除应用的旧版本残留.
# 'scoop cleanup <应用名>' 会删除指定应用的所有旧版本文件
#
# 你可以使用通配符 '*' 来清除清理所有应用
#
# Options:
#   -g, --global       清理一个全局安装的应用
#   -k, --cache        清理已经过时的缓存

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\install.ps1"

reset_aliases

$opt, $apps, $err = getopt $args 'gk' 'global', 'cache'
if ($err) { "scoop cleanup: $err"; exit 1 }
$global = $opt.g -or $opt.global
$cache = $opt.k -or $opt.cache

if (!$apps) { '错误: 未指定应用'; my_usage; exit 1 }

if ($global -and !(is_admin)) {
    '错误: 需要管理员权限来清理全局应用'; exit 1
}

function cleanup($app, $global, $verbose, $cache) {
    $current_version = current_version $app $global
    if ($cache) {
        Remove-Item "$cachedir\$app#*" -Exclude "$app#$current_version#*"
    }
    $versions = versions $app $global | Where-Object { $_ -ne $current_version -and $_ -ne 'current' }
    if (!$versions) {
        if ($verbose) { success "无需清理 $app" }
        return
    }

    write-host -f yellow "移除 $app`:" -nonewline
    $versions | ForEach-Object {
        $version = $_
        write-host " $version" -nonewline
        $dir = versiondir $app $version $global
        # unlink all potential old link before doing recursive Remove-Item
        unlink_persist_data $dir
        Remove-Item $dir -ErrorAction Stop -Recurse -Force
    }
    write-host ''
}

if ($apps) {
    $verbose = $true
    if ($apps -eq '*') {
        $verbose = $false
        $apps = applist (installed_apps $false) $false
        if ($global) {
            $apps += applist (installed_apps $true) $true
        }
    } else {
        $apps = Confirm-InstallationStatus $apps -Global:$global
    }

    # $apps is now a list of ($app, $global) tuples
    $apps | ForEach-Object { cleanup @_ $verbose $cache}

    if ($cache) {
        Remove-Item "$cachedir\*.download" -ErrorAction Ignore
    }

    if (!$verbose) {
        success '已清理完毕!'
    }
}

exit 0
