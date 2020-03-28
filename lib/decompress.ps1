function Test-7zipRequirement {
    [CmdletBinding(DefaultParameterSetName = "URL")]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "URL")]
        [String[]]
        $URL,
        [Parameter(Mandatory = $true, ParameterSetName = "File")]
        [String]
        $File
    )
    if ($URL) {
        if ((get_config 7ZIPEXTRACT_USE_EXTERNAL)) {
            return $false
        } else {
            return ($URL | Where-Object { Test-7zipRequirement -File $_ }).Count -gt 0
        }
    } else {
        return $File -match '\.((gz)|(tar)|(tgz)|(lzma)|(bz)|(bz2)|(7z)|(rar)|(iso)|(xz)|(lzh)|(nupkg))$'
    }
}

function Test-LessmsiRequirement {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory = $true)]
        [String[]]
        $URL
    )
    if ((get_config MSIEXTRACT_USE_LESSMSI)) {
        return ($URL | Where-Object { $_ -match '\.msi$' }).Count -gt 0
    } else {
        return $false
    }
}

function Expand-7zipArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $ExtractDir,
        [Parameter(ValueFromRemainingArguments = $true)]
        [String]
        $Switches,
        [ValidateSet("All", "Skip", "Rename")]
        [String]
        $Overwrite,
        [Switch]
        $Removal
    )
    if ((get_config 7ZIPEXTRACT_USE_EXTERNAL)) {
        try {
            $7zPath = (Get-Command '7z' -CommandType Application | Select-Object -First 1).Source
        } catch [System.Management.Automation.CommandNotFoundException] {
            abort "无法找到 7-Zip (7z.exe) ,但 '7ZIPEXTRACT_USE_EXTERNAL' 为 'true'!`n执行 'scoop config 7ZIPEXTRACT_USE_EXTERNAL false' 或者手动安装 7-Zip 并再次尝试."
        }
    } else {
        $7zPath = Get-HelperPath -Helper 7zip
    }
    $LogPath = "$(Split-Path $Path)\7zip.log"
    $ArgList = @('x', "`"$Path`"", "-o`"$DestinationPath`"", '-y')
    $IsTar = ((strip_ext $Path) -match '\.tar$') -or ($Path -match '\.t[abgpx]z2?$')
    if (!$IsTar -and $ExtractDir) {
        $ArgList += "-ir!`"$ExtractDir\*`""
    }
    if ($Switches) {
        $ArgList += (-split $Switches)
    }
    switch ($Overwrite) {
        "All" { $ArgList += "-aoa" }
        "Skip" { $ArgList += "-aos" }
        "Rename" { $ArgList += "-aou" }
    }
    $Status = Invoke-ExternalCommand $7zPath $ArgList -LogPath $LogPath
    if (!$Status) {
        abort "无法解压 $Path 中的文件.`nLog file:`n  $(friendly_path $LogPath)`n$(new_issue_msg $app $bucket '解压失败')"
    }
    if (!$IsTar -and $ExtractDir) {
        movedir "$DestinationPath\$ExtractDir" $DestinationPath | Out-Null
    }
    if (Test-Path $LogPath) {
        Remove-Item $LogPath -Force
    }
    if ($IsTar) {
        # Check for tar
        $Status = Invoke-ExternalCommand $7zPath @('l', "`"$Path`"") -LogPath $LogPath
        if ($Status) {
            $TarFile = (Get-Content -Path $LogPath)[-4] -replace '.{53}(.*)', '$1' # get inner tar file name
            Expand-7zipArchive -Path "$DestinationPath\$TarFile" -DestinationPath $DestinationPath -ExtractDir $ExtractDir -Removal
        } else {
            abort "无法获得 $Path 的文件列表.`n这不是一个受支持的7zip格式."
        }
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function Expand-MsiArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $ExtractDir,
        [Parameter(ValueFromRemainingArguments = $true)]
        [String]
        $Switches,
        [Switch]
        $Removal
    )
    $DestinationPath = $DestinationPath.TrimEnd("\")
    if ($ExtractDir) {
        $OriDestinationPath = $DestinationPath
        $DestinationPath = "$DestinationPath\_tmp"
    }
    if ((get_config MSIEXTRACT_USE_LESSMSI)) {
        $MsiPath = Get-HelperPath -Helper Lessmsi
        $ArgList = @('x', "`"$Path`"", "`"$DestinationPath\\`"")
    } else {
        $MsiPath = 'msiexec.exe'
        $ArgList = @('/a', "`"$Path`"", '/qn', "TARGETDIR=`"$DestinationPath\\SourceDir`"")
    }
    $LogPath = "$(Split-Path $Path)\msi.log"
    if ($Switches) {
        $ArgList += (-split $Switches)
    }
    $Status = Invoke-ExternalCommand $MsiPath $ArgList -LogPath $LogPath
    if (!$Status) {
        abort "无法解压 $Path.`nLog file:`n  $(friendly_path $LogPath)`n$(new_issue_msg $app $bucket '解压失败')"
    }
    if ($ExtractDir -and (Test-Path "$DestinationPath\SourceDir")) {
        movedir "$DestinationPath\SourceDir\$ExtractDir" $OriDestinationPath | Out-Null
        Remove-Item $DestinationPath -Recurse -Force
    } elseif ($ExtractDir) {
        movedir "$DestinationPath\$ExtractDir" $OriDestinationPath | Out-Null
        Remove-Item $DestinationPath -Recurse -Force
    } elseif (Test-Path "$DestinationPath\SourceDir") {
        movedir "$DestinationPath\SourceDir" $DestinationPath | Out-Null
    }
    if (($DestinationPath -ne (Split-Path $Path)) -and (Test-Path "$DestinationPath\$(fname $Path)")) {
        Remove-Item "$DestinationPath\$(fname $Path)" -Force
    }
    if (Test-Path $LogPath) {
        Remove-Item $LogPath -Force
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function Expand-InnoArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $ExtractDir,
        [Parameter(ValueFromRemainingArguments = $true)]
        [String]
        $Switches,
        [Switch]
        $Removal
    )
    $LogPath = "$(Split-Path $Path)\innounp.log"
    $ArgList = @('-x', "-d`"$DestinationPath`"", "`"$Path`"", '-y')
    switch -Regex ($ExtractDir) {
        "^[^{].*" { $ArgList += "-c{app}\$ExtractDir" }
        "^{.*" { $ArgList += "-c$ExtractDir" }
        Default { $ArgList += "-c{app}" }
    }
    if ($Switches) {
        $ArgList += (-split $Switches)
    }
    $Status = Invoke-ExternalCommand (Get-HelperPath -Helper Innounp) $ArgList -LogPath $LogPath
    if (!$Status) {
        abort "无法解压 $Path.`nLog file:`n  $(friendly_path $LogPath)`n$(new_issue_msg $app $bucket '解压失败')"
    }
    if (Test-Path $LogPath) {
        Remove-Item $LogPath -Force
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function Expand-ZipArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [String]
        $ExtractDir,
        [Switch]
        $Removal
    )
    if ($ExtractDir) {
        $OriDestinationPath = $DestinationPath
        $DestinationPath = "$DestinationPath\_tmp"
    }
    # All methods to unzip the file require .NET4.5+
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        try {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $DestinationPath)
        } catch [System.IO.PathTooLongException] {
            # try to fall back to 7zip if path is too long
            if (Test-HelperInstalled -Helper 7zip) {
                Expand-7zipArchive $Path $DestinationPath -Removal
                return
            } else {
                abort "Zip解压失败: Windows 无法处理这个zip压缩中过长的路径.`n运行 'scoop install 7zip' 并再次尝试."
            }
        } catch [System.IO.IOException] {
            if (Test-HelperInstalled -Helper 7zip) {
                Expand-7zipArchive $Path $DestinationPath -Removal
                return
            } else {
                abort "Zip解压失败: Windows 无法处理这个zip压缩中的文件名.`n运行 'scoop install 7zip' 并再次尝试."
            }
        } catch {
            abort "Zip解压失败: $_"
        }
    } else {
        # Use Expand-Archive to unzip in PowerShell 5+
        # Compatible with Pscx (https://github.com/Pscx/Pscx)
        Microsoft.PowerShell.Archive\Expand-Archive -Path $Path -DestinationPath $DestinationPath -Force
    }
    if ($ExtractDir) {
        movedir "$DestinationPath\$ExtractDir" $OriDestinationPath | Out-Null
        Remove-Item $DestinationPath -Recurse -Force
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function Expand-DarkArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [String]
        $Path,
        [Parameter(Position = 1)]
        [String]
        $DestinationPath = (Split-Path $Path),
        [Parameter(ValueFromRemainingArguments = $true)]
        [String]
        $Switches,
        [Switch]
        $Removal
    )
    $LogPath = "$(Split-Path $Path)\dark.log"
    $ArgList = @('-nologo', "-x `"$DestinationPath`"", "`"$Path`"")
    if ($Switches) {
        $ArgList += (-split $Switches)
    }
    $Status = Invoke-ExternalCommand (Get-HelperPath -Helper Dark) $ArgList -LogPath $LogPath
    if (!$Status) {
        abort "无法解压 $Path.`nLog file:`n  $(friendly_path $LogPath)`n$(new_issue_msg $app $bucket '解压失败')"
    }
    if (Test-Path $LogPath) {
        Remove-Item $LogPath -Force
    }
    if ($Removal) {
        # Remove original archive file
        Remove-Item $Path -Force
    }
}

function extract_7zip($path, $to, $removal) {
    Show-DeprecatedWarning $MyInvocation 'Expand-7zipArchive'
    Expand-7zipArchive -Path $path -DestinationPath $to -Removal:$removal @args
}

function extract_msi($path, $to, $removal) {
    Show-DeprecatedWarning $MyInvocation 'Expand-MsiArchive'
    Expand-MsiArchive -Path $path -DestinationPath $to -Removal:$removal
}

function unpack_inno($path, $to, $removal) {
    Show-DeprecatedWarning $MyInvocation 'Expand-InnoArchive'
    Expand-InnoArchive -Path $path -DestinationPath $to -Removal:$removal @args
}

function extract_zip($path, $to, $removal) {
    Show-DeprecatedWarning $MyInvocation 'Expand-ZipArchive'
    Expand-ZipArchive -Path $path -DestinationPath $to -Removal:$removal
}
