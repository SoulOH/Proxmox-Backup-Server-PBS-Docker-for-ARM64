FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive \
    REPO=pbs-docker \
    IMAGE=pbs

LABEL org.opencontainers.image.source="local/pbs-arm64" \
      org.opencontainers.package.name="proxmox-backup-server-arm64"

# ---- Basic Tools / 基础工具 ----
# Instead of downloading binaries (tini/gosu/curl/wget) from GitHub, use the apt versions for better stability.
# 这里不再从 GitHub 拉取二进制文件，而是直接使用 apt 版本的 tini/gosu/curl/wget，稳定性更好。
RUN ln -s /bin/true /usr/bin/systemctl

# Install dependencies / 安装依赖
RUN apt-get -qq update -y && \
    apt-get -qq dist-upgrade -y --no-install-recommends -o Dpkg::Options::="--force-confold" && \
    apt-get -qq install -y --no-install-recommends \
    less netcat-openbsd iputils-ping iputils-tracepath net-tools \
    curl ca-certificates nano apt-utils dstat ifupdown2 \
    gnupg gosu tini

# Add repository and install modules / 添加软件源并安装模块
RUN apt -qq modernize-sources -y

# Add PiPBS repository (Unofficial PBS for ARM/Debian) / 添加 PiPBS 仓库（适用于 ARM/Debian 的非官方 PBS）
RUN cat <<EOF > /etc/apt/sources.list.d/pipbs.sources
Types: deb
URIs: https://dexogen.github.io/pipbs/
Suites: trixie
Components: main
Signed-By: /etc/apt/trusted.gpg.d/pipbs.gpg
EOF

# Enable contrib component and add GPG key / 启用 contrib 组件并添加 GPG 密钥
RUN sed -i '/Components:/s/main$/main contrib/g' /etc/apt/sources.list.d/debian.sources && \
    curl -fsSL https://dexogen.github.io/pipbs/gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/pipbs.gpg

# Install Proxmox Backup Server packages / 安装 PBS 相关软件包
RUN apt-get update && \
    apt-get install -y \
    --no-install-recommends \
    proxmox-backup-server \
    proxmox-backup-client \
    proxmox-backup-docs \
    proxmox-widget-toolkit \
    proxmox-backup-file-restore \
    pve-xtermjs \
    zfsutils-linux

# Disable enterprise repo to avoid errors / 禁用企业源以避免报错
RUN echo '' > /etc/apt/sources.list.d/pbs-enterprise.sources

# ---- Copy entrypoint / 拷贝启动脚本 ----
COPY entrypoint.sh /entrypoint.sh

# ---- Create Directories & Permissions / 创建目录与权限 ----
RUN mkdir -p /etc/proxmox-backup /var/log/proxmox-backup /var/lib/proxmox-backup /var/log/proxmox-backup/tasks/ /run/proxmox-backup && \
    # Ensure 'backup' user exists / 确保 backup 用户存在
    id backup 2>/dev/null || useradd -r -s /usr/sbin/nologin backup && \
    # Adjust shell and groups based on original image logic / 按原镜像逻辑调整 shell 和用户组
    usermod -s /bin/bash backup && \
    usermod -a -G backup root && \
    usermod -g backup root && \
    # Optional: 'sudo' group might not be strictly necessary in container, but kept for consistency / 可选：sudo 组在容器里不一定有必要，但按原镜像保留
    usermod -aG sudo backup 2>/dev/null || true && \
    # Set ownership and permissions / 设置所有权和权限
    chown -R backup:backup /etc/proxmox-backup && \
    chown -R backup:backup /var/log/proxmox-backup && \
    chown -R backup:backup /var/lib/proxmox-backup && \
    chmod -R 700 /etc/proxmox-backup && \
    chmod +x /entrypoint.sh

# ---- Use tini as init process to handle signals, calling entrypoint / 使用 tini 作为 init 进程处理信号，并调用 entrypoint ----
ENTRYPOINT [ "tini", "--", "/entrypoint.sh" ]

CMD ["/bin/bash"]
