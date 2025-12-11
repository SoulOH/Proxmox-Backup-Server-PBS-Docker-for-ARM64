# Proxmox Backup Server (PBS) Docker for ARM64

This is a Proxmox Backup Server Docker image built specifically for **ARM64** architecture devices (such as Raspberry Pi, Orange Pi, etc.).

## ⚠️ Important Notes & Limitations

*   **Architecture Limit**: This image only supports **ARM64** architecture; x86/amd64 platforms are not supported.
*   **Feature Limit**: Supports core backup and restore functions. Since it runs inside a container, host **Disk Management** features are **not supported**.
*   **Tested Environment**: Currently only tested on **Orange Pi 5 Plus**. Feedback on other devices is welcome.

### 🍓 Special Note for Raspberry Pi 5

For **Raspberry Pi 5** users, if you encounter a `400 Bad Request` error when accessing the service, this is caused by a kernel page size compatibility issue.

**Solution:**
Please add an extra line of configuration to the end of the `/boot/firmware/config.txt` file on the host machine beforehand:

```ini
kernel=kernel8.img
```

After adding this, please **reboot the Raspberry Pi** for the changes to take effect.

---

## 🚀 Quick Deployment

Before use, please ensure you have set the necessary environment variables, especially `ROOT_PASSWORD`.

### Option 1: Docker CLI

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

> **Note**: The `--tmpfs` parameter is crucial for PBS performance and stability; do not remove it.

### Option 2: Docker Compose (Recommended)

Create a `docker-compose.yml` file and add the following content:

```yaml
version: "3.8"

services:
  pbs:
    image: souloh/pbs:arm64-latest
    container_name: pbs
    restart: unless-stopped
    environment:
      # ⚠️ You must change this password
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

Start the container:

```bash
docker-compose up -d
```

---

## ⚙️ Initialization Configuration Guide

After the container starts, follow these steps to complete initialization:

1.  **Access the Web Interface**
    Open your browser and visit: `https://<Your-IP>:8007`
    *(Note: It uses the https protocol. The browser may warn about an insecure certificate; simply choose to proceed.)*

2.  **Login**
    *   **Username**: `root`
    *   **Password**: The password you set in the `ROOT_PASSWORD` environment variable.
    *   **Realm**: Select `Linux PAM standard authentication`.

3.  **Add Datastore**
    After logging in, click **Datastore** -> **Add Datastore** in the left menu:
    *   **Name**: Custom name (e.g., `backup-01`)
    *   **Backing Path**: Must be `/datastore`
        *(This is the path we mounted in Docker)*

After completing the above steps, you can start using PBS for backups.

---

## 🤝 Feedback & Contribution

If you successfully test this on other ARM64 devices, please submit an Issue or feedback to help others.