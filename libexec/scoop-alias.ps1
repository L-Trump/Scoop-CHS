# Usage: scoop alias add|list|rm [<参数>]
# Summary: 管理Scoop别名
# Help: 添加, 移除 或者列举 Scoop 别名
#
# 别名是自定义的Scoop子命令，可以创建这些子命令来执行常见任务
#
# 添加别名:
#     scoop alias add <别名> <命令> <描述>
#
# e.g.:
#     scoop alias add rm 'scoop uninstall $args[0]' '卸载应用'
#     scoop alias add upgrade 'scoop update *' '更新全部应用'
#
# Options:
#   -v, --verbose   列出别名的描述以及表头 (只对 'list' 生效)

param(
  [String]$opt,
  [String]$name,
  [String]$command,
  [String]$description,
  [Switch]$verbose = $false
)

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\install.ps1"

$script:config_alias = "alias"

function init_alias_config {
    $aliases = get_config $script:config_alias
    if(!$aliases) {
        $aliases = @{}
    }

    return $aliases
}

function add_alias($name, $command) {
    if(!$command) {
        abort "无法创造空的 alias."
    }

    # get current aliases from config
    $aliases = init_alias_config
    if($aliases.$name) {
        abort "Alias $name 已存在."
    }

    $alias_file = "scoop-$name"

    # generate script
    $shimdir = shimdir $false
    $script =
@"
# Summary: $description
$command
"@
    $script | out-file "$shimdir\$alias_file.ps1" -encoding utf8

    # add alias to config
    $aliases | Add-Member -MemberType NoteProperty -Name $name -Value $alias_file

    set_config $script:config_alias $aliases | Out-Null
}

function rm_alias($name) {
    $aliases = init_alias_config
    if(!$name) {
        abort "你到底想要移除哪个Alias?"
    }

    if($aliases.$name) {
        "移除 alias $name..."

        rm_shim $aliases.$name (shimdir $false)

        $aliases.PSObject.Properties.Remove($name)
        set_config $script:config_alias $aliases | Out-Null
    } else {
        abort "Alias $name 不存在."
    }
}

function list_aliases {
    $aliases = @()

    (init_alias_config).PSObject.Properties.GetEnumerator() | ForEach-Object {
        $content = Get-Content (command_path $_.Name)
        $command = ($content | Select-Object -Skip 1).Trim()
        $summary = (summary $content).Trim()

        $aliases += New-Object psobject -Property @{Name=$_.name; Summary=$summary; Command=$command}
    }

    if(!$aliases.count) {
        warn "未找到Alias."
    }
    $aliases = $aliases.GetEnumerator() | Sort-Object Name
    if($verbose) {
        return $aliases | Select-Object Name, Command, Summary | Format-Table -autosize -wrap
    } else {
        return $aliases | Select-Object Name, Command | Format-Table -autosize -hidetablehead -wrap
    }
}

switch($opt) {
    "add" { add_alias $name $command }
    "rm" { rm_alias $name }
    "list" { list_aliases }
    default { my_usage; exit 1 }
}

exit 0
