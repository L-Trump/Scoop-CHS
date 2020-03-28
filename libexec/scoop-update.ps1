# Usage: scoop update <应用名> [选项]
# Summary: 更新应用或者Scoop
# Help: 'scoop update' 用来更新Scoop和仓库到最新版本.
# 'scoop update <app>' 用来更新应用到最新版本.
#
# 你可以使用'scoop update *'来更新全部应用
#
# Options:
#   -f, --force               强制更新，即便不存在更新的版本
#   -g, --global              更新一个全局应用
#   -i, --independent         不自动安装依赖
#   -k, --no-cache            不使用下载缓存
#   -s, --skip                跳过Hash数据校验（谨慎使用）
#   -q, --quiet               隐藏无关信息

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\shortcuts.ps1"
. "$psscriptroot\..\lib\psmodules.ps1"
. "$psscriptroot\..\lib\decompress.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\getopt.ps1"
. "$psscriptroot\..\lib\depends.ps1"
. "$psscriptroot\..\lib\git.ps1"
. "$psscriptroot\..\lib\install.ps1"

reset_aliases

$opt, $apps, $err = getopt $args 'gfiksq:' 'global', 'force', 'independent', 'no-cache', 'skip', 'quiet'
if ($err) { "scoop update: $err"; exit 1 }
$global = $opt.g -or $opt.global
$force = $opt.f -or $opt.force
$check_hash = !($opt.s -or $opt.skip)
$use_cache = !($opt.k -or $opt.'no-cache')
$quiet = $opt.q -or $opt.quiet
$independent = $opt.i -or $opt.independent

# load config
$configRepo = get_config SCOOP_REPO
if (!$configRepo) {
    $configRepo = "https://github.com/L-Trump/Scoop-CHS"
    set_config SCOOP_REPO $configRepo | Out-Null
}

# Find current update channel from config
$configBranch = get_config SCOOP_BRANCH
if (!$configBranch) {
    $configBranch = "utf8"
    set_config SCOOP_BRANCH $configBranch | Out-Null
}

if(($PSVersionTable.PSVersion.Major) -lt 5) {
    # check powershell version
    # should be deleted after Oct 1, 2019
    If ((Get-Date).ToUniversalTime() -ge "2019-10-01") {
        Write-Output "需要 Powershell 5 以及上来运行Scoop."
        Write-Output "更新 PowerShell: https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-windows-powershell"
        break
    } else {
        Write-Output "Scoop将停止对Powershell 3的支持."
        Write-Output "请更新到Powershell 5或者更新版本."
        Write-Output "更新帮助: https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-windows-powershell"
    }
}

