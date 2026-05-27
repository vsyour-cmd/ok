#!/bin/bash

# 1. Create shared directory on host
echo "Preparing shared volume..."
mkdir -p $(pwd)/share_box
chmod 777 $(pwd)/share_box

# 2. Generate the Dockerfile
cat << 'EOF' > Dockerfile
# Base on Debian Bookworm
FROM debian:bookworm

# Set non-interactive mode and English Environment
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install core packages, Firefox dependencies (for Tor), and CJK font for rendering
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
    ca-certificates \
    locales \
    fonts-wqy-zenhei \
    firefox-esr \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen \
    && sed -i 's/#user_allow_other/user_allow_other/g' /etc/fuse.conf \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create 'admin' user with password 'admin123'
RUN adduser --gecos "" admin && \
    echo "admin:admin123" | chpasswd && \
    usermod -aG sudo,ssl-cert admin

# Configure LXDE as default
RUN echo "startlxde" > /home/admin/.xsession && \
    chown admin:admin /home/admin/.xsession

# Bypass X Server restriction
RUN echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

# Generate Entrypoint (移除了自动 SSH，仅保留系统级服务)
RUN echo '#!/bin/bash\n\
mkdir -p /run/dbus\n\
dbus-uuidgen > /var/lib/dbus/machine-id\n\
ln -sf /var/lib/dbus/machine-id /etc/machine-id\n\
dbus-daemon --system\n\
\n\
# Force correct permissions for mounted volumes\n\
chown -R admin:admin /home/admin\n\
\n\
rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/xrdp-sesman.pid\n\
service ssh start\n\
/etc/init.d/xrdp start\n\
\n\
tail -f /dev/null' > /entrypoint.sh && \
    chmod +x /entrypoint.sh

# 创建独立可执行的隧道脚本 'start-tunnel'
RUN echo '#!/bin/bash\n\
echo "Initiating reverse SSH tunnel..."\n\
ssh -o StrictHostKeyChecking=no -p 10022 -fCNR 3389:localhost:3389 root@104.194.83.44\n\
echo "Tunnel established in background."\n\
' > /usr/local/bin/start-tunnel && \
    chmod +x /usr/local/bin/start-tunnel

CMD ["/entrypoint.sh"]
EOF

# 3. Clean and build
echo "Rebuilding phantom-node..."
docker rm -f phantom-node 2>/dev/null
docker build -t phantom-node .

# 4. Launch container
echo "Launching container with full capabilities..."
# 保留 --restart always 实现开机自启
CONTAINER_ID=$(docker run -d \
  --name phantom-node \
  --restart always \
  --shm-size 2g \
  --cap-add SYS_ADMIN \
  --device /dev/fuse \
  --security-opt apparmor:unconfined \
  -v $(pwd)/share_box:/home/admin/Desktop/share_box \
  phantom-node)

CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)

echo "=================================================="
echo " Target ID: ${CONTAINER_ID:0:12}"
echo " Target IP: $CONTAINER_IP"
echo " Shared Directory: $(pwd)/share_box"
echo " How to connect tunnel: Type 'start-tunnel' inside container"
echo "=================================================="
echo " Initializing TTY drop-in in 5 seconds..."

sleep 5

# 5. Exec into the node
docker exec -it $CONTAINER_ID bash < /dev/tty
