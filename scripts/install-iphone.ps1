param([switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
# 安装入口：只校验本地安装包并交给 Sideloadly；不代替 Apple 的签名、信任与开发者模式。
try {
    $root = Split-Path $PSScriptRoot -Parent
    $directory = Join-Path $root 'build/ios-device'
    $manifestPath = Join-Path $directory 'latest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw '还没有真机安装包，请先运行“一键交付.cmd”或“更新真机安装包.cmd”。' }
    $metadata = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($metadata.fileName -notmatch '^ZeroRed-[0-9.]+-[0-9]+-[0-9]{8}T[0-9]{6}Z-unsigned\.ipa$') {
        throw '默认安装包信息无效，请重新生成。'
    }
    $ipa = Join-Path $directory $metadata.fileName
    $validation = & "$PSScriptRoot/Test-DeviceIpa.ps1" -IpaPath $ipa -MetadataPath $manifestPath
    if ($ValidateOnly) { Write-Output ($validation | Out-String -Width 200).Trim(); return }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Sideloadly/sideloadly.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Sideloadly/sideloadly.exe'),
        (Join-Path $env:LOCALAPPDATA 'Sideloadly/sideloadly.exe')
    )
    $sideloadly = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $sideloadly) {
        Write-Host '未找到 Sideloadly。先安装本机安装器：https://sideloadly.io/' -ForegroundColor Yellow
        $bundled = Join-Path $root 'apps/ios/TestResults/device-install'
        if (Test-Path -LiteralPath $bundled) { Start-Process explorer.exe $bundled }
        Start-Process 'https://sideloadly.io/'
        throw 'Sideloadly 未安装，已打开安装器位置与官网；安装后重新双击此入口。'
    }
    Write-Host "zero red 真机安装准备已通过：arm64 / iPhoneOS / iOS $($validation.MinimumOSVersion) 及以上，版本 $($validation.Version)（构建 $($validation.Build)）。" -ForegroundColor Green
    Write-Host '1. 用支持数据传输的 USB 线连接 iPhone，解锁并点“信任此电脑”。'
    Write-Host '2. 在 Sideloadly 选择这台 iPhone，核对 Apple 账户，然后把 IPA 拖入窗口点击 Start。'
    Write-Host '3. 密码/验证码只在 Sideloadly 内填写；首次按手机提示开启开发者模式、信任开发者。'
    Write-Host '4. 免费签名 7 天有效；以后用同一 Apple 账户与 App 编号覆盖续签，续签前先导出 App 内备份。'
    Write-Host "本次安装包：$ipa"
    Write-Host '此入口不代替 Apple 验证，也不宣称安装成功。'
    # Sideloadly 会在工作目录写包含设备 UDID 的日志，放到临时目录避免脏工作区。
    Start-Process -FilePath $sideloadly -ArgumentList ('"{0}"' -f $ipa) -WorkingDirectory $env:TEMP -WindowStyle Normal | Out-Null
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}