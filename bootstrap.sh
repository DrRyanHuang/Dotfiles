#!/bin/bash
# -----------------------------------------------------------------------------
# System Initialization Script
# 功能: 自动安装 Zsh, Zimfw, UV, 常用工具, 并配置代理与环境
# 兼容: Debian/Ubuntu, CentOS/RHEL, Arch, Alpine, macOS
# -----------------------------------------------------------------------------

# --- 0. Global Variables & Initialization (Scope Safety) ---
# 显式初始化全局变量，防止作用域污染
OS_NAME=""
INSTALL_CMD=""
CMD_PREFIX=""
PROXY_URL=""
SHOULD_WRITE_PROXY="no"
USE_SUDO="no"

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 1. Helper Functions ---

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 错误立即退出机制 (Fail Fast)
fail_fast() {
    log_error "$1"
    exit 1
}

# 检查命令是否存在
cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- 2. User Interaction: Proxy Setup ---

setup_proxy() {
    echo "------------------------------------------------"
    
    # 1. 尝试获取现有代理 (优先读取 http_proxy 或 HTTP_PROXY)
    # 使用 local 变量暂存检测到的值
    local current_proxy="${http_proxy:-$HTTP_PROXY}"
    # 如果 http_proxy 为空，再尝试 check https_proxy
    if [[ -z "$current_proxy" ]]; then
        current_proxy="${https_proxy:-$HTTPS_PROXY}"
    fi
    
    if [[ -n "$current_proxy" ]]; then
        # --- 情况 A: 发现现有代理 ---
        log_warn "检测到当前环境已配置代理: $current_proxy"
        read -p "是否需要修改此代理设置? (y/n, 默认 n - 保持使用): " modify_choice
        modify_choice=${modify_choice:-n}
        
        if [[ "$modify_choice" == "y" || "$modify_choice" == "Y" ]]; then
            read -p "请输入新的代理地址 (例如 http://127.0.0.1:7890): " PROXY_URL
        else
            # 用户选择保留现有代理，将其赋值给全局变量 PROXY_URL
            PROXY_URL="$current_proxy"
            log_info "将继续使用现有代理配置。"
        fi
    else
        # --- 情况 B: 无现有代理 ---
        log_warn "是否需要配置代理? (用于加速下载)"
        read -p "输入 y/n (默认 n): " proxy_choice
        proxy_choice=${proxy_choice:-n}
        
        if [[ "$proxy_choice" == "y" || "$proxy_choice" == "Y" ]]; then
            read -p "请输入代理地址 (例如 http://127.0.0.1:7890): " PROXY_URL
        fi
    fi
    
    # --- 公共逻辑: 应用与持久化 ---
    # 只要 PROXY_URL 不为空（无论是新输入的，还是继承现有的），都执行以下逻辑
    if [[ -n "$PROXY_URL" ]]; then
        # 重新 export 确保所有相关变量 (http, https, 大小写) 保持一致
        export http_proxy="$PROXY_URL"
        export https_proxy="$PROXY_URL"
        export HTTP_PROXY="$PROXY_URL"
        export HTTPS_PROXY="$PROXY_URL"
        export all_proxy="$PROXY_URL"
        
        # 即使是继承的代理，也可能没有写入 .zshrc，所以依然询问持久化
        read -p "是否将代理写入 ~/.zshrc 以永久生效? (y/n, 默认 n): " write_proxy
        if [[ "$write_proxy" == "y" || "$write_proxy" == "Y" ]]; then
            SHOULD_WRITE_PROXY="yes"
        fi
        
        log_success "代理设置已就绪: $PROXY_URL"
    else
        log_info "本次运行不使用代理。"
    fi
}

# --- 3. System Detection & Command Prep ---

detect_os_and_cmd() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
    else
        OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
    
    log_info "检测到操作系统: ${OS_NAME}"
    
    case "$OS_NAME" in
        ubuntu|debian|kali|linuxmint)
            INSTALL_CMD="apt-get update && apt-get install -y"
        ;;
        centos|rhel|fedora|rocky|almalinux)
            if cmd_exists dnf; then
                INSTALL_CMD="dnf install -y"
            else
                INSTALL_CMD="yum install -y"
            fi
        ;;
        arch|manjaro)
            INSTALL_CMD="pacman -Syu --noconfirm"
        ;;
        alpine)
            INSTALL_CMD="apk add --no-cache"
        ;;
        darwin)
            if ! cmd_exists brew; then
                fail_fast "macOS 检测到未安装 Homebrew，请先安装 Homebrew。"
            fi
            INSTALL_CMD="brew install"
        ;;
        *)
            # 变量安全检测：如果未匹配到系统，必须报错退出
            fail_fast "未知的操作系统: $OS_NAME，无法确定安装命令。"
        ;;
    esac
    
    # 二次检查：防止 INSTALL_CMD 为空
    if [[ -z "$INSTALL_CMD" ]]; then
        fail_fast "严重错误：INSTALL_CMD 变量为空。"
    fi
}

