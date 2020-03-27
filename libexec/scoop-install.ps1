# Usage: scoop install <[仓库]/应用名> [选项]
# Summary: 安装应用
# Help: e.g. 常规安装 (使用已添加的仓库):
#      scoop install git
# 
# 指定仓库安装（避免多个仓库拥有同一软件）:
#      scoop install main/git
#
# 通过网络Manifest安装应用:
#      scoop install https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/runat.json
#
# 通过本地Manifest安装应用：
#      scoop install \path\to\app.json
#
# Options:
#   -g, --global              将应用作为全局应用安装
#   -i, --independent         不自动安装依赖
#   -k, --no-cache            不使用下载缓存
#   -s, --skip                跳过Hash数据校验（谨慎使用）
#   -a, --arch <32bit|64bit>  安装特定架构的应用（如果应用支持）

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\decompress.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\shortcuts.ps1"
. "$psscriptroot\..\lib\psmodules.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\depends.ps1"

reset_aliases

function is_installed($app, $global) {
    if ($app.EndsWith('.json')) {
        $app = [System.IO.Path]::GetFileNameWithoutExtension($app)
    }
    if (installed $app $global) {
        function gf($g) { if ($g) { ' --global' } }

        $version = @(versions $app $global)[-1]
        if (!(install_info $app $version $global)) {
            error "看起来 $app 的前一次安装并未成功.`n执行 'scoop uninstall $app$(gf $global)' 后再试."
        }
        warn "'$app' ($version) 已安装.`n使用 'scoop update $app$(gf $global)' 来更新应用到新版本."
        return $true
    }
    return $false
}

$opt, $apps, $err = getopt $args 'gfiksa:' 'global', 'force', 'independent', 'no-cache', 'skip', 'arch='
if ($err) { "scoop install: $err"; exit 1 }

$global = $opt.g -or $opt.global
$check_hash = !($opt.s -or $opt.skip)
$independent = $opt.i -or $opt.independent
$use_cache = !($opt.k -or $opt.'no-cache')
$architecture = default_architecture
try {
    $architecture = ensure_architecture ($opt.a + $opt.arch)
} catch {
    abort "错误: $_"
}

if (!$apps) { error '未指定应用'; my_usage; exit 1 }

if ($global -and !(is_admin)) {
    abort '错误: 需要管理员权限来安装全局应用'
}

if (is_scoop_outdated) {
    scoop update
}

if ($apps.length -eq 1) {
    $app, $null, $version = parse_app $apps
    if ($null -eq $version -and (is_installed $app $global)) {
        return
    }
}

# get any specific versions that we need to handle first
$specific_versions = $apps | Where-Object {
    $null, $null, $version = parse_app $_
    return $null -ne $version
}

# compare object does not like nulls
if ($specific_versions.length -gt 0) {
    $difference = Compare-Object -ReferenceObject $apps -DifferenceObject $specific_versions -PassThru
} else {
    $difference = $apps
}

$specific_versions_paths = $specific_versions | ForEach-Object {
    $app, $bucket, $version = parse_app $_
    if (installed_manifest $app $version) {
        abort "'$app' ($version) 已安装.`n使用 'scoop update $app$global_flag' 来更新到新版本."
    }

    generate_user_manifest $app $bucket $version
}
$apps = @(($specific_versions_paths + $difference) | Where-Object { $_ } | Sort-Object -Unique)

# remember which were explictly requested so that we can
# differentiate after dependencies are added
$explicit_apps = $apps

if (!$independent) {
    $apps = install_order $apps $architecture # adds dependencies
}
ensure_none_failed $apps $global

$apps, $skip = prune_installed $apps $global

$skip | Where-Object { $explicit_apps -contains $_ } | ForEach-Object {
    $app, $null, $null = parse_app $_
    $version = @(versions $app $global)[-1]
    warn "'$app' ($version) 已存在，跳过."
}

$suggested = @{ };
if (Test-Aria2Enabled) {
    warn "Scoop正在使用 'aria2c' 进行多线程下载."
    warn "如果这导致了一些问题，可以使用 'scoop config aria2-enabled false' 来禁用它."
}
$apps | ForEach-Object { install_app $_ $architecture $global $suggested $use_cache $check_hash }

show_suggestions $suggested

exit 0
