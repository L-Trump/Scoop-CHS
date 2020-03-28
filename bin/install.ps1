#Requires -Version 5

# remote install:
#   Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')
$old_erroractionpreference = $erroractionpreference
$erroractionpreference = 'stop' # quit if anything goes wrong

if (($PSVersionTable.PSVersion.Major) -lt 5) {
    Write-Output "安装Scoop至少需要Powershell5及以上"
    Write-Output "升级 PowerShell: https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-windows-powershell"
    break
}

# show notification to change execution policy:
$allowedExecutionPolicy = @('Unrestricted', 'RemoteSigned', 'ByPass')
if ((Get-ExecutionPolicy).ToString() -notin $allowedExecutionPolicy) {
    Write-Output "PowerShell 需要组策略 [$($allowedExecutionPolicy -join ", ")] 的支持来安装 Scoop."
    Write-Output "例如将脚本运行安全策略设置到  'RemoteSigned' :"
    Write-Output "'Set-ExecutionPolicy RemoteSigned -scope CurrentUser'"
    Write-Output "或者完全开放脚本运行："
    Write-Output "'Set-ExecutionPolicy ByPass -scope CurrentUser'"
    break
}

if ([System.Enum]::GetNames([System.Net.SecurityProtocolType]) -notcontains 'Tls12') {
    Write-Output "Scoop 需要 .NET Framework 4.5"
    Write-Output "请先下载并安装它:"
    Write-Output "https://www.microsoft.com/net/download"
    break
}

# get core functions
$core_url = 'https://raw.githubusercontent.com/L-Trump/Scoop-CHS/utf8/lib/core.ps1'
Write-Output '配置中...'
Invoke-Expression (new-object net.webclient).downloadstring($core_url)

# prep
if (installed 'scoop') {
    write-host "Scoop 已安装在此计算机上，如需升级，执行:'scoop update'" -f red
    # don't abort if invoked with iex that would close the PS session
    if ($myinvocation.mycommand.commandtype -eq 'Script') { return } else { exit 1 }
}
$dir = ensure (versiondir 'scoop' 'current')

# download scoop zip
$zipurl = 'https://github.com/L-Trump/Scoop-CHS/archive/utf8.zip'
$zipfile = "$dir\scoop.zip"
Write-Output '下载 scoop...'
dl $zipurl $zipfile

Write-Output '解压中...'
Add-Type -Assembly "System.IO.Compression.FileSystem"
[IO.Compression.ZipFile]::ExtractToDirectory($zipfile, "$dir\_tmp")
Copy-Item "$dir\_tmp\*utf8\*" $dir -Recurse -Force
Remove-Item "$dir\_tmp", $zipfile -Recurse -Force

Write-Output '创建 shim...'
shim "$dir\bin\scoop.ps1" $false

# download main bucket
$dir = "$scoopdir\buckets\main"
$zipurl = 'https://github.com/ScoopInstaller/Main/archive/master.zip'
$zipfile = "$dir\main-bucket.zip"
Write-Output '下载主仓库（Bucket）...'
New-Item $dir -Type Directory -Force | Out-Null
dl $zipurl $zipfile

Write-Output '解压中...'
[IO.Compression.ZipFile]::ExtractToDirectory($zipfile, "$dir\_tmp")
Copy-Item "$dir\_tmp\*-master\*" $dir -Recurse -Force
Remove-Item "$dir\_tmp", $zipfile -Recurse -Force

ensure_robocopy_in_path
ensure_scoop_in_path

scoop config lastupdate ([System.DateTime]::Now.ToString('o'))
success 'Scoop 成功安装！！'

Write-Output "运行 'scoop help' 来获取帮助"

$erroractionpreference = $old_erroractionpreference # Reset $erroractionpreference to original value