setup_privileges() {
    # 自动检测是否为 Root
    if [ "$EUID" -eq 0 ]; then
        log_info "当前用户为 Root，直接执行。"
        CMD_PREFIX=""
    else
        echo "------------------------------------------------"
        log_warn "检测到非 Root 用户。"
        read -p "安装软件是否需要 sudo 权限? (y/n, 默认 y): " need_sudo
        need_sudo=${need_sudo:-y}
        
        if [[ "$need_sudo" == "y" || "$need_sudo" == "Y" ]]; then
            # 关键：使用 sudo -E 保留环境变量 (代理设置)
            CMD_PREFIX="sudo -E"
            log_info "将使用 '${CMD_PREFIX}' 执行安装命令。"
            # 测试 sudo 权限
            if ! $CMD_PREFIX true; then
                fail_fast "Sudo 验证失败或用户取消。"
            fi
        else
            CMD_PREFIX=""
            log_warn "将尝试直接运行命令 (可能会因权限不足失败)。"
        fi
    fi
}

# --- 4. Installation Logic ---

install_packages() {
    log_info "准备安装基础软件包..."
    
    # 基础包列表
    PACKAGES="zsh git curl wget tmux fzf ripgrep zoxide"
    
    # 根据系统调整包名或添加特定包
    case "$OS_NAME" in
        alpine)
            # Alpine 需要 shadow 来支持 chsh
            PACKAGES="$PACKAGES shadow"
            # Alpine 的 cron 常用 dcron 或 cronie，这里尝试安装 cronie
            PACKAGES="$PACKAGES cronie"
        ;;
        arch|manjaro)
            PACKAGES="$PACKAGES cronie"
        ;;
        ubuntu|debian|kali)
            PACKAGES="$PACKAGES cron"
        ;;
        centos|rhel|fedora)
            PACKAGES="$PACKAGES cronie"
        ;;
        darwin)
            # macOS 不需要安装 cron (自带 launchd/crontab)，但可以装 coreutils 等
        ;;
    esac
    
    log_info "执行安装命令: $CMD_PREFIX $INSTALL_CMD $PACKAGES"
    
    # 执行安装
    eval "$CMD_PREFIX $INSTALL_CMD $PACKAGES" || fail_fast "软件包安装失败！"
    
    log_success "基础软件包安装完成。"
}

install_uv() {
    # --- 变更点：先检查是否存在 ---
    if command -v uv >/dev/null 2>&1; then
        log_info "检测到 uv 已经安装 ($(which uv))，跳过安装步骤。"
        return
    fi
    # ---------------------------
    
    log_info "正在安装 uv (Python Package Manager)..."
    
    # UV 安装安全性：禁止直接管道执行，使用临时文件
    UV_INSTALLER="/tmp/uv-installer.sh"
    
    # 网络超时控制：连接10s，最大60s
    curl -L --connect-timeout 10 --max-time 60 https://astral.sh/uv/install.sh -o "$UV_INSTALLER" || fail_fast "下载 uv 安装脚本失败 (超时或网络错误)。"
    
    log_info "UV 安装脚本下载成功，开始安装..."
    sh "$UV_INSTALLER" || fail_fast "uv 安装脚本执行失败。"
    
    # 清理临时文件
    rm -f "$UV_INSTALLER"
    log_success "uv 安装完成。"
}

