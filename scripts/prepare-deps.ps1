<#
.SYNOPSIS
    一次性准备 EasyTier Windows 构建所需的外部依赖。

.DESCRIPTION
    easytier 的构建链会在不同阶段依赖以下外部资源，缺任何一个都会失败：

    1. protoc  —— easytier-proto 生成代码（上游会尝试从 GitHub 下载）
    2. libclang —— kcp-sys 通过 bindgen 生成绑定（必须有 LLVM）
    3. 7z       —— thunk-rs 解包 VC-LTL / YY-Thunks
    4. VC-LTL / YY-Thunks —— thunk-rs 链接 Win7 兼容层（上游用 curl 下载）

    本脚本把它们准备到 target/ 下的固定位置，并生成 env.ps1；
    构建前先 . .\scripts\env.ps1 即可。

.PARAMETER Force
    即使已存在也重新下载。
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'target'
$proxy = if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { '' }

$protocVersion = '26.0-rc1'
$vcLtlVersion = '5.2.2'
$yyThunksVersion = '1.1.7'
$llvmVersion = '19.1.7'

function Invoke-Download([string]$Url, [string]$OutFile) {
    if ((Test-Path $OutFile) -and -not $Force) {
        Write-Host "  已存在，跳过：$(Split-Path $OutFile -Leaf)"
        return
    }
    $args = @('-sSL', '--ssl-no-revoke', '--max-time', '900', '-o', $OutFile, '-w', '%{http_code}')
    # 本机 schannel 的吊销检查可能不可用；同时多数外网需要代理
    if ($proxy) { $args += @('--proxy', $proxy) }
    $code = & curl.exe @args $Url 2>&1
    if ($code -ne '200' -or -not (Test-Path $OutFile) -or (Get-Item $OutFile).Length -lt 10000) {
        throw "下载失败：$Url（http=$code）"
    }
    Write-Host "  完成：$(Split-Path $OutFile -Leaf)（$([math]::Round((Get-Item $OutFile).Length / 1MB, 1)) MB）"
}

function Get-SevenZip {
    foreach ($p in 'C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe') {
        if (Test-Path $p) { return $p }
    }
    throw '未找到 7z.exe，请先安装 7-Zip（https://www.7-zip.org/）。'
}

$sevenZip = Get-SevenZip

# ---- 1. protoc ----
$protocRoot = Join-Path $target 'protobuf'
if (-not (Test-Path (Join-Path $protocRoot 'bin\protoc.exe')) -or $Force) {
    Write-Host '[1/4] 准备 protoc ...'
    New-Item -ItemType Directory -Force -Path $protocRoot | Out-Null
    $zip = Join-Path $target 'protoc.zip'
    Invoke-Download "https://github.com/protocolbuffers/protobuf/releases/download/v26.0-rc1/protoc-$protocVersion-win64.zip" $zip
    Expand-Archive -Path $zip -DestinationPath $protocRoot -Force
}
else { Write-Host '[1/4] protoc 已就绪' }

# ---- 2. LLVM / libclang ----
$llvmBin = Join-Path $target 'llvm\extracted\bin'
if (-not (Test-Path (Join-Path $llvmBin 'libclang.dll')) -or $Force) {
    Write-Host '[2/4] 准备 LLVM（体积较大，约 336 MB）...'
    $llvmDir = Join-Path $target 'llvm'
    New-Item -ItemType Directory -Force -Path $llvmDir | Out-Null
    $installer = Join-Path $llvmDir "LLVM-$llvmVersion-win64.exe"
    Invoke-Download "https://github.com/llvm/llvm-project/releases/download/llvmorg-$llvmVersion/LLVM-$llvmVersion-win64.exe" $installer
    $extract = Join-Path $llvmDir 'extracted'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    & $sevenZip x $installer "-o$extract" -y *> $null
    if (-not (Test-Path (Join-Path $llvmBin 'libclang.dll'))) { throw 'LLVM 解包后未找到 libclang.dll。' }
}
else { Write-Host '[2/4] libclang 已就绪' }

# ---- 3. VC-LTL ----
$vcLtlDir = Join-Path $target "thunk-cache\VC-LTL-$vcLtlVersion"
if (-not (Test-Path (Join-Path $vcLtlDir 'TargetPlatform')) -or $Force) {
    Write-Host '[3/4] 准备 VC-LTL ...'
    $cache = Join-Path $target 'thunk-cache'
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    $archive = Join-Path $cache 'VC-LTL-Binary.7z'
    Invoke-Download "https://github.com/Chuyu-Team/VC-LTL5/releases/download/v$vcLtlVersion/VC-LTL-Binary.7z" $archive
    if (Test-Path $vcLtlDir) { Remove-Item $vcLtlDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $vcLtlDir | Out-Null
    & $sevenZip x $archive "-o$vcLtlDir" -y *> $null
}
else { Write-Host '[3/4] VC-LTL 已就绪' }

# ---- 4. YY-Thunks ----
$yyDir = Join-Path $target "thunk-cache\YY-Thunks-$yyThunksVersion"
if (-not (Test-Path (Join-Path $yyDir 'objs')) -or $Force) {
    Write-Host '[4/4] 准备 YY-Thunks ...'
    $cache = Join-Path $target 'thunk-cache'
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    $zip = Join-Path $cache 'YY-Thunks-Objs.zip'
    Invoke-Download "https://github.com/Chuyu-Team/YY-Thunks/releases/download/v$yyThunksVersion/YY-Thunks-Objs.zip" $zip
    if (Test-Path $yyDir) { Remove-Item $yyDir -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $yyDir -Force
}
else { Write-Host '[4/4] YY-Thunks 已就绪' }

# ---- 生成环境脚本 ----
$envFile = Join-Path $PSScriptRoot 'env.generated.ps1'
$lines = @(
    '# 由 scripts\prepare-deps.ps1 生成，请勿手工修改',
    "`$env:RUSTUP_TOOLCHAIN = '1.95-x86_64-pc-windows-msvc'",
    "`$env:LIBCLANG_PATH = '$(Join-Path $llvmBin '')'",
    "`$env:PROTOC = '$(Join-Path $protocRoot 'bin\protoc.exe')'",
    "`$env:PROTOC_INCLUDE = '$(Join-Path $protocRoot 'include')'",
    "`$env:VC_LTL = '$(Join-Path $vcLtlDir '')'",
    "`$env:YY_THUNKS = '$(Join-Path $yyDir '')'"
)
# 7-Zip 与 LLVM 的 bin 需要进入 PATH；TEMP 用仓库内短路径，避免 lib.exe 临时文件冲突
$pathPrefix = "$(Split-Path $sevenZip -Parent);$(Join-Path $llvmBin '')"
$lines += "`$env:PATH = '$pathPrefix;' + `$env:PATH"
$lines += "`$_tmp = Join-Path '$(Join-Path $target '_tmp')' ''"
$lines += "New-Item -ItemType Directory -Force -Path `$_tmp | Out-Null"
$lines += "`$env:TEMP = `$_tmp"
$lines += "`$env:TMP = `$_tmp"
[IO.File]::WriteAllLines($envFile, $lines, (New-Object Text.UTF8Encoding($true)))

Write-Host ''
Write-Host "环境已就绪：$envFile" -ForegroundColor Green
Write-Host '构建前先加载： . .\scripts\env.generated.ps1'
