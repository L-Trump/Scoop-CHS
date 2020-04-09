 foreach($file in Get-ChildItem -Path . -Filter *.ps1 -recurse)
 {
        Write-Host "正在处理文件 : $($file.FullName)"
        $fileContent = Get-Content -Path $file.FullName
        $fileContent | Out-File -Encoding oem -FilePath $file.FullName
 }
