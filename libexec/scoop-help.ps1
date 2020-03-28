# Usage: scoop help <命令>
# Summary: 查看某个命令的和帮助
param($cmd)

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\commands.ps1"
. "$psscriptroot\..\lib\help.ps1"

reset_aliases

function print_help($cmd) {
    $file = Get-Content (command_path $cmd) -raw

    $usage = usage $file
    $summary = summary $file
    $help = scoop_help $file

    if($usage) { "$usage`n" }
    if($help) { $help }
}

function print_summaries {
    $commands = @{}

    command_files | ForEach-Object {
        $command = command_name $_
        $summary = summary (Get-Content (command_path $command) -raw)
        if(!($summary)) { $summary = '' }
        $commands.add("$command ", $summary) # add padding
    }

    $commands.getenumerator() | Sort-Object name | Format-Table -hidetablehead -autosize -wrap
}

$commands = commands

if(!($cmd)) {
    "使用方法: scoop <命令> [<参数>]

这里是一些常用命令:"
    print_summaries
    "执行 'scoop help <命令>' 来获取某项命令的帮助."
} elseif($commands -contains $cmd) {
    print_help $cmd
} else {
    "scoop help: 不存在命令 '$cmd'"; exit 1
}

exit 0

