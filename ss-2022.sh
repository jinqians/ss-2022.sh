#!/usr/bin/env bash
set -e

# =========================================
# 作者: jinqians
# 日期: 2026年7月
# 网站：jinqians.com
# 描述: Shadowsocks Rust 管理脚本
# =========================================

# 版本信息
SCRIPT_VERSION="1.8"
SS_VERSION=""

# 系统路径
SCRIPT_PATH=$(cd "$(dirname "$0")"; pwd)
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
SCRIPT_NAME=$(basename "$0")

# 安装路径
INSTALL_DIR="/etc/ss-rust"
BINARY_PATH="/usr/local/bin/ss-rust"
CONFIG_PATH="/etc/ss-rust/config.json"
PORTS_DIR="/etc/ss-rust/ports"
VERSION_FILE="/etc/ss-rust/ver.txt"
SYSCTL_CONF="/etc/sysctl.d/local.conf"
MAINLAND_BLOCK_SCRIPT="/usr/local/bin/block-mainland.sh"
MAINLAND_EXTRACT_SCRIPT="/usr/local/bin/extract-cn-ip-from-mmdb.py"
MAINLAND_BLOCK_REPO_URL="https://raw.githubusercontent.com/jinqians/ss-2022.sh/refs/heads/main/block-mainland.sh"
MAINLAND_EXTRACT_REPO_URL="https://raw.githubusercontent.com/jinqians/ss-2022.sh/refs/heads/main/extract-cn-ip-from-mmdb.py"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PLAIN='\033[0m'
readonly BOLD='\033[1m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

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
SS_PLUGIN=""
SS_PLUGIN_OPTS=""

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
    # 优先读取 /etc/os-release（现代发行版标准，可识别 AlmaLinux/Rocky 等 RHEL 系）
    if [[ -f /etc/os-release ]]; then
        local os_id os_like
        os_id=$(. /etc/os-release 2>/dev/null && echo "${ID:-}")
        os_like=$(. /etc/os-release 2>/dev/null && echo "${ID_LIKE:-}")
        case "${os_id}" in
            debian) OS_TYPE="debian" ;;
            ubuntu) OS_TYPE="ubuntu" ;;
            centos|rhel|almalinux|rocky|fedora|ol|amzn|anolis|openEuler) OS_TYPE="centos" ;;
            *)
                if [[ "${os_like}" == *debian* || "${os_like}" == *ubuntu* ]]; then
                    OS_TYPE="debian"
                elif [[ "${os_like}" == *rhel* || "${os_like}" == *fedora* || "${os_like}" == *centos* ]]; then
                    OS_TYPE="centos"
                fi
                ;;
        esac
    fi

    # 旧的检测方式作为兜底
    if [[ -z "${OS_TYPE}" ]]; then
        if [[ -f /etc/redhat-release ]]; then
            OS_TYPE="centos"
        elif grep -q -E -i "debian" /etc/issue 2>/dev/null; then
            OS_TYPE="debian"
        elif grep -q -E -i "ubuntu" /etc/issue 2>/dev/null; then
            OS_TYPE="ubuntu"
        elif grep -q -E -i "centos|red hat|redhat" /etc/issue 2>/dev/null; then
            OS_TYPE="centos"
        elif grep -q -E -i "debian" /proc/version 2>/dev/null; then
            OS_TYPE="debian"
        elif grep -q -E -i "ubuntu" /proc/version 2>/dev/null; then
            OS_TYPE="ubuntu"
        elif grep -q -E -i "centos|red hat|redhat" /proc/version 2>/dev/null; then
            OS_TYPE="centos"
        else
            error_exit "不支持的操作系统"
        fi
    fi
}

# RHEL 系包管理器（AlmaLinux/Rocky 9 已无 yum 命令本体，优先 dnf）
rhel_pkg_mgr() {
    if command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    else
        echo "yum"
    fi
}

# 检测系统架构
detect_arch() {
    local arch=$(uname -m)
    local os=$(uname -s)
    
    case "${os}" in
        "Darwin")
            case "${arch}" in
                "arm64")
                    OS_ARCH="aarch64-apple-darwin"
                    ;;
                "x86_64")
                    OS_ARCH="x86_64-apple-darwin"
                    ;;
            esac
            ;;
        "Linux")
            case "${arch}" in
                "x86_64")
                    OS_ARCH="x86_64-unknown-linux-gnu"
                    ;;
                "aarch64")
                    OS_ARCH="aarch64-unknown-linux-gnu"
                    ;;
                "armv7l"|"armv7")
                    # 检查是否支持硬浮点
                    if grep -q "gnueabihf" /proc/cpuinfo; then
                        OS_ARCH="armv7-unknown-linux-gnueabihf"
                    else
                        OS_ARCH="arm-unknown-linux-gnueabi"
                    fi
                    ;;
                "armv6l")
                    OS_ARCH="arm-unknown-linux-gnueabi"
                    ;;
                "i686"|"i386")
                    OS_ARCH="i686-unknown-linux-musl"
                    ;;
                *)
                    error_exit "不支持的CPU架构: ${arch}"
                    ;;
            esac
            ;;
        *)
            error_exit "不支持的操作系统: ${os}"
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
Success="${Green_font_prefix}[成功]${Font_color_suffix}"

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

# 获取当前安装版本
get_current_version() {
    if [[ -f "${VERSION_FILE}" ]]; then
        current_ver=$(cat "${VERSION_FILE}")
        echo "${current_ver}"
    else
        echo "0.0.0"
    fi
}

