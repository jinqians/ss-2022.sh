#!/usr/bin/env bash
set -e

# =========================================
# 作者: jinqians
# 日期: 2025年3月
# 网站：jinqians.com
# 描述: Shadowsocks Rust 管理脚本
# =========================================

# 版本信息
SCRIPT_VERSION="1.1.0"
SS_VERSION=""

# 系统路径
SCRIPT_PATH=$(cd "$(dirname "$0")"; pwd)
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
SCRIPT_NAME=$(basename "$0")

# 安装路径
INSTALL_DIR="/etc/ss-rust"
BINARY_PATH="/usr/local/bin/ss-rust"
CONFIG_PATH="/etc/ss-rust/config.json"
VERSION_FILE="/etc/ss-rust/ver.txt"
SYSCTL_CONF="/etc/sysctl.d/local.conf"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PLAIN='\033[0m'
readonly BOLD='\033[1m'

# 状态提示
readonly INFO="${GREEN}[信息]${PLAIN}"
readonly ERROR="${RED}[错误]${PLAIN}"
readonly WARNING="${YELLOW}[警告]${PLAIN}"
readonly SUCCESS="${GREEN}[成功]${PLAIN}"

# 系统信息
OS_TYPE=""
OS_ARCH=""
OS_VERSION=""

# 配置信息
SS_PORT=""
SS_PASSWORD=""
SS_METHOD=""
SS_TFO=""
SS_DNS=""

# 错误处理函数
error_exit() {
    echo -e "${ERROR} $1" >&2
    exit 1
}

# 检查 root 权限
check_root() {
    if [[ $EUID != 0 ]]; then
        error_exit "当前非ROOT账号(或没有ROOT权限)，无法继续操作，请使用 sudo su 命令获取临时ROOT权限"
    fi
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        OS_TYPE="centos"
    elif grep -q -E -i "debian" /etc/issue; then
        OS_TYPE="debian"
    elif grep -q -E -i "ubuntu" /etc/issue; then
        OS_TYPE="ubuntu"
    elif grep -q -E -i "centos|red hat|redhat" /etc/issue; then
        OS_TYPE="centos"
    elif grep -q -E -i "debian" /proc/version; then
        OS_TYPE="debian"
    elif grep -q -E -i "ubuntu" /proc/version; then
        OS_TYPE="ubuntu"
    elif grep -q -E -i "centos|red hat|redhat" /proc/version; then
        OS_TYPE="centos"
    else
        error_exit "不支持的操作系统"
    fi
}

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    case "${arch}" in
        "i686"|"i386")
            OS_ARCH="i686"
            ;;
        "armv7"*|"armv6l")
            OS_ARCH="armv7"
            ;;
        "armv8"*|"aarch64")
            OS_ARCH="aarch64"
            ;;
        "x86_64")
            if [[ "$(uname)" == "Darwin" ]]; then
                OS_ARCH="x86_64-apple-darwin"
            else
                OS_ARCH="x86_64-unknown-linux"
            fi
            ;;
        *)
            error_exit "不支持的CPU架构: ${arch}"
            ;;
    esac
    echo -e "${INFO} 检测到系统架构为 [ ${OS_ARCH} ]"
}

# 检查安装状态
check_installation() {
    if [[ ! -e ${BINARY_PATH} ]]; then
        error_exit "Shadowsocks Rust 未安装，请先安装！"
    fi
}

# 检查服务状态
check_service_status() {
    local status=$(systemctl is-active ss-rust)
    echo "${status}"
}

