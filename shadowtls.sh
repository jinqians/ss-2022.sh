#!/bin/bash
# =========================================
# 作者: jinqians
# 日期: 2024年11月
# 网站：jinqians.com
# 描述: 这个脚本用于安装和管理 ShadowTLS V3
# =========================================

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 安装目录和配置文件
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/shadowtls"
SERVICE_FILE="/etc/systemd/system/shadowtls.service"

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请以 root 权限运行此脚本${RESET}"
        exit 1
    fi
}

# 安装必要的工具
install_requirements() {
    apt update
    apt install -y wget curl jq
}

# 获取最新版本
get_latest_version() {
    latest_version=$(curl -s "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" | jq -r .tag_name)
    if [ -z "$latest_version" ]; then
        echo -e "${RED}获取最新版本失败${RESET}"
        exit 1
    fi
    echo "$latest_version"
}

# 检查 Shadowsocks Rust 是否已安装
check_ssrust() {
    if [ ! -f "/usr/local/bin/ss-rust" ]; then
        echo -e "${RED}未检测到 Shadowsocks Rust，请先安装 Shadowsocks Rust${RESET}"
        return 1
    fi
    return 0
}

# 获取 Shadowsocks Rust 端口
get_ssrust_port() {
    local ssrust_conf="/etc/ss-rust/config.json"
    if [ ! -f "$ssrust_conf" ]; then
        echo -e "${RED}Shadowsocks Rust 配置文件不存在${RESET}"
        return 1
    fi
    
    # 获取端口
    local ssrust_port=$(jq -r '.server_port' "$ssrust_conf" 2>/dev/null)
    if [ -z "$ssrust_port" ] || [ "$ssrust_port" = "null" ]; then
        echo -e "${RED}无法读取 Shadowsocks Rust 端口配置${RESET}"
        return 1
    fi
    
    echo "$ssrust_port"
    return 0
}

# 获取 Shadowsocks Rust 密码
get_ssrust_password() {
    local ssrust_conf="/etc/ss-rust/config.json"
    if [ ! -f "$ssrust_conf" ]; then
        echo -e "${RED}未找到 Shadowsocks Rust 配置文件${RESET}"
        return 1
    fi
    
    local ssrust_password=$(jq -r '.password' "$ssrust_conf" 2>/dev/null)
    if [ -z "$ssrust_password" ] || [ "$ssrust_password" = "null" ]; then
        echo -e "${RED}无法读取 Shadowsocks Rust 密码配置${RESET}"
        return 1
    fi
    
    echo "$ssrust_password"
    return 0
}

# 获取 Shadowsocks Rust 加密方式
get_ssrust_method() {
    local ssrust_conf="/etc/ss-rust/config.json"
    if [ ! -f "$ssrust_conf" ]; then
        echo -e "${RED}未找到 Shadowsocks Rust 配置文件${RESET}"
        return 1
    fi
    
    local ssrust_method=$(jq -r '.method' "$ssrust_conf" 2>/dev/null)
    if [ -z "$ssrust_method" ] || [ "$ssrust_method" = "null" ]; then
        echo -e "${RED}无法读取 Shadowsocks Rust 加密方式配置${RESET}"
        return 1
    fi
    
    echo "$ssrust_method"
    return 0
}

# 获取服务器IP
get_server_ip() {
    local ipv4
    local ipv6
    
    # 获取IPv4地址
    ipv4=$(curl -s -4 ip.sb 2>/dev/null)
    
    # 获取IPv6地址
    ipv6=$(curl -s -6 ip.sb 2>/dev/null)
    
    # 判断IP类型并返回
    if [ -n "$ipv4" ] && [ -n "$ipv6" ]; then
        # 双栈，优先返回IPv4
        echo "$ipv4"
    elif [ -n "$ipv4" ]; then
        # 仅IPv4
        echo "$ipv4"
    elif [ -n "$ipv6" ]; then
        # 仅IPv6
        echo "$ipv6"
    else
        echo -e "${RED}无法获取服务器 IP${RESET}"
        return 1
    fi
    
    return 0
}

# 检查 shadow-tls 命令格式
check_shadowtls_command() {
    local help_output
    help_output=$($INSTALL_DIR/shadow-tls --help 2>&1)
    echo -e "${YELLOW}Shadow-tls 帮助信息：${RESET}"
    echo "$help_output"
    return 0
}

# 生成安全的Base64编码
urlsafe_base64() {
    date=$(echo -n "$1"|base64|sed ':a;N;s/\n/ /g;ta'|sed 's/ //g;s/=//g;s/+/-/g;s/\//_/g')
    echo -e "${date}"
}