# 版本号比较函数
version_compare() {
    local current=$1
    local latest=$2
    
    # 移除版本号中的 'v' 前缀
    current=${current#v}
    latest=${latest#v}
    
    if [[ "${current}" == "${latest}" ]]; then
        return 1  # 版本相同
    fi
    
    # 将版本号分割为数组
    IFS='.' read -r -a current_parts <<< "${current}"
    IFS='.' read -r -a latest_parts <<< "${latest}"
    
    # 比较每个部分
    for i in "${!current_parts[@]}"; do
        if [[ "${current_parts[$i]}" -lt "${latest_parts[$i]}" ]]; then
            return 0  # 当前版本低于最新版本
        elif [[ "${current_parts[$i]}" -gt "${latest_parts[$i]}" ]]; then
            return 1  # 当前版本高于最新版本
        fi
    done
    
    return 1
}

# 下载 Shadowsocks Rust
download_ss() {
    local version=$1
    local arch=$2
    local url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/v${version}"
    local filename=""

    case "${arch}" in
        # macOS 系统
        "aarch64-apple-darwin"|"x86_64-apple-darwin")
            filename="shadowsocks-v${version}.${arch}.tar.xz"
            ;;
        
        # Linux x86_64 系统
        "x86_64-unknown-linux-gnu"|"x86_64-unknown-linux-musl")
            filename="shadowsocks-v${version}.${arch}.tar.xz"
            ;;
        
        # Linux ARM 64位
        "aarch64-unknown-linux-gnu"|"aarch64-unknown-linux-musl")
            filename="shadowsocks-v${version}.${arch}.tar.xz"
            ;;
        
        # Linux ARM 32位
        "arm-unknown-linux-gnueabi"|"arm-unknown-linux-gnueabihf"|"arm-unknown-linux-musleabi"|"arm-unknown-linux-musleabihf")
            filename="shadowsocks-v${version}.${arch}.tar.xz"
            ;;
        
        # Linux ARMv7
        "armv7-unknown-linux-gnueabihf"|"armv7-unknown-linux-musleabihf")
            filename="shadowsocks-v${version}.${arch}.tar.xz"
            ;;
        
        # Linux i686
        "i686-unknown-linux-musl")
            filename="shadowsocks-v${version}.${arch}.tar.xz"
            ;;
        
        # Windows
        "x86_64-pc-windows-gnu")
            filename="shadowsocks-v${version}.${arch}.zip"
            ;;
        "x86_64-pc-windows-msvc")
            filename="shadowsocks-v${version}.${arch}.zip"
            ;;
            
        *)
            error_exit "不支持的系统架构: ${arch}"
            ;;
    esac
    
    echo -e "${INFO} 开始下载 Shadowsocks Rust ${version}..."
    echo -e "${INFO} 下载地址：${url}/${filename}"
    wget --no-check-certificate -N "${url}/${filename}"
    
    if [[ ! -e "${filename}" ]]; then
        error_exit "Shadowsocks Rust 下载失败！"
    fi
    
    # 根据文件扩展名选择解压方式
    if [[ "${filename}" == *.tar.xz ]]; then
        if ! tar -xf "${filename}"; then
            error_exit "Shadowsocks Rust 解压失败！"
        fi
    elif [[ "${filename}" == *.zip ]]; then
        if ! unzip -o "${filename}"; then
            error_exit "Shadowsocks Rust 解压失败！"
        fi
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

# 确保系统时间同步
# SS2022（2022-blake3 系列）协议校验时间戳，服务器与客户端时间误差超过 30 秒将无法连接
ensure_time_sync() {
    echo -e "${INFO} 检查系统时间同步（SS2022 协议要求时间误差在 30 秒内）..."

    # 已有 NTP 同步服务在运行则跳过
    if systemctl is-active chronyd >/dev/null 2>&1 || \
       systemctl is-active chrony >/dev/null 2>&1 || \
       systemctl is-active systemd-timesyncd >/dev/null 2>&1 || \
       systemctl is-active ntp >/dev/null 2>&1 || \
       systemctl is-active ntpd >/dev/null 2>&1; then
        echo -e "${INFO} 检测到 NTP 时间同步服务已在运行"
        return 0
    fi

    # 优先启用系统自带的 systemd-timesyncd
    if systemctl list-unit-files systemd-timesyncd.service 2>/dev/null | grep -q "systemd-timesyncd"; then
        if timedatectl set-ntp true 2>/dev/null || systemctl enable --now systemd-timesyncd 2>/dev/null; then
            echo -e "${SUCCESS} 已启用 systemd-timesyncd 时间同步"
            return 0
        fi
    fi

    # 回退：安装并启用 chrony
    echo -e "${INFO} 正在安装 chrony 时间同步服务..."
    if [[ ${OS_TYPE} == "centos" ]]; then
        $(rhel_pkg_mgr) install -y chrony || { echo -e "${WARNING} chrony 安装失败"; }
        systemctl enable --now chronyd 2>/dev/null || true
    else
        apt-get install -y chrony || { echo -e "${WARNING} chrony 安装失败"; }
        # Debian 服务名为 chrony，RHEL 系为 chronyd
        systemctl enable --now chrony 2>/dev/null || systemctl enable --now chronyd 2>/dev/null || true
    fi

    if systemctl is-active chronyd >/dev/null 2>&1 || systemctl is-active chrony >/dev/null 2>&1; then
        echo -e "${SUCCESS} chrony 时间同步已启用"
    else
        echo -e "${WARNING} 未能自动启用时间同步，请手动配置 NTP"
        echo -e "${WARNING} 使用 2022 系列加密时，若客户端无法连接请优先检查服务器时间是否准确"
    fi
    return 0
}

# 安装依赖
install_dependencies() {
    echo -e "${INFO} 开始安装系统依赖..."
    
    if [[ ${OS_TYPE} == "centos" ]]; then
        local pkg_mgr
        pkg_mgr=$(rhel_pkg_mgr)
        # qrencode 等包在 RHEL 系需要 EPEL 源
        ${pkg_mgr} install -y epel-release || echo -e "${WARNING} EPEL 源安装失败，qrencode 可能无法安装"
        ${pkg_mgr} install -y jq gzip wget curl unzip xz openssl tar || error_exit "系统依赖安装失败，请检查网络和软件源"
        ${pkg_mgr} install -y qrencode || echo -e "${WARNING} qrencode 安装失败，二维码功能不可用，不影响其他功能"
    else
        apt-get update
        apt-get install -y jq gzip wget curl unzip xz-utils openssl qrencode tar
    fi
    
    # 设置时区
    echo -e "${CYAN}正在设置时区...${RESET}"
    if [ -f "/usr/share/zoneinfo/Asia/Shanghai" ]; then
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        echo "Asia/Shanghai" > /etc/timezone
    else
        echo -e "${RED}时区文件不存在，跳过设置${RESET}"
    fi

    # 同步系统时间（仅设置时区不能保证时钟准确）
    ensure_time_sync

    echo -e "${SUCCESS} 系统依赖安装完成！"
}

