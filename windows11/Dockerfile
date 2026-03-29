# ==========================================
# 阶段 1：利用官方 uv 镜像获取二进制文件（为了通用和快）
# ==========================================
FROM ghcr.io/astral-sh/uv:latest AS uv_bin

# ==========================================
# 阶段 2：构建主体环境
# ==========================================
# 注意：nvcr.io 的镜像标签通常是 YY.MM 格式。
ARG BASE_IMAGE=nvcr.io/nvidia/pytorch:26.02-py3
FROM ${BASE_IMAGE}

# 设置环境变量，避免 apt 安装时弹出交互确认
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 通用参数配置，方便后续在 Compose 中覆盖
ARG SSH_PORT_INTERNAL=22222
ARG ROOT_PASSWORD=123456

# 1. 安装基础系统工具和 Zsh
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    zsh \
    git \
    curl \
    wget \
    vim \
    tmux \
    htop \
    net-tools \
    iputils-ping \
    sudo \
    locales \
    && rm -rf /var/lib/apt/lists/*

# 2. 配置语言环境 (解决 Zsh 中文乱码)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# 3. 配置核心开发工具

# --- 安装 uv (Python 包管理神器) ---
# 从第一阶段复制二进制文件，比 curl 安装更通用且稳定
COPY --from=uv_bin /uv /uvx /bin/

# --- 配置 SSH 服务 ---
RUN mkdir /var/run/sshd \
    # 修改 root 密码
    && echo "root:${ROOT_PASSWORD}" | chpasswd \
    # 修改默认端口为 22222
    && sed -i "s/#Port 22/Port ${SSH_PORT_INTERNAL}/" /etc/ssh/sshd_config \
    # 允许 root 登录
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    # 允许密码登录 (后续安全高了可以改为密钥登录)
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# --- 配置 Zsh 和 Zimfw (为 root 用户) ---
# 将默认 shell 改为 zsh
RUN chsh -s $(which zsh) \
    # 安装 Zimfw (全自动安装，无需交互)
    && curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh \
    # 在 .zshrc 末尾添加 uv 的自动补全
    && echo 'eval "$(uv generate-shell-completion zsh)"' >> ~/.zshrc

# 声明开放你在 Dockerfile 里配置的内部 SSH 端口
EXPOSE ${SSH_PORT_INTERNAL}

# 预留后续拓展端口的声明 (纯描述性，非强制)
EXPOSE 22223-22227

# 启动 SSH 服务，并保持前台运行以免容器退出
CMD ["/usr/sbin/sshd", "-D"]