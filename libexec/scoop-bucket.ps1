# Usage: scoop bucket add|list|known|rm [<参数>]
# Summary: 管理Scoop仓库
# Help: 添加, 列举或者删除仓库.
#
# Buckets是Scoop的应用仓库，决定了你可以安装哪些应用，
# Scoop自带了一些默认仓库。当然你也可以添加第三方仓库
#
# 添加Buckets:
#     scoop bucket add <仓库名> [<仓库地址>]
#
# e.g.:
#     scoop bucket add extras https://github.com/lukesampson/scoop-extras.git
#
# 由于 'extras' 仓库是已知的Scoop仓库, 所以可以简单地写成这样:
#     scoop bucket add extras
#
# 查看所有已知仓库，执行:
#     scoop bucket known
param($cmd, $name, $repo)

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\git.ps1"

reset_aliases

$usage_add = "使用方法: scoop bucket add <仓库名> [<仓库地址>]"
$usage_rm = "使用方法: scoop bucket rm <仓库名>"

switch($cmd) {
    'add' { add_bucket $name $repo }
    'rm' { rm_bucket $name }
    'list' { Get-LocalBucket }
    'known' { known_buckets }
    default { "scoop bucket: 不支持命令 '$cmd' "; my_usage; exit 1 }
}

exit 0