install_uv_tools() {
    echo "------------------------------------------------"
    log_info "准备安装/更新常用 Python 全局工具 (via uv tool)..."
    
    # --- 1. 镜像源选择交互 ---
    log_warn "请选择 PyPI 镜像源 (加速 Python 包下载):"
    echo "   1) 默认 (官方源)"
    echo "   2) 清华大学 (Tsinghua - 推荐)"
    echo "   3) 阿里云 (Aliyun)"
    echo "   4) 百度 (Baidu)"
    echo "   5) 手动输入"
    
    read -p "请输入选项 [1-5] (默认 2): " mirror_choice
    mirror_choice=${mirror_choice:-2}
    
    local selected_mirror=""
    local mirror_name="官方源"
    
    case "$mirror_choice" in
        1)
            selected_mirror=""
        ;;
        2)
            # 注意：自动将 web 预览链接修正为 simple 索引链接
            selected_mirror="https://pypi.tuna.tsinghua.edu.cn/simple"
            mirror_name="清华大学"
        ;;
        3)
            selected_mirror="https://mirrors.aliyun.com/pypi/simple/"
            mirror_name="阿里云"
        ;;
        4)
            selected_mirror="https://mirror.baidu.com/pypi/simple"
            mirror_name="百度"
        ;;
        5)
            read -p "请输入完整的镜像 URL (如 https://.../simple): " selected_mirror
            mirror_name="自定义"
        ;;
        *)
            log_warn "输入无效，默认使用清华源。"
            selected_mirror="https://pypi.tuna.tsinghua.edu.cn/simple"
            mirror_name="清华大学"
        ;;
    esac
    
    # 如果选择了镜像，通过环境变量传递给 uv
    if [[ -n "$selected_mirror" ]]; then
        export UV_INDEX_URL="$selected_mirror"
        log_info "已切换 PyPI 源为: $mirror_name ($selected_mirror)"
    fi
    
    # --- 2. 定义工具列表 ---
    # 在这里添加你需要的任何工具。
    # 推荐加入 ruff (极速 linter) 和 httpie (人性化 curl)
    local TOOLS=("pytest" "ninja" "ruff" "httpie" "ipython" "prek" "gpustat")
    
    # --- 3. 智能安装/更新循环 ---
    for tool in "${TOOLS[@]}"; do
        # 检查是否已安装 (uv tool list 输出格式包含包名)
        if uv tool list | grep -q "^$tool "; then
            log_info "检测到 $tool 已安装，正在检查更新..."
            # 尝试更新
            uv tool upgrade "$tool" || log_warn "$tool 更新失败 (可能已是最新或网络问题)"
        else
            log_info "正在安装 $tool ..."
            # 安装
            uv tool install "$tool" || log_warn "$tool 安装失败"
        fi
    done
    
    # 清理环境变量（可选，防止影响后续非 Python 操作，虽然脚本快结束了）
    unset UV_INDEX_URL
    log_success "Python 常用工具处理完毕。"
}

setup_zimfw() {
    log_info "正在设置 Zsh 和 Zimfw..."
    
    # 检测并清理残留文件
    if [ -d "${HOME}/.zim" ]; then
        log_warn "检测到旧的 Zimfw 安装目录，正在清理..."
        rm -rf "${HOME}/.zim"
    fi
    if [ -f "${HOME}/.zimrc" ]; then
        rm -f "${HOME}/.zimrc"
    fi
    
    # 备份现有的 .zshrc (如果有)
    if [ -f "${HOME}/.zshrc" ]; then
        log_warn "检测到现有的 .zshrc，已备份为 .zshrc.bak"
        mv "${HOME}/.zshrc" "${HOME}/.zshrc.bak"
    fi
    
    # 安装 Zimfw
    # 注意：Zim 官方安装脚本通常需要 curl | zsh。这里我们下载后执行以确保安全和超时控制。
    ZIM_INSTALLER="/tmp/zim-install.zsh"
    curl -fsSL --connect-timeout 10 --max-time 60 https://raw.githubusercontent.com/zimfw/install/master/install.zsh -o "$ZIM_INSTALLER" || fail_fast "下载 Zimfw 安装脚本失败。"
    
    # 使用 zsh 执行安装
    zsh "$ZIM_INSTALLER" || fail_fast "Zimfw 安装失败。"
    rm -f "$ZIM_INSTALLER"
    
    log_success "Zimfw 安装完成。"
    
    # 切换默认 Shell
    CURRENT_SHELL=$(basename "$SHELL")
    if [ "$CURRENT_SHELL" != "zsh" ]; then
        log_info "尝试将默认 Shell 更改为 zsh..."
        ZSH_PATH=$(which zsh)
        if [ -n "$ZSH_PATH" ]; then
            # 尝试更改 shell，如果失败不退出脚本，只是警告
            if [ "$EUID" -eq 0 ]; then
                chsh -s "$ZSH_PATH" root || log_warn "更改 root shell 失败，请手动执行 chsh -s $(which zsh)"
            else
                # 普通用户更改 shell 可能需要密码，这里尝试 sudo -E chsh 或者提示用户
                # 在脚本中交互式输入密码比较困难，通常建议用户最后手动改，或者使用 sudo
                if cmd_exists chsh; then
                    $CMD_PREFIX chsh -s "$ZSH_PATH" "$USER" || log_warn "无法更改默认 Shell，请稍后手动运行: chsh -s $(which zsh)"
                fi
            fi
        fi
    fi
}

