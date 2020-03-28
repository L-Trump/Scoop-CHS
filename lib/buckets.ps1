. "$PSScriptRoot\core.ps1"

$bucketsdir = "$scoopdir\buckets"

function Find-BucketDirectory {
    <#
    .DESCRIPTION
        Return full path for bucket with given name.
        Main bucket will be returned as default.
    .PARAMETER Name
        Name of bucket.
    .PARAMETER Root
        Root folder of bucket repository will be returned instead of 'bucket' subdirectory (if exists).
    #>
    param(
        [string] $Name = 'main',
        [switch] $Root
    )

    # Handle info passing empty string as bucket ($install.bucket)
    if(($null -eq $Name) -or ($Name -eq '')) { $Name = 'main' }
    $bucket = "$bucketsdir\$Name"

    if ((Test-Path "$bucket\bucket") -and !$Root) {
        $bucket = "$bucket\bucket"
    }

    return $bucket
}

function bucketdir($name) {
    Show-DeprecatedWarning $MyInvocation 'Find-BucketDirectory'

    return Find-BucketDirectory $name
}

function known_bucket_repos {
    $json = "$PSScriptRoot\..\buckets.json"

    return Get-Content $json -raw | convertfrom-json -ea stop
}

function known_bucket_repo($name) {
    $buckets = known_bucket_repos
    $buckets.$name
}

function known_buckets {
    known_bucket_repos | ForEach-Object { $_.psobject.properties | Select-Object -expand 'name' }
}

function apps_in_bucket($dir) {
    return Get-ChildItem $dir | Where-Object { $_.Name.endswith('.json') } | ForEach-Object { $_.Name -replace '.json$', '' }
}

function Get-LocalBucket {
    <#
    .SYNOPSIS
        List all local buckets.
    #>

    return (Get-ChildItem -Directory $bucketsdir).Name
}

function buckets {
    Show-DeprecatedWarning $MyInvocation 'Get-LocalBucket'

    return Get-LocalBucket
}

function find_manifest($app, $bucket) {
    if ($bucket) {
        $manifest = manifest $app $bucket
        if ($manifest) { return $manifest, $bucket }
        return $null
    }

    foreach($bucket in Get-LocalBucket) {
        $manifest = manifest $app $bucket
        if($manifest) { return $manifest, $bucket }
    }
}

function add_bucket($name, $repo) {
    if (!$name) { "<name> 参数缺失"; $usage_add; exit 1 }
    if (!$repo) {
        $repo = known_bucket_repo $name
        if (!$repo) { "未知的仓库 '$name'. 请尝试指定Git仓库地址 <repo>."; $usage_add; exit 1 }
    }

    if (!(Test-CommandAvailable git)) {
        abort "添加仓库需要Git的支持. 运行 'scoop install git' 后再次尝试."
    }

    $dir = Find-BucketDirectory $name -Root
    if (test-path $dir) {
        warn "仓库 '$name' 已存在. 使用 'scoop bucket rm $name' 来移除它."
        exit 0
    }

    write-host '检查仓库地址... ' -nonewline
    $out = git_ls_remote $repo 2>&1
    if ($lastexitcode -ne 0) {
        abort "'$repo' 并不是一个有效的Git仓库`n`nError given:`n$out"
    }
    write-host 'ok'

    ensure $bucketsdir > $null
    $dir = ensure $dir
    git_clone "$repo" "`"$dir`"" -q
    success "仓库 $name 成功添加到了Scoop."
}

function rm_bucket($name) {
    if (!$name) { "<name> 参数缺失"; $usage_rm; exit 1 }
    $dir = Find-BucketDirectory $name -Root
    if (!(test-path $dir)) {
        abort "'$name' 仓库不存在."
    }

    Remove-Item $dir -r -force -ea stop
}

function new_issue_msg($app, $bucket, $title, $body) {
    $app, $manifest, $bucket, $url = Find-Manifest $app $bucket
    $url = known_bucket_repo $bucket
    $bucket_path = "$bucketsdir\$bucket"

    if (Test-path $bucket_path) {
        Push-Location $bucket_path
        $remote = Invoke-Expression "git config --get remote.origin.url"
        # Support ssh and http syntax
        # git@PROVIDER:USER/REPO.git
        # https://PROVIDER/USER/REPO.git
        $remote -match '(@|:\/\/)(?<provider>.+)[:/](?<user>.*)\/(?<repo>.*)(\.git)?$' | Out-Null
        $url = "https://$($Matches.Provider)/$($Matches.User)/$($Matches.Repo)"
        Pop-Location
    }

    if(!$url) { return '请联系仓库维护人员!' }

    # Print only github repositories
    if ($url -like '*github*') {
        $title = [System.Web.HttpUtility]::UrlEncode("$app@$($manifest.version): $title")
        $body = [System.Web.HttpUtility]::UrlEncode($body)
        $url = $url -replace '\.git$', ''
        $url = "$url/issues/new?title=$title"
        if($body) {
            $url += "&body=$body"
        }
    }

    $msg = "`n请再次尝试或者在下列地址中添加issue，记得附上你的控制台输出:"
    return "$msg`n$url"
}
