. "$psscriptroot/autoupdate.ps1"
. "$psscriptroot/buckets.ps1"

function nightly_version($date, $quiet = $false) {
    $date_str = $date.tostring("yyyyMMdd")
    if (!$quiet) {
        warn "这是nightly版本，下载的文件不会进行数据校验."
    }
    "nightly-$date_str"
}

function install_app($app, $architecture, $global, $suggested, $use_cache = $true, $check_hash = $true) {
    $app, $bucket, $null = parse_app $app
    $app, $manifest, $bucket, $url = Find-Manifest $app $bucket

    if(!$manifest) {
        abort "$(if($url) { "无法在URL $url 中找到 " }) '$app'."
    }
    $version = $manifest.version
    if(!$version) { abort "Manifest中未定义版本号." }
    if($version -match '[^\w\.\-\+_]') {
        abort "Manifest版本号中含有不支持的字符 '$($matches[0])'."
    }

    $is_nightly = $version -eq 'nightly'
    if ($is_nightly) {
        $version = nightly_version $(get-date)
        $check_hash = $false
    }

    if(!(supports_architecture $manifest $architecture)) {
        write-host -f DarkRed "'$app' 不支持 $architecture 版本!"
        return
    }
    $nocurrent = $manifest.nocurrent
    write-output "安装 '$app' ($version) [$architecture]"
    $dir = ensure (versiondir $app $version $global)
    $original_dir = $dir # keep reference to real (not linked) directory
    $persist_dir = persistdir $app $global

    $fname = dl_urls $app $version $manifest $bucket $architecture $dir $use_cache $check_hash
    pre_install $manifest $architecture
    run_installer $fname $manifest $architecture $dir $global
    ensure_install_dir_not_in_path $dir $global
    if( $nocurrent -eq $true ) {
        Write-Host -f Yellow "Manifest中要求本应用不使用Current目录"
    } else {
        $dir = link_current $dir
    }
    create_shims $manifest $dir $global $architecture
    create_startmenu_shortcuts $manifest $dir $global $architecture
    install_psmodule $manifest $dir $global
    if($global) { ensure_scoop_in_path $global } # can assume local scoop is in path
    env_add_path $manifest $dir $global $architecture
    env_set $manifest $dir $global $architecture

    # persist data
    persist_data $manifest $original_dir $persist_dir
    persist_permission $manifest $global

    post_install $manifest $architecture

    # save info for uninstall
    save_installed_manifest $app $bucket $dir $url
    save_install_info @{ 'architecture' = $architecture; 'url' = $url; 'bucket' = $bucket } $dir

    if($manifest.suggest) {
        $suggested[$app] = $manifest.suggest
    }

    success "'$app' ($version) 成功安装!"

    show_notes $manifest $dir $original_dir $persist_dir
}

function locate($app, $bucket) {
    Show-DeprecatedWarning $MyInvocation 'Find-Manifest'
    return Find-Manifest $app $bucket
}

function Find-Manifest($app, $bucket) {
    $manifest, $url = $null, $null

    # check if app is a URL or UNC path
    if($app -match '^(ht|f)tps?://|\\\\') {
        $url = $app
        $app = appname_from_url $url
        $manifest = url_manifest $url
    } else {
        # check buckets
        $manifest, $bucket = find_manifest $app $bucket

        if(!$manifest) {
            # couldn't find app in buckets: check if it's a local path
            $path = $app
            if(!$path.endswith('.json')) { $path += '.json' }
            if(test-path $path) {
                $url = "$(resolve-path $path)"
                $app = appname_from_url $url
                $manifest, $bucket = url_manifest $url
            }
        }
    }

    return $app, $manifest, $bucket, $url
}

function dl_with_cache($app, $version, $url, $to, $cookies = $null, $use_cache = $true) {
    $cached = fullpath (cache_path $app $version $url)

    if(!(test-path $cached) -or !$use_cache) {
        ensure $cachedir | Out-Null
        do_dl $url "$cached.download" $cookies
        Move-Item "$cached.download" $cached -force
    } else { write-host "从缓存中加载 $(url_remote_filename $url)"}

    if (!($null -eq $to)) {
        Copy-Item $cached $to
    }
}

function do_dl($url, $to, $cookies) {
    $progress = [console]::isoutputredirected -eq $false -and
        $host.name -ne 'Windows PowerShell ISE Host'

    try {
        $url = handle_special_urls $url
        dl $url $to $cookies $progress
    } catch {
        $e = $_.exception
        if($e.innerexception) { $e = $e.innerexception }
        throw $e
    }
}

