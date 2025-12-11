#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

###############################################################################
# Architecture check
###############################################################################
ARCH="$(uname -m)"

case "$ARCH" in
    aarch64|arm64)
        # ARM64 – OK, continue
        ;;
    *)
        cat <<EOF

=======================================================
  ERROR: This image is built for ARM64 only.

  Detected host architecture : ${ARCH}
  Required architecture       : arm64 / aarch64

  You are most likely running on an x86/amd64 host.
  This ARM64-only image will NOT run on x86/amd64.

  What to do next:
    - If your host is x86/amd64:
        * Stop using arm64-* tags (e.g. arm64-latest, arm64-4.1.0).
        * Pull an image that is built for x86/amd64 instead.

    - If your host is supposed to be ARM64:
        * Check your Docker setup and verify 'uname -m' prints arm64/aarch64.

  This container will now exit.
=======================================================

EOF
        exit 1
        ;;
esac

###############################################################################
# Logging helpers
###############################################################################
pbs_log() {
    local type="$1"; shift
    printf '%s [%s] [Entrypoint]: %s\n' "$(date --rfc-3339=seconds)" "$type" "$*"
}

pbs_note() {
    pbs_log "Note" "$@"
}

pbs_warn() {
    pbs_log "Warn" "$@" >&2
}

pbs_error() {
    pbs_log "ERROR" "$@" >&2
    exit 1
}

###############################################################################
# Environment / configuration helpers
###############################################################################
docker_verify_minimum_env() {
    if [[ -z "${ROOT_PASSWORD:-}" ]]; then
        pbs_error $'Password option is not specified\n\tYou need to specify ROOT_PASSWORD'
    fi
}

docker_setup_env() {
    # Mark whether PBS users already exist
    if [[ -f "/etc/proxmox-backup/user.cfg" ]]; then
        USERS_ALREADY_EXISTS="true"
    else
        USERS_ALREADY_EXISTS=""
    fi
}

docker_setup_pbs() {
    pbs_note "Initializing PBS users and root password"

    # 1. Ensure root@pam exists in PBS and is enabled / 确保 PBS 里有 root@pam 并启用
    proxmox-backup-manager user update root@pam --enable 1 || true

    # 2. Directly change system root password (equivalent to running passwd in container) / 直接改系统 root 密码（等价于在容器里执行 passwd）
    echo "root:${ROOT_PASSWORD}" | chpasswd

    pbs_note "root@pam enabled and system root password updated via ROOT_PASSWORD"

    # If admin ACL is needed, add it here: / 如需管理员 ACL，可以在这里加：
    # proxmox-backup-manager acl update / Admin --auth-id root@pam
}

###############################################################################
# One-time filesystem / package configuration
###############################################################################
fix_permissions() {
    # Fix permissions / 权限修正
    chown -R backup:backup /etc/proxmox-backup || true
    chown -R backup:backup /var/log/proxmox-backup || true
    chown -R backup:backup /var/lib/proxmox-backup || true
    chown -R backup:backup /run/proxmox-backup || true
    chmod -R 700 /etc/proxmox-backup || true
}

configure_postfix() {
    local relay_host
    relay_host="${RELAY_HOST:-ext.home.local}"

    if [[ -f /etc/postfix/main.cf ]]; then
        sed -i "s/RELAY_HOST/${relay_host}/" /etc/postfix/main.cf || true
    fi
}

configure_repositories() {
    local pbs_enterprise
    pbs_enterprise="${PBS_ENTERPRISE:-no}"

    if [[ "${pbs_enterprise}" != "yes" ]]; then
        rm -f /etc/apt/sources.list.d/pbs-enterprise.list 2>/dev/null || true
    fi
}

configure_timezone() {
    if [[ -z "${TZ:-}" ]]; then
        return
    fi

    echo "Setting timezone to ${TZ}..."

    # 1. Write the timezone to /etc/timezone.
    #    Proxmox UI and many Debian-based tools read this file to determine the configured timezone.
    # 1. 将时区写入 /etc/timezone。
    #    Proxmox 的界面和许多基于 Debian 的工具都会读取这个文件来确定当前配置的时区。
    echo "${TZ}" > /etc/timezone

    # 2. Reconfigure /etc/localtime.
    #    This file controls the actual system time calculation (localtime).
    #    We remove the old link and create a new symbolic link to the correct zoneinfo file.
    # 2. 重新配置 /etc/localtime。
    #    这个文件控制实际的系统时间计算（本地时间）。
    #    我们删除旧链接，并创建一个指向正确 zoneinfo 文件的新符号链接。
    rm -f /etc/localtime
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime

    # 3. Apply changes using dpkg-reconfigure.
    #    This ensures that the system fully recognizes the change in a non-interactive way.
    # 3. 使用 dpkg-reconfigure 应用更改。
    #    这确保系统以非交互方式完全识别时区更改。
    dpkg-reconfigure -f noninteractive tzdata
}

###############################################################################
# Service startup helpers
###############################################################################
start_pbs_api() {
    # Start API (Note the arm64 path) / 启动 API（注意 arm64 路径）
    echo -n "Starting Proxmox backup API..."
    /usr/lib/aarch64-linux-gnu/proxmox-backup/proxmox-backup-api &

    # Wait for PID file
    while true; do
        if [[ ! -f /run/proxmox-backup/api.pid ]]; then
            echo -n "..."
            sleep 3
        else
            break
        fi
    done
    echo "OK"
}

start_postfix() {
    echo "Starting Postfix..."
    /etc/init.d/postfix start || ok=1
}

###############################################################################
# Main
###############################################################################
main() {
    docker_verify_minimum_env
    docker_setup_env

    fix_permissions
    configure_postfix
    configure_repositories

    # Rsyslog has been removed from this image; PBS will log to its own files.
    # 本镜像不再启动 rsyslog，PBS 会写入自身日志文件。
    start_pbs_api

    # If user.cfg does not exist, it's the first run, so initialize root / 如果没有 user.cfg，说明是第一次启动，就初始化 root
    if [[ -z "${USERS_ALREADY_EXISTS:-}" ]]; then
        docker_setup_pbs
    else
        pbs_note "Existing user configuration found, skipping initial PBS user setup"
        # Even with existing user.cfg, ensure system root password and enabled status match ROOT_PASSWORD / 即使有旧的 user.cfg，我们仍然确保系统 root 密码和启用状态符合 ROOT_PASSWORD
        proxmox-backup-manager user update root@pam --enable 1 || true
        echo "root:${ROOT_PASSWORD}" | chpasswd
        pbs_note "Updated system root password from ROOT_PASSWORD on existing setup"
    fi

    configure_timezone

    echo "Running PBS..."
    exec gosu backup /usr/lib/aarch64-linux-gnu/proxmox-backup/proxmox-backup-proxy "$@"
}

main "$@"