# 生成随机端口
generate_random_port() {
    local min_port=10000
    local max_port=65535
    echo $(shuf -i ${min_port}-${max_port} -n 1)
}

# 生成链接和二维码
generate_links() {
    local server_ip=$1
    local listen_port=$2
    local ssrust_password=$3
    local ssrust_method=$4
    local stls_password=$5
    local stls_sni=$6
    
    # 安装 qrencode
    if ! command -v qrencode &> /dev/null; then
        echo -e "${YELLOW}正在安装 qrencode...${RESET}"
        apt-get update && apt-get install -y qrencode
    fi
    
    echo -e "\n${YELLOW}=== 服务器配置 ===${RESET}"
    echo -e "服务器IP：${server_ip}"
    echo -e "\nShadowsocks 配置："
    echo -e "  - 端口：${ssrust_port}"
    echo -e "  - 加密方式：${ssrust_method}"
    echo -e "  - 密码：${ssrust_password}"
    echo -e "\nShadowTLS 配置："
    echo -e "  - 端口：${listen_port}"
    echo -e "  - 密码：${stls_password}"
    echo -e "  - SNI：${stls_sni}"
    echo -e "  - 版本：3"
    
    # 生成 SS + ShadowTLS 合并链接
    local userinfo=$(echo -n "${ssrust_method}:${ssrust_password}" | base64 | tr -d '\n')
    # 创建 shadow-tls JSON 配置
    local shadow_tls_config="{\"version\":\"3\",\"password\":\"${stls_password}\",\"host\":\"${stls_sni}\",\"port\":\"${listen_port}\",\"address\":\"${server_ip}\"}"
    local shadow_tls_base64=$(echo -n "${shadow_tls_config}" | base64 | tr -d '\n')
    local ss_url="ss://${userinfo}@${server_ip}:${ssrust_port}?shadow-tls=${shadow_tls_base64}#SS-${server_ip}"
    
    echo -e "\n${YELLOW}=== Surge 配置 ===${RESET}"
    echo -e "SS-${server_ip} = ss, ${server_ip}, ${listen_port}, encrypt-method=${ssrust_method}, password=${ssrust_password}, shadow-tls-password=${stls_password}, shadow-tls-sni=${stls_sni}, shadow-tls-version=3, udp-relay=true"
    
    echo -e "\n${YELLOW}=== Shadowrocket 配置说明 ===${RESET}"
    echo -e "1. 添加 Shadowsocks 节点："
    echo -e "   - 类型：Shadowsocks"
    echo -e "   - 地址：${server_ip}"
    echo -e "   - 端口：${ssrust_port}"
    echo -e "   - 加密方法：${ssrust_method}"
    echo -e "   - 密码：${ssrust_password}"
    
    echo -e "\n2. 添加 ShadowTLS 节点："
    echo -e "   - 类型：ShadowTLS"
    echo -e "   - 地址：${server_ip}"
    echo -e "   - 端口：${listen_port}"
    echo -e "   - 密码：${stls_password}"
    echo -e "   - SNI：${stls_sni}"
    echo -e "   - 版本：3"

    echo -e "\n${YELLOW}=== Shadowrocket分享链接 ===${RESET}"
    echo -e "${GREEN}SS + ShadowTLS 链接：${RESET}${ss_url}"
    
    echo -e "\n${YELLOW}=== Shadowrocket二维码 ===${RESET}"
    qrencode -t UTF8 "${ss_url}"
    
    echo -e "\n${YELLOW}=== Clash Meta 配置 ===${RESET}"
    echo -e "proxies:"
    echo -e "  - name: SS-${server_ip}"
    echo -e "    type: ss"
    echo -e "    server: ${server_ip}"
    echo -e "    port: ${listen_port}"
    echo -e "    cipher: ${ssrust_method}"
    echo -e "    password: \"${ssrust_password}\""
    echo -e "    plugin: shadow-tls"
    echo -e "    plugin-opts:"
    echo -e "      host: \"${stls_sni}\""
    echo -e "      password: \"${stls_password}\""
    echo -e "      version: 3"
}

