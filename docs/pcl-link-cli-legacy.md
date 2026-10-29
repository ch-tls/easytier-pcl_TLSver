# 阶段 4 具体方案：CLI 输出兼容（legacy JSON）

本文只描述方案与验收标准，不包含实现。相关背景见上一级 [PCL-LINK.md](../PCL-LINK.md)。

## 1. 目标

让 PCL 现有的 `peer` 解析逻辑继续可用，同时不阻碍后续跟随上游升级。

PCL 侧当前依赖的字段只有 5 个（见 `PageLinkMain.xaml.vb` 的 `Peer.New`）：

| 字段 | PCL 用途 |
| --- | --- |
| `hostname` | 显示名；以 `Client` 开头判为客户端 |
| `cost` | `== "Local"` 判为自己；包含 `relay` 判为走中继 |
| `ipv4` | `== 10.114.114.114` 判为房主 |
| `lat_ms` | 解析为 Double，用于 Ping 显示与「是否已连上」判定 |
| `nat_type` | 枚举名，映射到 PCL 的 `NATTypes` |

## 2. 现状差异

### 2.1 实测结果（2026-10-30，本分支 x86_64 构建）

用 `--no-tun` 启动 core 后执行：

```powershell
easytier-core.exe --network-name pcltest --network-secret pcltest123 --listeners 11010 `
    --rpc-portal 127.0.0.1:15899 --private-mode true --no-tun --hostname pcltest `
    -p tcp://public.easytier.cn:11010

easytier-cli.exe -p 127.0.0.1:15899 -o json peer
```

实际输出（仅自身节点，因沙箱内连不上公共节点）：

```json
[
  {
    "cidr": "",
    "ipv4": "",
    "hostname": "pcltest",
    "cost": "Local",
    "lat_ms": "-",
    "loss_rate": "-",
    "rx_bytes": "-",
    "tx_bytes": "-",
    "tunnel_proto": "-",
    "nat_type": "PortRestricted",
    "id": "3367778248",
    "version": "2.7.0-c66076b8~"
  }
]
```

**这是好消息**：`peer` 子命令的 JSON 输出**已经是扁平数组**，字段名与 PCL 期望的完全一致
（`hostname` / `ipv4` / `cost` / `lat_ms` / `nat_type`），与 2.x 早期版本相同。

也就是说：**上一版方案里基于 `{ nodeInfo, peerRoutes }` 的判断不成立**，那个嵌套结构是
`PeerListData` 的序列化形态，但 `handle_peer_list` 输出的是 `PeerTableItem` 的数组视图
（`impl From<PeerRoutePair> for PeerTableItem`），所以保持扁平。

### 2.2 仍需注意的差异

| 差异 | 影响 | 处理 |
| --- | --- | --- |
| `lat_ms` 可能为 `"-"`（无连接时） | PCL 用 `Double.TryParse` 解析，失败时 Ping 保持 0，不会崩溃 | 无需改动；PCL 侧可补充日志 |
| `ipv4` 在 no-tun 下为空串 | 房主判定原本依赖 `ipv4 == 10.114.114.114` | 启用 tun 并指定 `-i 10.114.114.114` 后正常；建议 PCL 侧同时用 `hostname` 前缀兜底 |
| `cost` 取值 | 实测 `"Local"`；非本机应为 `p2p` / `relay(n)` | 与 PCL 判断一致 |
| `nat_type` | 实测为 proto 枚举名（如 `PortRestricted`） | 与 PCL `NATTypes` 同名，可直接映射 |
| RPC 未监听 | 首次用配置文件启动时 `--rpc-portal` 未生效，CLI 报 `connection refused` | PCL 用命令行参数启动，实测正常 |

### 2.3 旧版嵌套结构（供参考）

早期分析中提到的 `{ nodeInfo, peerRoutes }` 结构确实存在于代码里：

```json
{
  "nodeInfo": { "peerId": 123, "hostname": "...", "stunInfo": { "udpNatType": "FullCone" } },
  "peerRoutes": [ { "route": { ... }, "peer": { ... } } ]
}
```

但它对应的是 `PeerListData`（`fetch_peer_list_data`），而不是 `peer` 子命令的输出路径。
若后续上游把 `handle_peer_list` 改成直接序列化 `PeerListData`，则本节结论失效，需要回到方案 A。

## 3. 方案对比

| 方案 | 做法 | 优点 | 缺点 |
| --- | --- | --- | --- |
| **A（推荐）** | 在 fork 的 CLI 里新增 `-o json-legacy`，由我们输出旧格式 | PCL 解析零改动；契约由我们掌握；上游升级不影响 | 需要维护一小段 CLI 补丁（约 30~50 行） |
| B | PCL 侧解析新嵌套结构 | 不改 CLI | PCL 侧大改；字段语义变化（NAT 只在 nodeInfo、房主判定失效）；上游再变就再改 |
| C | A + B 兜底 | 兼容官方 CLI | 两套解析都要维护，短期收益低 |

**建议：先做 A。** B 的兜底等确实需要支持「用户自行替换为官方 CLI」时再补。

## 4. 方案 A 设计

### 4.1 CLI 侧

- `OutputFormat` 增加一个变体（例如 `JsonLegacy`），仅对 `peer` 子命令生效；其他子命令遇到该值时报错提示。
- 新增 `PeerLegacyItem`，字段与旧版 CLI 对齐（PCL 只用前 5 个，其余保留便于排查）：