configure_zshrc() {
    log_info "正在注入配置到 ~/.zshrc ..."
    
    ZSHRC="${HOME}/.zshrc"
    
    # 幂等性检查
    if grep -q "### --- Added by Setup Script ---" "$ZSHRC"; then
        log_warn "配置标记已存在于 .zshrc，跳过写入。"
    else
        cat <<EOF >> "$ZSHRC"

### --- Added by Setup Script ---

# 1. Path Completion (uv, cargo, local)
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"

# 2. Proxy Settings
EOF
        
        # 如果用户选择持久化代理
        if [[ "$SHOULD_WRITE_PROXY" == "yes" && -n "$PROXY_URL" ]]; then
            cat <<EOF >> "$ZSHRC"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$PROXY_URL"
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
EOF
        fi
        
        cat <<EOF >> "$ZSHRC"

# 3. Modern Tools Init
# Zoxide (Smart cd)
if command -v zoxide > /dev/null; then
  eval "\$(zoxide init zsh)"
fi

# FZF
if command -v fzf > /dev/null; then
  source <(fzf --zsh) 2>/dev/null || true # Fallback for older fzf versions
fi

# 4. Aliases
alias ll='ls -alF'
alias t='tmux'
alias zinstall='source ~/.zshrc'

### --- End of Setup Script ---
EOF
        log_success "配置文件注入完成。"
    fi
}

setup_cron_service() {
    log_info "尝试启动 Crontab 服务..."
    
    if [[ "$OS_NAME" == "darwin" ]]; then
        log_info "macOS 使用 launchd 管理定时任务，无需手动启用 cron 服务。"
        return
    fi
    
    # 检测服务管理器
    if pidof systemd >/dev/null 2>&1; then
        # Systemd
        local cron_srv="cron"
        # RedHat 系通常叫 crond
        if [[ "$OS_NAME" =~ (centos|rhel|fedora|almalinux) ]]; then cron_srv="crond"; fi
        # Arch 系通常叫 cronie
        if [[ "$OS_NAME" =~ (arch|manjaro) ]]; then cron_srv="cronie"; fi
        
        $CMD_PREFIX systemctl enable --now "$cron_srv" || log_warn "无法通过 systemd 启动 cron，请手动检查。"
        
        elif [ -f /etc/init.d/cron ]; then
        # SysVinit
        $CMD_PREFIX /etc/init.d/cron start || log_warn "无法启动 cron (init.d)。"
        $CMD_PREFIX update-rc.d cron defaults >/dev/null 2>&1 || true
        
        elif [ -f /sbin/rc-service ]; then
        # OpenRC (Alpine)
        $CMD_PREFIX rc-update add crond default >/dev/null 2>&1 || true
        $CMD_PREFIX rc-service crond start || log_warn "无法启动 crond (OpenRC)。"
    else
        log_warn "未检测到已知的服务管理器 (systemd/openrc)，跳过 Cron 启动。"
    fi
}

# --- 5. Main Execution Flow ---

main() {
    # 1. 代理询问
    setup_proxy
    
    # 2. 系统检测
    detect_os_and_cmd
    
    # 3. 权限询问
    setup_privileges
    
    # 4. 安装基础软件
    install_packages
    
    # 5. 安装 UV
    install_uv
    install_uv_tools
    
    # 6. 安装/配置 Zimfw (含残留清理)
    setup_zimfw
    
    # 7. 注入 .zshrc
    configure_zshrc
    
    # 8. 启动服务
    setup_cron_service
    
    echo "------------------------------------------------"
    log_success "所有任务执行完毕！"
    log_info "请执行 'zsh' 进入新环境，或者重新登录。"
    echo "------------------------------------------------"
}

# 启动脚本
main