# 获取最新版本
get_latest_version() {
    SS_VERSION=$(wget -qO- https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases | \
                 jq -r '[.[] | select(.prerelease == false) | select(.draft == false) | .tag_name] | .[0]')
    
    if [[ -z ${SS_VERSION} ]]; then
        error_exit "获取 Shadowsocks Rust 最新版本失败！"
    fi
    
    # 移除版本号中的 'v' 前缀
    SS_VERSION=${SS_VERSION#v}
    
    echo -e "${INFO} 检测到 Shadowsocks Rust 最新版本为 [ ${SS_VERSION} ]"
}

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m" && Yellow_font_prefix="\033[0;33m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"

check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi
}

check_installed_status() {
    if [[ ! -e ${BINARY_PATH} ]]; then
        echo -e "${Error} Shadowsocks Rust 没有安装，请检查！"
        return 1
    fi
    return 0
}

check_status() {
    if systemctl is-active ss-rust >/dev/null 2>&1; then
        status="running"
    else
        status="stopped"
    fi
}

check_new_ver() {
    new_ver=$(wget -qO- https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases| jq -r '[.[] | select(.prerelease == false) | select(.draft == false) | .tag_name] | .[0]')
    [[ -z ${new_ver} ]] && echo -e "${Error} Shadowsocks Rust 最新版本获取失败！" && exit 1
    echo -e "${Info} 检测到 Shadowsocks Rust 最新版本为 [ ${new_ver} ]"
}

# 检查版本并比较
check_ver_comparison() {
    if [[ ! -f "${VERSION_FILE}" ]]; then
        echo -e "${Info} 未找到版本文件，可能是首次安装"
        return 0
    fi
    
    local now_ver=$(cat ${VERSION_FILE})
    if [[ "${now_ver}" != "${new_ver}" ]]; then
        echo -e "${Info} 发现 Shadowsocks Rust 新版本 [ ${new_ver} ]"
        echo -e "${Info} 当前版本 [ ${now_ver} ]"
        return 0
    else
        echo -e "${Info} 当前已是最新版本 [ ${new_ver} ]"
        return 1
    fi
}

# 下载 Shadowsocks Rust
download_ss() {
    local version=$1
    local arch=$2
    local url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${version}"
    local filename="shadowsocks-v${version}.${arch}-gnu.tar.xz"
    
    echo -e "${INFO} 开始下载 Shadowsocks Rust ${version}..."
    echo -e "${INFO} 下载地址：${url}/${filename}"
    wget --no-check-certificate -N "${url}/${filename}"
    
    if [[ ! -e "${filename}" ]]; then
        error_exit "Shadowsocks Rust 下载失败！"
    fi
    
    if ! tar -xf "${filename}"; then
        error_exit "Shadowsocks Rust 解压失败！"
    fi
    
    if [[ ! -e "ssserver" ]]; then
        error_exit "Shadowsocks Rust 解压后未找到主程序！"
    fi
    
    rm -f "${filename}"
    chmod +x ssserver
    mv -f ssserver "${BINARY_PATH}"
    rm -f sslocal ssmanager ssservice ssurl
    
    echo "${version}" > "${VERSION_FILE}"
    echo -e "${SUCCESS} Shadowsocks Rust ${version} 下载安装完成！"
}

# 下载主函数
download() {
    if [[ ! -e "${INSTALL_DIR}" ]]; then
        mkdir -p "${INSTALL_DIR}"
    fi
    
    local version=${SS_VERSION}
    local arch=${OS_ARCH}
    download_ss "${version}" "${arch}"
}

# 安装系统服务
install_service() {
    echo -e "${INFO} 开始安装系统服务..."
    cat > /etc/systemd/system/ss-rust.service << EOF
[Unit]
Description=Shadowsocks Rust Service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
ExecStart=${BINARY_PATH} -c ${CONFIG_PATH}
Restart=on-failure
RestartSec=3s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${INFO} 重新加载 systemd 配置..."
    systemctl daemon-reload
    
    echo -e "${INFO} 启用 ss-rust 服务..."
    systemctl enable ss-rust
    
    echo -e "${SUCCESS} Shadowsocks Rust 服务配置完成！"
}

# 安装依赖
install_dependencies() {
    echo -e "${INFO} 开始安装系统依赖..."
    
    if [[ ${OS_TYPE} == "centos" ]]; then
        yum update -y
        yum install -y jq gzip wget curl unzip xz openssl qrencode
    else
        apt-get update
        apt-get install -y jq gzip wget curl unzip xz-utils openssl qrencode
    fi
    
    # 设置时区
    cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo -e "${SUCCESS} 系统依赖安装完成！"
}

# 写入配置文件
write_config() {
    cat > ${CONFIG_PATH} << EOF
{
    "server": "::",
    "server_port": ${SS_PORT},
    "password": "${SS_PASSWORD}",
    "method": "${SS_METHOD}",
    "fast_open": ${SS_TFO},
    "mode": "tcp_and_udp",
    "user": "nobody",
    "timeout": 300${SS_DNS:+",\n    \"nameserver\":\"${SS_DNS}\""}
}
EOF
    echo -e "${SUCCESS} 配置文件写入完成！"
}

# 读取配置文件
read_config() {
    if [[ ! -e ${CONFIG_PATH} ]]; then
        error_exit "Shadowsocks Rust 配置文件不存在！"
    fi
    
    SS_PORT=$(jq -r '.server_port' ${CONFIG_PATH})
    SS_PASSWORD=$(jq -r '.password' ${CONFIG_PATH})
    SS_METHOD=$(jq -r '.method' ${CONFIG_PATH})
    SS_TFO=$(jq -r '.fast_open' ${CONFIG_PATH})
    SS_DNS=$(jq -r '.nameserver // empty' ${CONFIG_PATH})
}

# 检查防火墙并开放端口
check_firewall() {
    local port=$1
    echo -e "${INFO} 检查防火墙配置..."
    
    # 检查 UFW
    if command -v ufw >/dev/null 2>&1; then
        echo -e "${INFO} 检测到 UFW 防火墙..."
        if ufw status | grep -qw active; then
            echo -e "${INFO} 正在将端口 ${port} 加入 UFW 规则..."
            ufw allow ${port}/tcp
            ufw allow ${port}/udp
            echo -e "${SUCCESS} UFW 端口开放完成！"
        fi
    fi
    
    # 检查 iptables
    if command -v iptables >/dev/null 2>&1; then
        echo -e "${INFO} 检测到 iptables 防火墙..."
        echo -e "${INFO} 正在将端口 ${port} 加入 iptables 规则..."
        iptables -I INPUT -p tcp --dport ${port} -j ACCEPT
        iptables -I INPUT -p udp --dport ${port} -j ACCEPT
        echo -e "${SUCCESS} iptables 端口开放完成！"
        
        # 保存 iptables 规则
        if [[ ${OS_TYPE} == "centos" ]]; then
            service iptables save
        else
            iptables-save > /etc/iptables.rules
        fi
    fi
}

# 生成随机端口
generate_random_port() {
    local min_port=10000
    local max_port=65535
    echo $(shuf -i ${min_port}-${max_port} -n 1)
}

# 设置端口
set_port() {
    SS_PORT=$(generate_random_port)
    echo -e "${INFO} 已生成随机端口：${SS_PORT}"
    echo -e "${Tip} 是否使用该随机端口？"
    echo "=================================="
    echo -e " ${Green_font_prefix}1.${Font_color_suffix} 是"
    echo -e " ${Green_font_prefix}2.${Font_color_suffix} 否，我要自定义端口"
    echo "=================================="
    
    read -e -p "(默认: 1. 使用随机端口)：" port_choice
    [[ -z "${port_choice}" ]] && port_choice="1"
    
    if [[ ${port_choice} == "2" ]]; then
        while true; do
            echo -e "请输入 Shadowsocks Rust 端口 [1-65535]"
            read -e -p "(默认：2525)：" SS_PORT
            [[ -z "${SS_PORT}" ]] && SS_PORT="2525"
            
            if [[ ${SS_PORT} =~ ^[0-9]+$ ]]; then
                if (( SS_PORT >= 1 && SS_PORT <= 65535 )); then
                    break
                else
                    echo -e "${Error} 输入错误，端口范围必须在 1-65535 之间"
                fi
            else
                echo -e "${Error} 输入错误，请输入数字"
            fi
        done
    fi
    
    echo && echo "=================================="
    echo -e "端口：${Red_background_prefix} ${SS_PORT} ${Font_color_suffix}"
    echo "=================================="
    
    # 检查并配置防火墙
    check_firewall "${SS_PORT}"
    echo
}

# 设置密码
set_password() {
    echo "请输入 Shadowsocks Rust 密码 [0-9][a-z][A-Z]"
    read -e -p "(默认：随机生成 Base64)：" SS_PASSWORD
    if [[ -z "${SS_PASSWORD}" ]]; then
        # 根据加密方式选择合适的密钥长度
        case "${SS_METHOD}" in
            "2022-blake3-aes-128-gcm")
                # 生成16字节密钥并进行base64编码
                SS_PASSWORD=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64)
                ;;
            "2022-blake3-aes-256-gcm"|"2022-blake3-chacha20-poly1305"|"2022-blake3-chacha8-poly1305")
                # 生成32字节密钥并进行base64编码
                # 32字节 = 44个base64字符（包含填充）
                raw_key=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64)
                # 确保生成的base64字符串长度为44个字符
                while [[ ${#raw_key} -ne 44 ]]; do
                    raw_key=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64)
                done
                SS_PASSWORD="${raw_key}"
                ;;
            *)
                # 其他加密方式使用16字节密钥
                SS_PASSWORD=$(dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64)
                ;;
        esac
    fi
    
    # 验证密码长度
    if [[ "${SS_METHOD}" == "2022-blake3-aes-256-gcm" || "${SS_METHOD}" == "2022-blake3-chacha20-poly1305" || "${SS_METHOD}" == "2022-blake3-chacha8-poly1305" ]]; then
        # 解码base64并检查字节长度
        decoded_length=$(echo -n "${SS_PASSWORD}" | base64 -d | wc -c)
        echo -e "${INFO} 当前加密方式需要32字节密钥"
        echo -e "${INFO} 当前密码长度：${#SS_PASSWORD} 个base64字符"
        echo -e "${INFO} 解码后的字节长度：${decoded_length} 字节"
        if [[ ${decoded_length} -ne 32 ]]; then
            echo -e "${WARNING} 密码长度不符合要求，请重新设置密码！"
            set_password
            return
        fi
    fi
    
    echo && echo "=================================="
    echo -e "密码：${Red_background_prefix} ${SS_PASSWORD} ${Font_color_suffix}"
    echo "==================================" && echo
}

