#!/usr/bin/env bash
set -euo pipefail

# ================= Config Section / 配置区域 =================
# Image name (including Docker Hub username) / 镜像名（包含 Docker Hub 用户名）
IMAGE_NAME="souloh/pbs"
# Path to the file that stores the last built version / 记录上次构建版本号的文件路径
VERSION_FILE="last_version.txt"

# PiPBS repository (must match Dockerfile) / PiPBS 仓库（需与 Dockerfile 中保持一致）
# https://dexogen.github.io/pipbs/dists/trixie/main/binary-arm64/Packages
REPO_URL="https://dexogen.github.io/pipbs/dists/trixie/main/binary-arm64/Packages"
# If you are on x86_64, change binary-arm64 to binary-amd64 / 如果你是 x86_64 架构，可以把 binary-arm64 改成 binary-amd64
# ===========================================

# Change working directory to the script location / 切换到脚本所在目录
cd "$(dirname "$0")"

# Logging helper / 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "=== Start smart update check (PiPBS) ==="

# 1. Fetch latest version from remote repository / 获取远程仓库的最新版本号
# Logic: download Packages index -> locate 'Package: proxmox-backup-server' block -> extract 'Version' field
# 逻辑：下载 Packages 索引 -> 找到 Package: proxmox-backup-server 这一段 -> 提取 Version 字段
log "Checking remote PiPBS repository version..."

# Use curl to stream the index without saving to disk / 使用 curl 下载索引流，不保存文件，直接管道处理
# grep -A 10: show 10 lines after the matched line to ensure we see the Version field
# grep -A 10：找到匹配行后多显示 10 行，确保能找到 Version
# awk is used to extract the version field precisely / awk 用于精确提取版本号
REMOTE_VERSION=$(
    curl -fsSL "$REPO_URL" \
    | grep -A 10 "^Package: proxmox-backup-server$" \
    | grep "^Version:" \
    | head -n 1 \
    | awk '{print $2}'
)

if [[ -z "${REMOTE_VERSION}" ]]; then
    log "Error: failed to get proxmox-backup-server version from PiPBS. Check network or repo URL: $REPO_URL"
    exit 1
fi

log "Remote latest version: $REMOTE_VERSION"

# 2. Read last recorded local version / 读取本地记录的版本
if [[ -f "$VERSION_FILE" ]]; then
    LAST_VERSION=$(<"$VERSION_FILE")
else
    LAST_VERSION="none"
fi

# 3. Compare versions / 比对版本
if [[ "$REMOTE_VERSION" == "$LAST_VERSION" ]]; then
    log "Already up to date ($LAST_VERSION), no build needed."
    log "=== Job finished (no-op) ==="
    exit 0
fi

log "New version detected! (local: $LAST_VERSION -> remote: $REMOTE_VERSION)"

# ===========================================
# The following steps only run when an update is detected / 下面是真正干活的部分，只有上面检测到更新才会执行
# ===========================================

log "Start building image..."

# 4. Build image / 构建镜像
# Note: keep --no-cache to ensure apt-get fetches the latest packages
# 注意：这里依然要加 --no-cache，确保 apt-get 能拉到最新的包
# Use explicit platform to build linux/arm64 image (for buildx or multi-arch setups)
# 使用显式 platform 参数构建 linux/arm64 镜像（适用于 buildx 或多架构环境）
if docker build \
    --pull \
    --no-cache \
    --platform linux/arm64 \
    -t "${IMAGE_NAME}:latest" \
    .; then
    log "Build succeeded."
else
    log "Build failed!"
    exit 1
fi

# 5. Verify version inside container (double check) / 再次验证容器内版本（双重保险）
# Sometimes the repo is updated but CDN is not synced, so apt install may still get an older version
# 有时候源更新了，但 CDN 没同步，导致 apt install 还是旧版，这里做一个校验
# NOTE: we use a simple shell command to find and execute proxmox-backup-manager directly
# 注意：这里用简单的 shell 命令直接查找并执行 proxmox-backup-manager
BUILT_VERSION=$(
    docker run --rm \
        --entrypoint /bin/bash \
        "${IMAGE_NAME}:latest" \
        -c "proxmox-backup-manager version 2>/dev/null || echo 'version-check-failed'" \
        | grep 'client version' \
        | awk '{print $3}' \
        || true
)

# If version check failed, try to get it from package info as fallback
# 如果版本检查失败，尝试从包信息中获取版本作为备选
if [[ -z "$BUILT_VERSION" ]]; then
    log "Warning: Could not get version from proxmox-backup-manager, trying dpkg..."
    BUILT_VERSION=$(
        docker run --rm \
            --entrypoint /bin/bash \
            "${IMAGE_NAME}:latest" \
            -c "dpkg -l | grep proxmox-backup-server | awk '{print \$3}' | head -n1" \
            || true
    )
fi

log "Built version: ${BUILT_VERSION:-unknown}"

# If the built version and remote version differ too much (usually built is older), skip push
# 如果构建出来的版本和远程探测的不一样（通常是构建出来的比探测的旧），则放弃推送
if [[ "$BUILT_VERSION" != *"$REMOTE_VERSION"* && "$REMOTE_VERSION" != *"$BUILT_VERSION"* ]]; then
    # Note: sometimes apt version and binary version have small format differences, so we do a loose check
    # 注意：有时候 apt 版本号和 binary 版本号写法微小差异，这里做一个宽松判断
    # If they differ too much, apt update may not have pulled the latest version
    # 如果差异太大，说明 apt update 可能没拉到最新的
    log "Warning: built version ($BUILT_VERSION) differs from remote version ($REMOTE_VERSION)."
    log "Likely apt cache or mirror sync issue, canceling this push."
    exit 1
fi

log "Version verification passed. Proceeding to push..."

# 6. Tag and push / 打标签并推送
# Use arm64- prefix for version tags, e.g. arm64-4.1.0 / 使用 arm64- 前缀的版本标签，例如：arm64-4.1.0
VERSION_TAG="arm64-${REMOTE_VERSION}"

log "Pushing ${IMAGE_NAME}:${VERSION_TAG} and ${IMAGE_NAME}:arm64-latest ..."

docker tag "${IMAGE_NAME}:latest" "${IMAGE_NAME}:${VERSION_TAG}"
docker tag "${IMAGE_NAME}:latest" "${IMAGE_NAME}:arm64-latest"

if docker push "${IMAGE_NAME}:${VERSION_TAG}" && docker push "${IMAGE_NAME}:arm64-latest"; then
    log "Push succeeded."
    # Update local record to the remote version we detected / 更新本地记录为远程探测到的版本号
    echo "$REMOTE_VERSION" > "$VERSION_FILE"
else
    log "Push failed!"
    exit 1
fi

# 7. Cleanup / 清理
log "Cleaning old images..."
docker rmi "${IMAGE_NAME}:${VERSION_TAG}" || true
docker rmi "${IMAGE_NAME}:arm64-latest" || true
docker image prune -f

log "=== Update job finished ==="