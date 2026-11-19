param([string]$ArtifactDirectory)
$ErrorActionPreference = 'Stop'
# 手动备用路径：在网页上触发云构建，下载 Release 里的 IPA，再导入本机安装入口。
# 不自动挑选旧包：导入时会校验产物内的提交号必须等于当前 HEAD。
if (-not $ArtifactDirectory) {
    Write-Host '正在打开 zero red 的云构建页面。填写当前 HEAD 的完整 40 位提交 SHA 并运行。'
    Write-Host '运行完成后到本仓库 Releases 下载 ZeroRed-ipa.zip（标签 build-<运行ID>-<尝试>），解压。'
    Write-Host '确认运行的提交与要交付的源码一致；不会自动使用旧安装包。'
    Start-Process 'https://github.com/cresent630-glitch/zero-red/actions/workflows/ios-cloud-build.yml'
    $ArtifactDirectory = Read-Host '请输入解压后的 ipa 文件夹路径（直接回车取消导入）'
    if ([string]::IsNullOrWhiteSpace($ArtifactDirectory)) { Write-Host '已取消导入；原安装包不变。'; return }
    $ArtifactDirectory = $ArtifactDirectory.Trim().Trim('"')
}
& "$PSScriptRoot/import-github-ipa.ps1" -ArtifactDirectory $ArtifactDirectory
if (-not $?) { throw 'GitHub 产物导入失败。' }