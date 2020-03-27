# Usage: scoop cache show|rm [应用名]
# Summary: 查看或者清除Scoop缓存
# Help: Scoop会缓存已下载的文件，使你在卸载并再次安装
# 相同版本时避免重复下载。
#
# 你可以使用
#     scoop cache show
# 来查看所有缓存，并使用
#     scoop cache rm <应用名>
# 来删除某个应用的缓存（允许使用通配符*）
#
# 删除所有缓存可以使用:
#     scoop cache rm *
param($cmd, $app)

. "$psscriptroot\..\lib\help.ps1"

reset_aliases

function cacheinfo($file) {
    $app, $version, $url = $file.name -split '#'
    $size = filesize $file.length
    return new-object psobject -prop @{ app=$app; version=$version; url=$url; size=$size }
}

function show($app) {
    $files = @(Get-ChildItem "$cachedir" | Where-Object { $_.name -match "^$app" })
    $total_length = ($files | Measure-Object length -sum).sum -as [double]

    $f_app  = @{ expression={"$($_.app) ($($_.version))" }}
    $f_url  = @{ expression={$_.url};alignment='right'}
    $f_size = @{ expression={$_.size}; alignment='right'}


    $files | ForEach-Object { cacheinfo $_ } | Format-Table $f_size, $f_app, $f_url -auto -hide

    "共计: $($files.length) 个文件, $(filesize $total_length)"
}

switch($cmd) {
    'rm' {
        if(!$app) { '未指定应用 <应用名>'; my_usage; exit 1 }
        Remove-Item "$cachedir\$app#*"
        if(test-path("$cachedir\$app.txt")) {
            Remove-Item "$cachedir\$app.txt"
        }
    }
    'show' {
        show $app
    }
    '' {
        show
    }
    default {
        my_usage
    }
}

exit 0
