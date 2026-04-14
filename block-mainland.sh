#!/usr/bin/env bash
set -e

# =========================================
# 作者: jinqians
# 日期: 2025年4月
# 描述: 屏蔽中国大陆连接 Shadowsocks Rust 脚本
# =========================================

# 版本信息
SCRIPT_VERSION="1.0"

# 脚本路径
SCRIPT_PATH=$(cd "$(dirname "$0")"; pwd)
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
SCRIPT_NAME=$(basename "$0")
SCRIPT_FULL_PATH="$(cd "$(dirname "$0")"; pwd)/$(basename "$0")"

# 配置路径
INSTALL_DIR="/etc/ss-rust"
CONFIG_PATH="/etc/ss-rust/config.json"
IPLIST_DIR="/etc/ss-rust/iprules"
MAINLAND_IP_FILE="${IPLIST_DIR}/mainland_cn.txt"
MMDB_FILE="${IPLIST_DIR}/Country.mmdb"
IPTABLES_RULES="/etc/ss-rust/mainland_cn_rules.sh"
EXTRACT_SCRIPT="$(cd "$(dirname "$0")"; pwd)/extract-cn-ip-from-mmdb.py"
AUTO_UPDATE_CRON_FILE="/etc/cron.d/block-mainland-auto-update"
AUTO_UPDATE_LOG_FILE="/var/log/block-mainland-update.log"
DAILY_CRON_EXPR="30 4 * * *"
WEEKLY_CRON_EXPR="30 4 * * 1"

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

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${ERROR} 此脚本需要root权限运行"
        exit 1
    fi
}

# 检查依赖
check_dependencies() {
    echo -e "${INFO} 检查依赖..."
    
    local missing_deps=()
    local missing_python=false
    
    # 检查必需的工具
    for cmd in curl iptables python3; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${WARNING} 缺少依赖: ${missing_deps[*]}"
        echo -e "${INFO} 正在安装依赖..."
        
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y "${missing_deps[@]}"
        elif command -v yum &> /dev/null; then
            yum install -y "${missing_deps[@]}"
        else
            echo -e "${ERROR} 无法自动安装依赖，请手动安装后重试"
            exit 1
        fi
    fi
    
    # 检查pip
    echo -e "${INFO} 检查pip..."
    if ! python3 -m pip --version &>/dev/null; then
        echo -e "${WARNING} pip未安装，正在安装..."
        if command -v apt-get &> /dev/null; then
            apt-get install -y python3-pip
        elif command -v yum &> /dev/null; then
            yum install -y python3-pip
        fi
    fi
    
    # 检查Python maxminddb库
    echo -e "${INFO} 检查Python maxminddb库..."
    if ! python3 -c "import maxminddb" 2>/dev/null; then
        echo -e "${WARNING} 缺少Python库: maxminddb"
        echo -e "${INFO} 正在安装依赖..."
        
        # 先尝试用系统包管理器安装
        if command -v apt-get &> /dev/null; then
            if apt-cache search python3-maxminddb | grep -q python3-maxminddb; then
                echo -e "${INFO} 通过apt安装maxminddb..."
                apt-get install -y python3-maxminddb 2>/dev/null && echo -e "${SUCCESS} maxminddb库安装成功" && return 0 || true
            fi
            
            # 否则安装编译依赖然后用pip
            echo -e "${INFO} 安装编译依赖..."
            apt-get install -y python3-dev build-essential 2>/dev/null || true
        elif command -v yum &> /dev/null; then
            echo -e "${INFO} 安装编译依赖..."
            yum install -y python3-devel gcc 2>/dev/null || true
        fi
        
        # 用pip安装，添加--break-system-packages标志（用于Debian系统）
        echo -e "${INFO} 安装maxminddb库..."
        python3 -m pip install --break-system-packages maxminddb 2>&1 | tail -5 && echo -e "${SUCCESS} maxminddb库安装成功" || echo -e "${WARNING} maxminddb库安装可能失败，请手动检查Python环境"
    fi
    
    echo -e "${SUCCESS} 依赖检查完成"
}

# 创建必要的目录
create_directories() {
    echo -e "${INFO} 创建必要的目录..."
    
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR"
    fi
    
    if [ ! -d "$IPLIST_DIR" ]; then
        mkdir -p "$IPLIST_DIR"
    fi
    
    echo -e "${SUCCESS} 目录创建完成"
}