# 写入配置文件（使用 jq 生成，保证 JSON 合法）
write_config() {
    mkdir -p "$(dirname "${CONFIG_PATH}")"
    if ! jq -n \
        --arg server "$(get_ss_listen_addr)" \
        --argjson port "${SS_PORT}" \
        --arg password "${SS_PASSWORD}" \
        --arg method "${SS_METHOD}" \
        --argjson tfo "${SS_TFO}" \
        --arg dns "${SS_DNS}" \
        --arg plugin "${SS_PLUGIN}" \
        --arg plugin_opts "${SS_PLUGIN_OPTS}" \
        '{server: $server, server_port: $port, password: $password, method: $method,
          fast_open: $tfo, mode: "tcp_and_udp", user: "nobody", timeout: 300}
         + (if $dns != "" then {nameserver: $dns} else {} end)
         + (if $plugin != "" then {plugin: $plugin, plugin_opts: $plugin_opts} else {} end)' \
        > "${CONFIG_PATH}"; then
        error_exit "配置文件写入失败！"
    fi
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
    SS_PLUGIN=$(jq -r '.plugin // empty' ${CONFIG_PATH})
    SS_PLUGIN_OPTS=$(jq -r '.plugin_opts // empty' ${CONFIG_PATH})
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
    
    # 检查 firewalld（RHEL 系默认防火墙）
    local firewalld_active=0
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewalld_active=1
        echo -e "${INFO} 检测到 firewalld 防火墙..."
        echo -e "${INFO} 正在将端口 ${port} 加入 firewalld 规则..."
        firewall-cmd --permanent --add-port=${port}/tcp >/dev/null 2>&1 || echo -e "${WARNING} firewalld TCP 规则添加失败"
        firewall-cmd --permanent --add-port=${port}/udp >/dev/null 2>&1 || echo -e "${WARNING} firewalld UDP 规则添加失败"
        firewall-cmd --reload >/dev/null 2>&1 || echo -e "${WARNING} firewalld 规则重载失败"
        echo -e "${SUCCESS} firewalld 端口开放完成！"
    fi

    # 检查 iptables（firewalld 已处理时跳过，避免规则冲突）
    if [[ ${firewalld_active} -eq 0 ]] && command -v iptables >/dev/null 2>&1; then
        echo -e "${INFO} 检测到 iptables 防火墙..."
        echo -e "${INFO} 正在将端口 ${port} 加入 iptables 规则..."
        iptables -I INPUT -p tcp --dport ${port} -j ACCEPT
        iptables -I INPUT -p udp --dport ${port} -j ACCEPT
        echo -e "${SUCCESS} iptables 端口开放完成！"

        # 保存 iptables 规则
        if [[ ${OS_TYPE} == "centos" ]]; then
            # RHEL 系默认没有 iptables-services，保存失败不影响本次会话的规则生效
            service iptables save 2>/dev/null || echo -e "${WARNING} iptables 规则保存失败（未安装 iptables-services），重启后需重新放行端口"
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

# 按加密方式生成符合密钥长度要求的随机密码
generate_password_for_method() {
    local method=$1
    case "${method}" in
        "2022-blake3-aes-128-gcm")
            # 16 字节密钥的 Base64 编码
            dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64 | tr -d '\n'
            ;;
        "2022-blake3-aes-256-gcm"|"2022-blake3-chacha20-poly1305"|"2022-blake3-chacha8-poly1305")
            # 32 字节密钥的 Base64 编码
            dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d '\n'
            ;;
        *)
            dd if=/dev/urandom bs=16 count=1 2>/dev/null | base64 | tr -d '\n'
            ;;
    esac
}

# 加密方式要求的密钥字节数（非 2022 系列返回空）
required_key_length() {
    local method=$1
    case "${method}" in
        "2022-blake3-aes-128-gcm") echo 16 ;;
        "2022-blake3-aes-256-gcm"|"2022-blake3-chacha20-poly1305"|"2022-blake3-chacha8-poly1305") echo 32 ;;
        *) echo "" ;;
    esac
}

# 获取 ss-rust 监听地址：无 IPv6 协议栈的机器监听 0.0.0.0，避免绑定 :: 失败
get_ss_listen_addr() {
    if [[ -f /proc/net/if_inet6 ]]; then
        echo "::"
    else
        echo "0.0.0.0"
    fi
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
    local required_len decoded_length
    required_len=$(required_key_length "${SS_METHOD}")

    while true; do
        echo "请输入 Shadowsocks Rust 密码 [0-9][a-z][A-Z]"
        if [[ -n "${required_len}" ]]; then
            echo -e "${Tip} 当前加密方式 ${SS_METHOD} 要求密码为 ${required_len} 字节密钥的 Base64 编码，建议直接回车随机生成"
        fi
        read -e -p "(默认：随机生成 Base64)：" SS_PASSWORD
        if [[ -z "${SS_PASSWORD}" ]]; then
            SS_PASSWORD=$(generate_password_for_method "${SS_METHOD}")
        fi

        # 2022-blake3 系列加密对密钥长度有硬性要求，不满足会导致服务启动失败
        if [[ -n "${required_len}" ]]; then
            decoded_length=$(echo -n "${SS_PASSWORD}" | base64 -d 2>/dev/null | wc -c)
            if [[ ${decoded_length} -ne ${required_len} ]]; then
                echo -e "${WARNING} 密码不符合要求：解码后为 ${decoded_length} 字节，需要 ${required_len} 字节"
                echo -e "${WARNING} 请重新输入，或直接回车由脚本自动生成合规密码"
                continue
            fi
        fi
        break
    done

    echo && echo "=================================="
    echo -e "密码：${Red_background_prefix} ${SS_PASSWORD} ${Font_color_suffix}"
    echo "==================================" && echo
}

# 设置加密方式
set_method() {
    echo -e "请选择 Shadowsocks Rust 加密方式
==================================	
 ${Green_font_prefix} 1.${Font_color_suffix} aes-128-gcm
 ${Green_font_prefix} 2.${Font_color_suffix} aes-256-gcm
 ${Green_font_prefix} 3.${Font_color_suffix} chacha20-ietf-poly1305
 ${Green_font_prefix} 4.${Font_color_suffix} plain
 ${Green_font_prefix} 5.${Font_color_suffix} none
 ${Green_font_prefix} 6.${Font_color_suffix} table
 ${Green_font_prefix} 7.${Font_color_suffix} aes-128-cfb
 ${Green_font_prefix} 8.${Font_color_suffix} aes-256-cfb
 ${Green_font_prefix} 9.${Font_color_suffix} aes-256-ctr 
 ${Green_font_prefix}10.${Font_color_suffix} camellia-256-cfb
 ${Green_font_prefix}11.${Font_color_suffix} rc4-md5
 ${Green_font_prefix}12.${Font_color_suffix} chacha20-ietf
==================================
 ${Tip} AEAD 2022 加密（使用随机加密）
==================================	
 ${Green_font_prefix}13.${Font_color_suffix} 2022-blake3-aes-128-gcm ${Green_font_prefix}(默认)${Font_color_suffix}
 ${Green_font_prefix}14.${Font_color_suffix} 2022-blake3-aes-256-gcm ${Green_font_prefix}(推荐)${Font_color_suffix}
 ${Green_font_prefix}15.${Font_color_suffix} 2022-blake3-chacha20-poly1305
 ${Green_font_prefix}16.${Font_color_suffix} 2022-blake3-chacha8-poly1305
=================================="
    
    read -e -p "(默认: 13. 2022-blake3-aes-128-gcm)：" method_choice
    [[ -z "${method_choice}" ]] && method_choice="13"
    
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
        *) SS_METHOD="2022-blake3-aes-128-gcm" ;;
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