# 设置加密方式
set_method() {
    echo -e "请选择 Shadowsocks Rust 加密方式
==================================	
 ${Green_font_prefix} 1.${Font_color_suffix} aes-128-gcm ${Green_font_prefix}(默认)${Font_color_suffix}
 ${Green_font_prefix} 2.${Font_color_suffix} aes-256-gcm ${Green_font_prefix}(推荐)${Font_color_suffix}
 ${Green_font_prefix} 3.${Font_color_suffix} chacha20-ietf-poly1305 ${Green_font_prefix}${Font_color_suffix}
 ${Green_font_prefix} 4.${Font_color_suffix} plain ${Red_font_prefix}(不推荐)${Font_color_suffix}
 ${Green_font_prefix} 5.${Font_color_suffix} none ${Red_font_prefix}(不推荐)${Font_color_suffix}
 ${Green_font_prefix} 6.${Font_color_suffix} table
 ${Green_font_prefix} 7.${Font_color_suffix} aes-128-cfb
 ${Green_font_prefix} 8.${Font_color_suffix} aes-256-cfb
 ${Green_font_prefix} 9.${Font_color_suffix} aes-256-ctr 
 ${Green_font_prefix}10.${Font_color_suffix} camellia-256-cfb
 ${Green_font_prefix}11.${Font_color_suffix} rc4-md5
 ${Green_font_prefix}12.${Font_color_suffix} chacha20-ietf
==================================
 ${Tip} AEAD 2022 加密（须v1.15.0及以上版本且密码须经过Base64加密）
==================================	
 ${Green_font_prefix}13.${Font_color_suffix} 2022-blake3-aes-128-gcm ${Green_font_prefix}(推荐)${Font_color_suffix}
 ${Green_font_prefix}14.${Font_color_suffix} 2022-blake3-aes-256-gcm ${Green_font_prefix}(推荐)${Font_color_suffix}
 ${Green_font_prefix}15.${Font_color_suffix} 2022-blake3-chacha20-poly1305
 ${Green_font_prefix}16.${Font_color_suffix} 2022-blake3-chacha8-poly1305
=================================="
    
    read -e -p "(默认: 1. aes-128-gcm)：" method_choice
    [[ -z "${method_choice}" ]] && method_choice="1"
    
    case ${method_choice} in
        1) SS_METHOD="aes-128-gcm" ;;
        2) SS_METHOD="aes-256-gcm" ;;
        3) SS_METHOD="chacha20-ietf-poly1305" ;;
        4) SS_METHOD="plain" ;;
        5) SS_METHOD="none" ;;
        6) SS_METHOD="table" ;;
        7) SS_METHOD="aes-128-cfb" ;;
        8) SS_METHOD="aes-256-cfb" ;;
        9) SS_METHOD="aes-256-ctr" ;;
        10) SS_METHOD="camellia-256-cfb" ;;
        11) SS_METHOD="arc4-md5" ;;
        12) SS_METHOD="chacha20-ietf" ;;
        13) SS_METHOD="2022-blake3-aes-128-gcm" ;;
        14) SS_METHOD="2022-blake3-aes-256-gcm" ;;
        15) SS_METHOD="2022-blake3-chacha20-poly1305" ;;
        16) SS_METHOD="2022-blake3-chacha8-poly1305" ;;
        *) SS_METHOD="aes-128-gcm" ;;
    esac
    
    echo && echo "=================================="
    echo -e "加密：${Red_background_prefix} ${SS_METHOD} ${Font_color_suffix}"
    echo "==================================" && echo
}

