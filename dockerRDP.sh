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

# Configure LXDE as default & Remove lxpolkit autostart
RUN echo "startlxde" > /home/admin/.xsession && \
    chown admin:admin /home/admin/.xsession && \
    rm -f /etc/xdg/autostart/lxpolkit.desktop

# Bypass X Server restriction
RUN echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

# Generate Entrypoint (优化了写入方式，更清晰易读)
RUN { \
    echo '#!/bin/bash'; \
    echo 'mkdir -p /run/dbus'; \
    echo 'dbus-uuidgen > /var/lib/dbus/machine-id'; \
    echo 'ln -sf /var/lib/dbus/machine-id /etc/machine-id'; \
    echo 'dbus-daemon --system'; \
    echo ''; \
    echo '# Force correct permissions for mounted volumes'; \
    echo 'chown -R admin:admin /home/admin'; \
    echo ''; \
    echo 'rm -f /var/run/xrdp/xrdp.pid /var/run/xrdp/xrdp-sesman.pid'; \
    echo 'service ssh start'; \
    echo '/etc/init.d/xrdp start'; \
    echo ''; \
    echo 'tail -f /dev/null'; \
} > /entrypoint.sh && chmod +x /entrypoint.sh

# 创建独立可执行的隧道脚本 'start-tunnel' (加入智能免密配置逻辑)
RUN { \
    echo '#!/bin/bash'; \
    echo 'REMOTE_USER="root"'; \
    echo 'REMOTE_HOST="104.194.83.44"'; \
    echo 'REMOTE_PORT="10022"'; \
    echo 'KEY_PATH="$HOME/.ssh/id_rsa"'; \
    echo ''; \
    echo 'mkdir -p $HOME/.ssh'; \
    echo 'chmod 700 $HOME/.ssh'; \
    echo ''; \
    echo '# 1. 检测本地是否存在SSH密钥，不存在则静默生成'; \
    echo 'if [ ! -f "$KEY_PATH" ]; then'; \
    echo '    echo "=> 正在生成本地 SSH 密钥..."'; \
    echo '    ssh-keygen -t rsa -b 2048 -f "$KEY_PATH" -N "" -q'; \
    echo 'fi'; \
    echo ''; \
    echo '# 2. 使用 BatchMode 测试是否已经可以免密登录'; \
    echo 'if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST "exit" >/dev/null 2>&1; then'; \
    echo '    echo "=> 首次连接或密钥未认证！"'; \
    echo '    echo "=> 请根据提示输入远程服务器 ($REMOTE_HOST) 的密码，以配置永久免密登录："'; \
    echo '    # ssh-copy-id 会要求输入一次密码，然后自动将公钥写入远程服务器的 authorized_keys'; \
    echo '    ssh-copy-id -o StrictHostKeyChecking=no -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST'; \
    echo 'fi'; \
    echo ''; \
    echo '# 3. 启动后台反向隧道'; \
    echo 'echo "=> 正在建立反向 SSH 隧道..."'; \
    echo 'ssh -o StrictHostKeyChecking=no -p $REMOTE_PORT -fCNR 3389:localhost:3389 $REMOTE_USER@$REMOTE_HOST'; \
    echo 'echo "=> 隧道建立完成并在后台运行！"'; \
} > /usr/local/bin/start-tunnel && chmod +x /usr/local/bin/start-tunnel

CMD ["/entrypoint.sh"]
