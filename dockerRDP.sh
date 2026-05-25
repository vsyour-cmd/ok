# 1. Create Dockerfile using cat (All comments in English, no Chinese inside)
cat << 'EOF' > Dockerfile
# Base on Debian Bookworm official image
FROM debian:bookworm

# Set non-interactive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Install core packages (stealth mode desktop components)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    xfce4 \
    xfce4-goodies \
    xrdp \
    xorgxrdp \
    dbus-x11 \
    sudo \
    python3 \
    curl \
    wget \
    xz-utils \
    ssh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create 'admin' user with password 'admin123' and assign to sudo/ssl-cert groups
RUN adduser --gecos "" admin && \
    echo "admin:admin123" | chpasswd && \
    usermod -aG sudo,ssl-cert admin

# Configure default session for the admin user
RUN echo "startxfce4" > /home/admin/.xsession && \
    chown admin:admin /home/admin/.xsession

# Bypass X Server startup restrictions for headless environments
RUN echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

# Generate the entrypoint script to handle internal services
RUN echo '#!/bin/bash\n\
# Initialize DBUS to prevent components from crashing\n\
mkdir -p /run/dbus\n\
dbus-uuidgen > /var/lib/dbus/machine-id\n\
ln -sf /var/lib/dbus/machine-id /etc/machine-id\n\
dbus-daemon --system\n\
\n\
# Start SSH service\n\
service ssh start\n\
\n\
# Start XRDP service\n\
/etc/init.d/xrdp start\n\
\n\
# Keep the container running\n\
tail -f /dev/null' > /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Execute the entrypoint script on container start
CMD ["/entrypoint.sh"]
EOF

# 2. Build the custom Docker image with a stealthy name
echo "Building the Docker image (phantom-node)..."
docker build -t phantom-node .

# 3. Run the container and capture its ID
echo "Launching the container..."
CONTAINER_ID=$(docker run -d \
  --shm-size 2g \
  --cap-add SYS_ADMIN \
  --device /dev/fuse \
  --security-opt apparmor:unconfined \
  phantom-node)

# 4. Get the internal IP address of the newly created container
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)

echo "=================================================="
echo " Deployment Completed Successfully!"
echo " Target ID: ${CONTAINER_ID:0:12}"
echo " Target IP: $CONTAINER_IP"
echo " "
echo " Use the following command on your client to create the SSH tunnel:"
echo " ssh -L 3389:$CONTAINER_IP:3389 user@your_host_ip"
echo "=================================================="