# 下载MaxMind GeoIP2数据库文件
download_maxmind_mmdb() {
    echo -e "${INFO} 正在下载MaxMind GeoIP2数据库..."
    
    local mmdb_url="https://github.com/Hackl0us/GeoIP2-CN/raw/release/Country.mmdb"
    
    echo -e "${INFO} 从 $mmdb_url 下载..."
    
    if curl -L -s "$mmdb_url" -o "$MMDB_FILE" 2>/dev/null && [ -s "$MMDB_FILE" ]; then
        local file_size=$(du -h "$MMDB_FILE" | cut -f1)
        echo -e "${SUCCESS} mmdb文件下载成功 (大小: $file_size)"
        return 0
    else
        echo -e "${ERROR} 无法下载mmdb文件"
        return 1
    fi
}

# 从MaxMind mmdb文件提取中国IP CIDR
extract_china_ip_from_mmdb() {
    echo -e "${INFO} 正在从mmdb文件提取中国IP段..."
    
    if [ ! -f "$MMDB_FILE" ]; then
        echo -e "${ERROR} mmdb文件不存在: $MMDB_FILE"
        return 1
    fi
    
    if [ ! -f "$EXTRACT_SCRIPT" ]; then
        echo -e "${ERROR} 提取脚本不存在: $EXTRACT_SCRIPT"
        return 1
    fi
    
    # 先检查maxminddb库是否真的可用
    if ! python3 -c "import maxminddb" 2>/dev/null; then
        echo -e "${ERROR} maxminddb库不可用，跳过mmdb提取"
        return 1
    fi
    
    # 运行Python脚本提取CIDR
    local output=$(PYTHONIOENCODING=UTF-8 LC_ALL=C.UTF-8 LANG=C.UTF-8 python3 "$EXTRACT_SCRIPT" "$MMDB_FILE" "$MAINLAND_IP_FILE" 2>&1)
    
    if [ -f "$MAINLAND_IP_FILE" ]; then
        local ip_count=$(wc -l < "$MAINLAND_IP_FILE" 2>/dev/null || echo 0)
        if [ "$ip_count" -gt 100 ]; then
            echo -e "${SUCCESS} 已提取 $ip_count 个中国IP CIDR段"
            return 0
        fi
    fi
    
    echo -e "${ERROR} IP段提取失败或数据不足"
    echo -e "${INFO} 详细信息: $output"
    return 1
}



# 下载中国大陆IP列表（仅使用MaxMind）
download_mainland_ip_list() {
    echo -e "${INFO} 正在从MaxMind GeoIP2数据库提取中国IP列表..."
    
    # 下载并提取MaxMind mmdb文件
    if download_maxmind_mmdb && extract_china_ip_from_mmdb; then
        return 0
    else
        echo -e "${ERROR} 无法获取MaxMind数据，请检查网络连接或手动下载mmdb文件"
        return 1
    fi
}