# 设置 TFO
set_tfo() {
    echo -e "是否启用 TFO ？
==================================
 ${Green_font_prefix}1.${Font_color_suffix} 启用
 ${Green_font_prefix}2.${Font_color_suffix} 禁用
=================================="
    read -e -p "(默认：1)：" tfo_choice
    [[ -z "${tfo_choice}" ]] && tfo_choice="1"
    
    if [[ ${tfo_choice} == "1" ]]; then
        SS_TFO="true"
    else
        SS_TFO="false"
    fi
    
    echo && echo "=================================="
    echo -e "TFO：${Red_background_prefix} ${SS_TFO} ${Font_color_suffix}"
    echo "==================================" && echo
}

# 设置 DNS
set_dns() {
    echo -e "请选择 DNS 配置方式：
==================================
 ${Green_font_prefix}1.${Font_color_suffix} 使用系统默认 DNS ${Green_font_prefix}(推荐)${Font_color_suffix}
 ${Green_font_prefix}2.${Font_color_suffix} 自定义 DNS 服务器
=================================="
    read -e -p "(默认：1)：" dns_choice
    [[ -z "${dns_choice}" ]] && dns_choice="1"
    
    if [[ ${dns_choice} == "2" ]]; then
        echo -e "请输入自定义 DNS 服务器地址（多个 DNS 用逗号分隔，如：8.8.8.8,8.8.4.4）"
        read -e -p "(默认：8.8.8.8)：" SS_DNS
        [[ -z "${SS_DNS}" ]] && SS_DNS="8.8.8.8"
        echo && echo "=================================="
        echo -e "DNS：${Red_background_prefix} ${SS_DNS} ${Font_color_suffix}"
        echo "==================================" && echo
    else
        SS_DNS=""
        echo && echo "=================================="
        echo -e "DNS：${Red_background_prefix} 使用系统默认 DNS ${Font_color_suffix}"
        echo "==================================" && echo
    fi
}

