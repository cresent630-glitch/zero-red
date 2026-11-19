param(
    [Parameter(Mandatory)][string]$IpaPath,
    [Parameter(Mandatory)][string]$MetadataPath
)
$ErrorActionPreference = 'Stop'
# 期望值以 Xcode 工程为准：bundle 编号与最低系统直接从 project.pbxproj 读取，避免两处漂移。
$expectedBundle = 'com.zerored.browser'
$expectedExecutable = 'ZeroRed'
$expectedAppDirectory = 'Payload/ZeroRed.app'
$expectedMinimumOS = '17.0'
$projectFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'apps/ios/ZeroRed.xcodeproj/project.pbxproj'
if (Test-Path -LiteralPath $projectFile) {
    $bundleMatch = Select-String -LiteralPath $projectFile -Pattern 'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);' | Select-Object -First 1
    if ($bundleMatch) { $expectedBundle = $bundleMatch.Matches[0].Groups[1].Value.Trim() }
    $osMatch = Select-String -LiteralPath $projectFile -Pattern 'IPHONEOS_DEPLOYMENT_TARGET = ([0-9]+(?:\.[0-9]+)+);' | Select-Object -First 1
    if ($osMatch) { $expectedMinimumOS = $osMatch.Matches[0].Groups[1].Value }
}
$versionParts = @($expectedMinimumOS.Split('.') | ForEach-Object { [int]$_ })
while ($versionParts.Count -lt 3) { $versionParts += 0 }
$expectedMinos = ([uint32]$versionParts[0] -shl 16) -bor ([uint32]$versionParts[1] -shl 8) -bor [uint32]$versionParts[2]
Add-Type -AssemblyName System.IO.Compression.FileSystem
$file = Get-Item -LiteralPath $IpaPath
$metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
if ($metadata.fileName -cne $file.Name -or $metadata.sha256 -notmatch '^[a-f0-9]{64}$' -or
    $metadata.platform -ne 'iPhoneOS' -or $metadata.architecture -ne 'arm64' -or
    $metadata.signingState -ne 'unsigned-needs-resigning' -or $file.Length -ne $metadata.sizeBytes) {
    throw '安装包信息与文件不一致，请重新生成真机 IPA。'
}
if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $metadata.sha256) {
    throw '安装包 SHA256 不匹配，请重新下载。'
}
$archive = [System.IO.Compression.ZipFile]::OpenRead($file.FullName)
try {
    if ($metadata.appDirectory -cne $expectedAppDirectory -or $metadata.executable -cne $expectedExecutable) {
        throw '不支持的 App 目录或可执行文件名。'
    }
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName -match '(^|/)\.\.(/|$)|\\|^/' -or
            ($entry.FullName -ne 'Payload/' -and $entry.FullName -ne "$expectedAppDirectory/" -and
             -not $entry.FullName.StartsWith("$expectedAppDirectory/", [StringComparison]::Ordinal))) {
            throw '安装包包含非预期路径。'
        }
    }
    $infoEntry = $archive.GetEntry("$expectedAppDirectory/Info.plist")
    $binaryEntry = $archive.GetEntry("$expectedAppDirectory/$expectedExecutable")
    if (-not $infoEntry -or -not $binaryEntry -or $infoEntry.Length -gt 1MB -or $binaryEntry.Length -gt 200MB) {
        throw '安装包缺少 App 信息或可执行文件。'
    }
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $settings.XmlResolver = $null
    $stream = $infoEntry.Open()
    $reader = [System.Xml.XmlReader]::Create($stream, $settings)
    try {
        $plist = New-Object System.Xml.XmlDocument
        $plist.XmlResolver = $null
        $plist.Load($reader)
    } finally { $reader.Dispose(); $stream.Dispose() }
    function Get-PlistValue([string]$Key) {
        $node = $plist.SelectSingleNode("/plist/dict/key[.='$Key']/following-sibling::*[1]")
        if (-not $node) { throw "安装包缺少字段：$Key" }
        return $node
    }
    $bundleID = (Get-PlistValue 'CFBundleIdentifier').InnerText
    $minimumOS = (Get-PlistValue 'MinimumOSVersion').InnerText
    if ($bundleID -cne $expectedBundle -or $bundleID -cne $metadata.bundleIdentifier -or
        $minimumOS -cne $expectedMinimumOS -or $minimumOS -cne $metadata.minimumOSVersion -or
        (Get-PlistValue 'CFBundleExecutable').InnerText -cne $expectedExecutable -or
        (Get-PlistValue 'CFBundleShortVersionString').InnerText -cne $metadata.version -or
        (Get-PlistValue 'CFBundleVersion').InnerText -cne $metadata.build -or
        (Get-PlistValue 'CFBundleSupportedPlatforms').InnerText -cne 'iPhoneOS' -or
        (Get-PlistValue 'UIDeviceFamily').InnerText -cne '1') {
        throw "IPA 不是本项目的 iPhone / iOS $expectedMinimumOS 及以上真机构建。"
    }
    $binaryStream = $binaryEntry.Open()
    $memory = New-Object System.IO.MemoryStream
    try { $binaryStream.CopyTo($memory); $bytes = $memory.ToArray() }
    finally { $binaryStream.Dispose(); $memory.Dispose() }
    if ($bytes.Length -lt 32 -or [BitConverter]::ToUInt32($bytes, 0) -ne 0xfeedfacfL -or
        [BitConverter]::ToUInt32($bytes, 4) -ne 0x0100000c -or [BitConverter]::ToUInt32($bytes, 12) -ne 2) {
        throw '可执行文件不是 64 位 ARM 真机 App。'
    }
    $numberOfCommands = [BitConverter]::ToUInt32($bytes, 16)
    $commandBytes = [BitConverter]::ToUInt32($bytes, 20)
    if ($numberOfCommands -gt 10000 -or $commandBytes -gt ($bytes.Length - 32)) { throw '无效的 Mach-O 命令表。' }
    $offset = 32
    $foundDevicePlatform = $false
    for ($index = 0; $index -lt $numberOfCommands; $index++) {
        if ($offset + 8 -gt 32 + $commandBytes) { throw 'Mach-O 命令表被截断。' }
        $command = [BitConverter]::ToUInt32($bytes, $offset)
        $size = [BitConverter]::ToUInt32($bytes, $offset + 4)
        if ($size -lt 8 -or $size -gt 32 + $commandBytes - $offset) { throw '无效的 Mach-O 命令长度。' }
        if ($command -eq 0x32) {
            if ($size -lt 24 -or [BitConverter]::ToUInt32($bytes, $offset + 8) -ne 2 -or
                [BitConverter]::ToUInt32($bytes, $offset + 12) -ne $expectedMinos) {
                throw "二进制不是 iOS $expectedMinimumOS 真机平台；不能安装模拟器产物。"
            }
            $foundDevicePlatform = $true
        }
        if ($command -eq 0x2c -and ($size -lt 24 -or [BitConverter]::ToUInt32($bytes, $offset + 16) -ne 0)) {
            throw '可执行文件已加密，不能作为本项目测试包。'
        }
        $offset += $size
    }
    if (-not $foundDevicePlatform) { throw '未找到真机平台信息。' }
    [pscustomobject]@{ Valid = $true; Path = $file.FullName; Version = $metadata.version;
        Build = $metadata.build; MinimumOSVersion = $minimumOS; Architecture = 'arm64'; Platform = 'iPhoneOS' }
} finally { $archive.Dispose() }