function aria_exit_code($exitcode) {
    $codes = @{
        0='下载完成'
        1='未知错误'
        2='连接超时'
        3='资源不存在'
        4='Aria2发现了指定数量的"资源不存在"错误. 详情查看 --max-file-not-found 配置项'
        5='由于下载速度过慢，下载已停止. 详情查看 --lowest-speed-limit 配置项'
        6='出现网络错误.'
        7='存在未完成的下载. 只有当用户按Ctrl-C或发送TERM或INT信号退出aria2，所有完成的下载都成功并且队列中有未完成的下载时，才会报告此错误'
        8='需要恢复下载进度，但远程服务器不支持'
        9='硬盘空间不足'
        10='分块长度与 .aria2 控制文件中设定的不同. 请查看 --allow-piece-length-change 配置项'
        11='Aria2 正在下载相同的文件'
        12='Aria2 正在下载Hash校验值相同的Torrent文件'
        13='文件已存在. 请查看 --allow-overwrite 配置项'
        14='重命名失败. 请查看 --auto-file-renaming 配置项'
        15='Aria2 无法打开已存在的文件'
        16='Aria2 无法创建新文件或者修改现有文件'
        17='发生文件 I/O 错误'
        18='Aria2 无法创建目录'
        19='文件名解析失败'
        20='Aria2 无法解析 Metalink 文档'
        21='FTP 命令执行失败'
        22='HTTP 的响应头部返回了错误信息'
        23='存在太多的重定向'
        24='HTTP 认证失败'
        25='Aria2 无法解析 bencoded 文件 (通常是 ".torrent" 文件)'
        26='".torrent" 文件缺少Aria2需要的信息'
        27='磁力链接有误'
        28='发现错误的配置或参数'
        29='由于临时过载或维护，远程服务器无法处理该请求'
        30='Aria2 无法解析 JSON-RPC 请求'
        31='Reserved. Not used'
        32='文件校验失败'
    }
    if($null -eq $codes[$exitcode]) {
        return '发生未知错误'
    }
    return $codes[$exitcode]
}

function get_filename_from_metalink($file) {
    $bytes = get_magic_bytes_pretty $file ''
    # check if file starts with '<?xml'
    if(!($bytes.StartsWith('3c3f786d6c'))) {
        return $null
    }

    # Add System.Xml for reading metalink files
    Add-Type -AssemblyName 'System.Xml'
    $xr = [System.Xml.XmlReader]::Create($file)
    $filename = $null
    try {
        $xr.ReadStartElement('metalink')
        if($xr.ReadToFollowing('file') -and $xr.MoveToFirstAttribute()) {
            $filename = $xr.Value
        }
    } catch [System.Xml.XmlException] {
        return $null
    } finally {
        $xr.Close()
    }

    return $filename
}