# 修改配置
modify_config() {
    check_installation
    echo && echo -e "你要做什么？
==================================
 ${Green_font_prefix}1.${Font_color_suffix}  修改 端口配置
 ${Green_font_prefix}2.${Font_color_suffix}  修改 密码配置
 ${Green_font_prefix}3.${Font_color_suffix}  修改 加密配置
 ${Green_font_prefix}4.${Font_color_suffix}  修改 TFO 配置
 ${Green_font_prefix}5.${Font_color_suffix}  修改 DNS 配置
 ${Green_font_prefix}6.${Font_color_suffix}  修改 全部配置" && echo
    
    read -e -p "(默认：取消)：" modify
    [[ -z "${modify}" ]] && echo "已取消..." && Start_Menu
    
    case "${modify}" in
        1)
            read_config
            set_port
            write_config
            Restart
            ;;
        2)
            read_config
            set_password
            write_config
            Restart
            ;;
        3)
            read_config
            set_method
            write_config
            Restart
            ;;
        4)
            read_config
            set_tfo
            write_config
            Restart
            ;;
        5)
            read_config
            set_dns
            write_config
            Restart
            ;;
        6)
            read_config
            set_port
            set_password
            set_method
            set_tfo
            set_dns
            write_config
            Restart
            ;;
        *)
            echo -e "${Error} 请输入正确的数字(1-6)"
            sleep 2s
            modify_config
            ;;
    esac
}

