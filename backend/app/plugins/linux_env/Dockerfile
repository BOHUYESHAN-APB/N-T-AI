FROM alpine:3.23

ARG USE_CHINA_MIRROR=false

# 1. Setup Mirrors (must be first to speed up apk)
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories; \
    fi

# 2. Create User (Security)
# -S = system user, -G = group, -s = shell
RUN addgroup -S ntai && adduser -S ntai -G ntai -s /bin/bash

# 3. Install dependencies
# xvfb: Virtual Display
# fluxbox: Minimal Window Manager
# x11vnc: VNC Server
# python3/pip: For Python tasks and websockify
# bash: Shell
# supervisor: Process manager
# git: To fetch noVNC
RUN apk add --no-cache \
    xvfb \
    x11vnc \
    fluxbox \
    python3 \
    py3-pip \
    bash \
    supervisor \
    git \
    socat \
    ttf-freefont \
    procps \
    py3-numpy py3-pandas py3-requests

# 4. Install noVNC
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify /opt/novnc/utils/websockify \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html \
    && chown -R ntai:ntai /opt/novnc

# 5. Setup Workspace
WORKDIR /workspace
RUN chown -R ntai:ntai /workspace

# Configuration
ENV DISPLAY=:0
ENV RESOLUTION=1280x800
ENV HOME=/home/ntai

# Copy Supervisor config
COPY supervisord.conf /etc/supervisord.conf

# Switch to non-root user
USER ntai

# Expose ports
EXPOSE 6080 5900

# Start Supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