function update_scoop() {
    # check for git
    if(!(Test-CommandAvailable git)) { abort "Scoop需要使用Git来更新. 请执行 'scoop install git' 并再次尝试." }

    write-host "正在更新 Scoop..."
    $last_update = $(last_scoop_update)
    if ($null -eq $last_update) {$last_update = [System.DateTime]::Now}
    $last_update = $last_update.ToString('s')
    $show_update_log = get_config 'show_update_log' $true
    $currentdir = fullpath $(versiondir 'scoop' 'current')
    if (!(test-path "$currentdir\.git")) {
        $newdir = fullpath $(versiondir 'scoop' 'new')

        # get git scoop
        git_clone -q $configRepo --branch $configBranch --single-branch "`"$newdir`""

        # check if scoop was successful downloaded
        if (!(test-path "$newdir")) {
            abort 'Scoop 更新失败.'
        }

        # replace non-git scoop with the git version
        Remove-Item -r -force $currentdir -ea stop
        Move-Item $newdir $currentdir
    } else {
        Push-Location $currentdir

        $previousCommit = Invoke-Expression 'git rev-parse HEAD'
        $currentRepo = Invoke-Expression "git config remote.origin.url"
        $currentBranch = Invoke-Expression "git branch"

        $isRepoChanged = !($currentRepo -match $configRepo)
        $isBranchChanged = !($currentBranch -match "\*\s+$configBranch")

        # Change remote url if the repo is changed
        if ($isRepoChanged) {
            Invoke-Expression "git config remote.origin.url '$configRepo'"
        }

        # Fetch and reset local repo if the repo or the branch is changed
        if ($isRepoChanged -or $isBranchChanged) {
            # Reset git fetch refs, so that it can fetch all branches (GH-3368)
            Invoke-Expression "git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'"
            # fetch remote branch
            git_fetch --force origin "refs/heads/`"$configBranch`":refs/remotes/origin/$configBranch" -q
            # checkout and track the branch
            git_checkout -B $configBranch -t origin/$configBranch -q
            # reset branch HEAD
            Invoke-Expression "git reset --hard origin/$configBranch -q"
        } else {
            git_pull -q
        }

        $res = $lastexitcode
        if ($show_update_log) {
            Invoke-Expression "git --no-pager log --no-decorate --format='tformat: * %C(yellow)%h%Creset %<|(72,trunc)%s %C(cyan)%cr%Creset' '$previousCommit..HEAD'"
        }

        Pop-Location
        if ($res -ne 0) {
            abort '更新失败.'
        }
    }

    if ((Get-LocalBucket) -notcontains 'main') {
        info "新版本Scoop的Main仓库已移至 'https://github.com/ScoopInstaller/Main'"
        info "添加主仓库..."
        add_bucket 'main'
    }

    ensure_scoop_in_path
    shim "$currentdir\bin\scoop.ps1" $false

    Get-LocalBucket | ForEach-Object {
        write-host "更新 '$_' bucket..."

        $loc = Find-BucketDirectory $_ -Root
        # Make sure main bucket, which was downloaded as zip, will be properly "converted" into git
        if (($_ -eq 'main') -and !(Test-Path "$loc\.git")) {
            rm_bucket 'main'
            add_bucket 'main'
        }

        Push-Location $loc
        $previousCommit = (Invoke-Expression 'git rev-parse HEAD')
        git_pull -q
        if ($show_update_log) {
            Invoke-Expression "git --no-pager log --no-decorate --format='tformat: * %C(yellow)%h%Creset %<|(72,trunc)%s %C(cyan)%cr%Creset' '$previousCommit..HEAD'"
        }
        Pop-Location
    }

    set_config lastupdate ([System.DateTime]::Now.ToString('o')) | Out-Null
    success 'Scoop 更新成功!'
}

