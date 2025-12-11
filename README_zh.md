# Proxmox Backup Server (PBS) Docker for ARM64

这是一个专为 **ARM64** 架构设备（如树莓派、香橙派等）构建的 Proxmox Backup Server Docker 镜像。

## ⚠️ 注意事项与限制

*   **架构限制**：本镜像仅支持 **ARM64** 架构，不支持 x86/amd64 平台。
*   **功能限制**：支持核心备份与恢复功能。由于运行在容器内，**不支持** 宿主机的磁盘管理（Disk Management）功能。
*   **测试环境**：目前仅在 **Orange Pi 5 Plus** 上测试通过，欢迎反馈其他设备的运行情况。

### 🍓 树莓派 5 特别提示 (Raspberry Pi 5)

对于 **树莓派 5** 用户，如果遇到访问服务时出现 `400 Bad Request` 错误，这是由于内核页大小兼容性问题导致的。

**解决方法：**
请提前在宿主机的 `/boot/firmware/config.txt` 文件末尾额外添加一行配置：

```ini
kernel=kernel8.img
```

添加完成后，请**重启树莓派**以使更改生效。

---

## 🚀 快速部署

在使用前，请确保您已设置必要的环境变量，特别是 `ROOT_PASSWORD`。

### 方式一：Docker CLI

```bash
docker run -d \
  --name pbs \
  --restart unless-stopped \
  -p 8007:8007 \
  -e ROOT_PASSWORD="YourStrongPassword" \
  -e TZ="Asia/Shanghai" \
  -v /dockerData/pbs/lib:/var/lib/proxmox-backup \
  -v /dockerData/pbs/etc:/etc/proxmox-backup \
  -v /dockerData/pbs/datastore:/datastore \
  --tmpfs /run/proxmox-backup/shmem \
  souloh/pbs:arm64-latest
```

> **注意**：`--tmpfs` 参数对于 PBS 的性能和稳定性至关重要，请勿移除。

### 方式二：Docker Compose (推荐)

创建 `docker-compose.yml` 文件并填入以下内容：

```yaml
version: "3.8"

services:
  pbs:
    image: souloh/pbs:arm64-latest
    container_name: pbs
    restart: unless-stopped
    environment:
      # ⚠️ 必须修改此密码
      ROOT_PASSWORD: "YourStrongPassword"
      TZ: "Asia/Shanghai"
    ports:
      - "8007:8007"
    volumes:
      - /dockerData/pbs/lib:/var/lib/proxmox-backup
      - /dockerData/pbs/etc:/etc/proxmox-backup
      - /dockerData/pbs/datastore:/datastore
    tmpfs:
      - /run/proxmox-backup/shmem
```

运行启动：

```bash
docker-compose up -d
```

---

## ⚙️ 初始化配置指南

容器启动后，请按照以下步骤完成初始化：

1.  **访问 Web 界面**
    打开浏览器访问：`https://<你的IP>:8007`
    *(注意是 https 协议，浏览器可能会提示证书不安全，选择继续访问即可)*

2.  **登录系统**
    *   **Username**: `root`
    *   **Password**: 你在环境变量 `ROOT_PASSWORD` 中设置的密码
    *   **Realm**: 选择 `Linux PAM standard authentication`

3.  **添加数据存储 (Datastore)**
    登录成功后，点击左侧菜单的 **Datastore** -> **Add Datastore**：
    *   **Name**: 自定义名称（例如：`backup-01`）
    *   **Backing Path**: 必须填写 `/datastore`
        *(这是我们在 Docker 中挂载的路径)*

完成以上步骤后，即可开始使用 PBS 进行备份。

---

## 🤝 反馈与贡献

如果您在其他 ARM64 设备上测试成功，欢迎提交 Issue 或反馈，帮助更多人使用。