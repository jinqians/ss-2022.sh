# 更新日志

## v4.3（2026-07-18）

menu.sh 3.4 → 4.3：与 snell 项目的 menu.sh（v4.2）合并功能，两个仓库统一为同一份文件、同一版本号。

### menu.sh 合并回 snell 项目 menu.sh（v4.2）中被删减的功能
- 新增 `close_port()` / `close_nftables_port()` / `save_nftables_rules()`：卸载时自动清理 ufw / iptables / nftables 中放行的端口规则。
- `uninstall_snell()` 补全：卸载前先停止并删除依赖 Snell 后端的 `shadowtls-snell-*` 服务；清理 `snell.socket`、`snell-netns` 服务及 `snell-netns-setup.sh`；各端口同步关闭防火墙；无其余 ShadowTLS 服务时顺带删除 `shadow-tls` 二进制。修复原实现中 `${service_name}` 未定义导致主服务文件删不掉的问题。
- `uninstall_shadowtls()` 补全：从 service 文件解析 `--listen` 端口并关闭防火墙。
- `uninstall_ss_rust()` 增强（menu.sh 独有）：清理 v3.3 引入的多端口节点服务（`ss-rust-<端口>`），并关闭主端口及各多端口的防火墙规则。
- 定义 `SYSTEMD_DIR=/etc/systemd/system`（此前被引用但从未定义）。
- 保留 ss-2022 版独有功能：中国大陆屏蔽管理（选项 10）、VLESS Reality 由 PSM 提供。

## v3.4（2026-07-18）

### 修复：开启 obfs 混淆后节点连接失败
- 根因是 shadowsocks-rust 已知 bug（[issue #694](https://github.com/shadowsocks/shadowsocks-rust/issues/694)）：配置 `server` 为 `::`（双栈）且启用 obfs 插件时，ss-rust 只监听 IPv6、完全不监听 IPv4，导致 IPv4 客户端全部连不上。
- `get_ss_listen_addr()`：启用 obfs 插件且机器有 IPv4 时，监听地址强制用 `0.0.0.0`，规避该 bug（纯 IPv6 机器仍用 `::`）。
- 分享链接补上 `obfs-host`（http 模式的 Host 头 / tls 模式的 SNI），提升客户端兼容性；Surge 配置同步输出 `obfs-host`。
- 抽出 `build_plugin_param()` 统一生成插件参数，修复多端口额外节点的分享链接此前不带 obfs 参数的问题。

## v3.3（2026-07-18）

ss-2022.sh 1.7 → 1.8，menu.sh 3.2 → 3.3

### #13 ShadowTLS 默认监听 IPv6 导致不通
- `shadowtls.sh`：新增 `get_listen_address()`，机器有 IPv4 地址时监听 `0.0.0.0`（此前硬编码 `::0`，在某些IDC环境不接受 IPv4 连接），纯 IPv6 机器仍监听 `::0`。
- `shadowtls.sh` / `ss-2022.sh`：所有从 service 文件解析 ShadowTLS 端口的地方改为兼容任意监听地址（`::0` / `0.0.0.0` / 手动修改过的地址），解决"自行修改 service 文件后提示配置文件不完整或已损坏"的问题。
- `shadowtls.sh` / `menu.sh`：snell 配置 `listen` 行解析同样改为容错格式。
- 注意：双栈机器现在默认只监听 IPv4；如需 IPv6 入口，手动把 service 中 `--listen` 改为 `[::]:端口` 即可，脚本能正常解析。

### #12 创建多个 ss 节点
- `ss-2022.sh` 主菜单新增「11. 多端口管理」：新增/查看/删除端口节点。
- 每个额外端口使用独立配置（`/etc/ss-rust/ports/<端口>.json`）和独立 systemd 服务（`ss-rust-<端口>`），互不影响；沿用主配置的加密方式/TFO/DNS/插件，密码独立。
- 卸载 Shadowsocks Rust 时自动清理所有额外节点服务。

### #11 ss 增加 obfs 配置
- `ss-2022.sh` 安装流程和「修改配置」菜单新增混淆插件选项：simple-obfs（http/tls）。
- Debian/Ubuntu 自动 `apt install simple-obfs`；RHEL 系官方源无此包，会提示自行编译并自动跳过。
- 查看配置时输出带 `plugin` 参数的 SIP002 分享链接及 Surge `obfs=` 参数。

### #10 AlmaLinux 安装问题
- `detect_os()` 改为优先读取 `/etc/os-release`，识别 AlmaLinux/Rocky/RHEL/Fedora/Anolis 等（含 `ID_LIKE` 兜底）。
- RHEL 系使用 `dnf`（无则 `yum`）安装依赖，自动启用 EPEL（qrencode 需要）。
- 防火墙支持 firewalld（RHEL 系默认）；firewalld 激活时跳过 iptables 直改，避免规则冲突。
- `service iptables save` 失败不再中断脚本（RHEL 系默认无 iptables-services）。
- `shadowtls.sh` 依赖安装同样兼容 dnf/yum，并修复了 `install_requirements` 从未被调用的问题。

### #1 安装后显示未安装 / 自定义密码启动失败
- 密码校验覆盖全部 2022-blake3 系列：`aes-128-gcm` 要求 16 字节、其余要求 32 字节的 Base64 密钥（此前 128-gcm 无校验，手动输入短密码会导致服务启动失败）。
- 不合规时循环重新输入（原实现为递归），并提示可回车自动生成。
- （时区 `cp` 报错导致安装中断的问题此前版本已修复。）

### #4 service 文件加入环境变量
- v3.2 已包含 `Environment=MONOIO_FORCE_LEGACY_DRIVER=1`（shadowtls.sh service 模板），本次仅确认。

### 新增：强制时间同步
- SS2022（2022-blake3 系列）协议校验时间戳，服务器与客户端时间误差超过 30 秒无法连接；此前脚本只设置时区、不同步时钟。
- 新增 `ensure_time_sync()`（安装依赖时自动执行）：已有 NTP 服务在运行则跳过 → 优先启用 systemd-timesyncd → 回退安装 chrony（自动适配 Debian/RHEL 服务名差异）；全部失败时明确警告用户手动配置。

### 其他修复
- `write_config` 原写法在启用自定义 DNS 时会生成非法 JSON，改用 `jq` 生成（同时保证特殊字符转义正确）。
- 「修改全部配置」原先密码在加密方式之前设置，导致按旧加密方式校验密码，已调整顺序。
- `${Success}` 变量未定义导致安装成功提示缺少前缀，已补充定义。
- ss-rust 主配置监听地址：无 IPv6 协议栈的机器自动用 `0.0.0.0` 代替 `::`。
