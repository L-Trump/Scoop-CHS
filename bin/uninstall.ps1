<#
.SYNOPSIS
    Uninstall ALL scoop applications and scoop itself.
.PARAMETER global
    Global applications will be uninstalled.
.PARAMETER purge
    Persisted data will be deleted.
#>
param(
    [bool] $global,
    [bool] $purge
)

. "$PSScriptRoot\..\lib\core.ps1"
. "$PSScriptRoot\..\lib\install.ps1"
. "$PSScriptRoot\..\lib\shortcuts.ps1"
. "$PSScriptRoot\..\lib\versions.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1"

if ($global -and !(is_admin)) {
    error 'You need admin rights to uninstall globally.'
    exit 1
}

if ($purge) {
    warn '这将会删除Scoop,和所有通过Scoop安装的应用以及Persist数据!'
} else {
    warn '这将会Scoop和通过Scoop安装的应用!'
}
$yn = Read-Host '你确定要继续吗? (yN)'
if ($yn -notlike 'y*') { exit }

$errors = $false

# Uninstall given app
function do_uninstall($app, $global) {
    $version = current_version $app $global
    $dir = versiondir $app $version $global
    $manifest = installed_manifest $app $version $global
    $install = install_info $app $version $global
    $architecture = $install.architecture

    Write-Output "卸载 '$app'"
    run_uninstaller $manifest $architecture $dir
    rm_shims $manifest $global $architecture

    # If a junction was used during install, that will have been used
    # as the reference directory. Othewise it will just be the version
    # directory.
    $refdir = unlink_current (appdir $app $global)

    env_rm_path $manifest $refdir $global
    env_rm $manifest $global

    $appdir = appdir $app $global
    try {
        Remove-Item $appdir -Recurse -Force -ErrorAction Stop
    } catch {
        $errors = $true
        warn "无法移除 $(friendly_path $appdir): $_.Exception"
    }
}

function rm_dir($dir) {
    try {
        Remove-Item $dir -Recurse -Force -ErrorAction Stop
    } catch {
        abort "无法移除 $(friendly_path $dir): $_"
    }
}

# Remove all folders (except persist) inside given scoop directory.
function keep_onlypersist($directory) {
    Get-ChildItem $directory -Exclude 'persist' | ForEach-Object { rm_dir $_ }
}

# Run uninstallation for each app if necessary, continuing if there's
# a problem deleting a directory (which is quite likely)
if ($global) {
    installed_apps $true | ForEach-Object { # global apps
        do_uninstall $_ $true
    }
}

installed_apps $false | ForEach-Object { # local apps
    do_uninstall $_ $false
}

if ($errors) {
    abort '部分应用未成功删除，请再试一次或者重启后再试'
}

if ($purge) {
    rm_dir $scoopdir
    if ($global) { rm_dir $globaldir }
} else {
    keep_onlypersist $scoopdir
    if ($global) { keep_onlypersist $globaldir }
}

remove_from_path (shimdir $false)
if ($global) { remove_from_path (shimdir $true) }

success 'Scoop 成功卸载.'