function dl_with_cache_aria2($app, $version, $manifest, $architecture, $dir, $cookies = $null, $use_cache = $true, $check_hash = $true) {
    $data = @{}
    $urls = @(url $manifest $architecture)

    # aria2 input file
    $urlstxt = Join-Path $cachedir "$app.txt"
    $urlstxt_content = ''
    $has_downloads = $false

    # aria2 options
    $options = @(
        "--input-file='$urlstxt'"
        "--user-agent='$(Get-UserAgent)'"
        "--allow-overwrite=true"
        "--auto-file-renaming=false"
        "--retry-wait=$(get_config 'aria2-retry-wait' 2)"
        "--split=$(get_config 'aria2-split' 5)"
        "--max-connection-per-server=$(get_config 'aria2-max-connection-per-server' 5)"
        "--min-split-size=$(get_config 'aria2-min-split-size' '5M')"
        "--console-log-level=warn"
        "--enable-color=false"
        "--no-conf=true"
        "--follow-metalink=true"
        "--metalink-preferred-protocol=https"
        "--min-tls-version=TLSv1.2"
        "--stop-with-process=$PID"
        "--continue"
    )

    if($cookies) {
        $options += "--header='Cookie: $(cookie_header $cookies)'"
    }

    $proxy = get_config 'proxy'
    if($proxy -ne 'none') {
        if([Net.Webrequest]::DefaultWebProxy.Address) {
            $options += "--all-proxy='$([Net.Webrequest]::DefaultWebProxy.Address.Authority)'"
        }
        if([Net.Webrequest]::DefaultWebProxy.Credentials.UserName) {
            $options += "--all-proxy-user='$([Net.Webrequest]::DefaultWebProxy.Credentials.UserName)'"
        }
        if([Net.Webrequest]::DefaultWebProxy.Credentials.Password) {
            $options += "--all-proxy-passwd='$([Net.Webrequest]::DefaultWebProxy.Credentials.Password)'"
        }
    }

    $more_options = get_config 'aria2-options'
    if($more_options) {
        $options += $more_options
    }

    foreach($url in $urls) {
        $data.$url = @{
            'filename' = url_filename $url
            'target' = "$dir\$(url_filename $url)"
            'cachename' = fname (cache_path $app $version $url)
            'source' = fullpath (cache_path $app $version $url)
        }

        if(!(test-path $data.$url.source)) {
            $has_downloads = $true
            # create aria2 input file content
            $urlstxt_content += "$(handle_special_urls $url)`n"
            if(!$url.Contains('sourceforge.net')) {
                $urlstxt_content += "    referer=$(strip_filename $url)`n"
            }
            $urlstxt_content += "    dir=$cachedir`n"
            $urlstxt_content += "    out=$($data.$url.cachename)`n"
        } else {
            Write-Host "从缓存中加载 " -NoNewline
            Write-Host $(url_remote_filename $url) -f Cyan
        }
    }

    if($has_downloads) {
        # write aria2 input file
        Set-Content -Path $urlstxt $urlstxt_content

        # build aria2 command
        $aria2 = "& '$(Get-HelperPath -Helper Aria2)' $($options -join ' ')"

        # handle aria2 console output
        Write-Host "开始使用Aria2下载..."
        $prefix = "Download: "
        Invoke-Expression $aria2 | ForEach-Object {
            if([String]::IsNullOrWhiteSpace($_)) {
                # skip blank lines
                return
            }
            Write-Host $prefix -NoNewline
            if($_.StartsWith('(OK):')) {
                Write-Host $_ -f Green
            } elseif($_.StartsWith('[') -and $_.EndsWith(']')) {
                Write-Host $_ -f Cyan
            } else {
                Write-Host $_ -f Gray
            }
        }

        if($lastexitcode -gt 0) {
            error "下载失败! (Error $lastexitcode) $(aria_exit_code $lastexitcode)"
            error $urlstxt_content
            error $aria2
            abort $(new_issue_msg $app $bucket "通过Aria2下载失败")
        }

        # remove aria2 input file when done
        if(test-path($urlstxt)) {
            Remove-Item $urlstxt
        }
    }

    foreach($url in $urls) {

        $metalink_filename = get_filename_from_metalink $data.$url.source
        if($metalink_filename) {
            Remove-Item $data.$url.source -Force
            Rename-Item -Force (Join-Path -Path $cachedir -ChildPath $metalink_filename) $data.$url.source
        }

        # run hash checks
        if($check_hash) {
            $manifest_hash = hash_for_url $manifest $url $architecture
            $ok, $err = check_hash $data.$url.source $manifest_hash $(show_app $app $bucket)
            if(!$ok) {
                error $err
                if(test-path $data.$url.source) {
                    # rm cached file
                    Remove-Item -force $data.$url.source
                }
                if($url.Contains('sourceforge.net')) {
                    Write-Host -f yellow '众所周知，SourceForge.net会导致哈希验证失败。建议你再试一次。'
                }
                abort $(new_issue_msg $app $bucket "Hash校验失败")
            }
        }

        # copy or move file to target location
        if(!(test-path $data.$url.source) ) {
            abort $(new_issue_msg $app $bucket "未找到缓存")
        }

        if(!($dir -eq $cachedir)) {
            if($use_cache) {
                Copy-Item $data.$url.source $data.$url.target
            } else {
                Move-Item $data.$url.source $data.$url.target -force
            }
        }
    }
}

# download with filesize and progress indicator
function dl($url, $to, $cookies, $progress) {
    $reqUrl = ($url -split "#")[0]
    $wreq = [net.webrequest]::create($reqUrl)
    if($wreq -is [net.httpwebrequest]) {
        $wreq.useragent = Get-UserAgent
        if (-not ($url -imatch "sourceforge\.net")) {
            $wreq.referer = strip_filename $url
        }
        if($cookies) {
            $wreq.headers.add('Cookie', (cookie_header $cookies))
        }
    }

    $wres = $wreq.getresponse()
    $total = $wres.ContentLength
    if($total -eq -1 -and $wreq -is [net.ftpwebrequest]) {
        $total = ftp_file_size($url)
    }

    if ($progress -and ($total -gt 0)) {
        [console]::CursorVisible = $false
        function dl_onProgress($read) {
            dl_progress $read $total $url
        }
    } else {
        write-host "下载 $url ($(filesize $total))..."
        function dl_onProgress {
            #no op
        }
    }

    try {
        $s = $wres.getresponsestream()
        $fs = [io.file]::openwrite($to)
        $buffer = new-object byte[] 2048
        $totalRead = 0
        $sw = [diagnostics.stopwatch]::StartNew()

        dl_onProgress $totalRead
        while(($read = $s.read($buffer, 0, $buffer.length)) -gt 0) {
            $fs.write($buffer, 0, $read)
            $totalRead += $read
            if ($sw.elapsedmilliseconds -gt 100) {
                $sw.restart()
                dl_onProgress $totalRead
            }
        }
        $sw.stop()
        dl_onProgress $totalRead
    } finally {
        if ($progress) {
            [console]::CursorVisible = $true
            write-host
        }
        if ($fs) {
            $fs.close()
        }
        if ($s) {
            $s.close();
        }
        $wres.close()
    }
}

