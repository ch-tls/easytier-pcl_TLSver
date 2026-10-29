# easytier-pcl_TLSver

本仓库是 [EasyTier](https://github.com/EasyTier/EasyTier) 的 **LGPL 分支**，专供
[Plain Craft Launcher TLSver 社区修改版](https://github.com/ch-tls/Plain-Craft-Launcher-PCL-TLSver-Community)
的「联机」功能使用。

> **这不是官方 PCL 的组件。** 官方 [Meloong-Git/PCL](https://github.com/Meloong-Git/PCL) 与本仓库无关，
> 请勿将本仓库的构建产物用于官方 PCL；官方 PCL 的联机模块由其自身渠道分发。
>
> - 仓库地址：<https://github.com/ch-tls/easytier-pcl_TLSver>
> - 上游基线：`main` @ `c66076b8`（`nightly-1-gc66076b8`，版本 2.7.0，2026-10-29）
> - 许可：**LGPL-3.0**（见 [LICENSE](LICENSE)），本分支的所有修改同样以 LGPL-3.0 发布
>
> 命名说明：目录与仓库名中的 `TLSver` 表示该分支服务于 TLSver 社区修改版，
> 与 EasyTier 官方、PCL 官方均无隶属关系。

---

## 一、阶段 0 决策记录

### 决策 1：联机只走「自建节点链路」（原 B 方案）

不做官方链路的恢复，也不做双轨：

- **不使用** PCL 服务端下发的 `ServerConfig("Link")`；
- **不使用** `uptime.easytier.cn` 的节点发现与负载均衡；
- 房间的联通完全依赖用户在「设置 → 联机 → 自定义节点」里填写的 EasyTier 节点（房主与加入者必须填至少一个相同节点）。

落到 PCL 侧的语义是 `DiscoverNodeID = -2`（「必须设定自定义节点」），这条分支在现有代码里已经存在，只是目前走不到。

**放弃官方链路的理由**：节点服务地址在开发者本机已无法解析，且服务端配置下发依赖的 `ServerLoader` 在本项目里是空实现；自建节点链路不依赖任何外部服务，复活成本最低。

### 决策 2：模块版本策略

PCL 用整数比较模块版本（`LinkEasyTierVersion`），因此本分支沿用整数编码：

```
版本整数 = major * 10000 + minor * 100 + patch
例：2.7.0 → 20700
```

- 版本整数在构建时由 `scripts/package-module.ps1` 从 `easytier/Cargo.toml` 解析，写入包内的 `PCL-LINK-VERSION.json`；
- PCL 侧保存一份内置常量作为「期望版本」，并支持两个覆盖来源：设置项里手填的本地模块目录 > 内置常量；
- 若用户本地模块的版本 ≥ 期望版本，则跳过下载（方便测试新构建）。

### 决策 3：分发与打包

本分支自行构建并打包，产物布局对齐 PCL 现有解压逻辑（zip 内**唯一一个顶层目录**）：

```
easytier-module-x86_64-20700/
├── easytier-core.exe
├── easytier-cli.exe
├── wintun.dll
├── Packet.dll
├── WinDivert64.sys
├── LICENSE
├── THIRD-PARTY.md
└── PCL-LINK-VERSION.json
```

- 仅 Windows 参与打包（x86_64 优先，i686 / arm64 后续按需）；
- PCL 侧解压后会自行把 `easytier-core.exe` 重命名为 `联机模块.exe`、`easytier-cli.exe` 重命名为 `联机模块 CLI.exe`，因此包内**必须保持上游文件名**；
- 下载地址：本仓库的 GitHub Release（PCL 侧做成常量 + 设置项覆盖，并支持直接读取本地目录）。

### 决策 4：CLI 输出兼容策略（阶段 4 实施）

EasyTier 2.7.0 的 `easytier-cli peer -o json` 已改为 `{ node_info, peer_routes[] }` 的 protobuf 结构，而 PCL 期望扁平数组。由于本分支由我们维护，**优先在 CLI 侧新增 legacy 输出模式**，PCL 侧解析逻辑保持不变。

详见 [docs/pcl-link-cli-legacy.md](docs/pcl-link-cli-legacy.md)。

### 决策 5：合规

- 保留上游 [LICENSE](LICENSE)、版权声明与修改说明（本文件）；
- 修改后的源码随本仓库公开（LGPL 要求）；
- 打包产物中附带 `LICENSE` 与 `THIRD-PARTY.md`，说明 `wintun.dll`、`WinDivert*.sys`、`Packet.dll` 的第三方许可来源；
- PCL 侧「关于 → 特别鸣谢」已有 EasyTier 条目，README 会补充联机模块来源；
- PCL 与 easytier-core 是**独立进程**关系（通过命令行与本地 RPC 交互），不构成静态/动态链接，但源码与许可仍按 LGPL 公开。

---

## 二、构建

需要 Rust 工具链（仓库内 `rust-toolchain.toml` 锁定 `1.95`）、7-Zip，以及一次性的外部依赖准备。

```powershell
# 首次构建前：准备 protoc / LLVM(libclang) / VC-LTL / YY-Thunks
# 需要能访问 GitHub（本机实测需设置 HTTPS_PROXY，且 curl 需 --ssl-no-revoke）
$env:HTTPS_PROXY = 'http://127.0.0.1:7890'
.\scripts\prepare-deps.ps1

# 每次构建前加载环境
. .\scripts\env.generated.ps1

# 构建
.\scripts\build-windows.ps1              # x86_64
.\scripts\build-windows.ps1 -Arch i686   # 需要先 rustup target add
```

产物落在 `artifacts\<arch>\`。

### 已踩过的坑（脚本已自动处理）

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `LNK1104: 无法打开 lnk{...}.tmp` | `%TEMP%` 下 lib.exe 临时文件冲突 | 构建时把 TEMP 指向 `target\_tmp` |
| `Could not find protoc` | 缺少 protobuf 编译器 | `prepare-deps.ps1` 下载到 `target\protobuf`，用 `PROTOC` 指定 |
| `Unable to find libclang` | kcp-sys 用 bindgen 需要 LLVM | 下载 LLVM 并设置 `LIBCLANG_PATH` |
| `7z is needed to unpack libraries` | thunk-rs 需要 7-Zip | 把 7-Zip 加入 PATH |
| `Download libraries from ... VC-LTL-Binary.7z failed` | thunk-rs 内嵌 curl 不带代理 | 预先下载解压，用 `VC_LTL` / `YY_THUNKS` 指定 |
| TLS handshake failed | 本机 schannel 吊销检查不可用 | 下载统一加 `--ssl-no-revoke` |

> 说明：上游 Release 使用 nightly + `-Z build-std` 交叉编译。本分支在本机构建时使用 stable 工具链的默认目标，不启用 `build-std`，以获得可复现的本机产物；如需与上游完全一致的行为，请改用上游 workflow。

### 已验证的构建结果（2026-10-30）

```
easytier-core.exe   20.39 MB   easytier-core 2.7.0-c66076b8~
easytier-cli.exe     6.00 MB   easytier-cli 2.7.0-c66076b8~
```

已确认 PCL 依赖的 core 参数全部存在：`--network-name`、`--network-secret`、`--listeners`、
`--rpc-portal`、`--private-mode`、`--hostname`、`--tcp-whitelist`、`--udp-whitelist`、
`--port-forward`、`--latency-first`；CLI 的 `-p/--rpc-portal`、`-o/--output`、`peer` 均可用。

## 三、打包

```powershell
.\scripts\package-module.ps1              # x86_64，版本从 Cargo.toml 解析
.\scripts\package-module.ps1 -Arch i686
```

输出 `artifacts\easytier-module-<arch>-<ver>.zip` 并打印 SHA-256，供 PCL 侧填写校验值。

## 四、发布到 LGPL 仓库

```powershell
# 首次：把 upstream 改名，新增自己的 origin
git remote rename origin upstream
git remote add origin <新建的 LGPL 仓库地址>
git push -u origin main
```

之后上游同步：

```powershell
git fetch upstream
git merge upstream/main        # 或 rebase，注意 PCL 兼容补丁可能冲突
```

## 五、与 PCL 的接口约定（摘要）

| 约定 | 内容 |
| --- | --- |
| 进程 | `联机模块.exe`（= `easytier-core.exe`），参数见 PCL `PageLinkMain.InitLaunch` |
| 控制面 | `联机模块 CLI.exe -o json-legacy -p 127.0.0.1:<rpcPort> peer`（阶段 4 新增该输出模式） |
| 房间标识 | `--network-name` / `--network-secret` 由 PCL 生成，邀请码携带 |
| 节点 | `-p="<peer>"`，来自 PCL 的「自定义节点」设置 |
| 端口映射 | 加入者用 `--port-forward tcp|udp://<loopback>:<clientPort>/10.114.114.114:<serverPort>` |
| 版本 | 整数版本号，见决策 2 |