```json
[
  {
    "hostname": "Server-1a2b3c",
    "ipv4": "10.114.114.114",
    "cost": "Local",
    "lat_ms": "0.00",
    "nat_type": "FullCone",
    "loss_rate": "0.00",
    "rx_bytes": "0",
    "tx_bytes": "0",
    "tunnel_proto": "udp",
    "id": "123",
    "version": "2.7.0"
  },
  { "hostname": "Client-xxxxxx", "ipv4": "10.114.114.115", "cost": "p2p", "lat_ms": "12.34", "nat_type": "Unknown", "...": "..." }
]
```

### 4.2 字段推导规则

| 旧字段 | 新数据来源 | 规则 |
| --- | --- | --- |
| 自己那一条 | `node_info` | 始终是数组第 0 项，`cost` 固定 `"Local"` |
| `hostname` | `route.hostname`（自己用 `node_info.hostname`） | 原样输出 |
| `ipv4` | `route.ipv4_addr`（自己用 `node_info.ipv4_addr`） | 只取地址部分；取不到输出空串 |
| `cost` | `route.cost` | `1` → `"p2p"`，其余 → `"relay(<cost>)"`；自己固定 `"Local"` |
| `lat_ms` | `cost == 1` 时用 `PeerRoutePair::get_latency_ms()`，否则用 `route.path_latency` | 保留两位小数的字符串；取不到输出 `"0.00"` |
| `nat_type` | `stun_info.udp_nat_type` | 输出 proto 枚举名（与 PCL `NATTypes` 同名）；取不到输出 `"Unknown"` |

要点：

- `cost` 必须是 `Local` / `p2p` / `relay(n)` 这三种形态，因为 PCL 用 `= "Local"` 和 `ContainsIgnoreCase("relay")` 判断。
- `nat_type` 必须是合法枚举名，否则 PCL 会在 `Peer.New` 里抛异常并丢掉该节点。
- `lat_ms` 必须是可被 `Double.TryParse` 解析的十进制字符串。

### 4.3 实施步骤

1. `easytier/src/easytier-cli.rs`
   - `OutputFormat` 增加变体与 clap 名字（`json-legacy`）。
   - `handle_peer_list()` 中按输出格式分支：`json` → 保持上游行为；`json-legacy` → 组装 `Vec<PeerLegacyItem>` 后打印。
   - 新增 `impl From<PeerRoutePair> for PeerLegacyItem` 与「自己」的构造函数。
   - 其余子命令：若不支持 legacy，给出明确错误信息（避免静默输出错误格式）。
2. 单测（放在同文件 `#[cfg(test)]`，参考现有 CLI 测试风格）
   - self 条目 `cost == "Local"`；
   - p2p 条目 `cost == "p2p"`、`lat_ms` 可解析；
   - relay 条目 `cost` 以 `relay(` 开头；
   - `nat_type` 均为合法枚举名；
   - 输出是 JSON 数组且长度 = peer 数 + 1（含自己）。
3. 文档
   - 在本目录补充 CLI 输出示例；
   - `PCL-LINK.md` 的接口约定表里把命令改为 `-o json-legacy`。

## 5. PCL 侧改动（阶段 4 后半）

1. `PageLinkMain.RefreshPeer`
   - 恢复被注释的调用，改为实现好的进程输出辅助函数（`StartProcessAndGetOutput` 在上游 PCL 里存在，本仓库没有，需要自行实现：带超时、UTF-8 解码、`PrintLog` 开关）。
   - 命令改为 `联机模块 CLI.exe --output json-legacy -p 127.0.0.1:<rpcPort> peer`。
   - 容错：空输出、超时、非 JSON 各给独立日志；连续失败阈值沿用 4 次。
2. 房主判定
   - B 路线下不再依赖 `ipv4 == 10.114.114.114`（自建节点场景该固定 IP 仍由 PCL 启动参数指定，保留 `-i 10.114.114.114` 即可，因此可继续沿用），同时以 `hostname` 前缀 `Server-` 作为兜底。
3. 版本提示
   - 若 CLI 输出缺少 legacy 字段（用户手动换成了官方 CLI），提示「联机模块版本不匹配，请重新安装联机模块」，而不是直接崩溃。

## 6. 验收用例

| 用例 | 期望 |
| --- | --- |
| 单机双实例（房主 + 加入者）连同一自建节点 | 双方都出现 `cost=Local` 的自己与对方条目，Ping 合理，`nat_type` 合法 |
| 走中继 | 对方条目 `cost` 含 `relay` |
| 直连打洞成功 | 对方条目 `cost == "p2p"` |
| 节点不可达 | 连接超时，`Peers` 为空，UI 给出可读错误而非崩溃 |
| CLI 不存在 / 被杀 | 连续失败 4 次后 `Panic("获取节点信息失败")` |
| 用户使用官方 CLI | 提示版本不匹配，不影响已建立的连接（仅状态刷新失败） |

## 7. 风险与回滚

- **上游合并冲突**：改动集中在 `easytier-cli.rs`，冲突面约一段 `handle_peer_list` 分支 + 一个结构体，可控；每次同步 upstream 后跑一次单测即可。
- **上游再加字段**：legacy 输出由我们维护，只要旧字段仍能推导，PCL 不受影响。
- **回滚**：PCL 侧把参数切回 `-o json` 并同时回退解析（不推荐）；更稳妥的回滚是保留本补丁、只回退 PCL 侧对 legacy 参数的依赖。
