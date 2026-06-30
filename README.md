## 食用说明
### 安装脚本
*请确保已安装curl/wget* 

**以下脚本根据需要选择**
+ ss 2022 | snell | shadowtls 多功能管理菜单
```bash
bash <(curl -L -s menu.jinqians.com)
```
+ ss 2022 安装脚本
```bash
bash <(curl -L -s ss.jinqians.com)
```
+ 下载脚本，本地执行
```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/jinqians/ss-2022.sh/main/ss-2022.sh && chmod +x ss-2022.sh && ./ss-2022.sh
```

# Shadowsocks Rust + ShadowTLS 安装管理脚本

这是一个用于安装和管理 Shadowsocks Rust 和 ShadowTLS 的脚本集合。

## 功能特点

- 支持 Shadowsocks Rust 的完整管理
- 支持 ShadowTLS V3 的安装和配置
- 自动生成配置信息和分享链接
- 支持多种加密方式
- 支持多客户端配置格式

## 系统要求

- 支持的操作系统：Debian / Ubuntu / CentOS
- 需要 root 权限
- 需要 curl、wget、jq 等基础工具

## 主要功能

### Shadowsocks Rust 功能
1. 安装 Shadowsocks Rust
2. 更新 Shadowsocks Rust
3. 卸载 Shadowsocks Rust
4. 启动/停止/重启服务
5. 修改配置信息
6. 查看配置信息
7. 查看运行状态
8. 安装 ShadowTLS

### ShadowTLS 功能
1. 安装 ShadowTLS
2. 卸载 ShadowTLS
3. 查看配置信息

## 支持的加密方式

### Shadowsocks Rust 加密方式
- aes-128-gcm (默认)
- aes-256-gcm (推荐)
- chacha20-ietf-poly1305
- 2022-blake3-aes-128-gcm (推荐)
- 2022-blake3-aes-256-gcm (推荐)
- 2022-blake3-chacha20-poly1305
- 2022-blake3-chacha8-poly1305
- 其他更多加密方式...

## 客户端配置

脚本支持生成多种客户端配置格式：

### Surge 配置
自动生成 Surge 配置格式，包含：
- 服务器地址
- 端口
- 加密方式
- 密码
- ShadowTLS 配置

### Shadowrocket 配置
提供完整的 Shadowrocket 配置说明，包括：
- Shadowsocks 节点配置
- ShadowTLS 节点配置
- 自动生成的配置二维码

### Clash Meta 配置
生成完整的 Clash Meta 配置，包含：
- 代理配置
- ShadowTLS 插件配置

## 分享功能

- 生成 SS + ShadowTLS 合并链接
- 生成配置二维码
- 支持 IPv4/IPv6 地址

## 流量管理

<details>
   <summary>流量管理说明[展开查看]</summary>

### 功能说明
通过 iptables 对 SS2022 节点进行流量计数，支持设置月度流量上限，超限后自动暂停节点，每月指定日期自动重置。

### 计量原理
SS2022 监听在指定端口（TCP + UDP），流量管理通过在 iptables 中添加专用计数规则（`PSM_TRF` 链）统计该端口的进出字节数，不影响数据包的正常转发。超限时向 `INPUT` 链插入 DROP 规则，阻断新连接。

```
客户端 ──TCP/UDP──▶ iptables 计数 ──▶ ss-rust
                         │
                       超限时 DROP
```

### 使用方式
在管理菜单中选择 **9. 流量管理**，按提示安装并使用 PSM：

```bash
bash <(curl -fsSL https://psm.jinqians.com)
```

进入 PSM 后选择 **15. 流量管理** → **添加节点** → 选择 SS2022，设置流量上限（GB）和每月重置日。

### 自动检查定时器
首次配置后会提示安装 systemd 定时器（`psm-traffic.timer`），每分钟执行一次检查：
- 累计流量 ≥ 限额 → 自动暂停节点（TCP + UDP 同时阻断）
- 到达重置日 → 清零计数并恢复节点

手动查看定时器状态：
```bash
systemctl status psm-traffic.timer
```

### 注意事项
- 流量计数基于 iptables 字节计数器，**服务器重启后计数器归零**，但已累计的流量数据保存在 `/etc/psm/traffic/state.json` 中，下次计数从断点续计
- SS2022 同时使用 TCP 和 UDP，两种协议均会被计入流量并在超限时一同暂停
- 暂停节点仅阻断**新连接**，已建立的连接会在自然断开后失效
- 若系统使用 nftables，需确认 iptables 兼容层已启用（`iptables-legacy` 或 `iptables-nft`）

</details>

## 注意事项

1. 安装 ShadowTLS 之前需要先安装 Shadowsocks Rust
2. 配置文件会自动备份
3. 更新脚本前建议先备份配置
4. 请确保安装过程中网络连接稳定

## 问题排查

如果遇到问题，可以：
1. 查看服务状态：`systemctl status ss-rust`
2. 查看服务日志：`journalctl -xe --unit ss-rust`
3. 查看 ShadowTLS 状态：`systemctl status shadowtls`

## 更新日志

### v1.3.0
- 添加 ShadowTLS 支持
- 优化配置生成逻辑
- 改进错误处理

### v1.0.0
- 初始发布
- 支持 Shadowsocks Rust 基本功能

## 作者信息

- 作者：jinqians
- 网站：https://jinqians.com
