param([Parameter(Mandatory)][string]$ArtifactDirectory)
$ErrorActionPreference = 'Stop'
# 导入云端产物：必须证明包来自当前 HEAD 的提交，否则不更新默认安装包。
$source = (Resolve-Path -LiteralPath $ArtifactDirectory).Path
$sourceInfo = Join-Path $source 'build-source.txt'
if (-not (Test-Path -LiteralPath $sourceInfo)) { throw '产物缺少构建来源，未更新默认安装包。' }
$commitLines = @(Get-Content -LiteralPath $sourceInfo | Where-Object { $_ -match '^commit=[0-9a-f]{40}$' })
if ($commitLines.Count -ne 1) { throw '构建来源中的提交号无效。' }
$root = Split-Path $PSScriptRoot -Parent
$expectedCommit = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $expectedCommit -notmatch '^[0-9a-f]{40}$' -or $commitLines[0] -cne "commit=$expectedCommit") {
    throw '产物提交与当前项目 HEAD 不一致，未更新默认安装包。'
}
$manifest = Join-Path $source 'latest.json'
if (-not (Test-Path -LiteralPath $manifest)) { throw '产物缺少 latest.json 构建信息。' }
$metadata = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
if ($metadata.fileName -notmatch '^ZeroRed-[0-9.]+-[0-9]+-[0-9]{8}T[0-9]{6}Z-unsigned\.ipa$') {
    throw '构建信息中的文件名无效。'
}
$ipa = Join-Path $source $metadata.fileName
$firstCheck = & "$PSScriptRoot/Test-DeviceIpa.ps1" -IpaPath $ipa -MetadataPath $manifest
if (-not $?) { throw '安装包校验失败，未更新默认安装包。' }
$directory = Join-Path $root 'build/ios-device'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$destination = Join-Path $directory $metadata.fileName
if (Test-Path -LiteralPath $destination) {
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $metadata.sha256) {
        throw '同名安装包内容不同，未覆盖。'
    }
} else {
    Copy-Item -LiteralPath $ipa -Destination $destination
}
& "$PSScriptRoot/Test-DeviceIpa.ps1" -IpaPath $destination -MetadataPath $manifest | Out-Null
if (-not $?) { throw '复制后的安装包校验失败，未更新默认安装包。' }
Copy-Item -LiteralPath $manifest -Destination "$destination.json" -Force
$temporary = Join-Path $directory ('.latest-' + [guid]::NewGuid().ToString('N') + '.json')
Copy-Item -LiteralPath $manifest -Destination $temporary
Move-Item -LiteralPath $temporary -Destination (Join-Path $directory 'latest.json') -Force
Write-Output "已导入并校验：$destination"
Write-Output "版本 $($metadata.version)（构建 $($metadata.build)）；$($metadata.architecture) / $($metadata.platform) / iOS $($metadata.minimumOSVersion) 及以上；SHA256 $($metadata.sha256)"