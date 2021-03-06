﻿# Usage: scoop info <应用名>
# Summary: 展示一个应用的信息
param($app)

. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\depends.ps1"
. "$psscriptroot\..\lib\help.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\versions.ps1"

reset_aliases

if(!$app) { my_usage; exit 1 }

if ($app -match '^(ht|f)tps?://|\\\\') {
    # check if $app is a URL or UNC path
    $url = $app
    $app = appname_from_url $url
    $global = installed $app $true
    $status = app_status $app $global
    $manifest = url_manifest $url
    $manifest_file = $url
} else {
    # else $app is a normal app name
    $global = installed $app $true
    $app, $bucket, $null = parse_app $app
    $status = app_status $app $global
    $manifest, $bucket = find_manifest $app $bucket
}

if (!$manifest) {
    abort "无法找到 '$(show_app $app $bucket)' 的Manifest."
}

$install = install_info $app $status.version $global
$status.installed = $install.bucket -eq $bucket
$version_output = $manifest.version
if (!$manifest_file) {
    $manifest_file = manifest_path $app $bucket
}

$dir = versiondir $app 'current' $global
$original_dir = versiondir $app $manifest.version $global
$persist_dir = persistdir $app $global

if($status.installed) {
    $manifest_file = manifest_path $app $install.bucket
    if ($install.url) {
        $manifest_file = $install.url
    }
    if($status.version -eq $manifest.version) {
        $version_output = $status.version
    } else {
        $version_output = "$($status.version) (新版本 $($manifest.version) 可用)"
    }
}

Write-Output "Name: $app"
if ($manifest.description) {
    Write-Output "描述: $($manifest.description)"
}
Write-Output "版本: $version_output"
Write-Output "主页: $($manifest.homepage)"
# Show license
if ($manifest.license) {
    $license = $manifest.license
    if ($manifest.license.identifier -and $manifest.license.url) {
        $license = "$($manifest.license.identifier) ($($manifest.license.url))"
    } elseif ($manifest.license -match '^((ht)|f)tps?://') {
        $license = "$($manifest.license)"
    } elseif ($manifest.license -match '[|,]') {
        $licurl = $manifest.license.Split("|,") | ForEach-Object {"https://spdx.org/licenses/$_.html"}
        $license = "$($manifest.license) ($($licurl -join ', '))"
    } else {
        $license = "$($manifest.license) (https://spdx.org/licenses/$($manifest.license).html)"
    }
    Write-Output "License: $license"
}

# Manifest file
Write-Output "Manifest:`n  $manifest_file"

if($status.installed) {
    # Show installed versions
    Write-Output "安装状态:"
    $versions = versions $app $global
    $versions | ForEach-Object {
        $dir = versiondir $app $_ $global
        if($global) { $dir += " *global*" }
        Write-Output "  $dir"
    }
} else {
    Write-Output "安装状态: 未安装"
}

$binaries = @(arch_specific 'bin' $manifest $install.architecture)
if($binaries) {
    $binary_output = "可执行文件:`n "
    $binaries | ForEach-Object {
        if($_ -is [System.Array]) {
            $binary_output += " $($_[1]).exe"
        } else {
            $binary_output += " $_"
        }
    }
    Write-Output $binary_output
}

if($manifest.env_set -or $manifest.env_add_path) {
    if($status.installed) {
        Write-Output "环境变量:"
    } else {
        Write-Output "环境变量: (模拟)"
    }
}
if($manifest.env_set) {
    $manifest.env_set | Get-Member -member noteproperty | ForEach-Object {
        $value = env $_.name $global
        if(!$value) {
            $value = format $manifest.env_set.$($_.name) @{ "dir" = $dir }
        }
        Write-Output "  $($_.name)=$value"
    }
}
if($manifest.env_add_path) {
    $manifest.env_add_path | Where-Object { $_ } | ForEach-Object {
        if($_ -eq '.') {
            Write-Output "  PATH=%PATH%;$dir"
        } else {
            Write-Output "  PATH=%PATH%;$dir\$_"
        }
    }
}

# Show notes
show_notes $manifest $dir $original_dir $persist_dir

exit 0
