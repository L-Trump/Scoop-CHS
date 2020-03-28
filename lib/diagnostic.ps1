<#
Diagnostic tests.
Return $true if the test passed, otherwise $false.
Use 'warn' to highlight the issue, and follow up with the recommended actions to rectify.
#>
. "$PSScriptRoot\buckets.ps1"

function check_windows_defender($global) {
    $defender = get-service -name WinDefend -errorAction SilentlyContinue
    if($defender -and $defender.status) {
        if($defender.status -eq [system.serviceprocess.servicecontrollerstatus]::running) {
            if (Test-CommandAvailable Get-MpPreference) {
                $installPath = $scoopdir;
                if($global) { $installPath = $globaldir; }

                $exclusionPath = (Get-MpPreference).exclusionPath
                if(!($exclusionPath -contains $installPath)) {
                    warn "Windows Defender 可能会降低安装速度甚至打断安装."
                    write-host "  可以尝试运行:"
                    write-host "    sudo Add-MpPreference -ExclusionPath '$installPath'"
                    write-host "  (需要 'sudo' 命令. 运行 'scoop install sudo' 来获取.)"
                    return $false
                }
            }
        }
    }
    return $true
}

function check_main_bucket {
    if ((Get-LocalBucket) -notcontains 'main'){
        warn '主仓库未添加.'
        Write-Host "运行 'scoop bucket add main'"

        return $false
    }

    return $true
}

function check_long_paths {
    $key = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction SilentlyContinue -Name 'LongPathsEnabled'
    if (!$key -or ($key.LongPathsEnabled -eq 0)) {
        warn '长目录支持未启用.'
        Write-Host "你可以运行下面的命令来启用:"
        Write-Host "    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1"

        return $false
    }

    return $true
}

function check_envs_requirements {
    if ($null -eq $env:COMSPEC) {
        warn '$env:COMSPEC 环境变量未找到.'
        Write-Host "    在windows中环境变量通常指向 cmd.exe: '%SystemRoot%\system32\cmd.exe'."

        return $false
    }

    return $true
}
