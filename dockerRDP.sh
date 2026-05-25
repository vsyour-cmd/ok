# 1. Create the updated Dockerfile using cat (All comments in English, no Chinese inside)
cat << 'EOF' > Dockerfile
# Base on Debian Bookworm official image
FROM debian:bookworm

# Set non-interactive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Install core packages (Reverted to full LXDE environment for native Debian theme and compatibility)
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create 'admin' user with password 'admin123' and assign to sudo/ssl-cert groups
RUN adduser --gecos "" admin && \
    echo "admin:admin123" | chpasswd && \
    usermod -aG sudo,ssl-cert admin

# Configure LXDE as the default desktop session for the admin user (Restoring your original working configuration)
RUN echo "startlxde" > /home/admin/.xsession && \
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
# Kill any stale rdp/xrdp pid files if they exist\n\
rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/xrdp-sesman.pid\n\
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

# 2. Build the custom Docker image with the stealthy name
echo "Rebuilding the Docker image with LXDE desktop (phantom-node)..."
docker build -t phantom-node .

# 3. Run the container with enhanced security (No -p) and full file-copy permissions (FUSE)
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
echo " Update and Deployment Completed!"
echo " Target ID: ${CONTAINER_ID:0:12}"
echo " Target IP: $CONTAINER_IP"
echo " "
echo " Environment has been restored to LXDE with Debian background."
echo " Use your SSH tunnel to link up and enjoy direct file copying!"
echo "=================================================="