# 安装
Install() {
    [[ -e ${BINARY_PATH} ]] && echo -e "${Error} 检测到 Shadowsocks Rust 已安装！" && exit 1
    
    echo -e "${Info} 开始设置配置..."
    set_port
    set_method
    set_password
    set_tfo
    set_dns
    
    echo -e "${Info} 开始安装/配置依赖..."
    install_dependencies
    
    echo -e "${Info} 开始下载/安装..."
    detect_arch
    get_latest_version
    download
    
    echo -e "${Info} 开始写入配置文件..."
    write_config
    
    echo -e "${Info} 开始安装系统服务..."
    install_service
    
    echo -e "${Info} 所有步骤安装完毕，开始启动服务..."
    start_service
    
    if [[ "$?" == "0" ]]; then
        echo -e "${Success} Shadowsocks Rust 安装并启动成功！"
        View
        Before_Start_Menu
    else
        echo -e "${Error} Shadowsocks Rust 启动失败，请检查日志！"
        echo -e "${Info} 您可以使用以下命令查看详细日志："
        echo -e " - systemctl status ss-rust"
        echo -e " - journalctl -xe --unit ss-rust"
        Before_Start_Menu
    fi
}

# 启动服务
start_service() {
    check_installed_status || return 1
    
    echo -e "${INFO} 检查服务状态..."
    check_status
    if [[ "$status" == "running" ]]; then
        echo -e "${INFO} Shadowsocks Rust 已在运行！"
        return 1
    fi
    
    echo -e "${INFO} 正在启动 Shadowsocks Rust..."
    systemctl start ss-rust
    
    # 等待服务启动
    sleep 2
    
    # 检查服务状态和日志
    if ! systemctl is-active ss-rust >/dev/null 2>&1; then
        echo -e "${ERROR} Shadowsocks Rust 启动失败！"
        echo -e "${INFO} 查看服务日志："
        journalctl -xe --unit ss-rust
        return 1
    fi
    
    echo -e "${SUCCESS} Shadowsocks Rust 启动成功！"
}

# 停止
Stop() {
    check_installed_status || return 1
    check_status
    if [[ ! "$status" == "running" ]]; then
        echo -e "${Error} Shadowsocks Rust 没有运行，请检查！"
        return 1
    fi
    systemctl stop ss-rust
    echo -e "${Info} Shadowsocks Rust 已停止！"
}

# 重启
Restart() {
    check_installed_status || return 1
    systemctl restart ss-rust
    echo -e "${Info} Shadowsocks Rust 重启完毕！"
}

# 更新
Update() {
    check_installed_status
    check_new_ver
    check_ver_comparison
    echo -e "${Info} Shadowsocks Rust 更新完毕！"
    sleep 3s
    Start_Menu
}

# 卸载
Uninstall() {
    check_installed_status || return 1
    echo "确定要卸载 Shadowsocks Rust ? (y/N)"
    echo
    read -e -p "(默认：n)：" unyn
    [[ -z ${unyn} ]] && unyn="n"
    if [[ ${unyn} == [Yy] ]]; then
        check_status
        [[ "$status" == "running" ]] && systemctl stop ss-rust
        systemctl disable ss-rust
        rm -rf "${INSTALL_DIR}"
        rm -rf "${BINARY_PATH}"
        echo && echo "Shadowsocks Rust 卸载完成！" && echo
    else
        echo && echo "卸载已取消..." && echo
    fi
}

# 获取IPv4地址
getipv4() {
    ipv4=$(wget -qO- -4 -t1 -T2 ipinfo.io/ip)
    if [[ -z "${ipv4}" ]]; then
        ipv4=$(wget -qO- -4 -t1 -T2 api.ip.sb/ip)
        if [[ -z "${ipv4}" ]]; then
            ipv4=$(wget -qO- -4 -t1 -T2 members.3322.org/dyndns/getip)
            if [[ -z "${ipv4}" ]]; then
                ipv4="IPv4_Error"
            fi
        fi
    fi
}

# 获取IPv6地址
getipv6() {
    ipv6=$(wget -qO- -6 -t1 -T2 ifconfig.co)
    if [[ -z "${ipv6}" ]]; then
        ipv6="IPv6_Error"
    fi
}

# 生成安全的Base64编码
urlsafe_base64() {
    date=$(echo -n "$1"|base64|sed ':a;N;s/\n/ /g;ta'|sed 's/ //g;s/=//g;s/+/-/g;s/\//_/g')
    echo -e "${date}"
}