# 安装 simple-obfs 混淆插件（提供 obfs-server 命令）
install_obfs_plugin() {
    if command -v obfs-server >/dev/null 2>&1; then
        echo -e "${INFO} 检测到已安装 obfs-server"
        return 0
    fi

    [[ -z "${OS_TYPE}" ]] && detect_os

    if [[ ${OS_TYPE} == "centos" ]]; then
        echo -e "${WARNING} RHEL 系（CentOS/AlmaLinux/Rocky）官方源没有 simple-obfs 软件包"
        echo -e "${WARNING} 请自行编译安装 obfs-server（https://github.com/shadowsocks/simple-obfs）后再启用该插件"
        return 1
    fi

    echo -e "${INFO} 正在安装 simple-obfs..."
    apt-get update
    if ! apt-get install -y simple-obfs; then
        echo -e "${WARNING} simple-obfs 安装失败，请检查软件源"
        return 1
    fi

    if ! command -v obfs-server >/dev/null 2>&1; then
        echo -e "${WARNING} 安装完成但未找到 obfs-server 命令"
        return 1
    fi
    return 0
}

# 设置混淆插件（obfs）
set_plugin() {
    echo -e "是否启用混淆插件（obfs）？
==================================
 ${Green_font_prefix}1.${Font_color_suffix} 不使用插件 ${Green_font_prefix}(默认)${Font_color_suffix}
 ${Green_font_prefix}2.${Font_color_suffix} simple-obfs (http 混淆)
 ${Green_font_prefix}3.${Font_color_suffix} simple-obfs (tls 混淆)
==================================
 ${Tip} 混淆插件主要用于兼容旧客户端，2022 系列加密本身已足够安全"
    read -e -p "(默认：1)：" plugin_choice
    [[ -z "${plugin_choice}" ]] && plugin_choice="1"

    case ${plugin_choice} in
        2)
            SS_PLUGIN="obfs-server"
            SS_PLUGIN_OPTS="obfs=http"
            ;;
        3)
            SS_PLUGIN="obfs-server"
            SS_PLUGIN_OPTS="obfs=tls"
            ;;
        *)
            SS_PLUGIN=""
            SS_PLUGIN_OPTS=""
            ;;
    esac

    if [[ -n "${SS_PLUGIN}" ]]; then
        if ! install_obfs_plugin; then
            echo -e "${WARNING} 插件不可用，本次不启用混淆插件"
            SS_PLUGIN=""
            SS_PLUGIN_OPTS=""
        fi
    fi

    echo && echo "=================================="
    if [[ -n "${SS_PLUGIN}" ]]; then
        echo -e "插件：${Red_background_prefix} ${SS_PLUGIN} (${SS_PLUGIN_OPTS}) ${Font_color_suffix}"
    else
        echo -e "插件：${Red_background_prefix} 不使用 ${Font_color_suffix}"
    fi
    echo "==================================" && echo
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
 ${Green_font_prefix}6.${Font_color_suffix}  修改 混淆插件配置
 ${Green_font_prefix}7.${Font_color_suffix}  修改 全部配置" && echo
    
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
            set_plugin
            write_config
            Restart
            ;;
        7)
            read_config
            set_port
            set_method
            set_password
            set_tfo
            set_dns
            set_plugin
            write_config
            Restart
            ;;
        *)
            echo -e "${Error} 请输入正确的数字(1-7)"
            sleep 2s
            modify_config
            ;;
    esac
}

# 安装
Install() {
    [[ -e ${BINARY_PATH} ]] && echo -e "${Error} 检测到 Shadowsocks Rust 已安装！" && exit 1
    
    echo -e "${Info} 检测系统信息..."
    detect_os
    
    echo -e "${Info} 开始设置配置..."
    set_port
    set_method
    set_password
    set_tfo
    set_dns
    set_plugin

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

    echo -e "${Info} 创建命令快捷方式..."
    curl -L -s ss.jinqians.com -o "/usr/local/bin/ss-2022.sh"
    chmod +x "/usr/local/bin/ss-2022.sh"
    if [ -f "/usr/local/bin/ssrust" ]; then
        rm -f "/usr/local/bin/ssrust"
    fi
    ln -s "/usr/local/bin/ss-2022.sh" "/usr/local/bin/ssrust"
    
    echo -e "${Info} 所有步骤安装完毕，开始启动服务..."
    start_service
    
    if [[ "$?" == "0" ]]; then
        echo -e "${Success} Shadowsocks Rust 安装并启动成功！"
        View
        echo -e "${Info} 您可以使用 ${Green_font_prefix}ssrust${Font_color_suffix} 命令进行管理"
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
    
    # 获取当前版本
    current_ver=$(get_current_version)
    echo -e "${Info} 当前版本: [ ${current_ver} ]"
    
    # 获取最新版本
    check_new_ver
    
    # 比较版本
    if version_compare "${current_ver}" "${new_ver}"; then
        echo -e "${Info} 发现新版本 [ ${new_ver} ]"
        echo -e "${Info} 是否更新？[Y/n]"
        read -p "(默认: y)：" yn
        [[ -z "${yn}" ]] && yn="y"
        if [[ ${yn} == [Yy] ]]; then
            echo -e "${Info} 开始更新 Shadowsocks Rust..."
            detect_arch
            download_ss "${new_ver#v}" "${OS_ARCH}"
            systemctl restart ss-rust
            echo -e "${Success} Shadowsocks Rust 已更新到最新版本 [ ${new_ver} ]"
        else
            echo -e "${Info} 已取消更新"
        fi
    else
        echo -e "${Info} 当前已是最新版本 [ ${new_ver} ]，无需更新"
    fi
    
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

        # 清理多端口节点服务
        local extra_service
        for extra_service in /etc/systemd/system/ss-rust-*.service; do
            [[ -f "${extra_service}" ]] || continue
            local svc_name=$(basename "${extra_service}" .service)
            systemctl stop "${svc_name}" 2>/dev/null || true
            systemctl disable "${svc_name}" 2>/dev/null || true
            rm -f "${extra_service}"
        done
        systemctl daemon-reload

        rm -rf "${INSTALL_DIR}"
        rm -rf "${BINARY_PATH}"
        rm -f "/usr/local/bin/ssrust"
        rm -f "/usr/local/bin/ss-2022.sh"
        echo && echo "Shadowsocks Rust 卸载完成！" && echo
    else
        echo && echo "卸载已取消..." && echo
    fi
}

