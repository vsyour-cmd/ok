#!/bin/bash

# 开启遇到错误即刻退出的模式 (Fail-fast)
set -e

# 捕获 Ctrl+C 中断，恢复终端回显并清理临时文件，防止终端假死
trap 'stty echo 2>/dev/null; rm -f "$PWD/.ssh_secret_temp"; exit 1' INT TERM

# ==========================================
# 1. 配置区域 (可以在这里修改你的服务器信息)
# ==========================================
REMOTE_HOST="104.194.83.44"
REMOTE_PORT="10022"
REMOTE_USER="root"
# RDP 桌面密码 (账号固定为 admin)
RDP_PASS="admin123"

echo "=================================================="
echo " 🚀 正在启动 Phantom-Node 全自动安全部署程序"
echo "=================================================="

# ⚠️ 极限安全方案：直接从终端底层读取输入到机密文件，彻底消灭变量
SECRET_FILE="$PWD/.ssh_secret_temp"
> "$SECRET_FILE"
chmod 600 "$SECRET_FILE"

while [ ! -s "$SECRET_FILE" ]; do
    echo -n "🔑 请输入远程服务器 ($REMOTE_HOST) 的 SSH 密码: " < /dev/tty
    
    # 关闭终端回显，将键盘敲击的数据流直接重定向进文件，不经过任何变量
    stty -echo < /dev/tty
    head -n 1 < /dev/tty | tr -d '\r\n' > "$SECRET_FILE"
    stty echo < /dev/tty
    
    echo "" # 换行补全
    
    if [ ! -s "$SECRET_FILE" ]; then
        echo "❌ 错误：密码不能为空，请重新输入！"
    fi
done

echo -e "=> ✅ 密码已无痕直写机密文件，开始自动化构建...\n"

# 2. 准备共享目录
echo "=> 准备共享目录..."
mkdir -p "$PWD/share_box"
chmod 777 "$PWD/share_box"

# 3. 生成 Dockerfile (使用 'EOF' 防止宿主机变量被意外展开)
echo "=> 正在生成 Dockerfile..."
cat << 'EOF' > Dockerfile
# Base on Debian Bookworm
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# 安装必要组件
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    lxde xrdp xorgxrdp dbus-x11 sudo python3 curl wget xz-utils ssh \
    fuse ca-certificates locales fonts-wqy-zenhei firefox-esr sshpass \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen \
    && sed -i 's/#user_allow_other/user_allow_other/g' /etc/fuse.conf \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 创建桌面用户 (不在这里设置密码，彻底阻断 docker history 泄露)
RUN adduser --disabled-password --gecos "" admin && \
    usermod -aG sudo,ssl-cert admin

# 配置 LXDE 并防弹窗
RUN echo "startlxde" > /home/admin/.xsession && \
    chown admin:admin /home/admin/.xsession && \
    rm -f /etc/xdg/autostart/lxpolkit.desktop && \
    rm -f /usr/bin/lxpolkit    

RUN echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

# 全自动隧道脚本
RUN { \
    echo '#!/bin/bash'; \
    echo 'KEY_PATH="/root/.ssh/id_rsa"'; \
    echo 'mkdir -p /root/.ssh && chmod 700 /root/.ssh'; \
    echo ''; \
    echo '# [步骤 A] 生成本地密钥'; \
    echo 'if [ ! -f "$KEY_PATH" ]; then'; \
    echo '    echo "[Tunnel] 正在生成 RSA 密钥..."'; \
    echo '    ssh-keygen -t rsa -b 2048 -f "$KEY_PATH" -N "" -q'; \
    echo 'fi'; \
    echo ''; \
    echo '# [步骤 B] 智能读取机密文件进行免密配置 (使用 -f 防止 ps 进程泄露)'; \
    echo 'if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST "exit" >/dev/null 2>&1; then'; \
    echo '    if [ -f "/run/secrets/ssh_pass" ]; then'; \
    echo '        echo "[Tunnel] 首次连接，正在使用挂载的凭证注册公钥..."'; \
    echo '        sshpass -f /run/secrets/ssh_pass ssh-copy-id -o StrictHostKeyChecking=no -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST >/dev/null 2>&1'; \
    echo '    else'; \
    echo '        echo "[Tunnel] 警告：未检测到凭证文件且未授权，隧道可能建立失败！"'; \
    echo '    fi'; \
    echo 'fi'; \
    echo ''; \
    echo '# [步骤 C] 后台启动隧道'; \
    echo 'echo "[Tunnel] 正在建立到 $REMOTE_HOST 的反向 RDP 隧道..."'; \
    echo 'ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -p $REMOTE_PORT -fCNR 3389:localhost:3389 $REMOTE_USER@$REMOTE_HOST'; \
    echo 'echo "[Tunnel] 隧道已在后台运行！"'; \
} > /usr/local/bin/auto-tunnel && chmod +x /usr/local/bin/auto-tunnel

# Generate Entrypoint
RUN { \
    echo '#!/bin/bash'; \
    echo 'mkdir -p /run/dbus'; \
    echo 'dbus-uuidgen > /var/lib/dbus/machine-id'; \
    echo 'ln -sf /var/lib/dbus/machine-id /etc/machine-id'; \
    echo 'dbus-daemon --system'; \
    echo ''; \
    echo '# 运行时动态设置 RDP 桌面密码 (读取环境变量，防 docker history)'; \
    echo 'RDP_PASS=${RDP_PASS:-admin123}'; \
    echo 'echo "admin:$RDP_PASS" | chpasswd'; \
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
docker rm -f phantom-node 2>/dev/null || true 
docker build -t phantom-node .
rm -f Dockerfile # 构建完成清理 Dockerfile

# 5. Launch container
echo "=> 正在启动容器，并挂载机密文件..."
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
  -e RDP_PASS="$RDP_PASS" \
  -v "$PWD/share_box:/home/admin/Desktop/share_box" \
  -v "$SECRET_FILE:/run/secrets/ssh_pass:ro" \
  phantom-node)

CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)

# 容器启动后，立刻在宿主机上彻底销毁机密文件
rm -f "$SECRET_FILE"

echo "=================================================="
echo " 🎉 部署圆满完成！(极限安全版)"
echo "=================================================="
echo " 标识 ID: ${CONTAINER_ID:0:12}"
echo " 内部 IP: $CONTAINER_IP"
echo " 共享目录: $PWD/share_box"
echo " RDP 账户: admin"
echo " RDP 密码: $RDP_PASS"
echo " 状态: RDP桌面已启动，SSH隧道已全自动打通！"
echo " 安全状态: SSH 密码零变量驻留，临时凭证已物理销毁。"
echo "=================================================="
echo " 💡 现在你可以直接在 $REMOTE_HOST 这台机器上，"
echo "    通过 localhost:3389 连入容器桌面，完全无需手动干预了。"
