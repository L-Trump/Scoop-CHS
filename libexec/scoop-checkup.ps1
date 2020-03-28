# Usage: scoop checkup
# Summary: 检查潜在的问题
# Help: 执行一系列诊断测试以尝试识别可能存在的问题

. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\diagnostic.ps1"

$issues = 0

$issues += !(check_windows_defender $false)
$issues += !(check_windows_defender $true)
$issues += !(check_main_bucket)
$issues += !(check_long_paths)
$issues += !(check_envs_requirements)

if (!(Test-HelperInstalled -Helper 7zip)) {
    error "'7-Zip' 未安装! 大部分的解压操作需要它，请执行 'scoop install 7zip' 或 'scoop install 7zip-zstd'."
    $issues++
}

if (!(Test-HelperInstalled -Helper Innounp)) {
    error "'Inno Setup Unpacker' 未安装! 解压InnoSetup安装包需要它. 请执行 'scoop install innounp'."
    $issues++
}

if (!(Test-HelperInstalled -Helper Dark)) {
    error "'dark' 未安装! 解压 WiX Toolset 创建的安装包需要它. 请执行 'scoop install dark' 或 'scoop install wixtoolset'."
    $issues++
}

$globaldir = New-Object System.IO.DriveInfo($globaldir)
if($globaldir.DriveFormat -ne 'NTFS') {
    error "Scoop 需要一个 NTFS 分区来运行! 请指定 `$env:SCOOP_GLOBAL 或者 'globalPath' variable (位于'~/.config/scoop/config.json') 到另一个硬盘分区."
    $issues++
}

$scoopdir = New-Object System.IO.DriveInfo($scoopdir)
if($scoopdir.DriveFormat -ne 'NTFS') {
    error "Scoop 需要一个 NTFS 分区来运行! 请指定 `$env:SCOOP 或者 'rootPath' variable (位于'~/.config/scoop/config.json') 到另一个硬盘分区."
    $issues++
}

if($issues) {
    warn "发现潜在问题 $issues."
} else {
    success "没有发现问题!"
}

exit 0
