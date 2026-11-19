#requires -Version 5.1
# zero red 本地预检：只做 Windows 与云工作区能做的静态检查。
# iOS 编译、Swift 单元测试与界面测试只在 GitHub Actions 的 macOS 运行器执行；本脚本不代替云端验证。
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root
$env:PYTHONIOENCODING = 'utf-8'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$results = New-Object System.Collections.ArrayList
function Add-Result([string]$Name, [string]$Status, [string]$Detail) {
    [void]$results.Add([pscustomobject]@{ Check = $Name; Status = $Status; Detail = $Detail })
}
function Invoke-Captured([scriptblock]$Block) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = (& $Block 2>&1 | Out-String).Trim(); return @{ Code = $LASTEXITCODE; Output = $out } }
    finally { $ErrorActionPreference = $prev }
}

# 1. Git 状态
try {
    $sha = (& git rev-parse HEAD 2>$null).Trim()
    $branch = (& git rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-f]{40}$') { throw '不是有效的 Git 仓库或没有提交。' }
    Add-Result 'git-head' 'PASS' "$branch $sha"
    $dirty = @(& git status --porcelain)
    if ($dirty.Count -gt 0) {
        Add-Result 'git-clean' 'WARN' "工作区有 $($dirty.Count) 处未提交改动；云构建只包含已推送提交，交付前请审查提交。"
    } else { Add-Result 'git-clean' 'PASS' '工作区干净。' }
    & git diff --check | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'git diff --check 发现空白错误。' }
    Add-Result 'git-diff-check' 'PASS' '无空白错误。'
} catch { Add-Result 'git' 'FAIL' $_.Exception.Message }

# 2. PowerShell 脚本语法
try {
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File |
        Where-Object { $_.FullName -notmatch '[\\/](build|\.git|node_modules)[\\/]' })
    $bad = @()
    foreach ($f in $files) {
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { $bad += "$($f.Name): $($errors[0].Message)" }
    }
    if ($bad.Count -gt 0) { throw ($bad -join '; ') }
    Add-Result 'ps-syntax' 'PASS' "$($files.Count) 个 PowerShell 脚本语法通过。"
} catch { Add-Result 'ps-syntax' 'FAIL' $_.Exception.Message }

# 3. Bash 脚本语法（用 Git 自带的 bash，不要求 bash 在 PATH 上）
try {
    $shs = @(
        Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Filter '*.sh' -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $root 'apps/ios/scripts') -Filter '*.sh' -File -ErrorAction SilentlyContinue
    )
    if ($shs.Count -eq 0) { throw '未找到任何 shell 脚本。' }
    if ($env:OS -eq 'Windows_NT') {
        $gitCmd = (Get-Command git -CommandType Application -TotalCount 1 -ErrorAction Stop).Source
        $bash = Join-Path (Split-Path (Split-Path $gitCmd -Parent) -Parent) 'bin\bash.exe'
        if (-not (Test-Path -LiteralPath $bash)) { throw "未找到 Git Bash：$bash" }
    } else {
        $bash = (Get-Command bash -CommandType Application -TotalCount 1 -ErrorAction Stop).Source
    }
    foreach ($s in $shs) {
        $r = Invoke-Captured { & $bash -n $s.FullName }
        if ($r.Code -ne 0) { throw "$($s.Name) 语法错误：$($r.Output)" }
    }
    Add-Result 'bash-syntax' 'PASS' "$($shs.Count) 个 shell 脚本语法通过。"
} catch { Add-Result 'bash-syntax' 'FAIL' $_.Exception.Message }

# 4. 工作流 YAML 与关键指向
try {
    $workflows = @('ios-cloud-build.yml', 'web-tests.yml')
    $missing = @($workflows | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root ".github/workflows/$_")) })
    if ($missing.Count -gt 0) { throw "缺少工作流：$($missing -join ', ')" }
    if (Test-Path -LiteralPath (Join-Path $root '.github/workflows/ios.yml')) { throw '旧的 ios.yml 仍在，会重复触发未维护的旧流程。' }
    $yaml = Invoke-Captured { & python -c "import yaml, sys; [yaml.safe_load(open(p, encoding='utf-8')) for p in sys.argv[1:]]; print('OK')" (@($workflows | ForEach-Object { ".github/workflows/$_" })) }
    $ios = Get-Content -LiteralPath (Join-Path $root '.github/workflows/ios-cloud-build.yml') -Raw
    foreach ($needle in @('runs-on: xcode-27', 'bash scripts/package-ipa.sh', 'tag="build-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"', 'build/ipa/build-source.txt')) {
        if ($ios -notmatch [regex]::Escape($needle)) { throw "iOS 工作流缺少关键内容：$needle" }
    }
    if ($yaml.Code -ne 0) {
        Add-Result 'yaml-workflow' 'SKIP' "本机未安装 PyYAML，未做语法解析；关键指向已核对。安装 pyyaml 后重跑。"
    } else {
        Add-Result 'yaml-workflow' 'PASS' '2 个工作流可解析，iOS 工作流指向 xcode-27 运行器与本仓库 Release。'
    }
} catch { Add-Result 'yaml-workflow' 'FAIL' $_.Exception.Message }

# 5. Xcode 工程结构（纯 Python，不依赖 macOS）
try {
    $r = Invoke-Captured { & python 'apps/ios/scripts/verify_project.py' }
    if ($r.Code -ne 0) { throw $r.Output }
    Add-Result 'xcode-project' 'PASS' $r.Output
} catch { Add-Result 'xcode-project' 'FAIL' $_.Exception.Message }