function update($app, $global, $quiet = $false, $independent, $suggested, $use_cache = $true, $check_hash = $true) {
    $old_version = current_version $app $global
    $old_manifest = installed_manifest $app $old_version $global
    $install = install_info $app $old_version $global

    # re-use architecture, bucket and url from first install
    $architecture = ensure_architecture $install.architecture
    $bucket = $install.bucket
    if ($null -eq $bucket) {
        $bucket = 'main'
    }
    $url = $install.url

    if (!$independent) {
        # check dependencies
        $man = if ($url) { $url } else { $app }
        $deps = @(deps $man $architecture) | Where-Object { !(installed $_) }
        $deps | ForEach-Object { install_app $_ $architecture $global $suggested $use_cache $check_hash }
    }

    $version = latest_version $app $bucket $url
    $is_nightly = $version -eq 'nightly'
    if ($is_nightly) {
        $version = nightly_version $(get-date) $quiet
        $check_hash = $false
    }

    if (!$force -and ($old_version -eq $version)) {
        if (!$quiet) {
            warn "最新版本的 '$app' ($version) 已安装."
        }
        return
    }
    if (!$version) {
        # installed from a custom bucket/no longer supported
        error "未找到 '$app' 的Manifest."
        return
    }

    $manifest = manifest $app $bucket $url

    write-host "更新 '$app' ($old_version -> $version)"

    # region Workaround
    # Workaround for https://github.com/lukesampson/scoop/issues/2220 until install is refactored
    # Remove and replace whole region after proper fix
    Write-Host "正在下载新版本"
    if (Test-Aria2Enabled) {
        dl_with_cache_aria2 $app $version $manifest $architecture $cachedir $manifest.cookie $true $check_hash
    } else {
        $urls = url $manifest $architecture

        foreach ($url in $urls) {
            dl_with_cache $app $version $url $null $manifest.cookie $true

            if ($check_hash) {
                $manifest_hash = hash_for_url $manifest $url $architecture
                $source = fullpath (cache_path $app $version $url)
                $ok, $err = check_hash $source $manifest_hash $(show_app $app $bucket)

                if (!$ok) {
                    error $err
                    if (test-path $source) {
                        # rm cached file
                        Remove-Item -force $source
                    }
                    if ($url.Contains('sourceforge.net')) {
                        Write-Host -f yellow '已知SourceForge.net会导致哈希校验失败. 请再次尝试.'
                    }
                    abort $(new_issue_msg $app $bucket "Hash校验失败")
                }
            }
        }
    }
    # There is no need to check hash again while installing
    $check_hash = $false
    # endregion Workaround

    $dir = versiondir $app $old_version $global
    $persist_dir = persistdir $app $global

    #region Workaround for #2952
    $processdir = appdir $app $global | Resolve-Path | Select-Object -ExpandProperty Path
    if (Get-Process | Where-Object { $_.Path -like "$processdir\*" }) {
        error "应用正在运行，请关闭所有相关进程后再试."
        return
    }
    #endregion Workaround for #2952

    write-host "正在卸载 '$app' ($old_version)"
    run_uninstaller $old_manifest $architecture $dir
    rm_shims $old_manifest $global $architecture
    env_rm_path $old_manifest $dir $global
    env_rm $old_manifest $global

    # If a junction was used during install, that will have been used
    # as the reference directory. Otherwise it will just be the version
    # directory.
    $refdir = unlink_current $dir

    if ($force -and ($old_version -eq $version)) {
        if (!(Test-Path "$dir/../_$version.old")) {
            Move-Item "$dir" "$dir/../_$version.old"
        } else {
            $i = 1
            While (Test-Path "$dir/../_$version.old($i)") {
                $i++
            }
            Move-Item "$dir" "$dir/../_$version.old($i)"
        }
    }

    if ($bucket) {
        # add bucket name it was installed from
        $app = "$bucket/$app"
    }
    if ($install.url) {
        # use the url of the install json if the application was installed through url
        $app = $install.url
    }
    install_app $app $architecture $global $suggested $use_cache $check_hash
}

if (!$apps) {
    if ($global) {
        "scoop update: --global 选项在未指定应用时不可用."; exit 1
    }
    if (!$use_cache) {
        "scoop update: --no-cache 选项在未指定应用时不可用."; exit 1
    }
    update_scoop
} else {
    if ($global -and !(is_admin)) {
        '错误: 需要管理员权限来更新全局应用.'; exit 1
    }

    if (is_scoop_outdated) {
        update_scoop
    }
    $outdated = @()
    $apps_param = $apps

    if ($apps_param -eq '*') {
        $apps = applist (installed_apps $false) $false
        if ($global) {
            $apps += applist (installed_apps $true) $true
        }
    } else {
        $apps = Confirm-InstallationStatus $apps_param -Global:$global
    }
    if ($apps) {
        $apps | ForEach-Object {
            ($app, $global) = $_
            $status = app_status $app $global
            if ($force -or $status.outdated) {
                if(!$status.hold) {
                    $outdated += applist $app $global
                    write-host -f yellow ("$app`: $($status.version) -> $($status.latest_version){0}" -f ('',' (global)')[$global])
                } else {
                    warn "'$app' 被锁定在版本 $($status.version)"
                }
            } elseif ($apps_param -ne '*') {
                write-host -f green "$app`: $($status.version) (latest version)"
            }
        }

        if ($outdated -and (Test-Aria2Enabled)) {
            warn "Scoop 使用'aria2c' 来进行多线程下载."
            warn "如果这导致了一些问题, 执行 'scoop config aria2-enabled false' 来禁用它."
        }
        if ($outdated.Length -gt 1) {
            write-host -f DarkCyan "正在更新 $($outdated.Length) 个过时的应用:"
        } elseif ($outdated.Length -eq 0) {
            write-host -f Green "所有应用的最新版本已安装! 可以通过 'scoop status' 来获取更多信息"
        } else {
            write-host -f DarkCyan "正在更新一个过时的应用:"
        }
    }

    $suggested = @{};
    # $outdated is a list of ($app, $global) tuples
    $outdated | ForEach-Object { update @_ $quiet $independent $suggested $use_cache $check_hash }
}

exit 0
