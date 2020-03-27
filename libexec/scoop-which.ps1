# Usage: scoop which <命令>
# Summary: 定位一个 shim 或可执行文件 (类似于Linux中的'which')
# Help: 定位一个由Scoop安装的 shim 或可执行文件的路径 (类似于Linux中的'which')
param($command)
. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\help.ps1"

reset_aliases

if(!$command) { '错误: 未指定命令'; my_usage; exit 1 }

try {
    $gcm = Get-Command "$command" -ea stop
} catch {
    abort "'$command' 不存在" 3
}

$path = "$($gcm.path)"
$usershims = "$(resolve-path $(shimdir $false))"
$globalshims = fullpath (shimdir $true) # don't resolve: may not exist

if($path.endswith(".ps1") -and ($path -like "$usershims*" -or $path -like "$globalshims*")) {
    $shimtext = Get-Content $path

    $exepath = ($shimtext | Where-Object { $_.startswith('$path') }).split(' ') | Select-Object -Last 1 | Invoke-Expression

    if(![system.io.path]::ispathrooted($exepath)) {
        # Expand relative path
        $exepath = resolve-path (join-path (split-path $path) $exepath)
    }

    friendly_path $exepath
} elseif($gcm.commandtype -eq 'Application') {
    $gcm.Source
} elseif($gcm.commandtype -eq 'Alias') {
    scoop which $gcm.resolvedcommandname
} else {
    [console]::error.writeline("不是Scoop的Shim.")
    $path
    exit 2
}

exit 0