function dl_progress_output($url, $read, $total, $console) {
    $filename = url_remote_filename $url

    # calculate current percentage done
    $p = [math]::Round($read / $total * 100, 0)

    # pre-generate LHS and RHS of progress string
    # so we know how much space we have
    $left  = "$filename ($(filesize $total))"
    $right = [string]::Format("{0,3}%", $p)

    # calculate remaining width for progress bar
    $midwidth  = $console.BufferSize.Width - ($left.Length + $right.Length + 8)

    # calculate how many characters are completed
    $completed = [math]::Abs([math]::Round(($p / 100) * $midwidth, 0) - 1)

    # generate dashes to symbolise completed
    if ($completed -gt 1) {
        $dashes = [string]::Join("", ((1..$completed) | ForEach-Object {"="}))
    }

    # this is why we calculate $completed - 1 above
    $dashes += switch($p) {
        100 {"="}
        default {">"}
    }

    # the remaining characters are filled with spaces
    $spaces = switch($dashes.Length) {
        $midwidth {[string]::Empty}
        default {
            [string]::Join("", ((1..($midwidth - $dashes.Length)) | ForEach-Object {" "}))
        }
    }

    "$left [$dashes$spaces] $right"
}

function dl_progress($read, $total, $url) {
    $console = $host.UI.RawUI;
    $left  = $console.CursorPosition.X;
    $top   = $console.CursorPosition.Y;
    $width = $console.BufferSize.Width;

    if($read -eq 0) {
        $maxOutputLength = $(dl_progress_output $url 100 $total $console).length
        if (($left + $maxOutputLength) -gt $width) {
            # not enough room to print progress on this line
            # print on new line
            write-host
            $left = 0
            $top  = $top + 1
        }
    }

    write-host $(dl_progress_output $url $read $total $console) -nonewline
    [console]::SetCursorPosition($left, $top)
}

function dl_urls($app, $version, $manifest, $bucket, $architecture, $dir, $use_cache = $true, $check_hash = $true) {
    # we only want to show this warning once
    if(!$use_cache) { warn "缓存将被忽略." }

    # can be multiple urls: if there are, then msi or installer should go last,
    # so that $fname is set properly
    $urls = @(url $manifest $architecture)

    # can be multiple cookies: they will be used for all HTTP requests.
    $cookies = $manifest.cookie

    $fname = $null

    # extract_dir and extract_to in manifest are like queues: for each url that
    # needs to be extracted, will get the next dir from the queue
    $extract_dirs = @(extract_dir $manifest $architecture)
    $extract_tos = @(extract_to $manifest $architecture)
    $extracted = 0;

    # download first
    if(Test-Aria2Enabled) {
        dl_with_cache_aria2 $app $version $manifest $architecture $dir $cookies $use_cache $check_hash
    } else {
        foreach($url in $urls) {
            $fname = url_filename $url

            try {
                dl_with_cache $app $version $url "$dir\$fname" $cookies $use_cache
            } catch {
                write-host -f darkred $_
                abort "地址 $url 无效"
            }

            if($check_hash) {
                $manifest_hash = hash_for_url $manifest $url $architecture
                $ok, $err = check_hash "$dir\$fname" $manifest_hash $(show_app $app $bucket)
                if(!$ok) {
                    error $err
                    $cached = cache_path $app $version $url
                    if(test-path $cached) {
                        # rm cached file
                        Remove-Item -force $cached
                    }
                    if($url.Contains('sourceforge.net')) {
                        Write-Host -f yellow '众所周知，SourceForge.net会导致哈希验证失败。建议你再试一次。'
                    }
                    abort $(new_issue_msg $app $bucket "Hash校验失败")
                }
            }
        }
    }

    foreach($url in $urls) {
        $fname = url_filename $url

        $extract_dir = $extract_dirs[$extracted]
        $extract_to = $extract_tos[$extracted]

        # work out extraction method, if applicable
        $extract_fn = $null
        if ($manifest.innosetup) {
            $extract_fn = 'Expand-InnoArchive'
        } elseif($fname -match '\.zip$') {
            # Use 7zip when available (more fast)
            if (((get_config 7ZIPEXTRACT_USE_EXTERNAL) -and (Test-CommandAvailable 7z)) -or (Test-HelperInstalled -Helper 7zip)) {
                $extract_fn = 'Expand-7zipArchive'
            } else {
                $extract_fn = 'Expand-ZipArchive'
            }
        } elseif($fname -match '\.msi$') {
            # check manifest doesn't use deprecated install method
            if(msi $manifest $architecture) {
                warn "不建议使用MSI安装, 如果您维护这个Manifest，请参阅参考文档."
            } else {
                $extract_fn = 'Expand-MsiArchive'
            }
        } elseif(Test-7zipRequirement -File $fname) { # 7zip
            $extract_fn = 'Expand-7zipArchive'
        }

        if($extract_fn) {
            Write-Host "正在解压 " -NoNewline
            Write-Host $fname -f Cyan -NoNewline
            Write-Host " ... " -NoNewline
            & $extract_fn -Path "$dir\$fname" -DestinationPath "$dir\$extract_to" -ExtractDir $extract_dir -Removal
            Write-Host "完成" -f Green
            $extracted++
        }
    }

    $fname # returns the last downloaded file
}

