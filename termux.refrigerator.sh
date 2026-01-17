#!/data/data/com.termux/files/usr/bin/sh

# ================= 配置区域 =================

# 1. 阈值
THRESHOLD=12

# 2. 检测间隔 (秒)
STEP=2

# 3. 音乐目录
DIR_MUSIC="/sdcard/Music/ToLight"

# ================= 工具函数 =================

C_RED="\033[31m"
C_GRN="\033[32m"
C_YEL="\033[33m"
C_CYN="\033[36m"
C_RST="\033[0m"

# 检查依赖
if ! command -v jq >/dev/null; then
    printf "%bError: Please install jq (pkg install jq)%b\n" "$C_RED" "$C_RST"
    exit 1
fi

# 路径修正
case "$DIR_MUSIC" in
    */) ;;
    *) DIR_MUSIC="${DIR_MUSIC}/" ;;
esac

# --- 核心修改：死磕模式获取光强 ---
get_lux_value() {
    while true; do
        # 1. 尝试获取数据 (使用你指定的传感器名称)
        # 注意：这里去掉了 jq 里的 // 0，如果出错我们希望它是空的，方便判断
        RAW=$(termux-sensor -s "Light Sensor Wakeup" -n 1 2>/dev/null | jq -r '.[] | .values[0]')

        # 2. 数据清洗 (只保留数字)
        # 如果 RAW 是空的，sed 处理完还是空的
        VAL=$(echo "$RAW" | cut -d. -f1 | sed 's/[^0-9]//g')

        # 3. 判断数据有效性
        if [ -n "$VAL" ]; then
            # 成功！返回数值并退出函数
            echo "$VAL"
            return
        else
            # 失败！打印日志到 stderr (屏幕)，不返回数据
            printf "\n%b[Warning] Sensor read failed! Retrying in 2s...%b" "$C_RED" "$C_RST" >&2
            sleep 2
            # 循环继续，重试...
        fi
    done
}

# 播放音乐函数
play_music() {
    printf "\n%b[Action] Searching music in %s...%b\n" "$C_GRN" "$DIR_MUSIC" "$C_RST"
    
    if [ ! -d "$DIR_MUSIC" ]; then
        printf "%b[Error] Directory not found!%b\n" "$C_RED" "$C_RST"
        return
    fi

    FILE=$(find "$DIR_MUSIC" -maxdepth 1 -name "*.mp3" 2>/dev/null | shuf -n 1)

    if [ -n "$FILE" ]; then
        NAME=$(basename "$FILE")
        printf "%b[Player] Playing: %s%b\n" "$C_GRN" "$NAME" "$C_RST"
        termux-media-player stop >/dev/null 2>&1
        termux-media-player play "$FILE"
    else
        printf "%b[Warning] No MP3 files found!%b\n" "$C_YEL" "$C_RST"
    fi
}

# ================= 主逻辑 =================

printf "%b=== Light Sensor Trigger (Dark -> Light) ===%b\n" "$C_CYN" "$C_RST"
printf "Sensor: Light Sensor Wakeup\n"
printf "Threshold: %d Lux\n" "$THRESHOLD"
printf "Dir: %s\n\n" "$DIR_MUSIC"

while true; do

    # --- 阶段 1：复位等待 (Wait for Dark) ---
    printf "%b[Phase 1] Waiting for environment to become DARK (Reset)...%b\n" "$C_YEL" "$C_RST"
    
    while true; do
        # 这里调用函数，如果不成功，脚本会卡在函数里的 sleep 2，直到成功拿到值
        LUX=$(get_lux_value)
        
        # 打印实时数值 (使用 :-0 防止极小概率的空值报错)
        printf "\rCurrent: %b%-5s%b Lux (Need <= %d)   " "$C_YEL" "${LUX:-0}" "$C_RST" "$THRESHOLD"

        if [ "${LUX:-0}" -le "$THRESHOLD" ]; then
            printf "\n%b>>> Environment is Dark now. Armed and ready.%b\n" "$C_GRN" "$C_RST"
            break
        fi
        
        sleep "$STEP"
    done

    # --- 阶段 2：触发检测 (Wait for Light) ---
    printf "%b[Phase 2] Waiting for LIGHT trigger...%b\n" "$C_CYN" "$C_RST"
    
    while true; do
        LUX=$(get_lux_value)
        
        printf "\rCurrent: %b%-5s%b Lux (Need > %d)   " "$C_CYN" "${LUX:-0}" "$C_RST" "$THRESHOLD"

        if [ "${LUX:-0}" -gt "$THRESHOLD" ]; then
            printf "\n%b>>> TRIGGERED! Light detected!%b\n" "$C_GRN" "$C_RST"
            play_music
            break
        fi
        
        sleep "$STEP"
    done
    
    # 防止循环切换过快
    sleep 2

done