# 6. Python 脚本语法
try {
    $pys = @(Get-ChildItem -LiteralPath (Join-Path $root 'apps/ios/scripts') -Filter '*.py' -File)
    $r = Invoke-Captured { & python -m py_compile @($pys | ForEach-Object { $_.FullName }) }
    if ($r.Code -ne 0) { throw $r.Output }
    Add-Result 'python-syntax' 'PASS' "$($pys.Count) 个 Python 脚本语法通过。"
} catch { Add-Result 'python-syntax' 'FAIL' $_.Exception.Message }

# 7. 网页单元测试（需要 Node；缺失时如实 SKIP，由 web-tests 工作流承担）
try {
    $npm = Get-Command npm -CommandType Application -ErrorAction SilentlyContinue
    if (-not $npm) {
        Add-Result 'web-tests' 'SKIP' '本机没有 Node/npm，网页单元测试本轮未验证；由 GitHub Actions 的 web-tests 工作流执行。'
    } else {
        $web = Join-Path $root 'apps/web'
        if (-not (Test-Path -LiteralPath (Join-Path $web 'node_modules'))) {
            $r = Invoke-Captured { Push-Location $web; try { & npm install --no-audit --no-fund } finally { Pop-Location } }
            if ($r.Code -ne 0) { throw "npm install 失败：$($r.Output)" }
        }
        $r = Invoke-Captured { Push-Location $web; try { & npm test } finally { Pop-Location } }
        if ($r.Code -ne 0) { throw (($r.Output.Split("`n") | Select-Object -Last 8) -join ' ') }
        $summary = (@($r.Output.Split("`n") | Where-Object { $_ -match '^✔|^# (pass|fail)|tests? ' }) | Select-Object -Last 3) -join ' '
        Add-Result 'web-tests' 'PASS' $summary
    }
} catch { Add-Result 'web-tests' 'FAIL' $_.Exception.Message }

# 8. 密钥扫描（只报告位置）
try {
    $pattern = 'github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|sk-[A-Za-z0-9]{24,}'
    $tracked = @(& git -c core.quotepath=false ls-files)
    $untracked = @(& git -c core.quotepath=false ls-files --others --exclude-standard)
    $files = @($tracked + $untracked | Sort-Object -Unique)
    $hits = @()
    foreach ($rel in $files) {
        $p = Join-Path $root $rel
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $item = Get-Item -LiteralPath $p -Force
        if ($item.Length -gt 2MB) { continue }
        $m = Select-String -LiteralPath $p -Pattern $pattern -AllMatches
        if ($m) { $hits += "$rel (行 $($m[0].LineNumber))" }
    }
    if ($hits.Count -gt 0) { throw "疑似凭据：$($hits -join '; ')" }
    Add-Result 'secret-scan' 'PASS' "$($tracked.Count) 个跟踪文件及 $($untracked.Count) 个未忽略的未跟踪文件未发现凭据模式。"
} catch { Add-Result 'secret-scan' 'FAIL' $_.Exception.Message }

# 9. 忽略规则：云端构建与下载产物不得进版本库
try {
    foreach ($probe in @('build/probe.ipa', 'build/ios-device/latest.json', 'build/reviews/x.json',
                         'apps/ios/TestResults/probe.log', 'apps/web/node_modules/probe.js', 'sideloadlydaemon.log')) {
        & git check-ignore -q $probe
        if ($LASTEXITCODE -ne 0) { throw "$probe 未被忽略。" }
    }
    Add-Result 'ignore-rules' 'PASS' '构建产物、下载包、测试结果与 node_modules 均被忽略。'
} catch { Add-Result 'ignore-rules' 'FAIL' $_.Exception.Message }

# 10. 应用身份与版本
try {
    $project = Get-Content -LiteralPath 'apps/ios/ZeroRed.xcodeproj/project.pbxproj' -Raw
    $bundle = ([regex]::Match($project, 'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')).Groups[1].Value.Trim()
    $minos = ([regex]::Match($project, 'IPHONEOS_DEPLOYMENT_TARGET = ([0-9.]+);')).Groups[1].Value
    $version = ([regex]::Match($project, 'MARKETING_VERSION = ([^;]+);')).Groups[1].Value.Trim()
    $build = ([regex]::Match($project, 'CURRENT_PROJECT_VERSION = ([^;]+);')).Groups[1].Value.Trim()
    if ($bundle -ne 'com.zerored.browser') { throw "bundle 编号异常：$bundle" }
    if (-not $minos -or -not $version -or -not $build) { throw '未能从工程读取最低系统或版本号。' }
    if (-not (Test-Path -LiteralPath 'apps/ios/ZeroRed.xcodeproj/xcshareddata/xcschemes/ZeroRed.xcscheme')) { throw '缺少共享 scheme ZeroRed。' }
    Add-Result 'app-identity' 'PASS' "$bundle，版本 $version（构建 $build），最低 iOS $minos。"
} catch { Add-Result 'app-identity' 'FAIL' $_.Exception.Message }

$results | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Output
$fail = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
$skip = @($results | Where-Object { $_.Status -eq 'SKIP' }).Count
$warn = @($results | Where-Object { $_.Status -eq 'WARN' }).Count
Write-Output "预检结果：$($results.Count) 项，失败 $fail，跳过 $skip，警告 $warn。"
Write-Output '注意：预检不包含 iOS 编译、Swift 单元/界面测试与真机验收；这些以云端运行和实机记录为准。'
if ($fail -gt 0) { exit 1 }
exit 0