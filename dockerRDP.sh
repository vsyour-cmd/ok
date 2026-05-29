#!/bin/bash

# ==========================================
# 1. 配置区域 (可以在这里修改你的服务器信息)
# ==========================================
REMOTE_HOST="104.194.83.44"
REMOTE_PORT="10022"
REMOTE_USER="root"

echo "=================================================="
echo " 🚀 正在启动 Phantom-Node 全自动部署程序"
echo "=================================================="

# 提前向用户索要 SSH 密码，用于后续全自动免密配置
# (输入时屏幕不会显示字符，保障安全)
read -s -p "🔑 请输入远程服务器 ($REMOTE_HOST) 的密码: " SSH_PASS
echo -e "\n=> 密码已记录，开始自动化构建...\n"

# 2. Create shared directory on host
echo "=> 准备共享目录..."
mkdir -p $(pwd)/share_box
chmod 777 $(pwd)/share_box

# 3. Generate the Dockerfile
echo "=> 正在生成 Dockerfile..."
cat << 'EOF' > Dockerfile
# Base on Debian Bookworm
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# 新增安装 sshpass 用于全自动处理密码输入
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    lxde xrdp xorgxrdp dbus-x11 sudo python3 curl wget xz-utils ssh \
    fuse ca-certificates locales fonts-wqy-zenhei firefox-esr sshpass \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen \
    && sed -i 's/#user_allow_other/user_allow_other/g' /etc/fuse.conf \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create 'admin' user with password 'admin123'
RUN adduser --gecos "" admin && \
    echo "admin:admin123" | chpasswd && \
    usermod -aG sudo,ssl-cert admin

# Configure LXDE as default & 修复 polkit 弹窗
RUN echo "startlxde" > /home/admin/.xsession && \
    chown admin:admin /home/admin/.xsession && \
    rm -f /etc/xdg/autostart/lxpolkit.desktop

RUN echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

# 生成全自动隧道脚本
RUN { \
    echo '#!/bin/bash'; \
    echo 'KEY_PATH="/root/.ssh/id_rsa"'; \
    echo 'mkdir -p /root/.ssh && chmod 700 /root/.ssh'; \
    echo ''; \
    echo '# [步骤 A] 检查并生成本地密钥'; \
    echo 'if [ ! -f "$KEY_PATH" ]; then'; \
    echo '    echo "[Tunnel] 正在生成 RSA 密钥..."'; \
    echo '    ssh-keygen -t rsa -b 2048 -f "$KEY_PATH" -N "" -q'; \
    echo 'fi'; \
    echo ''; \
    echo '# [步骤 B] 智能免密配置'; \
    echo 'if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST "exit" >/dev/null 2>&1; then'; \
    echo '    if [ -n "$SSH_PASS" ]; then'; \
    echo '        echo "[Tunnel] 首次连接，正在使用环境变量中的密码全自动注册公钥..."'; \
    echo '        sshpass -p "$SSH_PASS" ssh-copy-id -o StrictHostKeyChecking=no -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST >/dev/null 2>&1'; \
    echo '    else'; \
    echo '        echo "[Tunnel] 警告：没有提供密码且未授权，隧道可能建立失败！"'; \
    echo '    fi'; \
    echo 'fi'; \
    echo ''; \
    echo '# [步骤 C] 后台启动隧道 (加入 ServerAliveInterval 防止假死掉线)'; \
    echo 'echo "[Tunnel] 正在建立到 $REMOTE_HOST 的反向 RDP 隧道..."'; \
    echo 'ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -p $REMOTE_PORT -fCNR 3389:localhost:3389 $REMOTE_USER@$REMOTE_HOST'; \
    echo 'echo "[Tunnel] 隧道已在后台运行！"'; \
} > /usr/local/bin/auto-tunnel && chmod +x /usr/local/bin/auto-tunnel

# Generate Entrypoint (将隧道启动加入开机自启)
RUN { \
    echo '#!/bin/bash'; \
    echo 'mkdir -p /run/dbus'; \
    echo 'dbus-uuidgen > /var/lib/dbus/machine-id'; \
    echo 'ln -sf /var/lib/dbus/machine-id /etc/machine-id'; \
    echo 'dbus-daemon --system'; \
    echo ''; \
    echo 'chown -R admin:admin /home/admin'; \
    echo 'rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/xrdp-sesman.pid'; \
    echo 'service ssh start'; \
    echo '/etc/init.d/xrdp start'; \
    echo ''; \
    echo '# 启动自动化隧道'; \
    echo '/usr/local/bin/auto-tunnel'; \
    echo ''; \
    echo 'tail -f /dev/null'; \
} > /entrypoint.sh && chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
EOF

# 4. Clean and build
echo "=> 开始构建 phantom-node 镜像 (请耐心等待)..."
docker rm -f phantom-node 2>/dev/null
docker build -t phantom-node .

# 5. Launch container
echo "=> 正在启动容器，并注入环境变量..."
# 使用 -e 传递环境变量给容器
CONTAINER_ID=$(docker run -d \
  --name phantom-node \
  --restart always \
  --shm-size 2g \
  --cap-add SYS_ADMIN \
  --device /dev/fuse \
  --security-opt apparmor:unconfined \
  -e REMOTE_HOST="$REMOTE_HOST" \
  -e REMOTE_PORT="$REMOTE_PORT" \
  -e REMOTE_USER="$REMOTE_USER" \
  -e SSH_PASS="$SSH_PASS" \
  -v $(pwd)/share_box:/home/admin/Desktop/share_box \
  phantom-node)

CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)

echo "=================================================="
echo " 🎉 部署圆满完成！"
echo "=================================================="
echo " 标识 ID: ${CONTAINER_ID:0:12}"
echo " 内部 IP: $CONTAINER_IP"
echo " 共享目录: $(pwd)/share_box"
echo " 状态: RDP桌面已启动，SSH隧道已全自动打通！"
echo "=================================================="
echo " 💡 现在你可以直接在 104.194.83.44 这台机器上，"
echo "    通过 localhost:3389 连入容器桌面，完全无需手动干预了。"
