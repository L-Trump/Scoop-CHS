# Usage: scoop reset <应用名>
# Summary: 调整应用来解决冲突
# Help: 用以解决一些特殊应用间的冲突，如：
# 如果你同时安装了'python'和'python27', 你可以使用 'scoop reset' 
# 来决定你使用哪一个

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\shortcuts.ps1"

reset_aliases
$opt, $apps, $err = getopt $args
if($err) { "scoop reset: $err"; exit 1 }

if(!$apps) { error '未指定应用'; my_usage; exit 1 }

if($apps -eq '*') {
    $local = installed_apps $false | ForEach-Object { ,@($_, $false) }
    $global = installed_apps $true | ForEach-Object { ,@($_, $true) }
    $apps = @($local) + @($global)
}

$apps | ForEach-Object {
    ($app, $global) = $_

    $app, $bucket, $version = parse_app $app

    if(($global -eq $null) -and (installed $app $true)) {
        # set global flag when running reset command on specific app
        $global = $true
    }

    if($app -eq 'scoop') {
        # skip scoop
        return
    }

    if(!(installed $app)) {
        error "'$app' 未安装"
        return
    }

    if ($null -eq $version) {
        $version = current_version $app $global
    }

    $manifest = installed_manifest $app $version $global
    # if this is null we know the version they're resetting to
    # is not installed
    if ($manifest -eq $null) {
        error "'$app ($version)' 未安装"
        return
    }

    if($global -and !(is_admin)) {
        warn "'$app' ($version) 是一个全局应用，需要管理员权限来执行reset操作，已跳过."
        return
    }

    write-host "重置到 $app ($version)."

    $dir = resolve-path (versiondir $app $version $global)
    $original_dir = $dir
    $persist_dir = persistdir $app $global

    $install = install_info $app $version $global
    $architecture = $install.architecture

    $dir = link_current $dir
    create_shims $manifest $dir $global $architecture
    create_startmenu_shortcuts $manifest $dir $global $architecture
    env_add_path $manifest $dir
    env_set $manifest $dir $global
    # unlink all potential old link before re-persisting
    unlink_persist_data $original_dir
    persist_data $manifest $original_dir $persist_dir
    persist_permission $manifest $global
}

exit 0
