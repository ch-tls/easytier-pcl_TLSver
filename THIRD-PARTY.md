# 第三方组件声明（随联机模块分发包一起分发）

联机模块的可执行文件来自 EasyTier（LGPL-3.0），其 Windows 构建还依赖以下第三方组件。
这些二进制来自上游 `easytier/third_party/<arch>/`，本分支不修改其内容。

| 文件 | 用途 | 许可 |
| --- | --- | --- |
| `wintun.dll` | Windows 虚拟网卡驱动（TUN） | Wintun 由 WireGuard 项目提供，遵循上游发布许可（GPL-2.0，附带官方使用例外说明） |
| `Packet.dll` | 抓包 / 重定向辅助库 | 由上游 vendored，具体许可以上游仓库为准 |
| `WinDivert64.sys` / `WinDivert32.sys` | 用户态网络包重定向驱动 | LGPL-3.0（WinDivert 项目） |

## 分发要求

- 打包时保留本文件与 `LICENSE`；
- 若上游 `third_party` 目录内附带了各自的许可文本，一并复制进分发包；
- 修改上游 vendored 二进制时，必须同时提供对应源码与修改说明（LGPL 要求）。

## 获取来源

- EasyTier: <https://github.com/EasyTier/EasyTier>
- Wintun: <https://www.wintun.net/>
- WinDivert: <https://github.com/basil00/WinDivert>
