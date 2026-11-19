#requires -Version 5.1
# zero red 一键交付：本地预检 → 推送 → 按当前提交触发 GitHub 云构建 → 跟踪 → 读取各步骤实际结论
# → 下载 Release 中的 IPA（校验 SHA256）→ 校验提交一致性与真机格式 → 更新安装入口 → 写交付收据。
# iOS 编译与测试只发生在 GitHub Actions 的 macOS 运行器；令牌取自本机 Git 凭据管理器，不落盘、不打印。
param(
    [switch]$RunUiTests,
    [switch]$SkipSimulatorRelease,
    [switch]$SkipPreflight,
    [string]$RunId = '',
    [int]$TimeoutMinutes = 95
)
$ErrorActionPreference = 'Stop'
$Owner = 'cresent630-glitch'
$Repo = 'zero-red'
$WorkflowFile = 'ios-cloud-build.yml'
$Api = 'https://api.github.com'
$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$receipt = [ordered]@{
    project = 'zero red'; startedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    repository = "$Owner/$Repo"; workflow = $WorkflowFile
}
function Save-Receipt([string]$Stage, [string]$ErrorMessage) {
    $receipt.stage = $Stage
    $receipt.finishedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    if ($ErrorMessage) { $receipt.error = $ErrorMessage }
    $dir = Join-Path $root 'build/reviews'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $name = 'delivery-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.json'
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dir $name) -Encoding UTF8
    Write-Output "交付收据：$(Join-Path $dir $name)"
}
function Get-GitHubToken {
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $cred = "protocol=https`nhost=github.com`n" | & git credential fill 2>$null
    $ErrorActionPreference = $prevEAP
    $line = @($cred | Select-String '^password=')
    if ($line.Count -ne 1) { throw '未从 Git 凭据管理器取得 github.com 令牌；请先完成一次 Git 登录。' }
    return $line[0].ToString().Substring(9)
}
function Invoke-GitHub([string]$Method, [string]$Url, $Body) {
    $headers = @{ Authorization = "Bearer $script:Token"; 'User-Agent' = 'zero-red-deliver'; Accept = 'application/vnd.github+json' }
    $params = @{ Method = $Method; Uri = $Url; Headers = $headers; UseBasicParsing = $true }
    if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 8); $params.ContentType = 'application/json; charset=utf-8' }
    return Invoke-RestMethod @params
}
function Get-StepState($Steps, [string]$Name) {
    $step = @($Steps | Where-Object { $_.name -eq $Name } | Select-Object -First 1)[0]
    if (-not $step) { return @{ State = 'missing'; Conclusion = 'missing' } }
    return @{ State = "$($step.status)/$($step.conclusion)"; Conclusion = $step.conclusion }
}