# 检测SS-Rust端口（兼容空格、不同JSON结构）
detect_ss_port() {
    local default_port="8388"
    local ss_port=""

    if [ ! -f "$CONFIG_PATH" ]; then
        echo "$default_port"
        return 0
    fi

    # 优先用Python解析JSON，避免grep受格式影响
    ss_port=$(python3 - "$CONFIG_PATH" << 'PY'
import json
import sys

cfg_path = sys.argv[1]

def print_port(value):
    if isinstance(value, int) and 1 <= value <= 65535:
        print(value)
        return True
    if isinstance(value, str) and value.isdigit():
        num = int(value)
        if 1 <= num <= 65535:
            print(num)
            return True
    return False

try:
    with open(cfg_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
except Exception:
    print("")
    raise SystemExit(0)

# 常见单端口字段
for key in ("server_port", "port", "local_port"):
    if key in cfg and print_port(cfg[key]):
        raise SystemExit(0)

# 部分配置使用 servers 数组
servers = cfg.get("servers")
if isinstance(servers, list):
    for item in servers:
        if isinstance(item, dict) and "server_port" in item and print_port(item["server_port"]):
            raise SystemExit(0)

print("")
PY
)

    # Python解析失败时，回退到grep（支持冒号两侧空格）
    if [ -z "$ss_port" ]; then
        ss_port=$(grep -oE '"server_port"[[:space:]]*:[[:space:]]*[0-9]+' "$CONFIG_PATH" 2>/dev/null | head -1 | grep -oE '[0-9]+' || true)
    fi

    if [[ ! "$ss_port" =~ ^[0-9]+$ ]] || [ "$ss_port" -lt 1 ] || [ "$ss_port" -gt 65535 ]; then
        echo "$default_port"
    else
        echo "$ss_port"
    fi
}

# 生成iptables规则
generate_iptables_rules() {
    echo -e "${INFO} 生成iptables规则..."
    
    if [ ! -f "$MAINLAND_IP_FILE" ]; then
        echo -e "${ERROR} IP列表文件不存在"
        return 1
    fi
    
    # 获取SS端口
    local ss_port
    ss_port=$(detect_ss_port)
    echo -e "${INFO} 检测到SS端口: $ss_port"
    
    cat > "$IPTABLES_RULES" << EOF
#!/bin/bash
# 中国大陆IP屏蔽规则
# 自动生成，请勿手动修改

set -e

# 清除旧规则
echo "[信息] 清除旧的屏蔽规则..."
iptables -D INPUT -p tcp --dport $ss_port -m set --match-set mainland_cn_src src -j DROP 2>/dev/null || true
iptables -D INPUT -p udp --dport $ss_port -m set --match-set mainland_cn_src src -j DROP 2>/dev/null || true
iptables -D INPUT -p tcp -m set --match-set mainland_cn_src src -j DROP 2>/dev/null || true
iptables -D INPUT -p udp -m set --match-set mainland_cn_src src -j DROP 2>/dev/null || true
ipset destroy mainland_cn_src 2>/dev/null || true

echo "[信息] 创建ipset集合..."
# 创建ipset集合用于存储IP列表
ipset create mainland_cn_src hash:net maxelem 200000

echo "[信息] 导入IP列表..."
# 从文件导入IP
/usr/local/bin/block-mainland-import-ips.sh

echo "[信息] 应用iptables规则..."
# 添加规则：仅屏蔽来自中国大陆且目标为SS端口的连接
iptables -I INPUT -p tcp --dport $ss_port -m set --match-set mainland_cn_src src -j DROP
iptables -I INPUT -p udp --dport $ss_port -m set --match-set mainland_cn_src src -j DROP

echo "[成功] 规则应用完成"
EOF
    
    chmod +x "$IPTABLES_RULES"
    echo -e "${SUCCESS} iptables规则生成完成"
}

# 生成IP导入脚本
generate_import_script() {
    echo -e "${INFO} 生成IP导入脚本..."
    
    local import_script="/usr/local/bin/block-mainland-import-ips.sh"
    
    cat > "$import_script" << 'IMPORTEOF'
#!/bin/bash
# IP导入脚本 - 支持CIDR和纯IP格式

MAINLAND_IP_FILE="__MAINLAND_IP_FILE__"

echo "[信息] 开始导入IP列表..."

local_count=0
local_total=$(wc -l < "$MAINLAND_IP_FILE" 2>/dev/null || echo 0)

while IFS= read -r line; do
    # 跳过空行和注释
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    
    # 清理空白
    line=$(echo "$line" | xargs)
    
    # 检查是否包含前缀长度标记(/)
    if [[ ! "$line" =~ / ]]; then
        # 纯IP地址，转换为/32
        line="${line}/32"
    fi
    
    # 导入到ipset
    if ipset add mainland_cn_src "$line" 2>/dev/null; then
        ((local_count++))
    fi
    
    # 进度显示
    if [ $((local_count % 1000)) -eq 0 ]; then
        echo "[进度] 已导入 $local_count/$local_total ..."
    fi
done < "$MAINLAND_IP_FILE"

if [ "$local_count" -eq 0 ]; then
    echo "[错误] 未导入任何IP段，请检查IP列表内容或格式"
    exit 1
fi

echo "[成功] IP列表导入完成！共导入 $local_count 条IP段"
IMPORTEOF

    sed -i "s|__MAINLAND_IP_FILE__|$MAINLAND_IP_FILE|g" "$import_script"
    
    chmod +x "$import_script"
    echo -e "${SUCCESS} IP导入脚本生成完成"
}

# 安装ipset
install_ipset() {
    echo -e "${INFO} 检查ipset..."
    
    if ! command -v ipset &> /dev/null; then
        echo -e "${WARNING} ipset未安装，正在安装..."
        
        if command -v apt-get &> /dev/null; then
            apt-get install -y ipset
        elif command -v yum &> /dev/null; then
            yum install -y ipset
        fi
    fi
    
    echo -e "${SUCCESS} ipset检查完成"
}

# 启用屏蔽规则
enable_blocking() {
    echo -e "${INFO} 启用屏蔽规则..."
    
    # 安装ipset
    install_ipset
    
    # 生成并执行规则
    if [ -f "$IPTABLES_RULES" ]; then
        bash "$IPTABLES_RULES"
    fi
    
    # 保存iptables规则（使用iptables-save/iptables-restore）
    if command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    echo -e "${SUCCESS} 屏蔽规则已启用"
}

# 禁用屏蔽规则
disable_blocking() {
    echo -e "${INFO} 禁用屏蔽规则..."

    local ss_port
    ss_port=$(detect_ss_port)
    
    # 删除当前端口规则
    iptables -D INPUT -p tcp --dport "$ss_port" -m set --match-set mainland_cn_src src -j DROP 2>/dev/null || true
    iptables -D INPUT -p udp --dport "$ss_port" -m set --match-set mainland_cn_src src -j DROP 2>/dev/null || true

    # 兼容清理旧版（未带端口）规则
    iptables -D INPUT -p tcp -m set --match-set mainland_cn_src src -j DROP 2>/dev/null || true
    iptables -D INPUT -p udp -m set --match-set mainland_cn_src src -j DROP 2>/dev/null || true
    
    # 删除ipset
    ipset destroy mainland_cn_src 2>/dev/null || true
    
    echo -e "${SUCCESS} 屏蔽规则已禁用"
}

# 查看规则状态
show_status() {
    local ss_port
    ss_port=$(detect_ss_port)

    echo -e "${BLUE}${BOLD}═══════════════════════════════════${PLAIN}"
    echo -e "${BLUE}${BOLD}    中国大陆屏蔽规则状态${PLAIN}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════${PLAIN}"
    echo -e "${BOLD}当前SS端口:${PLAIN} $ss_port"
    
    echo ""
    echo -e "${BOLD}IP列表文件:${PLAIN}"
    if [ -f "$MAINLAND_IP_FILE" ]; then
        local ip_count=$(wc -l < "$MAINLAND_IP_FILE")
        echo -e "  ${GREEN}✓${PLAIN} 存在 (共 $ip_count 个CIDR段)"
        echo -e "  文件路径: $MAINLAND_IP_FILE"
        echo -e "  文件大小: $(du -h "$MAINLAND_IP_FILE" | cut -f1)"
    else
        echo -e "  ${RED}✗${PLAIN} 不存在"
    fi
    
    echo ""
    echo -e "${BOLD}ipset状态:${PLAIN}"
    if ipset list mainland_cn_src &>/dev/null; then
        local ip_set_count=$(ipset save mainland_cn_src | grep "add" | wc -l)
        echo -e "  ${GREEN}✓${PLAIN} 已创建 (共 $ip_set_count 个IP段)"
    else
        echo -e "  ${RED}✗${PLAIN} 未创建"
    fi
    
    echo ""
    echo -e "${BOLD}iptables规则:${PLAIN}"
    if iptables -S INPUT 2>/dev/null | grep -q "mainland_cn_src" || iptables -L INPUT -n 2>/dev/null | grep -q "mainland_cn_src"; then
        echo -e "  ${GREEN}✓${PLAIN} 已启用"
    else
        echo -e "  ${RED}✗${PLAIN} 未启用"
    fi
    
    echo ""
    echo -e "${BLUE}${BOLD}═══════════════════════════════════${PLAIN}"
}

# 更新IP列表
update_ip_list() {
    echo -e "${INFO} 更新IP列表..."
    
    # 禁用旧规则
    disable_blocking
    
    # 下载新列表
    download_mainland_ip_list || {
        echo -e "${ERROR} IP列表更新失败"
        return 1
    }
    
    # 重新生成规则和脚本
    generate_iptables_rules
    generate_import_script
    
    # 启用新规则
    enable_blocking
    
    echo -e "${SUCCESS} IP列表更新完成"
}

# 获取用于定时任务调用的脚本路径
get_script_exec_path() {
    if [ -x "/usr/local/bin/block-mainland.sh" ]; then
        echo "/usr/local/bin/block-mainland.sh"
    else
        echo "$SCRIPT_FULL_PATH"
    fi
}

# 校验cron表达式（仅校验字段数）
is_valid_cron_expr() {
    local expr="$1"
    expr=$(echo "$expr" | awk '{$1=$1; print}')

    if [ -z "$expr" ]; then
        return 1
    fi

    [ "$(echo "$expr" | awk '{print NF}')" -eq 5 ]
}

# 规范化输入的计划类型
normalize_schedule_input() {
    local input="$1"

    case "$input" in
        daily)
            echo "$DAILY_CRON_EXPR"
            ;;
        weekly)
            echo "$WEEKLY_CRON_EXPR"
            ;;
        *)
            echo "$input"
            ;;
    esac
}

