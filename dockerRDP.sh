# 1. 在物理机当前路径下创建共享文件夹，并赋予最高权限（防止容器内普通用户无法写入）
echo "Creating shared directory on host..."
mkdir -p $(pwd)/share_box
chmod 777 $(pwd)/share_box

# 2. 生成 Dockerfile (保持 LXDE 桌面和核心组件)
cat << 'EOF' > Dockerfile
# Base on Debian Bookworm official image
FROM debian:bookworm

# Set non-interactive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Install core packages including fuse
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    lxde \
    xrdp \
    xorgxrdp \
    dbus-x11 \
    sudo \
    python3 \
    curl \
    wget \
    xz-utils \
    ssh \
    fuse \
    && sed -i 's/#user_allow_other/user_allow_other/g' /etc/fuse.conf \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create 'admin' user with password 'admin123'
RUN adduser --gecos "" admin && \
    echo "admin:admin123" | chpasswd && \
    usermod -aG sudo,ssl-cert admin

# Configure LXDE as the default desktop session
RUN echo "startlxde" > /home/admin/.xsession && \
    chown admin:admin /home/admin/.xsession

# Bypass X Server startup restrictions
RUN echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

# Generate the entrypoint script
RUN echo '#!/bin/bash\n\
mkdir -p /run/dbus\n\
dbus-uuidgen > /var/lib/dbus/machine-id\n\
ln -sf /var/lib/dbus/machine-id /etc/machine-id\n\
dbus-daemon --system\n\
\n\
rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/xrdp-sesman.pid\n\
service ssh start\n\
/etc/init.d/xrdp start\n\
\n\
tail -f /dev/null' > /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Execute the entrypoint script
CMD ["/entrypoint.sh"]
EOF

# 3. 清理旧容器并重新编译
echo "Cleaning up old containers and rebuilding phantom-node..."
docker rm -f phantom-node 2>/dev/null
docker build -t phantom-node .

# 4. 启动容器：加入 -v 参数，将宿主机的 share_box 挂载到 Linux 桌面上
echo "Launching the container with volume mount..."
CONTAINER_ID=$(docker run -d \
  --name phantom-node \
  --shm-size 2g \
  --cap-add SYS_ADMIN \
  --device /dev/fuse \
  --security-opt apparmor:unconfined \
  -v $(pwd)/share_box:/home/admin/Desktop/share_box \
  phantom-node)

# 5. 获取内网 IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)

echo "=================================================="
echo " 🚀 Deployment Completed Successfully!"
echo " Target ID: ${CONTAINER_ID:0:12}"
echo " Target IP: $CONTAINER_IP"
echo " Shared Directory: $(pwd)/share_box"
echo " "
echo " [下一步操作指南]"
echo " 1. 建立隧道: ssh -L 3389:$CONTAINER_IP:3389 user@your_host_ip"
echo " 2. 连接桌面后，你会看到桌面上多了一个 'share_box' 文件夹。"
echo " 3. 把物理机的文件扔进刚才创建的 $(pwd)/share_box 目录，系统内秒级同步！"
echo "=================================================="