try {
    # 0. 安全护栏：只在本项目仓库内运行，避免误推到别的项目。
    $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $originUrl = (& git remote get-url origin 2>$null | Out-String).Trim()
    $code = $LASTEXITCODE; $ErrorActionPreference = $prevEAP
    if ($code -ne 0 -or $originUrl -notmatch "/$Repo(\.git)?$") {
        throw "origin 不是 $Owner/$Repo（当前：$originUrl）。为避免误操作其他项目，已中止。"
    }
    $script:deliveryMutex = New-Object System.Threading.Mutex($false, 'Local\ZeroRedDelivery')
    if (-not $script:deliveryMutex.WaitOne(0)) {
        throw '另一个一键交付进程正在运行，已中止以免同时写下载目录与安装入口。'
    }

    # 1. 本地预检
    if (-not $SkipPreflight) {
        Write-Output '== 本地预检 =='
        & "$PSScriptRoot/preflight.ps1"
        if ($LASTEXITCODE -ne 0) { throw '本地预检失败，已中止交付。' }
    }

    if ($RunId) {
        # 续跑模式：只跟踪已有运行，不重新推送或触发。
        $script:Token = Get-GitHubToken
        $sha = (& git rev-parse HEAD).Trim()
        $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
        $receipt.commit = $sha
        $receipt.branch = $branch
        $run = Invoke-GitHub 'Get' "$Api/repos/$Owner/$Repo/actions/runs/$RunId" $null
        $runUrl = $run.html_url
        $receipt.runId = $run.id
        $receipt.runUrl = $runUrl
        Write-Output "续跑跟踪已有运行：$runUrl（本地 HEAD $sha）"
    } else {
        # 2. 工作区必须干净：云构建只包含已推送提交
        $dirty = @(& git status --porcelain)
        if ($dirty.Count -gt 0) { throw '工作区有未提交改动。云构建只包含已推送提交；请先审查并提交（git status 查看）。' }
        $sha = (& git rev-parse HEAD).Trim()
        if ($sha -notmatch '^[0-9a-f]{40}$') { throw '无法取得本地 HEAD 提交号。' }
        $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
        Write-Output "== 推送 $branch $sha 到 $Owner/$Repo =="
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & git push origin "HEAD:refs/heads/$branch" 2>&1 | ForEach-Object { Write-Output "$_" }
        $code = $LASTEXITCODE; $ErrorActionPreference = $prevEAP
        if ($code -ne 0) { throw 'git push 失败。' }
        $prevEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & git fetch origin $branch 2>&1 | Out-Null
        $code = $LASTEXITCODE; $ErrorActionPreference = $prevEAP
        if ($code -ne 0) { throw 'git fetch 失败。' }
        $remoteSha = (& git rev-parse FETCH_HEAD).Trim()
        if ($remoteSha -cne $sha) { throw "远端提交 $remoteSha 与本地 $sha 不一致。" }
        $receipt.commit = $sha
        $receipt.branch = $branch

        # 3. 触发云构建
        $script:Token = Get-GitHubToken
        try {
            $meta = Invoke-GitHub 'Get' "$Api/repos/$Owner/$Repo" $null
            if ($meta.private) { Write-Output '注意：仓库当前仍是私有，本次运行会消耗私有仓库 Actions 额度。' }
        } catch {}
        $ui = 'false'; if ($RunUiTests) { $ui = 'true' }
        $sim = 'true'; if ($SkipSimulatorRelease) { $sim = 'false' }
        Write-Output "== 触发云构建（核心测试=开，界面测试=$ui，模拟器Release=$sim） =="
        $body = @{
            ref = $branch
            inputs = @{ run_unit_tests = 'true'; run_ui_tests = $ui; build_simulator_release = $sim }
            return_run_details = $true
        }
        $dispatch = Invoke-GitHub 'Post' "$Api/repos/$Owner/$Repo/actions/workflows/$WorkflowFile/dispatches" $body
        if ($dispatch.workflow_run_id -notmatch '^[1-9][0-9]*$' -or -not $dispatch.html_url) {
            throw 'GitHub 未返回本次运行编号。请在 Actions 核对提交后用 -RunId 续跑。'
        }
        $run = @{ id = $dispatch.workflow_run_id }
        $runUrl = $dispatch.html_url
        $receipt.runId = $dispatch.workflow_run_id
        $receipt.runUrl = $runUrl
        Write-Output "运行已创建：$runUrl"
    }

    # 4. 跟踪运行（同一时间一个运行，等待期间不重复触发）
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $last = ''
    while ($true) {
        if ((Get-Date) -gt $deadline) { throw "等待超过 $TimeoutMinutes 分钟，运行仍未结束：$runUrl" }
        Start-Sleep -Seconds 30
        $run = Invoke-GitHub 'Get' "$Api/repos/$Owner/$Repo/actions/runs/$($run.id)" $null
        $stepName = ''
        try {
            $jobs = Invoke-GitHub 'Get' "$Api/repos/$Owner/$Repo/actions/runs/$($run.id)/jobs" $null
            $active = @($jobs.jobs | ForEach-Object { $_.steps } | Where-Object { $_.status -eq 'in_progress' })
            if ($active.Count -gt 0) { $stepName = $active[0].name }
        } catch {}
        $line = "状态：$($run.status)$(if ($stepName) { "，步骤：$stepName" })"
        if ($line -ne $last) { Write-Output $line; $last = $line }
        if ($run.status -eq 'completed') { break }
    }
    $receipt.runAttempt = $run.run_attempt
    $receipt.conclusion = $run.conclusion
    $tag = "build-$($run.id)-$($run.run_attempt)"
    $receipt.releaseTag = $tag

    # 5. 读取各步骤实际结论：整体成功不代表测试步骤真的执行过（步骤可能被跳过）
    $jobs = Invoke-GitHub 'Get' "$Api/repos/$Owner/$Repo/actions/runs/$($run.id)/jobs" $null
    $allSteps = @($jobs.jobs | ForEach-Object { $_.steps } | Where-Object { $_ })
    $stepCore = Get-StepState $allSteps 'Run core tests'
    $stepUI = Get-StepState $allSteps 'Run UI tests'
    $stepRelease = Get-StepState $allSteps 'Build simulator Release'
    $stepIpa = Get-StepState $allSteps 'Build unsigned device IPA'
    $stepPublish = Get-StepState $allSteps 'Publish build release'
    $receipt.steps = [ordered]@{
        core = $stepCore.State
        ui = $stepUI.State
        simulatorRelease = $stepRelease.State
        ipa = $stepIpa.State
        publish = $stepPublish.State
    }

    # 6. 失败：尽力取回构建日志做诊断
    if ($run.conclusion -ne 'success') {
        Write-Output "云构建结论：$($run.conclusion)。尝试取回构建日志。"
        try {
            $rel = Invoke-GitHub 'Get' "$Api/repos/$Owner/$Repo/releases/tags/$tag" $null
            $logAsset = @($rel.assets | Where-Object { $_.name -eq 'ZeroRed-build-logs.zip' })
            if ($logAsset.Count -gt 0) {
                $dir = Join-Path $root "build/reviews/failed-$($run.id)"
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                $zip = Join-Path $dir 'ZeroRed-build-logs.zip'
                Invoke-WebRequest -Uri $logAsset[0].url -Headers @{ Authorization = "Bearer $script:Token"; Accept = 'application/octet-stream'; 'User-Agent' = 'zero-red-deliver' } -OutFile $zip -UseBasicParsing
                Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
                Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.log' | ForEach-Object {
                    Write-Output "--- $($_.Name) 末尾 ---"
                    Get-Content -LiteralPath $_.FullName -Tail 25
                }
                $receipt.logs = $dir
            }
        } catch { Write-Output "构建日志不可用：$($_.Exception.Message)" }
        Save-Receipt 'cloud-build-failed' "云构建结论 $($run.conclusion)：$runUrl"
        exit 1
    }
    Write-Output '云构建成功。'
    if ($stepCore.Conclusion -ne 'success') { throw '核心测试步骤未成功；跳过或未运行的测试不能记为通过。' }
    if ($stepIpa.Conclusion -ne 'success') { throw '真机 IPA 构建步骤未成功，未导入任何产物。' }
    if ($stepPublish.Conclusion -ne 'success') { throw 'Release 发布步骤未成功。' }
    $receipt.coreTests = 'cloud-success'
    $receipt.uiTests = if ($stepUI.Conclusion -eq 'success') { 'cloud-success' } else { "not-run ($($stepUI.Conclusion))" }
    $receipt.simulatorRelease = if ($stepRelease.Conclusion -eq 'success') { 'cloud-success' } else { "not-run ($($stepRelease.Conclusion))" }

    # 7. 下载 Release 产物并校验摘要
    $rel = Invoke-GitHub 'Get' "$Api/repos/$Owner/$Repo/releases/tags/$tag" $null
    $receipt.releaseUrl = $rel.html_url
    $dlDir = Join-Path $root "build/downloads/$tag"
    New-Item -ItemType Directory -Path $dlDir -Force | Out-Null
    $ipaZip = $null
    foreach ($asset in $rel.assets) {
        $target = Join-Path $dlDir $asset.name
        Write-Output "下载 $($asset.name)（$([math]::Round($asset.size/1KB,1)) KB）"
        Invoke-WebRequest -Uri $asset.url -Headers @{ Authorization = "Bearer $script:Token"; Accept = 'application/octet-stream'; 'User-Agent' = 'zero-red-deliver' } -OutFile $target -UseBasicParsing
        if ($asset.digest -and $asset.digest -match '^sha256:([0-9a-f]{64})$') {
            $expectedHash = $Matches[1]
            $actualHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -cne $expectedHash) { throw "下载产物的 SHA256 与 Release 记录不一致：$($asset.name)" }
        }
        if ($asset.name -eq 'ZeroRed-ipa.zip') { $ipaZip = $target }
    }
    if ($null -eq $ipaZip) { throw 'Release 缺少 ZeroRed-ipa.zip。' }
    $receipt.downloads = $dlDir

    # 8. 解压并校验导入（提交一致性 + SHA256 + 真机格式）
    $extract = Join-Path $dlDir 'extracted'
    Expand-Archive -LiteralPath $ipaZip -DestinationPath $extract -Force
    $ipaDir = @(Get-ChildItem -LiteralPath $extract -Recurse -Directory | Where-Object { $_.Name -eq 'ipa' -and (Test-Path (Join-Path $_.FullName 'build-source.txt')) })
    if ($ipaDir.Count -ne 1) { throw '解压产物中未找到唯一 ipa 目录。' }
    Write-Output '== 校验并导入 IPA =='
    & "$PSScriptRoot/import-github-ipa.ps1" -ArtifactDirectory $ipaDir[0].FullName
    if ($LASTEXITCODE -ne 0) { throw 'IPA 校验导入失败。' }
    $latest = Get-Content -LiteralPath (Join-Path $root 'build/ios-device/latest.json') -Raw | ConvertFrom-Json
    $receipt.ipa = [ordered]@{ fileName = $latest.fileName; sha256 = $latest.sha256; sizeBytes = $latest.sizeBytes; version = $latest.version; build = $latest.build }

    # 9. 安装入口验证（不启动 Sideloadly、不操作手机）
    Write-Output '== 安装入口验证 =='
    & "$PSScriptRoot/install-iphone.ps1" -ValidateOnly
    if ($LASTEXITCODE -ne 0) { throw '安装入口验证失败。' }

    # 10. 收据
    $receipt.deviceInstall = 'not-performed（需用户用 Sideloadly 签名安装）'
    $receipt.unverified = @('真机安装与信任', '相机/网页媒体实机表现', '人工视觉验收', '默认浏览器资格（需 Apple 授权）')
    Save-Receipt 'delivered' $null
    Write-Output ''
    Write-Output "交付完成：版本 $($latest.version)（构建 $($latest.build)），提交 $sha"
    Write-Output "运行：$runUrl"
    Write-Output "Release：$($rel.html_url)"
    Write-Output "安装包：$(Join-Path $root "build/ios-device/$($latest.fileName)")"
    Write-Output '下一步：连接 iPhone，双击“安装到iPhone.cmd”，在 Sideloadly 中签名安装。未签名 IPA 不等于已安装或真机验收通过。'
    exit 0
} catch {
    Write-Output "交付失败：$($_.Exception.Message)"
    Save-Receipt 'failed' $_.Exception.Message
    exit 1
}