#requires -v 3
param($cmd)

set-strictmode -off

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\git.ps1"
. "$psscriptroot\..\lib\buckets.ps1"
. (relpath '..\lib\commands')

reset_aliases

# TODO: remove this in a few weeks
if ((Get-LocalBucket) -notcontains 'main') {
    warn "Scoop主仓库已分离至 'https://github.com/ScoopInstaller/Main'"
    warn "你的Scoop中并不含有主仓库，为您自动添加中..."
    add_bucket 'main'
    exit
}

$commands = commands
if ('--version' -contains $cmd -or (!$cmd -and '-v' -contains $args)) {
    Push-Location $(versiondir 'scoop' 'current')
    write-host "Current Scoop version:"
    Invoke-Expression "git --no-pager log --oneline HEAD -n 1"
    write-host ""
    Pop-Location

    Get-LocalBucket | ForEach-Object {
        Push-Location (Find-BucketDirectory $_ -Root)
        if(test-path '.git') {
            write-host "'$_' bucket:"
            Invoke-Expression "git --no-pager log --oneline HEAD -n 1"
            write-host ""
        }
        Pop-Location
    }
}
elseif (@($null, '--help', '/?') -contains $cmd -or $args[0] -contains '-h') { exec 'help' $args }
elseif ($commands -contains $cmd) { exec $cmd $args }
else { "scoop: '$cmd' 不是一个Scoop命令. 查看帮助: 'scoop help'."; exit 1 }
