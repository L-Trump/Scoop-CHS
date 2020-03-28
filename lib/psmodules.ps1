$modulesdir = "$scoopdir\modules"

function install_psmodule($manifest, $dir, $global) {
    $psmodule = $manifest.psmodule
    if(!$psmodule) { return }

    if($global) {
        abort "未实现全局安装PowerShell模块!"
    }

    $modulesdir = ensure $modulesdir
    ensure_in_psmodulepath $modulesdir $global

    $module_name = $psmodule.name
    if(!$module_name) {
        abort "无效的Manifest: 在 'psmodule' 中无 'name' 参数项."
    }

    $linkfrom = "$modulesdir\$module_name"
    write-host "安装 PowerShell 模块 '$module_name'"

    write-host "链接 $(friendly_path $linkfrom) => $(friendly_path $dir)"

    if(test-path $linkfrom) {
        warn "$(friendly_path $linkfrom) 已存在, 它将会被替代."
        & "$env:COMSPEC" /c "rmdir `"$linkfrom`""
    }

    & "$env:COMSPEC" /c "mklink /j `"$linkfrom`" `"$dir`"" | out-null
}

function uninstall_psmodule($manifest, $dir, $global) {
    $psmodule = $manifest.psmodule
    if(!$psmodule) { return }

    $module_name = $psmodule.name
    write-host "卸载 PowerShell 模块 '$module_name'."

    $linkfrom = "$modulesdir\$module_name"
    if(test-path $linkfrom) {
        write-host "移除 $(friendly_path $linkfrom)"
        $linkfrom = resolve-path $linkfrom
        & "$env:COMSPEC" /c "rmdir `"$linkfrom`""
    }
}

function ensure_in_psmodulepath($dir, $global) {
    $path = env 'psmodulepath' $global
    if(!$global -and $null -eq $path) {
        $path = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
    }
    $dir = fullpath $dir
    if($path -notmatch [regex]::escape($dir)) {
        write-output "添加 $(friendly_path $dir) 到 $(if($global){'全局'}else{'用户'}) PowerShell 模块路径."

        env 'psmodulepath' $global "$dir;$path" # for future sessions...
        $env:psmodulepath = "$dir;$env:psmodulepath" # for this session
    }
}
