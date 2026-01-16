#!/data/data/com.termux/files/usr/bin/bash

# ==============================================================================
# 0. 预备知识：下载与安装 (手动步骤)
# ==============================================================================
# 在运行此脚本前，请确保你已经安装了以下两个 APP：
#
# [下载地址]
# Termux App: https://github.com/termux/termux-app/releases
# Termux API: https://github.com/termux/termux-api/releases
#
# [APK 版本选择指南 - 该下哪个？]
# 1. termux-app_..._arm64-v8a.apk
#    -> 【推荐】适合 95% 的现代安卓手机（近5-6年的手机基本都是这个）。
# 2. termux-app_..._armeabi-v7a.apk
#    -> 适合非常老旧的手机（32位系统）。
# 3. termux-app_..._x86 / x86_64.apk
#    -> 适合在电脑模拟器、平板或 Chromebook 上运行。
# 4. termux-app_..._universal.apk
#    -> 【懒人包】包含所有架构，文件很大。如果你不知道自己手机是什么架构，选这个准没错。
#
# [Termux:API 是什么？]
# Termux 本体只是一个终端，没法直接访问手机硬件（相机/麦克风/GPS）。
# 这个 APP 相当于一个桥梁，让脚本能调用安卓系统的功能。
# 必须先安装这个 APP，才能在命令行里使用 termux-camera-photo 等命令。
# ==============================================================================

echo -e "\033[32m[1/5] 正在更新系统软件源...\033[0m"
# 更新所有包，-y 表示自动确认
pkg update -y && pkg upgrade -y




echo -e "\033[32m[2/5] 申请存储权限...\033[0m"
# 执行后手机会弹窗，必须点“允许”！
if [ ! -d "~/storage" ]; then
    termux-setup-storage
    echo "请在弹窗中点击【允许】，然后按回车继续..."
    read -r
else
    echo "存储权限看起来已经有了。"
fi
# ==============================================================================
# termux-setup-storage 这个命令干了两件事，而不仅仅是弹窗：
# 1. 向安卓系统讨要权限（弹窗）。
# 2. 在 Termux 内部创建一个名叫 storage 的文件夹，里面放满了通往手机各个角落的快速方式。
# 当你运行完 termux-setup-storage 后，Termux 会在你的家目录（~）下生成这样一个结构：
#    ~/storage/  (这是 Termux 里的文件夹)
#    ├── dcim       --> 指向 /sdcard/DCIM (相册)
#    ├── downloads  --> 指向 /sdcard/Download (下载)
#    ├── movies     --> 指向 /sdcard/Movies
#    ├── pictures   --> 指向 /sdcard/Pictures
#    ├── music      --> 指向 /sdcard/Music
#    └── shared     --> 指向 /sdcard (这才是真正的 SD 卡根目录！)
# ==============================================================================




echo -e "\033[32m[3/5] 安装基础开发工具...\033[0m"
# openssh: 远程连接
# vim: 编辑器
# git: 代码同步
# wget/curl: 下载工具
# termux-api: 调用硬件的命令行工具
# termux-services: 守护进程管理（让sshd持久化）
# python: 你的老本行
# tree: 查看目录结构
# jq: 处理 json 文件
pkg install -y openssh vim git wget curl termux-api termux-services python tree jq
# ==============================================================================
# 假如使用 vim 等工具出现了如下问题：
#     CANNOT LINK EXECUTABLE "vim": library "libsodium.so" not found
#     CANNOT LINK EXECUTABLE "vim": library "libacl.so" not found
# 可以尝试安装如下库来解决：
#     pkg install libsodium libacl
# ==============================================================================



echo -e "\033[32m[4/5] 配置 SSH 服务 (持久化启动)...\033[0m"
# 安装服务脚本后，需要重启 Termux 才能生效，这里先做配置
# 启用 sshd 服务，这样以后打开 Termux 就会自动启动 SSH，不用手输 sshd
sv-enable sshd

echo "----------------------------------------------------"
echo "【SSH 配置向导】"
echo "1. 默认端口是: 8022 (不是 22!)"
echo "2. 查看当前用户名: $(whoami)"
echo "3. 查看当前 IP: 输入 ifconfig"
echo "4. 电脑连接命令: ssh -p 8022 $(whoami)@<手机IP>"
echo "----------------------------------------------------"
echo "! 现在，请设置 SSH 密码 (输入两次，看不见是正常的):"
passwd




echo -e "\033[32m[5/5] 验证 API 功能...\033[0m"
# 检查是否安装了 Termux:API APP
echo "尝试获取电池信息测试 API..."
termux-battery-status
if [ $? -ne 0 ]; then
    echo -e "\033[31m[错误] 无法调用 API。请确保你安装了 'Termux:API' APP 并在设置中授予了权限。\033[0m"
else
    echo -e "\033[32mAPI 调用成功！\033[0m"
fi




echo -e "\033[32m[完成] 初始化脚本执行完毕！\033[0m"
echo "===================================================="
echo "常用备忘："
echo "1. 拍照命令: termux-camera-photo -c 0 /sdcard/photo.jpg"
echo "   (-c 0 是后置镜头, -c 1 是前置)"
echo "2. 开启简单网页服: python -m http.server 8080"
echo "3. 防止断连: 请务必在通知栏点击 'Acquire wakelock'"
echo "4. 重启 Termux 以使 termux-services (SSHD自启) 生效"
echo "===================================================="