# 生成链接和二维码
Link_QR() {
    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        SSbase64=$(urlsafe_base64 "${SS_METHOD}:${SS_PASSWORD}@${ipv4}:${SS_PORT}")
        SSurl="ss://${SSbase64}"
        link_ipv4=" 链接  [IPv4]：${Green_font_prefix}${SSurl}${Font_color_suffix}"
        echo -e "\n IPv4 二维码:"
        echo "${SSurl}" | qrencode -t utf8
    fi
    if [[ "${ipv6}" != "IPv6_Error" ]]; then
        SSbase64=$(urlsafe_base64 "${SS_METHOD}:${SS_PASSWORD}@${ipv6}:${SS_PORT}")
        SSurl="ss://${SSbase64}"
        link_ipv6=" 链接  [IPv6]：${Green_font_prefix}${SSurl}${Font_color_suffix}"
        echo -e "\n IPv6 二维码:"
        echo "${SSurl}" | qrencode -t utf8
    fi
}

# 查看配置信息
View() {
    check_installed_status
    read_config
    getipv4
    getipv6
    echo -e "Shadowsocks Rust 配置："
    echo -e "——————————————————————————————————"
    [[ "${ipv4}" != "IPv4_Error" ]] && echo -e " 地址：${Green_font_prefix}${ipv4}${Font_color_suffix}"
    [[ "${ipv6}" != "IPv6_Error" ]] && echo -e " 地址：${Green_font_prefix}${ipv6}${Font_color_suffix}"
    echo -e " 端口：${Green_font_prefix}${SS_PORT}${Font_color_suffix}"
    echo -e " 密码：${Green_font_prefix}${SS_PASSWORD}${Font_color_suffix}"
    echo -e " 加密：${Green_font_prefix}${SS_METHOD}${Font_color_suffix}"
    echo -e " TFO ：${Green_font_prefix}${SS_TFO}${Font_color_suffix}"
    [[ ! -z "${SS_DNS}" ]] && echo -e " DNS ：${Green_font_prefix}${SS_DNS}${Font_color_suffix}"
    echo -e "——————————————————————————————————"
    Link_QR
    [[ ! -z "${link_ipv4}" ]] && echo -e "${link_ipv4}"
    [[ ! -z "${link_ipv6}" ]] && echo -e "${link_ipv6}"
    echo -e "—————————————————————————"
    echo -e "${Info} Surge 配置："
    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        echo -e "$(uname -n) = ss,${ipv4},${SS_PORT},encrypt-method=${SS_METHOD},password=${SS_PASSWORD},tfo=${SS_TFO},udp-relay=true,ecn=true"
    else
        echo -e "$(uname -n) = ss,${ipv6},${SS_PORT},encrypt-method=${SS_METHOD},password=${SS_PASSWORD},tfo=${SS_TFO},udp-relay=true,ecn=true"
    fi
    echo -e "—————————————————————————"
    return 0
}

# 查看运行状态
Status() {
    echo -e "${Info} 获取 Shadowsocks Rust 活动日志 ……"
    echo -e "${Tip} 返回主菜单请按 q ！"
    systemctl status ss-rust
    Start_Menu
}

# 更新脚本
Update_Shell() {
    echo -e "${Info} 当前脚本版本为 [ ${SCRIPT_VERSION} ]"
    echo -e "${Info} 开始检测脚本更新..."
    
    # 下载最新版本进行版本对比
    local temp_file="/tmp/ss-2022.sh"
    if ! wget --no-check-certificate -O ${temp_file} "https://raw.githubusercontent.com/jinqians/ss-2022.sh/refs/heads/main/ss-2022.sh"; then
        echo -e "${Error} 下载最新脚本失败！"
        rm -f ${temp_file}
        return 1
    fi
    
    # 检查下载的文件是否存在且有内容
    if [[ ! -s ${temp_file} ]]; then
        echo -e "${Error} 下载的脚本文件为空！"
        rm -f ${temp_file}
        return 1
    fi
    
    # 获取最新版本号
    sh_new_ver=$(grep 'SCRIPT_VERSION="' ${temp_file} | awk -F '"' '{print $2}')
    if [[ -z ${sh_new_ver} ]]; then
        echo -e "${Error} 获取最新版本号失败！"
        rm -f ${temp_file}
        return 1
    fi
    
    # 比较版本号
    if [[ ${sh_new_ver} != ${SCRIPT_VERSION} ]]; then
        echo -e "${Info} 发现新版本 [ ${sh_new_ver} ]"
        echo -e "${Info} 是否更新？[Y/n]"
        read -p "(默认: y)：" yn
        [[ -z "${yn}" ]] && yn="y"
        if [[ ${yn} == [Yy] ]]; then
            # 备份当前脚本
            cp "${SCRIPT_PATH}/${SCRIPT_NAME}" "${SCRIPT_PATH}/${SCRIPT_NAME}.bak.${SCRIPT_VERSION}"
            echo -e "${Info} 已备份当前版本到 ${SCRIPT_NAME}.bak.${SCRIPT_VERSION}"
            
            # 更新脚本
            mv -f ${temp_file} "${SCRIPT_PATH}/${SCRIPT_NAME}"
            chmod +x "${SCRIPT_PATH}/${SCRIPT_NAME}"
            echo -e "${Success} 脚本已更新至 [ ${sh_new_ver} ]"
            echo -e "${Info} 2秒后执行新脚本..."
            sleep 2s
            exec "${SCRIPT_PATH}/${SCRIPT_NAME}"
        else
            echo -e "${Info} 已取消更新..."
            rm -f ${temp_file}
        fi
    else
        echo -e "${Info} 当前已是最新版本 [ ${sh_new_ver} ]"
        rm -f ${temp_file}
    fi
}