# 尝试确保系统的cron服务可用
ensure_cron_service() {
    if ! command -v systemctl >/dev/null 2>&1; then
        return 0
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q '^cron.service'; then
        systemctl enable --now cron >/dev/null 2>&1 || true
    elif systemctl list-unit-files 2>/dev/null | grep -q '^crond.service'; then
        systemctl enable --now crond >/dev/null 2>&1 || true
    fi
}

# 开启定时更新
enable_auto_update() {
    local schedule_input="$1"
    local cron_expr=""

    if [ -n "$schedule_input" ]; then
        cron_expr=$(normalize_schedule_input "$schedule_input")
        if ! is_valid_cron_expr "$cron_expr"; then
            echo -e "${ERROR} 无效的cron表达式: $schedule_input"
            echo -e "${INFO} 示例: '30 4 * * *'"
            return 1
        fi
    else
        echo -e "${INFO} 请选择定时更新频率:"
        echo "  1) 每日 04:30"
        echo "  2) 每周一 04:30"
        echo "  3) 自定义 cron 表达式"
        read -p "请选择 [1-3] (默认: 1): " schedule_choice
        [ -z "$schedule_choice" ] && schedule_choice="1"

        case "$schedule_choice" in
            1)
                cron_expr="$DAILY_CRON_EXPR"
                ;;
            2)
                cron_expr="$WEEKLY_CRON_EXPR"
                ;;
            3)
                read -p "请输入 cron 表达式(5段，如: 30 4 * * *): " custom_expr
                if ! is_valid_cron_expr "$custom_expr"; then
                    echo -e "${ERROR} cron表达式格式无效"
                    return 1
                fi
                cron_expr="$custom_expr"
                ;;
            *)
                echo -e "${ERROR} 无效选项"
                return 1
                ;;
        esac
    fi

    ensure_cron_service

    local script_exec_path
    script_exec_path=$(get_script_exec_path)

    touch "$AUTO_UPDATE_LOG_FILE"

    cat > "$AUTO_UPDATE_CRON_FILE" << EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$cron_expr root PYTHONIOENCODING=UTF-8 LC_ALL=C.UTF-8 LANG=C.UTF-8 bash $script_exec_path update >> $AUTO_UPDATE_LOG_FILE 2>&1