# 获取IPv4地址
getipv4() {
    set +e
    ipv4=$(curl -m 2 -s4 https://api.ipify.org)
    if [[ -z "${ipv4}" ]]; then
        ipv4="IPv4_Error"
    fi
    set -e
}

# 获取IPv6地址
getipv6() {
    set +e
    ipv6=$(curl -m 2 -s6 https://api64.ipify.org)
    if [[ -z "${ipv6}" ]]; then
        ipv6="IPv6_Error"
    fi
    set -e
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
    getipv4
    getipv6
    
    # 新增：如果 IPv4 和 IPv6 都获取失败，直接报错退出
    if [[ "${ipv4}" == "IPv4_Error" && "${ipv6}" == "IPv6_Error" ]]; then
        echo -e "${Error} 无法获取 IPv4 或 IPv6 地址，无法输出配置信息！"
        return 1
    fi
    
    # 从配置文件读取信息
    if [[ -f "${CONFIG_PATH}" ]]; then
        local config_port=$(jq -r '.server_port' "${CONFIG_PATH}")
        local config_password=$(jq -r '.password' "${CONFIG_PATH}")
        local config_method=$(jq -r '.method' "${CONFIG_PATH}")
        local config_tfo=$(jq -r '.fast_open' "${CONFIG_PATH}")
        local config_dns=$(jq -r '.nameserver // empty' "${CONFIG_PATH}")
        local config_plugin=$(jq -r '.plugin // empty' "${CONFIG_PATH}")
        local config_plugin_opts=$(jq -r '.plugin_opts // empty' "${CONFIG_PATH}")

        # 修复：赋值给全局变量，保证后续二维码/链接等输出正常
        SS_PORT="$config_port"
        SS_PASSWORD="$config_password"
        SS_METHOD="$config_method"
        SS_TFO="$config_tfo"
        SS_DNS="$config_dns"
        SS_PLUGIN="$config_plugin"
        SS_PLUGIN_OPTS="$config_plugin_opts"

        echo -e "Shadowsocks Rust 配置："
        echo -e "——————————————————————————————————"
        [[ "${ipv4}" != "IPv4_Error" ]] && echo -e " 地址：${Green_font_prefix}${ipv4}${Font_color_suffix}"
        [[ "${ipv6}" != "IPv6_Error" ]] && echo -e " 地址：${Green_font_prefix}${ipv6}${Font_color_suffix}"
        echo -e " 端口：${Green_font_prefix}${config_port}${Font_color_suffix}"
        echo -e " 密码：${Green_font_prefix}${config_password}${Font_color_suffix}"
        echo -e " 加密：${Green_font_prefix}${config_method}${Font_color_suffix}"
        echo -e " TFO ：${Green_font_prefix}${config_tfo}${Font_color_suffix}"
        [[ ! -z "${config_dns}" ]] && echo -e " DNS ：${Green_font_prefix}${config_dns}${Font_color_suffix}"
        [[ ! -z "${config_plugin}" ]] && echo -e " 插件：${Green_font_prefix}${config_plugin} (${config_plugin_opts})${Font_color_suffix}"
        echo -e "——————————————————————————————————"
    else
        echo -e "${Error} 配置文件不存在！"
        return 1
    fi

    # 生成 SS 链接（SIP002 格式，启用混淆插件时附带 plugin 参数）
    local userinfo=$(echo -n "${config_method}:${config_password}" | base64 -w 0)
    local ss_url_ipv4=""
    local ss_url_ipv6=""
    local plugin_param=""
    local obfs_mode=""

    if [[ -n "${config_plugin}" ]]; then
        obfs_mode="${config_plugin_opts#obfs=}"
        obfs_mode="${obfs_mode%%;*}"
        # 客户端插件名为 obfs-local；分号/等号需 URL 编码
        plugin_param="/?plugin=obfs-local%3Bobfs%3D${obfs_mode}"
    fi

    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        ss_url_ipv4="ss://${userinfo}@${ipv4}:${config_port}${plugin_param}#SS-${ipv4}"
    fi
    if [[ "${ipv6}" != "IPv6_Error" ]]; then
        ss_url_ipv6="ss://${userinfo}@${ipv6}:${config_port}${plugin_param}#SS-${ipv6}"
    fi

    echo -e "\n${Yellow_font_prefix}=== Shadowsocks 链接 ===${Font_color_suffix}"
    [[ ! -z "${ss_url_ipv4}" ]] && echo -e "${Green_font_prefix}IPv4 链接：${Font_color_suffix}${ss_url_ipv4}"
    [[ ! -z "${ss_url_ipv6}" ]] && echo -e "${Green_font_prefix}IPv6 链接：${Font_color_suffix}${ss_url_ipv6}"

    echo -e "\n${Yellow_font_prefix}=== Shadowsocks 二维码 ===${Font_color_suffix}"
    if command -v qrencode &> /dev/null; then
        if [[ ! -z "${ss_url_ipv4}" ]]; then
            echo -e "${Green_font_prefix}IPv4 二维码：${Font_color_suffix}"
            echo "${ss_url_ipv4}" | qrencode -t UTF8
        fi
        if [[ ! -z "${ss_url_ipv6}" ]]; then
            echo -e "${Green_font_prefix}IPv6 二维码：${Font_color_suffix}"
            echo "${ss_url_ipv6}" | qrencode -t UTF8
        fi
    else
        echo -e "${Red_font_prefix}未安装 qrencode，无法生成二维码${Font_color_suffix}"
    fi

    echo -e "\n${Yellow_font_prefix}=== Surge 配置 ===${Font_color_suffix}"
    local surge_obfs=""
    [[ -n "${obfs_mode}" ]] && surge_obfs=", obfs=${obfs_mode}"
    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        echo -e "SS-${ipv4} = ss, ${ipv4}, ${config_port}, encrypt-method=${config_method}, password=${config_password}, tfo=${config_tfo}, udp-relay=true${surge_obfs}"
    fi
    if [[ "${ipv6}" != "IPv6_Error" ]]; then
        echo -e "SS-${ipv6} = ss, ${ipv6}, ${config_port}, encrypt-method=${config_method}, password=${config_password}, tfo=${config_tfo}, udp-relay=true${surge_obfs}"
    fi

    # 检查 ShadowTLS 是否安装并获取配置
    if [ -f "/etc/systemd/system/shadowtls-ss.service" ]; then
        # 解析监听端口：兼容任意监听地址（::0 / 0.0.0.0 / 手动修改过的地址）
        local stls_listen_addr=$(grep -oP '(?<=--listen )\S+' /etc/systemd/system/shadowtls-ss.service | head -1)
        local stls_listen_port="${stls_listen_addr##*:}"
        local stls_password=$(grep -oP '(?<=--password )\S+' /etc/systemd/system/shadowtls-ss.service)
        local stls_sni=$(grep -oP '(?<=--tls )\S+' /etc/systemd/system/shadowtls-ss.service)

        echo -e "\n${Yellow_font_prefix}=== ShadowTLS 配置 ===${Font_color_suffix}"
        echo -e " 监听端口：${Green_font_prefix}${stls_listen_port}${Font_color_suffix}"
        echo -e " 密码：${Green_font_prefix}${stls_password}${Font_color_suffix}"
        echo -e " SNI：${Green_font_prefix}${stls_sni}${Font_color_suffix}"
        echo -e " 版本：3"

        # 生成 SS + ShadowTLS 合并链接
        local shadow_tls_config="{\"version\":\"3\",\"password\":\"${stls_password}\",\"host\":\"${stls_sni}\",\"port\":\"${stls_listen_port}\",\"address\":\"${ipv4}\"}"
        local shadow_tls_base64=$(echo -n "${shadow_tls_config}" | base64 -w 0)
        local ss_stls_url="ss://${userinfo}@${ipv4}:${config_port}?shadow-tls=${shadow_tls_base64}#SS-${ipv4}"

        echo -e "\n${Yellow_font_prefix}=== SS + ShadowTLS 链接 ===${Font_color_suffix}"
        [[ "${ipv4}" != "IPv4_Error" ]] && echo -e "${Green_font_prefix}合并链接：${Font_color_suffix}${ss_stls_url}"

        echo -e "\n${Yellow_font_prefix}=== SS + ShadowTLS 二维码 ===${Font_color_suffix}"
        if command -v qrencode &> /dev/null; then
            [[ "${ipv4}" != "IPv4_Error" ]] && echo "${ss_stls_url}" | qrencode -t UTF8
        else
            echo -e "${Red_font_prefix}未安装 qrencode，无法生成二维码${Font_color_suffix}"
        fi

        echo -e "\n${Yellow_font_prefix}=== Surge Shadowsocks + ShadowTLS 配置 ===${Font_color_suffix}"
        if [[ "${ipv4}" != "IPv4_Error" ]]; then
            echo -e "SS-${ipv4} = ss, ${ipv4}, ${stls_listen_port}, encrypt-method=${config_method}, password=${config_password}, shadow-tls-password=${stls_password}, shadow-tls-sni=${stls_sni}, shadow-tls-version=3, udp-relay=true"
        fi
        if [[ "${ipv6}" != "IPv6_Error" ]]; then
            echo -e "SS-${ipv6} = ss, ${ipv6}, ${stls_listen_port}, encrypt-method=${config_method}, password=${config_password}, shadow-tls-password=${stls_password}, shadow-tls-sni=${stls_sni}, shadow-tls-version=3, udp-relay=true"
        fi
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
    
    # 获取最新版本号（修复版本号提取）
    sh_new_ver=$(grep -m1 '^SCRIPT_VERSION=' ${temp_file} | cut -d'"' -f2)
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

# 安装 ShadowTLS
install_shadowtls() {
    echo -e "${Info} 开始下载 ShadowTLS 安装脚本..."
    
    # 下载 ShadowTLS 脚本
    wget -N --no-check-certificate https://raw.githubusercontent.com/jinqians/ss-2022.sh/refs/heads/main/shadowtls.sh
    
    if [ $? -ne 0 ]; then
        echo -e "${Error} ShadowTLS 脚本下载失败！"
        return 1
    fi
    
    # 添加执行权限
    chmod +x shadowtls.sh
    
    echo -e "${Info} 开始安装 ShadowTLS..."
    
    # 执行 ShadowTLS 安装脚本
    bash shadowtls.sh
    
    # 清理下载的脚本
    rm -f shadowtls.sh
    
    Before_Start_Menu
}

# 部署中国大陆IP屏蔽脚本
install_mainland_block_scripts() {
    local local_block_script="${SCRIPT_PATH}/block-mainland.sh"
    local local_extract_script="${SCRIPT_PATH}/extract-cn-ip-from-mmdb.py"

    echo -e "${Info} 准备部署中国大陆IP屏蔽脚本..."

    if [[ -f "${local_block_script}" ]]; then
        cp -f "${local_block_script}" "${MAINLAND_BLOCK_SCRIPT}"
    else
        wget --no-check-certificate -O "${MAINLAND_BLOCK_SCRIPT}" "${MAINLAND_BLOCK_REPO_URL}"
    fi

    if [[ -f "${local_extract_script}" ]]; then
        cp -f "${local_extract_script}" "${MAINLAND_EXTRACT_SCRIPT}"
    else
        wget --no-check-certificate -O "${MAINLAND_EXTRACT_SCRIPT}" "${MAINLAND_EXTRACT_REPO_URL}"
    fi

    if [[ ! -s "${MAINLAND_BLOCK_SCRIPT}" || ! -s "${MAINLAND_EXTRACT_SCRIPT}" ]]; then
        echo -e "${Error} 大陆IP屏蔽脚本部署失败，请检查网络或仓库文件"
        return 1
    fi

    chmod +x "${MAINLAND_BLOCK_SCRIPT}" "${MAINLAND_EXTRACT_SCRIPT}"
    echo -e "${Success} 大陆IP屏蔽脚本部署完成"
    return 0
}

run_mainland_block_cmd() {
    local cmd="$1"

    if [[ ! -x "${MAINLAND_BLOCK_SCRIPT}" ]]; then
        echo -e "${Error} 未找到可执行脚本：${MAINLAND_BLOCK_SCRIPT}"
        return 1
    fi

    if [[ -n "${cmd}" ]]; then
        PYTHONIOENCODING=UTF-8 LC_ALL=C.UTF-8 LANG=C.UTF-8 bash "${MAINLAND_BLOCK_SCRIPT}" "${cmd}"
    else
        PYTHONIOENCODING=UTF-8 LC_ALL=C.UTF-8 LANG=C.UTF-8 bash "${MAINLAND_BLOCK_SCRIPT}"
    fi
}

# 中国大陆IP屏蔽菜单
mainland_block_menu() {
    check_installed_status || return 1

    if ! install_mainland_block_scripts; then
        Before_Start_Menu
        return 1
    fi

    while true; do
        clear
        echo -e "${GREEN}============================================${RESET}"
        echo -e "${GREEN}        中国大陆IP屏蔽管理 ${RESET}"
        echo -e "${GREEN}============================================${RESET}"
        echo -e " ${Green_font_prefix}1.${Font_color_suffix} 初始化并启用屏蔽"
        echo -e " ${Green_font_prefix}2.${Font_color_suffix} 更新中国大陆IP库"
        echo -e " ${Green_font_prefix}3.${Font_color_suffix} 查看屏蔽状态"
        echo -e " ${Green_font_prefix}4.${Font_color_suffix} 禁用屏蔽规则"
        echo -e " ${Green_font_prefix}5.${Font_color_suffix} 进入高级菜单"
        echo -e " ${Green_font_prefix}0.${Font_color_suffix} 返回上一级"
        echo -e "${GREEN}============================================${RESET}"
        echo

        read -e -p " 请输入数字 [0-5]：" mainland_num
        case "${mainland_num}" in
            1)
                if run_mainland_block_cmd "enable"; then
                    echo -e "${Success} 大陆IP屏蔽启用完成"
                else
                    echo -e "${Error} 大陆IP屏蔽启用失败"
                fi
                ;;
            2)
                if run_mainland_block_cmd "update"; then
                    echo -e "${Success} 大陆IP库更新完成"
                else
                    echo -e "${Error} 大陆IP库更新失败"
                fi
                ;;
            3)
                run_mainland_block_cmd "status" || echo -e "${Error} 状态查询失败"
                ;;
            4)
                if run_mainland_block_cmd "disable"; then
                    echo -e "${Success} 大陆IP屏蔽已禁用"
                else
                    echo -e "${Error} 禁用失败"
                fi
                ;;
            5)
                run_mainland_block_cmd
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${Error} 请输入正确数字 [0-5]"
                ;;
        esac

        echo && echo -n -e "${Yellow_font_prefix}* 按回车返回此菜单 *${Font_color_suffix}" && read temp
    done
}

