#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="/var/log/ufw_whitelist.log"

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_title() { echo -e "${CYAN}========================================${NC}"; echo -e "${CYAN}$1${NC}"; echo -e "${CYAN}========================================${NC}"; }
print_subtitle() { echo -e "${MAGENTA}--- $1 ---${NC}"; }

validate_ip() {
    local ip=$1
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then return 1; fi
    IFS='.' read -r a b c d <<< "$ip"
    if [ "$a" -le 255 ] && [ "$b" -le 255 ] && [ "$c" -le 255 ] && [ "$d" -le 255 ]; then return 0; fi
    return 1
}

validate_ip_or_cidr() {
    local input=$1
    if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        local ip="${input%/*}"
        local mask="${input#*/}"
        if validate_ip "$ip" && [ "$mask" -ge 0 ] && [ "$mask" -le 32 ]; then return 0; fi
    fi
    if validate_ip "$input"; then return 0; fi
    return 1
}

validate_port() {
    local port=$1
    if [[ -z "$port" ]]; then return 1; fi
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then return 1; fi
    return 0
}

check_ufw() {
    if ! command -v ufw &> /dev/null; then
        print_error "UFW 未安装！"
        exit 1
    fi
    if ! ufw status | grep -q "Status: active"; then
        print_warning "UFW 当前未启用，正在启用..."
        ufw enable
    fi
    print_success "UFW 运行正常"
}

is_rule_exists() {
    local ip=$1
    local port=$2
    if ufw status | grep -q "$port/tcp.*$ip"; then return 0; else return 1; fi
}

add_ufw_rule() {
    local ip=$1
    local port=$2
    ufw allow from "$ip" to any port "$port" proto tcp 2>&1 | tee -a "$LOG_FILE" > /dev/null
    return $?
}

