# Usage: scoop unhold <应用名>
# Summary: 解除锁定来允许应用更新

. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\manifest.ps1"

reset_aliases
$apps = $args

if(!$apps) {
    my_usage
    exit 1
}

$apps | ForEach-Object {
    $app = $_
    $global = installed $app $true

    if (!(installed $app)) {
        error "'$app' 未安装."
        return
    }

    $dir = versiondir $app 'current' $global
    $json = install_info $app 'current' $global
    $install = @{}
    $json | Get-Member -MemberType Properties | ForEach-Object { $install.Add($_.Name, $json.($_.Name))}
    $install.hold = $null
    save_install_info $install $dir
    success "$app 现在已解锁，可以进行更新了."
}

exit $exitcode