EOF

    chmod 644 "$AUTO_UPDATE_CRON_FILE"

    echo -e "${SUCCESS} 定时更新已开启"
    echo -e "${INFO} 更新频率: $cron_expr"
    echo -e "${INFO} 日志文件: $AUTO_UPDATE_LOG_FILE"
}

# 关闭定时更新
disable_auto_update() {
    if [ -f "$AUTO_UPDATE_CRON_FILE" ]; then
        rm -f "$AUTO_UPDATE_CRON_FILE"
        echo -e "${SUCCESS} 定时更新已关闭"
    else
        echo -e "${WARNING} 定时更新未启用"
    fi
}

# 查看定时更新状态
show_auto_update_status() {
    echo -e "${BLUE}${BOLD}═══════════════════════════════════${PLAIN}"
    echo -e "${BLUE}${BOLD}      定时更新任务状态${PLAIN}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════${PLAIN}"

    if [ -f "$AUTO_UPDATE_CRON_FILE" ]; then
        local cron_line
        cron_line=$(grep -vE '^(#|SHELL=|PATH=|$)' "$AUTO_UPDATE_CRON_FILE" | head -1)
        local cron_expr
        cron_expr=$(echo "$cron_line" | awk '{print $1" "$2" "$3" "$4" "$5}')

        echo -e "${GREEN}✓${PLAIN} 已启用"
        echo -e "  调度表达式: $cron_expr"
        echo -e "  任务文件: $AUTO_UPDATE_CRON_FILE"
    else
        echo -e "${RED}✗${PLAIN} 未启用"
    fi

    if [ -f "$AUTO_UPDATE_LOG_FILE" ]; then
        echo -e "  日志文件: $AUTO_UPDATE_LOG_FILE"
        echo -e "  日志大小: $(du -h "$AUTO_UPDATE_LOG_FILE" | cut -f1)"
    fi

    echo -e "${BLUE}${BOLD}═══════════════════════════════════${PLAIN}"
}