function cookie_header($cookies) {
    if(!$cookies) { return }

    $vals = $cookies.psobject.properties | ForEach-Object {
        "$($_.name)=$($_.value)"
    }

    [string]::join(';', $vals)
}

function is_in_dir($dir, $check) {
    $check = "$(fullpath $check)"
    $dir = "$(fullpath $dir)"
    $check -match "^$([regex]::escape("$dir"))(\\|`$)"
}

function ftp_file_size($url) {
    $request = [net.ftpwebrequest]::create($url)
    $request.method = [net.webrequestmethods+ftp]::getfilesize
    $request.getresponse().contentlength
}

# hashes
function hash_for_url($manifest, $url, $arch) {
    $hashes = @(hash $manifest $arch) | Where-Object { $_ -ne $null };

    if($hashes.length -eq 0) { return $null }

    $urls = @(url $manifest $arch)

    $index = [array]::indexof($urls, $url)
    if($index -eq -1) { abort "无法在 '$url' 中找到Hash值" }

    @($hashes)[$index]
}

# returns (ok, err)
function check_hash($file, $hash, $app_name) {
    $file = fullpath $file
    if(!$hash) {
        warn "警告, Manifest中未指定Hash. '$(fname $file)' 的SHA256校验值为:`n    $(compute_hash $file 'sha256')"
        return $true, $null
    }

    Write-Host "检查 " -NoNewline
    Write-Host $(url_remote_filename $url) -f Cyan -NoNewline
    Write-Host " 的Hash值... " -nonewline
    $algorithm, $expected = get_hash $hash
    if ($null -eq $algorithm) {
        return $false, "不支持Hash类型 '$algorithm'."
    }

    $actual = compute_hash $file $algorithm
    $expected = $expected.ToLower()

    if($actual -ne $expected) {
        $msg = "Hash校验失败!`n"
        $msg += "App:         $app_name`n"
        $msg += "URL:         $url`n"
        if(Test-Path $file) {
            $msg += "First bytes: $((get_magic_bytes_pretty $file ' ').ToUpper())`n"
        }
        if($expected -or $actual) {
            $msg += "预期Hash值:    $expected`n"
            $msg += "实际Hash值:    $actual"
        }
        return $false, $msg
    }
    Write-Host "ok." -f Green
    return $true, $null
}

function compute_hash($file, $algname) {
    try {
        if(Test-CommandAvailable Get-FileHash) {
            return (Get-FileHash -Path $file -Algorithm $algname).Hash.ToLower()
        } else {
            $fs = [system.io.file]::openread($file)
            $alg = [system.security.cryptography.hashalgorithm]::create($algname)
            $hexbytes = $alg.computehash($fs) | ForEach-Object { $_.tostring('x2') }
            return [string]::join('', $hexbytes)
        }
    } catch {
        error $_.exception.message
    } finally {
        if($fs) { $fs.dispose() }
        if($alg) { $alg.dispose() }
    }
    return ''
}

# for dealing with installers
function args($config, $dir, $global) {
    if($config) { return $config | ForEach-Object { (format $_ @{'dir'=$dir;'global'=$global}) } }
    @()
}

function run_installer($fname, $manifest, $architecture, $dir, $global) {
    # MSI or other installer
    $msi = msi $manifest $architecture
    $installer = installer $manifest $architecture
    if($installer.script) {
        write-output "运行安装脚本..."
        Invoke-Expression (@($installer.script) -join "`r`n")
        return
    }

    if($msi) {
        install_msi $fname $dir $msi
    } elseif($installer) {
        install_prog $fname $dir $installer $global
    }
}

