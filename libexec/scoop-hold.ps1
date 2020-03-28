# Usage: scoop hold <应用名>
# Summary: 锁定某个应用，避免其更新

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
    $install.hold = $true
    save_install_info $install $dir
    success "$app 成功锁定，解锁前将无法更新."
}

exit $exitcode
