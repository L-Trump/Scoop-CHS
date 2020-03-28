# Usage: scoop status
# Summary: 检查应用状态与应用更新

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\manifest.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. "$psscriptroot\..\lib\versions.ps1"
. "$psscriptroot\..\lib\depends.ps1"
. "$psscriptroot\..\lib\git.ps1"

reset_aliases

# check if scoop needs updating
$currentdir = fullpath $(versiondir 'scoop' 'current')
$needs_update = $false

if(test-path "$currentdir\.git") {
    Push-Location $currentdir
    git_fetch -q origin
    $commits = $(git log "HEAD..origin/$(scoop config SCOOP_BRANCH)" --oneline)
    if($commits) { $needs_update = $true }
    Pop-Location
}
else {
    $needs_update = $true
}

if($needs_update) {
    warn "Scoop有新的更新可用. 执行 'scoop update' 来更新Scoop."
}
else { success "Scoop已是最新."}

$failed = @()
$outdated = @()
$removed = @()
$missing_deps = @()
$onhold = @()

$true, $false | ForEach-Object { # local and global apps
    $global = $_
    $dir = appsdir $global
    if(!(test-path $dir)) { return }

    Get-ChildItem $dir | Where-Object name -ne 'scoop' | ForEach-Object {
        $app = $_.name
        $status = app_status $app $global
        if($status.failed) {
            $failed += @{ $app = $status.version }
        }
        if($status.removed) {
            $removed += @{ $app = $status.version }
        }
        if($status.outdated) {
            $outdated += @{ $app = @($status.version, $status.latest_version) }
            if($status.hold) {
                $onhold += @{ $app = @($status.version, $status.latest_version) }
            }
        }
        if($status.missing_deps) {
            $missing_deps += ,(@($app) + @($status.missing_deps))
        }
    }
}

if($outdated) {
    write-host -f DarkCyan '下列应用可更新:'
    $outdated.keys | ForEach-Object {
        $versions = $outdated.$_
        "    $_`: $($versions[0]) -> $($versions[1])"
    }
}

if($onhold) {
    write-host -f DarkCyan '下列被锁定的应用可更新:'
    $onhold.keys | ForEach-Object {
        $versions = $onhold.$_
        "    $_`: $($versions[0]) -> $($versions[1])"
    }
}

if($removed) {
    write-host -f DarkCyan '这些应用的Manifest已被移除:'
    $removed.keys | ForEach-Object {
        "    $_"
    }
}

if($failed) {
    write-host -f DarkCyan '下列应用安装失败:'
    $failed.keys | ForEach-Object {
        "    $_"
    }
}

if($missing_deps) {
    write-host -f DarkCyan '下列应用缺失运行环境:'
    $missing_deps | ForEach-Object {
        $app, $deps = $_
        "    '$app' 需要 '$([string]::join("', '", $deps))'"
    }
}

if(!$old -and !$removed -and !$failed -and !$missing_deps -and !$needs_update) {
    success "所有应用都没问题!"
}

exit 0
