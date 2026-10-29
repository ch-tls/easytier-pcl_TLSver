<#
.SYNOPSIS
    构建 PCL 联机模块所需的 EasyTier Windows 可执行文件。

.DESCRIPTION
    在本机使用仓库锁定的 Rust 工具链（rust-toolchain.toml）构建
    easytier-core 与 easytier-cli，并把产物复制到 artifacts\<arch>\。

.NOTES
    不启用上游 Release 使用的 nightly `-Z build-std`，以获得可复现的本机构建。
#>
[CmdletBinding()]
param(
    [ValidateSet('x86_64', 'i686', 'arm64')]
    [string]$Arch = 'x86_64',

    # 上游 Release 默认启用 jemalloc；本机构建默认关闭，按需打开
    [switch]$Jemalloc
)

$ErrorActionPreference = 'Stop'

$targets = @{
    x86_64 = 'x86_64-pc-windows-msvc'
    i686   = 'i686-pc-windows-msvc'
    arm64  = 'aarch64-pc-windows-msvc'
}
$triple = $targets[$Arch]
$root = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw '未找到 cargo，请先安装 Rust 工具链（https://rustup.rs/）。'
}

Push-Location $root
try {
    if (Get-Command rustup -ErrorAction SilentlyContinue) {
        Write-Host "同步 Rust 工具链（rust-toolchain.toml）..."
        rustup show active-toolchain | Out-Null
        if ($Arch -ne 'x86_64') {
            Write-Host "添加目标平台 $triple ..."
            rustup target add $triple
        }
    }
    else {
        Write-Warning '未找到 rustup，将尝试使用当前默认工具链。'
    }

   $cargoArgs = @('build', '--release', '--package', 'easytier', '--target', $triple)
    if ($Jemalloc) { $cargoArgs += '--features', 'jemalloc' }

    Write-Host "cargo $($cargoArgs -join ' ')"
    & cargo @cargoArgs
    if ($LASTEXITCODE -ne 0) { throw "cargo 构建失败（退出码 $LASTEXITCODE）" }

    $releaseDir = Join-Path $root "target\$triple\release"
    $outDir = Join-Path $root "artifacts\$Arch"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    foreach ($name in 'easytier-core.exe', 'easytier-cli.exe') {
        $source = Join-Path $releaseDir $name
        if (-not (Test-Path $source)) { throw "未找到构建产物：$source" }
        Copy-Item $source $outDir -Force
    }

    Write-Host ''
    Write-Host "构建完成：$outDir" -ForegroundColor Green
    Get-ChildItem $outDir -File | Select-Object Name, @{ n = 'Size(MB)'; e = { [math]::Round($_.Length / 1MB, 2) } } | Format-Table -AutoSize
}
finally {
    Pop-Location
}
