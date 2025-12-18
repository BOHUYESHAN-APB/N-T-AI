FROM alpine:latest

# Install dependencies
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
    procps

# Install noVNC
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify /opt/novnc/utils/websockify \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# Install common Python tools for the agent (Pandas, Requests, etc.)
# Note: Alpine compiles pandas/numpy from source which takes forever. 
# Using --only-binary or pre-built packages if possible, or sticking to system packages.
# For Alpine, it's often better to use 'py3-pandas' 'py3-numpy' from apk if available to avoid compilation hell.
RUN apk add --no-cache py3-numpy py3-pandas py3-requests

# Setup Workspace
WORKDIR /workspace

# Configuration
ENV DISPLAY=:0
ENV RESOLUTION=1280x800

# Copy Supervisor config
COPY supervisord.conf /etc/supervisord.conf

# Expose ports
EXPOSE 6080 5900

# Start Supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
