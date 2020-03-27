# Usage: scoop config [rm] 配置项 [配置值]
# Summary: 获取或者设置Scoop配置
# Help: Scoop配置文件保存在 ~/.config/scoop/config.json.
#
# 获取一项设置:
#
#     scoop config <配置项>
#
# 添加/修改一项设置:
#
#     scoop config <配置项> <配置值>
#
# 移除一项设置：
#
#     scoop config rm <配置项>
#
# 代理设置
# --------
#
# proxy: [用户名:密码@]地址:端口
# 
# e.g.
#   scoop config proxy 127.0.0.1:1080
#   scoop config proxy username:password@127.0.0.1:1080
#
# 默认情况下，Scoop会使用系统代理，然而这并不能指定用户名密码
#
# * 如果要以当前登录的用户进行身份验证,  用 'currentuser' 代替 username:password
# * 如果要使用系统代理的地址，用 'default' 代替 '地址:端口'
# * 不配置proxy项相当于将proxy设为 'default'
# * 如果要跳过代理（无视系统代理），使用 'none' 来配置proxy项

param($name, $value)

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\help.ps1"

reset_aliases

if(!$name) { my_usage; exit 1 }

if($name -like 'rm') {
    set_config $value $null | Out-Null
    Write-Output "'$value' 已移除"
} elseif($null -ne $value) {
    set_config $name $value | Out-Null
    Write-Output "'$name' 被设置为 '$value'"
} else {
    $value = get_config $name
    if($null -eq $value) {
        Write-Output "'$name' 未设置"
    } else {
        Write-Output $value
    }
}

exit 0