# deprecated (see also msi_installed)
function install_msi($fname, $dir, $msi) {
    $msifile = "$dir\$(coalesce $msi.file "$fname")"
    if(!(is_in_dir $dir $msifile)) {
        abort "在Manifest中发现错误: MSI 文件 $msifile 在App目录之外."
    }
    if(!($msi.code)) { abort "在Manifest中发现错误: 未找到 MSI code."}
    if(msi_installed $msi.code) { abort "这个MSI安装包已经安装在当前系统中了." }

    $logfile = "$dir\install.log"

    $arg = @("/i `"$msifile`"", '/norestart', "/lvp `"$logfile`"", "TARGETDIR=`"$dir`"",
        "INSTALLDIR=`"$dir`"") + @(args $msi.args $dir)

    if($msi.silent) { $arg += '/qn', 'ALLUSERS=2', 'MSIINSTALLPERUSER=1' }
    else { $arg += '/qb-!' }

    $continue_exit_codes = @{ 3010 = "需要重启来完成安装" }

    $installed = Invoke-ExternalCommand 'msiexec' $arg -Activity "Running installer..." -ContinueExitCodes $continue_exit_codes
    if(!$installed) {
        abort "安装中止. 也许你需要运行 'scoop uninstall $app' 后再尝试."
    }
    Remove-Item $logfile
    Remove-Item $msifile
}

# deprecated
# get-wmiobject win32_product is slow and checks integrity of each installed program,
# so this uses the [wmi] type accelerator instead
# http://blogs.technet.com/b/heyscriptingguy/archive/2011/12/14/use-powershell-to-find-and-uninstall-software.aspx
function msi_installed($code) {
    $path = "hklm:\software\microsoft\windows\currentversion\uninstall\$code"
    if(!(test-path $path)) { return $false }
    $key = Get-Item $path
    $name = $key.getvalue('displayname')
    $version = $key.getvalue('displayversion')
    $classkey = "IdentifyingNumber=`"$code`",Name=`"$name`",Version=`"$version`""
    try { $wmi = [wmi]"Win32_Product.$classkey"; $true } catch { $false }
}

function install_prog($fname, $dir, $installer, $global) {
    $prog = "$dir\$(coalesce $installer.file "$fname")"
    if(!(is_in_dir $dir $prog)) {
        abort "在Manifest中发现错误: 安装包 $prog 位于App目录之外."
    }
    $arg = @(args $installer.args $dir $global)

    if($prog.endswith('.ps1')) {
        & $prog @arg
    } else {
        $installed = Invoke-ExternalCommand $prog $arg -Activity "Running installer..."
        if(!$installed) {
            abort "安装中止. 也许你需要运行 'scoop uninstall $app' 后再尝试."
        }

        # Don't remove installer if "keep" flag is set to true
        if(!($installer.keep -eq "true")) {
            Remove-Item $prog
        }
    }
}

function run_uninstaller($manifest, $architecture, $dir) {
    $msi = msi $manifest $architecture
    $uninstaller = uninstaller $manifest $architecture
    $version = $manifest.version
    if($uninstaller.script) {
        write-output "运行卸载脚本..."
        Invoke-Expression (@($uninstaller.script) -join "`r`n")
        return
    }

    if($msi -or $uninstaller) {
        $exe = $null; $arg = $null; $continue_exit_codes = @{}

        if($msi) {
            $code = $msi.code
            $exe = "msiexec";
            $arg = @("/norestart", "/x $code")
            if($msi.silent) {
                $arg += '/qn', 'ALLUSERS=2', 'MSIINSTALLPERUSER=1'
            } else {
                $arg += '/qb-!'
            }

            $continue_exit_codes.1605 = '未安装, 已跳过'
            $continue_exit_codes.3010 = '需要重启'
        } elseif($uninstaller) {
            $exe = "$dir\$($uninstaller.file)"
            $arg = args $uninstaller.args
            if(!(is_in_dir $dir $exe)) {
                warn "在Manifest中发现错误: 程序 $exe 位于App目录之外，已跳过."
                $exe = $null;
            } elseif(!(test-path $exe)) {
                warn "未找到卸载程序 $exe, 已跳过."
                $exe = $null;
            }
        }

        if($exe) {
            if($exe.endswith('.ps1')) {
                & $exe @arg
            } else {
                $uninstalled = Invoke-ExternalCommand $exe $arg -Activity "运行卸载程序..." -ContinueExitCodes $continue_exit_codes
                if(!$uninstalled) { abort "卸载中止." }
            }
        }
    }
}

# get target, name, arguments for shim
function shim_def($item) {
    if($item -is [array]) { return $item }
    return $item, (strip_ext (fname $item)), $null
}

function create_shims($manifest, $dir, $global, $arch) {
    $noWait = $manifest.nowait
    $shims = @(arch_specific 'bin' $manifest $arch)
    $shims | Where-Object { $_ -ne $null } | ForEach-Object {
        $target, $name, $arg = shim_def $_
        write-output "为 '$name' 创造 Shim."
        if ($nowait -eq $true) { Write-Host "本应用创建的Shim将不等待进程运行结束后关闭" }
        if(test-path "$dir\$target" -pathType leaf) {
            $bin = "$dir\$target"
        } elseif(test-path $target -pathType leaf) {
            $bin = $target
        } else {
            $bin = search_in_path $target
        }
        if(!$bin) { abort "无法创造shim '$target': 文件不存在."}

        shim $bin $global $name (substitute $arg @{ '$dir' = $dir; '$original_dir' = $original_dir; '$persist_dir' = $persist_dir}) $noWait
    }
}

function rm_shim($name, $shimdir) {
    $shim = "$shimdir\$name.ps1"

    if(!(test-path $shim)) { # handle no shim from failed install
        warn "'$name' 的shim不存在. 已跳过."
    } else {
        write-output "移除 '$name' 的 Shim."
        Remove-Item $shim
    }

    # other shim types might be present
    '', '.exe', '.shim', '.cmd' | ForEach-Object {
        if(test-path -Path "$shimdir\$name$_" -PathType leaf) {
            Remove-Item "$shimdir\$name$_"
        }
    }
}

function rm_shims($manifest, $global, $arch) {
    $shims = @(arch_specific 'bin' $manifest $arch)

    $shims | Where-Object { $_ -ne $null } | ForEach-Object {
        $target, $name, $null = shim_def $_
        $shimdir = shimdir $global

        rm_shim $name $shimdir
    }
}

# Gets the path for the 'current' directory junction for
# the specified version directory.
function current_dir($versiondir) {
    $parent = split-path $versiondir
    return "$parent\current"
}


# Creates or updates the directory junction for [app]/current,
# pointing to the specified version directory for the app.
#
# Returns the 'current' junction directory if in use, otherwise
# the version directory.
function link_current($versiondir) {
    if(get_config NO_JUNCTIONS) { return $versiondir }

    $currentdir = current_dir $versiondir

    write-host "链接 $(friendly_path $currentdir) => $(friendly_path $versiondir)"

    if($currentdir -eq $versiondir) {
        abort "错误: 禁止使用版本号 'current'!"
    }

    if(test-path $currentdir) {
        # remove the junction
        attrib -R /L $currentdir
        & "$env:COMSPEC" /c rmdir $currentdir
    }

    & "$env:COMSPEC" /c mklink /j $currentdir $versiondir | out-null
    attrib $currentdir +R /L
    return $currentdir
}

# Removes the directory junction for [app]/current which
# points to the current version directory for the app.
#
# Returns the 'current' junction directory (if it exists),
# otherwise the normal version directory.
function unlink_current($versiondir) {
    if(get_config NO_JUNCTIONS) { return $versiondir }
    $currentdir = current_dir $versiondir

    if(test-path $currentdir) {
        write-host "取消链接 $(friendly_path $currentdir)"

        # remove read-only attribute on link
        attrib $currentdir -R /L

        # remove the junction
        & "$env:COMSPEC" /c "rmdir `"$currentdir`""
        return $currentdir
    }
    return $versiondir
}

