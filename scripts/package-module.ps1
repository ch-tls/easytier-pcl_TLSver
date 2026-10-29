<#
.SYNOPSIS
    把构建产物打包成 PCL 可直接解压使用的联机模块 zip。

.DESCRIPTION
    包内布局与 PCL 的解压逻辑对齐：zip 里只有一个顶层目录，目录内包含
    easytier-core.exe、easytier-cli.exe、Windows 依赖 DLL/SYS、LICENSE、
    THIRD-PARTY.md 与 PCL-LINK-VERSION.json。

    版本整数编码：major * 10000 + minor * 100 + patch（2.7.0 -> 20700）。

.PARAMETER Arch
    目标架构，需与 scripts/build-windows.ps1 一致。

.PARAMETER Version
    覆盖版本整数（默认从 easytier/Cargo.toml 解析）。
#>
[CmdletBinding()]
param(
    [ValidateSet('x86_64', 'i686', 'arm64')]
    [string]$Arch = 'x86_64',

    [string]$Version = ''
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $root "artifacts\$Arch"
$thirdPartyDir = Join-Path $root "easytier\third_party\$Arch"
$cargoToml = Join-Path $root 'easytier\Cargo.toml'

if (-not (Test-Path $cargoToml)) { throw "未找到 $cargoToml" }
if (-not (Test-Path $sourceDir)) { throw "未找到构建产物目录 $sourceDir，请先运行 scripts\build-windows.ps1" }

# ---- 版本 ----
$upstreamVersion = (Select-String -Path $cargoToml -Pattern '^\s*version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"' |
    Select-Object -First 1).Matches.Groups[1].Value
if ([string]::IsNullOrWhiteSpace($upstreamVersion)) { throw '无法从 Cargo.toml 解析上游版本号。' }

if ([string]::IsNullOrWhiteSpace($Version)) {
    $parts = $upstreamVersion.Split('.')
    $Version = [string]([int]$parts[0] * 10000 + [int]$parts[1] * 100 + [int]$parts[2])
}
if ($Version -notmatch '^\d+$') { throw "版本整数格式不正确：$Version" }

# ---- git 信息 ----
$commit = (git -C $root rev-parse --short HEAD 2>$null)
$dirty = (git -C $root status --porcelain 2>$null) -ne $null
$builtAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')

# ---- 组装 ----
$stageRoot = Join-Path $root 'artifacts\stage'
$packageName = "easytier-module-$Arch-$Version"
$stageDir = Join-Path $stageRoot $packageName
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

foreach ($name in 'easytier-core.exe', 'easytier-cli.exe') {
    $source = Join-Path $sourceDir $name
    if (-not (Test-Path $source)) { throw "缺少可执行文件：$source" }
    Copy-Item $source $stageDir -Force
}

if (-not (Test-Path $thirdPartyDir)) { throw "缺少 Windows 依赖目录：$thirdPartyDir" }
Get-ChildItem $thirdPartyDir -File | Where-Object { $_.Extension -in '.dll', '.sys' } |
    ForEach-Object { Copy-Item $_.FullName $stageDir -Force }

foreach ($name in 'LICENSE', 'THIRD-PARTY.md') {
    $source = Join-Path $root $name
    if (Test-Path $source) { Copy-Item $source $stageDir -Force }
}

$meta = [ordered]@{
    name            = 'easytier-pcl_TLSver'
    purpose         = 'PCL 联机模块'
    upstreamRepo    = 'https://github.com/EasyTier/EasyTier'
    upstreamVersion = $upstreamVersion
    versionCode     = [int]$Version
    arch            = $Arch
    commit          = $commit
    dirty           = [bool]$dirty
    builtAt         = $builtAt
}
$meta | ConvertTo-Json | ForEach-Object {
    # 不带 BOM 的 UTF-8，避免 PCL 侧读取时把 BOM 当成 JSON 内容
    [IO.File]::WriteAllText((Join-Path $stageDir 'PCL-LINK-VERSION.json'), $_, (New-Object Text.UTF8Encoding($false)))
}

# ---- 压缩（单个顶层目录，PCL 解压后取第一个子目录） ----
$zipPath = Join-Path $root "artifacts\$packageName.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $stageDir -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item $stageDir -Recurse -Force

$hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host ''
Write-Host "打包完成：$zipPath" -ForegroundColor Green
Write-Host "版本整数：$Version（上游 $upstreamVersion，$Arch）"
Write-Host "SHA-256：$hash"
Write-Host ''
Write-Host 'PCL 侧需要填写：'
Write-Host ("  下载地址 = <发布地址>/" + (Split-Path $zipPath -Leaf))
Write-Host ("  期望版本 = " + $Version)
Write-Host ("  SHA-256  = " + $hash)
