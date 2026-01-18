#!/data/data/com.termux/files/usr/bin/sh

# =================================================================
# Termux 默认的 Shell 是 Bash，添加到 ~/.bashrc 即可在开启终端时显示
#     chmod +x termux_welcome_posix.sh
#     echo "source ~/termux_welcome_posix.sh" >> ~/.bashrc
# =================================================================

# =================================================================
# ⚙️ 配置区域
# =================================================================

# 是否显示 Emoji? (yes/no)
# 兼容性提示：这里只用简单的字符串，不搞 true/false 这种容易歧义的词
USE_EMOJI="no"

# =================================================================
# 🎨 颜色与符号定义 (使用 printf 兼容格式)
# =================================================================

# ANSI 颜色代码
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_KEY="\033[38;5;39m"   # 蓝色
C_VAL="\033[38;5;82m"   # 绿色
C_WARN="\033[38;5;208m" # 橙色
C_TIT="\033[38;5;226m"  # 黄色

# 图标逻辑 (使用标准的 = 进行判断)
if [ "$USE_EMOJI" = "yes" ]; then
    I_OS="🤖"
    I_TIM="⏰"
    I_IP="🌐"
    I_CPU="🧠"
    I_MEM="💾"
    I_DSK="💿"
    I_BAT="🔋"
    I_USR="👋"
    I_SEP="-"
else
    # 纯文本符号
    I_OS=">"
    I_TIM=">"
    I_IP=">"
    I_CPU=">"
    I_MEM=">"
    I_DSK=">"
    I_BAT=">"
    I_USR=">"
    I_SEP="-"
fi

# =================================================================
# 🛠️ 核心函数 (使用 printf 保证格式绝对对齐)
# =================================================================

print_row() {
    # 参数: $1=图标, $2=标题, $3=数值
    # %b : 解析转义字符 (颜色)
    # %-10s : 字符串左对齐，占10位
    printf "  %s %b%-10s%b : %b%s%b\n" "$1" "$C_KEY" "$2" "$C_RESET" "$C_VAL" "$3" "$C_RESET"
}

get_battery() {
    # 检查命令是否存在
    if command -v termux-battery-status >/dev/null 2>&1; then
        # 获取 JSON 数据
        # 注意：这里为了兼容性，依然推荐安装 jq (pkg install jq)
        if command -v jq >/dev/null 2>&1; then
            BAT_DATA=$(timeout 2s termux-battery-status 2>/dev/null)
            if [ -n "$BAT_DATA" ]; then
                PERC=$(echo "$BAT_DATA" | jq -r '.percentage // 0')
                TEMP=$(echo "$BAT_DATA" | jq -r '.temperature // 0')
                STAT=$(echo "$BAT_DATA" | jq -r '.status // "Unknown"')
                
                ICON=""
                if [ "$STAT" = "CHARGING" ]; then
                    if [ "$USE_EMOJI" = "yes" ]; then ICON="⚡"; else ICON=" [Charging]"; fi
                fi
                echo "${PERC}%${ICON} (${TEMP}°C)"
            else
                echo "${C_WARN}API No Response${C_RESET}"
            fi
        else
            echo "${C_WARN}Need 'jq' tool${C_RESET}"
        fi
    else
        echo "${C_WARN}No termux-api${C_RESET}"
    fi
}

# =================================================================
# 📊 信息采集
# =================================================================

# 1. 基础信息
USER_NAME=$(whoami)
KERNEL=$(uname -r | cut -d'-' -f1)
ARCH=$(uname -m)
# 兼容处理 uptime 输出
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //')
# 如果 uptime -p 不支持 (某些老版本busybox)，回退方案
if [ -z "$UPTIME" ]; then
    UPTIME=$(uptime | awk -F'( |,|:)+' '{print $6"h "$7"m"}')
fi

# 2. IP 地址
# 使用 grep -E 替代 grep -Eo (为了兼容性)，这里逻辑稍微简化以适配更多环境
IP_ADDR=$(ifconfig | grep -v '127.0.0.1' | grep -E "inet (addr:)?([0-9]*\.){3}[0-9]*" | awk '{print $2}' | sed 's/addr://' | head -n1)
if [ -z "$IP_ADDR" ]; then IP_ADDR="${C_WARN}Disconnected${C_RESET}"; fi

# 3. 存储
DISK_INFO=$(df -h /sdcard 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
if [ -z "$DISK_INFO" ]; then DISK_INFO="${C_WARN}No Permission${C_RESET}"; fi

# 4. 内存
MEM_INFO=$(free -h | awk '/Mem:/ {print $3 "/" $2}')

# 5. CPU
# 尝试多种方式获取 CPU 名字
if [ -f /proc/cpuinfo ]; then
    CPU_MODEL=$(grep -m1 'Hardware' /proc/cpuinfo | cut -d: -f2)
    if [ -z "$CPU_MODEL" ]; then
        CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2)
    fi
fi
# 去除首尾空格
CPU_MODEL=$(echo "$CPU_MODEL" | awk '{$1=$1};1')
if [ -z "$CPU_MODEL" ]; then CPU_MODEL="$ARCH"; fi

# 6. 电池
BAT_INFO=$(get_battery)

# =================================================================
# 🖥️ 输出显示
# =================================================================
# -----------------------------------------------------------------
# 安装 figlet (生成字) 和 toilet (更高级的生成字)
# lolcat（上彩色渐变）
# pkg install figlet toilet
# python -m pip install lolcat -i https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
# -----------------------------------------------------------------
clear
toilet -f standard "WELCOME" | lolcat -F 0.1
printf "%b----------------------------------------%b\n" "$C_KEY" "$C_RESET"
# 打印标题
printf "%b   Termux Environment - $(date '+%Y-%m-%d %H:%M')%b\n\n" "$C_TIT" "$C_RESET"

# 打印行
print_row "$I_OS"  "System"   "$KERNEL ($ARCH)"
print_row "$I_TIM" "Uptime"   "$UPTIME"
print_row "$I_IP"  "IP Addr"  "$IP_ADDR"
print_row "$I_CPU" "CPU"      "$CPU_MODEL"
print_row "$I_MEM" "Memory"   "$MEM_INFO"
print_row "$I_DSK" "Storage"  "$DISK_INFO"
print_row "$I_BAT" "Battery"  "$BAT_INFO"

printf "\n %s %bHello, %s!%b\n" "$I_USR" "$C_BOLD" "$USER_NAME" "$C_RESET"
printf "%b----------------------------------------%b\n" "$C_KEY" "$C_RESET"