delete_ufw_rule() {
    local ip=$1
    local port=$2
    
    # 获取规则编号
    local rule_num=$(ufw status numbered | grep "\[.*\].*$port/tcp" | grep "$ip" | head -1 | awk -F'[][]' '{print $2}')
    
    if [[ -z "$rule_num" ]]; then
        print_warning "  未找到规则: $port/tcp from $ip"
        return 1
    fi
    
    print_info "  找到规则编号: [$rule_num]"
    echo "y" | ufw delete "$rule_num" 2>&1 | tee -a "$LOG_FILE" > /dev/null
    
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

get_ports_from_user() {
    local ports_input=""
    local valid_ports=()
    
    echo "" >&2
    echo -e "${CYAN}========================================${NC}" >&2
    echo -e "${CYAN}请输入要操作的端口${NC}" >&2
    echo -e "${CYAN}========================================${NC}" >&2
    echo "" >&2
    echo -e "${CYAN}支持格式:${NC}" >&2
    echo "  单个端口: 22" >&2
    echo "  多个端口: 22 80 443" >&2
    echo "  端口范围: 8000-8100" >&2
    echo "  混合输入: 22 80 443 8000-8100" >&2
    echo "" >&2
    
    while true; do
        read -p "请输入端口 (多个用空格分隔): " ports_input < /dev/tty
        
        ports_input=$(echo "$ports_input" | xargs)
        
        if [[ -z "$ports_input" ]]; then
            echo -e "${RED}[ERROR]${NC} 端口不能为空，请重新输入！" >&2
            continue
        fi
        
        valid_ports=()
        local has_error=false
        
        for item in $ports_input; do
            if [[ "$item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start=${BASH_REMATCH[1]}
                end=${BASH_REMATCH[2]}
                
                if validate_port "$start" && validate_port "$end" && [ "$start" -le "$end" ]; then
                    for ((p=start; p<=end; p++)); do
                        valid_ports+=("$p")
                    done
                else
                    echo -e "${RED}[ERROR]${NC} 无效端口范围: $item (范围: 1-65535)" >&2
                    has_error=true
                    break
                fi
            else
                if validate_port "$item"; then
                    valid_ports+=("$item")
                else
                    echo -e "${RED}[ERROR]${NC} 无效端口: $item (范围: 1-65535)" >&2
                    has_error=true
                    break
                fi
            fi
        done
        
        if [ "$has_error" = false ] && [ ${#valid_ports[@]} -gt 0 ]; then
            break
        fi
    done
    
    printf '%s\n' "${valid_ports[@]}" | sort -nu
}

show_ports_summary() {
    local ports=("$@")
    echo ""
    print_title "端口摘要"
    echo -e "端口总数: ${GREEN}${#ports[@]}${NC}"
    local count=0
    echo -n "端口列表: "
    for port in "${ports[@]}"; do
        echo -n "$port "
        ((count++))
        if [ $((count % 10)) -eq 0 ]; then
            echo ""
            echo -n "          "
        fi
    done
    echo ""
    echo "========================================"
}

show_menu() {
    print_title "请选择操作模式"
    echo ""
    echo -e "  ${GREEN}1${NC}) 添加规则 - 从 ip.txt 读取 IP/CIDR，放行指定端口"
    echo -e "  ${YELLOW}2${NC}) 删除规则 - 从 ip.txt 读取 IP/CIDR，移除指定端口"
    echo -e "  ${CYAN}3${NC}) 查看规则 - 显示当前所有已放行的 TCP 白名单规则"
    echo ""
    echo -e "${BLUE}提示:${NC} 选择 1 或 2 需要先准备好 ip.txt 文件"
    echo ""
}

get_mode_choice() {
    while true; do
        read -p "请选择 [1/2/3]: " mode
        case $mode in
            1) echo "ADD"; return ;;
            2) echo "DELETE"; return ;;
            3) echo "VIEW"; return ;;
            *) ;;
        esac
    done
}

show_all_rules() {
    print_title "UFW 已放行规则列表"
    echo ""
    print_info "UFW 状态:"
    ufw status | head -1
    echo ""
    local rules=$(ufw status | grep "ALLOW" | grep "tcp")
    if [[ -z "$rules" ]]; then
        print_warning "暂无 TCP 白名单规则"
        return
    fi
    local total_rules=$(echo "$rules" | wc -l)
    print_subtitle "TCP 白名单规则 (共 $total_rules 条)"
    echo ""
    echo -e "${CYAN}序号  端口        来源 IP/CIDR${NC}"
    echo "----------------------------------------"
    local count=0
    while IFS= read -r line; do
        ((count++))
        local port=$(echo "$line" | awk '{print $1}')
        local from=$(echo "$line" | awk '{print $NF}')
        if [[ "$from" =~ / ]]; then
            printf "%-6s %-12s %s (CIDR)\n" "$count" "$port" "$from"
        else
            printf "%-6s %-12s %s\n" "$count" "$port" "$from"
        fi
    done <<< "$rules"
    echo "----------------------------------------"
}

# =============================================
# 主程序
# =============================================
clear
print_title "UFW 白名单批量管理工具"
echo ""
check_ufw
echo ""
show_menu
MODE=$(get_mode_choice)
echo ""

if [ "$MODE" = "VIEW" ]; then
    show_all_rules
    exit 0
fi

IP_FILE="ip.txt"
if [ ! -f "$IP_FILE" ]; then
    print_error "文件 $IP_FILE 不存在！"
    exit 1
fi
if [ ! -s "$IP_FILE" ]; then
    print_error "文件 $IP_FILE 为空！"
    exit 1
fi

print_info "正在读取白名单文件: $IP_FILE"
declare -a ip_entries
invalid_entries=0
while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    entry=$(echo "$line" | xargs)
    if validate_ip_or_cidr "$entry"; then
        ip_entries+=("$entry")
    else
        print_error "无效格式: $entry (已跳过)"
        ((invalid_entries++))
    fi
done < "$IP_FILE"

if [ ${#ip_entries[@]} -eq 0 ]; then
    print_error "没有有效的 IP/CIDR 条目！"
    exit 1
fi

echo ""
print_title "白名单 IP 摘要"
echo "有效条目: ${GREEN}${#ip_entries[@]}${NC}"
if [ $invalid_entries -gt 0 ]; then
    echo "无效条目: ${RED}$invalid_entries${NC} (已跳过)"
fi
echo ""
echo "IP 列表:"
for entry in "${ip_entries[@]}"; do
    if [[ "$entry" =~ / ]]; then
        echo "  📶 $entry (CIDR)"
    else
        echo "  📍 $entry (单个IP)"
    fi
done
echo "========================================"

port_list=($(get_ports_from_user))
if [ ${#port_list[@]} -eq 0 ]; then
    print_error "没有有效的端口！"
    exit 1
fi

show_ports_summary "${port_list[@]}"
total_rules=$(( ${#ip_entries[@]} * ${#port_list[@]} ))
echo "[INFO] 操作模式: $MODE"
echo "[INFO] 将要操作的规则总数: $total_rules 条"
echo ""
read -p "确认执行? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_warning "操作已取消"
    exit 0
fi

if [ "$MODE" = "ADD" ]; then
    print_title "开始添加规则"
else
    print_title "开始删除规则"
fi
echo ""

total_entries=${#ip_entries[@]}
total_ports=${#port_list[@]}
success=0
failed=0
skipped=0
entry_count=0

for entry in "${ip_entries[@]}"; do
    ((entry_count++))
    if [[ "$entry" =~ / ]]; then
        print_info "[$entry_count/$total_entries] 处理 CIDR: $entry"
    else
        print_info "[$entry_count/$total_entries] 处理 IP: $entry"
    fi
    for port in "${port_list[@]}"; do
        if [ "$MODE" = "ADD" ]; then
            if is_rule_exists "$entry" "$port"; then
                print_warning "  ⏭️  端口 $port/tcp 对 $entry 已存在 (跳过)"
                ((skipped++))
                continue
            fi
            print_info "  ➕ 添加: $port/tcp from $entry"
            if add_ufw_rule "$entry" "$port"; then
                print_success "  ✅ 添加成功"
                ((success++))
            else
                print_error "  ❌ 添加失败"
                ((failed++))
            fi
        else
            if ! is_rule_exists "$entry" "$port"; then
                print_warning "  ⏭️  端口 $port/tcp 对 $entry 不存在 (跳过)"
                ((skipped++))
                continue
            fi
            print_info "  ➖ 删除: $port/tcp from $entry"
            if delete_ufw_rule "$entry" "$port"; then
                print_success "  ✅ 删除成功"
                ((success++))
            else
                print_error "  ❌ 删除失败"
                ((failed++))
            fi
        fi
    done
    echo ""
done

print_title "执行完成！"
echo ""
echo -e "${CYAN}📊 统计信息${NC}"
echo "----------------------------------------"
echo "处理 IP/CIDR 条目: $total_entries"
echo "操作端口数量: $total_ports"
echo "操作模式: $MODE"
echo "尝试操作规则总数: $total_rules"
echo "----------------------------------------"
echo -e "✅ 成功: ${GREEN}$success${NC}"
echo -e "⏭️  跳过: ${YELLOW}$skipped${NC}"
echo -e "❌ 失败: ${RED}$failed${NC}"
echo "========================================"

echo ""
print_info "当前 UFW TCP 白名单规则:"
ufw status | grep "ALLOW" | grep "tcp" | head -20

total_rules_show=$(ufw status | grep "ALLOW" | grep "tcp" | wc -l)
print_info "TCP 白名单规则总数: $total_rules_show"

echo "$(date '+%Y-%m-%d %H:%M:%S') - $MODE 完成 - IP条目:$total_entries 端口:$total_ports 成功:$success 失败:$failed 跳过:$skipped" >> "$LOG_FILE"
print_success "日志已保存至: $LOG_FILE"