# to undo after installers add to path so that scoop manifest can keep track of this instead
function ensure_install_dir_not_in_path($dir, $global) {
    $path = (env 'path' $global)

    $fixed, $removed = find_dir_or_subdir $path "$dir"
    if($removed) {
        $removed | ForEach-Object { "安装程序添加了 '$(friendly_path $_)' 到路径中. 删除."}
        env 'path' $global $fixed
    }

    if(!$global) {
        $fixed, $removed = find_dir_or_subdir (env 'path' $true) "$dir"
        if($removed) {
            $removed | ForEach-Object { warn "安装程序添加了 '$_' 到系统目录. 你也许需要手动移除它（需要管理员权限）."}
        }
    }
}

function find_dir_or_subdir($path, $dir) {
    $dir = $dir.trimend('\')
    $fixed = @()
    $removed = @()
    $path.split(';') | ForEach-Object {
        if($_) {
            if(($_ -eq $dir) -or ($_ -like "$dir\*")) { $removed += $_ }
            else { $fixed += $_ }
        }
    }
    return [string]::join(';', $fixed), $removed
}

function env_add_path($manifest, $dir, $global, $arch) {
    $env_add_path = arch_specific 'env_add_path' $manifest $arch
    $env_add_path | Where-Object { $_ } | ForEach-Object {
        $path_dir = Join-Path $dir $_

        if (!(is_in_dir $dir $path_dir)) {
            abort "在Manifest中发现错误: 添加到环境变量的目录env_add_path '$_' 位于App目录之外."
        }
        add_first_in_path $path_dir $global
    }
}

function env_rm_path($manifest, $dir, $global, $arch) {
    $env_add_path = arch_specific 'env_add_path' $manifest $arch
    $env_add_path | Where-Object { $_ } | ForEach-Object {
        $path_dir = Join-Path $dir $_

        remove_from_path $path_dir $global
    }
}

function env_set($manifest, $dir, $global, $arch) {
    $env_set = arch_specific 'env_set' $manifest $arch
    if ($env_set) {
        $env_set | Get-Member -Member NoteProperty | ForEach-Object {
            $name = $_.name;
            $val = format $env_set.$($_.name) @{ "dir" = $dir }
            env $name $global $val
            Set-Content env:\$name $val
        }
    }
}
function env_rm($manifest, $global, $arch) {
    $env_set = arch_specific 'env_set' $manifest $arch
    if ($env_set) {
        $env_set | Get-Member -Member NoteProperty | ForEach-Object {
            $name = $_.name
            env $name $global $null
            if (Test-Path env:\$name) { Remove-Item env:\$name }
        }
    }
}

function pre_install($manifest, $arch) {
    $pre_install = arch_specific 'pre_install' $manifest $arch
    if($pre_install) {
        write-output "运行安装前脚本 pre_install..."
        Invoke-Expression (@($pre_install) -join "`r`n")
    }
}

function post_install($manifest, $arch) {
    $post_install = arch_specific 'post_install' $manifest $arch
    if($post_install) {
        write-output "运行安装后脚本 post_install..."
        Invoke-Expression (@($post_install) -join "`r`n")
    }
}

function show_notes($manifest, $dir, $original_dir, $persist_dir) {
    if($manifest.notes) {
        write-output "Notes"
        write-output "-----"
        write-output (wraptext (substitute $manifest.notes @{ '$dir' = $dir; '$original_dir' = $original_dir; '$persist_dir' = $persist_dir}))
    }
}

function all_installed($apps, $global) {
    $apps | Where-Object {
        $app, $null, $null = parse_app $_
        installed $app $global
    }
}

# returns (uninstalled, installed)
function prune_installed($apps, $global) {
    $installed = @(all_installed $apps $global)

    $uninstalled = $apps | Where-Object { $installed -notcontains $_ }

    return @($uninstalled), @($installed)
}

# check whether the app failed to install
function failed($app, $global) {
    if (is_directory (appdir $app $global)) {
        return !(install_info $app (current_version $app $global) $global)
    } else {
        return $false
    }
}

function ensure_none_failed($apps, $global) {
    foreach($app in $apps) {
        if(failed $app $global) {
            abort "'$app' 之前曾安装失败. 请先卸载它再尝试 ('scoop uninstall $app')."
        }
    }
}

function show_suggestions($suggested) {
    $installed_apps = (installed_apps $true) + (installed_apps $false)

    foreach($app in $suggested.keys) {
        $features = $suggested[$app] | get-member -type noteproperty | ForEach-Object { $_.name }
        foreach($feature in $features) {
            $feature_suggestions = $suggested[$app].$feature

            $fulfilled = $false
            foreach($suggestion in $feature_suggestions) {
                $suggested_app, $bucket, $null = parse_app $suggestion

                if($installed_apps -contains $suggested_app) {
                    $fulfilled = $true;
                    break;
                }
            }

            if(!$fulfilled) {
                write-host "'$app' 建议你安装 '$([string]::join("' or '", $feature_suggestions))'."
            }
        }
    }
}

# Persistent data
function persist_def($persist) {
    if ($persist -is [Array]) {
        $source = $persist[0]
        $target = $persist[1]
    } else {
        $source = $persist
        $target = $null
    }

    if (!$target) {
        $target = $source
    }

    return $source, $target
}

function persist_data($manifest, $original_dir, $persist_dir) {
    $persist = $manifest.persist
    if($persist) {
        $persist_dir = ensure $persist_dir

        if ($persist -is [String]) {
            $persist = @($persist);
        }

        $persist | ForEach-Object {
            $source, $target = persist_def $_

            write-host "Persisting $source"

            $source = $source.TrimEnd("/").TrimEnd("\\")

            $source = fullpath "$dir\$source"
            $target = fullpath "$persist_dir\$target"

            # if we have had persist data in the store, just create link and go
            if (Test-Path $target) {
                # if there is also a source data, rename it (to keep a original backup)
                if (Test-Path $source) {
                    Move-Item -Force $source "$source.original"
                }
            # we don't have persist data in the store, move the source to target, then create link
            } elseif (Test-Path $source) {
                # ensure target parent folder exist
                ensure (Split-Path -Path $target) | Out-Null
                Move-Item $source $target
            # we don't have neither source nor target data! we need to crate an empty target,
            # but we can't make a judgement that the data should be a file or directory...
            # so we create a directory by default. to avoid this, use pre_install
            # to create the source file before persisting (DON'T use post_install)
            } else {
                $target = New-Object System.IO.DirectoryInfo($target)
                ensure $target | Out-Null
            }

            # create link
            if (is_directory $target) {
                # target is a directory, create junction
                & "$env:COMSPEC" /c "mklink /j `"$source`" `"$target`"" | out-null
                attrib $source +R /L
            } else {
                # target is a file, create hard link
                & "$env:COMSPEC" /c "mklink /h `"$source`" `"$target`"" | out-null
            }
        }
    }
}

function unlink_persist_data($dir) {
    # unlink all junction / hard link in the directory
    Get-ChildItem -Recurse $dir | ForEach-Object {
        $file = $_
        if ($null -ne $file.LinkType) {
            $filepath = $file.FullName
            # directory (junction)
            if ($file -is [System.IO.DirectoryInfo]) {
                # remove read-only attribute on the link
                attrib -R /L $filepath
                # remove the junction
                & "$env:COMSPEC" /c "rmdir /s /q `"$filepath`""
            } else {
                # remove the hard link
                & "$env:COMSPEC" /c "del `"$filepath`""
            }
        }
    }
}

# check whether write permission for Users usergroup is set to global persist dir, if not then set
function persist_permission($manifest, $global) {
    if($global -and $manifest.persist -and (is_admin)) {
        $path = persistdir $null $global
        $user = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-545'
        $target_rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user, 'Write', 'ObjectInherit', 'none', 'Allow')
        $acl = Get-Acl -Path $path
        $acl.SetAccessRule($target_rule)
        $acl | Set-Acl -Path $path
    }
}