# 显示菜单
show_menu() {
    echo ""
    echo -e "${BLUE}${BOLD}════════════════════════════════════${PLAIN}"
    echo -e "${BLUE}${BOLD}  Shadowsocks Rust - 中国大陆屏蔽${PLAIN}"
    echo -e "${BLUE}${BOLD}════════════════════════════════════${PLAIN}"
    echo ""
    echo -e "  ${BOLD}1.${PLAIN} 下载IP列表并启用屏蔽"
    echo -e "  ${BOLD}2.${PLAIN} 启用屏蔽规则"
    echo -e "  ${BOLD}3.${PLAIN} 禁用屏蔽规则"
    echo -e "  ${BOLD}4.${PLAIN} 更新IP列表"
    echo -e "  ${BOLD}5.${PLAIN} 查看规则状态"
    echo -e "  ${BOLD}6.${PLAIN} 开启定时更新"
    echo -e "  ${BOLD}7.${PLAIN} 关闭定时更新"
    echo -e "  ${BOLD}8.${PLAIN} 查看定时更新状态"

    echo -e "  ${BOLD}0.${PLAIN} 退出"
    echo ""
}

# 主函数
main() {
    check_root
    
    # 如果有参数，直接执行相应操作
    if [ $# -gt 0 ]; then
        case "$1" in
            enable)
                check_dependencies
                create_directories
                download_mainland_ip_list
                generate_iptables_rules
                generate_import_script
                enable_blocking
                show_status
                ;;
            disable)
                disable_blocking
                show_status
                ;;
            update)
                check_dependencies
                update_ip_list
                show_status
                ;;
            auto-update-enable)
                check_dependencies
                create_directories
                enable_auto_update "$2"
                show_auto_update_status
                ;;
            auto-update-disable)
                disable_auto_update
                show_auto_update_status
                ;;
            auto-update-status)
                show_auto_update_status
                ;;
            status)
                show_status
                ;;
            *)
                echo "用法: $SCRIPT_NAME [enable|disable|update|status|auto-update-enable [daily|weekly|\"cron\"]|auto-update-disable|auto-update-status]"
                exit 1
                ;;
        esac
        return 0
    fi
    
    # 交互式菜单
    while true; do
        show_menu
        read -p "请选择操作 [0-8]: " choice
        
        case $choice in
            1)
                check_dependencies
                create_directories
                download_mainland_ip_list && {
                    generate_iptables_rules
                    generate_import_script
                    enable_blocking
                    show_status
                }
                ;;
            2)
                check_directories
                enable_blocking
                show_status
                ;;
            3)
                disable_blocking
                show_status
                ;;
            4)
                check_dependencies
                update_ip_list
                ;;
            5)
                show_status
                ;;
            6)
                check_dependencies
                create_directories
                enable_auto_update
                show_auto_update_status
                ;;
            7)
                disable_auto_update
                show_auto_update_status
                ;;
            8)
                show_auto_update_status
                ;;
            0)
                echo -e "${INFO} 退出脚本"
                exit 0
                ;;
            *)
                echo -e "${ERROR} 无效的选择"
                ;;
        esac
        
        read -p "按 Enter 键继续..."
    done
}

# 辅助函数：检查目录
check_directories() {
    if [ ! -d "$IPLIST_DIR" ]; then
        echo -e "${ERROR} IP列表目录不存在，请先运行初始化"
        exit 1
    fi
}

# 启动主函数
main "$@"