# ========== 多端口节点管理 ==========
# 每个额外端口使用独立的配置文件和 systemd 服务（ss-rust-<端口>），互不影响

# 检查端口是否已被系统占用
port_in_use() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -Eq "[:.]${port}([^0-9]|$)" && return 0
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -Eq "[:.]${port}([^0-9]|$)" && return 0
    fi
    return 1
}

# 新增端口节点
add_extra_port() {
    read_config
    mkdir -p "${PORTS_DIR}"

    echo -e "${Tip} 新节点将沿用主配置的加密方式（${SS_METHOD}）、TFO、DNS 与插件设置"

    # 端口
    local main_port="${SS_PORT}"
    local new_port input_port
    while true; do
        new_port=$(generate_random_port)
        read -e -p "请输入新节点端口 [1-65535]（直接回车使用随机端口 ${new_port}）：" input_port
        [[ -n "${input_port}" ]] && new_port="${input_port}"
        if ! [[ ${new_port} =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
            echo -e "${Error} 端口必须是 1-65535 之间的数字"
            continue
        fi
        if [[ "${new_port}" == "${main_port}" || -f "${PORTS_DIR}/${new_port}.json" ]]; then
            echo -e "${Error} 端口 ${new_port} 已被本脚本的节点使用"
            continue
        fi
        if port_in_use "${new_port}"; then
            echo -e "${Error} 端口 ${new_port} 已被其他服务占用"
            continue
        fi
        break
    done

    # 密码：默认随机生成，自定义时按加密方式校验密钥长度
    local new_password required_len decoded_len
    required_len=$(required_key_length "${SS_METHOD}")
    while true; do
        read -e -p "请输入新节点密码（直接回车随机生成）：" new_password
        [[ -z "${new_password}" ]] && new_password=$(generate_password_for_method "${SS_METHOD}")
        if [[ -n "${required_len}" ]]; then
            decoded_len=$(echo -n "${new_password}" | base64 -d 2>/dev/null | wc -c)
            if [[ ${decoded_len} -ne ${required_len} ]]; then
                echo -e "${WARNING} 密码需为 ${required_len} 字节密钥的 Base64 编码（当前解码后 ${decoded_len} 字节），请重新输入或直接回车随机生成"
                continue
            fi
        fi
        break
    done

    # 写节点配置
    local node_config="${PORTS_DIR}/${new_port}.json"
    if ! jq -n \
        --arg server "$(get_ss_listen_addr)" \
        --argjson port "${new_port}" \
        --arg password "${new_password}" \
        --arg method "${SS_METHOD}" \
        --argjson tfo "${SS_TFO}" \
        --arg dns "${SS_DNS}" \
        --arg plugin "${SS_PLUGIN}" \
        --arg plugin_opts "${SS_PLUGIN_OPTS}" \
        '{server: $server, server_port: $port, password: $password, method: $method,
          fast_open: $tfo, mode: "tcp_and_udp", user: "nobody", timeout: 300}
         + (if $dns != "" then {nameserver: $dns} else {} end)
         + (if $plugin != "" then {plugin: $plugin, plugin_opts: $plugin_opts} else {} end)' \
        > "${node_config}"; then
        rm -f "${node_config}"
        echo -e "${Error} 节点配置写入失败！"
        return 1
    fi

    # 创建独立 systemd 服务
    cat > "/etc/systemd/system/ss-rust-${new_port}.service" << EOF
[Unit]
Description=Shadowsocks Rust Service (Port ${new_port})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${BINARY_PATH} -c ${node_config}
Restart=on-failure
RestartSec=3s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "ss-rust-${new_port}" >/dev/null 2>&1 || true
    systemctl restart "ss-rust-${new_port}" || true
    sleep 2

    if ! systemctl is-active "ss-rust-${new_port}" >/dev/null 2>&1; then
        echo -e "${Error} 节点服务启动失败！最近日志："
        journalctl --no-pager -n 20 -u "ss-rust-${new_port}" 2>/dev/null || true
        return 1
    fi

    check_firewall "${new_port}"

    echo -e "${SUCCESS} 新节点已创建并启动！"
    echo -e "——————————————————————————————————"
    echo -e " 端口：${Green_font_prefix}${new_port}${Font_color_suffix}"
    echo -e " 密码：${Green_font_prefix}${new_password}${Font_color_suffix}"
    echo -e " 加密：${Green_font_prefix}${SS_METHOD}${Font_color_suffix}"
    echo -e "——————————————————————————————————"
    getipv4
    if [[ "${ipv4}" != "IPv4_Error" ]]; then
        local node_userinfo=$(echo -n "${SS_METHOD}:${new_password}" | base64 -w 0)
        echo -e " 链接：${Green_font_prefix}ss://${node_userinfo}@${ipv4}:${new_port}#SS-${ipv4}-${new_port}${Font_color_suffix}"
    fi
}

# 查看所有端口节点
list_extra_ports() {
    read_config
    getipv4

    echo -e "\n${Yellow_font_prefix}=== 端口节点列表 ===${Font_color_suffix}"
    echo -e "${Green_font_prefix}[主节点]${Font_color_suffix} 端口：${SS_PORT}  加密：${SS_METHOD}  密码：${SS_PASSWORD}"

    local found=0 f port password method node_status
    for f in "${PORTS_DIR}"/*.json; do
        [[ -f "$f" ]] || continue
        found=1
        port=$(jq -r '.server_port' "$f")
        password=$(jq -r '.password' "$f")
        method=$(jq -r '.method' "$f")
        if systemctl is-active "ss-rust-${port}" >/dev/null 2>&1; then
            node_status="${Green_font_prefix}运行中${Font_color_suffix}"
        else
            node_status="${Red_font_prefix}未运行${Font_color_suffix}"
        fi
        echo -e "${Green_font_prefix}[额外节点]${Font_color_suffix} 端口：${port}  加密：${method}  密码：${password}  状态：${node_status}"
        if [[ "${ipv4}" != "IPv4_Error" ]]; then
            local node_userinfo=$(echo -n "${method}:${password}" | base64 -w 0)
            echo -e "    链接：ss://${node_userinfo}@${ipv4}:${port}#SS-${ipv4}-${port}"
        fi
    done

    [[ ${found} -eq 0 ]] && echo -e "${Tip} 暂无额外端口节点，可通过\"新增端口节点\"创建"
    echo -e "——————————————————————————————————"
}

# 删除端口节点
delete_extra_port() {
    local ports=() f
    for f in "${PORTS_DIR}"/*.json; do
        [[ -f "$f" ]] || continue
        ports+=("$(basename "$f" .json)")
    done

    if [[ ${#ports[@]} -eq 0 ]]; then
        echo -e "${Tip} 暂无可删除的额外端口节点"
        return 0
    fi

    echo -e "当前额外端口节点：${Green_font_prefix}${ports[*]}${Font_color_suffix}"
    read -e -p "请输入要删除的端口（默认取消）：" del_port
    [[ -z "${del_port}" ]] && echo "已取消..." && return 0

    if [[ ! -f "${PORTS_DIR}/${del_port}.json" ]]; then
        echo -e "${Error} 端口 ${del_port} 不是本脚本管理的额外节点"
        return 1
    fi

    systemctl stop "ss-rust-${del_port}" 2>/dev/null || true
    systemctl disable "ss-rust-${del_port}" 2>/dev/null || true
    rm -f "/etc/systemd/system/ss-rust-${del_port}.service"
    rm -f "${PORTS_DIR}/${del_port}.json"
    systemctl daemon-reload
    echo -e "${SUCCESS} 端口节点 ${del_port} 已删除（防火墙放行规则未回收，如需请手动删除）"
}

# 多端口管理菜单
multiport_menu() {
    check_installed_status || return 1
    while true; do
        echo -e "
${CYAN}多端口节点管理${RESET}
==================================
 ${Green_font_prefix}1.${Font_color_suffix} 新增端口节点
 ${Green_font_prefix}2.${Font_color_suffix} 查看端口节点
 ${Green_font_prefix}3.${Font_color_suffix} 删除端口节点
 ${Green_font_prefix}0.${Font_color_suffix} 返回主菜单
=================================="
        read -e -p " 请输入数字 [0-3]：" mp_choice
        case "${mp_choice}" in
            1) add_extra_port ;;
            2) list_extra_ports ;;
            3) delete_extra_port ;;
            0) return 0 ;;
            *) echo -e "${Error} 请输入正确数字 [0-3]" ;;
        esac
        echo && echo -n -e "${Yellow_font_prefix}* 按回车返回多端口菜单 *${Font_color_suffix}" && read temp
    done
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
        detect_os
        action=${1:-}
    echo -e "${GREEN}============================================${RESET}"
    echo -e "${GREEN}          SS - 2022 管理脚本 ${RESET}"
    echo -e "${GREEN}============================================${RESET}"
    echo -e "${GREEN}            作者: jinqian${RESET}"
    echo -e "${GREEN}       网站：https://jinqians.com${RESET}"
    echo -e "${GREEN}============================================${RESET}"
        echo && echo -e "  
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
 ${Green_font_prefix}10.${Font_color_suffix} 安装 ShadowTLS
 ${Green_font_prefix}11.${Font_color_suffix} 多端口管理
 ${Green_font_prefix}12.${Font_color_suffix} 中国大陆IP屏蔽
 ${Green_font_prefix}13.${Font_color_suffix} 退出脚本
——————————————————————————————————
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
        read -e -p " 请输入数字 [0-13]：" num
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
                install_shadowtls
                ;;
            11)
                multiport_menu
                ;;
            12)
                mainland_block_menu
                ;;
            13)
                echo -e "${Info} 退出脚本..."
                exit 0
                ;;
            *)
                echo -e "${Error} 请输入正确数字 [0-13]"
                sleep 2
                ;;
        esac
    done
}

# 启动脚本
Start_Menu "$@"
