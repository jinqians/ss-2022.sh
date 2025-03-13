# Shadowsocks Rust 管理脚本

这是一个用于管理 Shadowsocks Rust 服务器的 Shell 脚本，提供了简单的命令行界面来安装、配置和管理 Shadowsocks Rust。本脚本仅使用官方源进行安装，确保最新版本和安全性。

## 功能特性

- 自动安装和配置 Shadowsocks Rust
- 支持多种加密方式，包括 AEAD 2022 加密
- 自动生成安全的随机密码
- 支持 IPv4/IPv6 双栈
- TCP Fast Open (TFO) 支持
- 自定义 DNS 服务器配置
- 自动生成 SS URL 和二维码
- 支持 Surge 配置格式
- 系统服务集成（systemd）
- 防火墙自动配置

## 支持的加密方式

### 标准加密
- aes-128-gcm (默认)
- aes-256-gcm
- chacha20-ietf-poly1305
- aes-128-cfb
- aes-256-cfb
- aes-256-ctr
- camellia-256-cfb
- chacha20-ietf

### AEAD 2022 加密（需要 v1.15.0 及以上版本）
- 2022-blake3-aes-128-gcm
- 2022-blake3-aes-256-gcm
- 2022-blake3-chacha20-poly1305
- 2022-blake3-chacha8-poly1305

## 系统要求

- 支持的操作系统：CentOS、Debian、Ubuntu
- 需要 ROOT 权限
- 支持的架构：x86_64、aarch64、armv7

## 安装方法

```bash
wget --no-check-certificate -O ss-2022.sh https://raw.githubusercontent.com/jinqians/ss-2022.sh/refs/heads/main/ss-2022.sh
chmod +x ss-2022.sh
./ss-2022.sh
```

## 使用说明

运行脚本后，您将看到以下菜单选项：

1. 安装 Shadowsocks Rust
2. 更新 Shadowsocks Rust
3. 卸载 Shadowsocks Rust
4. 启动 Shadowsocks Rust
5. 停止 Shadowsocks Rust
6. 重启 Shadowsocks Rust
7. 设置 配置信息
8. 查看 配置信息
9. 查看 运行状态
10. 退出脚本

## 配置说明

安装过程中，您可以配置以下选项：

- 端口：自动生成随机端口或手动指定（1-65535）
- 密码：自动生成随机密码或手动指定
- 加密方式：支持多种加密算法
- TFO（TCP Fast Open）：可选启用或禁用
- DNS：使用系统默认DNS或自定义DNS服务器

## 注意事项

1. 使用 AEAD 2022 加密方式时，密码必须是 Base64 编码格式
2. 某些加密方式（如 2022-blake3-aes-256-gcm）需要32字节密钥
3. 请确保您的系统防火墙允许所选端口的 TCP 和 UDP 流量
4. 本脚本仅从 Shadowsocks Rust 官方源获取程序，确保安全性

## 服务管理

### 启动服务
```bash
systemctl start ss-rust
```

### 停止服务
```bash
systemctl stop ss-rust
```

### 重启服务
```bash
systemctl restart ss-rust
```

### 查看服务状态
```bash
systemctl status ss-rust
```

### 查看服务日志
```bash
journalctl -xe --unit ss-rust
```

## 配置文件位置

- 主程序：`/usr/local/bin/ss-rust`
- 配置文件：`/etc/ss-rust/config.json`
- 版本文件：`/etc/ss-rust/ver.txt`

## 问题排查

如果服务无法启动，请检查：

1. 配置文件格式是否正确
2. 端口是否被占用
3. 系统日志中的错误信息
4. 确保密码长度符合加密方式的要求

## 更新记录

- v1.0.0：初始发布
  - 支持基本的安装和管理功能
  - 支持 AEAD 2022 加密方式
  - 添加自动化配置功能
  - 仅使用官方源安装

## 许可证

本项目采用 MIT 许可证 