# 返回主菜单
Before_Start_Menu() {
    echo && echo -n -e "${Yellow_font_prefix}* 按回车返回主菜单 *${Font_color_suffix}" && read temp
}

# 主菜单
Start_Menu() {
    while true; do
        clear
        check_root
        check_sys
        action=${1:-}
    echo -e "${GREEN}============================================${RESET}"
    echo -e "${GREEN}          Snell 管理脚本 v${current_version}${RESET}"
    echo -e "${GREEN}============================================${RESET}"
    echo -e "${GREEN}作者: jinqian${RESET}"
    echo -e "${GREEN}网站：https://jinqians.com${RESET}"
    echo -e "${CYAN}============================================${RESET}"
        echo && echo -e "  
============================================
Shadowsocks Rust 管理脚本 ${Green_font_prefix}[v${SCRIPT_VERSION}]${Font_color_suffix}
============================================
 ${Green_font_prefix}0.${Font_color_suffix} 更新脚本
——————————————————————————————————
 ${Green_font_prefix}1.${Font_color_suffix} 安装 Shadowsocks Rust
 ${Green_font_prefix}2.${Font_color_suffix} 更新 Shadowsocks Rust
 ${Green_font_prefix}3.${Font_color_suffix} 卸载 Shadowsocks Rust
——————————————————————————————————
 ${Green_font_prefix}4.${Font_color_suffix} 启动 Shadowsocks Rust
 ${Green_font_prefix}5.${Font_color_suffix} 停止 Shadowsocks Rust
 ${Green_font_prefix}6.${Font_color_suffix} 重启 Shadowsocks Rust
——————————————————————————————————
 ${Green_font_prefix}7.${Font_color_suffix} 设置 配置信息
 ${Green_font_prefix}8.${Font_color_suffix} 查看 配置信息
 ${Green_font_prefix}9.${Font_color_suffix} 查看 运行状态
——————————————————————————————————
 ${Green_font_prefix}10.${Font_color_suffix} 退出脚本
==================================" && echo
        if [[ -e ${BINARY_PATH} ]]; then
            check_status
            if [[ "$status" == "running" ]]; then
                echo -e " 当前状态：${Green_font_prefix}已安装${Font_color_suffix} 并 ${Green_font_prefix}已启动${Font_color_suffix}"
            else
                echo -e " 当前状态：${Green_font_prefix}已安装${Font_color_suffix} 但 ${Red_font_prefix}未启动${Font_color_suffix}"
            fi
        else
            echo -e " 当前状态：${Red_font_prefix}未安装${Font_color_suffix}"
        fi
        echo
        read -e -p " 请输入数字 [0-10]：" num
        case "$num" in
            0)
                Update_Shell
                ;;
            1)
                Install
                ;;
            2)
                Update
                ;;
            3)
                Uninstall
                sleep 2
                ;;
            4)
                start_service
                sleep 2
                ;;
            5)
                Stop
                sleep 2
                ;;
            6)
                Restart
                sleep 2
                ;;
            7)
                modify_config
                ;;
            8)
                View
                echo && echo -n -e "${Yellow_font_prefix}* 按回车返回主菜单 *${Font_color_suffix}" && read temp
                ;;
            9)
                Status
                ;;
            10)
                echo -e "${Info} 退出脚本..."
                exit 0
                ;;
            *)
                echo -e "${Error} 请输入正确数字 [0-10]"
                sleep 2
                ;;
        esac
    done
}

# 启动脚本
Start_Menu "$@"
