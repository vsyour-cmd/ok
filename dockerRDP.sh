#!/bin/bash
#
# Configure And Start RDP FOR Docker Debian Linux.
#
#


# 1. Create shared directory on host
echo "Creating shared directory on host..."
mkdir -p $(pwd)/share_box
chmod 777 $(pwd)/share_box

# 2. Generate Dockerfile
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

# 3. Clean up old containers and rebuild phantom-node
echo "Cleaning up old containers and rebuilding phantom-node..."
docker rm -f phantom-node 2>/dev/null
docker build -t phantom-node .

# 4. Launch the container with volume mount
echo "Launching the container with volume mount..."
CONTAINER_ID=$(docker run -d \
  --name phantom-node \
  --shm-size 2g \
  --cap-add SYS_ADMIN \
  --device /dev/fuse \
  --security-opt apparmor:unconfined \
  -v $(pwd)/share_box:/home/admin/Desktop/share_box \
  phantom-node)

# 5. Output connection details
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)

echo "=================================================="
echo " Deployment Completed Successfully!"
echo " Target ID: ${CONTAINER_ID:0:12}"
echo " Target IP: $CONTAINER_IP"
echo " Shared Directory: $(pwd)/share_box"
echo " "
echo " [Next Steps]"
echo " 1. Create SSH tunnel: ssh -L 3389:$CONTAINER_IP:3389 user@your_host_ip"
echo " 2. Connect via RDP. You will find a 'share_box' folder on the LXDE desktop."
echo " 3. Drop files into $(pwd)/share_box on your host machine to instantly sync them."
echo "=================================================="