# 安装 ShadowTLS
install_shadowtls() {
    echo -e "${CYAN}正在安装 ShadowTLS...${RESET}"
    
    # 检查 Shadowsocks Rust 是否已安装
    if ! check_ssrust; then
        echo -e "${YELLOW}请先安装 Shadowsocks Rust 再安装 ShadowTLS${RESET}"
        return 1
    fi
    
    # 获取 Shadowsocks Rust 端口
    local ssrust_port=$(get_ssrust_port)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 获取系统架构
    arch=$(uname -m)
    case $arch in
        x86_64)
            arch="x86_64-unknown-linux-musl"
            ;;
        aarch64)
            arch="aarch64-unknown-linux-musl"
            ;;
        *)
            echo -e "${RED}不支持的系统架构: $arch${RESET}"
            exit 1
            ;;
    esac
    
    # 获取最新版本
    version=$(get_latest_version)
    
    # 下载并安装
    download_url="https://github.com/ihciah/shadow-tls/releases/download/${version}/shadow-tls-${arch}"
    wget "$download_url" -O "$INSTALL_DIR/shadow-tls"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载 ShadowTLS 失败${RESET}"
        exit 1
    fi
    
    chmod +x "$INSTALL_DIR/shadow-tls"
    
    # 生成随机密码
    password=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    
    # 获取用户输入
    read -rp "请输入 ShadowTLS 监听端口 (1-65535): " listen_port
    read -rp "请输入 TLS 伪装域名 (直接回车默认为 www.microsoft.com): " tls_domain
    
    # 如果用户未输入域名，使用默认值
    if [ -z "$tls_domain" ]; then
        tls_domain="www.microsoft.com"
    fi
    
    # 创建 systemd 服务文件
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Shadow-TLS Server Service
Documentation=man:sstls-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/shadow-tls --v3 server --listen ::0:${listen_port} --server 127.0.0.1:${ssrust_port} --tls ${tls_domain} --password ${password}
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=shadow-tls

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载 systemd 配置
    systemctl daemon-reload
    
    # 启动服务
    systemctl start shadowtls
    systemctl enable shadowtls
    
    # 获取服务器IP和SS配置
    local server_ip=$(get_server_ip)
    local ssrust_password=$(get_ssrust_password)
    local ssrust_method=$(get_ssrust_method)
    
    # 验证服务状态
    if ! systemctl is-active shadowtls >/dev/null 2>&1; then
        echo -e "${RED}ShadowTLS 服务未能正常运行${RESET}"
        echo -e "${YELLOW}服务状态：${RESET}"
        systemctl status shadowtls
        echo -e "${YELLOW}日志内容：${RESET}"
        journalctl -u shadowtls -n 20
        return 1
    fi
    
    echo -e "\n${GREEN}=== ShadowTLS 安装成功 ===${RESET}"
    echo -e "\n${YELLOW}=== 服务器配置 ===${RESET}"
    echo -e "服务器IP：${server_ip}"
    echo -e "Shadowsocks 配置："
    echo -e "  - 端口：${ssrust_port}"
    echo -e "  - 加密方式：${ssrust_method}"
    echo -e "  - 密码：${ssrust_password}"
    echo -e "\nShadowTLS 配置："
    echo -e "  - 端口：${listen_port}"
    echo -e "  - 密码：${password}"
    echo -e "  - SNI：${tls_domain}"
    
    # 生成客户端配置
    generate_links "${server_ip}" "${listen_port}" "${ssrust_password}" "${ssrust_method}" "${password}" "${tls_domain}"
    
    echo -e "\n${GREEN}服务已启动并设置为开机自启${RESET}"
}

# 卸载 ShadowTLS
uninstall_shadowtls() {
    echo -e "${YELLOW}正在卸载 ShadowTLS...${RESET}"
    
    systemctl stop shadowtls
    systemctl disable shadowtls
    
    rm -f "$SERVICE_FILE"
    rm -f "$INSTALL_DIR/shadow-tls"
    rm -rf "$CONFIG_DIR"
    
    systemctl daemon-reload
    
    echo -e "${GREEN}ShadowTLS 已成功卸载${RESET}"
}

# 查看配置
view_config() {
    if [ -f "$SERVICE_FILE" ]; then
        echo -e "${CYAN}ShadowTLS 配置信息：${RESET}"
        cat "$SERVICE_FILE"
        echo -e "\n${CYAN}服务状态：${RESET}"
        systemctl status shadowtls
    else
        echo -e "${RED}配置文件不存在${RESET}"
    fi
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n${CYAN}ShadowTLS 管理菜单${RESET}"
        echo -e "${YELLOW}1. 安装 ShadowTLS${RESET}"
        echo -e "${YELLOW}2. 卸载 ShadowTLS${RESET}"
        echo -e "${YELLOW}3. 查看配置${RESET}"
        echo -e "${YELLOW}4. 返回上级菜单${RESET}"
        echo -e "${YELLOW}0. 退出${RESET}"
        
        read -rp "请选择操作 [0-4]: " choice
        
        case "$choice" in
            1)
                install_shadowtls
                ;;
            2)
                uninstall_shadowtls
                ;;
            3)
                view_config
                ;;
            4)
                return 0
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择${RESET}"
                ;;
        esac
    done
}

# 检查root权限
check_root

# 如果直接运行此脚本，则显示主菜单
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu
fi
